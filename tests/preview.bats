#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

stub_tree_palette() {
  cat >"$TEST_BIN/tree" <<'SH'
#!/bin/sh
printf '%s' "${TREE_COLORS-${LS_COLORS-}}"
SH
  chmod +x "$TEST_BIN/tree"
}

@test "tree applies the list directory and file colors to its inherited palette" {
  stub_tree_palette
  export LS_COLORS='di=34:fi=37:ex=32:ln=36'
  export FZD_COLOR_DIR='#f9e2af' FZD_COLOR_FILE='#cdd6f4'
  run_palette_preview
  [ "$output" = 'di=38;2;249;226;175:fi=38;2;205;214;244:ex=32:ln=36' ]
}

@test "tree honors TREE_COLORS precedence and preserves unrelated entries" {
  stub_tree_palette
  export LS_COLORS='di=34:fi=37:ex=32' TREE_COLORS='ln=35:di=36:fi=0'
  export FZD_COLOR_DIR=010203
  run_palette_preview
  [ "$output" = 'ln=35:di=38;2;1;2;3:fi=0' ]
  [ "$TREE_COLORS" = 'ln=35:di=36:fi=0' ]
  [ "$LS_COLORS" = 'di=34:fi=37:ex=32' ]
}

@test "tree retains its palette without valid overrides and supports empty palettes" {
  stub_tree_palette
  export LS_COLORS='di=34:fi=37' TREE_COLORS='di=35:fi=0'
  export FZD_COLOR_DIR=invalid FZD_COLOR_FILE='#12345g'
  run_palette_preview
  [ "$output" = "$TREE_COLORS" ]
  export TREE_COLORS='' FZD_COLOR_DIR=010203 FZD_COLOR_FILE=040506
  run_palette_preview
  [ "$output" = 'di=38;2;1;2;3:fi=38;2;4;5;6' ]
}

@test "real tree renders configured directory and regular file colors" {
  [[ -x "$FZD_REAL_TREE" ]] || skip 'tree unavailable'
  ln -s "$FZD_REAL_TREE" "$TEST_BIN/tree"
  mkdir -p "$FIXTURE_ROOT/manilla-dir"
  printf text >"$FIXTURE_ROOT/plain-file"
  export FZD_COLOR_DIR='#f9e2af' FZD_COLOR_FILE='#cdd6f4'
  unset TREE_COLORS LS_COLORS NO_COLOR
  run_palette_preview
  [[ "$output" == *$'\033[38;2;249;226;175mmanilla-dir'* ]]
  [[ "$output" == *$'\033[38;2;205;214;244mplain-file'* ]]
}

stub_eza_palette() {
  cat >"$TEST_BIN/eza" <<'SH'
#!/bin/sh
printf '%s' "${LS_COLORS-}"
SH
  cat >"$TEST_BIN/vivid" <<'SH'
#!/bin/sh
printf 'ln=99:di=99:fi=99:ex=99'
SH
  chmod +x "$TEST_BIN/eza" "$TEST_BIN/vivid"
}

run_palette_preview() {
  local encoded
  encoded=$(printf '%s' "$FIXTURE_ROOT" | base64 -w 0)
  run --separate-stderr bash "$FZD_SCRIPT" --_preview "$encoded"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "eza preserves the inherited palette without explicit overrides even with vivid installed" {
  stub_eza_palette
  export LS_COLORS='ln=36:di=34:fi=37:ex=32'
  run_palette_preview
  [ "$output" = "$LS_COLORS" ]
  rm -- "$TEST_BIN/vivid"
  run_palette_preview
  [ "$output" = "$LS_COLORS" ]
}

@test "eza replaces only the requested directory color and retains separators" {
  stub_eza_palette
  export LS_COLORS='ln=36:di=34:fi=37:ex=32' FZD_COLOR_DIR='#0102fF'
  run_palette_preview
  [ "$output" = 'ln=36:di=38;2;1;2;255:fi=37:ex=32' ]
}

@test "eza replaces adjacent directory and file colors including palette endpoints" {
  stub_eza_palette
  export LS_COLORS='di=34:fi=37:ln=36:di=35:fi=0'
  export FZD_COLOR_DIR=010203 FZD_COLOR_FILE='#aBcDeF'
  run_palette_preview
  [ "$output" = 'di=38;2;1;2;3:fi=38;2;171;205;239:ln=36:di=38;2;1;2;3:fi=38;2;171;205;239' ]
}

@test "eza appends missing override entries and handles an empty inherited palette" {
  stub_eza_palette
  export LS_COLORS='ln=36:ex=32' FZD_COLOR_FILE=000000
  run_palette_preview
  [ "$output" = 'ln=36:ex=32:fi=38;2;0;0;0' ]
  unset LS_COLORS
  run_palette_preview
  [ "$output" = 'fi=38;2;0;0;0' ]
}

@test "eza retains escaped colons backslashes and empty palette entries" {
  stub_eza_palette
  export LS_COLORS=':*.odd\:di=34:ln=36::di=35:*.slash\\=37:' FZD_COLOR_DIR=010203
  run_palette_preview
  [ "$output" = ':*.odd\:di=34:ln=36::di=38;2;1;2;3:*.slash\\=37:' ]
}

@test "invalid eza color overrides retain the inherited entries" {
  stub_eza_palette
  export LS_COLORS='ln=36:di=34:fi=37:ex=32'
  export FZD_COLOR_DIR=zzzzzz FZD_COLOR_FILE='#12345g'
  run_palette_preview
  [ "$output" = "$LS_COLORS" ]
  export FZD_COLOR_FILE=010203
  run_palette_preview
  [ "$output" = 'ln=36:di=34:fi=38;2;1;2;3:ex=32' ]
}

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
