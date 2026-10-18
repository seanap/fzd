# shellcheck shell=bash
# shellcheck disable=SC2034 # Fixture globals are consumed by sourced functions.
setup_explorer_fixture() {
  local bwrap
  bwrap=$(command -v bwrap || true)
  setup_fixture
  ln -s /usr/bin/readlink "$UTILITY_BIN/readlink"
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
  # Sourcing inside a function makes the application's declaration local.
  declare -gA LAST_CHILD=()
  # shellcheck source=/dev/null
  source "$FZD_TEST_REPO/lib/state.bash"
  _fzd_paths
  _fzd_init
  FZD_TEMP_FILES=()
  CUR=$FZD_TEST_ROOT
  _history_init
}
