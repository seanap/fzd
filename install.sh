#!/usr/bin/env bash
set -euo pipefail

# fzd installer
# Goals:
# - Works on Arch (pacman), Debian/Ubuntu (apt), Fedora (dnf)
# - Installs into XDG locations and ~/.local/bin
# - Adds shell init to BOTH ~/.bashrc and ~/.zshrc (configurable)
# - Keeps 'lf' shortcut (guarded so we don't clobber a real lf executable)

# ----------------- helpers -----------------
die(){ echo "ERR: $*" >&2; exit 1; }
log(){ echo ":: $*"; }
warn(){ echo "!! $*" >&2; }

have(){ command -v "$1" >/dev/null 2>&1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FZD_SRC_SCRIPT_DEFAULT="$SCRIPT_DIR/fzd.sh"
FZD_SRC_CONF_DEFAULT="$SCRIPT_DIR/share/fzd.conf.example"

# ----------------- args -----------------
DO_UPDATEDB=1
SHELL_TARGET="both"   # both|bash|zsh

usage(){
  cat <<'USAGE'
Usage:
  ./install.sh [--no-updatedb] [--shell both|bash|zsh]

Notes:
- Installs fzd to ~/.local/bin/fzd
- Installs config to ~/.config/fzd/fzd.conf (unless already present)
- Adds init blocks to ~/.bashrc and/or ~/.zshrc
USAGE
}

while (($#)); do
  case "$1" in
    -h|--help) usage; exit 0;;
    --no-updatedb) DO_UPDATEDB=0; shift;;
    --shell)
      shift
      [[ -n "${1:-}" ]] || die "--shell requires: both|bash|zsh"
      SHELL_TARGET="$1"; shift
      ;;
    *) die "Unknown arg: $1 (try --help)";;
  esac
done

[[ -f "$FZD_SRC_SCRIPT_DEFAULT" ]] || die "Missing fzd.sh at: $FZD_SRC_SCRIPT_DEFAULT"

# ----------------- dirs (XDG) -----------------
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

BIN_DIR="$HOME/.local/bin"
CFG_DIR="$XDG_CONFIG_HOME/fzd"
STATE_DIR="$XDG_STATE_HOME/fzd"
CACHE_DIR="$XDG_CACHE_HOME/fzd"

mkdir -p "$BIN_DIR" "$CFG_DIR" "$STATE_DIR" "$CACHE_DIR"

# ----------------- package manager detection -----------------
detect_pm(){
  if have pacman; then echo pacman; return; fi
  if have apt-get; then echo apt; return; fi
  if have dnf; then echo dnf; return; fi
  die "Unsupported system: need pacman (Arch), apt (Debian/Ubuntu), or dnf (Fedora)."
}

PM="$(detect_pm)"
log "Detected package manager: $PM"

# ----------------- dependency installation -----------------
# We check for binaries (not package DB) because names differ across distros.
# We'll install a best-effort set; optional tools are allowed to fail.

install_with_pacman(){
  local -a pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0
  log "Installing with pacman: ${pkgs[*]}"
  sudo pacman -S --needed --noconfirm "${pkgs[@]}"
}

install_with_apt(){
  local -a pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0
  log "Installing with apt: ${pkgs[*]}"
  sudo apt-get update -y
  sudo apt-get install -y "${pkgs[@]}"
}

install_with_dnf(){
  local -a pkgs=("$@")
  (( ${#pkgs[@]} )) || return 0
  log "Installing with dnf: ${pkgs[*]}"
  sudo dnf install -y "${pkgs[@]}"
}

best_effort_install(){
  # attempt install, but do not fail the whole installer for optional deps
  set +e
  case "$PM" in
    pacman) install_with_pacman "$@";;
    apt)    install_with_apt "$@";;
    dnf)    install_with_dnf "$@";;
  esac
  local rc=$?
  set -e
  return $rc
}

