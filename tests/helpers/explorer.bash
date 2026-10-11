# shellcheck shell=bash
# shellcheck disable=SC2034 # Fixture globals are consumed by sourced functions.
setup_explorer_fixture() {
  local bwrap
  bwrap=$(command -v bwrap || true)
  setup_fixture
  local tool
  for tool in cp stat rmdir readlink cmp; do
    ln -s "/usr/bin/$tool" "$UTILITY_BIN/$tool"
  done
  export FZD_TEST_HELPER="$FZD_REPO/tests/helpers/explorer.bash"
  export FZD_TEST_ROOT="$FIXTURE_ROOT" FZD_TEST_REPO="$FZD_REPO" FZD_SCRIPT
  export FZD_TEST_BWRAP=$bwrap
}
init_operations() {
  init_explorer
  # shellcheck source=/dev/null
  source "$FZD_TEST_REPO/lib/operations.bash"
  # shellcheck source=/dev/null
  source "$FZD_TEST_REPO/lib/ui.bash"
}
init_explorer() {
  # shellcheck source=/dev/null
  source "$FZD_SCRIPT"
  # shellcheck source=/dev/null
  source "$FZD_TEST_REPO/lib/state.bash"
  _fzd_paths
  _fzd_init
  FZD_TEMP_FILES=()
  CUR=$FZD_TEST_ROOT
  _history_init
}
