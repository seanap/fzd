# Phase two: performance optimization

Completed in the Linux checkout `/home/htpc/projects/fzd`, branch `revamp/audit`,
on 2026-10-11. Reference application: `385868a`; final application: `ed8a615`.
Installer modernization remains excluded.

## Outcome

Preparing 1,000 local records now takes **49 ms**, or **56 ms including real
directory enumeration**. Both are below the 200 ms stretch target. A 1,010-entry
global index takes **172 ms**. These are warm-cache component measurements;
interactive observations and their limits are reported separately below.

FZD still uses Bash, fzf and its existing base64 identities. Arrows, Enter,
Ctrl+F, Esc, query history, layout, labels, colors, preview renderers and trusted
configuration loading remain in place. No persistent index, new framework or
application dependency was introduced. `tput` is optional, with a tested fallback.
The only package added during this phase was the authorized developer tool
`strace` 6.8. No installer, shell rc file, Windows setting, system locate database
or production resource was changed.

The complete suite has **88 cases: 87 passed and one explicitly skipped**. All
73 previously passing cases remain, with 14 additional regressions. The skipped
installer wrapper still strips trailing newlines from directory targets through
command substitution; it is not a WSL limitation.

## What profiling established

The premise of a 1.554-to-2.395-second Phase One regression was reversed in the
original measurements: **2.395 seconds was the audit revision; 1.554 seconds was
Phase One**. Phase One removed two path-building command substitutions per entry.
It added safe display escaping and NUL sorting, while retaining the expensive
per-record encoder pipeline. The security repairs did not cause the alleged
local-list regression.

Actual `strace -f -c` counts for the same 1,000-candidate adapter:

| Revision | Child creation calls | Program executions |
| --- | ---: | ---: |
| Original audit `4dabc12` | 6,009 | 2,006 |
| Phase One `385868a` | 4,007 | 2,005 |
| Optimized listing | 6 | 4 |

These include the adapter and Bash startup, not just application functions.
Traced timings are not used as latency benchmarks. The Phase One graph included
1,001 record command substitutions, each running a printf/base64/tr pipeline.
Replacing the encoder with a builtin still cost about 439 ms because command
substitutions remained. Actual enumeration/sorting took about 19 ms.

A ten-sample display-only control took 13.6 ± 0.6 ms versus 8.5 ± 0.7 ms with a
no-op, including identical adapter startup. Safe escaping adds roughly **5 ms**
for 1,000 ordinary short names in that experiment. It is retained. Different
names, path lengths and samples mean these component values should not be added
or subtracted as exact universal costs.

## Changes and regression protection