ensure_core(){
  # Core deps: fzf, file/tree, locate backend, fd.
  # Optional: eza, bat, micro.

  case "$PM" in
    pacman)
      # Arch packages map closely to binary names
      best_effort_install fzf fd plocate tree file util-linux coreutils
      best_effort_install eza bat micro vivid curl ca-certificates tar || true
      ;;
    apt)
      # Debian/Ubuntu: fd is fd-find (binary fdfind), bat binary may be batcat
      best_effort_install fzf fd-find plocate tree file util-linux coreutils
      # optional: bat and micro exist; eza/vivid may or may not depending on distro version
      best_effort_install bat micro || true
      best_effort_install eza vivid curl ca-certificates tar || true
      ;;
    dnf)
      # Fedora: fd is often fd-find; keep best-effort.
      best_effort_install fzf fd-find plocate tree file util-linux coreutils
      best_effort_install bat micro eza vivid curl ca-certificates tar || true
      ;;
  esac
}

ensure_core

# ----------------- sanity checks / versions -----------------
have fzf || die "fzf missing after install"

ver_ge(){ printf '%s\n%s\n' "$2" "$1" | sort -V -C; }

fzf_ver(){
  fzf --version 2>/dev/null | awk '{print $1}' || true
}

install_fzf_upstream(){
  # Install a modern fzf into ~/.local/bin/fzf (user-local) without touching system packages.
  # This is needed on some distros (e.g., Ubuntu) where repo fzf is < 0.50.

  # Best effort prerequisites (usually installed already by ensure_core)
  case "$PM" in
    pacman) best_effort_install curl ca-certificates tar || true ;;
    apt)    best_effort_install curl ca-certificates tar || true ;;
    dnf)    best_effort_install curl ca-certificates tar || true ;;
  esac

  have curl || { warn "curl not available; cannot bootstrap newer fzf"; return 1; }

  local os="linux"
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64";;
    aarch64|arm64) arch="arm64";;
    *) warn "Unsupported arch for upstream fzf bootstrap: ${arch}"; return 1;;
  esac

  local api="https://api.github.com/repos/junegunn/fzf/releases/latest"
  local tag
  tag="$(curl -fsSL "$api" | awk -F'"' '/"tag_name"/ {print $4; exit}')"
  [[ -n "$tag" ]] || { warn "Could not determine latest fzf release tag from GitHub"; return 1; }

  local ver="${tag#v}"
  if ! ver_ge "$ver" "0.50.0"; then
    warn "Latest fzf release tag looks older than 0.50? tag=$tag (skipping)";
    return 1
  fi

  local asset="fzf-${ver}-${os}_${arch}.tar.gz"
  local url="https://github.com/junegunn/fzf/releases/download/${tag}/${asset}"

  local tmpd; tmpd="$(mktemp -d)"
  set +e
  curl -fL --retry 3 --retry-delay 1 -o "${tmpd}/${asset}" "$url"
  local dl_rc=$?
  set -e
  if (( dl_rc != 0 )); then
    warn "Failed to download upstream fzf (${url})"
    rm -rf "$tmpd"
    return 1
  fi

  tar -xzf "${tmpd}/${asset}" -C "$tmpd" || { warn "Failed to extract fzf tarball"; rm -rf "$tmpd"; return 1; }
  [[ -x "${tmpd}/fzf" ]] || { warn "fzf binary not found in tarball"; rm -rf "$tmpd"; return 1; }

  install -m 0755 "${tmpd}/fzf" "${BIN_DIR}/fzf"
  rm -rf "$tmpd"

  local newv; newv="$(${BIN_DIR}/fzf --version 2>/dev/null | awk '{print $1}' || true)"
  if [[ -z "$newv" ]] || ! ver_ge "$newv" "0.50.0"; then
    warn "Upstream fzf install did not produce a >=0.50 fzf (got '${newv:-?}')"
    return 1
  fi

  log "Bootstrapped upstream fzf ${newv} -> ${BIN_DIR}/fzf"
  return 0
}

# fzf version (require >= 0.50 for best UX)
fzv="$(fzf_ver)"
if [[ -n "$fzv" ]] && ! ver_ge "$fzv" "0.50.0"; then
  warn "fzf ${fzv} < 0.50; attempting to install a newer fzf to ~/.local/bin"
  if install_fzf_upstream; then
    # re-check with PATH preference (we add ~/.local/bin in rc blocks)
    fzv="$(fzf_ver)"
  else
    warn "Could not upgrade fzf automatically. fzd will still work, but caret preselect may not."
  fi
