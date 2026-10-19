# Packaging and releases

Packages use `install.sh --stage`; they never run the source installer on
installation, upgrade or removal. No maintainer scripts, automatic home edits,
themes, services or bundled fzf are shipped. Bash and fzf remain the architecture.

## Build one immutable revision

Build tools: Git, Bash, GNU coreutils/findutils/text utilities, tar, gzip,
xz-utils and dpkg (including dpkg-deb). Build without root or network:

```bash
bash packaging/build-release.sh HEAD .test-work/my-candidate
cd .test-work/my-candidate
sha256sum -c SHA256SUMS
```

The output directory must not exist. The revision is resolved once to a full
commit; `SOURCE` records that commit and its timestamp. All application,
documentation and builder inputs come from `git archive` of that commit, never
uncommitted files. Archives use `fzd-VERSION/`, Git commit timestamps and gzip -n.
Debian payload timestamps use SOURCE_DATE_EPOCH, root ownership and deterministic
compression. Repeat builds in the same toolchain must have identical checksums.
Cross-toolchain compressed-byte reproducibility is not promised; record tool
versions with validation evidence.

Outputs: source archive, architecture-independent `.deb`, generated `PKGBUILD`,
`SOURCE` provenance record and `SHA256SUMS`. SHA256 detects mismatches; it is not
a publisher signature. This release uses checksums and Git commit
provenance; it does not claim an independent cryptographic signature.

## Versioning

`VERSION` is MAJOR.MINOR.PATCH, optionally `-rc.N`. The current release is
`2.1.1`, following the previous public stable release `v2.1.0`. The build creates
no tag. Existing tags and the historical `v0.1.0-rc.1` draft remain unchanged.

| Upstream | Debian | Arch |
| --- | --- | --- |
| `2.1.1` | `2.1.1-1` | `2.1.1-1` |
| `2.1.1-rc.1` (example) | `2.1.1~rc.1-1` | `2.1.1rc.1-1` |

Prereleases sort below the final release. Packaging-only rebuilds increment the
distribution revision; application releases increment VERSION. The Debian builder
accepts FZD_DEB_REVISION=2 for upgrade tests. Arch uses pkgrel. Never replace a
published archive at the same version. Checksums identify the exact source commit.

Downloadable Debian files use `fzd-VERSION-debian-all.deb`, independently of the
internal Debian version and packaging revision. The stable filename is
`fzd-2.1.1-debian-all.deb`, while `dpkg-deb -f FILE Version` returns `2.1.1-1`.
For prereleases, Debian's tilde keeps the candidate below the final version;
GitHub normalizes tildes in asset names, so downloadable filenames never use them.
The builders emit the final filename directly and generate matching manifest
entries; do not rename files after building. Release filenames are restricted
to ASCII letters, digits, periods, underscores and hyphens, starting and ending
with a letter or digit. Regression checks cover stable and future RC versions,
exact manifest names, Arch source/checksum metadata and installation examples.

## Paths and ownership

| Component | Package path |
| --- | --- |
| Application | `/usr/bin/fzd`, the application itself, no startup wrapper |
| Explorer helpers | `/usr/share/fzd/lib/{state,operations,ui}.bash`, loaded lazily |
| Shell integration | `/usr/share/fzd/integration.sh`, opt-in |
| Example | `/usr/share/fzd/fzd.conf.example`, not an active configuration |
| Documentation | `/usr/share/doc/fzd/`, plus fzd(1) |
| MIT license | Debian `/usr/share/doc/fzd/copyright`; Arch `/usr/share/licenses/fzd/LICENSE.txt` |
| User configuration | `$XDG_CONFIG_HOME/fzd/fzd.conf` or `$FZD_CONF_FILE`, never package-owned |
| State/cache | Existing XDG paths, created at runtime and retained on removal |

