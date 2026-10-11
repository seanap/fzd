# Phase Three preservation measurements

Collected on the same Ubuntu 24.04 WSL2 host and inherited PATH as Phase Two.
`before` materializes the protected `d3315f8:fzd.sh`; component `after` uses the
checkout, and terminal `after` uses an actual disposable user installation.
All three application copies have SHA256
`57b3ae329e307827b7db06d6909060acf3549923261127bc65955c5d42bd2860`.
The application script was unchanged, so small timing differences are not optimization
claims.

Component files contain one warmup and three measured runs at 10, 100, 1,000 and
10,000 entries, plus startup, global index/query, private locate and previews.
JSON retains individual samples and hyperfine uncertainty. Very short components
are close to hyperfine's shell-calibration limit; several trials reported
outliers. Fixtures are prepared before timing. Tests and benchmark suites were
not intentionally run concurrently.

An initial global-index pair was 159.8 vs 171.9 ms. Because the application bytes
are identical, this was checked again with two warmups and ten runs against the
installed executable: 172.2 ± 6.1 vs 178.5 ± 12.6 ms (`index-repeat.json`), with
overlapping sample ranges. This does not establish a code-induced regression.
The protected Phase Two historical index mean was 172.5 ms.

Terminal CSVs use the existing real tmux/fzf harness and `/proc/uptime` monotonic
clock, with **10 ms resolution** and bounded screen polling. Each event has three
samples for both revisions, including 10,000 entries. `terminal-summary.csv`
contains event medians and ranges. The main matrix selects the live backend;
the separate cache overlay scans 2,001 candidates before rendering. Preview-move
trials use a real Down-arrow selection change. Zero milliseconds means below
the clock resolution, not zero work.

At 1,000 entries, installed startup/Right/Left medians are 90/100/90 ms, versus
90/90/90 ms for the same Phase Two code. Cached overlay opening is 360 vs 350 ms;
direct preview movement is 70 ms in both versions. No primary-screen gaps were
observed at the harness's polling resolution. This does not rule out briefer
flashes. See [the engineering report](../../../docs/phase-three.md) for tables.

These measurements cover the installed application process; installed parent
shell functions are additionally tested end-to-end in real Bash/zsh terminals.
Shell integration performs no external processes when sourced. The runtime's
deterministic encoder process-budget guards continue to pass.

Reproduce component comparisons with the commands in
[benchmarks/README.md](../../README.md), then run `terminal.sh` sequentially against
the materialized baseline and a disposable installed executable. No package
transaction, installer, system locate scan or theme download is timed.
