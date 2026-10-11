# shellcheck shell=bash
# shellcheck disable=SC2034 # Shared state is consumed by the application and UI.
# Private, versioned NUL records. Writers serialize and publish by atomic rename.
_state_lock() {
  local path
  command -v flock >/dev/null 2>&1 || {
    FZD_STATUS='Persistent state requires flock (util-linux)'
    return 1
  }
  FZD_EXPLORER_STATE=$FZD_STATE_DIR/explorer
  # Parent XDG state directories are initialized separately by the application.
  # shellcheck disable=SC2174
  if [[ -L $FZD_EXPLORER_STATE ]] || ! mkdir -p -m 700 -- "$FZD_EXPLORER_STATE"; then
    FZD_STATUS='Cannot create private Explorer state'
    return 1
  fi
  [[ -O $FZD_EXPLORER_STATE && -d $FZD_EXPLORER_STATE ]] || {
    FZD_STATUS='Explorer state directory is not owned by this user'
    return 1
  }
  chmod 700 -- "$FZD_EXPLORER_STATE" || {
    FZD_STATUS='Cannot protect Explorer state permissions'
    return 1
  }
  for path in lock recents clipboard; do
    path=$FZD_EXPLORER_STATE/$path
    [[ ! -L $path && (! -e $path || (-f $path && -O $path)) ]] || {
      FZD_STATUS='Unsafe Explorer state file; no operation performed'
      return 1
    }
  done
  # Redirection creates the lock privately even with a permissive calling umask.
  local old_umask
  old_umask=$(umask)
  umask 077
  if ! exec {FZD_LOCK_FD}>"$FZD_EXPLORER_STATE/lock"; then
    umask "$old_umask"
    FZD_STATUS='Cannot open Explorer state lock'
    return 1
  fi
  umask "$old_umask"
  if ! flock -w 2 "$FZD_LOCK_FD"; then
    exec {FZD_LOCK_FD}>&-
    FZD_STATUS='Explorer state is busy; try again'
    return 1
  fi
  FZD_STATE_HELD=1
}
_state_unlock() {
  exec {FZD_LOCK_FD}>&-
  FZD_STATE_HELD=0
}
_state_write() {
  local target=$1 temporary
  shift
  temporary=$(mktemp "$FZD_EXPLORER_STATE/.pending.XXXXXXXX") || {
    FZD_STATUS='Cannot create an atomic Explorer state update'
    return 1
  }
  FZD_TEMP_FILES+=("$temporary")
  if ! printf '%s\0' "$@" >"$temporary" || ! mv -fT -- "$temporary" "$FZD_EXPLORER_STATE/$target"; then
    FZD_STATUS='Cannot publish Explorer state; previous state retained'
    _remove_temp "$temporary"
    return 1
  fi
  _remove_temp "$temporary"
}
_recents_read() {
  RAW_RECENTS=()
  [[ -e $FZD_EXPLORER_STATE/recents ]] || return 0
  local magic path fd
  exec {fd}<"$FZD_EXPLORER_STATE/recents" || return 1
  if ! IFS= read -r -d '' magic <&"$fd" || [[ $magic != FZD-RECENT-1 ]]; then
    exec {fd}<&-
    FZD_STATUS='Invalid recent-directory state'
    return 1
  fi
  while :; do
    path=''
    if ! IFS= read -r -d '' path <&"$fd"; then
      exec {fd}<&-
      [[ -z $path ]] || {
        FZD_STATUS='Truncated recent-directory state'
        return 1
      }
      return 0
    fi
    [[ $path == /* ]] || {
      exec {fd}<&-
      FZD_STATUS='Invalid recent-directory path'
      return 1
    }
    RAW_RECENTS+=("$path")
    ((${#RAW_RECENTS[@]} <= 25)) || {
      exec {fd}<&-
      return 1
    }
  done
}
_recents_merge() {
  local path previous duplicate
  RECENTS=()
  for path in "${RECENT_PENDING[@]}" "${RAW_RECENTS[@]}"; do
    [[ -d $path && -r $path && -x $path ]] || continue
    duplicate=0
    for previous in "${RECENTS[@]}"; do [[ $path != "$previous" ]] || duplicate=1; done
    ((duplicate)) || RECENTS+=("$path")
    ((${#RECENTS[@]} < 25)) || break
  done
}
_recents_flush() {
  _state_lock || return 1
  local rc=0
  if _recents_read; then
    _recents_merge
    _state_write recents FZD-RECENT-1 "${RECENTS[@]}" || rc=1
    ((rc)) || RECENT_PENDING=()
  else rc=1; fi
  _state_unlock
  return "$rc"
}
_clipboard_read() {
  CLIP_OP=''
  CLIP_PATH=''
  [[ -e $FZD_EXPLORER_STATE/clipboard ]] || return 0
  local fd magic extra
  exec {fd}<"$FZD_EXPLORER_STATE/clipboard" || return 1
  if ! IFS= read -r -d '' magic <&"$fd" || [[ $magic != FZD-CLIPBOARD-1 ]] ||
    ! IFS= read -r -d '' CLIP_OP <&"$fd" || ! IFS= read -r -d '' CLIP_PATH <&"$fd" ||
    [[ $CLIP_OP != copy && $CLIP_OP != cut ]] || [[ $CLIP_PATH != /* ]] ||
    { IFS= read -r -d '' extra <&"$fd" || [[ -n $extra ]]; }; then
    exec {fd}<&-
    FZD_STATUS='Invalid clipboard state'
    return 1
  fi
  exec {fd}<&-
}
_reference_path() {
  REPLY=$1
  if [[ $1 == "$2" || $1 == "$2/"* ]]; then
    if [[ -n $3 ]]; then REPLY=$3${1#"$2"}; else REPLY=''; fi
  fi
}
_references_update() {
  # Caller holds the state lock. Rebase before discarding now-missing old paths.
  local old=$1 new=$2 index parent
  _recents_read && _clipboard_read || return 1
  _parent_path "$old"
  parent=$REPLY
  for index in "${!RAW_RECENTS[@]}"; do
    _reference_path "${RAW_RECENTS[index]}" "$old" "$new"
    RAW_RECENTS[index]=$REPLY
  done
  for index in "${!RECENT_PENDING[@]}"; do
    _reference_path "${RECENT_PENDING[index]}" "$old" "$new"
    RECENT_PENDING[index]=$REPLY
  done
  for index in "${!H_PATHS[@]}"; do
    if [[ ${H_PATHS[index]} == "$parent" && ${H_SELECTIONS[index]} == "${old##*/}" ]]; then
      H_SELECTIONS[index]=${new##*/}
    fi
    _reference_path "${H_PATHS[index]}" "$old" "$new"
    H_PATHS[index]=$REPLY
  done
  if [[ ${LAST_CHILD[$parent]:-} == "${old##*/}" ]]; then LAST_CHILD["$parent"]=${new##*/}; fi
  _reference_path "$CUR" "$old" "$new"
  CUR=$REPLY
  if [[ -n $CLIP_PATH ]]; then
    _reference_path "$CLIP_PATH" "$old" "$new"
    CLIP_PATH=$REPLY
    if [[ -n $CLIP_PATH ]]; then
      _state_write clipboard FZD-CLIPBOARD-1 "$CLIP_OP" "$CLIP_PATH" || return 1
    else rm -f -- "$FZD_EXPLORER_STATE/clipboard" || return 1; fi
  fi
  _recents_merge
  _state_write recents FZD-RECENT-1 "${RECENTS[@]}" || return 1
  RECENT_PENDING=()
}
