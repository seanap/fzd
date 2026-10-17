# FZD

<p align="center">
  <img src="https://i.imgur.com/BIzuhmK.png" alt="FZD — a terminal file explorer and fuzzy finder">
</p>

<p align="center"><strong>Intuitive Linux File Explorer TUI</strong></p>

Browse directories with arrow keys from the terminal. Autocomplete common locations. Instantaneous Global Search.

FZD is a small, keyboard-driven file explorer for Linux, built with Bash,
[fzf](https://github.com/junegunn/fzf), and [zoxide](https://github.com/ajeetdsouza/zoxide).
Browse with previews, search across your filesystem, and return to your shell
right where you need to be.

<p align="center">
  <img src="share/demo/fzd_demo.gif" alt="Animated demonstration of FZD terminal navigation">
  <br>
</p>

## Usage

```bash
lf                 # Opens Current dir, preview full tree
lf immich          # Jump to the best matching place you've already visited
lff immich         # Global search shortcut
```

You don't need the whole name: `lf imm` works. Add context with
`lf docker immich`. Full matching and ranking of common loactions; if it hasn't learned
a match yet, FZD opens discovery with your query ready to go.

Already know the path? `lf /srv/docker/immich` takes you there directly.
Use `lff` on its own to start a fresh global search.

## Why FZD exists

After years of using Linux,
I still found myself asking: where did that project put its files?

I built FZD to find my bearings without memorizing paths or repeatedly typing
`cd` and `ls`. Browse the directory tree. Quickly edit a config with `Micro`. Search your whole system, instantly, powered by `plocate`. All using pure Bash.

## Install

Supports Ubuntu/Debian, Arch, or Fedora, and runs on Bash or zsh:

```bash
git clone https://github.com/seanap/fzd.git
cd fzd
bash install.sh --deps recommended --inline-suggestions
```

Installs FZD under `~/.local`,
Adds gray inline autosuggestions. Press **Right** to accept. 
Leave off `--inline-suggestions` to keep existing autocomplete engine setup unchanged.
Use `--shell bash` / `--shell zsh` to configure one shell.

Open a **new terminal**, then run `lf`. 

<details>
<summary>Packages, manual installation, updates and removal</summary>

Debian and Arch build instructions, checksum verification, alternative prefixes,
automation, and uninstall commands live in the [technical guide](docs/TECHNICAL.md#install)
and [packaging guide](docs/packaging.md). Download release packages and checksums
from [GitHub Releases](https://github.com/seanap/fzd/releases/latest).
AUR publication is pending.

</details>

## Make yourself at home

| Key | Action |
| --- | --- |
| Left / Right | Parent / highlighted directory |
| Enter | Return to the shell there, or edit a file |
| Type | Filter the current directory |
| Ctrl+F | Global discovery |
| Alt+Left / Alt+Right | Back / Forward |
| Ctrl+C / X / V | Copy / Cut / Paste |
| F8 | Move to Trash after confirmation |
| F1 | All controls and contextual help |
| Esc | Cancel |

Previews, rename, new folders, recent directories, and safe file operations are
built in.

## Finish the thought

The installer’s explicit `--inline-suggestions` option installs and configures
ble.sh for Bash and zsh-autosuggestions for zsh. Existing engines are reused.
[Setup, updates and removal](docs/TECHNICAL.md#tab-completion-and-inline-suggestions).

## Go deeper

[Configuration, compatibility and troubleshooting](docs/TECHNICAL.md) ·
[Tests](tests/README.md) · [Benchmarks](benchmarks/README.md) ·
[Report an issue](https://github.com/seanap/fzd/issues)

FZD is open source under the [MIT license](LICENSE.txt).
