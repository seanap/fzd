# Search performance

The current default is `cache`: prepare a fresh filename snapshot when global
discovery opens, then let fzf fuzzy-filter each keystroke in memory. Python 3
accelerates snapshot formatting when available; Bash remains the fallback.
Indexed `auto`/`locate` searches remain available for larger scopes.

These measurements were recorded on 2026-10-19 on a WSL2 x86_64 host, before the
documentation cleanup. Each terminal session used fresh application state and
warm OS caches. Exact source hashes, individual trials, observed ranges and the
original reports are in the [historical evidence archive](../../docs/validation/README.md#historical-development-evidence).

## Snapshot launch and keystrokes

The baseline is the pre-optimization runtime. Times measure a fresh
`lff needle-1` process through its first visible matching filename, using
fzf 0.44.1. Each cell has one warmup and three measured trials; values are
medians in milliseconds. The next key narrows three matches to one.

| Files | Baseline launch to first match | Optimized launch to first match | Optimized next key |
| ---: | ---: | ---: | ---: |
| 1,005 | 322.4 | 144.2 | 0.9 |
| 10,000 | 2,747.7 | 267.1 | 0.7 |
| 100,000 | 25,884.3 | 1,447.8 | 1.9 |

The fixture cap was raised to include every file. Normal installations use a
5,000-result snapshot cap and six-level depth, with configured roots, exclusions
and fd ignore rules. The cap applies before matching; deeper, ignored and
capped-out entries are outside that overlay. A complete 100,000-file snapshot
still costs roughly 1.5–2 seconds to open. Ordinary `lf` directory browsing
does not enumerate the global scope.

With the actual installed shell integration and configured host roots, five
fresh terminal sessions loaded 3,248 snapshot records. Median `lf` startup was
72.8 ms and Ctrl-F to a fully loaded global list was 211.0 ms. Typing `global`
filtered in 5.5 ms; the next `_` narrowed the matches in 2.2 ms. The fuzzy
subsequence `glbfrmtpy` found both `global_format.py` entries in 1.6 ms.

## Indexed lookup comparison

Indexed queries reload literal case-insensitive matches from plocate. They can
reach a first result sooner than preparing a complete large snapshot, while
retaining per-query process and reload costs. These fixtures contain 10,000 or
100,000 indexed files. Values are medians in milliseconds from one warmup and
seven measured trials per revision.

| fzf | Files | First typed query, baseline to optimized | One key, baseline to optimized | Optimized seeded launch |
| --- | ---: | ---: | ---: | ---: |
| 0.44.1 | 10,000 | 142.2 → 113.2 | 101.9 → 101.7 | 77.2 |
| 0.44.1 | 100,000 | 173.8 → 113.6 | 102.3 → 102.1 | 85.8 |
| 0.65.2 | 10,000 | 104.0 → 93.4 | 62.9 → 39.0 | 79.7 |
| 0.65.2 | 100,000 | 125.2 → 88.4 | 94.1 → 59.0 | 93.2 |

Forty before/after host query pairs, including warmups, returned identical path
identity sets. Selective `immich` and `docker` lookups completed in about 60 ms,
down from about 195 ms. Broad short queries retained their scoped scan; the
`co` query had no first-result improvement. Faster results in these comparisons
did not come from returning fewer eligible paths.

The Omarchy compatibility fixture resolved its palette once per optimized
session. At 10,000 files with fzf 0.65.2, seeded snapshot launch fell from
2,841.4 to 304.5 ms, with a 1.0 ms next key. This was a WSL fixture using a pinned
theme utility and palette, rather than a native desktop measurement.

## Reproduce

Use the [benchmark instructions](../README.md) for prerequisites, current
harnesses, private output directories and measurement limits. For the
first-result comparison, prepare the original baseline and run sequentially:

```bash
mkdir -p .test-work/first-result-baseline
git archive 7b60f6a fzd.sh lib shell/integration.sh | tar -xf - -C .test-work/first-result-baseline
python3 benchmarks/global-first-result.py "$PWD/.test-work/first-result-baseline/fzd.sh" .test-work/recheck-indexed 7
python3 benchmarks/global-first-result.py "$PWD/.test-work/first-result-baseline/fzd.sh" .test-work/recheck-cache 3 --backend cache --sizes 1005 10000 100000 --skip-host
```

`--fzf /absolute/path/to/fzf` selects another version; `--omarchy` adds the
pinned theme fixture. A rerun measures the current source, which includes later
default and portability changes; the archive identifies the original measured
candidates. Do not run benchmarks alongside tests, builds or containers.

These are warm-cache terminal-output observations on one host. They do not
measure cold boot, cold disk or physical screen paint, and the small trial
counts do not support percentile claims. The archive also preserves rejected
wall-clock experiments, clearly marked as excluded from performance conclusions.
