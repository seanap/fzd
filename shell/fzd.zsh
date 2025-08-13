# ZLE widget: press Ctrl+O to run fzd and cd into result
fzd-cd-widget() {
  zle -I
  local dest rc
  dest="$("$HOME/.fzd/fzd.sh")"; rc=$?
  (( rc == 130 )) && return 0
  [[ -n "$dest" && -d "$dest" ]] && cd -- "$dest"
  zle reset-prompt
}
zle -N fzd-cd-widget
bindkey '^O' fzd-cd-widget
