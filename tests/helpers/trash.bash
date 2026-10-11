# shellcheck shell=bash
stub_trash_backend() {
  export FZD_TEST_TRASH="$BATS_TEST_TMPDIR/controlled-trash"
  export FZD_TEST_TRASH_LOG="$BATS_TEST_TMPDIR/trash-arguments"
  mkdir -p "$FZD_TEST_TRASH"
  cat >"$TEST_BIN/gio" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$FZD_TEST_TRASH_LOG"
[[ ${FZD_TEST_TRASH_STATUS:-0} == 0 ]] || exit "$FZD_TEST_TRASH_STATUS"
source=${@: -1}
exec /usr/bin/mv -nT -- "$source" "$FZD_TEST_TRASH/${source##*/}"
SH
  chmod +x "$TEST_BIN/gio"
}
