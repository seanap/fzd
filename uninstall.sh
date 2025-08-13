#!/usr/bin/env bash
set -euo pipefail
FZD_HOME="${FZD_HOME:-$HOME/.fzd}"
ZSHRC="$HOME/.zshrc"
MARK_BEGIN="# >>> fzd init >>>"
MARK_END="# <<< fzd init <<<"

echo "[fzd] Removing $FZD_HOME …"
rm -rf "$FZD_HOME"

if [[ -f "$ZSHRC" ]]; then
  echo "[fzd] Cleaning ~/.zshrc …"
  awk -v s="$MARK_BEGIN" -v e="$MARK_END" '
    $0==s {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$ZSHRC" > "$ZSHRC.tmp" && mv "$ZSHRC.tmp" "$ZSHRC"
fi
echo "[fzd] Done."