fi

if ! have fd && ! have fdfind; then
  warn "fd not found (neither 'fd' nor 'fdfind' in PATH). Global cache/live backends may be slower."
fi

if ! have plocate && ! have locate; then
  warn "No locate backend found (plocate/locate). Ctrl-F global search will fall back to fd/find."
fi

# ----------------- theme setup (bat + micro) -----------------
setup_bat_theme(){
  local batbin=""; have bat && batbin="bat"; [[ -z "$batbin" ]] && have batcat && batbin="batcat"
  [[ -n "$batbin" ]] || { warn "bat/batcat not found; skipping bat theme"; return 0; }

  local bconf; bconf="$($batbin --config-dir 2>/dev/null || true)"
  [[ -n "$bconf" ]] || { warn "Could not determine bat config dir; skipping"; return 0; }

  local themes_dir="$bconf/themes"
  mkdir -p "$themes_dir"

  local theme_file="$themes_dir/Catppuccin Mocha.tmTheme"
  if [[ ! -f "$theme_file" ]]; then
    log "Installing bat theme: Catppuccin Mocha"
    # shellcheck disable=SC2016
    curl -fsSL "https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Mocha.tmTheme" -o "$theme_file" \
      || { warn "Failed to download Catppuccin Mocha bat theme"; return 1; }
  fi

  # Ensure bat knows about the new theme
  if $batbin cache --build >/dev/null 2>&1; then
    :
  else
    warn "bat cache --build failed (non-fatal)"
  fi

  # Set default theme for bat
  mkdir -p "$bconf"
  local bcfg="$bconf/config"
  if [[ -f "$bcfg" ]]; then
    # remove existing --theme lines
    grep -vE '^\s*--theme=' "$bcfg" > "${bcfg}.tmp" || true
    mv "${bcfg}.tmp" "$bcfg"
  fi
  printf "\n--theme=\"Catppuccin Mocha\"\n" >> "$bcfg"
  log "Configured bat theme in ${bcfg}"
}

setup_micro_theme(){
  have micro || { warn "micro not found; skipping micro theme"; return 0; }

  local mconf="$HOME/.config/micro"
  local themes="$mconf/colorschemes"
  mkdir -p "$themes"

  local theme_path="$themes/catppuccin-mocha.micro"
  if [[ ! -f "$theme_path" ]]; then
    log "Installing micro theme: catppuccin-mocha"
    curl -fsSL "https://raw.githubusercontent.com/catppuccin/micro/main/themes/catppuccin-mocha.micro" -o "$theme_path" \
      || { warn "Failed to download Catppuccin micro theme"; return 1; }
  fi

  local settings="$mconf/settings.json"
  if have python3; then
    python3 - "$settings" <<'PY'
import json, os, sys
path = sys.argv[1]
try:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
except FileNotFoundError:
    data = {}
except Exception:
    data = {}
# micro expects scheme name without extension
data['colorscheme'] = 'catppuccin-mocha'
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
PY
    log "Configured micro colorscheme in ${settings}"
  else
    warn "python3 not found; can't auto-edit micro settings.json (theme file installed though)"
  fi
}

setup_bat_theme || true
setup_micro_theme || true

# ----------------- install fzd binary -----------------
install -m 0755 "$FZD_SRC_SCRIPT_DEFAULT" "${BIN_DIR}/fzd"
log "Installed fzd -> ${BIN_DIR}/fzd"

# ----------------- install config -----------------
if [[ ! -f "${CFG_DIR}/fzd.conf" ]]; then
  if [[ -f "$FZD_SRC_CONF_DEFAULT" ]]; then
    install -m 0644 "$FZD_SRC_CONF_DEFAULT" "${CFG_DIR}/fzd.conf"
    log "Installed config -> ${CFG_DIR}/fzd.conf"
  else
    cat > "${CFG_DIR}/fzd.conf" <<'EOF'
# fzd.conf (XDG)

