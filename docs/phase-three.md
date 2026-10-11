# Phase Three engineering report

## Result

FZD now has a Bash installer with explicit dependency modes, safe user-local
installation, retained backups, atomic file replacement, updates, read-only
verification, owned-file uninstallation and interrupted-install recovery. Bash
and zsh share a byte-preserving shell wrapper. Existing `lf` commands and user
configuration are protected. A separate staging mode prepares distribution files
without touching user homes or invoking dependency managers.

The application script is **byte-for-byte identical to Phase Two**. Navigation,
global-search security, preview policy, keyboard controls and existing styling
inheritance remain unchanged. The complete suite passes **138 tests, no skips**,
preserving the previous 87 passing cases and resolving the former wrapper skip.
There are 50 new cases. Another 42 installer/terminal cases pass using official
fzf 0.65.2 instead of Ubuntu's 0.44.1.

Work used `/home/htpc/projects/fzd`, branch `revamp/audit`. All destructive and
installation operations used disposable homes/prefixes beneath `.test-work`.
No actual `/home/htpc` shell/application configuration, Windows configuration,
system locate index or production resource was modified. No development package
installation was needed: required tools were already available. Official fzf
release metadata and a checksum-verified archive were downloaded only into the
workspace. Nothing was pushed, tagged, released or published.

The verified host is `HTPC-Win11`, user `htpc`, Linux kernel
`6.6.87.2-microsoft-standard-WSL2`. Tool versions are Bats 1.10.0,
ShellCheck 0.9.0, shfmt 3.8.0, tmux 3.4, hyperfine 1.18.0 and bubblewrap 0.9.0.

## Architecture and responsibilities

| File | Responsibility |
| --- | --- |
| `install.sh` | Validate options/paths; orchestrate source installation, config initialization/migration, lifecycle operations and package staging |
| `installer/dependencies.bash` | Detect required/recommended executable aliases, numeric fzf version and actual action capabilities; map distro package names; bounded sudo/package transactions; opt-in verified fzf download |
| `installer/lifecycle.bash` | Track owned file hashes and rc paths; lock, journal, backup, atomically replace, roll back, recover, verify and uninstall |
| `shell/integration.sh` | Bash/zsh functions, exact pathname transport, cancellation/error handling, existing-command preservation; no external processes or configuration execution on sourcing |
| `fzd.sh` | Unchanged Phase Two application; runtime XDG state/cache and existing trusted Bash configuration loading |
| `fzd.conf.example` | Unchanged defaults/example, copied only for a missing user config |

Normal files go under `PREFIX/bin` and `PREFIX/share/fzd`, defaulting to
`~/.local`. A marked block sources the shared integration from Bash and/or zsh rc
files. It records the installed binary and configuration path, respects an
existing configuration override, and adds the prefix to PATH. Exported ZDOTDIR
selects zsh's startup directory. Symlinked dotfiles retain their links; their
user-owned regular target is backed up and edited. Unterminated final lines are
remembered and restored during uninstall.

An existing configuration is syntax-checked without execution and preserved.
If no current config exists, a legacy `~/.fzd/fzd.conf` is copied, leaving the
source intact; otherwise the repository example is used. `--no-config` and
`--shell none` allow manual or automated setup. Third-party appearance changes
are deliberately outside the installer: no bat/micro/terminal config rewriting,
vivid initialization or theme downloads occur.

The manifest is NUL-delimited data, never sourced shell code. File ownership is
restricted to the known payload. Updates reject unmanaged or locally modified
program files unless `--adopt` explicitly authorizes replacement with retained
backups. Uninstall removes only unchanged owned application files and identifiable
integration blocks. It preserves modified files, all user configuration,
cache/state, backups, dependencies and even a locally bootstrapped fzf, which
other tools may use. Empty source-install directories are retained.

## Audit findings: actual corrections

