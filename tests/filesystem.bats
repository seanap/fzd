#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "sourcing exposes functions without configuration or filesystem side effects" {
  printf 'printf hit > %q\n' "$FIXTURE_ROOT/source-marker" >"$FZD_CONF_FILE"
  rm -f -- "$TEST_BIN/fzf"
  run bash -c 'before=$SHELLOPTS; source "$1"; [[ "$before" == "$SHELLOPTS" ]]; declare -F list_entries >/dev/null; printf loaded' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
  [ "$output" = loaded ]
  [ ! -e "$FIXTURE_ROOT/source-marker" ]
  [ ! -d "$XDG_STATE_HOME" ]
}

@test "local listing retains newlines hidden names and symlinks without duplicates" {
  local path="$FIXTURE_ROOT/"$'needle\nlast\n'
  printf text >"$path"
  printf text >"$FIXTURE_ROOT/.hidden"
  mkdir -p "$FIXTURE_ROOT/.hidden-dir"
  ln -s "$path" "$FIXTURE_ROOT/link"
  run bash -c 'source "$1"; CUR=$2; list_entries; printf "%s\0" "${FILES[@]}" | base64 | tr -d "\n"' _ "$FZD_SCRIPT" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
  local expected
  expected=$(printf '%s\0' .hidden link $'needle\nlast\n' | base64 | tr -d '\n')
  [ "$output" = "$expected" ]
}

@test "local records keep exact path bytes and escape display record separators" {
  local path="$FIXTURE_ROOT/"$'needle\ttab\nlast\n'
  printf text >"$path"
  run bash -c 'source "$1"; c_dir=; c_file=; c_reset=; CUR=$2; list_entries; build_lines; printf "%s\n" "${LINES[@]}"' _ "$FZD_SCRIPT" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  assert_record_path "$path"
  [[ "$output" == *'needle\ttab\nlast\n'* ]]
}

@test "navigation preserves directory names with trailing newlines" {
  local child="$FIXTURE_ROOT/"$'child\n'
  mkdir -p "$child"
  run bash -c 'source "$1"; CUR=$2; RAW=$3; enter_dir_from_raw; [[ "$CUR" == "$3" ]]; go_up; [[ "$CUR" == "$2" ]]; [[ "${LAST_CHILD[$CUR]}" == $'"'"'child\n'"'"' ]]' _ "$FZD_SCRIPT" "$FIXTURE_ROOT" "$child"
  [ "$status" -eq 0 ]
}

@test "Left at the filesystem root is a safe no-op under errexit" {
  run bash -ec 'source "$1"; CUR=/; go_up; [[ "$CUR" == / ]]' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
}

@test "inaccessible directories are safe no-op transitions" {
  mkdir -p "$FIXTURE_ROOT/locked"
  chmod 000 "$FIXTURE_ROOT/locked"
  run bash -c 'source "$1"; CUR=$2; RAW=$2/locked; enter_dir_from_raw; [[ "$CUR" == "$2" ]]' _ "$FZD_SCRIPT" "$FIXTURE_ROOT"
  chmod 700 "$FIXTURE_ROOT/locked"
  [ "$status" -eq 0 ]
}

@test "an empty directory still offers the current-directory Enter shortcut" {
  run bash -c 'source "$1"; c_dir=; c_file=; c_reset=; CUR=$2; list_entries; build_lines; [[ ${#LINES[@]} == 1 ]]; printf "%s" "${LINES[0]}"' _ "$FZD_SCRIPT" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\t../' ]]
}

@test "selection decoding retains every trailing newline byte" {
  local path="$FIXTURE_ROOT/"$'child\n\n'
  local encoded
  encoded=$(printf '%s' "$path" | base64 | tr -d '\n')
  run bash -c 'source "$1"; _decode_path "$2"; [[ "$REPLY" == "$3" ]]' _ "$FZD_SCRIPT" "$encoded" "$path"
  [ "$status" -eq 0 ]
}

@test "preview opens the exact filename including a trailing newline" {
  local path="$FIXTURE_ROOT/"$'needle\n'
  printf 'preview-unique-text\n' >"$path"
  local encoded
  encoded=$(printf '%s' "$path" | base64 | tr -d '\n')
  run bash "$FZD_SCRIPT" --_preview "$encoded"
  [ "$status" -eq 0 ]
  [[ "$output" == *preview-unique-text* ]]
}

@test "callback shell quoting preserves spaces quotes substitutions and newlines" {
  local value=$'space \'quote $(printf BAD) `printf BAD`\n'
  run bash -c 'source "$1"; quoted=$(_shell_quote "$2"); sh -c "printf %s $quoted"' _ "$FZD_SCRIPT" "$value"
  [ "$status" -eq 0 ]
  # Bats output trims the final newline; compare a base64 encoding instead.
  run bash -c 'source "$1"; quoted=$(_shell_quote "$2"); sh -c "printf %s $quoted" | base64 | tr -d "\n"' _ "$FZD_SCRIPT" "$value"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s' "$value" | base64 | tr -d '\n')" ]
}

@test "enumeration restores glob options and does not duplicate hidden entries" {
  mkdir -p "$FIXTURE_ROOT/.hidden-dir" "$FIXTURE_ROOT/visible-dir"
  printf text >"$FIXTURE_ROOT/.hidden"
  run bash -euo pipefail -c '
    source "$1"; CUR=$2
    for null in s u; do
      for dot in s u; do
        shopt -"$null" nullglob; shopt -"$dot" dotglob
        before=$(shopt -p nullglob dotglob || true)
        list_entries
        after=$(shopt -p nullglob dotglob || true)
        [[ "$before" == "$after" ]]
        [[ ${#DIRS[@]} == 2 && ${#FILES[@]} == 1 ]]
        [[ ${FILES[0]} == .hidden ]]
      done
    done
  ' _ "$FZD_SCRIPT" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
}
