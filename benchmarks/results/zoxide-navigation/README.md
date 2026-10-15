# Integrated navigation measurements — 2026-10-15

Linux x86_64 WSL development host, Bash 5.2, fzf 0.44.1, upstream zoxide 0.9.3.
Baseline: `8035d170eebff354d8b096fbf25399b51fe31427`, materialized from Git.
Feature timed runtime: `326062c17e2b31f0b50a1e3d620219279d2b1b08`.
Later test-fixture fixes and detection of disabled interactive hooks do not
change either timed path: no-argument exploration or noninteractive jumps.
Each revision uses its own actual shell integration with `FZD_BIN` pointing to
its matching executable. Source loading completes before the startup gate.
CSV source labels are normalized to `baseline/fzd.sh` and `feature/fzd.sh`;
all measured values are unchanged. Three trials at each size alternate order.

| Entries | Normal lf startup before | After | Right before / after | Left before / after |
| --- | ---: | ---: | ---: | ---: |
| 1,000 | 110 ms | 90 ms | 90 / 100 ms | 100 / 90 ms |
| 10,000 | 690 ms | 690 ms | 740 / 720 ms | 720 / 700 ms |

Screen observations use a monotonic kernel clock with 10 ms granularity.
The trials support no measurable startup regression; smaller differences are
within host/screen-observation variation. Global-open medians are 20 ms for both
revisions at both sizes. Exit includes batched learning (120 → 130 ms at 1,000;
130 → 130 ms at 10,000), along with existing screen restoration/state writes.

`direct-jumps.json` retains seven alternating groups of 150 warm Bash jumps,
using a private zoxide database and Python's monotonic clock. It includes query,
cd and learning, with one-time shell/source loading amortized. Median upstream
query/cd/add is 3.26 ms; `lf docker imm` is 3.51 ms (about 0.25 ms overhead).
No before-query timing is claimed: the baseline had no zoxide jump command.

Reproduce on an otherwise idle host, with tests/containers stopped:

```bash
bash benchmarks/navigation.sh .test-work/navigation-benchmark
FZD_BENCH_INTEGRATION="$PWD/shell/integration.sh" \
  bash benchmarks/terminal.sh "$PWD/fzd.sh" 1000 3
FZD_BENCH_INTEGRATION="$PWD/shell/integration.sh" \
  bash benchmarks/terminal.sh "$PWD/fzd.sh" 10000 3
```

For before/after trials, also materialize the baseline and set both integration
and executable paths to it. Alternate the revision order between trials. All
fixtures, sockets and zoxide data remain under ignored `.test-work` or a private
temporary directory. These are host measurements, not cross-machine guarantees.
