#!/usr/bin/env bats
load helpers/common
load helpers/terminal
load helpers/trash
setup() { setup_terminal_fixture; }
teardown() { stop_terminal; }

@test "real terminal preserves inherited initial query and colors while reserving operation keys" {
  export FZF_DEFAULT_OPTS='--query=needle --multi --expect=ctrl-c --color=fg:7'
  printf payload >"$FIXTURE_ROOT/needle-file"
  printf payload >"$FIXTURE_ROOT/other"
  start_terminal '1/3'
  wait_screen '1/3'
  tmux -S "$SOCKET" send-keys C-c
  wait_screen 'COPY: needle-file'
  wait_screen '1/3'
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_STATUS")" -eq 130 ]
  [ ! -s "$FZD_PTY_RESULT" ]
}

@test "real terminal pickers ignore inherited queries and print-query without losing the local query" {
  stub_trash_backend
  rm "$TEST_BIN/fzf"
  export PATH="$TEST_BIN:$PATH"
  export FZF_DEFAULT_OPTS='--query=needle --print-query --tac'
  printf payload >"$FIXTURE_ROOT/needle-item"
  start_terminal '1/2'
  tmux -S "$SOCKET" send-keys M-h
  wait_screen 'Recent > '
  wait_screen '1/1'
  tmux -S "$SOCKET" send-keys Escape
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys F8
  wait_screen '2/2'
  tmux -S "$SOCKET" send-keys Enter
  wait_screen 'Trash cancelled'
  [ -f "$FIXTURE_ROOT/needle-item" ]
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
  [ ! -s "$FZD_PTY_RESULT" ]
}

@test "real terminal F8 requires explicit confirmation and keeps the application usable" {
  stub_trash_backend
  rm "$TEST_BIN/fzf"
  export PATH="$TEST_BIN:$PATH"
  printf payload >"$FIXTURE_ROOT/needle-trash"
  start_terminal
  tmux -S "$SOCKET" send-keys -l needle-trash
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys F8
  wait_screen 'Move to Trash: needle-trash'
  tmux -S "$SOCKET" send-keys Enter
  wait_screen 'Trash cancelled'
  [ -f "$FIXTURE_ROOT/needle-trash" ]
  tmux -S "$SOCKET" send-keys F8
  wait_screen 'Confirm >'
  tmux -S "$SOCKET" send-keys Down Enter
  wait_screen 'Moved to Trash: needle-trash'
  [ ! -e "$FIXTURE_ROOT/needle-trash" ]
  [ -f "$FZD_TEST_TRASH/needle-trash" ]
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
  [ ! -s "$FZD_PTY_RESULT" ]
}

@test "real terminal Delete still edits the query and F1 help works at 60 by 16" {
  printf payload >"$FIXTURE_ROOT/needle"
  printf payload >"$FIXTURE_ROOT/eedle-other"
  start_terminal
  tmux -S "$SOCKET" send-keys -l needle
  wait_screen '1/3'
  tmux -S "$SOCKET" send-keys C-a DC
  wait_screen '2/3'
  [ -f "$FIXTURE_ROOT/needle" ]
  tmux -S "$SOCKET" resize-window -t fzd:0 -x 60 -y 16
  tmux -S "$SOCKET" send-keys F1
  wait_screen 'Help >'
  tmux -S "$SOCKET" send-keys -N 20 Down
  wait_screen Other
  tmux -S "$SOCKET" send-keys Escape
  wait_screen '2/3'
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
}

@test "real terminal F2 preserves an unusual name unchanged and Ctrl-R renames and restores highlighting" {
  local old=$'needle é\t\n\377' new=$'renamed 雪\n'
  printf payload >"$FIXTURE_ROOT/$old"
  start_terminal
  tmux -S "$SOCKET" send-keys -l needle
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys F2
  wait_screen 'Rename >'
  tmux -S "$SOCKET" send-keys Enter
  wait_screen 'Name unchanged'
  [ -f "$FIXTURE_ROOT/$old" ]
  tmux -S "$SOCKET" send-keys C-r
  wait_screen 'Rename >'
  tmux -S "$SOCKET" send-keys C-u
  tmux -S "$SOCKET" send-keys -l 'renamed 雪\n'
  tmux -S "$SOCKET" send-keys Enter
  wait_screen 'Renamed: renamed 雪\n'
  wait_screen '> renamed 雪\n' '▌ renamed 雪\n'
  [ -f "$FIXTURE_ROOT/$new" ]
  [ ! -e "$FIXTURE_ROOT/$old" ]
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
  [ ! -s "$FZD_PTY_RESULT" ]
}