# --- Global search tuning ---
FZD_GLOBAL_BACKEND=locate
FZD_GLOBAL_MINLEN=2
FZD_GLOBAL_MAXDEPTH=6
FZD_GLOBAL_MAXRESULTS=5000
FZD_GLOBAL_PATHS="/etc /opt /srv /home/$USER"
FZD_GLOBAL_XEXCLUDES="mnt,proc,sys,dev,run,proc/*,sys/*,dev/*,run/*,snap,lost+found,var/lib/docker"

# Excludes for dir trees and fd/find fallbacks
FZD_EXCLUDES=".git,node_modules,.cache,.venv,.tox,dist,build,__pycache__,.DS_Store"

# Preview
FZD_PREVIEW_DEPTH=2
FZD_PREVIEW_TIMEOUT=2
FZD_PREVIEW_MAX_LINES=200

# Optional label colors (hex). Leave commented to inherit your fzf/system theme.
# FZD_COLOR_DIR="#f9e2af"
# FZD_COLOR_FILE="#cdd6f4"
EOF
    log "Wrote default config -> ${CFG_DIR}/fzd.conf"
  fi
else
  log "Config already exists -> ${CFG_DIR}/fzd.conf (leaving as-is)"
fi

# ----------------- shell init block (idempotent) -----------------
START_MARK="# >>> fzd init >>>"
END_MARK="# <<< fzd init <<<"

read -r -d '' COMMON_BLOCK <<'__FZD_COMMON__' || true
# Ensure ~/.local/bin is on PATH
case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Tell fzd where the config lives (XDG)
export FZD_CONF_FILE="${FZD_CONF_FILE:-$HOME/.config/fzd/fzd.conf}"

# Editor default for fzd if user hasn't set one
export EDITOR="${EDITOR:-micro}"

# 'lf' shortcut: run fzd and cd to the chosen directory
# (guarded so we don't clobber an existing 'lf' executable)
if ! command -v lf >/dev/null 2>&1 || [[ "$(type -t lf)" != "file" ]]; then
  lf() {
    local dest rc
    dest="$(fzd "$@")"; rc=$?
    # Esc/close from fzd uses exit 130; treat as no-op
    if (( rc == 130 )); then return 0; fi
    if [[ -n "$dest" && -d "$dest" ]]; then
      builtin cd -- "$dest"
    fi
  }
fi
__FZD_COMMON__

update_rc_file(){
  local rc="$1"; shift
  local content="$1"; shift

  # Robust multi-line block update.
  # Avoid passing large multi-line strings via awk -v (can break on some systems).
  local tmpc; tmpc="$(mktemp)"
  printf '%s\n' "$content" > "$tmpc"

  if [[ -f "$rc" ]]; then
    if grep -Fq "$START_MARK" "$rc"; then
      # Replace everything between START_MARK and END_MARK (exclusive) with our content.
      # Preserve the markers exactly as-is.
      python3 - "$rc" "$tmpc" "$START_MARK" "$END_MARK" > "${rc}.tmp" <<'PY'
import re, sys
rc_path, content_path, start, end = sys.argv[1:]
rc = open(rc_path, 'r', encoding='utf-8', errors='surrogateescape').read()
block = open(content_path, 'r', encoding='utf-8', errors='surrogateescape').read().rstrip('\n')
pat = re.compile(re.escape(start) + r"\n.*?\n" + re.escape(end), re.S)
new = start + "\n" + block + "\n" + end
if not pat.search(rc):
    # markers present but pattern didn't match cleanly; fall back to append
    rc = rc.rstrip('\n') + "\n" + new + "\n"
else:
    rc = pat.sub(new, rc, count=1)
sys.stdout.write(rc)
PY
      mv "${rc}.tmp" "$rc"
    else
      printf "\n%s\n" "$START_MARK" >> "$rc"
      cat "$tmpc" >> "$rc"
      printf "%s\n" "$END_MARK" >> "$rc"
    fi
  else
    printf "%s\n" "$START_MARK" > "$rc"
    cat "$tmpc" >> "$rc"
    printf "%s\n" "$END_MARK" >> "$rc"
  fi

  rm -f "$tmpc"
}

