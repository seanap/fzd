#!/usr/bin/env bats
load helpers/installer

@test "installed Explorer modules load from share and uninstall removes only owned helpers" {
  install_fzd --shell none
  assert_installed
  local module
  for module in state operations ui; do cmp "$REPO/lib/$module.bash" "$DATA/lib/$module.bash"; done
  mkdir -p "$HOME/files"
  run bash -euo pipefail -c '
    source "$1/bin/fzd"; FZD_SELF=$1/bin/fzd
    _fzd_paths; _fzd_init; CUR=$HOME/files; _history_init
    _explorer_load state; _explorer_load operations; _explorer_load ui
    _mkdir_item "created through installed helpers"
  ' _ "$PREFIX"
  [ "$status" -eq 0 ]
  [ -d "$HOME/files/created through installed helpers" ]
  install_fzd --verify
  [ "$status" -eq 0 ]
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  for module in state operations ui; do [ ! -e "$DATA/lib/$module.bash" ]; done
  [ -d "$HOME/files/created through installed helpers" ]
}

@test "fresh noninteractive install verifies without root and matches the runtime exactly" {
  install_fzd
  assert_installed
  [ -f "$XDG_CONFIG_HOME/fzd/fzd.conf" ]
  cmp "$REPO/fzd.conf.example" "$XDG_CONFIG_HOME/fzd/fzd.conf"
  cmp "$REPO/lib/global_format.py" "$DATA/lib/global_format.py"
  install_fzd --verify
  [ "$status" -eq 0 ]
  [[ "$output" == *'configuration was not executed'* ]]
}

@test "reinstallation is idempotent and updates retain user configuration and shell contents" {
  printf 'export EDITOR=custom\nexport LS_COLORS=existing\nlf() { :; }\n' >"$HOME/.bashrc"
  cp "$HOME/.bashrc" "$BATS_TEST_TMPDIR/original"
  install_fzd
  assert_installed
  cp "$HOME/.bashrc" "$BATS_TEST_TMPDIR/once"
  printf '# custom settings\nFZD_GLOBAL_BACKEND=live\n' >"$XDG_CONFIG_HOME/fzd/fzd.conf"
  install_fzd
  assert_installed
  cmp "$HOME/.bashrc" "$BATS_TEST_TMPDIR/once"
  grep -q 'custom settings' "$XDG_CONFIG_HOME/fzd/fzd.conf"
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  cmp "$HOME/.bashrc" "$BATS_TEST_TMPDIR/original"
  [ ! -e "$PREFIX/bin/fzd" ]
  [ -f "$XDG_CONFIG_HOME/fzd/fzd.conf" ]
}

@test "installed lifecycle script uninstalls without the checkout and preserves shared files" {
  install_fzd
  assert_installed
  printf unrelated >"$PREFIX/bin/other"
  run bash "$DATA/install.sh" --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$PREFIX/bin/fzd" ]
  [ -f "$PREFIX/bin/other" ]
  [ -d "$DATA/backups" ]
}

@test "custom XDG ZDOTDIR prefix and configuration paths are preserved exactly" {
  export XDG_CONFIG_HOME="$HOME/"$'config space\nλ'
  export ZDOTDIR="$HOME/"$'zsh \'quoted\n'
  PREFIX="$HOME/"$'prefix \'quote\nλ'
  DATA="$PREFIX/share/fzd"
  export FZD_CONF_FILE="$HOME/"$'custom conf\n\n'
  install_fzd --prefix "$PREFIX"
  assert_installed
  [ -f "$FZD_CONF_FILE" ]
  [ -f "$ZDOTDIR/.zshrc" ]
  [ ! -e "$HOME/.zshrc" ]
  run "$REAL_ZSH" -fc 'unset FZD_CONF_FILE; source "$ZDOTDIR/.zshrc"; [[ $_FZD_INSTALL_BIN == "$1/bin/fzd" && $FZD_CONF_FILE == "$2" ]]; command -v fzd_cd' _ "$PREFIX" "$FZD_CONF_FILE"
  [ "$status" -eq 0 ]
  install_fzd --prefix "$PREFIX" --uninstall
  [ "$status" -eq 0 ]
}

