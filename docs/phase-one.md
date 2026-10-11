# Phase one: reliability, security and regression protection

Completed on 2026-10-11 in `/home/htpc/projects/fzd`, branch `revamp/audit`.
Application revision: `3cadebe`; original audit revision: `4dabc12`.

## Outcome and scope

Filename-derived shell execution has been removed from global search. Search
roots, exclusions, result identities, directory labels and fallbacks now have a
shared implementation. Confirmed navigation exits and newline-path corruption
are repaired. The suite contains **74 cases: 73 passed, one explicitly skipped**.

The existing arrows, Enter, Esc and Ctrl+F controls, fzf layout, color settings,
preview backends and editor behavior remain in place. No application dependency,
language or framework was added. No installer, shell rc file, Windows setting,
system locate database or production resource was changed. `install.sh` is
byte-for-byte identical to the audit revision.

## Verified development baseline

The host environment is Ubuntu 24.04.5 under WSL2, hostname `HTPC-Win11`, account
`htpc`, with Bash 5.2.21. Work and disposable fixtures used the Linux checkout,
not `/mnt/c/`.

| Tool | Verified version |
| --- | --- |
| fzf | 0.44.1 |
| fd-find | 9.0.0 |
| batcat | 0.24.0 |
| tree / micro | 2.1.1 / 2.0.13 |
| zsh | 5.9 |
| ShellCheck / shfmt | 0.9.0 / 3.8.0 |
| Bats-core / tmux | 1.10.0 / 3.4 |
| hyperfine | 1.18.0 |
| private plocate | 1.1.19 |

The user installed the approved application/benchmark packages. Existing
ShellCheck, shfmt, Bats and tmux were retained. Plocate and liburing packages were
downloaded and extracted into the ignored workspace, without installing a locate
service. All locate databases used in checks were built solely from fixtures.

`bash dev/run.sh` launches the checkout with private configuration and XDG
storage under `.test-work/manual/`. It copies the example once and preserves
subsequent edits there. Real terminal tests establish that the installed Ubuntu
fzf supports the controls and caret bindings used here. This is evidence for
0.44.1 on this environment, not a claim about every older fzf release; the README's
advertised minimum has not been broadly revalidated.

## Fixes and comparison with the audit

All findings below are confirmed unless explicitly marked as deferred. Original
line numbers refer to `4dabc12`; current line numbers refer to `3cadebe`.

