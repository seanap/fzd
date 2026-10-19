#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "global index does not execute command substitutions in filenames" {
  use_fd_stub
  local path="$FIXTURE_ROOT/needle\$(printf hit > FZD_INJECTION_MARKER).txt"
  printf 'fixture\n' >"$path"
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
  printf text >"$FIXTURE_ROOT/needle-file"
  run bash "$FZD_SCRIPT" --_global_index
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle-dir"
  assert_record_path "$FIXTURE_ROOT/needle-file"
}

@test "find search returns directories and files case insensitively" {
  mkdir -p "$FIXTURE_ROOT/Needle-dir"
  printf text >"$FIXTURE_ROOT/Needle-file"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/Needle-dir"
  assert_record_path "$FIXTURE_ROOT/Needle-file"
}

@test "find honors exclusions with spaces without shell expansion" {
  export FZD_EXCLUDES='skip this'
  mkdir -p "$FIXTURE_ROOT/skip this" "$FIXTURE_ROOT/keep"
  printf text >"$FIXTURE_ROOT/skip this/needle"
  printf text >"$FIXTURE_ROOT/keep/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/keep/needle"
  assert_no_record_path "$FIXTURE_ROOT/skip this/needle"
}

@test "locate filters results outside configured roots" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate
  mkdir -p "$BATS_TEST_TMPDIR/outside"
  printf text >"$FIXTURE_ROOT/needle"
  printf text >"$BATS_TEST_TMPDIR/outside/needle"
  set_results "$BATS_TEST_TMPDIR/outside/needle" "$FIXTURE_ROOT/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
  assert_no_record_path "$BATS_TEST_TMPDIR/outside/needle"
}

@test "locate root slash admits descendants" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate FZD_GLOBAL_PATHS=/
  printf text >"$FIXTURE_ROOT/needle"
  set_results "$FIXTURE_ROOT/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
}

@test "failed locate database falls back to live filesystem search" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate FZD_STUB_LOCATE_STATUS=2
  printf text >"$FIXTURE_ROOT/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
}

@test "explicit live mode does not call an available locate backend" {
  use_locate_stub
  printf text >"$FIXTURE_ROOT/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
  [ ! -e "$FZD_STUB_LOG" ]
}

@test "query option characters are literal filename data" {
  printf text >"$FIXTURE_ROOT/--help"
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

@test "all search producers preserve unusual path bytes without executing names" {
  local name path producer
  local names=('needle space' "needle'quote" 'needle"double' 'needle`printf hit`' 'needle$(printf hit)' 'needle\\slash' 'needle-é' $'needle\ttab' $'needle\nline' $'needle-tail\n')
  local paths=()
  for name in "${names[@]}"; do
    path="$FIXTURE_ROOT/$name"
    printf text >"$path"
    paths+=("$path")
  done
  set_results "${paths[@]}"
  for producer in find fd locate; do
    rm -f -- "$TEST_BIN/fd" "$TEST_BIN/plocate"
    export FZD_GLOBAL_BACKEND=live
    case "$producer" in
    fd) use_fd_stub ;;
    locate)
      use_locate_stub
      export FZD_GLOBAL_BACKEND=locate
      ;;
    esac
    run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q needle
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq "${#paths[@]}" ]
    for path in "${paths[@]}"; do assert_record_path "$path"; done
  done
}

@test "find honors depth and result limits" {
  mkdir -p "$FIXTURE_ROOT/one/two"
  printf text >"$FIXTURE_ROOT/needle-first"
  printf text >"$FIXTURE_ROOT/needle-second"
  printf text >"$FIXTURE_ROOT/one/two/needle-deep"
  export FZD_GLOBAL_MAXDEPTH=1 FZD_GLOBAL_MAXRESULTS=1
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  assert_no_record_path "$FIXTURE_ROOT/one/two/needle-deep"
}

@test "locate applies result cap after scope and exclusion filtering" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate FZD_GLOBAL_MAXRESULTS=1
  mkdir -p "$BATS_TEST_TMPDIR/outside" "$FIXTURE_ROOT/.git"
  printf text >"$BATS_TEST_TMPDIR/outside/needle"
  printf text >"$FIXTURE_ROOT/.git/needle"
  printf text >"$FIXTURE_ROOT/needle"
  set_results "$BATS_TEST_TMPDIR/outside/needle" "$FIXTURE_ROOT/.git/needle" "$FIXTURE_ROOT/needle"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  assert_record_path "$FIXTURE_ROOT/needle"
}