@test "existing FZD configuration is checked but never executed or rewritten by install or verify" {
  mkdir -p "$XDG_CONFIG_HOME/fzd"
  printf 'touch "$HOME/config-executed"\ndeclare -A SETTINGS=([key]=value)\n' >"$XDG_CONFIG_HOME/fzd/fzd.conf"
  cp "$XDG_CONFIG_HOME/fzd/fzd.conf" "$BATS_TEST_TMPDIR/original"
  install_fzd
  assert_installed
  install_fzd --verify
  [ "$status" -eq 0 ]
  cmp "$XDG_CONFIG_HOME/fzd/fzd.conf" "$BATS_TEST_TMPDIR/original"
  [ ! -e "$HOME/config-executed" ]
}

@test "invalid configuration and invalid CLI options fail before any installation writes" {
  mkdir -p "$XDG_CONFIG_HOME/fzd"
  printf 'if\n' >"$XDG_CONFIG_HOME/fzd/fzd.conf"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'invalid Bash syntax'* ]]
  [ ! -e "$PREFIX" ]
  install_fzd --shell wrong
  [ "$status" -ne 0 ]
  [ ! -e "$PREFIX" ]
}

@test "missing dependencies and incompatible fzf fail with useful errors before user changes" {
  rm "$TEST_BIN/find"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'Missing prerequisites: find'* ]]
  [ ! -e "$PREFIX" ]
  ln -s /usr/bin/find "$TEST_BIN/find"
  rm "$TEST_BIN/fzf"
  printf '#!/bin/sh\nprintf "0.24.0\\n"\n' >"$TEST_BIN/fzf"
  chmod +x "$TEST_BIN/fzf"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'fzf must be'* ]]
  [ ! -e "$PREFIX" ]
}

@test "available dependencies cause no sudo or package-manager calls" {
  stub_managers
  install_fzd --deps required
  assert_installed
  [ ! -e "$CALLS" ]
}

@test "shell integration preserves existing lf executable editor settings and third-party themes" {
  mkdir -p "$HOME/.config/micro" "$HOME/.config/bat"
  printf original >"$HOME/.config/micro/settings.json"
  printf original >"$HOME/.config/bat/config"
  printf '#!/bin/sh\nprintf existing\n' >"$TEST_BIN/lf"
  chmod +x "$TEST_BIN/lf"
  install_fzd
  assert_installed
  run bash -c 'EDITOR=custom; LS_COLORS=original; source "$HOME/.bashrc"; [[ $(lf) == existing && $EDITOR == custom && $LS_COLORS == original ]]; command -v fzd_cd' _
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.config/micro/settings.json")" = original ]
  [ "$(cat "$HOME/.config/bat/config")" = original ]
}

@test "symbolic shell rc files keep their links mode and unrelated contents" {
  printf '# custom dotfiles\n' >"$HOME/dotfile"
  chmod 600 "$HOME/dotfile"
  ln -s "$HOME/dotfile" "$HOME/.bashrc"
  install_fzd
  assert_installed
  [ -L "$HOME/.bashrc" ]
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ -L "$HOME/.bashrc" ]
  [ "$(cat "$HOME/dotfile")" = '# custom dotfiles' ]
}

@test "malformed shell blocks roll back all application and configuration writes" {
  printf '# user\n# >>> fzd init >>>\nunfinished\n' >"$HOME/.bashrc"
  cp "$HOME/.bashrc" "$BATS_TEST_TMPDIR/original"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'restoring previous files'* ]]
  cmp "$HOME/.bashrc" "$BATS_TEST_TMPDIR/original"
  [ ! -e "$PREFIX/bin/fzd" ]
  [ ! -e "$XDG_CONFIG_HOME/fzd/fzd.conf" ]
}

