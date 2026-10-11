#!/usr/bin/env bash
# Run the checkout without installing or reading the real user's FZD config.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work="$repo/.test-work/manual"
mkdir -p "$work/config/fzd"
if [[ ! -e "$work/config/fzd/fzd.conf" ]]; then
  cp -- "$repo/fzd.conf.example" "$work/config/fzd/fzd.conf"
fi
export XDG_CONFIG_HOME="$work/config" XDG_STATE_HOME="$work/state"
export XDG_CACHE_HOME="$work/cache" XDG_RUNTIME_DIR="$work/runtime"
export FZD_CONF_FILE="$work/config/fzd/fzd.conf"
export FZD_STATE_DIR="$work/state/fzd" FZD_CACHE_DIR="$work/cache/fzd" FZD_TMP_DIR="$work/runtime/fzd"
exec bash "$repo/fzd.sh" "$@"
