# First-use search performance

Measured 2026-10-19 on this WSL2 host. The comparison prioritizes opening the tool,
seeing a useful matching filename, and responding to the next individual key.
There is no resident FZD service or new persistent search cache.

**The old “instant” feeling is reproducible in the in-memory snapshot mode.**
The optimization makes that mode much cheaper to open. Indexed query reloads
remain useful for large scopes and quick one-off lookups, with measurable
per-query latency. Fuzzy matching itself was not the expensive part.

## Reproducing the v2.0 path

The tagged `v2.0.0` runtime was tested with `cache`, recreating the code path that
`auto` chooses when locate is absent. This verifies that path, not which tools
were actually present during the user's historical installation. The fixture
has 1,005 files and both revisions use fzf 0.44.1.

Launching `lff needle-1` to its first matching filename took **333.5 ms** in tagged v2.0.0 and **139.9 ms** in the final optimized source. Once open, one-key narrowing took **0.7 ms** and **1.4 ms**, respectively. Both reproduce the very fast in-memory response.

## Snapshot opening cost, including launch

Baseline here means the installed pre-optimization source, not the v2.0 tag.
These values measure `lff needle-1` from a fresh process to the actual visible
matching filename. Each session starts with empty private application state.
The single-key column measures narrowing three matches to one after loading.
All times are milliseconds; one warmup and three measured trials per cell.

| Files | Baseline launch → first match | Optimized launch → first match | Optimized one-key response |
| ---: | ---: | ---: | ---: |
| 1,005 | 322.4 | 144.2 | 0.9 |
| 10,000 | 2,747.7 | 267.1 | 0.7 |
| 100,000 | 25,884.3 | 1,447.8 | 1.9 |

The ordinary `lf` directory view remains independent of global enumeration.
Its ten-entry fixture opened in roughly 50–90 ms across the workflows, with
local filtering generally around 1–2 ms. No whole-filesystem snapshot runs just
because the user opens `lf`.

For `lf` followed by Ctrl-F, the optimized snapshot prompt appeared at about
131 / 259 / 1,677 ms for these sizes. On the 100,000-file case, initial fzf list
ingestion still added about 167 ms before the first filtered count completed.
The prompt and a fully loaded searchable list are distinct events; both are in
the raw data. After ingestion, the measured next key took about 2 ms.

The private result cap was raised to include every fixture file. The product's
normal snapshot cap is unchanged. Actual snapshots can omit deeper, ignored or
capped-out entries just as before; the formatter does not expand their scope.

## Indexed searches in the terminal

These use the unchanged `auto` policy, which chooses plocate on this host.
The local directory contains ten files; the separate global index contains
10,000 or 100,000 files. First query means typing `needle` into an initially
empty global overlay. One-key narrowing appends the final `1` to `needle-`.
The last column starts a new process with its query supplied via `lff`.
One warmup and seven measured trials per revision; milliseconds.

| fzf | Global files | First typed query, baseline → optimized | One key, baseline → optimized | Optimized `lff` launch → first match |
| --- | ---: | ---: | ---: | ---: |
| 0.44.1 | 10,000 | 142.2 → 113.2 | 101.9 → 101.7 | 77.2 |
| 0.44.1 | 100,000 | 173.8 → 113.6 | 102.3 → 102.1 | 85.8 |
| 0.65.2 | 10,000 | 104.0 → 93.4 | 62.9 → 39.0 | 79.7 |
| 0.65.2 | 100,000 | 125.2 → 88.4 | 94.1 → 59.0 | 93.2 |