@test "unmanaged files require explicit adoption and keep recoverable originals" {
  mkdir -p "$PREFIX/bin"
  printf original >"$PREFIX/bin/fzd"
  install_fzd
  [ "$status" -ne 0 ]
  [ "$(cat "$PREFIX/bin/fzd")" = original ]
  install_fzd --adopt
  assert_installed
  run find "$DATA/backups" -name 'backup-*' -exec grep -l '^original$' '{}' +
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "modified owned files block updates and are preserved on uninstall" {
  install_fzd
  assert_installed
  printf '\n# user edit\n' >>"$PREFIX/bin/fzd"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'Locally modified file'* ]]
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ -f "$PREFIX/bin/fzd" ]
  grep -q 'user edit' "$PREFIX/bin/fzd"
}

@test "legacy configuration migrates by copying without executing or deleting its source" {
  mkdir -p "$HOME/.fzd"
  printf 'FZD_GLOBAL_BACKEND=live\n# compatible old settings\n' >"$HOME/.fzd/fzd.conf"
  install_fzd
  assert_installed
  cmp "$HOME/.fzd/fzd.conf" "$XDG_CONFIG_HOME/fzd/fzd.conf"
}

@test "manual mode installs no shell integration or user configuration" {
  install_fzd --shell none --no-config
  assert_installed
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$HOME/.zshrc" ]
  [ ! -e "$XDG_CONFIG_HOME/fzd/fzd.conf" ]
}

@test "package staging separates distribution files from all user lifecycle state" {
  install_fzd --stage "$BATS_TEST_TMPDIR/package" --prefix /usr
  [ "$status" -eq 0 ]
  [ -x "$BATS_TEST_TMPDIR/package/usr/bin/fzd" ]
  [ -f "$BATS_TEST_TMPDIR/package/usr/share/fzd/integration.sh" ]
  [ -f "$BATS_TEST_TMPDIR/package/usr/share/licenses/fzd/LICENSE.txt" ]
  [ ! -e "$BATS_TEST_TMPDIR/package/usr/share/fzd/install.manifest" ]
  [ ! -e "$HOME/.bashrc" ]
  [ ! -e "$PREFIX" ]
}

@test "download failures and checksum mismatch never publish fzf or application files" {
  rm "$TEST_BIN/curl"
  printf '#!/bin/sh\nexit 22\n' >"$TEST_BIN/curl"
  chmod +x "$TEST_BIN/curl"
  local digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  install_fzd --fzf-version 0.65.2 --fzf-sha256 "$digest"
  [ "$status" -ne 0 ]
  [[ "$output" == *'fzf download failed'* ]]
  [ ! -e "$PREFIX/bin/fzd" ]
  printf '#!/bin/bash\nwhile (($#)); do if [[ $1 == --output ]]; then printf invalid >"$2"; exit; fi; shift; done\n' >"$TEST_BIN/curl"
  install_fzd --fzf-version 0.65.2 --fzf-sha256 "$digest"
  [ "$status" -ne 0 ]
  [[ "$output" == *'SHA256 mismatch'* ]]
  [ ! -e "$PREFIX/bin/fzf" ]
}

@test "unverified downloads and relative install paths are rejected before transactions" {
  install_fzd --fzf-version 0.65.2
  [ "$status" -ne 0 ]
  [ ! -e "$PREFIX" ]
  install_fzd --prefix relative
  [ "$status" -ne 0 ]
  [ ! -e "$PREFIX" ]
  install_fzd --prefix "$HOME/colon:prefix"
  [ "$status" -ne 0 ]
  [[ "$output" == *'PATH uses it as a separator'* ]]
  [ ! -e "$HOME/colon:prefix" ]
  install_fzd --prefix /.
  [ "$status" -ne 0 ]
  [[ "$output" == *'Resolved installation prefix'* ]]
  ln -s "$HOME/colon:prefix" "$HOME/prefix-alias"
  install_fzd --prefix "$HOME/prefix-alias"
  [ "$status" -ne 0 ]
  [[ "$output" == *'Resolved installation prefix'* ]]
  rm "$TEST_BIN/readlink"
  printf '#!/bin/sh\nexit 42\n' >"$TEST_BIN/readlink"
  chmod +x "$TEST_BIN/readlink"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'Could not resolve installation prefix'* ]]
  [ ! -e "$PREFIX" ]
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/readlink"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'Resolved installation prefix cannot be empty'* ]]
  [ ! -e "$PREFIX" ]
}

