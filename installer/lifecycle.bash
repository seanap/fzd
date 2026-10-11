# File transactions use a private persistent journal. Signals roll back; a
# SIGKILL leaves a journal for explicit --recover, never auto-replay.
hash_file() {
  REPLY=$(sha256sum <"$1")
  REPLY=${REPLY%% *}
}
record() {
  local previous
  if [[ $1 == rc ]]; then
    for previous in "${RECORDED_RC[@]}"; do [[ $previous != "$2" ]] || return 0; done
    RECORDED_RC+=("$2")
  fi
  printf '%s\0%s\0%s\0' "$1" "$2" "$3" >>"$TX/manifest"
}

begin_transaction() {
  RECORDED_RC=()
  PENDING_PATHS=()
  mkdir -p -- "$DATA"
  LOCK="$DATA/.install-lock"
  mkdir -- "$LOCK" 2>/dev/null || die "Installation locked. If no installer is running, use: bash install.sh --prefix $(printf %q "$PREFIX") --recover"
  printf '%s\n' "$$" >"$LOCK/pid"
  TX=$(mktemp -d "$DATA/.transaction.XXXXXXXX")
  chmod 700 "$TX"
  : >"$TX/journal"
  : >"$TX/manifest"
  printf '%s\0' "$CFG" >"$TX/rc-targets"
  printf '%s\0' "$TX" >"$LOCK/transaction"
  COMMITTED=0
  trap finish_transaction EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP
}

journal_path_allowed() {
  # Recovery journals are local user data, never executable shell code.
  local target=$1
  [[ $target == /* && $target != *'/../'* && $target != */.. ]] || return 1
  [[ $target != "$PREFIX/"* && $target != "$HOME/"* && $target != "$CFG" && $target != "${ZDOTDIR:-$HOME}/.zshrc" && $target != "$XDG_CONFIG_HOME/"* ]] || return 0
  local rc
  if [[ -f $TX/rc-targets && ! -L $TX/rc-targets ]]; then
    while IFS= read -r -d '' rc; do [[ $target != "$rc" ]] || return 0; done <"$TX/rc-targets"
  fi
  return 1
}

