#!/usr/bin/env bats
load helpers/installer

enhancement_tools() {
  local tool
  for tool in eza fd bat chafa glow wl-copy; do
    printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/$tool"
    chmod +x "$TEST_BIN/$tool"
  done
  mkdir -p "$XDG_DATA_HOME/blesh" "$HOME/.zsh/zsh-autosuggestions"
  printf ':\n' >"$XDG_DATA_HOME/blesh/ble.sh"
  printf ':\n' >"$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
  export WSL_DISTRO_NAME=Test
}
omarchy_tools() {
  cp "$REPO/tests/fixtures/omarchy/omarchy-tui-install" "$TEST_BIN/omarchy-tui-install"
  cp "$REPO/tests/fixtures/omarchy/omarchy-launch-editor" "$TEST_BIN/omarchy-launch-editor"
  chmod +x "$TEST_BIN/omarchy-tui-install" "$TEST_BIN/omarchy-launch-editor"
  export SHELL=/bin/bash
}

@test "plocate is mandatory while deps none leaves an uninitialized index untouched" {
  export PLOCATE_COUNT=0 PLOCATE_STATUS=1
  install_fzd
  assert_installed
  [[ "$output" == *'index is missing, empty or unreadable'* ]]
  [[ "$output" == *'sudo updatedb'* ]]
  rm "$TEST_BIN/plocate"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'Missing prerequisites: plocate'* ]]
}

stub_indexer() {
  cat >"$TEST_BIN/updatedb" <<'SH'
#!/bin/bash
printf 'updatedb' >>"$CALLS"
for arg; do printf ' <%s>' "$arg" >>"$CALLS"; done
printf '\n' >>"$CALLS"
[[ ${UPDATEDB_STATUS:-0} == 0 ]] || exit "$UPDATEDB_STATUS"
touch "$HOME/index-ready"
SH
  chmod +x "$TEST_BIN/updatedb"
  cat >"$TEST_BIN/plocate" <<'SH'
#!/bin/bash
[[ $1 != --version ]] || { echo 'plocate 1.1.19'; exit; }
[[ -f $HOME/index-ready ]] || exit 1
echo 1
SH
  chmod +x "$TEST_BIN/plocate"
}

@test "Simple and Enhanced install missing plocate and initialize its index without an extra flag" {
  enhancement_tools
  stub_indexer
  cp "$TEST_BIN/plocate" "$HOME/plocate-fixture"
  stub_managers
  local manager
  for manager in apt-get pacman dnf; do
    sed -i '/^exit /d' "$TEST_BIN/$manager"
    cat >>"$TEST_BIN/$manager" <<'SH'
for arg; do
  if [[ $arg == plocate ]]; then
    cp "$HOME/plocate-fixture" "$TEST_BIN/plocate"
    chmod +x "$TEST_BIN/plocate"
  fi
done
SH
  done
  local mode
  for mode in simple enhanced; do
    rm -f "$TEST_BIN/plocate" "$HOME/index-ready" "$CALLS"
    if [[ $mode == simple ]]; then
      run bash "$REPO/install.sh"
    else
      run bash "$REPO/install.sh" --enhanced
    fi
    assert_installed
    grep -q '<plocate>' "$CALLS"
    [ "$(grep -c '^updatedb$' "$CALLS")" -eq 1 ]
    [[ "$output" != *'index is missing, empty or unreadable'* ]]
  done
}

@test "index initialization uses distro defaults and reuses a ready index on subsequent installs" {
  stub_managers
  stub_indexer
  install_fzd --deps required
  assert_installed
  install_fzd --deps required
  assert_installed
  [ "$(grep -c '^updatedb$' "$CALLS")" -eq 1 ]
  # No arguments override distro exclusions; no policy or service tools run.
  ! grep -q 'systemctl\|PRUNEPATHS\|PRUNEFS\|--output\|--database' "$CALLS"
}

@test "missing updatedb warns and the plocate-specific executable can initialize the index" {
  stub_managers
  stub_indexer
  mv "$TEST_BIN/updatedb" "$HOME/updatedb-fixture"
  install_fzd --deps required
  assert_installed
  [[ "$output" == *'updatedb is unavailable'* ]]
  [ ! -e "$CALLS" ]
  mv "$HOME/updatedb-fixture" "$TEST_BIN/updatedb.plocate"
  install_fzd --deps required
  assert_installed
  [ "$(grep -c '^updatedb$' "$CALLS")" -eq 1 ]
}

