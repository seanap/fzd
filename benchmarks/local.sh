#!/usr/bin/env bash
# Component measurements on a fixed real directory. Prepare outside timed runs.
# shellcheck disable=SC2034 # Variables are consumed by sourced listing functions.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
script=${1:-$repo/fzd.sh}
count=${2:-1000}
mode=${3:-full}
[[ "$count" =~ ^[1-9][0-9]*$ ]] || exit 2
export LC_ALL=C
root="$repo/.test-work/phase-two/local-$count"
if [[ "$mode" == prepare ]]; then
  mkdir -p "$root"
  for ((i = 0; i < count; i++)); do
    printf -v name 'file-%05d.txt' "$i"
    printf 'FZD preview marker %s\n' "$name" >"$root/$name"
  done
  exit 0
fi
[[ -d "$root" ]] || {
  echo 'Prepare the local workload first' >&2
  exit 2
}
# shellcheck disable=SC1090
source <(sed -n '/^normalize_path() {/,/^# ---- Build a one-shot index/{ /^# ---- Build a one-shot index/d; p; }' "$script")
CUR=$root
DELIM=$'\t'
declare -A LAST_CHILD=()
c_dir='' c_file='' c_reset=''
case "$mode" in
full)
  list_entries
  build_lines
  [[ ${#LINES[@]} == $((count + 1)) ]]
  ;;
enumerate)
  list_entries
  [[ ${#FILES[@]} == "$count" ]]
  ;;
sort)
  FILES=()
  for ((i = count; i > 0; i--)); do FILES+=("file-$i"); done
  mapfile -d '' -t FILES < <(printf '%s\0' "${FILES[@]}" | sort -zf)
  ;;
*) exit 2 ;;
esac
