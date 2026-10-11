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
  if [[ $destination == "$source" || $destination == "$source/"* ]]; then
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
        FZD_STATUS="Copy staging retained: $stage"
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
_explorer_action() {
  case "$1" in
  COPY) _clipboard_set copy "$2" "${3:-local}" ;;
  CUT) _clipboard_set cut "$2" "${3:-local}" ;;
  PASTE) _clipboard_paste ;;
  *) return 1 ;;
  esac
}