@test "basename and full-path policies agree across backends" {
  local producer
  mkdir -p "$FIXTURE_ROOT/needle-parent"
  printf text >"$FIXTURE_ROOT/needle-parent/other"
  set_results "$FIXTURE_ROOT/needle-parent/other"
  for producer in find fd locate; do
    rm -f -- "$TEST_BIN/fd" "$TEST_BIN/plocate"
    export FZD_GLOBAL_BACKEND=live
    case "$producer" in
    fd) use_fd_stub ;;
    locate)
      use_locate_stub
      export FZD_GLOBAL_BACKEND=locate
      ;;
    esac
    export FZD_GLOBAL_FULLPATH=0
    run bash "$FZD_SCRIPT" --_global_list --q needle
    [ "$status" -eq 0 ]
    assert_no_record_path "$FIXTURE_ROOT/needle-parent/other"
    export FZD_GLOBAL_FULLPATH=1
    run bash "$FZD_SCRIPT" --_global_list --q NEEDLE
    [ "$status" -eq 0 ]
    assert_record_path "$FIXTURE_ROOT/needle-parent/other"
  done
}

@test "missing results are omitted while live and dangling symlinks remain operable" {
  use_fd_stub
  printf text >"$FIXTURE_ROOT/needle-target"
  ln -s "$FIXTURE_ROOT/needle-target" "$FIXTURE_ROOT/needle-link"
  ln -s "$FIXTURE_ROOT/missing" "$FIXTURE_ROOT/needle-dangling"
  set_results "$FIXTURE_ROOT/needle-link" "$FIXTURE_ROOT/needle-dangling" "$FIXTURE_ROOT/needle-missing"
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  assert_record_path "$FIXTURE_ROOT/needle-link"
  assert_record_path "$FIXTURE_ROOT/needle-dangling"
  assert_no_record_path "$FIXTURE_ROOT/needle-missing"
}

@test "a failed locate producer cannot leak partial results before fallback" {
  use_locate_stub
  cat >"$TEST_BIN/plocate-partial" <<'STUB'
#!/usr/bin/env bash
printf '%s\0' "$FZD_PARTIAL_RESULT"
exit 2
STUB
  chmod +x "$TEST_BIN/plocate-partial"
  ln -sf "$TEST_BIN/plocate-partial" "$TEST_BIN/plocate"
  export FZD_GLOBAL_BACKEND=locate FZD_PARTIAL_RESULT="$FIXTURE_ROOT/needle"
  printf text >"$FZD_PARTIAL_RESULT"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  assert_record_path "$FZD_PARTIAL_RESULT"
}

@test "plocate restricts visibility checks to configured roots without requesting global existence checks" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate FZD_GLOBAL_PATHS="$FIXTURE_ROOT"
  printf text >"$FIXTURE_ROOT/needle"
  set_results "$FIXTURE_ROOT/needle"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  assert_record_path "$FIXTURE_ROOT/needle"
  run bash -euc 'mapfile -d "" -t args <"$1"; [[ " ${args[*]} " != *" --regex "* ]]; [[ " ${args[*]} " != *" -e "* ]]; [[ $2/needle == ${args[-1]} ]]; [[ /mnt/windows/needle != ${args[-1]} ]]; [[ $2-sibling/needle != ${args[-1]} ]]' _ "$FZD_STUB_LOG" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
}

@test "validated locate results stream before later filesystem metadata checks finish" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate
  touch "$FIXTURE_ROOT/needle-first" "$FIXTURE_ROOT/needle-slow"
  set_results "$FIXTURE_ROOT/needle-first" "$FIXTURE_ROOT/needle-slow"
  run bash -euc '
    source "$1"
    RECENT_PENDING=(); FZD_TEMP_FILES=()
    _fzd_paths; _fzd_init --_global_list
    trap _cleanup EXIT
    _global_allowed() { [[ $1 != *-slow ]] || sleep 2; }
    _global_list needle >"$2" & producer=$!
    for attempt in {1..20}; do [[ ! -s $2 ]] || break; sleep .05; done
    [[ -s $2 ]] || { kill "$producer"; wait "$producer" || true; exit 1; }
    kill -0 "$producer"
    wait "$producer"
  ' _ "$FZD_SCRIPT" "$BATS_TEST_TMPDIR/streamed"
  [ "$status" -eq 0 ]
}

