# Installation experience: startup and previews

Baseline: `68686cf` (v2.0). Candidate: `262198e`; the application measured at
`d712fe6` is unchanged by the final package transaction fix. Linux x86_64 under
WSL2, kernel 6.6.87.2-microsoft-standard-WSL2, fzf 0.44.1, bat 0.24.0 and tree
2.1.1. eza is unavailable on this host, so these observations cover existing
preview fallbacks. No tests, builds or containers ran during measurement.

The direct PTY harness uses the real `lf` wrapper/fzf with a 120×32 terminal,
a private home per session, Python's monotonic clock, alternating revision order,
and one warmup followed by 15 measured sessions per revision and size. There are
90 measured sessions and six warmups. The initial list count must be complete.
First preview includes entering a two-match query; next preview measures Down to
the second text file. These are response observations, not physical display times.

Medians, milliseconds:

| Entries | Startup before → after | First preview before → after | Next preview before → after | Exit before → after |
| --- | --- | --- | --- | --- |
| 10 | 146.5 → 140.6 | 112.3 → 100.1 | 65.8 → 63.2 | 121.9 → 121.7 |
| 1,000 | 224.1 → 223.1 | 115.7 → 101.6 | 68.0 → 64.6 | 121.8 → 122.7 |
| 10,000 | 835.7 → 832.1 | 131.9 → 142.8 | 67.7 → 62.9 | 126.2 → 124.5 |

Startup has no observed median regression. Next-preview medians are also stable
or lower. The 10,000-entry first-preview median is 10.9 ms higher; individual
observations vary substantially, so this is not evidence of a general speedup
or a guarantee of identical performance on other hosts. Native Linux and real
eza/icon performance still require the hosted/distribution validation environment.

Separate hyperfine component observations include the helper process and renderer,
three warmups and 20 runs, with output captured (mean ± standard deviation, ms):

| Renderer workload | Baseline | Candidate |
| --- | --- | --- |
| Text preview, bat | 75.5 ± 21.9 | 69.2 ± 9.9 |
| Directory preview, tree | 52.8 ± 4.7 | 45.6 ± 8.1 |

Captured previews no longer initialize unused FZD storage. Normal browsing retains
runtime validation and private temporary sessions. Candidate serialization and
navigation process-budget regressions remain covered by the existing suite.

Files: [all PTY samples](trials.json), [medians](summary.json),
[hyperfine samples](preview-components.json), [versions and source hashes](environment.json).
The raw terminal streams and initial development run remain under
`.test-work/two-tier/` in this workspace. Reproduction commands are in
[the benchmark guide](../../README.md).
