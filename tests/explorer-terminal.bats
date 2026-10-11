#!/usr/bin/env bats
load helpers/common
load helpers/terminal
setup() { setup_terminal_fixture; }
teardown() { stop_terminal; }

@test "real terminal Alt arrows traverse local and global visits without replacing parent navigation" {
  mkdir -p "$FIXTURE_ROOT/child" "$FIXTURE_ROOT/needle-target"
  printf text >"$FIXTURE_ROOT/child/inside-local"
  printf text >"$FIXTURE_ROOT/needle-target/inside-global"
  start_terminal
  tmux -S "$SOCKET" send-keys -l child
  wait_screen '1/3'
  tmux -S "$SOCKET" send-keys Right
  wait_screen inside-local
  tmux -S "$SOCKET" send-keys M-Left
  wait_screen '> child/' '▌ child/'
  tmux -S "$SOCKET" send-keys M-Right
  wait_screen inside-local
  tmux -S "$SOCKET" send-keys C-f
  wait_screen 'global:/ >'
  tmux -S "$SOCKET" send-keys -l needle-target
  wait_screen '1/'
  tmux -S "$SOCKET" send-keys Right
  wait_screen inside-global
  tmux -S "$SOCKET" send-keys M-Left
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
  tmux -S "$SOCKET" send-keys -l child
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys Right
  wait_screen inside
  tmux -S "$SOCKET" send-keys Left
  wait_screen '> child/' '▌ child/'
  tmux -S "$SOCKET" send-keys M-h
  wait_screen 'Recent >'
  tmux -S "$SOCKET" send-keys -l child
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys Enter
  wait_screen inside
  tmux -S "$SOCKET" send-keys M-Left
  wait_screen '> child/' '▌ child/'
  tmux -S "$SOCKET" send-keys Enter
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_RESULT")" = "$FIXTURE_ROOT/child" ]
}
