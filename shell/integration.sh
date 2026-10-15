# shellcheck shell=bash
# shellcheck disable=SC2178,SC2128 # PROMPT_COMMAND supports both scalar and array forms.
# FZD shell integration: source from Bash or zsh. No configuration is executed.
# FZD_BIN may select a different executable; installers set _FZD_INSTALL_BIN.
function _fzd_run_and_cd {
  local fzd_result fzd_status
  # A sentinel preserves every trailing newline. Remove only FZD's one protocol
  # newline, and propagate failures without attempting to change directory.
  if fzd_result=$(
    EDITOR="${EDITOR:-}" VISUAL="${VISUAL:-}" LS_COLORS="${LS_COLORS:-}" \
      command "${FZD_BIN:-${_FZD_INSTALL_BIN:-fzd}}" "$@"
    fzd_status=$?
    printf '.'
    exit "$fzd_status"
  ); then
    fzd_result=${fzd_result%.}
    [ -n "$fzd_result" ] || return 0
    case "$fzd_result" in
    *$'\n') fzd_result=${fzd_result%$'\n'} ;;
    *)
      printf 'fzd: invalid directory response\n' >&2
      return 1
      ;;
    esac
    [ -d "$fzd_result" ] || {
      printf 'fzd: selected directory is no longer available\n' >&2
      return 1
    }
    builtin cd -- "$fzd_result" || return
  else
    fzd_status=$?
    [ "$fzd_status" -eq 130 ] && return 0
    return "$fzd_status"
  fi
}

function _fzd_require_zoxide {
  command -v zoxide >/dev/null 2>&1 && return 0
  printf 'fzd: zoxide is required; install it with your distribution package manager\n' >&2
  return 1
}

function _fzd_shell_learns {
  command -v __zoxide_hook >/dev/null 2>&1 || return 1
  [[ "${PROMPT_COMMAND[*]:-} ${__vsc_original_prompt_command[*]:-}" == *'__zoxide_hook'* ]]
}

function _fzd_jump {
  _fzd_require_zoxide || return
  [ "$#" -gt 0 ] || {
    _fzd_run_and_cd
    return
  }
  local fzd_target
  if [ "$#" -eq 2 ] && [ "$1" = -- ]; then
    fzd_target=$2
  elif [ "$#" -eq 1 ] && { [ -d "$1" ] || [ "$1" = - ]; }; then
    fzd_target=$1
  elif fzd_target=$(command zoxide query -- "$@" 2>/dev/null && printf '.'); then
    # Preserve trailing newlines in zoxide's line-delimited output protocol.
    fzd_target=${fzd_target%.}
    fzd_target=${fzd_target%$'\n'}
  else
    _fzd_run_and_cd --global "$*"
    return
  fi
  builtin cd -- "$fzd_target" || return
  # Interactive upstream hooks learn at chpwd/the next prompt. Scripts have no
  # prompt, and should still learn successful jumps immediately.
  case $- in
  *i*) _fzd_shell_learns && return 0 ;;
  esac
  command zoxide add -- "$PWD" || true
}

function _fzd_find {
  _fzd_require_zoxide || return
  _fzd_run_and_cd --global "$*"
}

# Noninteractive, ranked suggestions. Never invoke zoxide's interactive picker.
# Prefer a leaf name so `lf imm<Tab>` can become `lf immich`, including inline
# suggestions in engines that require the suggestion to extend the typed prefix.
function _fzd_candidates {
  local fzd_path fzd_leaf fzd_prefix fzd_seen=$'\n'
  fzd_prefix=''
  for fzd_prefix; do :; done
  while IFS= read -r fzd_path; do
    [ -d "$fzd_path" ] || continue
    case $fzd_path in *[$'\001'-$'\037'$'\177']*) continue ;; esac
    fzd_leaf=${fzd_path##*/}
    case $fzd_leaf in
    "$fzd_prefix"*) ;;
    *)
      [ "$#" -eq 1 ] || continue
      fzd_leaf=$fzd_path
      ;;
    esac
    case $fzd_seen in *$'\n'"$fzd_leaf"$'\n'*) continue ;; esac
    printf '%s\n' "$fzd_leaf"
    fzd_seen=$fzd_seen$fzd_leaf$'\n'
  done < <(command zoxide query --list -- "$@" 2>/dev/null)
}

