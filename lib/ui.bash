# shellcheck shell=bash
# shellcheck disable=SC2034 # Shared state is consumed by the main loop.
# All fzf output is captured; stdout remains the directory-return protocol.
_ui_decode_name() {
  local LC_ALL=C input=$1 index char hex
  REPLY=''
  for ((index = 0; index < ${#input}; index++)); do
    char=${input:index:1}
    if [[ $char == \\ ]]; then
      ((index += 1))
      char=${input:index:1}
      case "$char" in
      \\) char=$'\\' ;;
      n) char=$'\n' ;; r) char=$'\r' ;; t) char=$'\t' ;; e) char=$'\033' ;;
      x)
        hex=${input:index+1:2}
        [[ $hex =~ ^[0-9a-fA-F]{2}$ && $hex != 00 ]] || {
          FZD_STATUS='Invalid byte escape (NUL is not allowed)'
          return 1
        }
        printf -v char '%b' "\\x$hex"
        ((index += 2))
        ;;
      *)
        FZD_STATUS='Use \\ for a backslash, \n for newline, or \xHH for a byte'
        return 1
        ;;
      esac
    fi
    REPLY+=$char
  done
}
_ui_name() {
  local purpose=$1 initial=$2 capture query rc=0
  _display_name "$initial"
  query=$REPLY
  _make_temp || return 1
  capture=$REPLY
  printf 'Enter confirms · Esc cancels\n' | "$FZF_BIN" "${FZD_SCREEN_OPTS[@]}" \
    --height=100% --layout=reverse --border --no-mouse --no-multi --no-expect \
    --disabled --no-sort --print-query --query="$query" --prompt "$purpose > " \
    --header 'Name escapes: \n newline · \t tab · \xHH byte · \\ backslash' \
    --bind 'enter:accept,esc:abort' >"$capture" || rc=$?
  if ((rc == 0)); then IFS= read -r query <"$capture" || rc=1; fi
  _remove_temp "$capture"
  ((rc == 0)) || {
    FZD_STATUS='Cancelled'
    return 1
  }
  _ui_decode_name "$query"
}
_ui_confirm_trash() {
  local path=$1 capture choice rc=0
  _display_name "$path"
  local label="Trash: $REPLY"
  _make_temp || return 1
  capture=$REPLY
  printf 'Cancel\nMove to Trash\n' | "$FZF_BIN" "${FZD_SCREEN_OPTS[@]}" \
    --height=100% --layout=reverse --border --no-mouse --no-multi --no-expect \
    --no-sort --prompt 'Confirm > ' --header "$label" \
    --bind 'enter:accept,esc:abort' >"$capture" || rc=$?
  IFS= read -r choice <"$capture" || true
  _remove_temp "$capture"
  [[ $rc == 0 && $choice == 'Move to Trash' ]] || {
    FZD_STATUS='Trash cancelled'
    return 1
  }
}
_ui_recents() {
  _explorer_load state && _recents_flush || return 1
  ((${#RECENTS[@]})) || {
    FZD_STATUS='No accessible recent directories'
    return 0
  }
  local records=() index capture selected rc=0
  _b64_paths "${RECENTS[@]}" || return 1
  for index in "${!RECENTS[@]}"; do
    _display_name "${RECENTS[index]/#$HOME/~}"
    records+=("${B64_PATHS[index]}$DELIM$REPLY")
  done
  _make_temp || return 1
  capture=$REPLY
  printf '%s\n' "${records[@]}" | "$FZF_BIN" "${FZD_SCREEN_OPTS[@]}" \
    --height=100% --layout=reverse --border --no-mouse --no-multi --no-expect \
    --delimiter "$DELIM" --with-nth=2.. --prompt 'Recent > ' \
    --header 'Enter visits · Esc returns' --bind 'enter:accept,esc:abort' >"$capture" || rc=$?
  IFS= read -r selected <"$capture" || true
  _remove_temp "$capture"
  ((rc == 0)) || return 0
  _decode_path "${selected%%"$DELIM"*}"
  if [[ -d $REPLY && -r $REPLY && -x $REPLY ]]; then
    CUR=$REPLY
  else FZD_STATUS='Recent directory is no longer accessible'; fi
}
_ui_help() {
  local help=(
    'Navigation'
    '  Left / Right     Parent / enter directory'
    '  Enter            Return directory to shell / open file'
    '  Alt+Left/Right   Back / Forward'
    '  Alt+H            Recent directories'
    'Search'
    '  Type             Fuzzy search in this directory'
    '  Ctrl+F           Global search (Left / Esc returns)'
  )
  help+=('Other' '  F1 / Esc         Close help' '  Esc / Ctrl+G     Exit FZD' '  Up / Down        Select; scroll this help')
  printf '%s\n' "${help[@]}" | "$FZF_BIN" "${FZD_SCREEN_OPTS[@]}" \
    --height=100% --layout=reverse --border --no-mouse --no-multi --no-expect \
    --disabled --no-sort --prompt 'Help > ' --bind 'f1:abort,esc:abort,enter:ignore' >/dev/null || true
}
