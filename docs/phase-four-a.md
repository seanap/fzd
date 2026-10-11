# Phase 4A: packaging and release validation

## Outcome and scope

FZD has a working architecture-independent Debian/Ubuntu package, a generated
Arch PKGBUILD with a pinned archive checksum, a manual/CI candidate build process,
and genuine clean-distribution lifecycle validation. No application feature,
navigation architecture, keyboard binding or preview behavior changed.

Work started from `026ad23` on `revamp/audit`. The measured validation candidate is
`e848a484aa726800c0d487b1c6414b175a018b13`, upstream version `0.1.0-rc.1`.
Later commits contain CI runtime pins and validation tests/evidence/documentation.
The final review snapshot's SOURCE record identifies its exact revision. No
merge, tag, push, package submission or public release was performed.

## Deliverables and build model

- `packaging/build-release.sh`: resolve one Git revision, archive it with stable
  timestamps/compression, run its own Debian builder, generate checksum-pinned
  PKGBUILD, and emit SOURCE plus SHA256SUMS. Uncommitted/untracked inputs are
  excluded. Existing output directories are refused.
- `packaging/build-deb.sh`: use the existing `install.sh --stage`, add Debian
  metadata, DEP-5 MIT copyright, compressed README/packaging guide/changelog and
  fzd(1). Normalize ownership/timestamps. No maintainer scripts or home files.
- `packaging/arch/PKGBUILD.in`: arch=any, MIT, explicit runtime dependencies,
  optdepends, immutable custom release archive checksum and documented source
  epoch. Actual makepkg generates .SRCINFO and an installable package.
- `.github/workflows/validate.yml`: static checks, both supported fzf versions,
  repeat builds, checksums/linting and Ubuntu/Debian/Arch/Fedora container jobs.
  Read-only contents permission, SHA-pinned Node 24 actions, no persisted
  credentials or publishing job. Candidate artifacts/logs are retained for review.
- `packaging/validate-distributions.sh` and `validate-container.sh`: real package
  managers in disposable official images, unprivileged tests, explicit result
  markers and archived prior attempts. No real host home is mounted.
- `packaging/benchmark.sh`: installed-runtime identity checks plus the existing
  component/workload/PTY harnesses; alternating terminal trial order.

The application, integration, configuration example, all three Explorer modules,
license and documentation are packaged. Source lifecycle tools/manifests are
excluded. User configuration and persistent Explorer state remain user-owned.
Shell integration is the single documented opt-in source line; existing lf names
are preserved. There is no package startup wrapper or initialization service.

Micro is a required default fallback because the frozen application uses it when
EDITOR/VISUAL is unavailable. Optional previews/search tools and recoverable Trash
are separate recommendations/optdepends. flock is provided by util-linux on
Debian/Ubuntu/Arch and util-linux-core on Fedora. No locate index is initialized.

## Executed validation

The host is Ubuntu 24.04.5 on WSL2, kernel 6.6.87.2, Linux filesystem checkout.
Authorized development installations added Podman, dpkg-dev, fakeroot and lintian
(31 MB downloaded, 130 MB installed including dependencies). Actionlint 1.7.7
was checksum-verified and extracted privately under .test-work; no application
dependency was added. Existing host user configuration was not used for installer
or filesystem-operation tests.

| Environment | Runtime dependencies observed | Executed result |
| --- | --- | --- |
| Ubuntu 24.04.5 official image | Bash 5.2.21, fzf 0.44.1, coreutils 9.4, findutils 4.9, util-linux 2.39.3 | APT minimal dependency resolution, install, revision-2 upgrade, dpkg verification, purge, retained settings/dependencies, shell startup, 201/201 tests |
| Debian 13/trixie official slim image | Bash 5.2.37, fzf 0.60.3, coreutils 9.7, findutils 4.10, util-linux 2.41.5 | Same real APT/dpkg lifecycle and 201/201 tests |
| Current official Arch base | Bash 5.3.20, fzf 0.74.5, coreutils 9.12, findutils 4.11, util-linux 2.42.4 | Real makepkg/pacman, revision upgrade/removal, verification, byte reproducibility and 201/201 tests |
| Fedora 44 official image | Bash 5.3.9, fzf 0.74.4, coreutils 9.10, findutils 4.10, util-linux-core 2.41.5 | Real DNF dependency installation, staged /usr payload, shell startup and 201/201 tests; no RPM lifecycle claim |
| Host extracted Debian payload, fzf 0.44.1 | Existing WSL development tools | 209/209, zero skips |
| Host extracted Debian payload, official fzf 0.65.2 | Same fixtures/tools | 209/209, zero skips |

