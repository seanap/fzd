#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repo"
mode=${1:-before}
runs=${2:-3}
[[ "$mode" == before || "$mode" == after ]] || exit 2
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || exit 2
work="$repo/.test-work/phase-two"
mkdir -p "$work"
if [[ "$mode" == before ]]; then
  git show 385868a:fzd.sh >"$work/phase-one.sh"
  chmod +x "$work/phase-one.sh"
  script="$work/phase-one.sh"
else
  script="$repo/fzd.sh"
fi
hyperfine --warmup 1 --runs "$runs" --export-json "$work/$mode-candidates.json" --export-csv "$work/$mode-candidates.csv" \
  --parameter-list count 10,100,1000,10000 \
  "bash benchmarks/candidates.sh '$script' {count}"
