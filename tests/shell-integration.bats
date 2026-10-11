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
  # Extract the literal heredoc as data; never execute the installer.
  awk -v shell="$1" '
    $0 ~ "cat >.*init[.]" shell { copying=1; next }
    copying && /^EOF$/ { exit }
    copying { print }
  ' "$FZD_REPO/install.sh" >"$BATS_TEST_TMPDIR/init"
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

@test "legacy shell wrapper trailing-newline limitation remains explicitly deferred" {
  skip 'install.sh wrappers strip trailing newlines through command substitution; installer modernization is excluded from this phase'
}
