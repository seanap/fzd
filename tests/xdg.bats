#!/usr/bin/env bats
load helpers/common
setup() { setup_fixture; }

@test "absolute XDG homes keep configuration state cache and temporary storage separate" {
  export XDG_DATA_HOME="$BATS_TEST_TMPDIR/custom-data"
  run bash -ec '
    source "$1"; _fzd_paths; _fzd_init --_global_list
    [[ $FZD_STATE_DIR == "$XDG_STATE_HOME/fzd" && $FZD_CACHE_DIR == "$XDG_CACHE_HOME/fzd" ]]
    [[ $FZD_TMP_DIR == "$XDG_RUNTIME_DIR/fzd" && $TMPDIR == "$FZD_TMP_DIR/"* ]]
    [[ $(stat -c %a "$TMPDIR") == 700 ]]
    rmdir "$TMPDIR"
  ' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_DATA_HOME" ]
}

@test "relative XDG homes use freedesktop defaults without accessing relative paths" {
  export HOME="$BATS_TEST_TMPDIR/uncreated-home"
  run bash -ec '
    source "$1"
    XDG_CONFIG_HOME=relative; XDG_DATA_HOME=relative; XDG_STATE_HOME=relative; XDG_CACHE_HOME=relative
    unset FZD_CONF_FILE; _fzd_paths
    [[ $XDG_CONFIG_HOME == "$HOME/.config" && $XDG_DATA_HOME == "$HOME/.local/share" ]]
    [[ $XDG_STATE_HOME == "$HOME/.local/state" && $XDG_CACHE_HOME == "$HOME/.cache" ]]
  ' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$HOME" ]
}

@test "XDG traversal and relative FZD overrides fail before touching their targets" {
  local variable
  for variable in XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME; do
    run env "$variable=$BATS_TEST_TMPDIR/../escape" bash "$FZD_SCRIPT" --_global_list --q ''
    [ "$status" -ne 0 ]
    [[ "$output" == *'unsafe .. components'* ]]
  done
  for variable in FZD_STATE_DIR FZD_CACHE_DIR FZD_TMP_DIR FZD_CONF_FILE; do
    run env "$variable=relative" bash "$FZD_SCRIPT" --_global_list --q ''
    [ "$status" -ne 0 ]
    [[ "$output" == *'must be absolute'* ]]
  done
}

@test "missing relative unsafe and non-directory runtime paths fall back to cache" {
  local runtime
  printf file >"$BATS_TEST_TMPDIR/not-a-directory"
  for runtime in '' relative "$BATS_TEST_TMPDIR/missing" "$BATS_TEST_TMPDIR/not-a-directory" /tmp "$BATS_TEST_TMPDIR/../escape"; do
    run env XDG_RUNTIME_DIR="$runtime" bash -ec '
      source "$1"; _fzd_paths; _fzd_init --_global_list
      [[ $FZD_TMP_DIR == "$XDG_CACHE_HOME/fzd/tmp" && $(stat -c %a "$TMPDIR") == 700 ]]
      rmdir "$TMPDIR"
    ' _ "$FZD_SCRIPT"
    [ "$status" -eq 0 ]
  done
  [ ! -e "$BATS_TEST_TMPDIR/missing" ]
}

@test "runtime permissions are checked without repairing or changing user directories" {
  local mode
  for mode in 755 770 777 000; do
    chmod "$mode" "$XDG_RUNTIME_DIR"
    run bash -ec '
      source "$1"; _fzd_paths; _fzd_init --_global_list
      [[ $FZD_TMP_DIR == "$XDG_CACHE_HOME/fzd/tmp" ]]
      rmdir "$TMPDIR"
    ' _ "$FZD_SCRIPT"
    [ "$status" -eq 0 ]
    [ "$((8#$(stat -c %a "$XDG_RUNTIME_DIR")))" -eq "$((8#$mode))" ]
  done
  chmod 700 "$XDG_RUNTIME_DIR"
}