Debian changes only the first line to `#!/bin/bash`, following
[Debian script policy](https://www.debian.org/doc/debian-policy/ch-files.html#scripts).
Remaining executable bytes and all modules match the frozen source. Source
install manifests/lifecycle scripts are excluded from packages.

## Dependencies

| Purpose | Debian/Ubuntu | Arch | Fedora compatibility |
| --- | --- | --- | --- |
| Bash >=4.4, fzf >=0.44 | bash, fzf | bash, fzf | bash, fzf |
| Zoxide >=0.9 | zoxide | zoxide | zoxide |
| GNU tools | coreutils, findutils, grep, sed, mawk or gawk | coreutils, findutils, grep, sed, gawk | Same with gawk |
| flock | util-linux | util-linux | util-linux-core |
| Default editor | micro | micro | micro |
| Search/previews | eza, fd-find, bat, file, tree | eza, fd, bat, file, tree | eza, fd-find, bat, file, tree |
| Optional Trash | libglib2.0-bin or trash-cli | glib2 or trash-cli | glib2 or trash-cli |
| Required index search | plocate | plocate | plocate |

Micro is explicit because the runtime uses it when EDITOR/VISUAL is
absent/unavailable. No editor variables are changed by FZD.
plocate is required and provides the indexing tools. Simple and Enhanced install
it without an additional flag and run `updatedb` if the default index is not ready.
`--no-updatedb` skips that installer step. Native package setup can independently
initialize indexing or enable its distribution schedule. FZD never edits indexing
exclusions, timers or services, and leaves custom databases untouched. See the
[indexing guidance](TECHNICAL.md#plocate-readiness-and-package-indexing).
Debian recommends preview/search tools and Trash; normal APT installs these,
`--no-install-recommends` does not. Arch optdepends are explicit user choices.
Without gio/trash-put, F8 reports the missing backend and leaves files untouched.
Permanent deletion is never substituted.

## Install, integrate, update and remove

Download `fzd-2.1.1-debian-all.deb`, `SHA256SUMS` and `SOURCE` from the
`v2.1.1` entry on [GitHub Releases](https://github.com/seanap/fzd/releases).
FZD is not in the official Ubuntu/Debian repositories; APT installs the
downloaded file and its dependencies.

```bash
sha256sum --ignore-missing -c SHA256SUMS
cat SOURCE
sudo apt install ./fzd-2.1.1-debian-all.deb
```

On fully updated Arch, download `PKGBUILD` from the same release into a clean
directory and run `makepkg -si` as a normal user. Its HTTPS URL fetches the exact
custom release archive; the pinned checksum is mandatory. Before publication,
place the matching locally built archive beside the recipe for validation.
No SKIP checksum or moving Git branch is used. An AUR listing requires separate
submission and announcement; the direct recipe does not require AUR availability.
Generate AUR metadata with `makepkg --printsrcinfo > .SRCINFO`.
For reproducible Arch builds, export the source epoch from the generated SOURCE
record before invoking makepkg (the PKGBUILD header also gives the exact value):

```bash
export SOURCE_DATE_EPOCH=$(sed -n 's/^source_date_epoch=//p' SOURCE)
makepkg --force
```

The Arch validator builds twice with this epoch and compares the package bytes.
Real Arch validation retains .SRCINFO and its package locally; hosted validation
retains metadata and checksums. Publication and AUR submission are separate steps.

Add this line to your Bash/zsh startup file, respecting ZDOTDIR:

```bash
. /usr/share/fzd/integration.sh
```

Open a new shell and run fzd_cd, or lf when that name is available. Sourcing
integration runs no external commands. Existing commands, editor settings,
LS_COLORS and themes are preserved. Raw fzd prints the chosen directory; only the wrapper
changes its calling shell's directory. No implicit system-wide integration hook
is installed.

Upgrade with a newer `.deb` through APT or a rebuilt Arch recipe. Remove with
`sudo apt remove fzd` / `sudo apt purge fzd` or `sudo pacman -R fzd`. Remove your
source line after uninstalling, or use the guarded form in TECHNICAL.md. User
configuration/state remain; package managers own only /usr payload files.

For source-to-package transitions, uninstall the user-local source copy first,
then install the package and opt in to package integration. Open a new shell to
clear old _FZD_INSTALL_BIN values; check command -v fzd and FZD_BIN if the wrong
copy starts. Neither ownership mechanism silently removes the other.

## Real distribution validation

Prepare the pinned x86_64 fixture and install Podman (or Docker). Tests modify
only disposable container filesystems. No host home, package-manager database
or container socket is mounted. Host networking permits package downloads; no
ports are exposed. Nested bubblewrap requires relaxed seccomp/AppArmor filters,
without privileged mode. Podman also unmasks container `/proc` submounts so the
tests can mount their own private procfs; `/sys` masks and the container capability
budget remain in place. Ubuntu-hosted runners permit unprivileged user namespaces
only for the disposable job. These settings belong to the test harness, never
the installed application.

```bash
bash dev/prepare-fzf-test.sh
bash dev/prepare-shell-compat.sh
bash packaging/validate-distributions.sh .test-work/my-candidate ubuntu
bash packaging/validate-distributions.sh .test-work/my-candidate debian
bash packaging/validate-distributions.sh .test-work/my-candidate arch
bash packaging/validate-distributions.sh .test-work/my-candidate fedora
```

Use rootless Podman normally. This temporary WSL setup uses
`sudo env FZD_CONTAINER_LOCAL_STORAGE=1 bash packaging/validate-distributions.sh ...`
for rootful Podman storage under ignored .test-work/containers/. Docker users set
FZD_CONTAINER_RUNTIME=docker. Tests use Ubuntu 24.04, Debian 13/trixie, current
Arch base and Fedora 44; actual image IDs/digests and dependency versions are
recorded. Tags follow security updates; evidence identifies each tested image.

Debian/Ubuntu exercise real APT/dpkg dependency resolution, revision-2 upgrades,
verification and purge. Arch exercises makepkg/pacman. Fedora is staged-runtime
compatibility, not RPM lifecycle validation. Installed executable/integration/
modules are copied into the fixture source layout for the installed regression suite,
including real tmux/fzf PTYs, isolated gio Trash, concurrency and private-tmpfs
cross-filesystem movement. Tests run as an unprivileged container user, so Unix
permission and sudo tests retain their meaning. Packaging tests run separately
in the Git checkout.

These are genuine distro userspaces sharing the WSL kernel, not native desktop,
SELinux or ARM64 coverage. Four older distributions.bats profiles remain
explicitly simulated checks. See [executed evidence](phase-four-a.md).

## CI and future work

The GitHub workflow uses read-only repository permissions, pinned action commits,
no persisted credentials and no push/tag/release/publish steps. It runs static
checks, regression tests with both supported fzf versions, repeated builds,
checksums/linting and real distro validation. Hosted artifacts retain only test
evidence, checksums and provenance; packages and source archives remain ephemeral
on runners until publication is separately approved. Local validation retains
the packages for review.
[Hosted workflow results](https://github.com/seanap/fzd/actions/workflows/validate.yml)
identify each tested source revision. Match the run's commit SHA with the
candidate's `SOURCE` record and checksums when reviewing release evidence.

Separate approval is required for public releases, signing/APT repositories,
Debian source packages, AUR submission, Homebrew, Pacstall, Fedora RPM/COPR and
ARM64 validation. All future recipes must stage the same payload without home
edits or invoking the user installer.

## Zoxide navigation feature

Zoxide >= 0.9.0 is a required upstream dependency in Debian and Arch metadata,
and in the source installer. Fedora staging validation installs its native
zoxide package. No zoxide executable or database is bundled. Packages include
the shell integration files and the detailed `TECHNICAL.md` guide. The source
installer owns both shell files through the existing transactional manifest.

The README uses a source-checkout installation path with an explicit option
for inline suggestions. Published packages and the matching source archive are
available on GitHub Releases. Suggestion engines are independent upstream
dependencies, never FZD package payloads. CI uses pinned, private engine fixtures.

## Optional inline setup

`--enhanced` (or the advanced `--inline-suggestions` flag) in the source installer installs the selected shells'
engine requirements and writes opt-in settings in dedicated XDG shell files.
Only minimal guarded source entries are added to startup files. Enhanced also
offers optional user-scope font setup; package staging performs neither step. ble.sh is an independently verified upstream download, kept as a shared
user-local dependency; zsh-autosuggestions is resolved through the distribution.
Neither engine is bundled in FZD's source/package artifacts. Debian Suggests and
Arch optdepends advertise zsh/zsh-autosuggestions. eza is a Debian Recommends
and an Arch recommended optdepend; source Simple and Enhanced attempt to install
it with fd, bat, tree and file. Missing optional packages preserve fallbacks. The package payload includes
`inline.sh`, activated only by explicit user configuration. Package staging never
runs downloads or edits shell startup files. The default integration initializes
fresh zsh native completion after startup without replacing an existing setup.