rollback() {
  local target existed backup pending i
  local -a targets=() flags=() backups=() pendings=()
  while true; do
    target=''
    if ! IFS= read -r -d '' target; then
      [[ -z $target ]] || return 1
      break
    fi
    if ! IFS= read -r -d '' existed || ! IFS= read -r -d '' backup || ! IFS= read -r -d '' pending; then return 1; fi
    journal_path_allowed "$target" || {
      warn "Refusing invalid recovery target: $target"
      return 1
    }
    [[ $backup =~ ^backup-[0-9]+$ && ($existed == 0 || $existed == 1) && $pending == "$target".fzd-* ]] || return 1
    targets+=("$target")
    flags+=("$existed")
    backups+=("$backup")
    pendings+=("$pending")
  done <"$TX/journal"
  for ((i = ${#targets[@]} - 1; i >= 0; i--)); do
    target=${targets[i]}
    if [[ ${flags[i]} == 1 ]]; then
      [[ -f $TX/${backups[i]} && ! -L $TX/${backups[i]} ]] || return 1
      cp -p --remove-destination -- "$TX/${backups[i]}" "${pendings[i]}" || return 1
      mv -f -- "${pendings[i]}" "$target" || return 1
    else
      rm -f -- "$target" "${pendings[i]}" || return 1
    fi
  done
}

finish_transaction() {
  local result=$?
  trap - EXIT INT TERM HUP
  if ((COMMITTED == 0)); then
    warn 'Installation did not complete; restoring previous files'
    if ! rollback; then
      warn "Recovery requires inspection: $TX (lock retained)"
      return 1
    fi
  fi
  for pending in "${PENDING_PATHS[@]}"; do rm -f -- "$pending"; done
  : >"$TX/finished"
  # Keep originals and the journal for manual recovery; never overwrite backups.
  mkdir -p -- "$DATA/backups"
  mv -- "$TX" "$DATA/backups/${TX##*/}"
  rm -f -- "$LOCK/pid" "$LOCK/transaction"
  rmdir -- "$LOCK"
  return "$result"
}

recover_transaction() {
  local pid
  [[ -d $DATA/.install-lock && ! -L $DATA/.install-lock ]] || die 'No interrupted installation was found'
  IFS= read -r pid <"$DATA/.install-lock/pid" || pid=''
  if [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then die "Installer process $pid is still running; recovery refused"; fi
  IFS= read -r -d '' TX <"$DATA/.install-lock/transaction" || die 'Incomplete lock; inspect it before removing it'
  [[ $TX == "$DATA/"* && ${TX#"$DATA/"} =~ ^[.]transaction[.][a-zA-Z0-9]{8}$ && ! -L $TX ]] || die 'Invalid transaction directory'
  if [[ ! -d $TX && -f $DATA/backups/${TX##*/}/finished ]]; then
    rm -f -- "$DATA/.install-lock/pid" "$DATA/.install-lock/transaction"
    rmdir -- "$DATA/.install-lock"
    log 'Completed transaction found in backups; stale lock removed.'
    return 0
  fi
  [[ -d $TX ]] || die 'Transaction directory is missing; inspect the retained lock and backups'
  # A completed commit must survive a kill between manifest publication/cleanup.
  if [[ ! -e $TX/committed ]]; then rollback || die "Recovery failed; originals remain in $TX"; fi
  mkdir -p -- "$DATA/backups"
  mv -- "$TX" "$DATA/backups/${TX##*/}"
  rm -f -- "$DATA/.install-lock/pid" "$DATA/.install-lock/transaction"
  rmdir -- "$DATA/.install-lock"
  log 'Interrupted transaction recovered. Run installation again.'
}

save_target() {
  local target=$1 pending=$2 backup existed=0
  backup="backup-${JOURNAL_COUNT}"
  JOURNAL_COUNT=$((JOURNAL_COUNT + 1))
  [[ ! -L $target ]] || die "Refusing to replace a symbolic link: $target"
  if [[ -e $target ]]; then
    [[ -f $target ]] || die "Expected a regular file: $target"
    existed=1
    cp -p -- "$target" "$TX/$backup"
  fi
  printf '%s\0%s\0%s\0%s\0' "$target" "$existed" "$backup" "$pending" >>"$TX/journal"
}

write_file() {
  local source=$1 target=$2 mode=$3 pending parent
  parent=${target%/*}
  mkdir -p -- "$parent"
  pending=$(mktemp "$target.fzd-XXXXXXXX")
  PENDING_PATHS+=("$pending")
  save_target "$target" "$pending"
  if [[ -f $target ]]; then
    cp -p -- "$target" "$pending"
    cat -- "$source" >"$pending"
  else
    cat -- "$source" >"$pending"
    chmod "$mode" "$pending"
  fi
  mv -f -- "$pending" "$target"
}

delete_file() {
  local target=$1 pending
  pending=$(mktemp "$target.fzd-XXXXXXXX")
  PENDING_PATHS+=("$pending")
  save_target "$target" "$pending"
  rm -f -- "$target" "$pending"
}

owned_file() {
  case "$1" in
  "$PREFIX/bin/fzd" | "$PREFIX/bin/fzf" | "$DATA/integration.sh" | "$DATA/fzd.conf.example" | "$DATA/LICENSE.txt" | "$DATA/install.sh" | "$DATA/installer/dependencies.bash" | "$DATA/installer/lifecycle.bash") return 0 ;;
  *) return 1 ;;
  esac
}

load_manifest() {
  local kind path digest
  FILE_PATHS=()
  FILE_HASHES=()
  RC_PATHS=()
  RC_NEWLINES=()
  [[ -f $MANIFEST && ! -L $MANIFEST ]] || return 0
  while IFS= read -r -d '' kind; do
    if ! IFS= read -r -d '' path || ! IFS= read -r -d '' digest; then die 'Truncated install manifest'; fi
    case "$kind" in
    file)
      if ! owned_file "$path" || [[ ! $digest =~ ^[a-f0-9]{64}$ ]]; then die 'Invalid file in install manifest'; fi
      FILE_PATHS+=("$path")
      FILE_HASHES+=("$digest")
      ;;
    rc)
      [[ $path == /* && ($digest == 0 || $digest == 1) ]] || die 'Invalid shell path in install manifest'
      RC_PATHS+=("$path")
      RC_NEWLINES+=("$digest")
      ;;
    *) die 'Unknown install manifest record' ;;
    esac
  done <"$MANIFEST"
  [[ -z $kind ]] || die 'Truncated install manifest'
}

install_owned() {
  local source=$1 target=$2 mode=$3 index matched=0
  if [[ -e $target || -L $target ]]; then
    for index in "${!FILE_PATHS[@]}"; do
      if [[ ${FILE_PATHS[index]} == "$target" ]]; then
        hash_file "$target"
        [[ $REPLY == "${FILE_HASHES[index]}" || $ADOPT == 1 ]] || die "Locally modified file: $target. Back it up or explicitly use --adopt."
        matched=1
        break
      fi
    done
    ((matched || ADOPT)) || die "Unmanaged file exists: $target. Use --adopt to replace it with a retained backup."
  fi
  write_file "$source" "$target" "$mode"
  chmod "$mode" "$target"
  hash_file "$target"
  record file "$target" "$REPLY"
}

edit_rc() {
  local rc=$1 action=$2 line inside=0 count=0 found=0 newline ended_newline=1 index
  local original_newline=1 trailing_user=0
  local temporary="$TX/rc-content" block=''
  if [[ -L $rc ]]; then
    rc=$(
      readlink -f -- "$rc"
      printf '.'
    )
    rc=${rc%.}
    rc=${rc%$'\n'}
    [[ -f $rc ]] || die 'Shell configuration symlink must resolve to a regular file'
    [[ -O $rc ]] || die "Shell configuration target must belong to the installing user: $rc"
  fi
  printf '%s\0' "$rc" >>"$TX/rc-targets"
  : >"$temporary"
  if [[ -e $rc ]]; then
    [[ -f $rc ]] || die "Shell configuration is not a regular file: $rc"
    while true; do
      line=''
      if IFS= read -r line; then newline=1; else
        newline=0
        [[ -n $line ]] || break
      fi
      if [[ $line == '# >>> fzd init >>>' ]]; then
        ((inside == 0)) || die "Nested FZD block in $rc; repair it before installing"
        inside=1
        count=$((count + 1))
        found=1
      elif [[ $line == '# <<< fzd init <<<' ]]; then
        ((inside == 1)) || die "Unmatched FZD marker in $rc"
        inside=0
      elif ((inside)); then
        block+="$line"$'\n'
      else
        ((found == 0)) || trailing_user=1
        printf '%s' "$line" >>"$temporary"
        ((newline == 0)) || printf '\n' >>"$temporary"
        ended_newline=$newline
      fi
    done <"$rc"
    ((inside == 0 && count <= 1)) || die "Incomplete or duplicate FZD blocks in $rc"
  fi
  original_newline=$ended_newline
  for index in "${!RC_PATHS[@]}"; do
    [[ ${RC_PATHS[index]} != "$rc" ]] || original_newline=${RC_NEWLINES[index]}
  done
  if [[ $action == add ]]; then
    if [[ -s $temporary && $ended_newline == 0 ]]; then printf '\n' >>"$temporary"; fi
    {
      printf '# >>> fzd init >>>\n'
      printf '_FZD_INSTALL_BIN=%q\n' "$PREFIX/bin/fzd"
      # shellcheck disable=SC2016 # Preserve an existing override in the user's shell.
      printf 'if [ -z "${FZD_CONF_FILE:-}" ]; then FZD_CONF_FILE=%q; fi\nexport FZD_CONF_FILE\n' "$CFG"
      # shellcheck disable=SC2016 # Expansion belongs to the user's future shell.
      printf 'case "$PATH" in %q|%q:*) ;; *) export PATH=%q:"$PATH" ;; esac\n' "$PREFIX/bin" "$PREFIX/bin" "$PREFIX/bin"
      printf '[ ! -r %q ] || . %q\n' "$DATA/integration.sh" "$DATA/integration.sh"
      printf '# <<< fzd init <<<\n'
    } >>"$temporary"
    record rc "$rc" "$original_newline"
  elif ((found == 0)); then
    return 0
  elif [[ $block != *"$(printf %q "$DATA/integration.sh")"* ]]; then
    warn "Preserving shell block that now belongs to a different installation: $rc"
    return 0
  fi
  if [[ $action == remove && $original_newline == 0 && $trailing_user == 0 && -s $temporary ]]; then
    truncate -s -1 -- "$temporary"
  fi
  if [[ -f $rc ]] && cmp -s -- "$temporary" "$rc"; then return 0; fi
  write_file "$temporary" "$rc" 644
}

verify_installation() {
  local index
  [[ -x $PREFIX/bin/fzd && -r $DATA/integration.sh && -s $MANIFEST ]] || die 'Installation is incomplete; reinstall from the checkout'
  load_manifest
  for index in "${!FILE_PATHS[@]}"; do
    [[ -f ${FILE_PATHS[index]} && ! -L ${FILE_PATHS[index]} ]] || die "Installed file missing: ${FILE_PATHS[index]}"
    hash_file "${FILE_PATHS[index]}"
    [[ $REPLY == "${FILE_HASHES[index]}" ]] || die "Installed file changed: ${FILE_PATHS[index]}"
  done
  bash -n "$PREFIX/bin/fzd"
  [[ ! -e $CFG ]] || bash -n "$CFG" || die "Configuration has invalid Bash syntax: $CFG"
  log 'Verified installed files, dependency capabilities and configuration syntax (configuration was not executed).'
}

uninstall_files() {
  local index path
  load_manifest
  [[ -s $MANIFEST ]] || die 'No owned installation found; nothing removed'
  begin_transaction
  for path in "${RC_PATHS[@]}"; do edit_rc "$path" remove; done
  for index in "${!FILE_PATHS[@]}"; do
    path=${FILE_PATHS[index]}
    if [[ $path == "$PREFIX/bin/fzf" ]]; then
      log "Preserving user-local fzf dependency: $path"
      continue
    fi
    if [[ -f $path && ! -L $path ]]; then
      hash_file "$path"
      if [[ $REPLY == "${FILE_HASHES[index]}" ]]; then
        delete_file "$path"
      else
        warn "Preserving modified file: $path"
      fi
    elif [[ -e $path || -L $path ]]; then
      warn "Preserving replaced file: $path"
    fi
  done
  delete_file "$MANIFEST"
  : >"$TX/committed"
  COMMITTED=1
  log "Uninstalled owned files and integration blocks. Configuration, cache/state, backups and dependencies were preserved. Backups: $DATA/backups"
}
