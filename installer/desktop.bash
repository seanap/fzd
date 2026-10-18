# shellcheck shell=bash
# Omarchy's helper has no ownership checks and fixed HOME paths. Stage its
# output privately, then publish through FZD's normal transactional ownership.
_desktop_prepare() {
  local target=$XDG_DATA_HOME/applications/FZD.desktop index owned=0 previous='' exec_line quoted argument
  for index in "${!LAUNCHER_PATHS[@]}"; do
    if [[ ${LAUNCHER_PATHS[index]} == "$target" ]]; then
      owned=1
      previous=${LAUNCHER_HASHES[index]}
    fi
    if [[ ${LAUNCHER_PATHS[index]} != "$target" || $OMARCHY_LAUNCHER == none ]]; then record launcher "${LAUNCHER_PATHS[index]}" "${LAUNCHER_HASHES[index]}"; fi
  done
  [[ $OMARCHY_LAUNCHER != none ]] || return 0
  # Retain previous ownership on any optional setup failure.
  _desktop_keep() { [[ $owned == 0 ]] || record launcher "$target" "$previous"; }
  if ! have omarchy-tui-install || ! have omarchy-launch-editor; then
    warn 'Omarchy launcher skipped: current Omarchy utilities are unavailable'
    _desktop_keep
    return 0
  fi
  if [[ $SHELL_TARGET == zsh || ${SHELL:-/bin/bash} == */zsh ]]; then
    warn 'Omarchy launcher currently supports interactive Bash; use lf from your zsh terminal'
    _desktop_keep
    return 0
  fi
  if [[ -e $target || -L $target ]]; then
    if [[ $owned == 0 || ! -f $target || -L $target ]]; then
      warn "Preserving existing launcher: $target"
      _desktop_keep
      return 0
    fi
    hash_file "$target"
    [[ $REPLY == "$previous" ]] || {
      warn "Preserving modified launcher: $target"
      _desktop_keep
      return 0
    }
  fi
  # Desktop Exec has its own quoting rules. Reject controls; quote all arguments,
  # including percent field codes and literal shell metacharacters.
  exec_line=''
  for argument in bash --rcfile "$DATA/launcher.bash" -i; do
    [[ $argument != *[$'\001'-$'\037'$'\177']* ]] || {
      warn 'Launcher skipped: path contains control characters'
      _desktop_keep
      return 0
    }
    quoted=${argument//\\/\\\\}
    quoted=${quoted//\"/\\\"}
    quoted=${quoted//\`/\\\`}
    quoted=${quoted//\$/\\\$}
    quoted=${quoted//%/%%}
    # Desktop string escaping is decoded before Exec argument quoting.
    quoted=${quoted//\\/\\\\}
    exec_line+="${exec_line:+ }\"$quoted\""
  done
  mkdir -m 700 "$TX/desktop-home"
  if ! HOME=$TX/desktop-home omarchy-tui-install FZD "$exec_line" "$OMARCHY_LAUNCHER" utilities-terminal; then
    warn 'Omarchy launcher helper failed; core installation remains usable'
    _desktop_keep
    return 0
  fi
  local staged=$TX/desktop-home/.local/share/applications/FZD.desktop
  [[ -f $staged && ! -L $staged ]] || {
    warn 'Omarchy helper produced no launcher'
    _desktop_keep
    return 0
  }
  printf '%s\0' "$target" >>"$TX/rc-targets"
  write_file "$staged" "$target" 644
  hash_file "$target"
  record launcher "$target" "$REPLY"
  log "Registered FZD launcher ($OMARCHY_LAUNCHER); exits into an interactive Bash in the selected directory"
}
