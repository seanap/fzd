# FZD launcher: run TUI and cd into the chosen dir.
lf() {
  emulate -L zsh
  setopt pipe_fail
  local out rc
  out="$HOME/.fzd/fzd.sh"
  out="$("$out" "$@")"; rc=$?
  (( rc == 130 )) && return 0        # Esc/cancel
  [[ -n "$out" && -d "$out" ]] && builtin cd -- "$out"
}