@test "compiled scope and exclusions agree with literal roots and legacy glob policies" {
  run bash -euc '
    source "$1"
    FZD_GLOBAL_ROOTS=("$2" "$2/other[1]|(literal)")
    mkdir -p "${FZD_GLOBAL_ROOTS[@]}"
    FZD_GLOBAL_FULLPATH=0
    for exclusions in ".git,node_modules,proc/*,skip this" "@(skip|drop),literal|pipe"; do
      FZD_EXCLUDES=$exclusions
      _global_prepare
      for path in "$2/file" "$2/.git/file" "$2/proc/a/file" "$2/skip this/file" "$2/skip/file" "$2/literal|pipe/file" "$2-sibling/file" "$2/other[1]|(literal)/file"; do
        expected=1
        for root in "${GLOBAL_ROOTS[@]}"; do
          if [[ $path == "$root" || $path == "$root/"* ]]; then expected=0; break; fi
        done
        for pattern in "${GLOBAL_EXCLUDES[@]}"; do
          pattern=${pattern%/}
          if [[ -n $pattern && "$path/" == */$pattern/* ]]; then expected=1; fi
        done
        actual=0; _global_allowed "$path" || actual=$?
        [[ $actual == "$expected" ]] || { printf "Mismatch: %s\n" "$path"; exit 1; }
      done
    done
  ' _ "$FZD_SCRIPT" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
}

@test "a later scoped producer failure discards earlier results before live fallback" {
  mkdir -p "$FIXTURE_ROOT/one/a/b/c/d/e/f" "$FIXTURE_ROOT/two"
  local indexed="$FIXTURE_ROOT/one/a/b/c/d/e/f/needle-indexed-only"
  touch "$indexed" "$FIXTURE_ROOT/two/needle-live"
  printf 'FZD_GLOBAL_ROOTS=(%q %q)\n' "$FIXTURE_ROOT/one" "$FIXTURE_ROOT/two" >"$FZD_CONF_FILE"
  export FZD_GLOBAL_BACKEND=locate FZD_PARTIAL_RESULT="$indexed" FZD_FAIL_ROOT="$FIXTURE_ROOT/two"
  cat >"$TEST_BIN/plocate" <<'SH'
#!/usr/bin/env bash
last=${!#}
[[ $last != "$FZD_FAIL_ROOT/"* ]] || exit 2
printf '%s\0' "$FZD_PARTIAL_RESULT"
SH
  chmod +x "$TEST_BIN/plocate"
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  assert_record_path "$FIXTURE_ROOT/two/needle-live"
  assert_no_record_path "$indexed"
  [[ "$stderr" == *'falling back'* ]]
}

@test "indexed probes close descriptors and reap producers after repeated searches" {
  use_locate_stub
  export FZD_GLOBAL_BACKEND=locate
  touch "$FIXTURE_ROOT/needle"
  set_results "$FIXTURE_ROOT/needle"
  run bash -euc '
    source "$1"; RECENT_PENDING=(); FZD_TEMP_FILES=()
    _fzd_paths; _fzd_init --_global_list
    trap _cleanup EXIT
    before=(/proc/$$/fd/*)
    for attempt in {1..10}; do _global_list needle >/dev/null; done
    after=(/proc/$$/fd/*)
    [[ ${#before[@]} == ${#after[@]} ]]
    [[ -z $(jobs -pr) && -z ${FZD_GLOBAL_PRODUCER:-} ]]
  ' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "cancelling an indexed query terminates and reaps its active producer" {
  export FZD_GLOBAL_BACKEND=locate FZD_PRODUCER_PID="$BATS_TEST_TMPDIR/producer.pid"
  cat >"$TEST_BIN/plocate" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$$" >"$FZD_PRODUCER_PID"
exec sleep 30
SH
  chmod +x "$TEST_BIN/plocate"
  run bash -euc '
    bash "$1" --_global_list --q needle >/dev/null 2>&1 & helper=$!
    trap '\''kill "$helper" "${producer:-$helper}" 2>/dev/null || true'\'' EXIT
    for attempt in {1..100}; do [[ ! -s $FZD_PRODUCER_PID ]] || break; sleep .01; done
    read -r producer <"$FZD_PRODUCER_PID"
    kill -TERM "$helper"
    wait "$helper" || true
    ! kill -0 "$producer" 2>/dev/null
    trap - EXIT
  ' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
}
