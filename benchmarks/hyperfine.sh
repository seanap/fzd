#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$repo"
runs=${1:-5}
[[ "$runs" =~ ^[1-9][0-9]*$ ]] || exit 2
mkdir -p .test-work/results
bash benchmarks/workload.sh prepare
# Materialize historical code before timing, so Git/temp-file overhead does not
# bias the comparison against the working tree.
git show 4dabc1259eb6c9aad88fe57d19b5dfaf7124c8e6:fzd.sh >.test-work/benchmarks/audit-source.sh
hyperfine --warmup 1 --runs "$runs" --export-json .test-work/results/candidates-hyperfine.json --export-csv .test-work/results/candidates-hyperfine.csv \
  --parameter-list count 10,100,1000 \
  'bash benchmarks/candidates.sh BASELINE {count}' \
  'bash benchmarks/candidates.sh WORKTREE {count}'
hyperfine --warmup 1 --runs "$runs" --export-json .test-work/results/search-preview-hyperfine.json --export-csv .test-work/results/search-preview-hyperfine.csv \
  'bash benchmarks/workload.sh startup' \
  'bash benchmarks/workload.sh index' \
  'bash benchmarks/workload.sh query' \
  'bash benchmarks/workload.sh preview'
if bash benchmarks/workload.sh prepare-locate; then
  hyperfine --warmup 1 --runs "$runs" --export-json .test-work/results/locate-hyperfine.json --export-csv .test-work/results/locate-hyperfine.csv \
    'bash benchmarks/workload.sh query-locate'
fi