write_shell_init_files(){
  local xdg_conf="${XDG_CONFIG_HOME:-$HOME/.config}"
  local init_dir="$xdg_conf/fzd"
  mkdir -p "$init_dir"

  # Bash init
  cat > "$init_dir/init.bash" <<'EOF'
# fzd shell init (bash)

# Ensure ~/.local/bin is on PATH
case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Tell fzd where the config lives (XDG)
export FZD_CONF_FILE="${FZD_CONF_FILE:-$HOME/.config/fzd/fzd.conf}"

# Editor default for fzd if user hasn't set one
export EDITOR="${EDITOR:-micro}"

# 'lf' shortcut: run fzd and cd to the chosen directory
# (guarded so we don't clobber an existing 'lf' executable)
if ! command -v lf >/dev/null 2>&1 || [[ "$(type -t lf)" != "file" ]]; then
  lf() {
    local dest rc
    dest="$(fzd "$@")"; rc=$?
    (( rc == 130 )) && return 0
    [[ -n "$dest" && -d "$dest" ]] && builtin cd -- "$dest"
  }
fi
EOF

  # Zsh init (still runs bash-script fzd; this is just shell wiring)
  cat > "$init_dir/init.zsh" <<'EOF'
# fzd shell init (zsh)

# Ensure ~/.local/bin is on PATH
case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# Tell fzd where the config lives (XDG)
export FZD_CONF_FILE="${FZD_CONF_FILE:-$HOME/.config/fzd/fzd.conf}"

# Editor default for fzd if user hasn't set one
export EDITOR="${EDITOR:-micro}"

# 'lf' shortcut: run fzd and cd to the chosen directory
# (guarded so we don't clobber an existing 'lf' executable)
if ! command -v lf >/dev/null 2>&1 || [[ "$(type -t lf)" != "file" ]]; then
  lf() {
    local dest rc
    dest="$(fzd "$@")"; rc=$?
    (( rc == 130 )) && return 0
    [[ -n "$dest" && -d "$dest" ]] && builtin cd -- "$dest"
  }
fi
EOF

  log "Wrote shell init files -> $init_dir/init.bash, $init_dir/init.zsh"
}

install_bashrc(){
  local rc="$HOME/.bashrc"
  local block
  block=$(cat <<'__BASH_BLOCK__'
# fzd: source shell init (bash)
if [[ -f "$HOME/.config/fzd/init.bash" ]]; then
  . "$HOME/.config/fzd/init.bash"
fi
__BASH_BLOCK__
)
  update_rc_file "$rc" "$block"
  log "Updated ${rc}"
}

install_zshrc(){
  local rc="$HOME/.zshrc"
  local block
  block=$(cat <<'__ZSH_BLOCK__'
# fzd: source shell init (zsh)
if [[ -f "$HOME/.config/fzd/init.zsh" ]]; then
  source "$HOME/.config/fzd/init.zsh"
fi
__ZSH_BLOCK__
)
  update_rc_file "$rc" "$block"
  log "Updated ${rc}"
}

write_shell_init_files

case "$SHELL_TARGET" in
  both) install_bashrc; install_zshrc;;
  bash) install_bashrc;;
  zsh)  install_zshrc;;
  *) die "Invalid --shell value: $SHELL_TARGET";;
esac

# ----------------- updatedb (optional) -----------------
if (( DO_UPDATEDB == 1 )); then
  if have updatedb; then
    log "Updating locate DB (updatedb) — sudo may prompt"
    sudo updatedb || true
  else
    log "updatedb not found; skipping locate DB update"
  fi
else
  log "Skipping updatedb (--no-updatedb)"
fi

cat <<'OK'
✅ Done.

Binary:   ~/.local/bin/fzd
Config:   ~/.config/fzd/fzd.conf
State:    ~/.local/state/fzd    (created on demand by fzd)
Cache:    ~/.cache/fzd          (created on demand by fzd)

Open a new shell (or source your rc file) and use:
  lf         # launches fzd and cd's to your selection
  fzd        # launches raw fzd (prints dir on Enter)
OK
