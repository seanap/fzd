#!/usr/bin/env bash
set -euo pipefail

die(){ echo "ERR: $*" >&2; exit 1; }

# --- args ---
FZD_SRC_SCRIPT="${1:-}"; [[ -n "${FZD_SRC_SCRIPT}" ]] || die "First arg must be path to fzd.sh"
[[ -f "${FZD_SRC_SCRIPT}" ]] || die "fzd.sh not found at: ${FZD_SRC_SCRIPT}"
FZD_SRC_CONF="${2:-}"

# --- Arch/Omarchy preflight ---
command -v pacman >/dev/null 2>&1 || die "This installer is for Arch/Omarchy (pacman not found)."

# --- dirs ---
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

BIN_DIR="$HOME/.local/bin"
CFG_DIR="$XDG_CONFIG_HOME/fzd"
STATE_DIR="$XDG_STATE_HOME/fzd"
CACHE_DIR="$XDG_CACHE_HOME/fzd"

mkdir -p "$BIN_DIR" "$CFG_DIR" "$STATE_DIR" "$CACHE_DIR"

# --- packages ---
need_pkgs=(fzf fd plocate eza bat micro tree file util-linux)
missing=()
for p in "${need_pkgs[@]}"; do pacman -Qi "$p" >/dev/null 2>&1 || missing+=("$p"); done
if ((${#missing[@]})); then
  echo ":: Installing with pacman: ${missing[*]}"
  sudo pacman -S --needed --noconfirm "${missing[@]}" || true
fi

# AUR helper fallback only if still missing
helper=""
for h in yay paru; do command -v "$h" >/dev/null 2>&1 && helper="$h" && break; done
left=()
for p in "${need_pkgs[@]}"; do pacman -Qi "$p" >/dev/null 2>&1 || left+=("$p"); done
if ((${#left[@]})) && [[ -n "$helper" ]]; then
  echo ":: Installing with $helper: ${left[*]}"
  "$helper" -S --needed --noconfirm "${left[@]}"
fi

# Final sanity: fzf must exist (prefer >=0.50 for caret support)
command -v fzf >/dev/null 2>&1 || die "fzf missing after install"
fzv="$(fzf --version | awk '{print $1}')"
ver_ge(){ printf '%s\n%s\n' "$2" "$1" | sort -V -C; }
if ! ver_ge "$fzv" "0.50.0"; then
  echo "!! Warning: fzf ${fzv} < 0.50 (caret preselect may not work)."
fi

# --- install fzd binary ---
install -m 0755 "$FZD_SRC_SCRIPT" "${BIN_DIR}/fzd"
echo ":: Installed fzd -> ${BIN_DIR}/fzd"

# --- install config (optional) ---
if [[ -n "${FZD_SRC_CONF}" ]]; then
  [[ -f "${FZD_SRC_CONF}" ]] || die "Config not found: ${FZD_SRC_CONF}"
  install -m 0644 "$FZD_SRC_CONF" "${CFG_DIR}/fzd.conf"
  echo ":: Installed config -> ${CFG_DIR}/fzd.conf"
else
  if [[ ! -f "${CFG_DIR}/fzd.conf" ]]; then
    cat > "${CFG_DIR}/fzd.conf" <<'EOF'
# fzd.conf (Omarchy/XDG)

# --- Global search tuning ---
FZD_GLOBAL_BACKEND=locate
FZD_GLOBAL_MINLEN=2
FZD_GLOBAL_MAXDEPTH=6
FZD_GLOBAL_MAXRESULTS=5000
FZD_GLOBAL_PATHS="/etc /opt /srv /home/$USER"
FZD_GLOBAL_XEXCLUDES="mnt,proc,sys,dev,run,proc/*,sys/*,dev/*,run/*,snap,lost+found,var/lib/docker"

# plocate DB(s) (default path on Arch)
FZD_LOCATE_DBS="/var/lib/plocate/plocate.db"

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
    echo ":: Wrote default config stub -> ${CFG_DIR}/fzd.conf"
  fi
fi

# --- ~/.bashrc block (idempotent, includes lf() function) ---
BASHRC="$HOME/.bashrc"
START_MARK="# >>> fzd init >>>"
END_MARK="# <<< fzd init <<<"

BLOCK_CONTENT=$(cat <<'____FZD_BLOCK____'
# >>> fzd init >>>
# Ensure ~/.local/bin is on PATH
case ":$PATH:" in
  *:"$HOME/.local/bin":*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

# fzf: bash key-bindings + completion (if available)
[[ -f /usr/share/fzf/key-bindings.bash ]] && . /usr/share/fzf/key-bindings.bash
[[ -f /usr/share/fzf/completion.bash   ]] && . /usr/share/fzf/completion.bash

# Tell fzd where the config lives (XDG)
export FZD_CONF_FILE="${FZD_CONF_FILE:-$HOME/.config/fzd/fzd.conf}"

# Respect system theme: do NOT override FZF_DEFAULT_OPTS here.

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
    # If fzd printed a directory, cd into it
    if [[ -n "$dest" && -d "$dest" ]]; then
      builtin cd -- "$dest"
    fi
  }
fi
# <<< fzd init <<<
____FZD_BLOCK____
)

if [[ -f "$BASHRC" ]]; then
  if grep -Fq "$START_MARK" "$BASHRC"; then
    awk -v s="$START_MARK" -v e="$END_MARK" '
      $0==s {print; inb=1; print ENVIRON["BLOCK_CONTENT"]; next}
      $0==e {inb=0; next}
      !inb {print}
    ' BLOCK_CONTENT="$BLOCK_CONTENT" "$BASHRC" > "$BASHRC.tmp" && mv "$BASHRC.tmp" "$BASHRC"
  else
    printf "\n%s\n%s\n" "$START_MARK" "$BLOCK_CONTENT" >> "$BASHRC"
  fi
else
  printf "%s\n%s\n" "$START_MARK" "$BLOCK_CONTENT" > "$BASHRC"
fi

echo ":: Updated ${BASHRC} (fzf bindings, PATH, FZD_CONF_FILE, EDITOR, lf function)"

# --- plocate DB (optional but useful) ---
if command -v plocate >/dev/null 2>&1; then
  echo ":: Updating plocate DB (sudo may prompt)"
  sudo updatedb || true
fi

cat <<'OK'
✅ Done.

Binary:   ~/.local/bin/fzd
Config:   ~/.config/fzd/fzd.conf
State:    ~/.local/state/fzd    (created on demand by fzd)
Cache:    ~/.cache/fzd          (created on demand by fzd)

Open a new shell (or: source ~/.bashrc) and use:
  lf         # launches fzd and cd's to your selection
  fzd        # launches raw fzd (prints dir on Enter)
OK