| Finding | Correction and evidence | Confidence / residual risk |
| --- | --- | --- |
| Noninteractive sudo probe skipped needed installs even when normal authentication could succeed | `installer/dependencies.bash:54` authenticates normally for interactive dependency mode; explicit noninteractive mode uses `sudo -n -v` and fails with guidance. Stub tests cover success, authentication failure and package errors. | Confirmed fix to installer control flow. Actual password entry was simulated; the development account has passwordless sudo. |
| Repeated unconditional apt updates and best-effort package bundles | Missing executable detection builds one deduplicated package transaction; apt metadata refresh happens once only when packages are missing. fd/fdfind and bat/batcat prevent redundant installation. | Confirmed by command logs and no-transaction tests with available tools. Native clean distro repository transactions remain a release gate. |
| README/installer forced fzf >=0.50 without evidence | `installer/dependencies.bash:11` checks >=0.44.0 and probes required start/load/pos/reload/no-clear support with inherited defaults cleared. Ubuntu 0.44.1 passes all 138 cases. | The old claimed minimum was overstated. 0.44.1 and 0.65.2 were executed; arbitrary older or modified builds are not inferred compatible merely from a version string. |
| Unpinned latest-release bootstrap and unchecked extraction | `installer/dependencies.bash:123` requires an explicit version and SHA256, downloads from the fixed official HTTPS release URL, verifies before extraction, and streams only the expected `fzf` archive member to a private file. | Real x86_64 0.65.2 success, download failure and digest mismatch tested. SHA256 checks the supplied digest, not an independent signature. ARM64 mapping/checksum documented but not executed. |
| Automatic bat/micro theme and shell LS_COLORS/editor changes | Theme operations and parent-shell config sourcing were removed. Existing colors/editor values are forwarded to the child application without rewriting the parent environment. | Preservation tests cover bat/micro settings, EDITOR/VISUAL/LS_COLORS, and Bash-only configuration loaded from zsh integration. Existing changes made by the legacy installer are not automatically undone. |
| Existing lf function/alias could be overwritten; zsh used Bash-specific type checks | `shell/integration.sh:38` defines `lf` and `fzd_cd` only when each name is free. Bash/zsh-compatible function declarations also avoid interactive alias-expansion syntax errors. | Functions, aliases, executables and Bash expand_aliases mode tested. If both public names are already occupied, neither is overwritten. |
| Trailing-newline directory names were lost through command substitution | `shell/integration.sh:4` adds a sentinel, preserves exit status, then removes the sentinel and exactly one protocol newline. | All legal non-NUL filename bytes, multiple trailing newlines, failures and cancellation tested; real installed Bash/zsh + fzf sessions change the parent shell to the exact target. |
| Hardcoded XDG paths and ignored ZDOTDIR | `install.sh:95` validates configurable paths; `installer/lifecycle.bash:213` emits quoted integration pointers using actual locations. | Custom prefix/XDG/config/ZDOTDIR paths with spaces, quotes, Unicode and newlines tested. Unexported shell-local ZDOTDIR cannot be read by a child process. |
| No ownership-aware uninstall or interruption recovery | `installer/lifecycle.bash:16,48,100,300` implements private journals, retained backups, locks, rollback and recovery. Temporary rollback paths are unique, including deletion rollback. | Fault injection covers failed publication, TERM, KILL, interrupted lock recovery and failed uninstall after a deletion. Tests preserve unrelated temporary-looking files. Power-loss durability is not established. |
| Failed or empty path resolution must not misdirect installation | `install.sh` preserves the resolver's failure status and rejects empty/root/ambiguous canonical prefixes before writes. Staging roots are also canonicalized and root aliases rejected. Required GNU base64/sort flags are probed. | Resolver failure, empty output, root aliases, colon/symlink paths and incompatible serialization tools are covered by controlled regressions. Dangerous staging aliases are tested only with the host mounted read-only. Application pathname handling remains unchanged. |

The installer no longer needs Python. `--no-updatedb` remains accepted for legacy
invocations, but no mode invokes updatedb. Application and search backends do not
depend on installer modules, so installation metadata adds no runtime work.

