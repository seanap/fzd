# shellcheck shell=bash
# shellcheck disable=SC2034 # Shared state is consumed by the main loop.
# All fzf output is captured; stdout remains the directory-return protocol.
_ui_encode_name() {
  # Keep readable UTF-8; escape invalid bytes in prompts, without changing IDs.
  local LC_ALL=C input index byte code width offset next valid out=''
  _display_name "$1"
  input=$REPLY
  for ((index = 0; index < ${#input}; index += width)); do
    byte=${input:index:1}
    printf -v code '%d' "'$byte"
    width=1
    valid=1
    if ((code >= 128)); then
      if ((code >= 194 && code <= 223)); then
        width=2
      elif ((code >= 224 && code <= 239)); then
        width=3
      elif ((code >= 240 && code <= 244)); then
        width=4
      else valid=0; fi
      for ((offset = 1; valid && offset < width; offset++)); do
        byte=${input:index+offset:1}
        [[ -n $byte ]] || {
          valid=0
          break
        }
        printf -v next '%d' "'$byte"
        ((next >= 128 && next <= 191)) || valid=0
        if ((offset == 1)); then
          ((code != 224 || next >= 160)) || valid=0
          ((code != 237 || next <= 159)) || valid=0
          ((code != 240 || next >= 144)) || valid=0
          ((code != 244 || next <= 143)) || valid=0
        fi
      done
    fi
    if ((valid)); then
      out+=${input:index:width}
    else
      printf -v byte '\\x%02x' "$code"
      out+=$byte
      width=1
    fi
  done
  REPLY=$out
}
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
  _ui_encode_name "$initial"
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
  local scope=${1:-local}
  local help=(
    'Navigation'
    '  Left / Right     Parent / enter directory'
    '  Enter            Return directory to shell / open file'
    '  Alt+Left/Right   Back / Forward'
    '  Alt+H            Recent directories'
    'Search'
    '  Type             Fuzzy search in this directory'
    '  Ctrl+F           Global search (Left / Esc returns)'
    'File Operations'
    '  Ctrl+C / Alt+C   Copy selected item'
    '  Ctrl+X / Alt+X   Cut selected item (move on Paste)'
    '  Ctrl+V / Alt+V   Paste into current directory'
  )
  if [[ $scope == global ]]; then
    help=('Navigation' '  Left / Esc       Return to directory view'
      '  Right            Enter selected directory'
      '  Enter            Return directory to shell / open file'
      'Search' '  Type             Search configured global roots'
      'File Operations' '  Ctrl+C / Alt+C   Copy result and return'
      '  Ctrl+X / Alt+X   Cut result and return')
  else
    help+=('  Ctrl+R / F2      Rename selected item' '  Ctrl+N / F7      Create directory')
  fi
  help+=('Other' '  F1 / Esc         Close help' '  Esc / Ctrl+G     Exit FZD' '  Up / Down        Select; scroll this help')
  printf '%s\n' "${help[@]}" | "$FZF_BIN" "${FZD_SCREEN_OPTS[@]}" \
    --height=100% --layout=reverse --border --no-mouse --no-multi --no-expect \
    --disabled --no-sort --prompt 'Help > ' --bind 'f1:abort,esc:abort,enter:ignore' >/dev/null || true
}
