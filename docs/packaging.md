# Packaging architecture and readiness

Phase Three prepares a package payload; it does not create or publish packages.
The interactive source installer is never a distribution post-install script.

## Responsibilities and paths

| Component | Source installation | Distribution package |
| --- | --- | --- |
| Application | `PREFIX/bin/fzd` (unchanged Phase Two script) | `/usr/bin/fzd`, or the package prefix's `bin/fzd` |
| Shell functions | `PREFIX/share/fzd/integration.sh` | Same relative path; opt-in sourcing |
| Configuration example | `PREFIX/share/fzd/fzd.conf.example` | Read-only example under the package prefix |
| User configuration | `$XDG_CONFIG_HOME/fzd/fzd.conf` or `$FZD_CONF_FILE` | User creates it; runtime defaults work without a file |
| State/cache/runtime | FZD's existing XDG paths | Created by the running application as the user |
| Dependencies | Explicit source-installer mode | Declared in package metadata; package manager owns installation |
| Source lifecycle metadata | `PREFIX/share/fzd/install.manifest` and private retained transactions | Not shipped |
| Themes | User chooses independently | Optional external packages/settings; no automatic changes |

The shell integration contains no external startup commands and does not source
the user's Bash configuration into their interactive shell. `fzd_cd` and `lf`
are defined only when each name is free. Both delegate to the same byte-preserving
wrapper. An explicit `FZD_BIN` or source install's `_FZD_INSTALL_BIN` selects the
application; package integrations normally resolve `fzd` through PATH.

The source installer offers dependencies, files, configuration and rc setup as
separate operations/options. `--stage` bypasses all dependency transactions,
configuration initialization, shell rc changes, verification probes, downloads
and source-install metadata. It copies exactly the application, integration,
example and MIT license, using standard executable/data permissions.

```bash
bash install.sh --stage "$PWD/package-root" --prefix /usr
```

Use the same command with the package's own build root and prefix. Homebrew Linux
can stage with its formula prefix. AUR, Pacstall and RPM recipes can copy these
files directly instead. A package build does not require Git, network access,
sudo, fzf, or an editor to be present. Bash and GNU coreutils (including install
and readlink) are build tools. Root-directory aliases are rejected as staging
destinations.

The common staging license path is `PREFIX/share/licenses/fzd/LICENSE.txt`.
Debian recipes must place appropriate copyright information in
`/usr/share/doc/fzd/copyright`. Recipes should set a policy-compliant Bash shebang
and interpreter dependency; Debian's script conventions are described in
[Debian Policy](https://www.debian.org/doc/debian-policy/ch-files.html#scripts).
The source runtime currently uses `/usr/bin/env bash`.

## Shell integration without modifying homes

Ship `/usr/share/fzd/integration.sh` and tell users to add this one line to their
chosen Bash/zsh startup file:

```bash
. /usr/share/fzd/integration.sh
```

This gives explicit consent, respects nonstandard startup files and ZDOTDIR, and
leaves every home untouched. A future optional system-wide integration package
could use distribution shell startup directories, guarded for interactive Bash
or zsh only, after testing each distribution's startup rules. It should still
preserve existing commands and never load FZD configuration or themes into the
parent shell. Do not assume `/etc/profile.d` covers every interactive shell.

Packages should not create `~/.config/fzd` or run updatedb. Without a configuration
file, FZD uses runtime defaults; users wanting the example's colors/search scope
copy the example explicitly. Package removal leaves user configuration intact
and relies on package-manager ownership, rather than the source uninstaller.
Keep the source lifecycle script out of the package payload to prevent competing
ownership mechanisms.

## Dependency policy

Require Bash >=4.4, compatible fzf >=0.44.0, GNU coreutils/findutils and the standard
text utilities used by the script. Test fzf behavior as well as its version.
Ubuntu's 0.44.1 and official 0.65.2 have been exercised locally. Recommend fd,
bat, file, tree and a usable editor; select the distribution's editor dependency
policy explicitly. Source installation checks the configured single executable
and otherwise ensures micro is available. Locate, eza, icons, hexdump and tput
remain optional. Do not start locate services or download a second fzf from a
package-maintainer script.

| Target | Next-phase recipe/build work |
| --- | --- |
| Debian/Ubuntu APT and downloadable `.deb` | Add `debian/` metadata, dependencies, copyright and architecture-independent build; lint and test install/upgrade/remove in clean supported releases |
| Arch/AUR | Add pinned source/checksum PKGBUILD, optional dependencies and opt-in shell instructions; build in a clean chroot |
| Homebrew Linux | Formula installs application/data and depends on modern Bash/fzf/GNU utilities; test the installed prefix and shell instructions; consult the [Formula Cookbook](https://docs.brew.sh/Formula-Cookbook) |
| Pacstall | Add recipe with pinned source/checksum and distro dependency policy; stage files without user installer or theme hooks |
| Fedora RPM/COPR | Add spec with `%{_bindir}`, `%{_datadir}`, license/docs and dependencies; test with a clean buildroot and installed RPM |
| Other Linux | Retain the dependency-free manual/staging path; verify GNU tool availability and compatible Bash/fzf |

## Evidence and release gates

Current evidence covers actual Ubuntu 24.04 WSL installation in disposable homes,
Bash/zsh wrappers, official x86_64 fzf download integrity, package staging and
controlled apt/dnf/pacman command tests. Four bubblewrap-isolated full installs
add simulated Ubuntu/Debian/Fedora/Arch metadata and manager commands, with the
host mounted read-only. These are not complete native Debian/Fedora/Arch
installations. No ARM machine, native distribution VM or
package repository was used. WSL does not prevent these installer tests; separate
distribution userspaces and native sessions remain release validation work.

Before publishing:

- Choose a version/release policy, immutable source archive and checksums.
- Build each recipe offline from the staged payload; inspect every packaged path.
- Declare the interpreter, runtime and recommended/optional dependencies using
  each distribution's supported names and policies.
- Test real clean Ubuntu, Debian, Fedora and Arch environments, including old fzf,
  missing tools, interactive sudo, upgrade/removal, shell startup and permissions.
- Execute ARM64 download/application tests before advertising that path as tested.
- Run the complete regression suite and monotonic PTY/performance checks on the
  packaged executable; compare to the protected Phase Two baseline.
- Test source-to-package transitions explicitly. Existing user-local FZD may
  shadow `/usr/bin/fzd`; neither installer should silently remove the other.
- Confirm license/doc placement, shell opt-in instructions, package linting and
  clean removal through the package manager.
- Obtain Phase Four approval before creating/publishing releases or repositories.
