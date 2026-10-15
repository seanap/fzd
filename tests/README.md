# Regression checks

Phase 4A adds eight packaging checks to the original 201 tests (209 total).
Debian builds are checked for complete payloads, runtime identity, metadata,
ownership, absence of maintainer hooks/home edits, revision ordering, immutable
source selection, checksums and byte reproducibility.

To run runtime and terminal checks against an installed or extracted payload:

```bash
FZD_TEST_SCRIPT=/usr/bin/fzd bash dev/prepare-shell-compat.sh
bash tests/run.sh
```

Installer fixtures still use private prefixes; they never install into /usr.
Actual distribution lifecycle tests are separate from the four simulated
profiles: see [Packaging](../docs/packaging.md). History PTY tests use a wider
pane to observe the full directory prompt and avoid confusing preview text with
a completed navigation frame. Small-terminal coverage remains at 60 by 16.

From the Linux checkout:

```bash
bash tests/run.sh
```

Use upstream zoxide >= 0.9.0, Bash 4.4 or later, Bats-core 1.5 or later, and GNU utilities. Real backend
tests additionally use fd/fdfind and plocate. Terminal tests use tmux and fzf;
shell integration tests use zsh when available. Missing optional tools produce
explicit skips. The phase-one environment uses Bash 5.2 and Bats 1.10.
Installer fixtures also expect fzf, micro, file, tree, curl, tar and gzip in the
development environment. Distribution-profile isolation additionally uses
bubblewrap; those four checks explicitly skip if it is not installed.

Fixtures, XDG directories, private databases, sockets and transient output stay
under the ignored `.test-work/` directory. Installer tests execute the modernized
installer only with disposable HOME/XDG/ZDOTDIR/prefix fixtures, and no real
package manager or sudo is reachable on their restricted PATH. They never write
to the user's home configuration. Backend tests deliberately restrict PATH
to exercise find and controlled failures. Native tests also call actual fd and
plocate, and assert that successful locate checks did not silently fall back.

| Suite | Coverage |
| --- | --- |
| configuration.bats | Explicit/XDG configuration, environment expansion, root arrays, validation |
| display.bats | Every non-NUL ASCII control byte, DEL, Unicode and exact local/global identities |
| encoding.bats | Byte-exact batch encoding, process budgets, failures, stream-first output, descriptor/child cleanup |
| filesystem.bats | NUL-safe local listing, byte-exact paths, previews, permissions, root navigation |
| global-search.bats | Injection, scope, excludes, labels, limits, fallback, symlinks, unusual names |
| native-backends.bats | Real fd and private plocate databases, literal queries, depth, failures |
| navigation.bats | Deterministic action sequences, stale results, selection restoration, exit codes |
| preview.bats | MIME policy, renderer options, exact paths, binary fallback and missing optional tools |
| recovery.bats | Failed runtime creation, failed mktemp, normal cleanup, interrupted search |
| dependencies.bats | Version/capability checks, executable aliases, package mappings, sudo and bounded package-manager transactions |
| distributions.bats | Full installer with Ubuntu/Debian/Fedora/Arch metadata and manager stubs in a bubblewrap namespace; host read-only, network isolated |
| inline-installer.bats | Verified engine download, conditional dependencies, existing engines, explicit opt-in, updates, disable, rollback and shared-dependency retention |
| installer.bats | Fresh install/update/verify/uninstall, preservation, XDG/ZDOTDIR, staging, download failures, TERM/KILL recovery, installed-wrapper PTYs |
| zoxide-navigation.bats | Dispatch, partial/multiple matching, fallback, upstream ranking/learning/preferences, hooks, conflicts and completion preservation |
| shell-completion-terminal.bats | Native Tab, actual ble.sh/zsh-autosuggestions ghost text, acceptance, immediate partial Enter and ordinary cd in isolated PTYs |
| shell-integration.bats | Shared Bash/zsh integration, all non-NUL filename bytes, trailing newlines, cancellations, aliases and editor/color preservation |
| terminal.bats | Real fzf controls/backends, editor arguments, resize, signals, delayed actions and screen restoration |
| explorer-state.bats | Bounded browser history, persistent MRU, concurrency, atomic failures, invalid records, final Enter recording |
| explorer-operations.bats | Persistent clipboard, recursive copies, links, permissions, destination races, cross-filesystem moves and interrupted-copy cleanup |
| explorer-names.bats | All-byte prompt codec, rename/create, conflicts, permissions, reference updates and competing rename destinations |
| explorer-trash.bats | Missing/failed backends, exact arguments, links, reference pruning, confirmation changes and real isolated gio Trash |
| explorer-terminal.bats | Explorer keybindings, filtered-view restoration, global help/copy, inherited options, confirmation and small terminals |

