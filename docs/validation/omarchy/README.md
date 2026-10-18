# Omarchy integration implementation and validation

Implemented on `feature/omarchy-integration`, building on the existing two-tier
installation work at `28a483a`. The complete validated revision is `4c85d58`
(runtime finalized at `b74e477`, installer policy at `49a17c6`, followed by test
isolation changes).
The final evidence commit changes documentation and retained results only.
No release tags, published assets, releases, or main branch were changed.

## Implementation

| Improvement | Result |
| --- | --- |
| Editor | Safe argument parsing, EDITOR before VISUAL, micro fallback, separate filename arguments; current Omarchy wrapper supplies its own `--` and reads editor selection on each open |
| Theme | Current Omarchy palette once per session; explicit FZD overrides win; inherited fzf palettes remain intact; resolved entry colors go directly to previews |
| eza | Standard recommendation in both modes; forced captured icons and explicit icon opt-out; existing palettes and tree/ls fallback retained |
| Fonts/shell | Reuses verified font coverage and engines; WSL host-font guidance; existing zoxide hooks, aliases, completion and startup preferences preserved |
| Clipboard | Alt+Y, Wayland wl-copy or X11 xclip/xsel; exact absolute path through stdin, status in border, no GUI requirement on headless systems |
| Images | Chafa symbols, bounded size/time, no animation; negotiates probe option for older distro releases; safe fallback on failure |
| Launcher | Optional `--enhanced --omarchy-launcher float|tile`; staged upstream helper, owned XDG desktop entry, interactive Bash retaining selected directory; reversible and idempotent |
| Markdown | Glow when present, pane width/no pager/user style retained; bounded input and fallback to bat/head |
| Lazygit | Alt+G only when separately installed and selected path is in a working tree; terminal handoff and query/session restoration; no redraw Git scans |

Simple and Enhanced run the same application. Capability activation has no
installation-mode flag. plocate is required in source prerequisite checks and
Debian/Arch metadata. eza, fd, bat, file and tree remain recommendations attempted
by both source modes. Enhanced additionally attempts Chafa, Glow and a suitable
display clipboard provider, and performs optional engine/font setup. Lazygit is
never installed automatically. Optional tools stay optional in package metadata.
Missing optional packages produce guidance and retain working fallbacks.

The dedicated XDG shell files, minimal source entries, custom startup paths,
ZDOTDIR, v2 migration, owned-file manifests, backups, rollback, recovery,
uninstall protections and private runtime storage remain in place. Package
staging performs no per-user setup. Source installation never executes custom
startup/configuration files. The launcher reads normal shell startup at runtime.

Current Omarchy source fixtures include its editor wrapper, theme utility, TUI
installer, Bash rc/init/aliases/inputrc, and Tokyo Night/Catppuccin Latte palettes.
Their MIT license, retrieval date and exact hashes are retained under
`tests/fixtures/omarchy/`. This is upstream compatibility testing, not a native
Omarchy installation claim. The current upstream README banner and branding from
`c3bf90b` were preserved; image/GIF assets were not redesigned.

## Indexing authorization is a deliberate first-install limitation

Native packages have indexing side effects: Ubuntu/Debian can invoke updatedb
in postinst, Fedora starts its service after installation, and Arch ships an
enabled timer. The source installer refuses the first missing-plocate package
transaction unless `--allow-package-indexing` explicitly authorizes native setup.
It explains this without prompting or changing FZD files. Installing plocate
manually is the alternative. Existing plocate installations need no extra flag.

This means the featured installation command cannot complete unattended on a
machine missing plocate unless that additional authorization is supplied. It is
an explicit exception to fully automatic dependency setup, necessary to preserve
the no-implicit-indexing requirement without modifying distro scripts, timers,
exclusions or user preferences. FZD itself never invokes updatedb. Distribution
package installation of FZD follows the distribution's own dependency setup
policy independently of the source installer.

The bounded readiness probe reports missing/empty/unreadable indexes and gives
review/initialization guidance; it does not initialize them. Runtime locate-first
search and existing failure/manual-install fallbacks are unchanged. Relevant
package source links and operational guidance are in `docs/TECHNICAL.md`.

## Local validation

Executed on Ubuntu 24.04.5 userspace under WSL2 (Linux
6.6.87.2-microsoft-standard-WSL2), Bash 5.2.21 and zoxide 0.9.3. eza 0.18.2,
Chafa 1.14.0 and plocate 1.1.19 were exercised from private extracted distro
packages; the host package database and user terminal configuration were not
changed. Tool versions are in `versions.json`.

| fzf | Passed | Blocked failures | Skipped | Bats exit |
| --- | ---: | ---: | ---: | ---: |
| 0.44.1 | 283 | 42 | 0 | 1 |
| 0.65.2 | 283 | 42 | 0 | 1 |

Each complete run reports failure because 36 tmux socket tests and six namespace/socket isolation tests are denied by the sandbox (`Operation not permitted`). Every failure was classified from its captured error block; no other failures were observed. These tests are retained as failing in the raw TAP, not converted into passing skips. The accessible tests, including all 27 new tests, pass. Raw output is retained in the two fzf TAP files and `tests.json`.


