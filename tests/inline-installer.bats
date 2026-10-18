#!/usr/bin/env bats
load helpers/installer

prepare_inline() {
  local compat=${FZD_COMPAT_ROOT:-$REPO/.test-work/compat} tool executable
  export FZD_TEST_BLE_ARCHIVE="$compat/ble-0.4.0-devel3-2.tar.xz"
  [[ -f $FZD_TEST_BLE_ARCHIVE ]] || skip 'run bash dev/prepare-shell-compat.sh'
  export FZD_ZSH_AUTOSUGGESTIONS_PATH="$compat/zsh-autosuggestions/zsh-autosuggestions.zsh"
  # Recommended dependencies in the private PATH; no real manager is reachable.
  for tool in eza fd fdfind bat batcat; do
    executable=$(PATH="$HOST_PATH" command -v "$tool" || true)
    [[ -z $executable ]] || ln -s "$executable" "$TEST_BIN/$tool"
  done
  rm "$TEST_BIN/curl"
  cat >"$TEST_BIN/curl" <<'STUB'
#!/bin/bash
printf 'download\n' >>"$CALLS"
while (($#)); do
  if [[ $1 == --output ]]; then cp "$FZD_TEST_BLE_ARCHIVE" "$2"; exit; fi
  shift
done
exit 1
STUB
  chmod +x "$TEST_BIN/curl"
}

@test "Enhanced installs verified upstream Bash engine and configures both selected shells" {
  prepare_inline
  export WSL_DISTRO_NAME=FZD-Test
  install_fzd --deps recommended --enhanced
  assert_installed
  [ -f "$PREFIX/share/blesh/ble.sh" ]
  grep -q 'FZD_INLINE_SUGGESTIONS:=1' "$XDG_CONFIG_HOME/fzd/shell.bash"
  grep -q 'FZD_INLINE_SUGGESTIONS:=1' "$XDG_CONFIG_HOME/fzd/shell.zsh"
  grep -q 'then FZD_BLESH_PATH=' "$XDG_CONFIG_HOME/fzd/shell.bash"
  grep -q 'then FZD_ZSH_AUTOSUGGESTIONS_PATH=' "$XDG_CONFIG_HOME/fzd/shell.zsh"
  install_fzd --verify
  [ "$status" -eq 0 ]
  install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ -f "$PREFIX/share/blesh/ble.sh" ]
  [ ! -e "$XDG_CONFIG_HOME/fzd/shell.bash" ]
  [ -f "$FZD_ZSH_AUTOSUGGESTIONS_PATH" ]
}

@test "ordinary updates preserve opt-in and explicit disable retains shared engines and user rc content" {
  prepare_inline
  printf '# original settings\n' >"$HOME/.bashrc"
  install_fzd --deps recommended --inline-suggestions --shell bash
  assert_installed
  cp "$XDG_CONFIG_HOME/fzd/shell.bash" "$HOME/once"
  : >"$CALLS"
  install_fzd --shell bash
  assert_installed
  cmp "$XDG_CONFIG_HOME/fzd/shell.bash" "$HOME/once"
  [ ! -s "$CALLS" ]
  install_fzd --deps recommended --inline-suggestions --shell bash
  assert_installed
  [ ! -s "$CALLS" ]
  install_fzd --no-inline-suggestions --shell bash
  assert_installed
  grep -q '^FZD_INLINE_SUGGESTIONS=0$' "$XDG_CONFIG_HOME/fzd/shell.bash"
  grep -q '^# original settings$' "$HOME/.bashrc"
  [ -f "$PREFIX/share/blesh/ble.sh" ]
}

@test "existing custom Bash engine is reused and paths through symlinked Bash rc files are correct" {
  prepare_inline
  mkdir -p "$HOME/custom engine"
  export FZD_BLESH_PATH="$HOME/custom engine/ble.sh"
  printf '# existing dependency\n' >"$FZD_BLESH_PATH"
  printf '# user dotfile\n' >"$HOME/dotfile"
  ln -s "$HOME/dotfile" "$HOME/.bashrc"
  install_fzd --deps recommended --inline-suggestions --shell bash
  assert_installed
  [ -L "$HOME/.bashrc" ]
  [ ! -e "$CALLS" ]
  [ "$(cat "$FZD_BLESH_PATH")" = '# existing dependency' ]
  grep -q 'then FZD_BLESH_PATH=' "$XDG_CONFIG_HOME/fzd/shell.bash"
  ! grep -q 'then FZD_ZSH_AUTOSUGGESTIONS_PATH=' "$XDG_CONFIG_HOME/fzd/shell.bash"
}

@test "inline configuration requires explicit opt-in and never runs during noninteractive sourcing" {
  prepare_inline
  install_fzd --shell bash
  assert_installed
  [ ! -e "$CALLS" ]
  [ ! -e "$PREFIX/share/blesh" ]
  ! grep -q FZD_INLINE "$XDG_CONFIG_HOME/fzd/shell.bash"
  export FZD_BLESH_PATH="$HOME/engine"
  printf 'touch "$HOME/engine-executed"\n' >"$FZD_BLESH_PATH"
  install_fzd --deps recommended --inline-suggestions --shell bash
  assert_installed
  run bash -ec 'source "$XDG_CONFIG_HOME/fzd/shell.bash"; command -v lf; ! command -v bleopt'
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/engine-executed" ]
}

@test "inline with deps none requires engines already present and staging forbids shell setup" {
  prepare_inline
  install_fzd --deps recommended --inline-suggestions --deps none --shell bash
  [ "$status" -ne 0 ]
  [[ "$output" == *'ble.sh'* ]]
  [ ! -e "$PREFIX/bin/fzd" ]
  [ ! -e "$CALLS" ]
  install_fzd --deps recommended --inline-suggestions --shell none
  [ "$status" -ne 0 ]
  [ ! -e "$CALLS" ]
  install_fzd --deps recommended --inline-suggestions --stage "$HOME/stage" --prefix /usr
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/stage" ]
}

@test "failed download and wrong checksum roll back FZD without installing downloaded code" {
  prepare_inline
  export FZD_TEST_BLE_ARCHIVE="$HOME/wrong-archive"
  printf untrusted >"$FZD_TEST_BLE_ARCHIVE"
  install_fzd --deps recommended --inline-suggestions --shell bash
  [ "$status" -ne 0 ]
  [[ "$output" == *'ble.sh SHA256 mismatch'* ]]
  [ ! -e "$PREFIX/share/blesh" ]
  [ ! -e "$PREFIX/bin/fzd" ]
  [ ! -e "$XDG_CONFIG_HOME/fzd/shell.bash" ]
  printf '#!/bin/sh\nexit 22\n' >"$TEST_BIN/curl"
  install_fzd --deps recommended --inline-suggestions --shell bash
  [ "$status" -ne 0 ]
  [[ "$output" == *'ble.sh download failed'* ]]
  [ ! -e "$PREFIX/bin/fzd" ]
}

@test "existing incomplete engine directories are preserved and never adopted automatically" {
  prepare_inline
  mkdir -p "$PREFIX/share/blesh"
  printf original >"$PREFIX/share/blesh/important"
  install_fzd --deps recommended --inline-suggestions --shell bash
  [ "$status" -ne 0 ]
  [[ "$output" == *'Existing blesh directory'* ]]
  [ "$(cat "$PREFIX/share/blesh/important")" = original ]
  [ ! -e "$CALLS" ]
}

@test "inline dependency detection includes zsh plugin and native ps package providers" {
  run bash -ec 'source "$1/installer/dependencies.bash"; source "$1/installer/inline.bash"; have() { [[ $1 != ps && $1 != zsh ]]; }; _inline_find_engines() { BLESH_PATH=existing; AUTOSUGGEST_PATH=""; }; MISSING=(); SHELL_TARGET=both; DEPS=required; _inline_collect_missing; [[ ${MISSING[*]} == "ps zsh zsh-autosuggestions" ]]; PM=apt; package_for ps; [[ $REPLY == procps ]]; PM=pacman; package_for ps; [[ $REPLY == procps-ng ]]; PM=dnf; package_for ps; [[ $REPLY == procps-ng ]]' _ "$REPO"
  [ "$status" -eq 0 ]
}

@test "opt-in zsh configuration retains existing strategy order and colors without duplicate completion entries" {
  prepare_inline
  run "$REAL_ZSH" -efc 'ZSH_AUTOSUGGEST_STRATEGY=(history match_prev_cmd); ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=magenta"; source "$1/shell/integration.sh"; _fzd_inline_zsh; _fzd_inline_zsh; [[ ${#ZSH_AUTOSUGGEST_STRATEGY} == 3 && $ZSH_AUTOSUGGEST_STRATEGY[1] == history && $ZSH_AUTOSUGGEST_STRATEGY[2] == match_prev_cmd && $ZSH_AUTOSUGGEST_STRATEGY[3] == completion && $ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE == "fg=magenta" ]]' _ "$REPO"
  [ "$status" -eq 0 ]
}

@test "Enhanced Bash respects active engines and user blesh configuration including faces and opt-outs" {
  local configured
  for configured in active blerc xdg; do
    mkdir -p "$HOME/.config/blesh"
    rm -f "$HOME/.blerc" "$HOME/.config/blesh/init.sh" "$HOME/engine"
    if [[ $configured == blerc ]]; then printf '# custom faces\n' >"$HOME/.blerc"; fi
    if [[ $configured == xdg ]]; then
      mkdir -p "$XDG_CONFIG_HOME/blesh"
      printf '# custom preferences\n' >"$XDG_CONFIG_HOME/blesh/init.sh"
    fi
    cat >"$HOME/engine" <<'SH'
bleopt() { printf 'modified options\n' >>"$HOME/modified"; }
ble-face() { printf 'modified faces\n' >>"$HOME/modified"; }
ble-attach() { :; }
SH
    run bash --noprofile --norc -ic '
      FZD_INLINE_SUGGESTIONS=1; FZD_BLESH_PATH=$HOME/engine
      if [[ $2 == active ]]; then source "$HOME/engine"; fi
      source "$1/shell/inline.sh"
    ' _ "$REPO" "$configured"
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/modified" ]
  done
}