The terminal harness creates its own tmux server and socket, observes rendered
text or output files, and uses bounded polling. It never connects to existing
tmux sessions. A Codex sandbox can deny Unix sockets; run those checks with the
appropriate tool approval. This restriction is separate from WSL compatibility.

Explorer tests modify only disposable fixtures. The cross-filesystem test mounts
a private tmpfs through bubblewrap. The real gio test sets a disposable HOME and
XDG_DATA_HOME, disables remote VFS, and mounts the real host read-only; it verifies
recoverable Trash files and metadata without using your personal Trash. These
tests work in this WSL2 environment with user namespaces enabled. Native desktop
emulator interception, removable/network filesystems and actual distribution
userspaces remain separate validation work.

Use the prepared official binary to exercise the same suite with fzf 0.65.2:

```bash
PATH="$PWD/.test-work/phase-three/fzf-0.65-bin:$PATH" bash tests/run.sh
```

The directory above is the development fixture used for this phase; another
verified fzf installation can be selected through PATH instead. Both versions
receive real Ctrl+C/X/V, Alt+C/X/V, Alt+arrow, F1/F2/F7/F8, Ctrl+R/N and Delete
key events. The older Ctrl+C-aborts test now verifies safe refusal on the
synthetic parent row followed by Esc cleanup, matching the approved Copy binding.
The completed Explorer suite has 201 tests, all passing without skips on both
versions; [the report](../docs/phase-three-five.md) links the full TAP results.

For a subset, pass Bats paths or options to the runner:

```bash
bash tests/run.sh tests/global-search.bats
bash tests/run.sh --filter 'root' tests/filesystem.bats
```

To obtain private locate tools on Ubuntu/Debian without installing a service:

```bash
bash dev/prepare-locate-tests.sh
bash tests/run.sh tests/native-backends.bats
```

That optional preparation command downloads repository packages with apt and
extracts plocate/liburing under `.test-work/tools/`. Tests build databases rooted
only at disposable fixtures, with all system pruning policies explicitly
overridden. They never rebuild the system locate database. A system installation
of plocate/updatedb also works; preparation is not run automatically.

The filename-injection regression uses `$(printf hit > FZD_INJECTION_MARKER)` in
a filename. The original indexer created that marker in its disposable working
directory. The repaired application treats the entire filename as data. The
first regression commit intentionally records failures before their fixes.

Phase Three resolves the former shell-wrapper skip. A sentinel preserves stdout
through command substitution, and the wrapper removes exactly the protocol's one
final newline. Byte-exact tests and real installed Bash/zsh terminal sessions
verify directories ending in multiple newlines.

For the optional official-fzf bootstrap regression, prepare its pinned,
checksum-verified archive in the ignored workspace:

```bash
bash dev/prepare-fzf-test.sh
bash tests/run.sh tests/installer.bats
```

This optional preparation downloads the official Linux x86_64 fzf 0.65.2 archive;
it does not install a binary or execute an external script. The test copies the
archive through a curl stub, then exercises the real extraction, verification,
version probe, installation, update and uninstall code in a disposable home.
Without the prepared archive that one test explicitly skips. Download failure
and digest mismatch tests always run using controlled inputs. Source uninstall
preserves fzf, including a bootstrap it originally installed, as a shared
dependency. All 138 checks ran without skips in the Phase Three WSL environment.