@test "runtime symlinks fall back while explicit temporary symlinks are rejected" {
  mv "$XDG_RUNTIME_DIR" "$BATS_TEST_TMPDIR/real-runtime"
  ln -s "$BATS_TEST_TMPDIR/real-runtime" "$XDG_RUNTIME_DIR"
  run bash "$FZD_SCRIPT" --_global_list --q ''
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/real-runtime/fzd" ]
  export FZD_TMP_DIR="$XDG_RUNTIME_DIR/custom"
  run bash "$FZD_SCRIPT" --_global_list --q ''
  [ "$status" -ne 0 ]
  [[ "$output" == *'unsafe temporary directory symlink'* ]]
  [ ! -e "$BATS_TEST_TMPDIR/real-runtime/custom" ]
}

@test "temporary overrides create isolated private sessions retaining the user's parent mode" {
  export FZD_TMP_DIR="$BATS_TEST_TMPDIR/custom-temp"
  mkdir -m 755 "$FZD_TMP_DIR"
  run bash -ec '
    source "$1"; _fzd_paths; _fzd_init --_global_list
    first=$TMPDIR; _fzd_temp_init --_global_list
    [[ $first != "$TMPDIR" && $(stat -c %a "$first") == 700 && $(stat -c %a "$TMPDIR") == 700 ]]
    rmdir "$first" "$TMPDIR"
  ' _ "$FZD_SCRIPT"
  [ "$status" -eq 0 ]
  [ "$(stat -c %a "$FZD_TMP_DIR")" = 755 ]
  [ ! -e "$XDG_RUNTIME_DIR/fzd" ]
}

@test "unsafe shared temporary override directories and dangling symlinks are rejected" {
  export FZD_TMP_DIR="$BATS_TEST_TMPDIR/shared-temp"
  mkdir -m 777 "$FZD_TMP_DIR"
  run bash "$FZD_SCRIPT" --_global_list --q ''
  [ "$status" -ne 0 ]
  [[ "$output" == *'writable by other users'* ]]
  rm -r "$FZD_TMP_DIR"
  ln -s "$BATS_TEST_TMPDIR/missing" "$FZD_TMP_DIR"
  run bash "$FZD_SCRIPT" --_global_list --q ''
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/missing" ]
}

@test "success failure and signal cleanup remove session directories with their temporary files" {
  run bash "$FZD_SCRIPT" --_global_list --q ''
  [ "$status" -eq 0 ]
  run find "$XDG_RUNTIME_DIR" -name 'session.*'
  [ -z "$output" ]
  export FZD_GLOBAL_BACKEND=invalid
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -ne 0 ]
  run find "$XDG_RUNTIME_DIR" -name 'session.*'
  [ -z "$output" ]
  printf '#!/bin/sh\nkill -TERM "$PPID"\nsleep 0.05\nexit 2\n' >"$TEST_BIN/plocate"
  chmod +x "$TEST_BIN/plocate"
  export FZD_GLOBAL_BACKEND=locate
  run bash "$FZD_SCRIPT" --_global_list --q needle
  [ "$status" -eq 143 ]
  run find "$XDG_RUNTIME_DIR" -name 'session.*'
  [ -z "$output" ]
}

@test "unsafe runtime child paths fall back instead of following symlinks or shared directories" {
  mkdir "$BATS_TEST_TMPDIR/outside"
  ln -s "$BATS_TEST_TMPDIR/outside" "$XDG_RUNTIME_DIR/fzd"
  run bash "$FZD_SCRIPT" --_global_list --q ''
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/outside/session" ]
  rm "$XDG_RUNTIME_DIR/fzd"
  mkdir -m 777 "$XDG_RUNTIME_DIR/fzd"
  run bash "$FZD_SCRIPT" --_global_list --q ''
  [ "$status" -eq 0 ]
  run find "$XDG_RUNTIME_DIR/fzd" -mindepth 1
  [ -z "$output" ]
}
