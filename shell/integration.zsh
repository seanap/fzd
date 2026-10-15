# Native zsh completion and upstream zoxide initialization.
function _fzd_shell_learns {
  command -v __zoxide_hook >/dev/null 2>&1 || return 1
  [[ ${precmd_functions[(Ie)__zoxide_hook]:-0} -gt 0 || ${chpwd_functions[(Ie)__zoxide_hook]:-0} -gt 0 ]]
}

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
function _fzd_init_completion {
  precmd_functions=("${(@)precmd_functions:#_fzd_init_completion}")
  if ! command -v compdef >/dev/null 2>&1; then
    [[ ${FZD_AUTO_COMPLETION:-1} != 0 ]] || return 0
    autoload -Uz compinit
    # Check ownership/permissions and ignore unsafe completion directories.
    # Use zsh's normal cache; never chmod or rewrite the user's completion files.
    if ! compinit -i; then
      printf 'fzd: zsh completion initialization failed\n' >&2
      return 0
    fi
  fi
  _fzd_register_completions
  [[ ${FZD_INLINE_SUGGESTIONS:-0} != 1 ]] || _fzd_inline_zsh
}

function _fzd_inline_zsh {
  if ! (( $+functions[_zsh_autosuggest_start] )); then
    local fzd_plugin=${FZD_ZSH_AUTOSUGGESTIONS_PATH:-}
    if [[ -z $fzd_plugin ]]; then
      for fzd_plugin in /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
        /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh; do
        [[ ! -r $fzd_plugin ]] || break
      done
    fi
    if [[ ! -r $fzd_plugin ]]; then
      printf 'fzd: inline suggestions need zsh-autosuggestions; rerun the installer with --inline-suggestions\n' >&2
      return 0
    fi
    source "$fzd_plugin" || return
  fi
  # Append completion without discarding/reordering the user's other strategies.
  typeset -ga ZSH_AUTOSUGGEST_STRATEGY
  (( ${#ZSH_AUTOSUGGEST_STRATEGY} )) || ZSH_AUTOSUGGEST_STRATEGY=(history)
  (( ${ZSH_AUTOSUGGEST_STRATEGY[(Ie)completion]:-0} )) || ZSH_AUTOSUGGEST_STRATEGY+=(completion)
}

_fzd_register_completions
case $- in
*i*)
  # Initialize only after the user's complete startup/framework configuration.
  typeset -ga precmd_functions
  # shellcheck disable=SC2296,SC2154
  [[ ${precmd_functions[(Ie)_fzd_init_completion]:-0} -gt 0 ]] || precmd_functions+=(_fzd_init_completion)
  if command -v zoxide >/dev/null 2>&1 && ! command -v __zoxide_hook >/dev/null 2>&1 && ! command -v __zoxide_z >/dev/null 2>&1; then
    # shellcheck disable=SC2296
    [[ ${precmd_functions[(Ie)_fzd_init_zoxide]:-0} -gt 0 ]] || precmd_functions+=(_fzd_init_zoxide)
  fi
  ;;
esac