There are 27 new Bats tests, many with multiple cases. They cover safe editor
arguments and current Omarchy scripts, light/dark themes, color inheritance,
failed/cached adapters and WSL PATH scans, display provider selection and exact
clipboard bytes, image/Markdown fallbacks/timeouts, Lazygit context/handoff,
launcher ownership/escaping/rollback, dependency/index policy and repeat upgrades.
Existing suites retain font/engine presence/absence, WSL detection, Bash/zsh
customizations, XDG overrides and unsafe temporary paths, v2 migration,
noninteractive behavior, package staging and file preservation coverage.

Three new direct PTY tests work without tmux sockets: real fzf receives eza glyph
bytes with exclusions; the real shell launcher retains the selected directory;
clipboard/Lazygit actions resume local and global queries. Native GLib desktop
parsing verifies prefix paths with quotes, spaces, backslashes, dollar signs,
backticks and percent signs. A real PNG is rendered through Chafa. These do not
verify the active GUI terminal font, a real compositor clipboard, or the actual
Lazygit UI. Those interfaces use controlled providers/UI stubs. Glow rendering
is tested with CLI stubs and text fallback; no native Glow binary was available.

ShellCheck, shfmt, Bash/zsh syntax, workflow actionlint, fixture checksums and
`git diff --check` pass. Two builds from the immutable revision in `SOURCE` are
byte-for-byte identical for source archive, Debian package, PKGBUILD and provenance;
checksums verify. Lintian has no errors and one existing changelog warning
(`initial-upload-closes-no-bugs`). Local artifacts retain VERSION=2.0.0 solely for
validation and have not replaced any public release assets.

## Hosted and distribution validation remains unexecuted

The feature-branch git push failed because shell networking could not resolve
GitHub. An authenticated GitHub connector could read the repository, but its blob
upload returned HTTP 403, `Resource not accessible by integration`. No remote
branch or draft PR was created, and no hosted CI result is claimed.

Ubuntu, Debian, Arch and Fedora container validation was attempted; Podman stopped
before creating a container because its default runtime location was read-only.
A private runtime retry then failed because `newuidmap` is unavailable. These are
not native distribution passes. Package-manager fixtures and mocked distro
metadata tests do not substitute for real distro validation. The existing hosted
matrix is retained, with Python/Chafa added to its validation prerequisites.

Native Omarchy, Arch/Fedora/Debian sessions, Foot/Alacritty/Ghostty/Kitty visual
rendering, working tmux sessions, host GUI clipboards, actual Lazygit/Glow UIs and
native Linux font installation/terminal selection remain unverified here. Font
install/error/ownership scenarios use isolated fixtures. The optional launcher
currently supports Bash and skips zsh with guidance; normal zsh integration is
preserved. Unsupported preview versions and missing optional repository packages
fall back cleanly. WSL guidance correctly leaves host font setup to Windows.

## Performance

**Normal lf workload (11 measured trials per revision/size)**

| Entries | Startup ms, before → after | First preview ms | Next preview ms |
| ---: | ---: | ---: | ---: |
| 10 | 242.7 → 250.8 | 121.5 → 123.9 | 93.0 → 91.5 |
| 1000 | 301.2 → 301.3 | 163.1 → 159.2 | 95.2 → 87.1 |
| 10000 | 1141.6 → 1149.9 | 528.1 → 541.0 | 98.5 → 102.8 |

**Current-upstream Omarchy theme fixture (5 measured trials per revision/size)**

| Entries | Startup ms, before → after | First preview ms | Next preview ms |
| ---: | ---: | ---: | ---: |
| 10 | 176.6 → 180.0 | 94.3 → 100.9 | 66.7 → 66.1 |
| 1000 | 258.6 → 295.7 | 135.2 → 136.5 | 86.3 → 81.5 |
| 10000 | 938.4 → 999.5 | 451.1 → 462.2 | 84.9 → 78.3 |

Normal median startup differences are approximately +8, 0 and +8 ms; normal
first-preview differences range from −4 to +13 ms and next-preview differences
from −8 to +4 ms. The theme fixture adds approximately 3–61 ms at startup in this
batch; its subsequent preview transitions are unchanged or faster. Palette
querying is session-only, and preview helpers inherit resolved entry colors.
These are small normal-workload deltas, with measurable conditional theme
startup cost.

Use the existing real-fzf PTY runner:

```bash
python3 benchmarks/install-experience.py BASELINE_CHECKOUT OUTPUT 11
FZD_BENCH_OMARCHY=1 python3 benchmarks/install-experience.py BASELINE_CHECKOUT OUTPUT 5
```

Each workload alternates before/after observations with a fresh home, drops one
warmup per group, and runs without concurrent tests/builds. The normal workload
has 72 observations (11 measured trials plus warmup, two revisions, three sizes);
the current-upstream theme fixture has 36 observations. Raw trials, medians and
provenance are retained under `benchmarks/results/omarchy/`.

Benchmarking exposed a missing-tool lookup scanning the WSL Windows PATH on each
preview. That was removed; cached theme previews also skip module discovery and
palette reconstruction. Startup theme work runs once. Repeated batches varied
substantially on this shared WSL host, including opposite signs for large-list
startup differences, so these observations are not a cross-platform latency
promise or a native Omarchy benchmark.

## Review state

Once GitHub write/network access is available, pushing only the feature branch
will trigger the existing hosted validation workflow:

```bash
git push -u origin feature/omarchy-integration
```


Implementation and documentation are committed on the local feature branch.
The remaining acceptance gap is hosted CI and native platform/GUI validation,
which this environment cannot execute. Review the first-install indexing
exception and Bash-only optional launcher alongside the code. No merge, main
push, tag, release publication or public asset replacement was performed.
