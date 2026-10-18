#!/usr/bin/env bats
load helpers/installer

provide_recommended() {
  local tool
  for tool in eza fd bat; do
    printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/$tool"
    chmod +x "$TEST_BIN/$tool"
  done
}

provide_engines() {
  mkdir -p "$XDG_DATA_HOME/blesh" "$HOME/.zsh/zsh-autosuggestions"
  printf 'touch "$HOME/engine-executed"\n' >"$XDG_DATA_HOME/blesh/ble.sh"
  printf 'touch "$HOME/engine-executed"\n' >"$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
}

native_fonts() {
  rm "$TEST_BIN/uname"
  printf '#!/bin/sh\ncase "$1" in -s) echo Linux ;; -r) echo native-linux ;; *) echo x86_64 ;; esac\n' >"$TEST_BIN/uname"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$CALLS.font-probe"\nprintf "%%s" "${FZD_TEST_FAMILIES:-}"\n' >"$TEST_BIN/fc-list"
  printf '#!/bin/sh\necho "JetBrainsMono Nerd Font Mono"\n' >"$TEST_BIN/fc-scan"
  printf '#!/bin/sh\nprintf "cache\\n" >>"$CALLS"\n' >"$TEST_BIN/fc-cache"
  chmod +x "$TEST_BIN/uname" "$TEST_BIN/fc-list" "$TEST_BIN/fc-scan" "$TEST_BIN/fc-cache"
}

@test "plain Simple install uses present recommended tools and only minimal startup entries" {
  provide_recommended
  stub_managers
  printf 'alias eza="eza --long"\nexport LS_COLORS=custom\n' >"$HOME/.bashrc"
  run bash "$REPO/install.sh"
  assert_installed
  [ ! -e "$CALLS" ]
  [ ! -e "$XDG_DATA_HOME/fonts" ]
  [ ! -e "$PREFIX/share/blesh" ]
  [ ! -e "$HOME/.fzd" ]
  [ "$(wc -l <"$HOME/.bashrc")" -eq 5 ]
  grep -q '^alias eza=' "$HOME/.bashrc"
  ! grep -q FZD_INLINE "$XDG_CONFIG_HOME/fzd/shell.bash"
  grep -q shell.bash "$HOME/.bashrc"
  grep -q shell.zsh "$HOME/.zshrc"
  run bash -ec '. "$HOME/.bashrc"; declare -F lf; complete -p lf'
  [ "$status" -eq 0 ]
}

@test "Simple installs missing eza through the native package manager without replacing aliases" {
  provide_recommended
  rm "$TEST_BIN/eza"
  stub_managers
  local tool
  for tool in apt-get dnf pacman; do
    sed -i '/^exit /d' "$TEST_BIN/$tool"
    cat >>"$TEST_BIN/$tool" <<'STUB'
for arg; do
  if [[ $arg == eza ]]; then
    printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/eza"
    chmod +x "$TEST_BIN/eza"
  fi
done
STUB
  done
  printf 'alias ls="eza --icons=never"\n' >"$HOME/.bashrc"
  run bash "$REPO/install.sh"
  assert_installed
  [ -x "$TEST_BIN/eza" ]
  grep -q '<eza>' "$CALLS"
  ! grep -q '<zsh-autosuggestions>\|updatedb\|font' "$CALLS"
  if ((EUID != 0)); then grep -q 'sudo <-n> <-v>' "$CALLS"; fi
  grep -q '^alias ls="eza --icons=never"$' "$HOME/.bashrc"
}

@test "unavailable recommended packages leave a usable core installation and fallback guidance" {
  provide_recommended
  rm "$TEST_BIN/eza"
  stub_managers
  export PM_STATUS=42
  run bash "$REPO/install.sh"
  assert_installed
  [[ "$output" == *'Optional eza unavailable'* ]]
  [ ! -e "$TEST_BIN/eza" ]
  install_fzd --verify
  [ "$status" -eq 0 ]
}

