#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "real fd indexes configured roots and labels directories" {
  [ -n "$FZD_REAL_FD" ] || skip 'fd/fdfind is not installed'
  ln -s "$FZD_REAL_FD" "$TEST_BIN/fdfind"
  mkdir -p "$FIXTURE_ROOT/needle-dir" "$FIXTURE_ROOT/.git"
  printf text >"$FIXTURE_ROOT/needle file"
  printf text >"$FIXTURE_ROOT/.git/needle-hidden"
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
  printf text >"$path"
  printf text >"$FIXTURE_ROOT/--help"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q NEEDLE
  [ "$status" -eq 0 ]
  assert_record_path "$path"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q --help
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/--help"
}

@test "real plocate private database preserves unusual names and directory labels" {
  local path="$FIXTURE_ROOT/"$'needle\ttab\nlast\n'
  printf text >"$path"
  mkdir -p "$FIXTURE_ROOT/needle-dir" "$FIXTURE_ROOT/.git"
  printf text >"$FIXTURE_ROOT/.git/needle-excluded"
  private_locate
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q NEEDLE
  [ "$status" -eq 0 ]
  assert_record_path "$path"
  assert_record_path "$FIXTURE_ROOT/needle-dir"
  assert_no_record_path "$FIXTURE_ROOT/.git/needle-excluded"
  [[ "$output" == *$'\tneedle-dir/'* ]]
  [ -z "$stderr" ]
}

@test "real plocate treats wildcard query characters literally" {
  printf text >"$FIXTURE_ROOT/needle[1]*?.txt"
  printf text >"$FIXTURE_ROOT/needle-other.txt"
  private_locate
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q '[1]*?'
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle[1]*?.txt"
  assert_no_record_path "$FIXTURE_ROOT/needle-other.txt"
  [ -z "$stderr" ]
}

@test "scoped plocate escapes regex characters in roots and queries and retains newline names" {
  FIXTURE_ROOT+='/literal[1].(a)+$^|?'
  mkdir -p "$FIXTURE_ROOT"
  local path="$FIXTURE_ROOT/"$'needle[2].(b)+$^|?\nlast'
  touch "$path"
  export FZD_GLOBAL_PATHS="$FIXTURE_ROOT"
  private_locate
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q 'needle[2].(b)+$^|?'
  [ "$status" -eq 0 ]
  assert_record_path "$path"
  [ -z "$stderr" ]
}

@test "real plocate missing database falls back to the filesystem" {
  printf text >"$FIXTURE_ROOT/needle-file"
  private_locate
  export FZD_LOCATE_DBS="$BATS_TEST_TMPDIR/missing.db"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle-file"
  [[ "$stderr" == *'falling back'* ]]
}

@test "real plocate no matches succeeds without a fallback scan" {
  private_locate
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q no-matching-path
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "real fd honors relative roots containing dot components" {
  [ -n "$FZD_REAL_FD" ] || skip 'fd/fdfind is not installed'
  ln -s "$FZD_REAL_FD" "$TEST_BIN/fdfind"
  printf text >"$FIXTURE_ROOT/needle-file"
  export FZD_GLOBAL_PATHS=./files/.
  run --separate-stderr bash -c 'cd -- "$1"; exec bash "$2" --_global_list --q needle' _ "$BATS_TEST_TMPDIR" "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle-file"
}

@test "real fd and find agree that depth zero yields no descendants" {
  [ -n "$FZD_REAL_FD" ] || skip 'fd/fdfind is not installed'
  printf text >"$FIXTURE_ROOT/needle-file"
  export FZD_GLOBAL_MAXDEPTH=0
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  ln -s "$FZD_REAL_FD" "$TEST_BIN/fdfind"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
