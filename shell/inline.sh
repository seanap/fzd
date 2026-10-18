# shellcheck shell=bash
# Sourced only by an interactive shell after an explicit installer/user opt-in.
case $- in *i*) ;; *) return 0 ;; esac
[ "${FZD_INLINE_SUGGESTIONS:-0}" = 1 ] || return 0

if [ -n "${BASH_VERSION:-}" ]; then
  _fzd_loaded_blesh=0
  if ! command -v bleopt >/dev/null 2>&1; then
    _fzd_blesh=${FZD_BLESH_PATH:-}
    if [ -z "$_fzd_blesh" ]; then
      for _fzd_blesh in "${XDG_DATA_HOME:-$HOME/.local/share}/blesh/ble.sh" \
        "$_FZD_INTEGRATION_DIR/../blesh/ble.sh" /usr/local/share/blesh/ble.sh; do
        [ ! -r "$_fzd_blesh" ] || break
      done
    fi
    if [ ! -r "$_fzd_blesh" ]; then
      printf 'fzd: inline suggestions need ble.sh; rerun the installer with --inline-suggestions\n' >&2
      unset _fzd_blesh _fzd_loaded_blesh
      return 0
    fi
    # Upstream should be sourced at script scope, then attached after setup.
    # shellcheck source=/dev/null
    if ! source "$_fzd_blesh" --attach=none; then
      printf 'fzd: ble.sh could not initialize; native Tab completion remains available\n' >&2
      unset _fzd_blesh _fzd_loaded_blesh
      return 0
    fi
    _fzd_loaded_blesh=1
  fi
  # Preserve already active engines and explicit upstream configuration,
  # including opt-outs, suppression options, and faces from .blerc/themes.
  if [ "$_fzd_loaded_blesh" -eq 1 ] &&
    [ ! -e "$HOME/.blerc" ] && [ ! -e "${XDG_CONFIG_HOME:-$HOME/.config}/blesh/init.sh" ] &&
    [ ! -s "${_ble_base_rcfile:-/dev/null}" ]; then
    bleopt complete_auto_complete=1
    # Retain unrelated options while enabling noninteractive completion suggestions.
    _fzd_inline_opts=":${bleopt_complete_auto_complete_opts:-}:"
    for _fzd_inline_flag in syntax-disabled syntax-unique syntax-suppress-ambiguous; do
      _fzd_inline_opts=${_fzd_inline_opts//:$_fzd_inline_flag:/:}
    done
    _fzd_inline_opts=${_fzd_inline_opts#:}
    _fzd_inline_opts=${_fzd_inline_opts%:}
    bleopt "complete_auto_complete_opts=$_fzd_inline_opts"
    ble-face -s auto_complete fg=242
  fi
  ble-attach
  unset _fzd_loaded_blesh _fzd_blesh _fzd_inline_opts _fzd_inline_flag
elif [ -n "${ZSH_VERSION:-}" ]; then
  _fzd_inline_zsh
fi