@test "default required package installation fails without prompting when sudo is unauthorized" {
  ((EUID != 0)) || skip 'sudo authorization check requires an unprivileged user'
  provide_recommended
  stub_managers
  rm "$TEST_BIN/zoxide"
  export SUDO_STATUS=1
  run bash "$REPO/install.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *'sudo authentication is required'* ]]
  grep -q 'sudo <-n> <-v>' "$CALLS"
  ! grep -q '^apt-get\|^dnf\|^pacman' "$CALLS"
  [ ! -e "$PREFIX/bin/fzd" ]
}

@test "clean Enhanced reuses existing engines and a compatible native font without executing custom code" {
  provide_recommended
  provide_engines
  native_fonts
  export FZD_TEST_FAMILIES='JetBrainsMono Nerd Font Mono'
  run bash "$REPO/install.sh" --enhanced
  assert_installed
  [[ "$output" == *'Compatible font coverage found'* ]]
  [ ! -e "$CALLS" ]
  [ ! -e "$HOME/engine-executed" ]
  [ ! -e "$XDG_DATA_HOME/fonts" ]
  grep -q 'FZD_INLINE_SUGGESTIONS:=1' "$XDG_CONFIG_HOME/fzd/shell.bash"
  grep -q 'then FZD_ZSH_AUTOSUGGESTIONS_PATH=' "$XDG_CONFIG_HOME/fzd/shell.zsh"
  cp "$XDG_CONFIG_HOME/fzd/shell.bash" "$HOME/once"
  run bash "$REPO/install.sh"
  assert_installed
  cmp "$HOME/once" "$XDG_CONFIG_HOME/fzd/shell.bash"
  [ ! -e "$CALLS" ]
}

@test "font detection recognizes Nerd families and verified alternative glyph coverage" {
  native_fonts
  local family
  for family in 'JetBrainsMono Nerd Font' 'CaskaydiaCove Nerd Font' 'Cascadia Code Nerd Font' 'FiraCode Nerd Font' 'Hack Nerd Font' 'MesloLGS Nerd Font' 'Symbols Nerd Font Mono' 'Custom Verified Glyph Font'; do
    export FZD_TEST_FAMILIES=$family
    run bash -ec 'source "$1/installer/dependencies.bash"; source "$1/installer/fonts.bash"; log() { echo "$*"; }; _font_find_compatible' _ "$REPO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"$family"* ]]
  done
  grep -q ':charset=f115 f15b e5ff f024b family' "$CALLS.font-probe"
}

@test "WSL Enhanced reports Windows font setup and never attempts Linux font installation" {
  provide_engines
  export WSL_DISTRO_NAME=FZD-Test
  install_fzd --enhanced
  assert_installed
  [[ "$output" == *'install a Nerd Font on Windows'* ]]
  [[ "$output" == *'Linux fonts do not configure the Windows host terminal'* ]]
  [ ! -e "$CALLS" ]
  [ ! -e "$XDG_DATA_HOME/fonts" ]
}

@test "WSL kernel detection works without WSL environment variables" {
  rm "$TEST_BIN/uname"
  printf '#!/bin/sh\necho 6.6-microsoft-standard-WSL2\n' >"$TEST_BIN/uname"
  chmod +x "$TEST_BIN/uname"
  run bash -ec 'source "$1/installer/fonts.bash"; _font_is_wsl' _ "$REPO"
  [ "$status" -eq 0 ]
}

@test "optional native font download failure keeps the core installation verified and cleans private downloads" {
  provide_engines
  native_fonts
  rm "$TEST_BIN/curl"
  printf '#!/bin/sh\nexit 22\n' >"$TEST_BIN/curl"
  chmod +x "$TEST_BIN/curl"
  install_fzd --enhanced
  assert_installed
  [[ "$output" == *'Optional font setup did not complete'* ]]
  [ ! -e "$XDG_DATA_HOME/fonts" ]
  run find "$DATA" -name 'font.*'
  [ -z "$output" ]
  install_fzd --verify
  [ "$status" -eq 0 ]
}

