#!/usr/bin/env bash
# Compare the frozen checkout with the extracted Debian payload on the same host.
set -euo pipefail
repo=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
package=$(realpath -e -- "${1:?Debian package required}")
output=$(realpath -m -- "${2:?fresh benchmark output directory required}")
runs=${3:-3}
[[ $runs =~ ^[1-9][0-9]*$ && ! -e $output ]] || exit 2
mkdir -p "$output"
dpkg-deb -x "$package" "$output/root"
app=$output/root/usr/bin/fzd
diff <(tail -n +2 "$repo/fzd.sh") <(tail -n +2 "$app")
for module in state operations ui; do cmp "$repo/lib/$module.bash" "$output/root/usr/share/fzd/lib/$module.bash"; done
cmp "$repo/lib/global_format.py" "$output/root/usr/share/fzd/lib/global_format.py"
cmp "$repo/shell/integration.sh" "$output/root/usr/share/fzd/integration.sh"
sha256sum "$package" "$app" "$repo/fzd.sh" "$output/root/usr/share/fzd/lib/"*.bash "$output/root/usr/share/fzd/lib/"*.py >"$output/runtime.sha256"
for count in 10 100 1000 10000; do bash "$repo/benchmarks/local.sh" "$app" "$count" prepare; done
for component in candidates local; do
  printf -v source_command 'bash %q %q {count}' "$repo/benchmarks/$component.sh" "$repo/fzd.sh"
  printf -v package_command 'bash %q %q {count}' "$repo/benchmarks/$component.sh" "$app"
  hyperfine --warmup 1 --runs "$runs" --export-json "$output/$component.json" --export-csv "$output/$component.csv" \
    --parameter-list count 10,100,1000,10000 "$source_command" "$package_command"
done
bash "$repo/benchmarks/workload.sh" prepare
bash "$repo/benchmarks/workload.sh" prepare-locate
printf -v source_command 'FZD_BENCH_SCRIPT=%q bash %q {workload}' "$repo/fzd.sh" "$repo/benchmarks/workload.sh"
printf -v package_command 'FZD_BENCH_SCRIPT=%q bash %q {workload}' "$app" "$repo/benchmarks/workload.sh"
hyperfine --warmup 1 --runs "$runs" --export-json "$output/workload.json" --export-csv "$output/workload.csv" \
  --parameter-list workload startup,index,query,query-locate,preview,preview-dir,preview-binary "$source_command" "$package_command"
for count in 10 100 1000 10000; do
  for ((iteration = 1; iteration <= runs; iteration++)); do
    phases=(source package)
    if ((iteration % 2 == 0)); then phases=(package source); fi
    for phase in "${phases[@]}"; do
      script=$repo/fzd.sh
      [[ $phase != package ]] || script=$app
      bash "$repo/benchmarks/terminal.sh" "$script" "$count" 1 >"$output/$phase-terminal-$count-$iteration.csv"
    done
  done
done
printf 'Comparative packaged benchmarks: %s\n' "$output"
