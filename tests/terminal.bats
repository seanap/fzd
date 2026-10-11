#!/usr/bin/env bats
load helpers/common
load helpers/terminal
setup() { setup_terminal_fixture; }
teardown() { stop_terminal; }

@test "real terminal Right Left and Enter restore the child selection" {
  mkdir -p "$FIXTURE_ROOT/child"
  printf text >"$FIXTURE_ROOT/child/inside-only.txt"
  start_terminal
  tmux -S "$SOCKET" send-keys -l child
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys Right
  wait_screen '2/2'
  wait_screen inside-only.txt
  tmux -S "$SOCKET" send-keys Left
  # fzf changed its default pointer; selection behavior must hold with either.
  wait_screen '> child/' '▌ child/'
  tmux -S "$SOCKET" send-keys Enter
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_STATUS")" -eq 0 ]
  [ "$(cat "$FZD_PTY_RESULT")" = "$FIXTURE_ROOT/child" ]
  [ "$(tmux -S "$SOCKET" display-message -p -t fzd:0.0 '#{alternate_on}')" -eq 0 ]
}

check_global_navigation() {
  mkdir -p "$FIXTURE_ROOT/needle-target"
  printf text >"$FIXTURE_ROOT/needle-target/global-inside.txt"
  if [[ "${1:-}" == locate || "${1:-}" == broken-locate ]]; then
    private_locate
    rm -f -- "$TEST_BIN/fzf"
    export PATH="$TEST_BIN:$PATH"
    if [[ "$1" == broken-locate ]]; then
      export FZD_LOCATE_DBS="$BATS_TEST_TMPDIR/missing.db" FZD_GLOBAL_BACKEND=auto
    fi
  fi
  start_terminal
  tmux -S "$SOCKET" send-keys C-f
  wait_screen 'global:/ >'
  tmux -S "$SOCKET" send-keys -l needle-target
  wait_screen '1/'
  wait_screen 'needle-target/'
  tmux -S "$SOCKET" send-keys Right
  wait_screen '2/2'
  wait_screen global-inside.txt
  tmux -S "$SOCKET" send-keys Enter
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_STATUS")" -eq 0 ]
  [ "$(cat "$FZD_PTY_RESULT")" = "$FIXTURE_ROOT/needle-target" ]
}

@test "real terminal Ctrl-F cache search Right and Enter keep their controls" {
  export FZD_GLOBAL_BACKEND=cache
  check_global_navigation
}

@test "real terminal Ctrl-F live search Right and Enter keep their controls" {
  export FZD_GLOBAL_BACKEND=live
  check_global_navigation
}

@test "real terminal Ctrl-F searches a private locate database" {
  check_global_navigation locate
}

@test "real terminal auto search survives a broken locate database" {
  check_global_navigation broken-locate
}

@test "real terminal Enter opens exact unusual filename then Esc returns 130" {
  local path="$FIXTURE_ROOT/"$'needle \'quote $(printf BAD)\tlast\n'
  # Exercise both pathname interpolation sites in the real fzf callbacks.
  export FZD_TMP_DIR="$BATS_TEST_TMPDIR/"$'tmp \'quote $(printf BAD)\n'
  ln -s "$FZD_SCRIPT" "$TEST_BIN/fzd 'quoted.sh"
  export FZD_SCRIPT="$TEST_BIN/fzd 'quoted.sh"
  printf 'preview-unique-text\n' >"$path"
  export EDITOR="$TEST_BIN/editor"
  cat >"$EDITOR" <<'SH'
#!/bin/sh
tmux display-message -p -t "$TMUX_PANE" '#{alternate_on}' >"$FZD_PTY_EDITOR.screen"
printf '%s\0' "$@" >"$FZD_PTY_EDITOR"
SH
  chmod +x "$EDITOR"
  start_terminal
  tmux -S "$SOCKET" send-keys -l needle
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys Enter
  wait_file "$FZD_PTY_EDITOR"
  local expected actual
  expected=$(printf '%s\0' -- "$path" | base64 | tr -d '\n')
  actual=$(base64 <"$FZD_PTY_EDITOR" | tr -d '\n')
  [ "$actual" = "$expected" ]
  [ "$(cat "$FZD_PTY_EDITOR.screen")" -eq 0 ]
  wait_screen '2/2'
  tmux -S "$SOCKET" send-keys Escape
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_STATUS")" -eq 130 ]
  [ ! -s "$FZD_PTY_RESULT" ]
  [ "$(tmux -S "$SOCKET" display-message -p -t fzd:0.0 '#{alternate_on}')" -eq 0 ]
}

@test "real terminal remains usable after resizing to 60 columns and 16 rows" {
  start_terminal
  tmux -S "$SOCKET" resize-window -t fzd:0 -x 60 -y 16
  wait_screen '../'
  tmux -S "$SOCKET" send-keys Enter
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_RESULT")" = "$FIXTURE_ROOT" ]
}

@test "real terminal Ctrl-C leaves no control files" {
  start_terminal
  tmux -S "$SOCKET" send-keys C-c
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_STATUS")" -eq 130 ]
  run find "$XDG_RUNTIME_DIR" -type f
  [ -z "$output" ]
  [ "$(tmux -S "$SOCKET" display-message -p -t fzd:0.0 '#{alternate_on}')" -eq 0 ]
}

@test "real fzf completes a delayed action write before navigation resumes" {
  mkdir -p "$FIXTURE_ROOT/child"
  printf text >"$FIXTURE_ROOT/child/first"
  printf text >"$FIXTURE_ROOT/child/second"
  export SHELL="$TEST_BIN/delayed-shell"
  cat >"$SHELL" <<'SH'
#!/bin/sh
case "$*" in *'echo A:RIGHT:'*) sleep 0.3 ;; esac
exec /bin/sh "$@"
SH
  chmod +x "$SHELL"
  start_terminal
  tmux -S "$SOCKET" send-keys -l child
  wait_screen '1/2'
  tmux -S "$SOCKET" send-keys Right
  wait_screen '3/3'
  tmux -S "$SOCKET" send-keys Enter
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_RESULT")" = "$FIXTURE_ROOT/child" ]
  [ "$(cat "$FZD_PTY_STATUS")" -eq 0 ]
}

@test "real terminal works without an alternate-screen restore capability" {
  printf '#!/bin/sh\nexit 1\n' >"$TEST_BIN/tput"
  chmod +x "$TEST_BIN/tput"
  rm -f -- "$TEST_BIN/fzf"
  export PATH="$TEST_BIN:$PATH"
  start_terminal
  tmux -S "$SOCKET" send-keys Enter
  wait_file "$FZD_PTY_STATUS"
  [ "$(cat "$FZD_PTY_STATUS")" -eq 0 ]
  [ "$(cat "$FZD_PTY_RESULT")" = "$FIXTURE_ROOT" ]
  [ "$(tmux -S "$SOCKET" display-message -p -t fzd:0.0 '#{alternate_on}')" -eq 0 ]
}
