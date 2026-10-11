#!/usr/bin/env bats
load helpers/common
load helpers/explorer
load helpers/trash
setup() {
  FZD_TEST_REAL_GIO=$(command -v gio || true)
  export FZD_TEST_REAL_GIO
  setup_explorer_fixture
}

@test "missing Trash backend leaves data untouched without any permanent-delete fallback" {
  printf payload >"$FIXTURE_ROOT/item"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    if _trash_item "$CUR/item"; then exit 1; fi
    [[ -f $CUR/item && $FZD_STATUS == *"Trash unavailable"* ]]
  '
  [ "$status" -eq 0 ]
}

@test "Trash passes exact file directory and symlink arguments and never follows the link" {
  stub_trash_backend
  export FZD_TEST_NAME=$'é \'$(false)\t\n\a\b\n'
  printf payload >"$FIXTURE_ROOT/$FZD_TEST_NAME"
  printf sentinel >"$FIXTURE_ROOT/target"
  mkdir -p "$FIXTURE_ROOT/directory/child"
  ln -s "$FIXTURE_ROOT/target" "$FIXTURE_ROOT/link"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    for item in "$FZD_TEST_NAME" directory link; do
      _trash_item "$CUR/$item"
      [[ ! -e $CUR/$item && ! -L $CUR/$item ]]
    done
    [[ -f $FZD_TEST_TRASH/$FZD_TEST_NAME && -d $FZD_TEST_TRASH/directory/child && -L $FZD_TEST_TRASH/link ]]
    [[ $(cat "$CUR/target") == sentinel ]]
    mapfile -d "" -t args <"$FZD_TEST_TRASH_LOG"
    [[ ${#args[@]} == 3 && ${args[0]} == trash && ${args[1]} == -- && ${args[2]} == "$CUR/link" ]]
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "trashing a directory clears affected clipboard and prunes recents and browser history" {
  stub_trash_backend
  mkdir -p "$FIXTURE_ROOT/directory/child"
  printf payload >"$FIXTURE_ROOT/directory/child/item"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    CUR=$root/directory/child; _history_visit; _recents_flush
    _clipboard_set copy "$CUR/item"
    CUR=$root; _history_visit
    _trash_item "$CUR/directory"
    [[ ${H_PATHS[1]} == "" && ! -e $FZD_STATE_DIR/explorer/clipboard ]]
    _recents_flush; [[ ${#RECENTS[@]} == 1 && ${RECENTS[0]} == "$root" ]]
  '
  [ "$status" -eq 0 ]
}

@test "failed Trash operations retain source and clipboard and do not report success" {
  stub_trash_backend
  export FZD_TEST_TRASH_STATUS=42
  printf payload >"$FIXTURE_ROOT/item"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    _clipboard_set cut "$CUR/item"
    if _trash_item "$CUR/item"; then exit 1; fi
    [[ -f $CUR/item && -f $FZD_STATE_DIR/explorer/clipboard && $FZD_STATUS != *"Moved to Trash"* ]]
  '
  [ "$status" -eq 0 ]
}

@test "trash-put is used when gio is unavailable" {
  stub_trash_backend
  mv "$TEST_BIN/gio" "$TEST_BIN/trash-put"
  printf payload >"$FIXTURE_ROOT/item"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; _trash_item "$CUR/item"
    mapfile -d "" -t args <"$FZD_TEST_TRASH_LOG"
    [[ ${#args[@]} == 2 && ${args[0]} == -- && ${args[1]} == "$CUR/item" ]]
  '
  [ "$status" -eq 0 ]
}

@test "a changed item after confirmation is not trashed" {
  stub_trash_backend
  printf payload >"$FIXTURE_ROOT/item"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    _ui_confirm_trash() { printf changed-and-longer >"$1"; }
    if _explorer_action TRASH "$CUR/item"; then exit 1; fi
    [[ $(cat "$CUR/item") == changed-and-longer && ! -e $FZD_TEST_TRASH_LOG ]]
  '
  [ "$status" -eq 0 ]
}

@test "real gio uses an isolated XDG Trash with recoverable metadata" {
  [[ -x $FZD_TEST_REAL_GIO && -x $FZD_TEST_BWRAP ]] || skip 'real Trash integration needs gio and bubblewrap'
  ln -s "$FZD_TEST_REAL_GIO" "$TEST_BIN/gio"
  mkdir -p "$BATS_TEST_TMPDIR/home" "$BATS_TEST_TMPDIR/data"
  printf payload >"$FIXTURE_ROOT/item"
  run "$FZD_TEST_BWRAP" --unshare-user --unshare-pid --unshare-net --die-with-parent \
    --ro-bind / / --bind "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" \
    --setenv HOME "$BATS_TEST_TMPDIR/home" --setenv XDG_DATA_HOME "$BATS_TEST_TMPDIR/data" \
    --setenv GIO_USE_VFS local --unsetenv DBUS_SESSION_BUS_ADDRESS --proc /proc --dev /dev -- \
    bash -euo pipefail -c '
      source "$FZD_TEST_HELPER"; init_operations; _trash_item "$CUR/item"
      [[ ! -e $CUR/item && $(cat "$XDG_DATA_HOME/Trash/files/item") == payload ]]
      [[ -s $XDG_DATA_HOME/Trash/info/item.trashinfo ]]
    '
  [ "$status" -eq 0 ]
}
