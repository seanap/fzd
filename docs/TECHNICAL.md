# FZD technical guide

[Back to FZD](../README.md) · [Packaging and reproducible builds](packaging.md)

## Navigation and zoxide

Source `shell/integration.sh` from the checkout, or the integration path installed
by the source installer or package. Bash and zsh provide these commands:

| Command | Action |
| --- | --- |
| `lf` / `fzd_cd` | Explore the current directory |
| `lf imm` | Change directly to zoxide's highest-ranked match |
| `lf docker immich` | Match multiple terms using upstream zoxide's ordering |
| `lf /srv/media` / `lf -- DIR` | Change to an explicit directory; `--` forces a path |
| `lf -` | Return to the previous shell directory |
| `lff` / `fzd_find` | Open global discovery |
| `lff immich` | Open global discovery with the query already entered |

An existing directory takes precedence over keywords. No zoxide match opens
FZD's global search with the original query. Cancelling discovery returns to
local exploration; cancelling that preserves the calling shell's directory.
Raw `fzd [DIRECTORY]` explores without changing the parent shell; `fzd --global
[QUERY]` starts in discovery. Quote a multiword query when invoking raw `fzd`.

FZD uses upstream [zoxide](https://github.com/ajeetdsouza/zoxide) directly for
matching, ranking and persistence. There is no second navigation database.
Successful shell jumps are learned. Explorer visits are batched into `zoxide
add` on exit, including cancellation, without adding work to directory redraws.
An abrupt SIGKILL/power loss cannot flush pending visits. FZD's existing bounded
recent-directory list remains available through Alt+H; it is not a ranking index.

In an interactive shell, initialization is deferred until the first prompt so
an existing `zoxide init` anywhere in shell startup wins. If zoxide has not been
initialized, FZD runs upstream `zoxide init SHELL --no-cmd --hook pwd`. This
learns ordinary shell navigation and leaves existing `z`/`zi` commands alone.
Existing upstream hooks, `--cmd` and `--hook none` configurations are respected;
repeated sourcing adds no duplicate hook. Bash prompt arrays and zsh chpwd hooks
are retained. FZD does not replace `cd` or bind any keys in the user's shell.

Zoxide's `_ZO_DATA_DIR`, `_ZO_EXCLUDE_DIRS`, `_ZO_MAXAGE` and
`_ZO_RESOLVE_SYMLINKS` retain their upstream meanings. Normal shell learning
requires an interactive prompt/chpwd hook. Noninteractive FZD jumps still learn.
Upstream zoxide 0.9.3 excludes paths containing newlines; FZD still browses and
changes directly to every legal pathname, and unmatched queries use discovery.
FZD does not implement alternate matching rules to bypass zoxide exclusions.

## Tab completion and inline suggestions

Native Bash and zsh completion reads `zoxide query --list`, preserving upstream
rank order. Leaf names that extend the current word let `lf imm<Tab>` become
`lf immich`; multiple keywords constrain suggestions. Local directory completion
is also available for the first argument. Full paths are offered when a learned
match cannot be expressed as a matching leaf name. Missing/control-character
paths are omitted from learned suggestions; direct path navigation still works.
Completion never scans global roots or opens an interactive picker.

Existing `lf`, `lff`, `fzd_cd`, `fzd_find` commands, aliases and executables are
preserved, along with registered completion handlers. Use the free fallback
names when another application owns `lf`/`lff`. Load integration after defining
commands that should take precedence. In zsh, initialize native completion with
`autoload -Uz compinit; compinit`; FZD can be sourced before or after compinit.
FZD does not run compinit, change completion styles, or configure suggestion engines.

Tab completion and inline ghost text are separate features:

- **Bash + [ble.sh](https://github.com/akinomyoga/ble.sh):** its programmable
  completion source can suggest learned names inline when automatic completion
  is enabled and not suppressed by the user's ble.sh settings.
- **zsh + [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions):**
  the default `history` strategy suggests previous commands. To also use learned
  completions, users may opt into `ZSH_AUTOSUGGEST_STRATEGY=(history completion)`
  in their own zsh configuration. The upstream completion strategy requires zpty.
- **Plain Bash/zsh:** Tab completion works; inline suggestions require an engine.

FZD never installs, replaces or reconfigures these engines. Suggestions must
extend the typed prefix; some non-prefix/case-changing matches can only appear
on Tab. Pressing Enter on `lf imm` resolves the query without accepting a suggestion.

The regression suite uses pinned upstream engines in private test homes and real
PTYs. It checks that a displayed suffix is absent from the editable buffer before
acceptance, then checks Right-arrow acceptance. Prepare fixtures with `bash
dev/prepare-shell-compat.sh`; see [test instructions](../tests/README.md).

## Install

For the feature preview, use the source-checkout command in the [README](../README.md#install).
Package examples below apply to locally built candidates or explicitly published
assets; this feature has not been released.

**Prerelease for testing: `v0.1.0-rc.2`.** Get its assets from
[GitHub Releases](https://github.com/seanap/fzd/releases). If this candidate is
not listed, publication is still pending. FZD is not available in the official
Ubuntu or Debian repositories.

Tested on Linux x86_64: Ubuntu 24.04, Debian 13 and current Arch Linux. Fedora 44
has staged-runtime validation, not an RPM package. ARM64 is not yet validated.

For Ubuntu/Debian, download `fzd-0.1.0-rc.2-debian-all.deb`, `SHA256SUMS` and `SOURCE`
into a clean directory. Verify the checksum and source revision, then install
with APT so dependencies are resolved:

```bash
sha256sum --ignore-missing -c SHA256SUMS
cat SOURCE
sudo apt install ./fzd-0.1.0-rc.2-debian-all.deb
```

For Arch, download `PKGBUILD` from the same release into a clean directory and
run `makepkg -si` as your normal user. It fetches the exact custom release archive
and verifies its pinned checksum. Fully update Arch before building; avoid
partial upgrades. Use this recipe directly unless an AUR listing is explicitly
announced; do not assume the package is available in AUR.

`SOURCE` identifies the immutable Git commit used to build the release.
Checksums provide integrity checking, not an independent cryptographic signature.

Packages leave your home and shell startup files untouched.
Add this line to `~/.bashrc` or
`${ZDOTDIR:-$HOME}/.zshrc`, then open a new terminal (or run the line now):

```bash
. /usr/share/fzd/integration.sh
```

Run **`fzd_cd`**, or **`lf`** when that name is available. Existing `lf` commands
are preserved. Defaults work without copying a configuration file. Package
details and reproducible builds are in [Packaging](packaging.md).

### From source

Use Linux with Bash 4.4+ and GNU utilities. Bash and zsh are supported as
interactive shells. Ubuntu/Debian, Fedora, and Arch dependency managers are
supported. The source installer is separate from package installation; it owns
only its user-local files. Other Linux systems can use the manual installation
below. See [Packaging](packaging.md) for build and validation details.

Download the custom `fzd-0.1.0-rc.2.tar.gz`, `SHA256SUMS` and `SOURCE` from the
same release. GitHub's automatically generated source links are different archives.
Extract the custom archive and install as your normal user:

```bash
sha256sum --ignore-missing -c SHA256SUMS
cat SOURCE
tar -xzf fzd-0.1.0-rc.2.tar.gz
cd fzd-0.1.0-rc.2
bash install.sh --deps recommended
```

The installer prints the missing packages before installing them. It requests
sudo only for those packages, then installs FZD under `~/.local` and adds a small,
marked block to your Bash/zsh startup files. Open a **new terminal** and run:

```bash
lf
```

If you already have an `lf` command, function, or alias, FZD preserves it. Use
`fzd_cd` instead. Raw `fzd` prints the chosen directory; the shell function is
what changes your shell's directory.

No editor settings, terminal themes, `LS_COLORS`, or locate databases are changed.
Original files are backed up before replacement. Existing FZD configuration is
preserved. Upgrading from the old installer may require `--adopt`: this explicitly
replaces unmanaged FZD program files and retains their originals in backups.
It does not authorize changing other applications' settings.

## Controls

| Key | Action |
| --- | --- |
| Left | Parent directory; highlight the child you came from |
| Right | Enter the highlighted directory |
| Enter | Directory: return to the shell there. File: open the editor, then resume |
| Esc | Cancel; keep the shell's current directory |
| Ctrl+F | Global search; Esc returns to local navigation |
| Type | Fuzzy filter the current directory |
| Alt+Left / Alt+Right | Back / Forward through this session's directory history |
| Alt+H | Recent directories; Enter visits, Esc returns |
| Ctrl+C / Alt+C | Copy the highlighted item into FZD's internal clipboard |
| Ctrl+X / Alt+X | Cut the highlighted item; source stays in place until Paste |
| Ctrl+V / Alt+V | Paste into the directory being browsed |
| Ctrl+R / F2 | Rename the highlighted item |
| Ctrl+N / F7 | Create a directory |
| F8 | Move to Linux Trash after confirmation; requires a Trash tool |
| F1 | Contextual help; F1 or Esc closes it |
| Ctrl+G | Exit FZD; Ctrl+C now copies while browsing |

Global search also supports Copy/Cut on the highlighted result, then returns to
the directory view. F1 explains the controls available in each view. Delete
continues to edit the fuzzy query.

Some terminal emulators intercept Ctrl+C/V or Alt+arrow keys. Use the Alt+C/X/V
fallbacks or adjust the emulator's key assignments to deliver the shortcuts to
FZD. The clipboard belongs to FZD and is separate from the desktop clipboard.

## File operations and history

Copy or Cut one highlighted item, navigate to a destination, then Paste. Copy
preserves directory trees, permissions where supported, and symbolic links.
Cut moves only after Paste succeeds, including across filesystems. Existing
destinations cancel Paste or Rename; the clipboard remains available for retry.
Choose another directory or rename the source before retrying. Copy remains
available for repeated pastes; a completed Cut clears the clipboard.

Rename starts with the current name. Enter confirms; Esc cancels. Names with
control characters or invalid UTF-8 bytes use visible escapes in the prompt:
`\n` for newline, `\t` for tab, `\r` for carriage return, `\e` for Escape,
`\xHH` for a byte, and `\\` for a literal backslash. Existing names are
prepopulated automatically; spaces and ordinary Unicode can be typed directly.
The newly created or renamed item remains highlighted.

F8 offers **Cancel** first. Choose **Move to Trash** to confirm. Restore items
through your desktop's Trash or the installed Trash tool. Install `gio` or
`trash-cli` to enable this feature; on Ubuntu/Debian, `gio` is provided by
`libglib2.0-bin`. FZD reports unavailable or unsupported Trash operations and
never substitutes permanent deletion. Large copies and cross-filesystem moves
run in the foreground; Ctrl+C during an active operation interrupts it and exits
FZD.

Back/Forward keeps up to 100 visits in memory and restores highlighted items
where possible. A new visit after Back replaces the forward branch. Up to 25
unique recent directories and the clipboard persist under
`${XDG_STATE_HOME:-$HOME/.local/state}/fzd/explorer/` (or your configured
`FZD_STATE_DIR`). Missing recent directories are skipped. These features use no
filesystem index or background process. Uninstallation preserves this state.

## Prerequisites and dependency choices

| Level | Tools |
| --- | --- |
| Required | Bash 4.4+, fzf >= 0.44.0 with the tested bindings, zoxide >= 0.9.0, GNU coreutils, findutils, flock (util-linux), standard Linux text utilities, and an editor |
| Recommended | fd/fdfind, bat/batcat, file, tree |
| Optional | gio or trash-put for Trash, plocate/locate with an existing index, eza and a compatible icon font, hexdump, tput |
| Optional download | curl, CA certificates, tar, gzip |

`--deps none` (the default) checks prerequisites without package transactions.
`--deps required` installs only missing required tools. `--deps recommended`
also installs the preview and search tools above. Ubuntu/Debian use packages
`fd-find` and `bat`, whose executables may be `fdfind` and `batcat`.

Set `EDITOR` or `VISUAL` to a **single executable name or path** to use your editor.
Arguments inside these variables are not supported. If the selected executable
is unavailable, FZD falls back to micro; the installer ensures a usable fallback
without changing your shell's editor variables.

Ubuntu 24.04's fzf 0.44.1 works, including child highlighting; an upgrade is not
required. Installation checks both the version and required action bindings.
The old technical guide's blanket requirement for fzf 0.50 was incorrect.

For older distro fzf packages, prefer an updated distribution package. An
explicit, checksum-verified user-local download is also available. This tested
example is **Linux x86_64 only**, using a pinned official release:

```bash
bash install.sh --deps recommended --fzf-version 0.65.2 \
  --fzf-sha256 5eb8efc0e94aa559f84ea83eeba99bea7dce818e63f92b4b62e60663220f1c14
```

See the [official fzf release](https://github.com/junegunn/fzf/releases/tag/v0.65.2)
and its checksum file. For Linux arm64 the same version's archive digest is
`097347160595bf03a426d2abe0a17e14ca060540ddfc0ea45c0a9be62bb29a2b`;
that architecture has not been executed in this environment. Other releases
require their own published archive digest. Downloads use HTTPS and are checked
before extraction or execution. SHA256 verifies the supplied archive digest;
it is not an independent publisher signature. No “latest” release is selected
implicitly, and an existing unmanaged `~/.local/bin/fzf` requires `--adopt`.
A different fzf release can have different upstream styling defaults (for
example, its selection marker). FZD continues to inherit your configured fzf
styling; compatible existing installations are kept.

## Configuration and appearance

Edit `${XDG_CONFIG_HOME:-$HOME/.config}/fzd/fzd.conf`. `FZD_CONF_FILE` overrides
this location. The installer records custom configuration paths in its shell
block while respecting an override already present in your shell. Configuration
is trusted **Bash code**, read by FZD rather than by zsh or the shell integration.
Installation checks syntax without executing it.

```bash
FZD_GLOBAL_BACKEND=auto           # auto | locate | cache | live
FZD_GLOBAL_ROOTS=("$HOME" "/srv/media with spaces")
FZD_GLOBAL_MINLEN=2
FZD_GLOBAL_MAXDEPTH=6
FZD_GLOBAL_MAXRESULTS=5000
FZD_EXCLUDES=".git,node_modules,.cache,.venv,dist,build"
```

`auto` prefers locate, otherwise a fresh fd/find snapshot. `cache` filters that
snapshot with fzf; `live` and `locate` reload literal case-insensitive queries.
An unavailable or failed locate backend falls back to fd/find. No system index
is built automatically. Prefer Linux roots under WSL; scanning Windows mounts
can be slower. `FZD_GLOBAL_PATHS` remains supported; use `FZD_GLOBAL_ROOTS` for
paths containing whitespace. A legacy `~/.fzd/fzd.conf` is copied only when the
current configuration does not exist, leaving the original intact.

The [example configuration](../fzd.conf.example) documents exclusions, result
limits, preview depth/time/line limits, colors, and an optional locate database.
FZD retains its existing colors and inherits fzf appearance/search options.
Its controls, single-item operation mode, and output protocol take precedence
over fzf's `--expect` and multiselect settings. To request different
label colors, set `FZD_COLOR_DIR` / `FZD_COLOR_FILE` in your FZD configuration
to six hexadecimal digits, optionally prefixed with `#`. Invalid overrides are
ignored. Eza previews inherit `LS_COLORS`, replacing only explicitly requested
directory or file colors.
Third-party bat, micro, eza, or terminal themes are personal choices: configure
those tools yourself if desired. Installation never downloads themes or changes
their configuration. To use a vivid palette, configure `LS_COLORS` in your shell.

## Manual installation and automation

With prerequisites already installed:

```bash
bash install.sh --noninteractive --deps none
```

This mode never prompts for sudo input. To permit automated package installation,
use `--deps required` or `--deps recommended` and provide root or an existing
noninteractive sudo authorization. Package-manager failures stop installation.
Arch package databases are not refreshed automatically: update the system
normally rather than creating a partial upgrade.

Useful options:

```bash
bash install.sh --shell bash          # bash only; default is both
bash install.sh --shell zsh           # zsh only; respects exported ZDOTDIR
bash install.sh --prefix "$HOME/apps/fzd" --shell none --no-config
```

With `--shell none`, add this yourself to your chosen shell startup file, adapting
the prefix if needed:

```bash
_FZD_INSTALL_BIN="$HOME/apps/fzd/bin/fzd"
export PATH="$HOME/apps/fzd/bin:$PATH"
. "$HOME/apps/fzd/share/fzd/integration.sh"
```

The function uses that exact executable. The PATH line also exposes an optional
user-local fzf bootstrap. To choose another executable later, set `FZD_BIN`.
For a custom zsh startup directory, export `ZDOTDIR` before installation, e.g.
`ZDOTDIR="$HOME/my-zsh" bash install.sh --shell zsh`. A shell-local, unexported
variable cannot be discovered by a child installer. Symlinked shell startup files
retain their links; the regular target is backed up and edited.

## Update, verify, and uninstall

**Packages:** install a newer `.deb` with `sudo apt install ./NEW-PACKAGE.deb`;
remove it with `sudo apt remove fzd` (or `sudo apt purge fzd`). Arch users build
the newer recipe with `makepkg -si` and remove with `sudo pacman -R fzd`.
Your configuration, clipboard, recents and explicitly added shell integration
line remain yours. Remove that one source line when uninstalling. Dependencies
are shared; FZD never removes them itself. You can guard the source line with
`[ ! -r /usr/share/fzd/integration.sh ] || . /usr/share/fzd/integration.sh`
to avoid startup errors after removal.

**Source to package:** first uninstall the user-local copy with its lifecycle
command below; this preserves preferences. Install the package and add the
package integration line. Open a new terminal so the old `_FZD_INSTALL_BIN` is
cleared. An old `~/.local/bin/fzd`, `FZD_BIN`, or custom PATH entry can otherwise
select the old executable; check `command -v fzd`. Never use the source
uninstaller to remove `/usr` package files.

**Source installations:**

For an archive installation, extract the newer approved source archive and repeat
the same installation options. From a Git checkout, update and reinstall:

```bash
git pull --ff-only
bash install.sh --deps recommended
```

Custom configurations are not merged or overwritten. Modified program files
stop an update unless you explicitly use `--adopt`; originals are retained.
Use the same `--prefix` when updating a custom-prefix installation.
Installation prefixes must be absolute, without `..` components or `:` (PATH's
separator). These restrictions do not apply to files and directories you browse.

The installed lifecycle tool works even if the checkout has been removed:

```bash
bash "$HOME/.local/share/fzd/install.sh" --verify
bash "$HOME/.local/share/fzd/install.sh" --uninstall
```

Adapt the prefix for a custom installation. Verification checks owned-file
hashes, dependency capabilities, and Bash configuration syntax; it does not
execute configuration or launch an interactive session. Uninstall removes
unchanged FZD-owned files and its shell integration blocks. It preserves modified
files, configuration, state/cache, retained backups, and all dependencies.
The optional downloaded user-local fzf is preserved too, since other tools may use it.
Open a new terminal afterward to clear previously loaded functions.

## Troubleshooting

- **Command missing after install:** open a new terminal. If `lf` was already
  present, run `fzd_cd`. Packages require the opt-in source line above; verify
  installation with `dpkg -V fzd` or `pacman -Qkk fzd`. Confirm that your shell reads the configured rc
  file; pass exported `ZDOTDIR` when using a custom zsh setup.
- **Missing tools / sudo authentication:** install the reported packages, then
  retry. Interactive dependency installation uses normal sudo authentication;
  noninteractive mode needs existing authorization and fails with guidance.
- **Old fzf:** use the verified pinned example above or a compatible distro
  package. FZD does not silently replace a shared system executable.
- **Invalid configuration:** correct the reported Bash syntax error. Existing
  settings remain untouched. Runtime search validation also reports invalid
  backend names or numeric settings; `--verify` checks syntax only.
- **Interrupted installation / lock:** ensure no installer is running, then run
  `bash install.sh --recover` from the checkout, with your original `--prefix`
  and custom XDG/ZDOTDIR environment. Recovery refuses a live owner. Ordinary
  errors and signals roll back file changes automatically; SIGKILL requires this
  explicit step. Dependency transactions are separate and are not rolled back.
- **Backups:** originals and NUL-delimited transaction journals are retained in
  `PREFIX/share/fzd/backups/.transaction.*`. Inspect these before manually
  restoring files. Backups and empty installation directories are intentionally
  retained after uninstall. Sudden storage/power failures are not a tested
  durability guarantee.
- **Global search slow / empty:** check roots, exclusions and permissions. Use
  `FZD_GLOBAL_BACKEND=live` to bypass a stale locate database. Database maintenance
  belongs to your distribution; FZD never invokes sudo updatedb.
- **Explorer state busy:** another FZD instance may be completing a file
  operation. Retry when it finishes. Invalid state is reported without replacing
  it; close FZD and move the affected state file aside before retrying.
- **Trash failed:** confirm that `gio` or `trash-put` is installed and that the
  filesystem supports its Trash implementation. Mount permissions and removable
  or network filesystems can prevent trashing; FZD reports the backend error.

## Development and packaging

Run `bash tests/run.sh`; see [test instructions](../tests/README.md) and
[benchmarks](../benchmarks/README.md). Installer tests use disposable homes and
controlled package-manager commands.
See the [Explorer engineering report](phase-three-five.md) for architecture,
safety behavior, validation and performance comparisons.

Distribution packages stage standard files with
`bash install.sh --stage "$PWD/package-root" --prefix /usr`. They must not run
the user installer in post-install scripts or edit users' homes. See the
[packaging architecture and readiness checklist](packaging.md).

## Navigation performance

Measurements on the development WSL x86_64 host use upstream zoxide 0.9.3 and
fzf 0.44.1. Three alternating real-PTY trials per revision show normal `lf`
startup medians of 110 → 90 ms at 1,000 entries and 690 → 690 ms at 10,000 entries.
The screen clock has 10 ms granularity; this is evidence of no measurable startup
regression, not a claim that the new navigation is faster.

Warm `lf docker imm` jumps took a median 3.51 ms, including querying and learning,
versus 3.26 ms for direct upstream query/cd/add. Seven alternating groups of 150
jumps use Python's monotonic clock; one-time shell/source startup is amortized.
No tests or local containers ran during benchmarking. Explorer learning is
batched on exit and adds no zoxide process to the redraw loop.

[Retained measurements](../benchmarks/results/zoxide-navigation/README.md) include
all groups and terminal trials, baseline revision and reproduction commands.
