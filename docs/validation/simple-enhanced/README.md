# Simple / Enhanced installation implementation and validation

Implemented on `feature/simple-enhanced-install` in `/home/htpc/fzd`.
Application/installer candidate: `262198ef5207c6f2c5236b6ee3f3e1de48b491bb`.
Baseline: `68686cf` (v2.0.0). Validation date: 2026-10-18, WSL2 x86_64.
The final documentation/benchmark commit adds this evidence without changing
application behavior. No release tag, VERSION, release publication, public asset,
project banner or terminal GIF was changed.

## Delivered behavior

- Plain `bash install.sh` provides Simple; `--enhanced` explicitly adds inline
  engines and optional font setup. Both reuse existing tools and provide native
  Bash/zsh Tab completion, normal zoxide integration, and existing XDG state.
- Recommended dependencies now default to **eza, fd, bat, tree and file**. Required
  dependencies, including fzf and zoxide, remain mandatory. Unavailable optional
  packages produce guidance and retain fallbacks. eza is a Debian Recommends and
  an Arch optdepend described as recommended. plocate/indexing is never installed
  or initialized automatically. Advanced dependency/engine flags remain available.
- eza previews explicitly use `--icons=always`; `FZD_ICONS=0` disables them.
  LS_COLORS and eza palettes retain unrelated entries; explicit FZD directory/file
  overrides apply only to that invocation. tree/ls fallback remains available.
- Generated `XDG_CONFIG_HOME/fzd/shell.bash` and `shell.zsh` isolate shell setup;
  startup files receive only a guarded source statement between existing markers.
  Custom startup paths, ZDOTDIR, symlinks, hooks, aliases and configuration survive.
  Edited/unmanaged shell files are never overwritten or claimed for deletion.
- v2 managed blocks migrate in place without executing them. Repeated installs
  add no duplicate initialization. Simple updates retain an earlier Enhanced
  inline opt-in; `--no-inline-suggestions` explicitly disables managed setup.
  Earlier shell preferences still win. Active/configured Bash engines keep their
  upstream settings, faces and opt-outs; zsh strategy order/colors are retained.
- Enhanced checks fontconfig glyph coverage, including a Nerd Fonts 3 material
  glyph, before downloading anything. Missing native Linux fonts use the official
  Nerd Fonts **v3.4.0** JetBrainsMono archive with an embedded upstream SHA256.
  One regular Mono face is validated and published at user scope without clobbering.
  Fonts and shared engines remain installed after uninstall. Font failures leave
  the committed core installation usable.
- WSL skips Linux font setup and gives Windows-side instructions. Terminal font
  selection remains explicit; availability does not prove the selected face.
- Relative XDG homes use specification defaults; traversal and unsafe explicit
  paths are rejected. Runtime selection checks ownership, mode, access and
  symlinks, with a cache fallback. Temporary users get private session directories,
  cleaned on ordinary errors/signals. Captured previews allocate no unused storage.
  Existing application data and legacy config migration are retained.
- Ownership manifests, private journals, backups, recovery and rollback remain.
  Historic shell files outside HOME are included in recovery targets. New XDG
  configuration/font directories are private; existing modes remain unchanged.
  Debian transactions retain modified conffiles and all package operations close
  input. Packages stage only distribution files and never configure users' homes.

Detailed policy and platform instructions: [TECHNICAL.md](../../TECHNICAL.md).

## Static checks and regressions

`bash packaging/check.sh` passes: Bash/zsh syntax, ShellCheck, shfmt, and whitespace
checks. Actionlint 1.7.7 also passes for the hosted workflow. The benchmark harness
parses with Python's standard AST parser and completed all 96 PTY sessions.

The **complete 298-test suite was executed on both fzf versions** against the
committed implementation. Neither run is a green full-suite result:

| fzf | Passed | Failed due to sandbox permission denial | Skipped |
| --- | --- | --- | --- |
| 0.44.1 | 255 | 41 | 2 |
| 0.65.2 | 255 | 41 | 2 |

Every failure's retained output contains `Operation not permitted`: the sandbox
blocks tmux Unix sockets and bubblewrap namespaces. The two skips require a real
eza executable, which is unavailable locally. The mocked eza argument/color tests
pass. CI/container setup installs eza and rejects any skipped tests; actual captured
glyph output in real fzf is implemented as a regression, but remains unverified here.

