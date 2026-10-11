# Phase 3.5: Explorer UX engineering report

FZD now supports browser history, persistent recent directories, an internal
clipboard, Rename, Create Directory, confirmed Linux Trash, and contextual help.
The Bash/fzf navigation loop, previews, global search and shell return protocol
remain the foundation. There is no new framework, language, index, watcher,
multiselect mode, permanent deletion command, or package publication.

This work uses `/home/htpc/projects/fzd` on `revamp/audit`. Filesystem operations
and installer tests use disposable fixtures, never the user's real configuration
or documents. The WSL development environment required no additional package
installation during this phase.

## Architecture and controls

The existing loop generates a listing and starts fzf for each navigation frame.
Fixed key callbacks pass an action and an existing base64 pathname identity
through the private control file. Filesystem names never become shell program
text. Explorer actions return to the same loop; output from prompts and commands
is captured so stdout remains exclusively the final directory-return protocol.

| Responsibility | Implementation |
| --- | --- |
| Session navigation | `fzd.sh`: bounded path/selection arrays, 100 visits; Back/Forward traversal creates no new entries and a new visit discards the forward branch |
| Recent directories | `lib/state.bash`: 25 unique accessible directories, MRU merge, no filesystem scan |
| Clipboard and references | `lib/state.bash`: strict versioned NUL records; rename/move rebase paths and Trash removes affected references |
| Filesystem operations | `lib/operations.bash`: quoted argument arrays, explicit status checks, private Copy staging, no-clobber move/rename, standard Trash backend |
| Prompts and overlays | `lib/ui.bash`: byte-preserving name prompt, recent picker, confirmation and contextual help |
| Installation | Installer stages the three modules under `PREFIX/share/fzd/lib`; manifest verification and uninstall account for these owned files |

Modules load on first feature use. Ordinary navigation keeps history and queued
recent visits in Bash memory; it does not read clipboard files, acquire locks,
or write recent state on each keypress. Recents flush on exit, when the picker
opens, or when an operation must update references. Preview and global-search
helper invocations do not initialize Explorer state.

| Keys | Behavior |
| --- | --- |
| Left / Right / Enter | Existing parent/child navigation and shell/editor selection |
| Alt+Left / Alt+Right | Back / Forward, with saved highlight where available; skip inaccessible history entries |
| Alt+H | Recent directories; Enter visits, Esc returns |
| Ctrl+C/X/V or Alt+C/X/V | Internal Copy / Cut / Paste, one item, persistent across launches |
| Ctrl+R or F2 | Rename, prepopulated with the current name |
| Ctrl+N or F7 | Create Directory and highlight it |
| F8 | Confirm, then move to recoverable Linux Trash |
| F1 | Contextual help; F1 or Esc dismisses it |
| Esc / Ctrl+G | Exit browsing; Esc dismisses an overlay first |

Delete remains query editing. Binding it to Trash would conflict with editing
the fuzzy query. Ctrl+C intentionally becomes Copy while fzf is active; during
a foreground filesystem operation it remains an interrupt. Terminal emulators
can intercept keys before fzf receives them; Alt+C/X/V are tested fallbacks.

Global search supports Copy/Cut on a result and then returns to the local view.
Its F1 help suspends and restores the global picker, including its query.
Paste, Rename, Create Directory, Trash, Back/Forward and Recents operate in the
ordinary directory view. Existing global Left/Esc, Right and Enter behavior
remains in place.

Feedback uses the existing border label rather than an additional panel.
Help is scrollable and tested at 60 columns by 16 rows. Local filtering survives
help, cancelled pickers and cancelled file-operation prompts. Operation prompts
have independent queries and capture output even when inherited fzf defaults
enable `--print-query`. User colors and initial browsing queries are retained;
FZD reserves its control bindings, single selection and result protocol.

## Filesystem and state safety

