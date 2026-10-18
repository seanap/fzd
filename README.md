# FZD

<p align="center">
  <img src="https://i.imgur.com/InGa0TZ.png" alt="FZD — a terminal file explorer and fuzzy finder">
</p>

<p align="center"><strong>Find your way.</strong></p>

Discover unfamiliar directories. Remember the places that matter. Get back to work.

FZD is a small, keyboard-driven file explorer for Linux, built with Bash,
[fzf](https://github.com/junegunn/fzf), and [zoxide](https://github.com/ajeetdsouza/zoxide).
Browse with previews, search across your filesystem, and return to your shell
right where you need to be.

<p align="center">
  <img src="share/demo/fzd_demo.gif" alt="Animated demonstration of FZD terminal navigation">
  <br>
  <sub>The original FZD demo; the navigation commands below extend this experience.</sub>
</p>

## Explore. Remember. Find.

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

After years of using Linux, running Docker containers, and self-hosting services,
I still found myself asking: where did that project put its files?
AI-generated projects added even more unfamiliar directory structures to explore.

I built FZD to find my bearings without memorizing paths or repeatedly typing
`cd` and `ls`. Look around, understand what's there, and get back to the actual
work. Once you've found a useful place, zoxide helps you get there again.

## Install

Run as your normal user on Ubuntu/Debian, Arch, or Fedora:

```bash
git clone https://github.com/seanap/fzd.git
cd fzd
bash install.sh --enhanced
```

`--enhanced` adds optional inline autosuggestions and Nerd Font conveniences.
Plain `bash install.sh` provides the standard **Simple** experience: required
and recommended tools, previews, shell integration, and native **Tab** completion.

Open a **new terminal**, then run `lf`. Both modes reuse existing tools and
preserve your shell customizations. FZD lives under `~/.local`, with its shell
setup in `~/.config/fzd/shell.bash` or `shell.zsh`. Missing system packages need
root or cached sudo authorization (`sudo -v`). Enhanced provides terminal font
selection guidance; on WSL, fonts must be installed and selected on Windows.

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
