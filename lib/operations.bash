# shellcheck shell=bash
# shellcheck disable=SC2034 # Shared selection/status fields are consumed by main.
FZD_COPY_STAGES=()
_status_item() {
  _display_name "${2##*/}"
  FZD_STATUS="$1: $REPLY"
}
_operation_item() {
  local path=$1 scope=${2:-local} parent
  _parent_path "$CUR"
  parent=$REPLY
  if [[ $path != /* || $path == / || $path == "$CUR" ||
    ($scope == local && $path == "$parent") || (! -e $path && ! -L $path) ]]; then
    FZD_STATUS='Select an existing file or directory, not the navigation row'
    return 1
  fi
}
_operation_name() {
  [[ -n $1 && $1 != */* && $1 != . && $1 != .. ]] || {
    FZD_STATUS='Name must be nonempty and contain no slash (not . or ..)'
    return 1
  }
}
_operation_run() {
  local error_file rc=0 message
  _make_temp || return 1
  error_file=$REPLY
  "$@" >/dev/null 2>"$error_file" || rc=$?
  if ((rc)); then
    message=$(<"$error_file")
    _display_name "$message"
    FZD_STATUS="${REPLY:-Operation failed (status $rc)}"
  fi
  _remove_temp "$error_file"
  return "$rc"
}
_operation_descendant() {
  [[ -d $1 && ! -L $1 ]] || return 0
  local source destination
  IFS= read -r -d '' source < <(realpath -ze -- "$1") || return 1
  IFS= read -r -d '' destination < <(realpath -ze -- "$2") || return 1
  if [[ $source == / || $destination == "$source" || $destination == "$source/"* ]]; then
    FZD_STATUS='Cannot paste a directory into itself or its descendants'
    return 1
  fi
}
_stage_cleanup() {
  # Only private staging copies created by this process reach this function.
  # The user's selected source is never passed to recursive cleanup.
  local stage=$1 previous remaining_stages=()
  if [[ -e $stage || -L $stage ]]; then
    [[ -d $stage && -O $stage && ! -L $stage ]] || return 1
    chmod -R u+rwX -- "$stage" 2>/dev/null || return 1
    rm -r -- "$stage" 2>/dev/null || return 1
  fi
  for previous in "${FZD_COPY_STAGES[@]}"; do
    [[ $previous == "$stage" ]] || remaining_stages+=("$previous")
  done
  FZD_COPY_STAGES=("${remaining_stages[@]}")
}
_operations_cleanup() {
  local stage
  for stage in "${FZD_COPY_STAGES[@]}"; do
    _stage_cleanup "$stage" || printf 'fzd: private copy staging retained: %q\n' "$stage" >&2
  done
}
_clipboard_set() {
  local operation=$1 source=$2 scope=${3:-local} rc=0
  _operation_item "$source" "$scope" || return 1
  _state_lock || return 1
  if _clipboard_read; then
    _state_write clipboard FZD-CLIPBOARD-1 "$operation" "$source" || rc=1
  else rc=1; fi
  _state_unlock
  ((rc == 0)) || return "$rc"
  _status_item "${operation^^}" "$source"
}
_clipboard_paste() {
  _state_lock || return 1
  local source destination operation stage rc=0
  if ! _clipboard_read || ! _recents_read; then
    _state_unlock
    return 1
  fi
  source=$CLIP_PATH
  operation=$CLIP_OP
  if [[ -z $source ]]; then
    FZD_STATUS='Clipboard is empty'
    _state_unlock
    return 1
  fi
  destination=${CUR%/}/${source##*/}
  if [[ ! -e $source && ! -L $source ]]; then
    FZD_STATUS='Clipboard source is missing; clipboard retained'
    _state_unlock
    return 1
  fi
  if [[ -e $destination || -L $destination ]]; then
    FZD_STATUS='Destination exists; paste cancelled (rename the source to use another name)'
    _state_unlock
    return 1
  fi
  if ! _operation_descendant "$source" "$CUR"; then
    _state_unlock
    return 1
  fi
  if [[ $operation == copy ]]; then
    if stage=$(mktemp -d -- "${CUR%/}/.fzd-copy.XXXXXXXX"); then
      FZD_COPY_STAGES+=("$stage")
      if _operation_run cp -a --reflink=auto -- "$source" "$stage/item" &&
        _operation_run mv -nT -- "$stage/item" "$destination"; then
        if [[ -e $stage/item || -L $stage/item || (! -e $destination && ! -L $destination) ]]; then
          FZD_STATUS='Destination changed during paste; nothing replaced'
          rc=1
        fi
      else rc=1; fi
      _stage_cleanup "$stage" || {
        _display_name "$stage"
        FZD_STATUS="Copy staging retained: $REPLY"
        rc=1
      }
    else
      FZD_STATUS='Cannot create private copy staging in this directory'
      rc=1
    fi
  else
    if _operation_run mv -nT -- "$source" "$destination"; then
      if [[ -e $source || -L $source || (! -e $destination && ! -L $destination) ]]; then
        FZD_STATUS='Source or destination changed; move not completed'
        rc=1
      elif _references_update "$source" "$destination"; then
        rm -f -- "$FZD_EXPLORER_STATE/clipboard" || rc=1
      else
        FZD_STATUS='Item moved; persistent references could not be saved'
        rc=1
      fi
    else rc=1; fi
  fi
  _state_unlock
  ((rc == 0)) || return "$rc"
  FZD_SELECT_NAME=${destination##*/}
  FZD_QUERY=''
  if [[ $operation == copy ]]; then
    _status_item Copied "$destination"
  else _status_item Moved "$destination"; fi
}
_rename_item() {
  local source=$1 name=$2 destination rc=0
  _operation_item "$source" && _operation_name "$name" || return 1
  destination=${source%/*}/$name
  [[ $source != "$destination" ]] || {
    FZD_STATUS='Name unchanged'
    return 0
  }
  if [[ -e $destination || -L $destination ]]; then
    FZD_STATUS='Rename failed: destination exists'
    return 1
  fi
  _state_lock || return 1
  if ! _recents_read || ! _clipboard_read; then
    _state_unlock
    return 1
  fi
  if _operation_run mv -nT -- "$source" "$destination"; then
    if [[ -e $source || -L $source || (! -e $destination && ! -L $destination) ]]; then
      FZD_STATUS='Rename failed: source or destination changed'
      rc=1
    elif ! _references_update "$source" "$destination"; then
      FZD_STATUS='Item renamed; persistent references could not be saved'
      rc=1
    fi
  else rc=1; fi
  _state_unlock
  ((rc == 0)) || return "$rc"
  FZD_SELECT_NAME=$name
  FZD_QUERY=''
  _status_item Renamed "$destination"
}
_mkdir_item() {
  local name=$1
  _operation_name "$name" || return 1
  _operation_run mkdir -- "${CUR%/}/$name" || return 1
  FZD_SELECT_NAME=$name
  FZD_QUERY=''
  _status_item Created "${CUR%/}/$name"
}
_trash_backend() {
  TRASH_COMMAND=()
  if command -v gio >/dev/null 2>&1; then
    TRASH_COMMAND=(gio trash --)
  elif command -v trash-put >/dev/null 2>&1; then
    TRASH_COMMAND=(trash-put --)
  else
    FZD_STATUS='Trash unavailable: install gio (glib) or trash-cli; nothing deleted'
    return 1
  fi
}
_trash_item() {
  local source=$1 expected=${2:-} fingerprint rc=0
  _operation_item "$source" || return 1
  _trash_backend || return 1
  if [[ -d $source && ! -L $source ]] && ! _operation_descendant "$source" "$CUR"; then
    FZD_STATUS='Cannot trash the directory being browsed or its ancestors'
    return 1
  fi
  _state_lock || return 1
  if ! _recents_read || ! _clipboard_read; then
    _state_unlock
    return 1
  fi
  if [[ -n $expected ]]; then
    fingerprint=$(stat -c '%d:%i:%f:%s:%Z' -- "$source" 2>/dev/null) || {
      FZD_STATUS='Selected item is unavailable; nothing trashed'
      _state_unlock
      return 1
    }
    if [[ $fingerprint != "$expected" ]]; then
      FZD_STATUS='Item changed during confirmation; nothing trashed'
      _state_unlock
      return 1
    fi
  fi
  if _operation_run "${TRASH_COMMAND[@]}" "$source"; then
    if [[ -e $source || -L $source ]]; then
      FZD_STATUS='Trash did not remove the selected item'
      rc=1
    elif ! _references_update "$source" ''; then
      FZD_STATUS='Item trashed; persistent references could not be saved'
      rc=1
    fi
  else rc=1; fi
  _state_unlock
  ((rc == 0)) || return "$rc"
  FZD_SELECT_NAME=''
  FZD_QUERY=''
  _status_item 'Moved to Trash' "$source"
}
_explorer_action() {
  case "$1" in
  COPY) _clipboard_set copy "$2" "${3:-local}" ;;
  CUT) _clipboard_set cut "$2" "${3:-local}" ;;
  PASTE) _clipboard_paste ;;
  RENAME)
    _operation_item "$2" || return 1
    if _ui_name Rename "${2##*/}"; then _rename_item "$2" "$REPLY"; else return 1; fi
    ;;
  MKDIR) if _ui_name 'New directory' ''; then _mkdir_item "$REPLY"; else return 1; fi ;;
  TRASH)
    local fingerprint
    _operation_item "$2" && _trash_backend || return 1
    fingerprint=$(stat -c '%d:%i:%f:%s:%Z' -- "$2" 2>/dev/null) || {
      FZD_STATUS='Selected item is unavailable; nothing trashed'
      return 1
    }
    if _ui_confirm_trash "$2"; then _trash_item "$2" "$fingerprint"; else return 1; fi
    ;;
  *) return 1 ;;
  esac
}
