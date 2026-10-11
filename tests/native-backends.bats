#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

private_locate() {
  local tools="$FZD_REPO/.test-work/tools/root"
  if [[ -z "$FZD_REAL_LOCATE" && -x "$tools/usr/bin/plocate" ]]; then
    FZD_REAL_LOCATE="$tools/usr/bin/plocate"
    FZD_REAL_UPDATEDB="$tools/usr/sbin/updatedb.plocate"
    export LD_LIBRARY_PATH="$tools/usr/lib/$(/usr/bin/dpkg-architecture -qDEB_HOST_MULTIARCH)${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  fi
  [[ -x "$FZD_REAL_LOCATE" && -x "$FZD_REAL_UPDATEDB" ]] || skip 'private locate tools unavailable; see tests/README.md'
  ln -s "$FZD_REAL_LOCATE" "$TEST_BIN/plocate"
  export FZD_LOCATE_DBS="$BATS_TEST_TMPDIR/locate.db" FZD_GLOBAL_BACKEND=locate
  "$FZD_REAL_UPDATEDB" --database-root "$FIXTURE_ROOT" --output "$FZD_LOCATE_DBS" \
    --require-visibility no --prunepaths '' --prunenames '' --prunefs '' --prune-bind-mounts no
}

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
}

@test "real plocate treats wildcard query characters literally" {
  printf text >"$FIXTURE_ROOT/needle[1]*?.txt"
  printf text >"$FIXTURE_ROOT/needle-other.txt"
  private_locate
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q '[1]*?'
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle[1]*?.txt"
  assert_no_record_path "$FIXTURE_ROOT/needle-other.txt"
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
