#!/usr/bin/env bats
load helpers/common
load helpers/explorer
setup() { setup_explorer_fixture; }

@test "browser history traverses without duplicates and discards the forward branch" {
  mkdir -p "$FIXTURE_ROOT/a" "$FIXTURE_ROOT/b" "$FIXTURE_ROOT/c"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_explorer
    root=$CUR; CUR=$root/a; _history_visit
    RAW=$CUR/selected; _history_remember
    CUR=$root/b; _history_visit
    _history_step -1; [[ $CUR == "$root/a" && $FZD_SELECT_NAME == selected ]]
    _history_step 1; [[ $CUR == "$root/b" && ${#H_PATHS[@]} == 3 ]]
    _history_step -1; CUR=$root/c; _history_visit
    [[ ${#H_PATHS[@]} == 3 && ${H_PATHS[2]} == "$root/c" ]]
    _history_step 1; [[ $CUR == "$root/c" ]]
    [[ ! -e $FZD_STATE_DIR/explorer ]]
  '
  [ "$status" -eq 0 ]
}

@test "browser history skips missing and inaccessible directories and is bounded" {
  mkdir -p "$FIXTURE_ROOT/a" "$FIXTURE_ROOT/b"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_explorer
    root=$CUR; CUR=$root/a; _history_visit
    CUR=$root/b; _history_visit
    rmdir -- "$root/a"
    _history_step -1; [[ $CUR == "$root" ]]
    for ((i=0;i<110;i++)); do CUR=$root/path-$i; _history_visit; done
    [[ ${#H_PATHS[@]} == 100 && $H_INDEX == 99 ]]
  '
  [ "$status" -eq 0 ]
}

@test "recent directories persist in MRU order with exact bytes and private permissions" {
  local unusual="$FIXTURE_ROOT/"$'é 雪 \'$(false)\t\n\n'
  mkdir -p "$unusual" "$FIXTURE_ROOT/other"
  export FZD_TEST_UNUSUAL="$unusual"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_explorer
    _recent_queue "$CUR/other"; _recent_queue "$FZD_TEST_UNUSUAL"
    _recent_queue "$CUR/other"; _recents_flush
    [[ $(stat -c %a "$FZD_STATE_DIR/explorer") == 700 ]]
    [[ $(stat -c %a "$FZD_STATE_DIR/explorer/recents") == 600 ]]
    RECENT_PENDING=(); _recents_flush
    [[ ${#RECENTS[@]} == 3 && ${RECENTS[0]} == "$CUR/other" && ${RECENTS[1]} == "$FZD_TEST_UNUSUAL" ]]
  '
  [ "$status" -eq 0 ]
}

@test "recents discard stale paths and retain at most 25 unique directories" {
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_explorer
    for ((i=0;i<30;i++)); do mkdir -- "$CUR/dir-$i"; _recent_queue "$CUR/dir-$i"; done
    _recents_flush; [[ ${#RECENTS[@]} == 25 && ${RECENTS[0]} == "$CUR/dir-29" ]]
    rmdir -- "$CUR/dir-29"; _recents_flush
    [[ ${#RECENTS[@]} == 24 && ${RECENTS[0]} == "$CUR/dir-28" ]]
  '
  [ "$status" -eq 0 ]
}

@test "concurrent recent-directory updates retain each session without corrupting records" {
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_explorer
    pids=()
    for ((i=0;i<10;i++)); do
      mkdir -- "$CUR/dir-$i"
      (RECENT_PENDING=("$CUR/dir-$i"); _recents_flush) & pids+=("$!")
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    RECENT_PENDING=(); _recents_flush; [[ ${#RECENTS[@]} == 10 ]]
  '
  [ "$status" -eq 0 ]
}

@test "invalid state and symlinked state files fail without replacing unrelated data" {
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_explorer
    _state_lock; printf broken >"$FZD_EXPLORER_STATE/recents"; _state_unlock
    if _recents_flush; then exit 1; fi
    [[ $(cat "$FZD_EXPLORER_STATE/recents") == broken ]]
    rm -- "$FZD_EXPLORER_STATE/recents"
    printf untouched >"$CUR/target"
    ln -s "$CUR/target" "$FZD_EXPLORER_STATE/clipboard"
    if _state_lock; then exit 1; fi
    [[ $(cat "$CUR/target") == untouched ]]
  '
  [ "$status" -eq 0 ]
}