@test "real terminal Ctrl-N and F7 validate cancel and create directories with escaped names" {
  start_terminal
  tmux -S "$SOCKET" send-keys C-n
  wait_screen 'New directory >'
  tmux -S "$SOCKET" send-keys Enter
  wait_screen 'Name must be nonempty'
  tmux -S "$SOCKET" send-keys F7
  wait_screen 'New directory >'
  tmux -S "$SOCKET" send-keys -l 'new-folder\n'
  tmux -S "$SOCKET" send-keys Enter
  wait_screen 'Created: new-folder\n'
  wait_screen '> new-folder\n/' '▌ new-folder\n/'
  [ -d "$FIXTURE_ROOT/"$'new-folder\n' ]
  tmux -S "$SOCKET" send-keys C-n
  wait_screen 'New directory >'
  tmux -S "$SOCKET" send-keys Escape
  wait_screen 'Cancelled'
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
  [ ! -s "$FZD_PTY_RESULT" ]
}

@test "real terminal global F1 help restores the active global query" {
  mkdir -p "$FIXTURE_ROOT/needle-dir"
  printf payload >"$FIXTURE_ROOT/needle-dir/inside"
  start_terminal
  tmux -S "$SOCKET" send-keys C-f
  wait_screen 'global:/ >'
  tmux -S "$SOCKET" send-keys -l needle-dir
  wait_screen '1/'
  tmux -S "$SOCKET" send-keys F1
  wait_screen 'Help >'
  tmux -S "$SOCKET" send-keys Escape
  wait_screen 'global:/ > needle-dir'
  tmux -S "$SOCKET" send-keys Right
  wait_screen inside
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
}

clipboard_terminal_cycle() {
  local copy_key=$1 cut_key=$2 paste_key=$3
  printf payload >"$FIXTURE_ROOT/needle-item"
  mkdir -p "$FIXTURE_ROOT/dest-one" "$FIXTURE_ROOT/dest-two"
  start_terminal
  tmux -S "$SOCKET" send-keys -l needle
  wait_screen '1/4'
  tmux -S "$SOCKET" send-keys "$copy_key"
  wait_screen 'COPY: needle-item'
  tmux -S "$SOCKET" send-keys C-u
  tmux -S "$SOCKET" send-keys -l dest-one
  wait_screen '1/4'
  tmux -S "$SOCKET" send-keys Right
  wait_screen '1/1'
  tmux -S "$SOCKET" send-keys "$paste_key"
  wait_screen 'Copied: needle-item'
  tmux -S "$SOCKET" send-keys "$cut_key"
  wait_screen 'CUT: needle-item'
  tmux -S "$SOCKET" send-keys Left
  wait_screen '> dest-one/' '▌ dest-one/'
  tmux -S "$SOCKET" send-keys -l dest-two
  wait_screen '1/4'
  tmux -S "$SOCKET" send-keys Right
  wait_screen '1/1'
  tmux -S "$SOCKET" send-keys "$paste_key"
  wait_screen 'Moved: needle-item'
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FIXTURE_ROOT/dest-two/needle-item")" = payload ]
  [ ! -e "$FIXTURE_ROOT/dest-one/needle-item" ]
  [ "$(cat "$FIXTURE_ROOT/needle-item")" = payload ]
  [ ! -s "$FZD_PTY_RESULT" ]
}

@test "real terminal Ctrl-C Ctrl-X Ctrl-V copy cut and paste without aborting" {
  clipboard_terminal_cycle C-c C-x C-v
}

@test "real terminal Alt-C Alt-X Alt-V provide the same clipboard operations" {
  clipboard_terminal_cycle M-c M-x M-v
}

