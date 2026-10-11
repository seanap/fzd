# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # Shared fixture globals are consumed by Bats.
setup_terminal_fixture() {
  local host_path=$PATH
  setup_fixture
  export PATH=$host_path BASH_ENV=/dev/null
  export FZD_SCRIPT
  command -v tmux >/dev/null || skip 'tmux is not installed'
  command -v fzf >/dev/null || skip 'fzf is not installed'
  SOCKET="$BATS_TEST_TMPDIR/tmux.sock"
  export FZD_PTY_RESULT="$BATS_TEST_TMPDIR/result"
  export FZD_PTY_STATUS="$BATS_TEST_TMPDIR/status"
  export FZD_PTY_ERROR="$BATS_TEST_TMPDIR/stderr"
  export FZD_PTY_EDITOR="$BATS_TEST_TMPDIR/editor-arguments"
}
stop_terminal() {
  if [[ -n "${SOCKET:-}" ]]; then tmux -S "$SOCKET" kill-server 2>/dev/null || true; fi
}
start_terminal() {
  local command
  printf -v command 'exec bash --noprofile --norc %q' "$FZD_REPO/tests/helpers/pty-session"
  tmux -S "$SOCKET" -f /dev/null new-session -d -x 120 -y 32 -s fzd -c "$FIXTURE_ROOT" "$command"
  wait_screen '../'
}
wait_screen() {
  local attempt screen pattern
  for ((attempt = 0; attempt < 160; attempt++)); do
    screen=$(tmux -S "$SOCKET" capture-pane -p -t fzd:0.0)
    for pattern; do [[ "$screen" == *"$pattern"* ]] && return 0; done
    sleep 0.05
  done
  printf 'Expected screen text: %s\n%s\n' "$1" "$screen" >&2
  cat "$FZD_PTY_ERROR" >&2
  return 1
}
wait_file() {
  local attempt
  for ((attempt = 0; attempt < 160; attempt++)); do
    [[ -s "$1" ]] && return 0
    sleep 0.05
  done
  printf 'Timed out waiting for %s\n' "$1" >&2
  tmux -S "$SOCKET" capture-pane -p -t fzd:0.0 >&2
  cat "$FZD_PTY_ERROR" >&2
  return 1
}
