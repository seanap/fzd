# FZD

<p align="center">
  <img src="https://i.imgur.com/BIzuhmK.png" alt="FZD — a terminal file explorer and fuzzy finder">
</p>

<p align="center"><strong>Intuitive Linux File Explorer TUI</strong></p>

Browse directories with arrow keys from the terminal. Autocomplete common
locations. Search your filesystem with plocate.

FZD is a small, keyboard-driven file explorer for Linux, built with Bash,
[fzf](https://github.com/junegunn/fzf), [zoxide](https://github.com/ajeetdsouza/zoxide),
and [plocate](https://plocate.sesse.net/).
Browse with previews, search across your filesystem, and return to your shell
right where you need to be.

**New in [FZD 2.1](https://github.com/seanap/fzd/releases/tag/v2.1.0):**
Simple and Enhanced installation, Omarchy theme and editor integration,
image and Markdown previews, clipboard actions, and Lazygit support.
See the [release notes](docs/releases/v2.1.0.md) for upgrade guidance.

<p align="center">
  <img src="share/demo/fzd_demo.gif" alt="Animated demonstration of FZD terminal navigation">
  <br>
</p>

## Explore. Remember. Find.

<img width="1440" height="535" alt="FZD's three commands: explore, remember and find" src="https://github.com/user-attachments/assets/a311fe78-90fa-44f2-966c-f1f8dc2ced20" />

```bash
lf                 # Explore from here
lf immich          # Jump to the best matching place you've visited
lff immich         # Discover it through global search
```

**`lf` explores, `lf name` remembers, and `lff name` finds.**

You don't need the whole name: `lf imm` works. Add context with
`lf docker immich`. Zoxide handles the matching and ranking; if it hasn't learned
a match yet, FZD opens discovery with your query ready to go.

Already know the path? `lf /srv/docker/immich` takes you there directly.
Use `lff` on its own to start a fresh global search.

## Why FZD exists

After years of using Linux, I still found myself asking: where did that project
put its files?

I built FZD to find my bearings without memorizing paths or repeatedly typing
`cd` and `ls`. Browse the directory tree, edit a config, and find files across the
system. Once you've found a useful place, zoxide helps you get there again.

<img width="1440" height="611" alt="FZD file and directory previews" src="https://github.com/user-attachments/assets/a3798f0a-5ddb-487a-b03b-fdc0654f1bf0" />

## Install

Run as your normal user on Omarchy, ordinary Arch, Ubuntu/Debian, Fedora, or WSL:

```bash
git clone https://github.com/seanap/fzd.git
cd fzd
bash install.sh --enhanced
```

<img width="1440" height="620" alt="FZD Simple and Enhanced installation options" src="https://github.com/user-attachments/assets/11e2182f-773e-4d48-b794-f2dcc043a6f3" />

`--enhanced` adds optional image/Markdown preview tools, clipboard support,
inline autosuggestions, and Nerd Font conveniences. Plain `bash install.sh`
provides the full standard experience with plocate, recommended preview tools,
shell integration, and native **Tab** completion. Both run the same application;
installed capabilities work automatically in either mode.
Use `--shell bash` / `--shell zsh` to configure one shell.

Open a **new terminal**, then run `lf`. Both modes reuse existing tools and
preserve your shell customizations. FZD lives under `~/.local`, with its shell
setup in `~/.config/fzd/shell.bash` or `shell.zsh`. Missing system packages need
root or cached sudo authorization (`sudo -v`). Enhanced provides terminal font
selection guidance; on WSL, fonts must be installed and selected on Windows.

Installing a missing plocate package can start indexing or enable its schedule.
FZD stops before that transaction unless you explicitly authorize package setup;
see the [installation guidance](docs/TECHNICAL.md#plocate-readiness-and-package-indexing).

<details>
<summary>Packages, manual installation, updates and removal</summary>

Debian and Arch build instructions, checksum verification, alternative prefixes,
automation, and uninstall commands live in the [technical guide](docs/TECHNICAL.md#install)
and [packaging guide](docs/packaging.md). Download release packages and checksums
from [GitHub Releases](https://github.com/seanap/fzd/releases/latest).
AUR publication is pending.

</details>

## At home on Omarchy

FZD follows the current Omarchy palette each time it starts and opens files with
Omarchy's selected editor, including subsequent editor changes. It reuses existing
zoxide, fzf, fonts, aliases, and shell setup. An optional Enhanced launcher opens
an interactive terminal that stays in the directory you choose.

Images render with Chafa; Markdown renders with Glow when installed. **Alt+Y**
copies the selected absolute path to your system clipboard. **Alt+G** opens the
selected Git working tree in Lazygit and returns to your browsing session.
Lazygit is detected when present and is never installed automatically.
See [Omarchy integration](docs/TECHNICAL.md#omarchy-integration) for setup details.

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
built in. Your editor, terminal styling, and existing shell commands stay yours.
If another tool already owns `lf` or `lff`, use `fzd_cd` or `fzd_find` instead.

## Finish the thought

Type `lf imm` and press Enter to let zoxide resolve the partial name, or use
**Tab** to complete it in Bash or zsh. Enhanced also offers inline suggestions:
press **Right** to accept the suggested suffix. Existing engines are reused.
[Setup, updates and removal](docs/TECHNICAL.md#tab-completion-and-inline-suggestions).

## Go deeper

[Configuration, compatibility and troubleshooting](docs/TECHNICAL.md) ·
[Tests](tests/README.md) · [Benchmarks](benchmarks/README.md) ·
[Report an issue](https://github.com/seanap/fzd/issues)

FZD is open source under the [MIT license](LICENSE.txt).
