# Phase 4A packaged performance evidence

Source application: frozen Phase 3.5 runtime at 026ad23, unchanged in this phase.
Package: source commit e848a484aa726800c0d487b1c6414b175a018b13.
See runtime.sha256 for the exact executable/module/package digests. Debian
changes only the Bash interpreter line; the benchmark verifies all remaining
runtime bytes and integration/module identity before executing measurements.

Command (no other test or container job running):

```bash
bash packaging/benchmark.sh .test-work/phase-four-a/artifacts/fzd_0.1.0~rc.1-1_all.deb \
  .test-work/phase-four-a/benchmarks 3
```

candidates/local/workload CSV and JSON retain three hyperfine measurements per
command after one warmup. The 24 terminal CSV files contain three alternating
source/package trials at each of 10, 100, 1,000 and 10,000 entries.
terminal-medians.csv summarizes every observed event. Kernel-clock resolution is
10 ms; zero observations mean below that resolution, not instantaneous work.

No application optimization or statistically significant speedup is claimed.
The [engineering report](../../../docs/phase-four-a.md) compares the paired
results and earlier Phase 3.5 measurements and explains remaining limits.