@test "font checksum mismatch discards download without overwriting fonts or rolling back FZD" {
  provide_engines
  native_fonts
  rm "$TEST_BIN/curl"
  cat >"$TEST_BIN/curl" <<'STUB'
#!/bin/bash
while (($#)); do if [[ $1 == --output ]]; then echo untrusted >"$2"; exit; fi; shift; done
STUB
  chmod +x "$TEST_BIN/curl"
  install_fzd --enhanced
  assert_installed
  [[ "$output" == *'Nerd Font SHA256 mismatch'* ]]
  [ ! -e "$XDG_DATA_HOME/fonts" ]
  [ ! -e "$DATA/.install-lock" ]
}

@test "font publication uses XDG data user scope and never clobbers a concurrent or existing destination" {
  native_fonts
  mkdir "$HOME/tx" "$HOME/font-source"
  printf fixture-font >"$HOME/font-source/JetBrainsMonoNerdFontMono-Regular.ttf"
  tar -cJf "$HOME/font.tar.xz" -C "$HOME/font-source" JetBrainsMonoNerdFontMono-Regular.ttf
  # Isolate verification's success branch with a known fixture; the mismatch
  # test above uses the real digest. No unverified font is used by the test host.
  run bash -ec '
    source "$1/installer/dependencies.bash"; source "$1/installer/fonts.bash"
    log() { echo "$*"; }; warn() { echo "$*" >&2; }
    TX=$HOME/tx; XDG_DATA_HOME=$HOME/data
    curl() { while (($#)); do if [[ $1 == --output ]]; then cp "$HOME/font.tar.xz" "$2"; return; fi; shift; done; }
    sha256sum() { cat >/dev/null; echo ef552a3e638f25125c6ad4c51176a6adcdce295ab1d2ffacf0db060caf8c1582; }
    _font_install
    _font_install
  ' _ "$REPO"
  [ "$status" -eq 0 ]
  local installed="$XDG_DATA_HOME/fonts/fzd-nerd-fonts-3.4.0/JetBrainsMonoNerdFontMono-Regular.ttf"
  cmp "$HOME/font-source/JetBrainsMonoNerdFontMono-Regular.ttf" "$installed"
  [ "$(grep -c '^cache$' "$CALLS")" -eq 1 ]
  run find "$HOME/tx" -mindepth 1
  [ -z "$output" ]
  install_fzd
  assert_installed
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ -f "$installed" ]
}

@test "existing font destinations including symlinks are preserved" {
  provide_engines
  native_fonts
  mkdir -p "$XDG_DATA_HOME/fonts" "$HOME/third-party-fonts"
  printf original >"$HOME/third-party-fonts/font.ttf"
  ln -s "$HOME/third-party-fonts" "$XDG_DATA_HOME/fonts/fzd-nerd-fonts-3.4.0"
  install_fzd --enhanced
  assert_installed
  [[ "$output" == *'Existing font directory preserved'* ]]
  [ "$(cat "$HOME/third-party-fonts/font.ttf")" = original ]
}

@test "custom startup paths and ZDOTDIR preserve aliases hooks and shell preferences" {
  provide_engines
  export WSL_DISTRO_NAME=Test
  export ZDOTDIR="$HOME/zsh-dir"
  mkdir -p "$ZDOTDIR"
  printf 'FZD_INLINE_SUGGESTIONS=0\nPROMPT_COMMAND=custom_hook\nalias lf=custom\n' >"$HOME/custom-bash"
  printf 'typeset -a chpwd_functions=(custom_hook)\n' >"$HOME/custom-zsh"
  install_fzd --enhanced --bashrc "$HOME/custom-bash" --zshrc "$HOME/custom-zsh"
  assert_installed
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$ZDOTDIR/.zshrc" ]
  run bash -ec '. "$HOME/custom-bash"; [[ $FZD_INLINE_SUGGESTIONS == 0 && $PROMPT_COMMAND == custom_hook ]]'
  [ "$status" -eq 0 ]
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  grep -q '^alias lf=custom$' "$HOME/custom-bash"
  ! grep -q 'fzd init' "$HOME/custom-bash"
}

@test "edited shell configuration stays user-owned through update explicit preference changes and uninstall" {
  provide_engines
  export WSL_DISTRO_NAME=Test
  install_fzd
  assert_installed
  printf '\nFZD_INLINE_SUGGESTIONS=0\ntouch "$HOME/never-execute"\n' >>"$XDG_CONFIG_HOME/fzd/shell.bash"
  cp "$XDG_CONFIG_HOME/fzd/shell.bash" "$HOME/custom-shell"
  install_fzd --enhanced
  assert_installed
  [[ "$output" == *'Preserving user-edited shell configuration'* ]]
  cmp "$HOME/custom-shell" "$XDG_CONFIG_HOME/fzd/shell.bash"
  install_fzd --no-inline-suggestions
  assert_installed
  cmp "$HOME/custom-shell" "$XDG_CONFIG_HOME/fzd/shell.bash"
  install_fzd --verify
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/never-execute" ]
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  cmp "$HOME/custom-shell" "$XDG_CONFIG_HOME/fzd/shell.bash"
  ! grep -q 'fzd init' "$HOME/.bashrc"
}

@test "preexisting user shell files are neither executed nor claimed for removal" {
  mkdir -p "$XDG_CONFIG_HOME/fzd"
  printf 'touch "$HOME/never-execute"\n' >"$XDG_CONFIG_HOME/fzd/shell.bash"
  install_fzd
  assert_installed
  install_fzd --verify
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/never-execute" ]
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ -f "$XDG_CONFIG_HOME/fzd/shell.bash" ]
  ! grep -q 'fzd init' "$HOME/.bashrc"
}

@test "v2 managed blocks migrate once retaining inline settings without evaluating them" {
  local legacy="$BATS_TEST_TMPDIR/v2"
  mkdir "$legacy"
  # Immutable v2 fixture exercises the actual old ownership manifest and blocks.
  tar -xzf "$REPO/tests/fixtures/installer-v2.tar.gz" -C "$legacy"
  provide_engines
  export FZD_BLESH_PATH="$XDG_DATA_HOME/blesh/ble.sh"
  export FZD_ZSH_AUTOSUGGESTIONS_PATH="$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
  run bash "$legacy/install.sh" --deps none --inline-suggestions
  [ "$status" -eq 0 ]
  grep -q '^FZD_INLINE_SUGGESTIONS=1$' "$HOME/.bashrc"
  install_fzd
  assert_installed
  [ "$(grep -c '>>> fzd init' "$HOME/.bashrc")" -eq 1 ]
  [ "$(wc -l <"$HOME/.bashrc")" -eq 3 ]
  grep -q '^FZD_INLINE_SUGGESTIONS=1$' "$XDG_CONFIG_HOME/fzd/shell.bash"
  [ ! -e "$HOME/engine-executed" ]
  cp "$HOME/.bashrc" "$HOME/once"
  install_fzd
  assert_installed
  cmp "$HOME/once" "$HOME/.bashrc"
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ ! -s "$HOME/.bashrc" ]
}

@test "unsafe installer overrides fail before writes while relative XDG homes use defaults" {
  local variable
  for variable in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME; do
    run env "$variable=$HOME/../escape" bash "$REPO/install.sh" --deps none
    [ "$status" -ne 0 ]
    [ ! -e "$PREFIX/bin/fzd" ]
  done
  for variable in FZD_BASH_RC FZD_ZSH_RC ZDOTDIR FZD_CONF_FILE; do
    run env "$variable=relative" bash "$REPO/install.sh" --deps none
    [ "$status" -ne 0 ]
    [ ! -e "$PREFIX/bin/fzd" ]
  done
  run env XDG_CONFIG_HOME=relative XDG_DATA_HOME=relative XDG_STATE_HOME=relative XDG_CACHE_HOME=relative bash "$REPO/install.sh" --deps none
  assert_installed
  [ -f "$HOME/.config/fzd/shell.bash" ]
  [ ! -e "$HOME/relative" ]
}

@test "Enhanced package staging is forbidden and Simple staging never creates home files" {
  install_fzd --enhanced --stage "$HOME/stage" --prefix /usr
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/stage" ]
  run bash "$REPO/install.sh" --stage "$HOME/stage" --prefix /usr
  [ "$status" -eq 0 ]
  [ -f "$HOME/stage/usr/share/fzd/integration.sh" ]
  [ ! -e "$XDG_CONFIG_HOME" ]
  [ ! -e "$XDG_DATA_HOME" ]
  [ ! -e "$HOME/.bashrc" ]
}

@test "shell config symlinks and foreign installation blocks never get overwritten" {
  mkdir -p "$XDG_CONFIG_HOME/fzd"
  printf original >"$HOME/original"
  ln -s "$HOME/original" "$XDG_CONFIG_HOME/fzd/shell.bash"
  install_fzd
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/original")" = original ]
  [ ! -e "$PREFIX/bin/fzd" ]
  rm "$XDG_CONFIG_HOME/fzd/shell.bash"
  printf '# >>> fzd init >>>\n. /other/install/integration.sh\n# <<< fzd init <<<\n' >"$HOME/.bashrc"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'belongs to another installation'* ]]
  grep -q /other/install "$HOME/.bashrc"
}