The reload path does not achieve the snapshot's 1 ms response. In fzf 0.44.1,
reading and search events pass through a coordinator that can back off while
input is arriving; its configured maximum is 100 ms. That helps explain why a
fast backend alone does not make every external reload instantaneous.
See the pinned upstream [coordinator](https://github.com/junegunn/fzf/blob/0.44.1/src/core.go)
and [timing constants](https://github.com/junegunn/fzf/blob/0.44.1/src/constants.go).
This is not a universal 100 ms floor: observed timings vary by event and version.
The newer fzf was tested through its resolved absolute executable path; it was
not installed over the user's system fzf.

## Actual configured host roots

These are process/helper timings, not interactive terminal timings. The original
roots, exclusions and cap were retained. Each of the 40 before/after query pairs,
including warmups, asserts identical returned path identities as unordered sets.
No speedup comes from returning fewer files in these comparisons.

| Query / operation | Returned records | First record, baseline → optimized | All records, baseline → optimized |
| --- | ---: | ---: | ---: |
| `immich` | 3 | 186.9 → 53.0 | 195.4 → 59.7 |
| `docker` | 10 | 188.1 → 53.2 | 195.9 → 60.2 |
| `co` | 2,748 | 171.0 → 179.0 | 839.7 → 711.8 |
| `fzd` | 2,157 | 181.4 → 177.7 | 710.6 → 558.8 |
| fd snapshot | 3,208 | 78.9 → 73.6 | 1,029.3 → 139.4 |

The fd snapshot's full preparation cost matters for the current cache overlay,
which waits for preparation before launching its picker. Its early first record
is not equivalent to opening the overlay. The real host snapshot contained
3,208 entries, below its 5,000-entry cap.

The broader `co` query has no first-result improvement. Its result-set completion
is faster. A larger exploratory indexed probe regressed the broad `fzd` query;
that candidate was rejected. The final implementation keeps queries shorter
than four bytes on the scoped scan and limits longer-string probes to 129
candidates before falling back to the scoped scan. This is a performance probe,
not a replacement result cap; late true matches remain discoverable.

## Omarchy desktop fixture

This is a WSL compatibility workload using the existing pinned upstream theme
utility and Tokyo Night palette, not a measurement on the user's native PC.
It uses fzf 0.65.2, 10,000 global files and three measured trials per revision.

- Indexed mode: launch to the seeded match fell from **122.7 ms** to **95.0 ms**; the optimized next-key response was **57.7 ms**.

- Snapshot mode: launch to the seeded match fell from **2,841.4 ms** to **304.5 ms**; the optimized next-key response was **1.0 ms**.

The optimized sessions call the palette utility exactly once. The baseline's
normal indexed sequence calls it six times, and its seeded search twice.
Resolved entry colors and the existing controls are preserved.

## What changed

- Selective strings use scoped plocate globs that can use its index. Scope is
  present in the producer's query before visibility checks, preserving the WSL
  protection against unrelated Windows/network mounts. Short and broad queries
  retain the scoped scan. Overlapping roots are deduplicated.
- Common scope/exclusion policies are compiled once rather than checked through
  nested Bash loops for each result. Complex user exclusion syntax retains its
  original Bash behavior.
- Whole snapshots use an optional Python 3 standard-library formatter. Input is
  NUL-delimited; identities are the same base64 bytes; colors, escaping, symlinks,
  scope, cap and batches match the Bash fallback. Without Python, the installed
  helper, or supported simple exclusion syntax, the original formatter runs.
- Seeded global searches feed their first results directly to fzf, avoiding a
  separate startup reload. Query-change reloads remain available.
- Preview and global-data helpers reuse the parent session's resolved colors.
  Standalone helpers still resolve a palette when needed.
- Cancellation reaps active indexed producers. A failed producer cannot leak
  partial results before fallback; reaching the probe ceiling does not truncate
  the eligible result set.

No system database is rebuilt during search. Search settings, ignore rules,
depth, minimum query length, and normal result-cap defaults are unchanged.

## Assessment for quick lookups

For a few thousand eligible filenames, the optimized snapshot is a practical way
to recover the old fast-keystroke feel without the previous long preparation.
For very large scopes, a seeded indexed lookup gets a first result sooner than
preparing every filename. The 100,000-file complete snapshot still costs roughly
1.5–2 seconds to open, despite its substantial improvement; it should not be
advertised as instant startup.

Keep both choices. Use `cache` for in-memory fuzzy interaction within a suitable
scope; use indexed `auto`/`locate` for broad one-off discovery. The initial runtime
installation preserved `auto`. Following the user's subsequent request to enable
the recommended fast interaction, this host now explicitly selects `cache`.

## Installed host verification

### Default rollout after these measurements

Following the successful host verification below, new installations now select
`cache` by default, matching this host's fast in-memory fuzzy interaction. The
runtime without a config file also matches the shipped config's 5,000-result
cap, Linux roots, exclusions and six-level depth. Python 3 is now recommended by
both installer modes and the package metadata, so normal installs can use the
snapshot accelerator automatically. Existing user configs are preserved, and
explicit `auto`/`locate` selection remains available for larger search scopes.
The tables above retain their original explicit backend choices and source
hashes; these defaults do not change what was measured.

The final runtime and optional formatter were installed to this host's existing
user-local installation with dependency, shell-startup and configuration writes
disabled. `install.sh --verify` passed. The installed runtime/formatter match the
tested source byte-for-byte; that initial installation preserved `fzd.conf`,
`.bashrc` and `.zshrc`. An installed-path snapshot smoke test selected the
native formatter and matched source output for directories, normal files,
control-character names and a dangling symlink.

The subsequent host configuration change replaced only
`FZD_GLOBAL_BACKEND=auto` with `FZD_GLOBAL_BACKEND=cache` in
`/home/htpc/.config/fzd/fzd.conf`. Installer verification passed again. Five fresh
PTY sessions used the actual installed shell integration, runtime and host
configuration, with 3,248 snapshot records. Median ordinary `lf` startup was
72.8 ms; Ctrl-F to the fully loaded global count was 211.0 ms. Typing `global`
filtered in 5.5 ms; adding one `_` narrowed 31 matches to 21 in 2.2 ms. The fuzzy
subsequence `glbfrmtpy` found both `global_format.py` entries in 1.6 ms. These
measurements use warm OS caches and terminal output, without measuring physical
screen paint. [Host switch evidence and individual trials](../../../docs/validation/global-first-result/host-cache-switch.json).

## Validation and reproduction

The clean full suite passed 350 tests. After the final palette-only optimization,
66 relevant integration, real-terminal, formatter, native-backend, search-safety
and cancellation tests passed again. Static checks and Python syntax validation
also passed. The tests cover byte identities, unsafe-looking names, dangling
symlinks, literal metacharacters, producer failures, caps after filtering, late
matches beyond a saturated probe, descriptor closure, cancellation, and package
payload/lifecycle handling.

- [Validation evidence](../../../docs/validation/global-first-result/checks.json)
- [Full suite TAP](../../../docs/validation/global-first-result/full-tests.tap)
- [Final targeted TAP](../../../docs/validation/global-first-result/final-targeted-tests.tap)
- [All timing records](trials.json)
- [Medians and observed ranges](summary.json)
- [Versions, hashes and candidate provenance](environment.json)

Run sequentially on an otherwise idle host with fresh output directories:

```bash
mkdir -p .test-work/first-result-baseline
git archive 7b60f6a fzd.sh lib shell/integration.sh | tar -xf - -C .test-work/first-result-baseline
python3 benchmarks/global-first-result.py "$PWD/.test-work/first-result-baseline/fzd.sh" .test-work/recheck-indexed 7
python3 benchmarks/global-first-result.py "$PWD/.test-work/first-result-baseline/fzd.sh" .test-work/recheck-cache 3 --backend cache --sizes 1005 10000 100000 --skip-host
python3 benchmarks/global-first-result.py "$PWD/.test-work/first-result-baseline/fzd.sh" .test-work/recheck-theme 3 --omarchy --sizes 10000 --skip-host
```

`--fzf /absolute/path/to/fzf` selects another version. The tagged-v2.0 comparison
uses an archive of `v2.0.0` as its baseline and `--backend cache --sizes 1005`.
The runner builds only private fixture databases, outside the host search roots,
and reads the real index for host probes. It does not run system updatedb or
change the installed search configuration. Original PTY logs and exact timed
candidate copies remain under `.test-work/global-fast/`.

These are fresh-application-state, warm-OS-cache observations on this WSL2 host.
They are not cold-boot, cold-disk, native-Linux-PC, physical-screen-paint or p95
claims. Each summary includes all measured samples and observed ranges; small
sample counts limit precision. Exact source hashes identify incremental
candidates: the plain-cache matrix precedes query-only guard and palette changes
that do not run in those sessions; its formatter bytes match the final source.
The final runtime itself is measured in both Omarchy workflows and the v2.0
comparison. Rejected exploratory probes and the incorrectly resolved early fzf
run are retained privately and excluded from the published results.
