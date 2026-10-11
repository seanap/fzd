#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "global index does not execute command substitutions in filenames" {
  use_fd_stub
  local path="$FIXTURE_ROOT/needle\$(printf hit > FZD_INJECTION_MARKER).txt"
  printf 'fixture\n' > "$path"
  set_results "$path"
  run bash -c 'cd -- "$1"; exec bash "$2" --_global_index' _ "$FIXTURE_ROOT" "$FZD_SCRIPT"
  [ ! -e "$FIXTURE_ROOT/FZD_INJECTION_MARKER" ]
  [ "$status" -eq 0 ]
  assert_record_path "$path"
}

@test "cache sends configured roots and exclusions to fd" {
  use_fd_stub
  mkdir -p "$FIXTURE_ROOT/needle-dir"
  set_results "$FIXTURE_ROOT/needle-dir/"
  run bash "$FZD_SCRIPT" --_global_index
  [ "$status" -eq 0 ]
  run bash -c 'mapfile -d "" -t args < "$1"; printf "<%s>\n" "${args[@]}"' _ "$FZD_STUB_LOG"
  [[ "$output" == *"<$FIXTURE_ROOT>"* ]]
  [[ "$output" == *'<.git>'* ]]
}

@test "cache directory labels contain the directory basename" {
  use_fd_stub
  mkdir -p "$FIXTURE_ROOT/needle-dir"
  set_results "$FIXTURE_ROOT/needle-dir/"
  run bash "$FZD_SCRIPT" --_global_index
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\tneedle-dir/'* ]]
}

@test "cache falls back to find when fd is unavailable" {
  mkdir -p "$FIXTURE_ROOT/needle-dir"
  printf text > "$FIXTURE_ROOT/needle-file"
  run bash "$FZD_SCRIPT" --_global_index
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle-dir"
  assert_record_path "$FIXTURE_ROOT/needle-file"
}

@test "find search returns directories and files case insensitively" {
  mkdir -p "$FIXTURE_ROOT/Needle-dir"
  printf text > "$FIXTURE_ROOT/Needle-file"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/Needle-dir"
  assert_record_path "$FIXTURE_ROOT/Needle-file"
}

@test "find honors exclusions with spaces without shell expansion" {
  export FZD_EXCLUDES='skip this'
  mkdir -p "$FIXTURE_ROOT/skip this" "$FIXTURE_ROOT/keep"
  printf text > "$FIXTURE_ROOT/skip this/needle"
  printf text > "$FIXTURE_ROOT/keep/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/keep/needle"
  assert_no_record_path "$FIXTURE_ROOT/skip this/needle"
}

@test "locate filters results outside configured roots" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  printf text > "$FIXTURE_ROOT/needle"
  printf text > "$BATS_TEST_TMPDIR/outside/needle"
  set_results "$BATS_TEST_TMPDIR/outside/needle" "$FIXTURE_ROOT/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
  assert_no_record_path "$BATS_TEST_TMPDIR/outside/needle"
}

@test "locate root slash admits descendants" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate FZD_GLOBAL_PATHS=/
  printf text > "$FIXTURE_ROOT/needle"
  set_results "$FIXTURE_ROOT/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
}

@test "failed locate database falls back to live filesystem search" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate FZD_STUB_LOCATE_STATUS=2
  printf text > "$FIXTURE_ROOT/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
}

@test "explicit live mode does not call an available locate backend" {
  use_locate_stub
  printf text > "$FIXTURE_ROOT/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
  [ ! -e "$FZD_STUB_LOG" ]
}

@test "query option characters are literal filename data" {
  printf text > "$FIXTURE_ROOT/--help"
  export FZD_GLOBAL_FULLPATH=1
  run bash "$FZD_SCRIPT" --_global_list --q --help
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/--help"
}

@test "short queries return no records successfully" {
  run bash "$FZD_SCRIPT" --_global_list --q n
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no matches is a successful empty search" {
  run bash "$FZD_SCRIPT" --_global_list --q absent
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
