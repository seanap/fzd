# Native zsh completion and upstream zoxide initialization.
function _fzd_init_zoxide {
  # shellcheck disable=SC2296,SC2154 # Native zsh arrays/options.
  precmd_functions=("${(@)precmd_functions:#_fzd_init_zoxide}")
  { command -v __zoxide_hook >/dev/null 2>&1 || command -v __zoxide_z >/dev/null 2>&1; } && return 0
  local fzd_init
  fzd_init=$(command zoxide init zsh --no-cmd --hook pwd) || return
  # --no-cmd in older zoxide still binds a ZLE widget; only install its hook.
  setopt localoptions no_zle
  eval "$fzd_init"
}

function _fzd_complete {
  setopt localoptions extendedglob
  local -a fzd_matches
  # shellcheck disable=SC2296,SC2154,SC2086 # Native zsh completion parameters.
  fzd_matches=("${(@f)$(_fzd_candidates "${words[@]:1:$((CURRENT-1))}")}")
  compadd -V learned -- "${fzd_matches[@]}"
  [ "$CURRENT" -ne 2 ] || _files -/
}
function _fzd_register_completions {
  command -v compdef >/dev/null 2>&1 || return 0
  precmd_functions=("${(@)precmd_functions:#_fzd_register_completions}")
  local fzd_cmd
  for fzd_cmd in lf lff fzd_cd fzd_find; do
    # shellcheck disable=SC2296,SC2154 # Native zsh associative arrays.
    if [[ ${functions[$fzd_cmd]:-} == *'_fzd_jump "$@"'* || ${functions[$fzd_cmd]:-} == *'_fzd_find "$@"'* ]]; then
      # shellcheck disable=SC2296
      [[ -n ${_comps[$fzd_cmd]:-} ]] || compdef _fzd_complete "$fzd_cmd"
    fi
  done
}
_fzd_register_completions
case $- in
*i*)
  # compinit may run later in the user's zshrc. Retry registration at prompts.
  typeset -ga precmd_functions
  # shellcheck disable=SC2296,SC2154
  [[ ${precmd_functions[(Ie)_fzd_register_completions]:-0} -gt 0 ]] || precmd_functions+=(_fzd_register_completions)
  if command -v zoxide >/dev/null 2>&1 && ! command -v __zoxide_hook >/dev/null 2>&1 && ! command -v __zoxide_z >/dev/null 2>&1; then
    # shellcheck disable=SC2296
    [[ ${precmd_functions[(Ie)_fzd_init_zoxide]:-0} -gt 0 ]] || precmd_functions+=(_fzd_init_zoxide)
  fi
  ;;
esac
