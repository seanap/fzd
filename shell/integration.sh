# shellcheck shell=bash
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

# Preserve existing functions, aliases, builtins and executables in both shells.
if ! command -v fzd_cd >/dev/null 2>&1; then
  function fzd_cd { _fzd_run_and_cd "$@"; }
fi
if ! command -v lf >/dev/null 2>&1; then
  function lf { _fzd_run_and_cd "$@"; }
fi