@test "real terminal can copy a selected global result and paste into the browsed directory" {
  printf payload >"$FIXTURE_ROOT/needle-global"
  mkdir -p "$FIXTURE_ROOT/dest"
  start_terminal
  tmux -S "$SOCKET" send-keys C-f
  wait_screen 'global:/ >'
  tmux -S "$SOCKET" send-keys -l needle-global
  wait_screen '1/'
  tmux -S "$SOCKET" send-keys C-c
  wait_screen 'COPY: needle-global'
  tmux -S "$SOCKET" send-keys -l dest
  wait_screen '1/3'
  tmux -S "$SOCKET" send-keys Right
  wait_screen '1/1'
  tmux -S "$SOCKET" send-keys C-v
  wait_screen 'Copied: needle-global'
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FIXTURE_ROOT/dest/needle-global")" = payload ]
}

@test "real terminal Alt arrows traverse local and global visits without replacing parent navigation" {
  mkdir -p "$FIXTURE_ROOT/child" "$FIXTURE_ROOT/needle-target"
  printf text >"$FIXTURE_ROOT/child/inside-local"
  printf text >"$FIXTURE_ROOT/needle-target/inside-global"
  start_terminal
  # Keep the long disposable fixture path visible for directory-frame checks.
  tmux -S "$SOCKET" resize-window -t fzd:0 -x 320 -y 32
  tmux -S "$SOCKET" send-keys -l child
  wait_screen '1/3'
  tmux -S "$SOCKET" send-keys Right
  wait_screen 'child/ >'
  wait_screen inside-local
  tmux -S "$SOCKET" send-keys M-Left
  wait_screen 'files/ >'
  wait_screen '> child/' '▌ child/'
  tmux -S "$SOCKET" send-keys M-Right
  wait_screen 'child/ >'
  wait_screen Forward
  wait_screen inside-local
  tmux -S "$SOCKET" send-keys C-f
  wait_screen 'global:/ >'
  tmux -S "$SOCKET" send-keys -l needle-target
  wait_screen '1/'
  tmux -S "$SOCKET" send-keys Right
  wait_screen '2/2'
  wait_screen 'needle-target/ >'
  wait_screen inside-global
  tmux -S "$SOCKET" send-keys M-Left
  wait_screen 'child/ >'
  wait_screen Back
  wait_screen inside-local
  tmux -S "$SOCKET" send-keys Up
  wait_screen '> ../' '▌ ../'
  tmux -S "$SOCKET" send-keys Enter
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_RESULT")" = "$FIXTURE_ROOT/child" ]
}

@test "real terminal F1 and recent-directory cancellation restore the filtered view" {
  printf text >"$FIXTURE_ROOT/needle-selected"
  printf text >"$FIXTURE_ROOT/other"
  start_terminal
  tmux -S "$SOCKET" send-keys -l needle
  wait_screen '1/3'
  tmux -S "$SOCKET" send-keys F1
  wait_screen 'Help >'
  wait_screen Navigation
  tmux -S "$SOCKET" send-keys F1
  wait_screen '1/3'
  tmux -S "$SOCKET" send-keys M-h
  wait_screen 'Recent >'
  tmux -S "$SOCKET" send-keys Escape
  wait_screen '1/3'
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_STATUS")" -eq 130 ]
  [ ! -s "$FZD_PTY_RESULT" ]
}

@test "real terminal recent picker navigates and session history includes that visit" {
  mkdir -p "$FIXTURE_ROOT/child"
  printf text >"$FIXTURE_ROOT/child/inside"
  start_terminal
  tmux -S "$SOCKET" resize-window -t fzd:0 -x 320 -y 32
  tmux -S "$SOCKET" send-keys -l child
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys Right
  wait_screen 'child/ >'
  wait_screen inside
  tmux -S "$SOCKET" send-keys Left
  wait_screen 'files/ >'
  wait_screen '> child/' '▌ child/'
  tmux -S "$SOCKET" send-keys M-h
  wait_screen 'Recent >'
  tmux -S "$SOCKET" send-keys -l child
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys Enter
  wait_screen 'child/ >'
  wait_screen inside
  tmux -S "$SOCKET" send-keys M-Left
  wait_screen 'files/ >'
  wait_screen '> child/' '▌ child/'
  tmux -S "$SOCKET" send-keys Enter
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_RESULT")" = "$FIXTURE_ROOT/child" ]
}