@test "failed file publication and SIGTERM restore prior shell and application files" {
  printf '# original Bash\n' >"$HOME/.bashrc"
  printf '# original zsh\n' >"$HOME/.zshrc"
  cp "$HOME/.bashrc" "$HOME/original-bash"
  cp "$HOME/.zshrc" "$HOME/original-zsh"
  inject_fault fail
  install_fzd
  [ "$status" -eq 73 ]
  cmp "$HOME/.bashrc" "$HOME/original-bash"
  cmp "$HOME/.zshrc" "$HOME/original-zsh"
  [ ! -e "$PREFIX/bin/fzd" ]
  rm "$FZD_FAULT_MARKER"
  export FZD_FAULT=term
  install_fzd
  [ "$status" -eq 143 ]
  cmp "$HOME/.bashrc" "$HOME/original-bash"
  [ ! -e "$PREFIX/bin/fzd" ]
  [ ! -e "$DATA/.install-lock" ]
}

@test "SIGKILL leaves an explicit recoverable transaction and blocks concurrent installs" {
  printf '# original\n' >"$HOME/.bashrc"
  cp "$HOME/.bashrc" "$HOME/original"
  inject_fault kill
  install_fzd
  [ "$status" -eq 137 ]
  [ -d "$DATA/.install-lock" ]
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'Installation locked'* ]]
  install_fzd --recover
  [ "$status" -eq 0 ]
  cmp "$HOME/.bashrc" "$HOME/original"
  [ ! -e "$PREFIX/bin/fzd" ]
  [ ! -e "$DATA/.install-lock" ]
  install_fzd
  assert_installed
}

@test "recovery refuses a live installer owner" {
  mkdir -p "$DATA/.install-lock"
  printf '%s\n' "$$" >"$DATA/.install-lock/pid"
  install_fzd --recover
  [ "$status" -ne 0 ]
  [[ "$output" == *'still running'* ]]
}

@test "installed Bash and zsh wrappers transport a real FZD selection ending with newlines" {
  install_fzd
  assert_installed
  export FZD_STUB_ACTION=ENTER
  local target="$HOME/"$'actual λ\tquote\x27\n\n'
  mkdir -p "$target"
  export FZD_STUB_SELECTION="$target"
  rm "$TEST_BIN/fzf"
  ln -s "$REPO/tests/helpers/fzf-stub" "$TEST_BIN/fzf"
  run bash -ec 'source "$HOME/.bashrc"; lf; [[ $PWD == "$1" ]]' _ "$target"
  [ "$status" -eq 0 ]
  run "$REAL_ZSH" -efc 'source "$HOME/.zshrc"; lf; [[ $PWD == "$1" ]]' _ "$target"
  [ "$status" -eq 0 ]
}

