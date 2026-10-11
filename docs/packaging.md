# Packaging and release candidates

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
a publisher signature. Signing/public provenance remains a release decision.

## Versioning

`VERSION` is MAJOR.MINOR.PATCH, optionally `-rc.N`. The first candidate is
`0.1.0-rc.1`; the build creates no tag.

| Upstream | Debian | Arch |
| --- | --- | --- |
| `0.1.0-rc.1` | `0.1.0~rc.1-1` | `0.1.0rc.1-1` |
| `0.1.0` | `0.1.0-1` | `0.1.0-1` |

Prereleases sort below the final release. Packaging-only rebuilds increment the
distribution revision; application releases increment VERSION. The Debian builder
accepts FZD_DEB_REVISION=2 for upgrade tests. Arch uses pkgrel. Never replace a
published archive at the same version. Checksums identify the exact source commit.

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
| GNU tools | coreutils, findutils, grep, sed, mawk or gawk | coreutils, findutils, grep, sed, gawk | Same with gawk |
| flock | util-linux | util-linux | util-linux-core |
| Default editor | micro | micro | micro |
| Search/previews | fd-find, bat, file, tree | fd, bat, file, tree | fd-find, bat, file, tree |
| Optional Trash | libglib2.0-bin or trash-cli | glib2 or trash-cli | glib2 or trash-cli |
| Optional index | plocate | plocate | plocate |

Micro is explicit because the unchanged runtime uses it when EDITOR/VISUAL is
absent/unavailable. No editor variables or locate databases are changed.
Debian recommends preview/search tools and Trash; normal APT installs these,
`--no-install-recommends` does not. Arch optdepends are explicit user choices.
Without gio/trash-put, F8 reports the missing backend and leaves files untouched.
Permanent deletion is never substituted.

## Install, integrate, update and remove

```bash
sha256sum --ignore-missing -c SHA256SUMS
sudo apt install ./fzd_0.1.0~rc.1-1_all.deb
```

On Arch, place generated PKGBUILD and matching archive together and run
`makepkg -si` as a normal user. The HTTPS source URL names the prospective
approved GitHub release. Until publication, the local archive satisfies makepkg's
cache with the same mandatory checksum. No SKIP checksum or moving Git branch
is used. Generate AUR metadata with `makepkg --printsrcinfo > .SRCINFO`.
Real Arch validation retains .SRCINFO and its package. The recipe is ready for
review/build; public source availability and AUR submission await approval.

Add this line to your Bash/zsh startup file, respecting ZDOTDIR:

```bash
. /usr/share/fzd/integration.sh
```

Open a new shell and run lf; use fzd_cd if lf already exists. Sourcing integration
runs no external commands. Existing commands, editor settings, LS_COLORS and
themes are preserved. Raw fzd prints the chosen directory; only the wrapper
changes its calling shell's directory. No implicit system-wide integration hook
is installed.

Upgrade with a newer `.deb` through APT or a rebuilt Arch recipe. Remove with
`sudo apt remove fzd` / `sudo apt purge fzd` or `sudo pacman -R fzd`. Remove your
source line after uninstalling, or use the guarded form in the README. User
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
without privileged mode.

```bash
bash dev/prepare-fzf-test.sh
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
modules are copied into the fixture source layout for the original 201 tests,
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
checksums/linting and real distro validation, retaining artifacts and logs.
GitHub execution cannot be claimed until approved push and a workflow run;
local equivalents are tested first.

Separate approval is required for public releases, signing/APT repositories,
Debian source packages, AUR submission, Homebrew, Pacstall, Fedora RPM/COPR and
ARM64 validation. All future recipes must stage the same payload without home
edits or invoking the user installer.
