<div align="center" markdown="1">
   <br>
   
  # fzd :{dir nav + preview + fuzzy search}<br>
A tiny, shell-native, fuzzy searching, directory navigator with colored previews for `zsh`. 
</div>
 


<div align="center">
  <img src="https://i.imgur.com/InGa0TZ.png" alt="fzd - a cli dir navigator & fuzzy finder">
  <a href="https://github.com/seanap/fzd/graphs/contributors"><img src="https://img.shields.io/github/contributors/seanap/fzd" alt="Contributors"></a>
  <a href="https://github.com/seanap/fzd/stargazers"><img src="https://img.shields.io/github/stars/seanap/fzd?style=flat" alt="Stars"></a>
</div>

---

![fzd dmeo](/share/demo/fzd_demo.gif)


### Why? 
A lot of other great tools can do what this does but I found they were too bloated with tons of amazing features that I would instantly forget how to use, or they used vim keybinds. I just wanted something simple, intuitive, fast, and pretty.

`fzd` (Fuzzy-Directory) is built on `fzf`. Browse your directory tree with your **arrow keys**, colorized previews with `eza`/`bat`, hit Enter to edit files, and `Ctrl-F` for instant global search via `plocate`, hit Enter on a dir and drop right back into your shell at the dir you selected. 

### Install
```bash
git clone https://github.com/seanap/fzd.git
cd fzd
chmod +x install.sh
./install.sh
```
Open a new shell (or `source ~/.zshrc` / `source ~/.bashrc`)

### Controls
- Arrow **Left**: go to parent; preselect the child you came from (needs `fzf >= 0.50`).
- Arrow **Right**: drills down into directory.
- **Enter** on dir: exit & `cd`; on file: open in `$EDITOR` (default: micro).
- **Esc**: exit.
- typing: Just start typing to fuzzy filter current directory.
- **Ctrl+F**: global search.

## Daily use cheatsheet

* Launch browser: `lf`
* Use `left` or `right` arrows to navigate directory tree
* Just start typing to fuzzy-filter current directory
* Global Search from anywhere: `Ctrl+F`, type ≥ 2 chars
* `Enter` on highlighted dir returns to shell and cd’s into that directory.
* `Enter` on highlighted file opens in `micro` (or `$EDITOR`), exiting the editor returns to fzd.
* `esc` exits fzd

## Config
If you want to tweak the search roots/excludes later, edit `~/.config/fzd/fzd.conf`.

Installed from `share/fzd.conf.example`


## REQUIREMENTS

### Core tools (installed via install script)
- **fzf ≥ 0.50** – we rely on `start:pos(N)` (caret preselect)
  - Note: Ubuntu/Debian repos may ship an older `fzf`. The installer will bootstrap a newer `fzf` into `~/.local/bin` if needed.
- **fd** (or `fdfind` on Ubuntu) – fast filesystem listing for cache mode
- **plocate** – global search backend; we call `locate -i -e -l N QUERY`
- **eza** (optional) – colored tree preview, `--icons`
  - Preview colors come from `LS_COLORS` (Catppuccin recommended). fzd will also try to align dir/file colors with `FZD_COLOR_DIR`/`FZD_COLOR_FILE` in previews.
- **bat** (or `batcat`) – syntax-highlight file preview (installer will add Catppuccin Mocha theme)
- **micro** (or `$EDITOR`) – used when pressing Enter on files (installer will add Catppuccin Mocha theme)
- `tree`, `file`, `hexdump` – fallbacks/extra info
- Nerd Font for those icons

### WSL / locate tuning
- Avoid indexing Windows mounts for speed/stability:
  - `sudo cp /etc/updatedb.conf /etc/updatedb.conf.bak`
  - Ensure `/mnt` appears in `PRUNEPATHS`, and `PRUNE_BIND_MOUNTS = yes`
  - `sudo updatedb`
- Keep `FZD_GLOBAL_PATHS` to Linux paths; exclude `/mnt` via `FZD_GLOBAL_XEXCLUDES`.

### Useful env vars (in `~/.fzd/fzd.conf`)
- `FZD_GLOBAL_BACKEND=locate`
- `FZD_GLOBAL_PATHS="/etc /opt /srv /home/$USER"`
- `FZD_GLOBAL_XEXCLUDES="proc,sys,dev,run,proc/*,sys/*,dev/*,run/*"`
- `FZD_GLOBAL_MINLEN=2`, `FZD_GLOBAL_MAXRESULTS=3000`
- `FZD_PREVIEW_DEPTH=2`, `FZD_PREVIEW_TIMEOUT=2`, `FZD_PREVIEW_MAX_LINES=200`
- `FZD_DEBUG=1` – debug logs to TTY
