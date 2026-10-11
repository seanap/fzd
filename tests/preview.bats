#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

stub_preview_tools() {
  export FZD_PREVIEW_LOG="$BATS_TEST_TMPDIR/preview.log"
  cat >"$TEST_BIN/file" <<'SH'
#!/bin/sh
if [ "$2" = --mime-type ]; then
  printf '%s\n' "$FZD_TEST_MIME"
  exit "${FZD_TEST_MIME_STATUS:-0}"
fi
printf 'Binary description\n'
SH
  cat >"$TEST_BIN/bat" <<'SH'
#!/bin/sh
printf '%s\0' "$@" >"$FZD_PREVIEW_LOG"
printf 'Rendered text\n'
SH
  chmod +x "$TEST_BIN/file" "$TEST_BIN/bat"
}

@test "preview preserves text MIME policy renderer options and exact filename" {
  stub_preview_tools
  local path="$FIXTURE_ROOT/"$'quote\' tab\tend\n' mime expected actual encoded
  printf text >"$path"
  encoded=$(printf '%s' "$path" | base64 -w 0)
  export FZD_PREVIEW_MAX_LINES=37
  expected=$(printf '%s\0' --color=always --pager=never --line-range :37 -- "$path" | base64 -w 0)
  for mime in text/plain application/json application/xml application/x-sh application/javascript; do
    export FZD_TEST_MIME=$mime
    run bash "$FZD_SCRIPT" --_preview "$encoded"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Rendered text'* ]]
    actual=$(base64 -w 0 <"$FZD_PREVIEW_LOG")
    [ "$actual" = "$expected" ]
  done
}

@test "binary MIME and failed MIME detection retain binary previews" {
  stub_preview_tools
  local path="$FIXTURE_ROOT/binary" mime encoded
  printf '\000\001' >"$path"
  encoded=$(printf '%s' "$path" | base64 -w 0)
  for mime in application/octet-stream text/plain; do
    export FZD_TEST_MIME=$mime FZD_TEST_MIME_STATUS=0
    [[ "$mime" == text/plain ]] && export FZD_TEST_MIME_STATUS=7
    run bash "$FZD_SCRIPT" --_preview "$encoded"
    [ "$status" -eq 0 ]
    [[ "$output" == *'Binary description'* ]]
    [ ! -e "$FZD_PREVIEW_LOG" ]
  done
}

@test "directory preview retains tree colors depth exclusions and path bytes" {
  local path="$FIXTURE_ROOT/"$'dir\tend\n' encoded expected actual
  mkdir -p "$path"
  export FZD_PREVIEW_LOG="$BATS_TEST_TMPDIR/preview.log"
  export FZD_PREVIEW_DEPTH=3 FZD_EXCLUDES='.git,node_modules'
  cat >"$TEST_BIN/tree" <<'SH'
#!/bin/sh
printf '%s\0' "$@" >"$FZD_PREVIEW_LOG"
printf 'Tree render\n'
SH
  chmod +x "$TEST_BIN/tree"
  encoded=$(printf '%s' "$path" | base64 -w 0)
  run bash "$FZD_SCRIPT" --_preview "$encoded"
  [ "$status" -eq 0 ]
  [ "$output" = 'Tree render' ]
  expected=$(printf '%s\0' -a -C -L 3 -I '.git|node_modules' -- "$path" | base64 -w 0)
  actual=$(base64 -w 0 <"$FZD_PREVIEW_LOG")
  [ "$actual" = "$expected" ]
}