State resides in `${FZD_STATE_DIR}/explorer/`, normally
`${XDG_STATE_HOME:-$HOME/.local/state}/fzd/explorer/`. Its directory is user-owned
and mode 0700; new state files are mode 0600. Cooperative writers use `flock`
with a two-second timeout and publish private temporary files through same-
directory atomic rename. Symlinked, foreign-owned or malformed state is refused
with an error rather than silently replaced. Records are:

```
recents:   FZD-RECENT-1\0absolute-path\0...
clipboard: FZD-CLIPBOARD-1\0copy|cut\0absolute-path\0
```

Every legal non-NUL filename byte is preserved in identities and persistent
records. Prompts retain readable Unicode while escaping controls, literal
backslashes and invalid UTF-8 bytes. A validated decoder supports `\\`, `\n`,
`\r`, `\t`, `\e` and `\xHH`, rejecting NUL and invalid escapes. Unchanged Rename
does not modify the item. Empty names, slash, `.` and `..` are rejected.

Copy/Cut initially only record a source. Copy uses `cp -a --reflink=auto` into
a private staging directory inside the destination, then publishes with
`mv -nT`. Cut and Rename also use `mv -nT`. Pre-existing files, directories and
symlinks cancel rather than merge or overwrite. Postconditions detect the
successful exit code GNU mv can return when a no-clobber move was skipped.
An actual competing-destination regression verifies that behavior. Ubuntu's
GNU coreutils 9.4 was also observed using `renameat2(..., RENAME_NOREPLACE)`;
the syscall trace is retained with the benchmark evidence. GNU mv provides the
cross-filesystem copy/remove behavior; an actual private-tmpfs Cut regression
exercises it. See the [GNU mv manual](https://www.gnu.org/software/coreutils/manual/html_node/mv-invocation.html).

Recursive Copy preserves links and permissions where supported; symlink objects
are copied/moved without operating on their targets, including dangling links.
Canonical source/destination checks reject pasting a real directory into itself
or descendants, including a symlink alias. Synthetic `../`, the browsed directory
and filesystem root cannot be clipboard/rename/trash sources. A failed operation
retains the clipboard; a completed Cut clears it, while Copy remains reusable.

Trash prefers `gio trash --`, then `trash-put --`. It is optional and never falls
back to permanent deletion. Confirmation starts on Cancel, shows the escaped
basename and parent path, and checks a metadata fingerprint again before acting.
Backend errors and a still-present source are failures. An isolated test invokes
real gio and verifies recoverable Trash content plus `.trashinfo` metadata.
Reference updates prune trashed paths and rebase renamed/moved directory trees.

Graceful INT/TERM cleanup removes only this process's private staging copies,
never selected originals. The cleanup's recursive removal is confined to those
owned private copies; it is not a user-facing permanent deletion operation.
Operations do not occur merely from previewing or highlighting a result.

## Reviewed defects and compatibility corrections

The reviewed color/display fixes precede the feature commits and are protected
by the complete suite:

- Preserve inherited `LS_COLORS` without overrides; replace only requested valid
  `di`/`fi` entries without removing adjacent separators.
- Validate all six hexadecimal digits, with an optional leading `#`; invalid
  overrides retain the inherited theme instead of raising arithmetic errors.
- Escape every non-NUL ASCII control byte and DEL in filename labels while
  preserving exact pathname identities.

Dangling symbolic links are now selectable in local/global results and operable
as links. A prior test expecting their omission was corrected; nonexistent
non-link results remain omitted.

Full-suite testing exposed installer capability-probe defects not covered by the
earlier newer-fzf subset: fzf 0.65.2 reads inherited defaults even for `--version`,
and `--select-1` with bindings can require a terminal during a noninteractive
probe. Version and binding probes now clear defaults and use deterministic
`--filter=x` parsing checks. Both old and new position probes succeed inside a
real PTY on both versions; the earlier history-test failure was a synchronization
race, not evidence that the old interactive application lacked position support.
That test now waits for a fresh directory frame rather than matching preview text.

## Validation

The suite grows from the reviewed 150-test baseline to **201 tests**. All 201
pass with both supported fzf versions, with **no skips**. Existing Ctrl+C abort
expectations change to the approved Copy behavior; the dangling-link omission
expectation changes to selectable links. Historical Phase Three reports retain
their original snapshot counts.

| Executed check | Result |
| --- | --- |
| Full Bats suite, Ubuntu fzf 0.44.1 | [201 passed, no skips](validation/phase-three-five-tests.tap) |
| Full Bats suite, official fzf 0.65.2 | [201 passed, no skips](validation/phase-three-five-fzf-0.65-tests.tap) |
| Bash syntax, application/installer/modules/helpers/benchmarks | Passed |
| zsh syntax, shared shell integration | Passed |
| ShellCheck, application/installer/modules/helpers/benchmarks | Passed |
| shfmt, modules/installer/helpers/benchmarks and all Bats files | Passed; existing application formatting was not rewritten |
| Git whitespace checks | Passed |

The new coverage includes history bounds/branching/stale paths, local/global
visits and final Enter, MRU persistence/deduplication/concurrent writers, strict
state parsing and failed atomic writes, clipboard cross-session persistence,
recursive permissions/hardlinks/symlinks, destination races, cross-filesystem
moves, permission failures, interrupted Copy, Rename/Create Directory, reference
rebasing, controlled and actual gio Trash, and every non-NUL filename byte in
the prompt codec. Real PTY tests exercise all shortcuts, global help/query
restoration, inherited defaults, F8 confirmation and query Delete behavior.

Installer regressions retain disposable homes, custom XDG/ZDOTDIR, shell
integration, dependency failures, source updates, verification, rollback and
uninstallation. Installed Explorer modules are loaded and exercised as part
of that suite. Required tools now include flock; provider mappings distinguish
Debian/Ubuntu and Arch's util-linux from Fedora's util-linux-core. Trash remains
an optional dependency.

## Performance comparisons

Measurement baseline: `e73b22d`, the Phase Three application plus the reviewed
color/display fixes, before Explorer features. Final runtime: `076a0f7`.
The paired runs use the same
WSL environment, fixture sizes and harnesses, without concurrent test activity.
Components use hyperfine, one warmup and three measured runs. PTY observations
use tmux and fzf 0.44.1 at 120×32, with the monotonic Linux uptime clock's 10 ms
resolution. All four sizes have three-run paired batches. Additional checks at
1,000/10,000 use six samples per revision with alternating run order. These are
warm-cache observations, not CI latency guarantees. Raw JSON, CSV, earlier trials,
profiling and source checksums are [retained together](../benchmarks/results/phase-three-five/README.md).

Component means, milliseconds (before → after):

| Entries | Candidate formatting | Enumeration | Sort workload | Complete local preparation |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 5.5 → 6.1 | 6.8 → 6.2 | 6.2 → 6.1 | 8.2 → 7.2 |
| 100 | 8.0 → 8.6 | 7.4 → 6.2 | 6.2 → 6.7 | 10.7 → 12.2 |
| 1,000 | 39.2 → 43.8 | 17.0 → 16.6 | 9.1 → 8.4 | 53.3 → 53.2 |
| 10,000 | 361.8 → 362.2 | 134.4 → 134.8 | 52.1 → 51.4 | 599.6 → 597.3 |

These are separate workloads, so their timings are not additive. Candidate-only
numbers include preparation of the synthetic arrays; complete preparation uses
the actual directory. The small candidate-formatting increase at 1,000 is
reported rather than hidden; complete preparation stays at about 53 ms.

Real-terminal medians, milliseconds (before → after):

| Entries | Samples per revision | Startup-to-render | Right-to-render | Left-to-render |
| ---: | ---: | ---: | ---: | ---: |
| 10 | 3 | 40 → 30 | 30 → 30 | 20 → 20 |
| 100 | 3 | 60 → 70 | 60 → 60 | 50 → 40 |
| 1,000 | 6, alternating order | 105 → 95 | 105 → 105 | 100 → 95 |
| 10,000 | 6, alternating order | 730 → 750 | 805 → 830 | 775 → 830 |

At 1,000 entries, alternating startup ranges are 80–120 ms before and 80–100 ms
after; Right ranges are 100–110 and 90–110 ms. At 10,000, startup ranges are
710–810 and 710–850 ms, and Right ranges 750–860 and 770–940 ms. The modest
large-directory residual is visible, with overlapping ranges; it is not grounds
to claim identical latency or justify a persistent-fzf rewrite in this phase.

The initial comparison showed a larger 10,000-entry difference: 640 → 800 ms
startup and 670 → 870 ms Right. Consecutive and alternating repeats showed a
substantial baseline shift too, so those first differences cannot all be assigned
to Explorer. A controlled five-run formatting experiment removed only the new
per-file highlight condition: 392.9 → 372.3 ms mean at 10,000, with roughly 19 ms
standard deviations. File restoration now performs a separate lookup only when
a nonempty target was not already found among directories. Ordinary visits and
directory highlight restoration avoid that additional file scan. No safety,
serialization, sorting or selection behavior was removed.

Helper workload means, milliseconds:

| Workload | Before | After |
| --- | ---: | ---: |
| Helper startup, without TUI | 7.0 | 7.8 |
| Global index, 1,000 files / ten directories | 184.8 | 188.4 |
| Live query | 51.2 | 56.7 |
| Private locate query | 18.7 | 19.4 |
| Text preview | 70.1 | 63.1 |
| Directory preview | 44.0 | 36.9 |
| Binary preview | 14.7 | 15.5 |

No preview or search optimization is claimed from these short runs. In the
order-balanced 1,000-entry PTY check, preview changes remain 120 → 120 ms, global
queries 210 → 205 ms, and exit 115 → 120 ms. Recents add exit work rather than
per-navigation writes. Global query timings include the existing reload debounce.
Very large listings still spend roughly 600 ms preparing candidates; the Bash
loop and repeated fzf frames remain the main limit at 10,000 entries.

Deterministic encoder budgets still pass: one encoder for 1,001 local records
and three for 257 global records at the configured batch bound. The history
regression also verifies that visits create no persistent Explorer directory
before flushing. No per-entry processes, background watchers or extra indexes
were introduced.

## Remaining limits and packaging readiness

- Filesystem mutation and persistent reference updates are separate operations.
  If the filesystem operation succeeds but saving references fails, FZD reports
  that partial completion; it does not claim to undo the filesystem change.
- Cooperative locking prevents FZD sessions corrupting shared state. It is not
  a transaction against external programs changing sources, directories or
  symlink ancestors. Confirmation fingerprints catch tested replacements but
  do not eliminate every hostile filesystem race. Copy is not a snapshot of
  concurrently edited file contents.
- Large copies and cross-filesystem moves run in the foreground. A competing
  session may report busy after two seconds. Graceful interruption is tested;
  SIGKILL can leave a hidden private `.fzd-copy.*` directory, and can lose recent
  visits not yet flushed. No unsafe automatic orphan reclamation is added.
- Atomic state publication is not an fsync/power-loss durability guarantee.
- WSL ext4/private tmpfs and real isolated gio are exercised. Native Debian,
  Fedora and Arch userspaces/package transactions, graphical terminal key
  interception, ARM, and Trash behavior on removable/network filesystems remain
  separate release gates. Distribution-profile stubs are not native distro tests.

Runtime modules have explicit owned paths and install manifests. Distribution
packages can stage them alongside the existing application and shared shell
integration without modifying homes or executing the source installer at
post-install time. Explorer state remains user-managed and survives uninstall.
See [packaging readiness](packaging.md). No packages or releases were published.
