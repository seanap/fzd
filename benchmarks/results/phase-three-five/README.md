# Explorer measurements

Date: 2026-10-11. Ubuntu 24.04.5 WSL2, Bash 5.2.21, fzf 0.44.1,
hyperfine 1.18.0, tmux 3.4. Linux checkout `/home/htpc/projects/fzd`,
branch `revamp/audit`. No concurrent tests or package operations during timing.

- Baseline: `e73b22d`, Phase Three plus reviewed palette/display fixes.
- Completed Explorer runtime: `076a0f7`; checksums are in `runtime.sha256`.
- Pre-optimization Explorer runtime: `fbc6c39`.
- Components: one warmup, three measured runs per command. JSON retains
  individual samples, CPU times and exit codes; CSV contains summary statistics.
- PTY: 120×32, monotonic `/proc/uptime`, 10 ms clock resolution and 5 ms polling.
  Values of zero mean below the observation resolution. Samples include terminal
  observation/polling overhead and are warm-cache WSL measurements.
- Components count ordinary file candidates plus the synthetic navigation row;
  PTY roots also contain one navigable child. Workload/index fixtures contain
  1,000 files in ten directories. No system locate database is used.

## File groups

| Prefix | Revision and purpose |
| --- | --- |
| `before-{candidates,local-*,workload}` | Original component baseline, e73b22d |
| `after-{candidates,local-*,workload}` | Final component matrix, 076a0f7 |
| `pre-optimization-after-{candidates,local-*,workload}` | Earlier Explorer component matrix, fbc6c39 |
| `before-terminal-*`, `after-terminal-*` | Final consecutive baseline/Explorer batches, three runs per size |
| `first-before-terminal-*`, `first-after-terminal-*` | Initial baseline and fbc6c39 runs; retained to show the timing variation that triggered investigation |
| `pre-optimization-before-terminal-*`, `pre-optimization-after-terminal-*` | Consecutive e73b22d/fbc6c39 repeat, three runs per size |
| `alternating-{before,after}-{size}-{pair}` | Final order-balanced check at 1,000 and 10,000 entries, six samples per revision; odd pairs baseline first, even pairs Explorer first |
| `selection-profile.*` | Five-run formatting control: fbc6c39 against the same source with only its per-file highlight condition removed |
| `renameat2.txt` | Actual no-replace rename syscall observed on an isolated fixture with GNU coreutils 9.4 |
| `fzf-probe-pty.txt` | Old and new position probes both succeed in a real terminal on both supported fzf versions |

The report uses the final three-run PTY matrix for 10/100 entries and the larger,
order-balanced sample for 1,000/10,000. Earlier observations are retained rather
than discarded. This is a small sample on one WSL machine; overlapping ranges,
outliers and short-command calibration limits do not establish universal latency
guarantees or a causal speedup for unchanged preview/search code.

The selection control measured means of 392.9 versus 372.3 ms at 10,000 entries
(standard deviations 19.8 and 18.9 ms). It motivated skipping unnecessary file
highlight work during ordinary navigation. It is deliberately not a functional
alternative application. To reproduce the control, materialize fbc6c39 and
remove only the one line beginning `if [[ -n "$want_child" && "$f"` inside
`build_lines`; run each through `benchmarks/candidates.sh ... 10000`.

Reproduce the primary matrices with the commands in
[the benchmark guide](../../README.md). For the balanced check, run each revision
with `benchmarks/terminal.sh SCRIPT SIZE 1` six times, alternating which revision
goes first. Do not run benchmarks alongside tests. See
[the report](../../../docs/phase-three-five.md) for interpretation and limits.
