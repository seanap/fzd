#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "unwritable runtime storage fails clearly before starting fzf" {
  printf file >"$BATS_TEST_TMPDIR/not-a-directory"
  export FZD_TMP_DIR="$BATS_TEST_TMPDIR/not-a-directory/tmp"
  run bash "$FZD_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *'cannot create state, cache or temporary directories'* ]]
}

@test "failed mktemp never launches a session with an empty control pathname" {
  printf '#!/bin/sh\nif [ "$#" -eq 0 ]; then exit 1; fi\nexec %s "$@"\n' "$(command -v mktemp)" >"$TEST_BIN/mktemp"
  chmod +x "$TEST_BIN/mktemp"
  run_planned_session
  [ "$status" -eq 1 ]
  [[ "$stderr" == *'cannot create temporary file'* ]]
}

@test "normal exit and Esc remove all control files" {
  run_planned_session
  [ "$status" -eq 130 ]
  run find "$XDG_RUNTIME_DIR" -type f
  [ -z "$output" ]
}

@test "termination cleans a locate staging file and reports signal status" {
  # Signal the direct parent Bash while the controlled producer is running.
  printf '#!/bin/sh\nkill -TERM "$PPID"\nsleep 0.05\nexit 2\n' >"$TEST_BIN/plocate"
  chmod +x "$TEST_BIN/plocate"
  export FZD_GLOBAL_BACKEND=locate
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 143 ]
  run find "$XDG_RUNTIME_DIR" -type f
  [ -z "$output" ]
}
