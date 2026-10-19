# Global search choices: measurements on the installed host

These measurements precede the first-result optimizations and optional snapshot
formatter. They retain the recorded source hashes and describe that baseline;
rerunning the harness against the updated source will produce different timings.

Measured 2026-10-19 on this WSL2 host, with fzf 0.44.1, fdfind 9.0.0,
plocate 1.1.19, and the current source executable. The installed executable
is byte-identical to the measured source. No application behavior, user
configuration, or system database was changed.

**The experiments do not support trading fuzzy matching for speed.** On an
already loaded list of 100,000 filenames, both fuzzy and exact matching responded
in roughly 2–7 ms for the tested query replacements. The substantial costs are
collecting/preparing the list and running a new external search for each query.

## What the available modes actually do

| Mode | Filename source | Matching | When work happens | Freshness and coverage |
| --- | --- | --- | --- | --- |
| `cache` | Fresh fd/find snapshot each time the overlay opens | fzf fuzzy matching in memory | Prepare the whole snapshot before opening; filter it while typing | Current when opened; constrained by depth, exclusions, ignore rules, and snapshot cap |
| `live` | fd/find search on each query | Literal case-insensitive substring | Search and format results for each query | Current filesystem; same depth/exclusion rules; fd honors ignore files |
| `locate` | plocate/locate database on each query | Literal case-insensitive substring | Query database, validate paths, format results, reload fzf | New files require indexing; existing indexed results can include deeper and ignored paths |
| `auto` | Chooses `locate` when the tool exists, otherwise `cache` | Depends on selected mode | Depends on selected mode | Installing plocate changes both acquisition and matching behavior |

fd/find enumerate filenames; fzf performs the fuzzy matching. plocate could also
feed a fuzzy snapshot. These are independent choices. Current locate/live modes
explicitly disable fzf's matcher. They have a two-character minimum; the cache
matcher does not apply that minimum.

The `cache` name does **not** mean a persistent cache reused across launches:
the current implementation rebuilds the list whenever the overlay opens.

## Actual host, configured roots

The measured configuration searches `/etc /opt /srv /home/htpc`, with maximum
depth 6, maximum results 5,000, and the existing exclusions. Its fd snapshot
contained **3,201 records**; the 5,000-record cap was not reached in this run.
Building that snapshot took **724 ms** (median).

These are backend/helper timings, including a new process per query, but
excluding the interactive terminal. Cached fzf controls also start a fresh fzf
process and parse the snapshot every time; the persistent UI measurements below
better represent typing in an open overlay.

| Query | Live fd helper | Current plocate helper | Cached fuzzy control | Live / locate / cached-fuzzy matches |
| --- | ---: | ---: | ---: | --- |
| `immich` | 59 ms | 156 ms | 10 ms | 0 / 3 / 0 |
| `docker` | 89 ms | 205 ms | 16 ms | 0 / 10 / 0 |
| `co` | 160 ms | 748 ms | 10 ms | 502 / 2,748 / 813 |
| `imch` | 58 ms | 147 ms | 11 ms | 0 / 0 / 3 |

**These columns search different candidate sets.** A faster empty result is not
evidence of an equivalent successful search. The fuzzy `imch` matches do not
rescue the absent `immich` candidates: searching that snapshot for `immich`
returns zero.

The host coverage audit found:

| fd configuration | Indexed `immich` matches recovered | Indexed `docker` matches recovered |
| --- | ---: | ---: |
| Current: depth 6, respects ignore files | 0/3 | 0/10 |
| Depth 6, ignore files disabled | 0/3 | 3/10 |
| Depth 64, respects ignore files | 0/3 | 5/10 |
| Depth 64, ignore files disabled | 3/3 | 10/10 |

The indexed `immich` entries are at relative depths 7, 10 and 10. The indexed
`docker` entries span depths 5–11. This shows that fd can recover these matches;
its current search policy is narrower. Raising the depth and disabling ignore
files were experiments, not changes to the installed configuration. Depth 64 is
a probe, not a claim of unbounded coverage.

