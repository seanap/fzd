#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "filename labels escape every non-NUL ASCII control byte and DEL" {
  run --separate-stderr bash -euo pipefail -c '
    source "$1"
    for ((code=1; code<=127; code++)); do
      ((code<32 || code==127)) || continue
      printf -v oct "%03o" "$code"
      printf -v byte "%b" "\\$oct"
      case "$code" in
        9) expected="\\t" ;;
        10) expected="\\n" ;;
        13) expected="\\r" ;;
        27) expected="\\e" ;;
        *) printf -v expected "\\\\x%02x" "$code" ;;
      esac
      _display_name "before${byte}after"
      [[ "$REPLY" == "before${expected}after" ]] || {
        printf "Unexpected display for byte %s: %q\n" "$code" "$REPLY" >&2
        exit 1
      }
    done
  ' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "filename display retains Unicode and distinguishes literal escapes from control bytes" {
  local name=$'é-雪-😀 \\x07\\n\\e\a\b\v\f\033\n\r\t\177'
  local expected='é-雪-😀 \\x07\\n\\e\x07\x08\x0b\x0c\e\n\r\t\x7f'
  run bash -euo pipefail -c '
    export LC_ALL=C.UTF-8
    source "$1"
    _display_name "$2"
    printf "%s" "$REPLY"
  ' _ "$FZD_SCRIPT" "$name"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

control_path_fixture() {
  local code oct byte name=needle
  for ((code = 1; code < 32; code++)); do
    printf -v oct '%03o' "$code"
    printf -v byte '%b' "\\$oct"
    name+=$byte
  done
  name+=$'\177-é-雪'
  CONTROL_PATH="$FIXTURE_ROOT/$name"
  printf text >"$CONTROL_PATH"
}

assert_printable_control_record() {
  assert_record_path "$CONTROL_PATH"
  local record label
  for record in "${lines[@]}"; do
    label=${record#*$'\t'}
    label=${label%$'\033[0m'}
    [[ "$label" != *[$'\001'-$'\037'$'\177']* ]]
  done
  [[ "$output" == *'\x07\x08\t\n'* ]]
  [[ "$output" == *'\x7f-é-雪'* ]]
}

@test "local candidate labels are printable while control-character path identities remain exact" {
  control_path_fixture
  run bash -euo pipefail -c '
    source "$1"; c_dir=; c_file=; c_reset=; CUR=$2
    list_entries; build_lines
    printf "%s\n" "${LINES[@]}"
  ' _ "$FZD_SCRIPT" "$FIXTURE_ROOT"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  assert_printable_control_record
}

@test "global candidate labels are printable while control-character path identities remain exact" {
  control_path_fixture
  run --separate-stderr bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "${#lines[@]}" -eq 1 ]
  assert_printable_control_record
}