@test "real pinned upstream fzf archive installs verifies and remains owned across updates" {
  local archive="$REPO/.test-work/phase-three/fzf-0.65.2-linux_amd64.tar.gz"
  [[ -f $archive && $(uname -m) == x86_64 ]] || skip 'optional verified upstream archive is not prepared; see tests/README.md'
  export FZD_TEST_ARCHIVE="$archive"
  rm "$TEST_BIN/curl"
  cat >"$TEST_BIN/curl" <<'STUB'
#!/bin/bash
while (($#)); do
  if [[ $1 == --output ]]; then cp "$FZD_TEST_ARCHIVE" "$2"; exit; fi
  shift
done
exit 1
STUB
  chmod +x "$TEST_BIN/curl"
  install_fzd --fzf-version 0.65.2 --fzf-sha256 5eb8efc0e94aa559f84ea83eeba99bea7dce818e63f92b4b62e60663220f1c14
  assert_installed
  run "$PREFIX/bin/fzf" --version
  [ "$status" -eq 0 ]
  [[ "$output" == 0.65.2* ]]
  install_fzd
  assert_installed
  install_fzd --verify
  [ "$status" -eq 0 ]
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ -x "$PREFIX/bin/fzf" ]
  [ -x "$REAL_FZF" ]
}

@test "installer upgrades an owned runtime from a changed source checkout" {
  install_fzd
  assert_installed
  local source="$BATS_TEST_TMPDIR/source"
  mkdir -p "$source/installer" "$source/shell" "$source/lib"
  cp "$REPO/lib/"*.bash "$REPO/lib/"*.py "$source/lib/"
  cp "$REPO/install.sh" "$REPO/fzd.sh" "$REPO/fzd.conf.example" "$REPO/LICENSE.txt" "$source/"
  cp "$REPO/installer/"*.bash "$source/installer/"
  cp "$REPO/shell/"* "$source/shell/"
  printf '\n# fixture update\n' >>"$source/fzd.sh"
  run bash "$source/install.sh" --noninteractive --deps none
  [ "$status" -eq 0 ]
  cmp "$source/fzd.sh" "$PREFIX/bin/fzd"
  cmp "$source/lib/global_format.py" "$DATA/lib/global_format.py"
  install_fzd --verify
  [ "$status" -eq 0 ]
}

@test "uninstall preserves shell edits added after installation and foreign replacement blocks" {
  install_fzd
  assert_installed
  printf '# later user addition\n' >>"$HOME/.bashrc"
  printf '# >>> fzd init >>>\n. /another/prefix/integration.sh\n# <<< fzd init <<<\n' >"$HOME/.zshrc"
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.bashrc")" = '# later user addition' ]
  grep -q /another/prefix "$HOME/.zshrc"
}

@test "unterminated shell files survive repeated installation and uninstall byte-for-byte" {
  printf '# user line without final newline' >"$HOME/.bashrc"
  cp "$HOME/.bashrc" "$HOME/original"
  install_fzd
  assert_installed
  cp "$HOME/.bashrc" "$HOME/once"
  install_fzd
  assert_installed
  cmp "$HOME/.bashrc" "$HOME/once"
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  cmp "$HOME/.bashrc" "$HOME/original"
}

@test "application destination symlinks and malformed manifests are never followed" {
  printf unrelated >"$HOME/unrelated"
  mkdir -p "$PREFIX/bin"
  ln -s "$HOME/unrelated" "$PREFIX/bin/fzd"
  install_fzd --adopt
  [ "$status" -ne 0 ]
  [ -L "$PREFIX/bin/fzd" ]
  [ "$(cat "$HOME/unrelated")" = unrelated ]
  rm "$PREFIX/bin/fzd"
  install_fzd
  assert_installed
  printf 'file\0%s\0%s\0' "$HOME/unrelated" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa >"$DATA/install.manifest"
  install_fzd --uninstall
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/unrelated")" = unrelated ]
  [ -e "$PREFIX/bin/fzd" ]
}

@test "canonical prefix paths keep installed lifecycle ownership consistent" {
  local alias_prefix="$HOME/.local/."
  install_fzd --prefix "$alias_prefix"
  assert_installed
  run bash "$DATA/install.sh" --verify
  [ "$status" -eq 0 ]
  run bash "$DATA/install.sh" --uninstall
  [ "$status" -eq 0 ]
}

@test "recovery clears a stale lock after a completed transaction was archived" {
  install_fzd
  assert_installed
  local archive
  for archive in "$DATA/backups/".transaction.*; do break; done
  mkdir "$DATA/.install-lock"
  printf '999999999\n' >"$DATA/.install-lock/pid"
  printf '%s\0' "$DATA/${archive##*/}" >"$DATA/.install-lock/transaction"
  install_fzd --recover
  [ "$status" -eq 0 ]
  [ ! -e "$DATA/.install-lock" ]
  [ -x "$PREFIX/bin/fzd" ]
}