| Finding and severity | Original evidence | Implemented repair and verification |
| --- | --- | --- |
| **High: filename command injection** | `fzd.sh:183–190, 350–351, 409–411` interpolated paths into AWK shell commands and `system()` | `fzd.sh:410–501` consumes NUL records, tests paths with Bash builtins and passes data as quoted arguments. The original indexer created a harmless marker from a crafted filename; repaired find/fd/locate paths do not. |
| **High: broken cache initialization/scope** | `fzd.sh:170–193` called root/exclusion functions defined only at `436–445`; cache could scan the working directory and had no find fallback | `fzd.sh:332–481, 705–747` prepares configuration and functions before dispatch. Tests verify actual backend arguments, configured scope, exclusions and find fallback. Relative roots with `.` components are canonicalized consistently. |
| **High: unexpected navigation exits** | `fzd.sh:508–510` returned false for global Right on files under `set -e`; empty child state also made Left at `/` fail | `fzd.sh:124–151, 578–596` makes no-op transitions successful and rejects inaccessible directory entry. Reproduced failures now pass deterministic and real terminal checks. |
| **Medium: pathname corruption** | `fzd.sh:138–141` sorted newline-delimited names; multiple command substitutions stripped trailing newlines, including preview and selection decoding | `fzd.sh:88–103, 154–209, 301–310` uses NUL sorting, byte-preserving path returns/decoding, and escaped display labels independent of identity. Tests cover spaces, Unicode, quotes, backticks, substitutions, tabs, backslashes, embedded and trailing newlines. |
| **Medium: wrong labels, roots and result limits** | Directory producers emitted trailing slashes and then selected an empty basename; locate limits preceded scope filtering and `/` scope matching was incorrect | `fzd.sh:392–434, 475–509` removes producer slashes, labels directories once, filters exact root boundaries/exclusions and only then caps results. Root, label, exclusion and post-filter-cap tests pass. |
| **Medium: ineffective backend selection/fallback** | `--_global_list` preferred any installed locate regardless of explicit live mode and exited after locate failure | `fzd.sh:475–596` respects the selected backend, implements live overlay reload and discards failed locate output before fallback. Real plocate revealed that missing databases and no matches both return 1; diagnostics distinguish failure from a valid empty search. Both cases pass with actual binaries and in a terminal. |
| **Medium: unsafe legacy root evaluation** | `fzd.sh:314` used `eval echo` | `fzd.sh:318–390` expands `$NAME`, `${NAME}` and legacy leading `~/` without executing commands. Existing string roots remain supported; optional `FZD_GLOBAL_ROOTS=(...)` handles whitespace losslessly. Shell substitutions are now literal data, deliberately. |
| **Medium: interruption and temp-file failures** | Runtime creation failures were ignored; control files had no exit/signal cleanup | `fzd.sh:32–38, 105–122, 705–716` reports initialization/mktemp failures and tracks outstanding files for EXIT/INT/TERM/HUP cleanup. Normal exit, Ctrl+C and interrupted locate tests pass. Tracking is cleared as files are removed. |
| **Medium: fzf callback pathname quoting** | Preview/reload commands interpolated `$0` and control paths without shell quoting | `fzd.sh:514–673` quotes executable and control paths for fzf's shell callbacks. A real terminal test uses a quoted executable path and a temporary directory containing quotes, substitution text and a newline. |
| **Medium: configuration scope and runtime overrides** | The original startup created storage before sourcing configuration; the first testable startup change also made config `declare` statements function-local | `fzd.sh:16–38, 738–747` retains top-level sourcing, then initializes storage. New tests reproduced both cases and now verify declared arrays plus explicit runtime-directory overrides. |
| **Low: contradictory example configuration** | `fzd.conf.example:4,27` assigned different backends; roots were duplicated; locate DB used an Arch-specific path | The example has one `auto` setting, one legacy root list, an optional array example and an optional database override. Existing user configuration was not rewritten. |
| **Deferred: repeated fzf processes / sleep synchronization** | Original navigation relaunched fzf and polled temporary control files | Preserved for this phase. Benchmarks and real terminal regressions provide protection for a later measured redesign. No evidence here justifies replacing the application's shell/fzf architecture. |
| **Deferred: installer and README inconsistencies** | Sudo behavior, configuration preservation, legacy paths and installation lifecycle remain audit concerns | Installer execution and modernization were excluded. This report and development instructions supplement the existing README without claiming its installer problems are solved. |

Configuration remains trusted executable Bash, as before. Removing `eval` from
root expansion does not make arbitrary configuration files safe to source. The
remaining `eval` restores Bash's own `shopt -p` output; filenames/configuration
strings do not enter that expression. It is not the injection mechanism fixed
in this phase.

## Preserved search contracts

| Setting | Behavior |
| --- | --- |
| `auto` | Prefer installed locate; otherwise build a cache. A failing locate query falls back to fd/find. |
| `locate` | Query locate when available; otherwise use fd/find. Database errors fall back; genuine zero matches remain empty. |
| `cache` | Build a capped fd/find snapshot and let fzf perform its existing fuzzy matching. |
| `live` | Reload fd/find results as the global query changes, using the existing overlay controls. |

Live/locate queries use case-insensitive literal substring matching, with basename
or full-path policy controlled by `FZD_GLOBAL_FULLPATH`. Query option characters
are data. Hidden entries and existing file/directory symlinks remain supported;
missing or dangling results are omitted. Filesystem traversal does not follow
descendant directory symlinks. `FZD_GLOBAL_MAXDEPTH` applies to filesystem scans;
locate searches its index. The cache's result cap still limits the searchable
snapshot. These distinctions should remain explicit in future documentation.

## Validation actually executed

The initial 17-case regression checkpoint reproduced 11 failures and passed six
checks on the original code. Later focused tests also reproduced newline-path,
root-navigation, inaccessible-entry and real plocate error cases before repair.
The final suite passed 73 cases and skipped only the known wrapper limitation.
The complete TAP output is in [validation/phase-one-tests.tap](validation/phase-one-tests.tap).

Coverage includes isolated functions, backend arguments and failures, real fd,
private plocate databases, configuration precedence, directory selection state,
exact editor arguments, Bash/zsh init-block behavior and eight real tmux/fzf
tests. Terminal checks exercise local navigation, cached/live/locate global
search, broken-database fallback, 60×16 resizing, Esc and Ctrl+C cleanup.

`bash -n fzd.sh`, ShellCheck on the application and development scripts, shfmt
checks on the new tooling/Bats files, and `git diff --check` passed. The application
was not reformatted wholesale. The unchanged installer is excluded from the
passing ShellCheck claim. Narrow annotations identify trusted config sourcing,
optional configuration arrays and deliberate literal shell syntax.