The compatibility decision is supported by both executed tests and
[Ubuntu's Noble fzf package information](https://packages.ubuntu.com/noble/fzf).
The optional pinned binary/digest came from the
[official fzf 0.65.2 release metadata](https://api.github.com/repos/junegunn/fzf/releases/tags/v0.65.2).

## Compatibility and verification

| Target | Executed evidence | Limit |
| --- | --- | --- |
| Ubuntu 24.04.5, Bash 5.2.21, zsh 5.9, WSL2 | Actual installation/update/verification/uninstall in disposable homes; real fzf 0.44.1; installed Bash/zsh parent-shell PTYs | This is not a clean machine with every package initially absent, or a native graphical Linux session. |
| Ubuntu and Debian apt profiles | Full installer runs inside bubblewrap with selected os-release metadata, package/sudo stubs, and missing findutils; one update and one deduplicated installation | Ubuntu userspace; simulated distro/package commands, not native Debian package installation. |
| Fedora dnf profile | Same isolated full installer flow; correct dnf arguments and package mappings | No native Fedora userspace/repository transaction executed. |
| Arch pacman profile | Same isolated full installer flow; no automatic metadata-only refresh or partial upgrade | No native Arch clean-chroot package installation executed. |
| Official fzf 0.65.2, Linux x86_64 | Verified real release archive, extraction/version checks, user-local install/update; 42 terminal/installer cases | fzf changes its default pointer from `>` to `▌`; the test now verifies selection with either. Existing compatible fzf is kept, and FZD inherits user styling. |
| Linux arm64 bootstrap | Fixed architecture mapping and official published digest documented | Not executed on ARM hardware/emulation. |

Distribution-profile tests mount the host read-only, expose only their fixture as
writable, and isolate network/PID namespaces. Their stubs are the only reachable
package manager/sudo commands. Some Codex sandbox calls denied Unix sockets or
NETLINK setup; approved runs outside that tool sandbox passed. These were sandbox
restrictions, not WSL failures. Every included regression ran on WSL without skips;
native distribution and ARM coverage are still explicit packaging release gates.

The README installer invocation (`--deps recommended`) was also executed from a
fresh **local clone** of `revamp/audit` in an isolated home, followed by the
installed `--verify` and `--uninstall` commands. The clone source was local to
avoid publishing or executing unreviewed remote installer contents. GitHub quick
installation naturally requires these reviewed changes to reach the public
default branch; no remote was changed in this phase.

## Regression and static-analysis results

- Full suite with Ubuntu fzf 0.44.1: **138 passed, 0 failed, 0 skipped**.
- Additional fzf 0.65.2 run: **42 passed, 0 failed, 0 skipped**.
- ShellCheck passes for the application, installer/modules, integration,
  benchmarks, development scripts and shell test helpers.
- Bash syntax checks pass for executable/source scripts; zsh syntax checks pass
  for the shared integration. shfmt checks pass for maintained scripts and Bats
  tests; the unchanged application is not reformatted wholesale.
- `git diff --check` passes. Encoder process-budget, injection, stream-first
  search, navigation and all earlier application regressions remain protected.

Raw TAP evidence is in [validation/phase-three-tests.tap](validation/phase-three-tests.tap)
and [validation/phase-three-fzf-0.65-tests.tap](validation/phase-three-fzf-0.65-tests.tap).
The optional prepared-release fixture is reproducible with
`bash dev/prepare-fzf-test.sh`; see [test instructions](../tests/README.md).

## Performance preservation

The protected `d3315f8` application, checkout application and actual installed
executable share SHA256
`57b3ae329e307827b7db06d6909060acf3549923261127bc65955c5d42bd2860`.
The new shell startup block/integration uses only shell builtins and launches no
external process when sourced. The application does not read installer metadata.

Components used the existing hyperfine fixtures, one warmup and three runs per
command, sequentially on this WSL host. Values below are **mean milliseconds**;
small differences are not optimization claims. JSON preserves standard deviations
and samples, including outlier warnings and shell-calibration limits for the
shortest cases.

| Entries | Candidate records: Phase Two / current | Enumeration + sorting + records: Phase Two / current |
| ---: | ---: | ---: |
| 10 | 5.4 / 5.7 | 8.1 / 6.2 |
| 100 | 8.2 / 7.0 | 11.0 / 9.9 |
| 1,000 | **42.0 / 38.1** | **51.8 / 48.9** |
| 10,000 | 364.3 / 332.0 | 593.3 / 525.9 |

| Component | Phase Two / current mean ms |
| --- | ---: |
| Helper startup (no TUI) | 7.05 / 7.06 |
| Global index, initial 3-run pair | 159.8 / 171.9 |
| Live fd query | 45.1 / 45.3 |
| Private locate query | 17.0 / 17.5 |
| Text preview | 54.9 / 56.3 |
| Directory preview | 34.2 / 34.5 |
| Binary preview | 12.9 / 14.0 |

The index difference was investigated with two warmups and ten measured runs
against the installed executable: **172.2 ± 6.1 ms vs 178.5 ± 12.6 ms**, with
overlapping ranges (163.4–180.0 vs 164.7–208.3 ms). The earlier Phase Two historical
mean was 172.5 ms. Together with identical application bytes, this does not
establish an installer-induced performance regression. It illustrates the limits
of small WSL samples; no runtime change was made to chase that noise.

Real terminal comparisons use the existing monotonic `/proc/uptime` harness,
**10 ms clock resolution**, three samples per event, and the **installed
executable** for the current run. These are startup-to-render and
keypress-to-render observations, including fzf and shell callback costs.

| Entries | Startup: before / installed | Right: before / installed | Left: before / installed |
| ---: | ---: | ---: | ---: |
| 10 | 40 / 30 ms | 20 / 20 ms | 20 / 20 ms |
| 100 | 50 / 40 ms | 60 / 20 ms | 20 / 20 ms |
| 1,000 | **90 / 90 ms** | **90 / 100 ms** | **90 / 90 ms** |
| 10,000 | 640 / 660 ms | 700 / 720 ms | 680 / 710 ms |

At 1,000 entries, installed startup ranged 90–110 ms, Right 80–100 ms, and Left
80–100 ms. Live global opening remained 10 ms median, live query rendering was
210/200 ms, and cached opening for 2,001 candidates was 350/360 ms. Direct
Down-arrow preview movement remained **70/70 ms**; query-to-preview medians were
100/100 ms and query-change previews 90/110 ms with overlapping ranges. No
primary-screen gap was observed at the polling resolution. Wrapper functionality
is separately verified in real installed parent-shell sessions; the benchmark
times the application process rather than parent startup-file parsing.

The 1,000-candidate responsiveness target remains comfortably met. The 10,000
entry and synchronous cache-opening limits remain Phase Two characteristics;
there is no new persistent index or fzf architecture. Raw JSON/CSV and all event
medians/ranges are in [benchmarks/results/phase-three](../benchmarks/results/phase-three/).

## Documentation, packaging and remaining work

The revised README covers one-command source installation, prerequisites,
manual/noninteractive modes, Bash/zsh and custom ZDOTDIR, configuration, optional
appearance, compatible fzf downloads, updates, verification, uninstall and
recovery. It removes the incorrect fzf minimum, legacy config guidance and theme
side effects. Existing manual/unmarked legacy startup lines are deliberately not
deleted; users can use `fzd_cd` if an existing `lf` remains in control.

[Packaging architecture/readiness](packaging.md) defines the standard staged
payload and ownership boundary for Debian/APT, AUR, Homebrew Linux, Pacstall and
Fedora RPM/COPR. Packages must use their own dependency/ownership mechanisms,
never invoke the interactive source installer or edit every user's home. Shell
integration is an opt-in sourced file. No package recipes were published.

Remaining release gates are native clean-distribution installation/upgrade/remove
testing, ARM execution, actual password-prompt validation, package-specific
interpreter/license/dependency policies and source-to-package transition tests.
Unexported ZDOTDIR, manually altered rc blocks, PID reuse in stale-lock checks and
storage/power failure require conservative handling rather than forced cleanup.
Configuration is still trusted executable Bash at application runtime; syntax
checking does not sandbox it or validate every semantic setting. Backups and
dependencies are intentionally retained and need explicit user review for any
later removal.

Phase Three stops here. Publishing GitHub Releases or distribution packages
requires Phase Four approval.

## Commit review order

1. `1a1aaf7` — exact directory bytes and shared Bash/zsh wrapper regressions.
2. `1fa6f57` — preserve aliases when interactive shells parse integration.
3. `3be8dba` — isolated dependency policy and bounded distro transactions.
4. `0f1fbf6` — transactional source lifecycle, configuration preservation and tests.
5. `2015c88` — uninstall recovery, prefix validation and isolated distro profiles.
6. `6679de0` — repeatable component/installed-terminal performance evidence.
7. `b78b825` — reject failed path resolution and incompatible GNU flags.
8. `81c98f5` — reject package staging aliases resolving to the filesystem root.
9. Documentation/evidence commit — revised README, packaging readiness, this
   report and the two final TAP runs.