@test "custom engine paths are quoted safely for both generated shell files and never evaluated during install" {
  local engine="$HOME/"$'engine \'$(touch NEVER)\n'
  mkdir -p "$engine"
  export FZD_BLESH_PATH="$engine/ble.sh" FZD_ZSH_AUTOSUGGESTIONS_PATH="$engine/autosuggestions.zsh"
  printf '# custom engine\n' >"$FZD_BLESH_PATH"
  printf '# custom plugin\n' >"$FZD_ZSH_AUTOSUGGESTIONS_PATH"
  export WSL_DISTRO_NAME=Test
  install_fzd --enhanced
  assert_installed
  run bash -ec 'unset FZD_BLESH_PATH; . "$HOME/.bashrc"; [[ $FZD_BLESH_PATH == "$1" ]]' _ "$FZD_BLESH_PATH"
  [ "$status" -eq 0 ]
  run "$REAL_ZSH" -efc 'unset FZD_ZSH_AUTOSUGGESTIONS_PATH; . "$HOME/.zshrc"; [[ $FZD_ZSH_AUTOSUGGESTIONS_PATH == "$1" ]]' _ "$FZD_ZSH_AUTOSUGGESTIONS_PATH"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/NEVER" ]
  [ ! -e "$REPO/NEVER" ]
}

