#!/usr/bin/env bash
# Measure unchanged candidate preparation across revisions, without starting fzf.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ref=${1:-WORKTREE}
count=${2:-1000}
[[ "$count" =~ ^[1-9][0-9]*$ ]] || exit 2
export LC_ALL=C
if [[ "$ref" == WORKTREE ]]; then
  source_file="$repo/fzd.sh"
else
  mkdir -p "$repo/.test-work/benchmarks"
  source_file=$(mktemp "$repo/.test-work/benchmarks/source.XXXXXX")
  trap 'rm -f -- "$source_file"' EXIT
  git -C "$repo" show "$ref:fzd.sh" >"$source_file"
fi
# This historical adapter deliberately extracts the same marked function block
# from the audit revision. It does not execute either revision's startup code.
# shellcheck disable=SC1090
source <(sed -n '/^normalize_path() {/,/^# ---- Build a one-shot index/{ /^# ---- Build a one-shot index/d; p; }' "$source_file")
DELIM=$'\t'
declare -A LAST_CHILD=()
CUR=/benchmark
c_dir=
c_file=
c_reset=$'\033[0m'
DIRS=()
FILES=()
for ((i = 0; i < count; i++)); do
  FILES+=("entry-$i.txt")
done
build_lines
[[ ${#LINES[@]} == $((count + 1)) ]]
