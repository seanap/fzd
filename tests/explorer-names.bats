#!/usr/bin/env bats
load helpers/common
load helpers/explorer
setup() { setup_explorer_fixture; }

@test "a competing destination created during rename is not replaced" {
  printf original >"$FIXTURE_ROOT/old"
  cat >"$TEST_BIN/mv" <<'SH'
#!/bin/bash
if [[ $1 == -nT ]]; then printf competitor >"${@: -1}"; fi
exec /usr/bin/mv "$@"
SH
  chmod +x "$TEST_BIN/mv"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    if _rename_item "$CUR/old" new; then exit 1; fi
    [[ $(cat "$CUR/old") == original && $(cat "$CUR/new") == competitor ]]
  '
  [ "$status" -eq 0 ]
}

@test "name prompt codec roundtrips every non-NUL byte and keeps valid Unicode readable" {
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; bytes=""
    for ((i=1;i<256;i++)); do
      printf -v oct "%03o" "$i"; printf -v byte "%b" "\\$oct"; bytes+=$byte
    done
    _ui_encode_name "$bytes"; encoded=$REPLY
    _ui_decode_name "$encoded"; [[ $REPLY == "$bytes" ]]
    _ui_encode_name "é-雪-😀"; [[ $REPLY == "é-雪-😀" ]]
    for invalid in "\\c" "\\x00" "\\x0" "\\xz1" "\\"; do
      if _ui_decode_name "$invalid"; then exit 1; fi
    done
  '
  [ "$status" -eq 0 ]
}

@test "rename preserves exact name bytes and unchanged names perform no move" {
  export FZD_TEST_OLD=$'needle \'$(false)\t\n\377' FZD_TEST_NEW=$'renamed é 雪\a\b\n\n'
  printf payload >"$FIXTURE_ROOT/$FZD_TEST_OLD"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    old=$CUR/$FZD_TEST_OLD; inode=$(stat -c %i "$old")
    _rename_item "$old" "$FZD_TEST_OLD"; [[ $(stat -c %i "$old") == "$inode" ]]
    _rename_item "$old" "$FZD_TEST_NEW"
    [[ ! -e $old && $(cat "$CUR/$FZD_TEST_NEW") == payload ]]
    [[ $(stat -c %i "$CUR/$FZD_TEST_NEW") == "$inode" && $FZD_SELECT_NAME == "$FZD_TEST_NEW" ]]
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "directory rename rebases browser history recents clipboard and highlighted names" {
  mkdir -p "$FIXTURE_ROOT/old/child"
  printf payload >"$FIXTURE_ROOT/old/child/file"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    CUR=$root/old/child; _history_visit; _recents_flush
    _clipboard_set copy "$CUR/file"
    CUR=$root; _history_visit; RAW=$CUR/old; _history_remember
    _rename_item "$CUR/old" new
    [[ ${H_PATHS[1]} == "$root/new/child" && ${H_SELECTIONS[2]} == new ]]
    _state_lock; _clipboard_read; _recents_read; _state_unlock
    [[ $CLIP_PATH == "$root/new/child/file" ]]
    [[ " ${RAW_RECENTS[*]} " == *"$root/new/child"* ]]
    [[ ! -e $root/old && -f $root/new/child/file ]]
  '
  [ "$status" -eq 0 ]
}

@test "rename conflicts never replace files links or merge directories" {
  mkdir -p "$FIXTURE_ROOT/old" "$FIXTURE_ROOT/existing"
  printf original >"$FIXTURE_ROOT/old/file"
  printf competitor >"$FIXTURE_ROOT/existing/file"
  ln -s missing "$FIXTURE_ROOT/link"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    for target in existing link; do if _rename_item "$CUR/old" "$target"; then exit 1; fi; done
    [[ $(cat "$CUR/old/file") == original && $(cat "$CUR/existing/file") == competitor && -L $CUR/link ]]
  '
  [ "$status" -eq 0 ]
}

@test "mkdir accepts unusual bytes rejects invalid names and never replaces existing targets" {
  export FZD_TEST_NAME=$'new é \'$(false)\t\n\a\377\n'
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    for name in "" . .. a/b; do if _mkdir_item "$name"; then exit 1; fi; done
    _mkdir_item "$FZD_TEST_NAME"; [[ -d $CUR/$FZD_TEST_NAME && $FZD_SELECT_NAME == "$FZD_TEST_NAME" ]]
    if _mkdir_item "$FZD_TEST_NAME"; then exit 1; fi
    printf sentinel >"$CUR/existing"
    if _mkdir_item existing; then exit 1; fi
    [[ $(cat "$CUR/existing") == sentinel ]]
  '
  [ "$status" -eq 0 ]
}

@test "rename permission failures preserve names and state" {
  mkdir -p "$FIXTURE_ROOT/locked"
  printf payload >"$FIXTURE_ROOT/locked/old"
  chmod 500 "$FIXTURE_ROOT/locked"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; CUR=$CUR/locked
    _clipboard_set copy "$CUR/old"
    if _rename_item "$CUR/old" new; then exit 1; fi
    [[ -f $CUR/old && ! -e $CUR/new ]]
    _state_lock; _clipboard_read; _state_unlock; [[ $CLIP_PATH == "$CUR/old" ]]
  '
  chmod 700 "$FIXTURE_ROOT/locked"
  [ "$status" -eq 0 ]
}