apt/dnf/pacman tests verify real installer functions with controlled executables.
Four full installation profiles also replace os-release metadata inside an
isolated Ubuntu userspace; only each fixture is writable. They need bubblewrap
and user/network namespaces. These are not native Debian/Fedora/Arch package
transactions. No root host operation or
system locate database rebuild is part of this suite. Clean native distribution
and ARM validation remain packaging release gates; see
[packaging readiness](../docs/packaging.md).

Static checks used for this phase:

```bash
bash -n fzd.sh
shellcheck fzd.sh lib/*.bash tests/run.sh tests/helpers/*.bash \
  install.sh installer/*.bash shell/integration.sh \
  tests/helpers/installer.bash tests/helpers/installer-mv-stub \
  tests/helpers/fzf-stub tests/helpers/backend-stub tests/helpers/pty-session \
  benchmarks/*.sh dev/*.sh
shfmt -d -i 2 lib/*.bash tests/run.sh tests/helpers/*.bash \
  install.sh installer/*.bash shell/integration.sh \
  tests/helpers/installer.bash tests/helpers/installer-mv-stub \
  tests/helpers/fzf-stub tests/helpers/backend-stub tests/helpers/pty-session \
  benchmarks/*.sh dev/*.sh
shfmt -d -i 2 -ln bats tests/*.bats
git diff --check
```

The application file is not reformatted wholesale. The modernized installer,
dependency/lifecycle modules and shared shell integration are included in static
checks.

For a manual, isolated application baseline, run `bash dev/run.sh`. It copies the
example configuration once to `.test-work/manual/config/fzd/fzd.conf` and directs
FZD's state/cache/runtime there. It preserves later edits to that private config.
Its selected directory is printed to stdout; your existing shell wrapper remains
responsible for changing the parent shell's directory.

For warm-cache performance measurements on an otherwise idle machine:

```bash
bash benchmarks/hyperfine.sh 5
```

This prepares 1,000 files in ten directories, uses one warmup and five measured
runs, and exports JSON/CSV under `.test-work/results/`. Historical listing
functions are materialized before timing to avoid charging Git extraction to the
old revision. Candidate tests measure formatting from arrays, not filesystem
enumeration or fzf rendering. Other commands measure helper startup, live
index/query, text preview and optionally private locate queries. The `startup`
workload does not launch the TUI. No installation, theme generation or system
indexing is timed. The simpler `benchmarks/run.sh REVISION RUNS` remains available,
but arbitrary historical revisions include per-run extraction overhead.

Native distribution package transactions, system updatedb services, graphical
terminal key interception and wider architecture coverage remain separate
validation gates. Source installation lifecycle and both fzf 0.44.1 and 0.65.2
are exercised by the current regression suite.

Phase Two adds reproducible component and real-terminal matrices at 10, 100,
1,000 and 10,000 entries. See [../benchmarks/README.md](../benchmarks/README.md).
The terminal harness uses a monotonic Linux uptime clock with 10 ms resolution;
discarded wall-clock trials are explicitly separated from valid results.

Suggestion-engine fixtures are pinned to upstream ble.sh `d81fd54` (including its
contrib submodule) and zsh-autosuggestions `85919cd`. Preparation needs Git, Make,
and GNU Awk. They remain in ignored `.test-work/compat` and are never installed
into the user's shell. `FZD_COMPAT_ROOT` can select prepared fixtures. Hosted CI
requires these tests to pass without skips, on both supported fzf fixtures and
all four distribution userspaces. Tests use fresh zoxide databases through
`_ZO_DATA_DIR`; the user's real database and shell rc files are never touched.

The inline installer additionally tests official ble.sh v0.4.0-devel3-2, whose
release archive is SHA256-verified by fixture preparation and the installer.
Fresh Bash/zsh terminal tests source exactly the generated installation blocks;
no manual compinit, engine sourcing or suggestion configuration is injected.
Existing-framework tests check that completion is initialized once. Ubuntu,
Debian and Arch validators exercise the real opt-in installer with native plugin
dependency resolution and the official download in a disposable home. Fedora
continues its existing runtime validation; no additional RPM work is introduced.
