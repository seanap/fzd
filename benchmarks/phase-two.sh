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
for count in 10 100 1000 10000; do
  bash benchmarks/local.sh "$script" "$count" prepare
done
for component in full enumerate sort; do
  hyperfine --warmup 1 --runs "$runs" --export-json "$work/$mode-local-$component.json" --export-csv "$work/$mode-local-$component.csv" \
    --parameter-list count 10,100,1000,10000 \
    "bash benchmarks/local.sh '$script' {count} '$component'"
done
bash benchmarks/workload.sh prepare
bash benchmarks/workload.sh prepare-locate
hyperfine --warmup 1 --runs "$runs" --export-json "$work/$mode-workload.json" --export-csv "$work/$mode-workload.csv" \
  --parameter-list workload startup,index,query,query-locate,preview,preview-dir,preview-binary \
  "FZD_BENCH_SCRIPT='$script' bash benchmarks/workload.sh {workload}"
