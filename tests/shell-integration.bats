#!/usr/bin/env bats
load helpers/common
setup() {
  setup_fixture
  export FZD_DEST="$FIXTURE_ROOT/"$'space \'quote Unicode-λ embedded\nline'
  mkdir -p "$FZD_DEST"
  printf '#!/bin/sh\nprintf "%%s\\n" "$FZD_DEST"\nexit "${FZD_EXIT:-0}"\n' >"$TEST_BIN/fzd"
  chmod +x "$TEST_BIN/fzd"
}

extract_init() {
  cat "$FZD_REPO/shell/integration.sh" >"$BATS_TEST_TMPDIR/init"
  [ -s "$BATS_TEST_TMPDIR/init" ]
}

check_shell_cd() {
  extract_init "$1"
  local options=(--noprofile --norc)
  [[ "$1" == zsh ]] && options=(-f)
  run "$2" "${options[@]}" -c 'source "$1"; lf; [[ "$PWD" == "$FZD_DEST" ]]' _ "$BATS_TEST_TMPDIR/init"
  [ "$status" -eq 0 ]
}

check_shell_cancel() {
  extract_init "$1"
  export FZD_EXIT=130
  local options=(--noprofile --norc)
  [[ "$1" == zsh ]] && options=(-f)
  run "$2" "${options[@]}" -c 'source "$1"; before=$PWD; lf; rc=$?; [[ "$rc" == 0 && "$PWD" == "$before" ]]' _ "$BATS_TEST_TMPDIR/init"
  [ "$status" -eq 0 ]
}

@test "existing Bash integration changes directory with quotes Unicode and embedded newline" {
  check_shell_cd bash bash
}

@test "existing zsh integration changes directory with quotes Unicode and embedded newline" {
  [ -n "$FZD_REAL_ZSH" ] || skip 'zsh is not installed'
  check_shell_cd zsh "$FZD_REAL_ZSH"
}

@test "existing Bash integration treats Esc as a cancelled navigation" {
  check_shell_cancel bash bash
}

@test "existing zsh integration treats Esc as a cancelled navigation" {
  [ -n "$FZD_REAL_ZSH" ] || skip 'zsh is not installed'
  check_shell_cancel zsh "$FZD_REAL_ZSH"
}

@test "Bash and zsh wrappers preserve directories ending with multiple newlines" {
  export FZD_DEST="$FIXTURE_ROOT/"$'trailing\n\n'
  mkdir -p "$FZD_DEST"
  check_shell_cd bash bash
  check_shell_cd zsh "$FZD_REAL_ZSH"
}

@test "Bash and zsh wrappers preserve every legal non-NUL filename byte" {
  local bytes='' byte i
  for ((i = 1; i < 256; i++)); do
    ((i == 47)) && continue
    printf -v byte '%03o' "$i"
    printf -v byte '%b' "\\$byte"
    bytes+=$byte
  done
  export FZD_DEST="$FIXTURE_ROOT/$bytes"
  mkdir -p "$FZD_DEST"
  check_shell_cd bash bash
  check_shell_cd zsh "$FZD_REAL_ZSH"
}

@test "shell integration leaves existing lf functions aliases and executables intact" {
  extract_init bash
  for shell in bash "$FZD_REAL_ZSH"; do
    run "$shell" -c 'lf() { printf existing; }; source "$1"; [[ $(lf) == existing ]]; command -v fzd_cd' _ "$BATS_TEST_TMPDIR/init"
    [ "$status" -eq 0 ]
    run "$shell" -c 'alias lf="printf existing"; source "$1"; alias lf' _ "$BATS_TEST_TMPDIR/init"
    [ "$status" -eq 0 ]
    [[ "$output" == *existing* ]]
  done
  run bash -O expand_aliases -ec 'alias lf="printf existing"; alias fzd_cd="printf alternate"; source "$1"; alias lf; alias fzd_cd' _ "$BATS_TEST_TMPDIR/init"
  [ "$status" -eq 0 ]
  printf '#!/bin/sh\nprintf existing\n' >"$TEST_BIN/lf"
  chmod +x "$TEST_BIN/lf"
  for shell in bash "$FZD_REAL_ZSH"; do
    run "$shell" -c 'source "$1"; [[ $(lf) == existing ]]' _ "$BATS_TEST_TMPDIR/init"
    [ "$status" -eq 0 ]
  done
}

@test "shell integration preserves editor colors and never sources Bash user configuration in zsh" {
  extract_init bash
  printf 'printf executed >"$XDG_CONFIG_HOME/marker"\ndeclare -A bash_only=()\n' >"$FZD_CONF_FILE"
  for shell in bash "$FZD_REAL_ZSH"; do
    run "$shell" -c 'export EDITOR=custom VISUAL=other LS_COLORS=original; source "$1"; source "$1"; [[ $EDITOR == custom && $VISUAL == other && $LS_COLORS == original ]]' _ "$BATS_TEST_TMPDIR/init"
    [ "$status" -eq 0 ]
  done
  [ ! -e "$XDG_CONFIG_HOME/marker" ]
}

@test "shell wrappers propagate failures safely under errexit and treat empty output as success" {
  extract_init bash
  export FZD_EXIT=7
  for shell in bash "$FZD_REAL_ZSH"; do
    run "$shell" -ec 'source "$1"; lf; printf unreachable' _ "$BATS_TEST_TMPDIR/init"
    [ "$status" -eq 7 ]
    [[ "$output" != *unreachable* ]]
  done
  export FZD_EXIT=0 FZD_DEST=''
  for shell in bash "$FZD_REAL_ZSH"; do
    run "$shell" -ec 'source "$1"; lf; [[ $PWD == "$2" ]]' _ "$BATS_TEST_TMPDIR/init" "$PWD"
    # The stub emits the protocol newline even for an empty value: reject it.
    [ "$status" -eq 1 ]
  done
}