No test here requires WSL-specific application behavior. Codex's socket sandbox
required tool approval for private tmux sockets; WSL itself supported all terminal
checks. Fresh Ubuntu/Debian/Arch/Fedora installs, system updatedb scheduling,
package upgrades/removal and native terminal-emulator/theme validation were not
run. Those need disposable distribution environments or native Linux checks.

## Performance baseline

Run `bash benchmarks/hyperfine.sh 5` on an otherwise idle machine. The recorded
run uses one warmup and five samples, Linux filesystem storage and fixed inputs.
Historical functions are extracted before timing; Git extraction is not charged
to the audit revision. Raw JSON/CSV records are in `benchmarks/results/`.

| Workload | Audit revision mean ± SD | Phase-one mean ± SD |
| --- | --- | --- |
| Prepare 10 local candidates | 26.2 ± 0.9 ms | 18.0 ± 0.6 ms |
| Prepare 100 local candidates | 222.8 ± 3.7 ms | 145.9 ± 2.0 ms |
| Prepare 1,000 local candidates | 2,395 ± 72 ms | 1,554 ± 48 ms |
| Helper startup, no TUI | Not compared | 6.3 ± 0.5 ms |
| Global fd index, 1,010 entries | Not compared | 1,508 ± 25 ms |
| Live fd query, ten matches | Not compared | 99.9 ± 16.0 ms |
| Private locate query, ten matches | Not compared | 89.0 ± 4.5 ms |
| Text-file preview | Not compared | 56.3 ± 6.7 ms |

Candidate measurements were recorded at `414a699`; the extracted function block
is byte-identical at `3cadebe`, verified with `diff`. Runtime measurements were
recorded again at `3cadebe` after the configuration-loading repair. The original
unsafe global-search implementation is not timed as though it produced equivalent
correct results.

Candidate preparation measures arrays-to-records and includes Bash startup; it
excludes directory enumeration, fzf rendering and key latency. The filesystem
fixture contains 1,000 text files in ten directories; `needle` matches ten files.
The startup command validates configuration and an empty helper query without
launching the TUI. Preview measurement includes file detection and batcat.
Measurements are warm-cache observations, not cold-start or native-Linux claims.
Some query/preview samples vary noticeably; raw samples and dispersion are
retained. Memory use and end-to-end interactive latency remain unmeasured.

Path-correctness changes incidentally remove some subprocess work; the existing
per-record base64 processes still dominate larger lists. Performance work should
start with that measured cost and the regressions already established, without
changing controls or introducing a new framework by default.

## Remaining risks and next approval boundary

- **Known skipped behavior:** installer-generated Bash/zsh wrappers use
  `dest="$(fzd ...)"`, stripping trailing newlines. Internal FZD paths and stdout
  now preserve them, but shell `cd` integration for those names remains deferred.
- Locate indexes can be stale. Failed indexes fall back, but an otherwise valid
  index with no matches does not trigger an expensive live rescan.
- Cache caps can hide later candidates; full cache construction and per-change
  live reload still incur measurable latency. fzf restarts and short sleeps
  remain; no broad performance optimization was attempted.
- Configuration is trusted shell code. Arbitrary shell evaluation inside legacy
  root strings is intentionally unsupported; use normal config assignments or
  the array form. Unicode path bytes are preserved; comprehensive Unicode case
  folding and all terminal control characters are not newly guaranteed.
- Current editor-command argument limitations, optional theme behavior and
  installer/XDG integration concerns remain for the next reviewable phase.
- SIGKILL and machine shutdown cannot run cleanup traps. Native distribution,
  permission-policy and packaging lifecycle coverage remains outstanding.

The runtime entrypoint owns initialization/dispatch; sourceable functions support
tests without starting the UI. Developer dependency preparation and fixtures are
separate from runtime. This keeps future packaging free to install the program,
provide shell integration separately, leave themes optional and preserve user
configuration without embedding dependency installation in the application.

Reviewable commits before this report:

1. `6f945b3` — capture failures and the original candidate baseline.
2. `709cb18` — pathname-safe global search and backend fallback.
3. `fff26d5` — navigation state and unusual local filenames.
4. `888b324` — canonical search scope and interrupted-session cleanup.
5. `6c84f74` — actual plocate errors and navigation at `/`.
6. `22cdc07` — real terminal tests, isolated developer tools and benchmarks.
7. `414a699` — safe legacy tilde-root compatibility.
8. `3cadebe` — top-level configuration declarations and runtime path overrides.

Phase one stops here. Performance optimization and installer modernization
require the user's next approval.
