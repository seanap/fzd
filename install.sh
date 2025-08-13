#!/usr/bin/env bash
set -euo pipefail

# -------- config --------
FZD_HOME="${FZD_HOME:-$HOME/.fzd}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSHRC="$HOME/.zshrc"
MARK_BEGIN="# >>> fzd init >>>"
MARK_END="# <<< fzd init <<<"
APT_PKGS=(fzf fd-find bat eza tree file micro plocate)

say() { printf "\033[1;36m[fzd]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[fzd]\033[0m %s\n" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1; }

# -------- pkg install (Ubuntu/WSL-first) --------
install_apt() {
  sudo apt-get update -y
  sudo apt-get install -y "${APT_PKGS[@]}"
  # friendly symlinks on Ubuntu (fd -> fdfind, bat -> batcat)
  if ! need_cmd fd && need_cmd fdfind; then
    sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
  fi
  if ! need_cmd bat && need_cmd batcat; then
    sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat
  fi
}

ensure_deps() {
  if need_cmd apt-get; then
    install_apt
  else
    say "Non-Ubuntu system detected; please install these manually: ${APT_PKGS[*]}"
  fi

  # ensure fzf >= 0.50 for start:pos
  if need_cmd fzf; then
    ver="$(fzf --version 2>/dev/null | awk '{print $1}')"
    if printf '%s\n%s\n' "0.50.0" "$ver" | sort -V | head -n1 | grep -qx "0.50.0"; then
      say "fzf >= 0.50 OK ($ver)"
    else
      say "fzf too old ($ver). Installing user-local fzf…"
      git clone --depth=1 https://github.com/junegunn/fzf.git "$HOME/.fzf" >/dev/null 2>&1 || true
      "$HOME/.fzf/install" --bin --no-update-rc
      export PATH="$HOME/.fzf/bin:$PATH"
    fi
  fi
}

# -------- plocate tuning --------
tune_locate() {
  if ! need_cmd updatedb; then
    say "updatedb not found; skipping plocate tuning"
    return 0
  fi
  local cfg="/etc/updatedb.conf"
  if [[ -r "$cfg" && -w "$cfg" ]]; then
    sudo cp -n "$cfg" "${cfg}.bak"
    # Ensure /mnt is pruned on WSL to avoid crawling Windows files
    if ! grep -qE '(^| )/mnt( |$)' "$cfg"; then
      say "Adding /mnt to PRUNEPATHS in $cfg"
      sudo sed -i 's|^PRUNEPATHS="|PRUNEPATHS="/mnt |' "$cfg"
    fi
    # Safer defaults
    if grep -q '^PRUNE_BIND_MOUNTS=' "$cfg"; then
      sudo sed -i 's/^PRUNE_BIND_MOUNTS=.*/PRUNE_BIND_MOUNTS = yes/' "$cfg"
    else
      echo 'PRUNE_BIND_MOUNTS = yes' | sudo tee -a "$cfg" >/dev/null
    fi
    say "Refreshing locate DB (sudo updatedb)…"
    sudo updatedb || true
  fi
}

# -------- install files --------
install_files() {
  mkdir -p "$FZD_HOME"
  install -m 0755 "$REPO_ROOT/bin/fzd.sh" "$FZD_HOME/fzd.sh"
  install -m 0644 "$REPO_ROOT/share/fzd.conf.example" "$FZD_HOME/fzd.conf"
  install -m 0644 "$REPO_ROOT/shell/lf.zsh" "$FZD_HOME/lf.zsh"
  install -m 0644 "$REPO_ROOT/shell/fzd.zsh" "$FZD_HOME/fzd.zsh"
}

# -------- zsh integration (idempotent) --------
patch_zshrc() {
  grep -q "$MARK_BEGIN" "$ZSHRC" 2>/dev/null && { say "~/.zshrc already patched"; return; }

  cat >>"$ZSHRC" <<'EOF'

# >>> fzd init >>>
export FZD_HOME="$HOME/.fzd"
[[ -f "$FZD_HOME/fzd.conf" ]] && source "$FZD_HOME/fzd.conf"
[[ -f "$FZD_HOME/lf.zsh"    ]] && source "$FZD_HOME/lf.zsh"
# Optional: hotkey widget (Ctrl+O by default)
[[ -f "$FZD_HOME/fzd.zsh"   ]] && source "$FZD_HOME/fzd.zsh"
# <<< fzd init <<<
EOF
  say "Patched ~/.zshrc (open a new shell or:  source ~/.zshrc )"
}

main() {
  [[ -f "$REPO_ROOT/bin/fzd.sh" ]] || die "Missing bin/fzd.sh"
  ensure_deps
  tune_locate
  install_files
  patch_zshrc
  say "Installed to $FZD_HOME"
  say "Quick test:  printf '..\nA\nB\n' | fzf --bind 'start:pos(2)' --select-1 --exit-0 >/dev/null && echo OK"
  say "Run: lf   (fuzzy cd)   |   Ctrl+F inside fzd for global search"
}
main "$@"