Debian 13 is the current stable series according to the
[Debian release information](https://www.debian.org/releases/).
Images and installed packages are recorded in retained JSON/log evidence; tests
use actual distro binaries and package databases. These are distribution
userspaces sharing the WSL kernel, not simulated profiles or native desktop VMs.
The four older metadata/manager-profile tests remain explicitly simulated checks
inside the original suite.

The original 201 checks cover browser history, recents, cross-session clipboard,
recursive copying, cross-filesystem Cut through a private tmpfs, no-clobber
conflicts, symlink/descendant safety, permission failures, interrupted operations,
concurrent state writers, byte-exact unusual names, colors/previews/search,
Ctrl/Alt clipboard shortcuts, Rename/Create Directory, F8 confirmation, isolated
real gio Trash, F1 restoration, small terminals and Bash/zsh directory return.
Tests now support FZD_TEST_SCRIPT to execute the actual installed pathname.
Installed modules/integration are also copied into isolated source fixtures for
unit and source-installer tests.

Eight new packaging tests check payload completeness, runtime identity, no hooks
or home edits, dependencies, root ownership/permissions, fixed-epoch byte
reproducibility, upgrade ordering, invalid build inputs, immutable source content,
exclusion of .test-work, provenance and checksums. ShellCheck, Bash syntax, shfmt,
git diff --check and actionlint pass. Lintian has no errors; its sole warning is
initial-upload-closes-no-bugs, expected for a local first candidate without a
Debian bug to close. GitHub-hosted Actions have not been executed or claimed.

### Findings resolved during validation

1. Bash expands an unquoted tilde in a parameter replacement: the Debian version
   mapper initially produced a HOME path. Quoting the literal tilde fixes this;
   isolated-home package tests reproduce/protect the conversion.
2. Root bypasses Unix permission and sudo expectations. Container regression
   tests now run as an ordinary user; package transactions alone run as root.
3. Newer bubblewrap refuses /etc/os-release as a symlink bind destination. The
   simulated-profile fixture resolves its real target before binding.
4. The official minimal Arch image excludes documentation/manpages with
   NoExtract. Only this disposable test image's exclusions are removed so the
   complete package payload can be verified.
5. Two history PTY tests mistook preview contents for navigation completion.
   They now wait for the directory prompt, with a wider pane so fixture paths
   remain visible. Existing 60x16 behavior remains covered separately.
6. Arch .BUILDINFO records the installed package set. Installing FZD between
   two builds made the environments differ. Reproducibility comparison now
   precedes installation, with identical toolchain and SOURCE_DATE_EPOCH.
7. The final upstream check found GitHub had retired Node 20. CI now pins
   checkout v7.0.1 (`3d3c42e`) and upload-artifact v7.0.2 (`cf430e0`), with their
   official metadata verified as Node 24 and compatible workflow inputs.
   See [GitHub's runtime retirement notice](https://github.blog/changelog/2026-09-23-node-20-is-no-longer-available-in-github-actions/).

No release-blocking application defect required changing the frozen runtime.
All filename execution/security boundaries remain unchanged.

## Performance protection

The benchmark driver compares the frozen checkout and extracted final `.deb`
on the same otherwise-idle WSL host, using fzf 0.44.1. All distribution and Bats
jobs finished first. Component values are means of three measured runs after one
warmup; terminal values are three-trial medians with alternating source/package
order. The existing kernel-clock observation resolution is 10 ms.

| Entries | Phase 3.5 candidate mean | Source now | Package now | Source startup | Package startup | Source Right | Package Right |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 10 | 6.1 ms | 6.0 ms | 6.3 ms | 30 ms | 30 ms | 30 ms | 30 ms |
| 100 | 8.6 ms | 8.4 ms | 8.6 ms | 60 ms | 30 ms | 20 ms | 20 ms |
| 1,000 | 43.8 ms | 40.8 ms | 41.5 ms | 110 ms | 90 ms | 100 ms | 90 ms |
| 10,000 | 362.2 ms | 370.5 ms | 382.4 ms | 690 ms | 720 ms | 810 ms | 780 ms |

Full enumeration/sort/record preparation (source/package means) is 8.4/8.0 ms,
11.6/11.8 ms, 55.3/55.6 ms and 631.0/593.4 ms at the same sizes. At 1,000 entries,
packaged Left is 100 ms, first text preview 90 ms, changed preview 110 ms, global
overlay opening 20 ms and global query 210 ms (including existing reload/debounce
behavior). Phase 3.5's larger alternating PTY sample was 95 ms startup, 105 ms
Right and 95 ms Left. The user-provided approximate 38/90/90-100 ms Phase Three
baseline and final Phase 3.5 measurements remain in the same latency range.

| 1,000-file workload component | Source mean | Package mean |
| --- | --- | --- |
| Helper startup (not interactive render) | 7.8 ms | 7.9 ms |
| Global fd/find snapshot | 168.4 ms | 167.5 ms |
| Live global query | 41.5 ms | 47.2 ms |
| Private locate query | 18.7 ms | 18.6 ms |
| Text preview subprocess | 60.1 ms | 65.7 ms |
| Directory preview subprocess | 35.3 ms | 38.0 ms |
| Binary preview subprocess | 14.3 ms | 14.3 ms |

No material packaging regression is observed. These small samples do not prove
a speedup or statistical equivalence; preview/query and 10,000-entry differences
include normal host variability. No optimization was made to chase them.
10,000-entry navigation still takes roughly 0.7-0.8 seconds and remains a known
application limit, not a new package wrapper cost.

Stronger structural protection comes from byte identity: fzd.sh, all three modules
and shell integration match `026ad23`; Debian changes only the interpreter line.
The package executable's remaining bytes are compared before benchmarking.
Existing deterministic tests still protect one encoder per 1,000 local records
and bounded global batches. No startup wrapper, service, index or initialization
process was introduced. Raw CSV/JSON and all 24 PTY trial files are in
`benchmarks/results/phase-four-a/`.

## Evidence and release gates

The measured candidate is under `.test-work/phase-four-a/artifacts/`; its Arch
package/.SRCINFO/checksum evidence is under `.test-work/phase-four-a/arch/`.
These are local review artifacts, not published download locations. The source
archive, Debian package, generated PKGBUILD and SOURCE record match across two
builds using the same host toolchain. Arch reproducibility uses the recorded
source epoch and an unchanged installed build environment.

Ubuntu/Debian/Fedora and host full-suite evidence uses candidate `456648d`; the
final candidate `e848a48` changes only test-harness ordering and a README package
verification sentence. Its runtime, modules and integration are identical, and
the final packaging gate and Arch lifecycle use the final revision. Exact source
revisions and image digests remain in the raw evidence rather than being inferred
from the later documentation commit.

Retained evidence is under `docs/validation/phase-four-a/`: both 209-test host
transcripts, the final eight packaging checks, four actual 201-test distro
transcripts, normalized package-manager logs, OCI image metadata, unchanged-home
hash records, lint/static tool output, generated PKGBUILD/.SRCINFO, package
checksums and source revision records. Original logs and binary artifacts remain
under ignored .test-work. No sensitive real-home content is included.

Measured validation source archive SHA256:
`b74c2cc8fd9658ba96a3087dc2dc28234e3602b203278c66991ab9fd0562a5b9`.
Measured Debian package SHA256:
`6dc6c24f4fd5a4e1a67a0f663571b66bc8123f6c1bf751b6cf47120c3101e3bf`.
Validation Arch package SHA256:
`b19fc3a1e1fea9e728bbb1ae6172cbc16232982875f29f304ab77b76ce398fde`.
Both Debian dpkg ordering and actual Arch vercmp confirm that this candidate
sorts before 0.1.0 final.

The final review bundle is rebuilt under `.test-work/phase-four-a/review-artifacts/`
after the final README and Node 24 workflow pins are committed. It includes the
current documentation/workflow in its immutable source archive. Its SOURCE,
checksums, PKGBUILD, packaging checks and repeated actual Arch validation are
recorded separately under `docs/validation/phase-four-a/review/`. The measured
candidate above remains unchanged for benchmark provenance. All review/runtime
bytes are checked against the frozen application; these later changes do not
alter navigation or performance. Binary artifacts remain local and ignored.

Review the small implementation commits with:

```bash
git log --oneline 026ad23..revamp/audit
```

Remaining gates before public release:

- Explicit user approval to push/tag/publish, merge, upload the custom source
  archive and submit any distribution recipe. No public APT/AUR repository exists.
- Execute the committed workflow on GitHub after an approved push; local
  equivalents and actionlint cannot prove hosted execution.
- Confirm release identity/version and approved artifact checksums. The generated
  Arch HTTPS source URL intentionally remains unavailable until publication;
  local cache/checksum builds are verified now. Do not substitute GitHub's
  automatically generated archive for the reproducible custom archive.
- Choose signing/public provenance policy. SHA256 is integrity checking, not an
  independent publisher signature.

Supported validation scope is Linux x86_64 Ubuntu 24.04, Debian 13 and current
Arch, with Fedora 44 staged-runtime compatibility. Architecture-independent
packages contain no native application binary, but ARM64 has not been executed.
Native desktop terminal interception, native kernels, SELinux enforcement and
network/removable-filesystem Trash behavior are not exhaustively tested.
RPM/COPR, APT repositories, Debian source packages, AUR submission, Homebrew and
Pacstall remain future work requiring approval. Existing Phase 3.5 foreground
large-copy, cooperative-locking and power-loss limitations remain unchanged.
