#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "batch encoding matches GNU base64 for every non-NUL byte and alignment" {
  run bash -euo pipefail -c '
    source "$1"
    bytes=""
    for ((i=1; i<256; i++)); do
      printf -v oct "%03o" "$i"
      printf -v byte "%b" "\\$oct"
      bytes+=$byte
    done
    printf -v long "%8192s" x
    paths=("" a ab abc abcd "$bytes" "x$bytes" "xx$bytes" "$long" $'"'"'Unicode-é-雪\t\n\n'"'"')
    _b64_paths "${paths[@]}"
    [[ ${#B64_PATHS[@]} == ${#paths[@]} ]]
    for ((i=0; i<${#paths[@]}; i++)); do
      expected=$(printf %s "${paths[i]}" | base64 -w 0)
      [[ ${B64_PATHS[i]} == "$expected" ]]
    done
    _b64_paths
    [[ ${#B64_PATHS[@]} == 0 ]]
  ' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "one encoder handles a thousand local records without per-path execution" {
  export FZD_CODEC_REAL="$UTILITY_BIN/base64" FZD_CODEC_LOG="$BATS_TEST_TMPDIR/codec.log"
  cat >"$TEST_BIN/base64" <<'SH'
#!/usr/bin/env bash
printf 'called\n' >>"$FZD_CODEC_LOG"
exec "$FZD_CODEC_REAL" "$@"
SH
  chmod +x "$TEST_BIN/base64"
  run bash -euo pipefail -c '
    source "$1"; CUR=$2; c_dir=; c_file=; c_reset=
    DIRS=(); FILES=()
    for ((i=0; i<1000; i++)); do FILES+=("file-$i"); done
    build_lines
    [[ ${#LINES[@]} == 1001 ]]
  ' _ "$FZD_SCRIPT" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
  [ "$(wc -l <"$FZD_CODEC_LOG")" -eq 1 ]
}

@test "truncated encoder output fails without publishing partial path identities" {
  cat >"$TEST_BIN/base64" <<'SH'
#!/usr/bin/env bash
printf AAAA
exit 7
SH
  chmod +x "$TEST_BIN/base64"
  run --separate-stderr bash -euo pipefail -c '
    source "$1"
    if _b64_paths /first /second; then exit 2; fi
    [[ ${#B64_PATHS[@]} == 0 ]]
  ' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *'pathname encoding failed'* ]]
}

@test "encoder failure after complete output is still propagated" {
  export FZD_CODEC_REAL="$UTILITY_BIN/base64"
  cat >"$TEST_BIN/base64" <<'SH'
#!/usr/bin/env bash
"$FZD_CODEC_REAL" "$@"
exit 7
SH
  chmod +x "$TEST_BIN/base64"
  run --separate-stderr bash -euo pipefail -c '
    source "$1"
    if _b64_paths /first /second; then exit 2; fi
    [[ ${#B64_PATHS[@]} == 0 ]]
  ' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *'pathname encoding failed'* ]]
}
