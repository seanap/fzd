#!/usr/bin/env bats
load helpers/common
load helpers/explorer
setup() { setup_explorer_fixture; }

@test "copy persists across sessions and preserves unusual filenames contents and permissions" {
  export FZD_TEST_ITEM="$FIXTURE_ROOT/"$'é 雪 \'$(false)`false`\t\n\a\b\n'
  printf payload >"$FZD_TEST_ITEM"
  chmod 751 "$FZD_TEST_ITEM"
  mkdir -p "$FIXTURE_ROOT/dest"
  run bash -euo pipefail -c 'source "$FZD_TEST_HELPER"; init_operations; _clipboard_set copy "$FZD_TEST_ITEM"'
  [ "$status" -eq 0 ]
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; CUR=$CUR/dest; _clipboard_paste
    target=$CUR/${FZD_TEST_ITEM##*/}
    cmp "$FZD_TEST_ITEM" "$target"
    [[ $(stat -c %a "$target") == 751 ]]
    [[ -f $FZD_STATE_DIR/explorer/clipboard ]]
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "recursive copy preserves directory permissions hardlinks and symlinks without touching targets" {
  mkdir -p "$FIXTURE_ROOT/source/nested" "$FIXTURE_ROOT/dest"
  printf payload >"$FIXTURE_ROOT/source/nested/file"
  printf outside >"$FIXTURE_ROOT/outside"
  ln "$FIXTURE_ROOT/source/nested/file" "$FIXTURE_ROOT/source/hardlink"
  ln -s "$FIXTURE_ROOT/outside" "$FIXTURE_ROOT/source/link"
  ln -s missing "$FIXTURE_ROOT/source/dangling"
  chmod 711 "$FIXTURE_ROOT/source/nested"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    _clipboard_set copy "$CUR/source"; CUR=$CUR/dest; _clipboard_paste
    [[ $(cat "$CUR/source/nested/file") == payload ]]
    [[ $(stat -c %a "$CUR/source/nested") == 711 ]]
    [[ "$CUR/source/hardlink" -ef "$CUR/source/nested/file" ]]
    [[ ! "$CUR/source/hardlink" -ef "$root/source/hardlink" ]]
    [[ $(readlink "$CUR/source/link") == "$root/outside" && -L $CUR/source/dangling ]]
    [[ $(cat "$root/outside") == outside ]]
  '
  [ "$status" -eq 0 ]
}

@test "cut only records intent then successful paste moves and clears its clipboard" {
  mkdir -p "$FIXTURE_ROOT/source/child" "$FIXTURE_ROOT/dest"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    _recent_queue "$CUR/source/child"; _recents_flush
    _clipboard_set cut "$CUR/source"; [[ -d $CUR/source/child ]]
    CUR=$root/dest; _clipboard_paste
    [[ ! -e $root/source && -d $CUR/source/child ]]
    [[ ! -e $FZD_STATE_DIR/explorer/clipboard ]]
    _recents_flush; [[ ${RECENTS[0]} == "$CUR/source/child" ]]
  '
  [ "$status" -eq 0 ]
}

@test "paste refuses its original location and directory descendants including symlink aliases" {
  mkdir -p "$FIXTURE_ROOT/source/child"
  ln -s "$FIXTURE_ROOT/source/child" "$FIXTURE_ROOT/alias"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    for operation in copy cut; do
      CUR=$root; _clipboard_set "$operation" "$CUR/source"
      if _clipboard_paste; then exit 1; fi
      CUR=$root/alias
      if _clipboard_paste; then exit 1; fi
      [[ -d $root/source/child && ! -e $CUR/source ]]
    done
  '
  [ "$status" -eq 0 ]
}

@test "dangling symlinks can be listed copied and moved as links" {
  ln -s missing "$FIXTURE_ROOT/dangling"
  mkdir -p "$FIXTURE_ROOT/copy" "$FIXTURE_ROOT/move"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    list_entries; [[ ${FILES[0]} == dangling ]]
    _clipboard_set copy "$root/dangling"; CUR=$root/copy; _clipboard_paste
    [[ -L $CUR/dangling && $(readlink "$CUR/dangling") == missing ]]
    CUR=$root; _clipboard_set cut "$root/dangling"; CUR=$root/move; _clipboard_paste
    [[ -L $CUR/dangling && ! -L $root/dangling ]]
  '
  [ "$status" -eq 0 ]
}

@test "existing destination files directories and symlinks are never replaced or merged" {
  mkdir -p "$FIXTURE_ROOT/source" "$FIXTURE_ROOT/dest/source"
  printf payload >"$FIXTURE_ROOT/source/file"
  printf competitor >"$FIXTURE_ROOT/dest/source/existing"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    _clipboard_set copy "$root/source"; CUR=$root/dest
    if _clipboard_paste; then exit 1; fi
    [[ $(cat "$CUR/source/existing") == competitor && ! -e $CUR/source/file ]]
    _clipboard_set copy "$root/source/file" global
    ln -s "$root/source/file" "$CUR/file"
    if _clipboard_paste; then exit 1; fi
    [[ -L $CUR/file && $(cat "$root/source/file") == payload ]]
  '
  [ "$status" -eq 0 ]
}

@test "missing clipboard sources and synthetic navigation entries fail safely" {
  printf payload >"$FIXTURE_ROOT/item"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    _parent_path "$CUR"; parent=$REPLY
    if _clipboard_set cut "$parent"; then exit 1; fi
    [[ ! -e $FZD_STATE_DIR/explorer/clipboard ]]
    _clipboard_set copy "$CUR/item"; rm -- "$CUR/item"
    if _clipboard_paste; then exit 1; fi
    [[ -e $FZD_STATE_DIR/explorer/clipboard ]]
  '
  [ "$status" -eq 0 ]
}

@test "failed copying cleans private staging while preserving the source and clipboard" {
  printf '#!/bin/sh\nexit 42\n' >"$TEST_BIN/cp"
  chmod +x "$TEST_BIN/cp"
  printf payload >"$FIXTURE_ROOT/item"
  mkdir -p "$FIXTURE_ROOT/dest"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    _clipboard_set copy "$CUR/item"; CUR=$CUR/dest
    if _clipboard_paste; then exit 1; fi
    [[ $(cat "$root/item") == payload && -e $FZD_STATE_DIR/explorer/clipboard ]]
    shopt -s nullglob; staging=("$CUR"/.fzd-copy.*); [[ ${#staging[@]} == 0 ]]
  '
  [ "$status" -eq 0 ]
}

@test "a destination appearing during atomic copy publication is not overwritten or reported successful" {
  cat >"$TEST_BIN/mv" <<'SH'
#!/bin/bash
if [[ $1 == -nT ]]; then printf competitor >"${@: -1}"; fi
exec /usr/bin/mv "$@"
SH
  chmod +x "$TEST_BIN/mv"
  printf payload >"$FIXTURE_ROOT/item"
  mkdir -p "$FIXTURE_ROOT/dest"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    _clipboard_set copy "$CUR/item"; CUR=$CUR/dest
    if _clipboard_paste; then exit 1; fi
    [[ $(cat "$CUR/item") == competitor && $(cat "$root/item") == payload ]]
    [[ -e $FZD_STATE_DIR/explorer/clipboard ]]
  '
  [ "$status" -eq 0 ]
}

@test "permission failures preserve cut sources and allow retry" {
  printf payload >"$FIXTURE_ROOT/item"
  mkdir -p "$FIXTURE_ROOT/locked"
  chmod 500 "$FIXTURE_ROOT/locked"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; root=$CUR
    _clipboard_set cut "$CUR/item"; CUR=$CUR/locked
    if _clipboard_paste; then exit 1; fi
    [[ -f $root/item && -e $FZD_STATE_DIR/explorer/clipboard ]]
    chmod 700 -- "$CUR"; _clipboard_paste; [[ -f $CUR/item && ! -e $root/item ]]
  '
  chmod 700 "$FIXTURE_ROOT/locked"
  [ "$status" -eq 0 ]
}

@test "concurrent clipboard writers publish complete private records" {
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations; pids=()
    for ((i=0;i<8;i++)); do
      printf payload >"$CUR/item-$i"
      (_clipboard_set copy "$CUR/item-$i") & pids+=("$!")
    done
    for pid in "${pids[@]}"; do wait "$pid"; done
    _state_lock; _clipboard_read
    [[ $CLIP_OP == copy && -f $CLIP_PATH ]]
    [[ $(stat -c %a "$FZD_EXPLORER_STATE/clipboard") == 600 ]]
    _state_unlock
  '
  [ "$status" -eq 0 ]
}

@test "cut paste works across an isolated tmpfs boundary" {
  [[ -x $FZD_TEST_BWRAP ]] || skip 'cross-filesystem test needs bubblewrap/user namespaces'
  mkdir -p "$BATS_TEST_TMPDIR/otherfs"
  printf payload >"$FIXTURE_ROOT/item"
  export FZD_TEST_OTHERFS="$BATS_TEST_TMPDIR/otherfs"
  run "$FZD_TEST_BWRAP" --unshare-user --unshare-pid --unshare-net --die-with-parent \
    --ro-bind / / --bind "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" \
    --tmpfs "$FZD_TEST_OTHERFS" --proc /proc --dev /dev -- \
    bash -euo pipefail -c '
      source "$FZD_TEST_HELPER"; init_operations; root=$CUR
      _clipboard_set cut "$CUR/item"; CUR=$FZD_TEST_OTHERFS; _clipboard_paste
      [[ $(cat "$CUR/item") == payload && ! -e $root/item ]]
    '
  [ "$status" -eq 0 ]
}

@test "termination during copying cleans private staging and preserves clipboard and source" {
  cat >"$TEST_BIN/cp" <<'SH'
#!/bin/bash
printf partial >"${@: -1}"
kill -TERM "$PPID"
exit 1
SH
  chmod +x "$TEST_BIN/cp"
  printf payload >"$FIXTURE_ROOT/item"
  mkdir -p "$FIXTURE_ROOT/dest"
  run bash -euo pipefail -c '
    source "$FZD_TEST_HELPER"; init_operations
    trap _cleanup EXIT; trap "exit 143" TERM
    _clipboard_set copy "$CUR/item"; CUR=$CUR/dest; _clipboard_paste
  '
  [ "$status" -eq 143 ]
  [ "$(cat "$FIXTURE_ROOT/item")" = payload ]
  [ -f "$XDG_STATE_HOME/fzd/explorer/clipboard" ]
  run find "$FIXTURE_ROOT/dest" -mindepth 1
  [ -z "$output" ]
}
