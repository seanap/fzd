#!/usr/bin/env bats
setup() {
  bats_require_minimum_version 1.5.0
  REPO=$(cd -- "$BATS_TEST_DIRNAME/.." && pwd)
}

@test "real fzf preview pane receives eza Nerd glyphs ANSI colors and exclusions" {
  command -v eza >/dev/null || skip 'eza unavailable for native PTY preview check'
  run python3 "$REPO/tests/helpers/integration-pty.py" "$REPO" "$BATS_TEST_TMPDIR/pty" icons
  [ "$status" -eq 0 ]
}

@test "Omarchy interactive launcher keeps selected directory after real fzf exits" {
  run python3 "$REPO/tests/helpers/integration-pty.py" "$REPO" "$BATS_TEST_TMPDIR/pty" launcher
  [ "$status" -eq 0 ]
}

@test "real terminal clipboard and Lazygit actions return to local and global query sessions" {
  run python3 "$REPO/tests/helpers/integration-pty.py" "$REPO" "$BATS_TEST_TMPDIR/pty" actions
  [ "$status" -eq 0 ]
}