| Area and current source | Change and evidence | Tradeoff or limit |
| --- | --- | --- |
| [Path encoding](../fzd.sh#L92), [local records](../fzd.sh#L230) | One GNU base64 process encodes the whole local batch. Inputs are padded to three-byte boundaries only inside a pipe; fixed-width reads restore each original base64 value and its `=` padding. Incremental reads avoid quadratic slicing. Tests compare every non-NUL byte, Unicode, whitespace, all alignments and long input against GNU base64. | Temporary arrays increase memory modestly. The single-record `b64` helper remains compatible. No filename becomes shell code or an executable argument. |
| [Global formatting](../fzd.sh#L462) | The first matching record is emitted immediately, then remaining records use batches of up to 128. Existing scope, exclusions, metadata checks, literal query policy, directory labels, ordering and post-filter caps remain. Tests cover boundaries, 129-result caps and encoder counts. | The first immediate batch adds one encoder in larger scans. Later results arrive in bounded groups rather than one at a time. |
| [Global streaming](../fzd.sh#L472) | A gated producer reproduced a weakness in the first batching implementation: a rare first hit could wait for scan EOF. The new test requires that hit before allowing the producer to finish. | This safeguards first-result responsiveness without a persistent encoder, index or new synchronization mechanism. |
| [Enumeration](../fzd.sh#L202) | Classify one set of glob results into directories/files, preserve directory-first NUL sorting, and restore nullglob/dotglob with builtins. This removes a duplicate traversal, a command substitution and the remaining runtime eval. | The measured enumeration gain is modest. Sort is already inexpensive and remains GNU `sort -zf`; replacing it was not justified. |
| [Navigation](../fzd.sh#L679), [overlay](../fzd.sh#L585) | Read action fields with Bash `read`; remove grep/cut pipelines, the 5 ms sleeps and the 20×10 ms abort polling. Fzf's documented execute-silent action is synchronous. A real fzf test delays a callback by 300 ms and confirms correct navigation. | This relies on the existing synchronous callback contract, not a guessed write delay. Bindings and action-file protocol remain. |
| [Backend setup](../fzd.sh#L544) | Skip locate discovery for explicit live/cache helper requests; the overlay probes locate only when auto selection needs it. | Preserve priority of existing binaries and the user's PATH. No fd-thread or backend preference change was justified by a tiny fixture. |
| [Screen lifecycle](../fzd.sh#L165), [startup](../fzd.sh#L772) | Use fzf's documented `--no-clear` when stderr is a terminal and terminfo supplies a restore capability. Keep the previous frame during preparation; restore the shell screen before editors and on exit. Tests assert restoration after Enter, Esc and Ctrl+C, exact editor arguments, resizing and capability failure. | Fzf still restarts. The optional feature avoids visible shell flashes without a persistent fzf architecture. Wider terminal-emulator coverage remains outstanding. |
| [Preview](../fzd.sh#L330) | Use Bash MIME matching instead of grep, and a here-string for base64 decoding. Preserve renderer flags, filenames, depth, exclusions, colors and limits. New tests exposed and fixed an existing nonzero binary-preview exit when optional hexdump is absent. | Text-renderer startup still dominates; no substantial text-preview speedup is claimed. Renderer/style substitutions would change the experience. |

Encoder errors, including failure after complete output, propagate rather than
publishing partial identities. Tests verify descriptor closure and child reaping.
Performance guards require one encoder for 1,001 local records and three for
257 global records. These are deterministic process budgets rather than fragile
CI wall-clock thresholds. The full suite passed after each significant runtime
change; the final TAP is [validation/phase-two-tests.tap](validation/phase-two-tests.tap).

## Component measurements

Ubuntu 24.04.5 / WSL2, Bash 5.2.21, fzf 0.44.1, fd 9.0.0, batcat 0.24.0,
tree 2.1.1, tmux 3.4, hyperfine 1.18.0, private plocate 1.1.19. Fixtures used the
Linux filesystem. The main comparison uses the same inherited PATH, one warmup
and three samples per command. Values are **mean ± sample SD in milliseconds**.
Preparation and Git extraction are excluded; Bash/adapter startup is included.

| Entries | Records: before | Records: after | Enumeration + records: before | Enumeration + records: after |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 19.2 ± 0.4 | 8.1 ± 0.4 | 22.3 ± 1.0 | 8.9 ± 0.6 |
| 100 | 147.9 ± 0.3 | 11.5 ± 0.2 | 172.7 ± 6.8 | 11.9 ± 0.2 |
| 1,000 | 1,529.1 ± 20.7 | 49.4 ± 1.1 | 1,700.2 ± 22.8 | 55.8 ± 0.5 |
| 10,000 | 19,599.1 ± 124.0 | 388.8 ± 14.3 | 18,950.6 ± 500.2 | 598.7 ± 3.4 |

Enumeration alone at 1,000 entries changed from 18.7 to 17.5 ms; at 10,000,
145.0 to 136.4 ms. The isolated sorting adapter takes about 9.1 ms at 1,000 and
54.2 ms at 10,000. Enumeration and sort were not the original dominant cost.
Raw matrices contain all four sizes, samples and dispersion.

| Workload | Before | Final |
| --- | ---: | ---: |
| Helper startup, no TUI | 8.1 ± 0.5 | 7.5 ± 0.9 |
| Global index, 1,010 entries | 2,300.2 ± 144.1 | 172.5 ± 5.8 |
| Live fd query, ten matches | 150.9 ± 3.7 | 49.8 ± 0.8 |
| Private locate query, ten matches | 46.5 ± 11.3 | 18.1 ± 0.3 |
| Text preview | 78.8 ± 10.6 | 69.3 ± 3.2 |
| Directory preview | 44.4 ± 6.8 | 47.8 ± 2.7 |
| Binary preview | 23.1 ± 3.3 | 14.4 ± 0.8 |

The earlier Phase One global-index measurement was 1,508 ms; an initial fresh
profile here was 1,428 ms. Absolute times varied substantially in this WSL host;
the table preserves the final comparable matrix rather than mixing a favorable
old sample into it. Hyperfine uses a monotonic clock. Query tool/database discovery
was removed from the benchmark's timed locate setup for **both** revisions.

The inherited PATH contains Windows directories. A syscall trace of a missing
optional command shows 60 Windows-path metadata calls; forcing a different
application PATH would change command precedence, so runtime does not do that.
A separate, five-sample controlled Linux-only PATH experiment at `1917685`
measured index 1,542→146 ms, live query 28.3→15.8 ms, locate 30.1→17.6 ms and text
preview 35.7→36.0 ms. This isolates environmental overhead; it is not a native
Linux benchmark or a proposed configuration change. That checkpoint precedes
the additional first-result flush; the final matrix above includes it.

Standalone fd took about 3.9 ms, file detection 3.4 ms and batcat 19.2 ms on the
small fixture. Forcing fd to one thread saved only about 1.5 ms there, insufficient
evidence for changing search behavior across much larger roots. A directory
preview containing 10,000 root files and 10,000 child files took 88 ± 8 ms as a
command; terminal wrapping/rendering is additional work.

Single-run GNU time observations of maximum process RSS:

| Candidates | Before | After |
| ---: | ---: | ---: |
| 1,000 | 3,584 KiB | 4,352 KiB |
| 10,000 | 6,448 KiB | 12,456 KiB |

These are peak process RSS, not aggregate process-tree memory or PSS. The added
arrays are a real tradeoff: about 0.75 MiB at 1,000 and 5.9 MiB at 10,000 in these
observations. Candidate CPU time in the main 1,000-entry comparison fell from
about 1.51 to 0.05 seconds. No persistent cache memory or background service was
added. Local component functions are byte-identical between `1917685` and the
final application; the later change only affects global output scheduling.

## Interactive measurements

The private 120×32 tmux/fzf harness timestamps Linux `/proc/uptime` with **10 ms
resolution** and polls visible text every 5 ms plus command overhead. It excludes
tmux server creation, includes application startup, and waits for complete new
candidate counts. Results are coarse screen-observation bounds, not physical
display latency. A recorded zero means below clock resolution. Three samples
are used except the slow 10,000-entry Phase One baseline, which has one.

The first harness used wall time. A negative elapsed result exposed a WSL clock
adjustment; **all initial wall-clock terminal measurements were discarded from
conclusions and rerun**, with the original trials retained separately. This also
prevents treating wall-clock outliers as proven application stalls.

Main matrix medians, in milliseconds at the clock's 10 ms resolution:

| Files per directory | Startup: before→after | Right: before→after | Left: before→after |
| ---: | ---: | ---: | ---: |
| 10 | 50→30 | 50→20 | 50→30 |
| 100 | 180→70 | 190→50 | 190→50 |
| 1,000 | 1,410→100 | 1,540→100 | 1,570→110 |
| 10,000 | 16,440→710 | 20,140→820 | 20,490→780 |

At 1,000 entries, startup ranged 90–110 ms, Right was 100 ms in all three samples,
and Left ranged 90–110 ms. The stretch target is therefore met for these complete
interactive transitions, as well as for component preparation. At 10,000 the
final startup range was 690–820 ms and Right 750–930 ms; it is not instantaneous.

Additional 1,000-entry main-matrix medians:

| Event | Before | Final |
| --- | ---: | ---: |
| Local fuzzy query | 10 | 10 |
| Open **live** Ctrl+F overlay | 90 | 10 |
| Live query to visible two-match result | 240 | 200 |
| Dismiss overlay and render local list | 1,740 | 200 |
| File query to preview content | 100 | 120 |
| Change query to another file preview | 110 | 130 |
| Esc to application exit | 350 | 120 |

The direct Down-arrow preview comparison, measured separately after filtering to
ten files, was **70 ms in both revisions**. Its query-change medians were
110→120 ms, with overlapping 110–120 ms observations. The main sequence's preview
numbers were slower after optimization; the standalone Linux-PATH experiment and
direct arrow test do not establish a consistent preview speedup or a general
regression. Preview cancellation/render scheduling and host variation remain
limits. No improvement is claimed from fewer preview processes alone.

The **cache** overlay is a different workload. With 1,000 files in each of root
and child, its fresh snapshot has 2,001 entries. Three monotonic samples measured
Ctrl+F-to-overlay at 2,630/2,640/2,690 ms before and 340/350/340 ms after.
Cached filtering then took 0–10 ms at this clock resolution. Auto mode without
locate uses this cache design and additionally probes optional backend commands;
the 10 ms live-mode opening time must not be advertised as general auto-mode
startup. Cache creation remains synchronous and rebuilds on each opening.

Primary-shell screen gaps were observed during every sampled Phase One
Right/Left transition: roughly 40–50 ms at ten entries and 1.5 seconds at 1,000.
No such gap was observed with retained frames. This is evidence at the polling
and clock resolution, not proof against every possible terminal flash. Small
directory transitions now cost 20–30 ms including fzf restart and all application
work, so the measurements do not justify a persistent-fzf redesign.

## Verification, limits and next boundary

Validation includes real fd, fixture-only plocate databases, Bash/zsh integration,
injection regressions, unusual filenames, configuration overrides, selection
restoration, errors, signals and ten real terminal tests. New coverage includes
all-byte encoding, chunk/cap boundaries, producer failures and cleanup, glob-option
preservation, MIME/renderer contracts, missing hexdump, delayed action completion,
screen restoration and a failed terminfo capability. All ran in WSL; no new test
requires a native Linux host. Native terminal emulators, broader fzf versions,
optional eza/vivid themes and fresh Debian/Arch/Fedora packaging were not tested.

`bash -n`, ShellCheck on the application/development tools, shfmt on the new and
changed tooling/Bats files, and `git diff --check` passed. Legacy fzd.sh was not
reformatted wholesale. The unchanged installer is excluded from the passing
ShellCheck claim. No install or uninstall operation was run against the real home.

Remaining limits are deliberate:

- A 10,000-entry local directory still takes roughly 0.6 seconds just to prepare;
  Bash array/string handling, stat calls and fzf input/rendering remain linear.
- Global scopes can be much larger or slower than the fixture. Permission errors,
  stale locate indexes, capped cache snapshots and external filesystem latency
  retain their Phase One behavior. Later global results are emitted in batches.
- Text previews retain renderer startup and inherited-PATH overhead. Larger trees,
  files, syntax grammars and wrapping can cost more; existing timeouts remain.
- Configuration remains trusted Bash. Unicode identity bytes are preserved;
  comprehensive Unicode case folding and every terminal-control display policy
  were not expanded in this phase.
- Screen preservation has tested fallback and cleanup, but wider native-terminal
  validation remains useful. No persistent fzf process or index is justified by
  the measured fixed startup cost at this point.
- Installer behavior and its trailing-newline wrapper limitation remain unchanged.

See [../benchmarks/README.md](../benchmarks/README.md) for repeatable commands,
[../benchmarks/results/phase-two/](../benchmarks/results/phase-two/) for raw results,
and [phase-one.md](phase-one.md) for the security/reliability baseline.
Application runtime, developer dependency setup, shell integration, optional
themes and user configuration remain separate responsibilities, compatible with
future Debian/Ubuntu and Arch packaging. Phase Two stops here; installer
modernization requires the next approval.

Runtime commits: `dbe333d` (local encoding), `7dcb516` (global batches),
`46441ea` (enumeration/navigation), `c9a154c` (preview), `1917685` (retained
frames) and `ed8a615` (first-match streaming). Benchmark and evidence commits are
separate. No history was rewritten or pushed.