@test "no-updatedb deps none and custom databases skip initialization" {
  stub_managers
  stub_indexer
  install_fzd --deps required --no-updatedb
  assert_installed
  [ ! -e "$CALLS" ]
  install_fzd
  assert_installed
  [ ! -e "$CALLS" ]
  export FZD_LOCATE_DBS="$HOME/custom.db"
  install_fzd --deps required
  assert_installed
  [ ! -e "$CALLS" ]
  [[ "$output" == *'index is missing, empty or unreadable'* ]]
}

@test "failed index initialization preserves a usable install and reports the fallback" {
  stub_managers
  stub_indexer
  export UPDATEDB_STATUS=42
  install_fzd --deps required
  assert_installed
  [[ "$output" == *'Index initialization failed'* ]]
  [[ "$output" == *'filesystem fallback'* ]]
  [ "$(grep -c '^updatedb$' "$CALLS")" -eq 1 ]
}

@test "index initialization without sudo authorization continues without running updatedb" {
  ((EUID != 0)) || skip 'sudo authorization check requires an unprivileged user'
  stub_managers
  stub_indexer
  export SUDO_STATUS=1
  install_fzd --deps required
  assert_installed
  [[ "$output" == *'without sudo authorization'* ]]
  ! grep -q '^updatedb' "$CALLS"
}

@test "legacy package indexing flag remains accepted without being required" {
  install_fzd --allow-package-indexing
  assert_installed
}

@test "Enhanced reuses rich preview clipboard and editor tools and never installs Lazygit" {
  enhancement_tools
  stub_managers
  omarchy_tools
  export WAYLAND_DISPLAY=wayland-1 EDITOR='omarchy-launch-editor --inline'
  rm "$TEST_BIN/micro"
  install_fzd --enhanced
  assert_installed
  [ ! -e "$CALLS" ]
  [ ! -e "$XDG_DATA_HOME/applications/FZD.desktop" ]
  install_fzd
  assert_installed
  grep -q 'FZD_INLINE_SUGGESTIONS:=1' "$XDG_CONFIG_HOME/fzd/shell.bash"
}

@test "Enhanced dependency collection selects display provider and excludes headless clipboard and Lazygit" {
  run bash -euc 'source "$1/installer/dependencies.bash"; ENHANCED=1; unset WAYLAND_DISPLAY DISPLAY; collect_recommended; [[ " ${MISSING[*]} " == *" chafa "* && " ${MISSING[*]} " == *" glow "* && " ${MISSING[*]} " != *" xclip "* && " ${MISSING[*]} " != *lazygit* ]]; WAYLAND_DISPLAY=wayland-1; collect_recommended; [[ " ${MISSING[*]} " == *" wl-copy "* ]]; unset WAYLAND_DISPLAY; DISPLAY=:0; collect_recommended; [[ " ${MISSING[*]} " == *" xclip "* ]]; for PM in apt pacman dnf; do package_for wl-copy; [[ $REPLY == wl-clipboard ]]; done' _ "$REPO"
  [ "$status" -eq 0 ]
}

@test "Omarchy launcher uses upstream helper and interactive shell with idempotent ownership" {
  enhancement_tools
  omarchy_tools
  install_fzd --enhanced --omarchy-launcher float
  assert_installed
  local desktop="$XDG_DATA_HOME/applications/FZD.desktop"
  grep -q 'app-id=TUI.float' "$desktop"
  grep -q 'launcher.bash' "$desktop"
  grep -q -- '-i' "$desktop"
  install_fzd --enhanced --omarchy-launcher tile
  assert_installed
  grep -q 'app-id=TUI.tile' "$desktop"
  install_fzd
  assert_installed
  grep -q 'app-id=TUI.tile' "$desktop"
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ ! -e "$desktop" ]
  [ -f "$XDG_DATA_HOME/blesh/ble.sh" ]
}