@test "changing XDG config locations keeps all owned source entries recoverable on uninstall" {
  install_fzd
  assert_installed
  local old_config=$XDG_CONFIG_HOME
  export XDG_CONFIG_HOME="$HOME/new-config"
  install_fzd
  assert_installed
  grep -q new-config "$HOME/.bashrc"
  [ -f "$old_config/fzd/shell.bash" ]
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$old_config/fzd/shell.bash" ]
  [ ! -e "$XDG_CONFIG_HOME/fzd/shell.bash" ]
  ! grep -q 'fzd init' "$HOME/.bashrc"
}

@test "optional font tooling package failures preserve a verified core install" {
  provide_recommended
  provide_engines
  native_fonts
  rm "$TEST_BIN/fc-list" "$TEST_BIN/fc-scan" "$TEST_BIN/fc-cache"
  stub_managers
  export PM_STATUS=42
  install_fzd --enhanced --deps recommended
  assert_installed
  [[ "$output" == *'Optional font setup did not complete'* ]]
  [ ! -e "$XDG_DATA_HOME/fonts" ]
  install_fzd --verify
  [ "$status" -eq 0 ]
}

@test "font download termination cleans its private archive directory" {
  native_fonts
  mkdir "$HOME/font-tx"
  run bash -ec '
    source "$1/installer/dependencies.bash"; source "$1/installer/fonts.bash"
    warn() { echo "$*" >&2; }; log() { :; }
    TX=$HOME/font-tx; XDG_DATA_HOME=$HOME/data
    curl() { kill -TERM "$BASHPID"; }
    _font_install
  ' _ "$REPO"
  [ "$status" -eq 143 ]
  run find "$HOME/font-tx" -mindepth 1
  [ -z "$output" ]
  [ ! -e "$XDG_DATA_HOME/fonts" ]
}

@test "new XDG configuration directories are private and existing directory modes stay unchanged" {
  install_fzd
  assert_installed
  [ "$(stat -c %a "$XDG_CONFIG_HOME/fzd")" = 700 ]
  chmod 750 "$XDG_CONFIG_HOME/fzd"
  install_fzd
  assert_installed
  [ "$(stat -c %a "$XDG_CONFIG_HOME/fzd")" = 750 ]
}