Current plocate queries use scoped regular expressions, which scan the database
and constrain directory visibility checks to the configured roots. The helper
collects the producer's output before formatting so failed searches cannot leak
partial results. It then filters exclusions, checks existing paths, and formats
records. This differs from a simple indexed literal plocate invocation.

## Equal-coverage terminal experiment

Each fixture contains exactly 1,000, 10,000 or 100,000 flat files, including
three `needle` files and two `immich` files. A separate private plocate database
contains exactly the same files. fd and database snapshot identities were
checked for equality. The result limit was raised to 200,000 in the **private
benchmark configuration** so the snapshot could not win by dropping candidates.

These are observed terminal-output latencies in milliseconds. "Open" is from
launching `fzd --global` until the full snapshot is loaded for cache, or until
the query prompt is available for live/locate. The latter initially show no
results because an empty query is below the minimum length. "Query" is replacing
the query with `needle` until its three-result count is emitted.

| Files | Cache open | Cache fuzzy query | Live open | Live query | Locate open | Locate query |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 222 | 2.3 | 21 | 175 | 23 | 173 |
| 10,000 | 2,106 | 3.5 | 33 | 175 | 35 | 72 |
| 100,000 | 20,786 | 5.0 | 48 | 250 | 37 | 193 |

The other query replacements (`immich`, then the abbreviation `imch`) are in the
raw data. At 100,000 files, cache took about 2 ms for each; live took 230–270 ms;
locate took about 202–203 ms. The literal modes correctly return no `imch` match.

The query-reload timings include process startup, producer work, formatting, fzf
reload scheduling and terminal output. They do not isolate a particular internal
fzf delay. These are query bursts/replacements, not individual-character typing
cadence or physical display-paint measurements.

Approximate steady fzf resident memory after opening the list:

| Files | Cache | Live, initially empty | Locate, initially empty |
| ---: | ---: | ---: | ---: |
| 1,000 | 7.5 MiB | 6.5 MiB | 6.4 MiB |
| 10,000 | 11.0 MiB | 6.5 MiB | 6.6 MiB |
| 100,000 | 41.8 MiB | 6.4 MiB | 6.5 MiB |

This measures fzf only, not total process-tree peak memory. Reload modes can
grow when large result sets arrive.

## Where snapshot startup time goes

| Files | Raw fd enumeration | Raw find enumeration | Raw plocate snapshot | fd + FZD formatting | plocate + FZD formatting prototype |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1,000 | 5.1 ms | 2.2 ms | 1.7 ms | 176 ms | 137 ms |
| 10,000 | 8.8 ms | 5.7 ms | 6.2 ms | 1,849 ms | 1,668 ms |
| 100,000 | 74.8 ms | 105.3 ms | 47.3 ms | 20,160 ms | 19,714 ms |

The raw enumeration controls omit FZD's per-path validation, display escaping,
color labels and encoded identity records. That shared stage dominates the large
snapshot test. Switching the snapshot source from fd to plocate leaves it intact.

The experimental database snapshot used exactly the same FZD formatter and then
the same fuzzy matcher. Its subsequent queries took roughly 1–5 ms. Its reported
UI load is separate from acquisition: it is **not** an instant-start hybrid.
Building its 100,000-record snapshot still cost about 20 seconds. This prototype
is not a new supported FZD backend.

## Fuzzy versus exact, with acquisition excluded

A separate persistent-fzf control uses the same prebuilt records for both modes,
alternating the order of fuzzy and exact trials. It measures query replacements
without any filesystem search or repeated fzf startup.

| Files | Fuzzy `needle` | Exact `needle` | Fuzzy `immich` | Exact `immich` |
| ---: | ---: | ---: | ---: | ---: |
| 1,000 | 2.4 ms | 4.1 ms | 1.2 ms | 1.1 ms |
| 10,000 | 3.9 ms | 2.9 ms | 2.0 ms | 1.4 ms |
| 100,000 | 6.3 ms | 6.7 ms | 2.5 ms | 3.1 ms |

With three samples, small differences should be treated as noise. These queries
provide no evidence of a user-visible benefit from turning fuzzy matching off.
This is not a worst-case matcher benchmark for long strings or ambiguous queries.

