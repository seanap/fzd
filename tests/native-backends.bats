#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "real fd indexes configured roots and labels directories" {
  [ -n "$FZD_REAL_FD" ] || skip 'fd/fdfind is not installed'
  ln -s "$FZD_REAL_FD" "$TEST_BIN/fdfind"
  mkdir -p "$FIXTURE_ROOT/needle-dir" "$FIXTURE_ROOT/.git"
  printf text > "$FIXTURE_ROOT/needle file"
  printf text > "$FIXTURE_ROOT/.git/needle-hidden"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_index
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle-dir"
  assert_record_path "$FIXTURE_ROOT/needle file"
  assert_no_record_path "$FIXTURE_ROOT/.git/needle-hidden"
  [[ "$output" == *$'\tneedle-dir/'* ]]
}

@test "real fd query preserves newline paths and literal option characters" {
  [ -n "$FZD_REAL_FD" ] || skip 'fd/fdfind is not installed'
  ln -s "$FZD_REAL_FD" "$TEST_BIN/fdfind"
  local path="$FIXTURE_ROOT/"$'needle\nlast\n'
  printf text > "$path"
  printf text > "$FIXTURE_ROOT/--help"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q NEEDLE
  [ "$status" -eq 0 ]
  assert_record_path "$path"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q --help
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/--help"
}
