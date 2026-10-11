#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ref=${1:-WORKTREE}
runs=${2:-3}
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || exit 2
printf 'revision,entries,run,seconds\n'
for count in 10 100 1000; do
  for ((iteration = 1; iteration <= runs; iteration++)); do
    start=$EPOCHREALTIME
    bash "$repo/benchmarks/candidates.sh" "$ref" "$count"
    end=$EPOCHREALTIME
    awk -v ref="$ref" -v n="$count" -v i="$iteration" -v start="$start" -v end="$end" \
      'BEGIN { printf "%s,%d,%d,%.6f\n", ref, n, i, end-start }'
  done
done