[0.44.1 TAP](fzf-044-tests.tap), [0.65.2 TAP](fzf-065-tests.tap),
[machine-readable counts](test-summary.json), [focused mode tests](mode-tests.tap).
The 25 mode tests pass, including real v2 installer migration, clean Simple and
Enhanced, reuse/missing tools, WSL/native branching, optional font failures,
custom/edited startup files, private XDG directories, and failed uninstall rollback
from old XDG locations outside HOME. Existing serialization/process-budget,
filesystem identity, zoxide, lifecycle, configuration and operation tests pass
where the sandbox permits their execution.

Font tests use controlled fontconfig/download responses for publication and real
SHA256 rejection for untrusted input. Existing pinned upstream ble.sh/fzf archives
are exercised in private homes. Native font download/installation with a real
fontconfig stack remains pending distribution execution; no real user font or
terminal setting was modified by tests.

## Packaging, reproducibility, and CI

Two builds from the immutable implementation commit are byte-identical:
source archive, Debian package, Arch recipe, provenance and checksum manifest.
Every manifest checksum verifies. [SOURCE](SOURCE), [SHA256SUMS](SHA256SUMS),
[verification log](reproducibility.log). Local candidates remain under
`.test-work/two-tier/final-build-a` and `final-build-b`; they were not published.
Lintian exits successfully with one existing warning,
`initial-upload-closes-no-bugs`, from the generated Debian changelog:
[lintian output](lintian.log).

Actual Ubuntu, Debian, Arch and Fedora validation was attempted against that
candidate. Each is blocked before container launch: the default runtime path is
read-only in this sandbox, and a retry with a private XDG runtime requires the
unavailable `newuidmap` helper. [Distribution summary](distribution-summary.json)
records the four current logs: [Ubuntu](distribution-ubuntu.log),
[Debian](distribution-debian.log), [Arch](distribution-arch.log),
[Fedora](distribution-fedora.log). Native lifecycle/regression/reproducibility results
for those distributions are therefore **pending**, rather than inferred from mocks.
The validator now runs actual Enhanced setup, checks NF3 coverage on native hosts,
and retains the existing package preservation and deterministic Arch rebuild checks.

The branch push failed with `Could not resolve host: github.com`:
[push output](push.log). Hosted CI has **not run** for this branch. Its existing
matrix covers both fzf versions, all four distribution userspaces, deterministic
builds and full suites with skip rejection; eza is now included in those runners.
No release or release-asset operation was attempted.

Automatic approval review rejected unsandboxed test execution because sandbox
escalation is disabled. Full approval-grade validation needs an environment that
allows Unix sockets/namespaces, supplies eza/container helpers and can reach GitHub.
The direct PTY observations below supplement the blocked tests; they do not turn
those failures into passes.

## Startup and preview observations

[Full benchmark report and samples](../../../benchmarks/results/simple-enhanced/README.md)
use real `lf`/fzf in direct PTYs without a tmux socket, an otherwise idle host,
15 alternating measured sessions per revision and directory size, and one warmup.
Medians in milliseconds:

| Entries | Startup before → after | First text preview before → after | Next text preview before → after |
| --- | --- | --- | --- |
| 10 | 146.5 → 140.6 | 112.3 → 100.1 | 65.8 → 63.2 |
| 1,000 | 224.1 → 223.1 | 115.7 → 101.6 | 68.0 → 64.6 |
| 10,000 | 835.7 → 832.1 | 131.9 → 142.8 | 67.7 → 62.9 |

No normal startup median regression was observed. Next-preview medians are stable
or lower. The 10,000-entry first-preview median increases by 10.9 ms; baseline and
candidate observations overlap substantially (123.2–192.7 versus 96.8–192.8 ms).
First preview includes query work. This is a small single-host observation, not a
cross-platform performance guarantee. Separate 20-run helper/renderer observations
are 75.5 → 69.2 ms for bat and 52.8 → 45.6 ms for tree (means).

## Remaining limits

- The current host cannot complete the tmux/bubblewrap suite, hosted CI or actual
  distribution validation. Those checks remain required before merging/releasing.
- eza glyph capture and native real-font installation need the prepared CI/native
  environment; current performance uses bat/tree fallbacks. Font coverage probing
  is representative, not proof of every icon in every eza theme/version.
- WSL users must install/select fonts on Windows. Native terminal font selection
  cannot be reliably detected or changed across emulators; the glyph check and
  `FZD_ICONS=0` offer explicit alternatives.
- ARM64, native desktop font selection and third-party terminal settings were not
  exercised. Existing fzf/zoxide minimums still apply to older distributions.
- SIGKILL/power loss cannot run temporary cleanup; private stale sessions can be
  removed when unused. Installer journals support explicit recovery, retaining
  the established durability limits and shared-dependency policy.
