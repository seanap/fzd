# FZD

A small Bash file navigator built around fzf. Browse with the arrow keys, fuzzy
filter as you type, preview files and directories, and press **Ctrl+F** to search
globally. Selecting a directory returns to your shell in that directory.

![FZD demo](share/demo/fzd_demo.gif)

## Install

Use Linux with Bash 4.4+, GNU utilities, and Git. Bash and zsh are supported as
interactive shells. Ubuntu/Debian, Fedora, and Arch dependency managers are
supported; Ubuntu 24.04 under WSL2 is the fully tested environment. Other Linux
systems can use the manual installation below.

Run as your normal user:

```bash
git clone https://github.com/seanap/fzd.git && cd fzd && bash install.sh --deps recommended
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

## Prerequisites and dependency choices

| Level | Tools |
| --- | --- |
| Required | Bash 4.4+, fzf >= 0.44.0 with the tested bindings, GNU coreutils, findutils, standard Linux text utilities, and an editor |
| Recommended | fd/fdfind, bat/batcat, file, tree |
| Optional | plocate/locate with an existing index, eza and a compatible icon font, hexdump, tput |
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
The old README's blanket requirement for fzf 0.50 was incorrect.

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

The [example configuration](fzd.conf.example) documents exclusions, result
limits, preview depth/time/line limits, colors, and an optional locate database.
FZD retains its existing colors and inherits fzf options. To request different
label colors, set `FZD_COLOR_DIR` / `FZD_COLOR_FILE` in your FZD configuration.
Third-party bat, micro, eza, or terminal themes are personal choices: configure
those tools yourself if desired. Installation never downloads themes or changes
their configuration. With eza/vivid already installed, the existing preview
renderer still applies its established palette locally to the preview process.

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

From your original checkout, update and repeat the same installation options:

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
  present, run `fzd_cd`. Confirm that your chosen shell reads the configured rc
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

## Development and packaging

Run `bash tests/run.sh`; see [test instructions](tests/README.md) and
[benchmarks](benchmarks/README.md). Installer tests use disposable homes and
controlled package-manager commands.

Distribution packages stage standard files with
`bash install.sh --stage "$PWD/package-root" --prefix /usr`. They must not run
the user installer in post-install scripts or edit users' homes. See the
[packaging architecture and readiness checklist](docs/packaging.md).