@test "rc targets outside HOME also roll back safely through retained dotfile symlinks" {
  printf '# original outside HOME\n' >"$BATS_TEST_TMPDIR/external-rc"
  ln -s "$BATS_TEST_TMPDIR/external-rc" "$HOME/.bashrc"
  inject_fault fail
  install_fzd
  [ "$status" -eq 73 ]
  [ -L "$HOME/.bashrc" ]
  [ "$(cat "$BATS_TEST_TMPDIR/external-rc")" = '# original outside HOME' ]
  [ ! -e "$DATA/.install-lock" ]
}

@test "installed Bash and zsh launchers change parent directory through a real fzf terminal" {
  [[ -n $REAL_TMUX && -n $REAL_ZSH ]] || skip 'real installed-wrapper PTY check needs tmux and zsh'
  install_fzd
  assert_installed
  local target="$HOME/"$'chosen-pty λ\tquote\x27\n\n' shell command screen attempt actual
  mkdir -p "$target"
  for shell in "$REAL_BASH" "$REAL_ZSH"; do
    INSTALL_SOCKET="$BATS_TEST_TMPDIR/installed-${shell##*/}.sock"
    export INSTALL_PTY_RESULT="$BATS_TEST_TMPDIR/result-${shell##*/}"
    printf 'source %q\n' "$HOME/.${shell##*/}rc" >"$HOME/session"
    printf '%s\n' 'lf' 'printf "%s\0" "$PWD" >"$INSTALL_PTY_RESULT"' 'exec sleep 60' >>"$HOME/session"
    printf -v command 'exec %q %q' "$shell" "$HOME/session"
    "$REAL_TMUX" -S "$INSTALL_SOCKET" -f /dev/null new-session -d -x 120 -y 32 -s install -c "$HOME" "$command"
    for ((attempt = 0; attempt < 100; attempt++)); do
      screen=$("$REAL_TMUX" -S "$INSTALL_SOCKET" capture-pane -p -t install:0.0)
      [[ $screen != *chosen-pty* ]] || break
      sleep 0.05
    done
    [[ $screen == *chosen-pty* ]]
    "$REAL_TMUX" -S "$INSTALL_SOCKET" send-keys -t install:0.0 -l chosen-pty
    sleep 0.1
    "$REAL_TMUX" -S "$INSTALL_SOCKET" send-keys -t install:0.0 Enter
    for ((attempt = 0; attempt < 100; attempt++)); do
      [[ ! -s $INSTALL_PTY_RESULT ]] || break
      sleep 0.05
    done
    IFS= read -r -d '' actual <"$INSTALL_PTY_RESULT"
    [ "$actual" = "$target" ]
    "$REAL_TMUX" -S "$INSTALL_SOCKET" kill-server
    INSTALL_SOCKET=''
  done
}

@test "failed uninstall restores deleted files without replacing an unrelated temporary-looking file" {
  install_fzd
  assert_installed
  printf unrelated >"$PREFIX/bin/fzd.fzd-uninstall"
  FZD_REAL_CP=$(readlink -f "$TEST_BIN/cp")
  export FZD_REAL_CP FZD_FAIL_SOURCE="$DATA/integration.sh"
  rm "$TEST_BIN/cp"
  cat >"$TEST_BIN/cp" <<'STUB'
#!/bin/bash
for arg; do [[ $arg != "$FZD_FAIL_SOURCE" ]] || exit 73; done
exec "$FZD_REAL_CP" "$@"
STUB
  chmod +x "$TEST_BIN/cp"
  install_fzd --uninstall
  [ "$status" -eq 73 ]
  [ "$(cat "$PREFIX/bin/fzd.fzd-uninstall")" = unrelated ]
  cmp "$REPO/fzd.sh" "$PREFIX/bin/fzd"
  install_fzd --verify
  [ "$status" -eq 0 ]
}