## Matching feature probes

These deterministic examples test behavior, not universal precision/recall or a
human relevance score. The file set is deliberately controlled.

| Query and intended file | Live / locate literal | Cached fzf fuzzy | Cached fzf exact |
| --- | --- | --- | --- |
| `immich` → `immich-server.conf` | Found | Found, rank 2 | Found, rank 2 |
| `imch` → `immich-server.conf` | Missing | Found, rank 2 | Missing |
| `imm server` → `immich-server.conf` | Missing | Found, rank 1 | Found, rank 1 |
| `dcomp` → `docker-compose.yaml` | Missing | Found, rank 1 | Missing |
| `an rpt` → `annual-report.pdf` | Missing | Found, rank 1 | Missing |
| `immcih` → `immich-server.conf` | Missing | Missing | Missing |
| `i` → `immich-server.conf` | Below minimum length | Found | Found |

fzf extended matching accepts multiple terms even with `--exact`; that example
does not require fuzzy subsequences. Fuzzy matching handles skipped letters and
abbreviations, but the tested letter transposition does not match. It is not a
general spelling-correction engine.

Freshness/coverage probes also confirmed:

- A file created after indexing appears in live mode, and in a newly rebuilt fd
  snapshot, but not in the old database or an already open snapshot.
- A fresh database finds the tested gitignored and deeper-than-six files; the
  current fd settings omit them.
- A snapshot cap is applied before the user's fuzzy query. A deliberately tiny
  10-record cap retained 10 of 1,008 otherwise eligible candidates. Query modes
  apply their cap to the query results instead.

## Assessment

Keep fuzzy matching for an in-memory snapshot: it adds useful abbreviation
matching at little observed latency. For the current 3,201-record fd candidate
set on this host, cache mode offers instant query responses after roughly a
three-quarter-second preparation cost. It currently misses real indexed matches
because of search policy, so it is not an equivalent replacement as configured.

Live fd avoids database setup and sees new files immediately. On this host its
helpers were faster than current plocate helpers, but the controlled 100,000-file
fixture favored plocate for sparse queries. Both current reload modes incur
noticeable interactive latency and use literal matching.

Removing plocate project-wide is not justified by these measurements. Keeping it
optional while making search policy and matching behavior explicit is a
reasonable direction. For a consistently fast fuzzy global experience across
large scopes, the measured priority is reducing full-list preparation cost and
considering streamed/background snapshot loading or reuse with a refresh policy.
Those designs need freshness, completeness and stale-selection handling; they
were not implemented here.

## Reproduction and limits

```bash
python3 benchmarks/global-search-options.py .test-work/global-options-main 3
python3 benchmarks/global-search-options.py .test-work/global-options-matchers 3 --matching-only
python3 benchmarks/global-search-options.py .test-work/global-options-coverage 3 --host-coverage-only
```

Each output directory must be fresh. Run sequentially on an otherwise idle host.
The runner uses private temporary fixtures and databases, reads the real index
for host probes, and removes only its own temporary fixtures. It does not run
system updatedb, change settings, install packages, or drop kernel caches. Root
is not required, but sandbox restrictions on the setgid plocate executable and
PTY creation must not interfere with the run.

One warmup plus three measured trials per timing group; medians shown, with all
samples retained. Component trials are grouped; terminal trials alternate mode
order. Host coverage is a separate untimed feature audit. Warm filesystem caches,
the tested WSL2 host, flat synthetic fixtures, and the installed tool versions
limit generalization. Cold starts, spinning disks, remote mounts, million-file
corpora, and long ambiguous fuzzy queries were not tested.

- [Summary and ranges](summary.json)
- [All retained trials](trials.json)
- [Matching and coverage probes](features.json)
- [Environment and provenance](environment.json)

Primary timing samples are retained unchanged. Matching and coverage feature
records come from the final validated adapter runs. Original runs and raw PTY
logs remain under `.test-work/global-search-options/`; real host filename lists
were not saved. Only fixture names, query strings and aggregate host counts are
published here.