# Delay upstream initialization until shell startup has finished, allowing a
# user's later `zoxide init` (including --hook none/--cmd) to take precedence.
function _fzd_init_zoxide {
  if [ -n "${BASH_VERSION:-}" ]; then
    local fzd_item fzd_is_array=0 fzd_prompt='' fzd_init
    local -a fzd_prompts=()
    if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
      fzd_is_array=1
      for fzd_item in "${PROMPT_COMMAND[@]}"; do
        [ "$fzd_item" = _fzd_init_zoxide ] || fzd_prompts+=("$fzd_item")
      done
      PROMPT_COMMAND=("${fzd_prompts[@]}")
    else
      fzd_prompt=${PROMPT_COMMAND:-}
      fzd_prompt=${fzd_prompt//;_fzd_init_zoxide/}
      fzd_prompt=${fzd_prompt#_fzd_init_zoxide;}
      [ "$fzd_prompt" != _fzd_init_zoxide ] || fzd_prompt=''
      PROMPT_COMMAND=$fzd_prompt
    fi
    { command -v __zoxide_hook >/dev/null 2>&1 || command -v __zoxide_z >/dev/null 2>&1; } && return 0
    fzd_init=$(command zoxide init bash --no-cmd --hook pwd) || return
    # Older upstream zoxide versions only understand scalar PROMPT_COMMAND.
    # Restore its exact type/contents and append the generated hook once.
    eval "$fzd_init"
    if [ "$fzd_is_array" -eq 1 ]; then
      PROMPT_COMMAND=("${fzd_prompts[@]}" __zoxide_hook)
    else
      fzd_prompt=${fzd_prompt%"${fzd_prompt##*[![:space:];]}"}
      PROMPT_COMMAND="${fzd_prompt:+$fzd_prompt;}__zoxide_hook"
    fi

  fi
}

# Preserve existing functions, aliases, builtins and executables in both shells.
if ! command -v fzd_cd >/dev/null 2>&1; then
  function fzd_cd { _fzd_jump "$@"; }
fi
if ! command -v lf >/dev/null 2>&1; then
  function lf { _fzd_jump "$@"; }
fi
if ! command -v fzd_find >/dev/null 2>&1; then
  function fzd_find { _fzd_find "$@"; }
fi
if ! command -v lff >/dev/null 2>&1; then
  function lff { _fzd_find "$@"; }
fi

if [ -n "${BASH_VERSION:-}" ]; then
  _FZD_INTEGRATION_DIR=${BASH_SOURCE[0]%/*}
  [ "$_FZD_INTEGRATION_DIR" != "${BASH_SOURCE[0]}" ] || _FZD_INTEGRATION_DIR=.
  function _fzd_complete {
    local fzd_candidate
    COMPREPLY=()
    while IFS= read -r fzd_candidate; do COMPREPLY+=("$fzd_candidate"); done \
      < <(_fzd_candidates "${COMP_WORDS[@]:1:COMP_CWORD}")
    if [ "$COMP_CWORD" -eq 1 ]; then
      while IFS= read -r fzd_candidate; do COMPREPLY+=("$fzd_candidate"); done \
        < <(compgen -A directory -- "${COMP_WORDS[COMP_CWORD]}")
    fi
  }
  # Register only for FZD-owned commands; respect existing completion handlers.
  for _fzd_cmd in lf lff fzd_cd fzd_find; do
    if [[ $(declare -f "$_fzd_cmd") == *'_fzd_jump "$@"'* || $(declare -f "$_fzd_cmd") == *'_fzd_find "$@"'* ]]; then
      complete -p "$_fzd_cmd" >/dev/null 2>&1 || complete -o filenames -o nosort -F _fzd_complete "$_fzd_cmd"
    fi
  done
  unset _fzd_cmd
  case $- in
  *i*)
    if command -v zoxide >/dev/null 2>&1 && ! command -v __zoxide_hook >/dev/null 2>&1 && ! command -v __zoxide_z >/dev/null 2>&1; then
      if [[ $(declare -p PROMPT_COMMAND 2>/dev/null) == 'declare -a'* ]]; then
        [[ " ${PROMPT_COMMAND[*]} " == *' _fzd_init_zoxide '* ]] || PROMPT_COMMAND+=(_fzd_init_zoxide)
      elif [[ ${PROMPT_COMMAND:-} != *'_fzd_init_zoxide'* ]]; then
        PROMPT_COMMAND=${PROMPT_COMMAND:-}
        PROMPT_COMMAND=${PROMPT_COMMAND%"${PROMPT_COMMAND##*[![:space:];]}"}
        PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND;}_fzd_init_zoxide"
      fi
    fi
    ;;
  esac
elif [ -n "${ZSH_VERSION:-}" ]; then
  # Keep native zsh syntax in its own file; %x identifies this sourced script.
  eval '_FZD_INTEGRATION_DIR="${${(%):-%x}:A:h}"; source "$_FZD_INTEGRATION_DIR/integration.zsh"'
fi
if [ "${FZD_INLINE_SUGGESTIONS:-0}" = 1 ]; then
  # shellcheck source=shell/inline.sh
  source "$_FZD_INTEGRATION_DIR/inline.sh"
fi
