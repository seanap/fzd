# Phase Two evidence

See [the engineering report](../../../docs/phase-two.md) and
[repeatable commands](../../README.md).

- `before-*`: application `385868a`. `after-*`: final application `ed8a615`.
  Local component code and the codec process/memory profiles were captured at
  `1917685`; that listing block is byte-identical at `ed8a615`.
- Candidate, local and workload JSON/CSV files: hyperfine, one warmup and three
  samples. These use hyperfine's monotonic timer and the inherited PATH.
- `*-terminal-SIZE.csv`: the final monotonic `/proc/uptime` main matrix, with
  10 ms clock resolution. Three samples except the single 10,000-entry baseline.
- `*-preview-terminal.csv`: separate three-sample 1,000-entry comparison with
  `FZD_BENCH_PREVIEW_MOVE=1`, including Down-arrow preview changes.
- `*-cache-terminal.csv`: separate three-sample cache comparison at 1,000 local
  files per directory and 2,001 global entries, using `FZD_BENCH_BACKEND=cache`.
- `terminal-summary.csv`: per-event summaries of the main matrix. The report
  uses medians for terminal observations and mean ± SD for hyperfine components.
- `profiles/profile-components.json`: initial Phase One profile. `WORKTREE`
  denotes the then-unchanged Phase One listing, not the final application.
  Its dummy encoder retains command substitutions.
- `profiles/escape-profile.json`: Phase One display-only/no-op controls, ten
  samples with two warmups, using the reference file.
- `profiles/query-profile.json`: initial batching checkpoint `7dcb516`, including
  raw fd/thread/find/file/bat commands, seven samples with one warmup.
- `profiles/linux-path-workload.json`: controlled five-sample PATH experiment
  comparing `385868a` and `1917685`; it is not a native Linux benchmark.
- `profiles/large-directory-preview.json`: five-sample directory preview at
  `1917685`, whose preview code is unchanged at the final application.
- `profiles/*processes.txt`: strace summaries for 1,000 candidate records.
  Syscall counts are used; traced timings are not performance claims.
- `profiles/*memory-*.txt`: single-run GNU time observations. The report uses
  maximum process RSS, not total process-tree memory or their elapsed values.

All fixtures and private locate databases live in the ignored Linux workspace.
No system index, installer, existing tmux session or home configuration is used.
Input sizes and command lines are retained in the artifacts. Host scheduling,
WSL filesystem bridges and warm caches can affect absolute times.
