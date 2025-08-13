# fzd — dir nav + preview + fuzzy search

`fzd` is a tiny, fast fuzzy directory navigator for zsh.  
It uses `fzf` for the UI, `eza`/`bat` for pretty previews, and `plocate` for lightning–fast global search.

![fzd dmeo](/share/demo/fzd_demo.gif)


Why? A lot of other tools were too bloated with tons of amazing features that I would instantly forget how to use, or they used vim keybinds. I just wanted something for the casual user, something intuitive, fast, and pretty.

### Features
- Arrow **Left**: go to parent; preselect the child you came from (needs `fzf >= 0.50`).
- Arrow **Right**: enter directory.
- **Enter** on dir: exit & `cd`; on file: open in `$EDITOR` (default: micro).
- **Esc**: exit.
- typing: Just start typing to fuzzy filter current directory.
- **Ctrl+F**: global search (powered by `plocate` by default).

### Install
```bash
git clone https://github.com/seanap/fzd.git
cd fzd
./install.sh
```
Open a new shell (or source ~/.zshrc) and run:

## Daily use cheatsheet

* Launch browser: `lf`
* Jump anywhere: press **Ctrl+F**, type ≥ 2 chars → live global search (no `/mnt`).
* Enter on dir → shell cd’s there.
  Enter on file → opens in `micro` (or `$EDITOR`), then returns.
* Quick hotkey anywhere: **Ctrl+O** (our ZLE `fzd-cd-widget`).

If you want to tweak the search roots/excludes later, edit `~/.fzd/fzd.conf`.

## Config
Edit ~/.fzd/fzd.conf (installed from share/fzd.conf.example).


## REQUIREMENTS

### Core tools
- **fzf ≥ 0.50** – we rely on `start:pos(N)` (caret preselect)
- **fd** (or `fdfind` on Ubuntu) – fast filesystem listing for cache mode
- **plocate** – global search backend; we call `locate -i -e -l N QUERY`
- **eza** (optional) – colored tree preview, `--icons`
- **bat** (or `batcat`) – syntax-highlight file preview
- **micro** (or `$EDITOR`) – used when pressing Enter on files
- `tree`, `file`, `hexdump` – fallbacks/extra info

### WSL / locate tuning
- Avoid indexing Windows mounts for speed/stability:
  - `sudo cp /etc/updatedb.conf /etc/updatedb.conf.bak`
  - Ensure `/mnt` appears in `PRUNEPATHS`, and `PRUNE_BIND_MOUNTS = yes`
  - `sudo updatedb`
- Keep `FZD_GLOBAL_PATHS` to Linux paths; exclude `/mnt` via `FZD_GLOBAL_XEXCLUDES`.

### Useful env vars (in `~/.fzd/fzd.conf`)
- `FZD_GLOBAL_BACKEND=locate|cache|auto`
- `FZD_GLOBAL_PATHS="/ /etc /opt /srv /home/$USER"` (space-separated)
- `FZD_GLOBAL_XEXCLUDES="proc,sys,dev,run,proc/*,sys/*,dev/*,run/*,mnt,..."`
- `FZD_GLOBAL_MINLEN=2`, `FZD_GLOBAL_MAXRESULTS=3000`
- `FZD_PREVIEW_DEPTH=2`, `FZD_PREVIEW_TIMEOUT=2`, `FZD_PREVIEW_MAX_LINES=200`
- `FZD_DEBUG=1` – debug logs to TTY