@test "unmanaged and modified Omarchy desktop entries are preserved even with adopt" {
  enhancement_tools
  omarchy_tools
  mkdir -p "$XDG_DATA_HOME/applications"
  printf 'user launcher\n' >"$XDG_DATA_HOME/applications/FZD.desktop"
  install_fzd --enhanced --omarchy-launcher float --adopt
  assert_installed
  [ "$(cat "$XDG_DATA_HOME/applications/FZD.desktop")" = 'user launcher' ]
  rm "$XDG_DATA_HOME/applications/FZD.desktop"
  install_fzd --enhanced --omarchy-launcher float
  assert_installed
  printf '# user edit\n' >>"$XDG_DATA_HOME/applications/FZD.desktop"
  install_fzd --enhanced --omarchy-launcher tile
  assert_installed
  grep -q '# user edit' "$XDG_DATA_HOME/applications/FZD.desktop"
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  grep -q '# user edit' "$XDG_DATA_HOME/applications/FZD.desktop"
}

@test "launcher skips non Omarchy and unsupported shell and rejects accidental Simple registration" {
  enhancement_tools
  install_fzd --enhanced --omarchy-launcher float
  assert_installed
  [ ! -e "$XDG_DATA_HOME/applications/FZD.desktop" ]
  omarchy_tools
  install_fzd --enhanced --omarchy-launcher float --shell zsh
  assert_installed
  [[ "$output" == *'currently supports interactive Bash'* ]]
  [ ! -e "$XDG_DATA_HOME/applications/FZD.desktop" ]
  install_fzd --omarchy-launcher float
  [ "$status" -ne 0 ]
  [[ "$output" == *'requires --enhanced'* ]]
}

@test "launcher rollback leaves an earlier desktop entry intact after later publication failure" {
  enhancement_tools
  omarchy_tools
  install_fzd --enhanced --omarchy-launcher float
  assert_installed
  cp "$XDG_DATA_HOME/applications/FZD.desktop" "$HOME/desktop.before"
  inject_fault fail
  export FZD_FAULT_TARGET="$DATA/install.manifest"
  install_fzd --enhanced --omarchy-launcher tile
  [ "$status" -ne 0 ]
  cmp "$HOME/desktop.before" "$XDG_DATA_HOME/applications/FZD.desktop"
  install_fzd --verify
  [ "$status" -eq 0 ]
}

@test "package-owned Omarchy startup files cannot be selected through a user symlink" {
  enhancement_tools
  mkdir -p "$HOME/omarchy/default/bash"
  export OMARCHY_PATH="$HOME/omarchy"
  printf 'user-content\n' >"$OMARCHY_PATH/default/bash/rc"
  ln -s "$OMARCHY_PATH/default/bash/rc" "$HOME/.bashrc"
  install_fzd
  [ "$status" -ne 0 ]
  [[ "$output" == *'package-owned Omarchy startup'* ]]
  [ "$(cat "$OMARCHY_PATH/default/bash/rc")" = user-content ]
  [ ! -e "$PREFIX/bin/fzd" ]
}

@test "native desktop parser retains quoted special characters in custom launcher prefixes" {
  [[ -n $REAL_GIO ]] || skip 'gio unavailable for native desktop parsing'
  enhancement_tools
  omarchy_tools
  PREFIX="$HOME/space \"quote\" \$literal \`literal\` \\slash %percent"
  DATA="$PREFIX/share/fzd"
  install_fzd --prefix "$PREFIX" --enhanced --omarchy-launcher float
  assert_installed
  cat >"$TEST_BIN/xdg-terminal-exec" <<'SH'
#!/bin/sh
printf '%s\0' "$@" >"$HOME/launcher-args"
SH
  chmod +x "$TEST_BIN/xdg-terminal-exec"
  run "$REAL_GIO" launch "$XDG_DATA_HOME/applications/FZD.desktop"
  [ "$status" -eq 0 ]
  # GIO spawns asynchronously; wait for the private recording process only.
  local attempt
  for attempt in {1..30}; do
    [[ ! -e $HOME/launcher-args ]] || break
    sleep .05
  done
  local args=()
  mapfile -d '' -t args <"$HOME/launcher-args"
  [ "${args[0]}" = --app-id=TUI.float ]
  [ "${args[2]}" = bash ]
  [ "${args[4]}" = "$DATA/launcher.bash" ]
  [ "${args[5]}" = -i ]
}
