
---

# FZD – Requirements & Conventions

## OS / shell

* Ubuntu (incl. WSL2).
* Default shell: **zsh**.

## Required CLI tools

* `fzf` (≥ 0.65)
* `fd` (package name **fd-find** on Ubuntu; we shim `fd` → `fdfind`)
* `plocate` (or `locate`) — with DB configured to **exclude `/mnt`**
* `eza` (tree view + icons)
* `bat` (Ubuntu provides `batcat`; we shim `bat` → `batcat`)
* `tree`, `file`, `micro`, `git`, `curl`

## zsh plugins (lightweight, no frameworks)

* **fzf** completion/keybindings from apt examples
* **fzf-tab** (Aloxaf)
* **zsh-autosuggestions**
* **fast-syntax-highlighting** (load last)

## FZD files

fzd/
├─ bin/
│  └─ fzd.sh
├─ share/
│  └─ fzd.conf.example       # editable defaults
├─ shell/
│  ├─ lf.zsh                 # `lf` function that runs fzd then cd's
│  └─ fzd.zsh                # hotkey widget
├─ install.sh                # one-shot installer (Ubuntu/WSL-first)
├─ uninstall.sh              # clean removal
├─ README.md
├─ docs/
│  └─ REQUIREMENTS.md
├─ .editorconfig
├─ .gitignore
├─ LICENSE                   # MIT
└─ .github/workflows/
   └─ shellcheck.yml         # CI lint


## Defaults we set

* Global search backend: **locate** (fast), falling back to cache.
* Global paths: `/etc /opt /srv /home/$USER` (intentionally **not** scanning `/mnt`).
* Excludes: project junk + heavy system dirs + `mnt/*`.
* Preview: `eza --tree -L 2 --icons` or `tree -C -L 2`; file preview with `bat`.
