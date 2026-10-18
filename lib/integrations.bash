# shellcheck shell=bash
# shellcheck disable=SC2034 # Status is consumed by the main UI.
# Optional actions run only on request, never while drawing a directory.
_copy_absolute_path() {
  local path=$1
  local -a provider=()
  [[ $path == /* && (-e $path || -L $path) ]] || {
    FZD_STATUS='No path selected'
    return 0
  }
  if [[ -n ${WAYLAND_DISPLAY:-} ]] && _have wl-copy; then
    provider=(wl-copy)
  elif [[ -n ${DISPLAY:-} ]]; then
    if _have xclip; then provider=(xclip -selection clipboard); elif _have xsel; then provider=(xsel --clipboard --input); fi
  fi
  if ((${#provider[@]} == 0)); then
    FZD_STATUS='No clipboard provider for this display'
  elif printf '%s' "$path" | _timeout_wrap 2 "${provider[@]}" 2>/dev/null; then
    FZD_STATUS='Path copied'
  else FZD_STATUS='Clipboard copy failed'; fi
}

_launch_lazygit() {
  local path=$1 directory
  if ! _have lazygit; then
    FZD_STATUS='Install Lazygit to use Alt+G'
    return 0
  fi
  if [[ -d $path ]]; then directory=$path; elif [[ -f $path ]]; then directory=${path%/*}; else
    FZD_STATUS='No path selected'
    return 0
  fi
  if ! _have git || [[ $(git -C "$directory" rev-parse --is-inside-work-tree 2>/dev/null) != true ]]; then
    FZD_STATUS='Selection is outside a Git working tree'
    return 0
  fi
  if (cd -- "$directory" && _terminal_run lazygit); then FZD_STATUS='Returned from Lazygit'; else FZD_STATUS='Lazygit exited with an error'; fi
}

_integration_action() {
  case $1 in COPY_PATH) _copy_absolute_path "$2" ;; LAZYGIT) _launch_lazygit "$2" ;; esac
}
