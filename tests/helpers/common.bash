# shellcheck disable=SC2034,SC2154 # Globals are shared with Bats test bodies/run.
setup_fixture() {
  bats_require_minimum_version 1.5.0
  FZD_REPO=$(cd -- "$BATS_TEST_DIRNAME/.." && pwd)
  FZD_SCRIPT="$FZD_REPO/fzd.sh"
  FZD_REAL_FD=$(command -v fd 2>/dev/null || command -v fdfind 2>/dev/null || true)
  FZD_REAL_LOCATE=$(command -v plocate 2>/dev/null || true)
  FZD_REAL_UPDATEDB=$(command -v updatedb.plocate 2>/dev/null || command -v updatedb 2>/dev/null || true)
  FZD_REAL_ZSH=$(command -v zsh 2>/dev/null || true)
  FIXTURE_ROOT="$BATS_TEST_TMPDIR/files"
  TEST_BIN="$BATS_TEST_TMPDIR/bin"
  UTILITY_BIN="$BATS_TEST_TMPDIR/utilities"
  mkdir -p "$FIXTURE_ROOT" "$TEST_BIN" "$UTILITY_BIN"
  export FZD_CONF_FILE="$BATS_TEST_TMPDIR/fzd.conf"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export XDG_CACHE_HOME="$BATS_TEST_TMPDIR/cache"
  export XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR/runtime"
  export FZD_GLOBAL_PATHS="$FIXTURE_ROOT"
  export FZD_GLOBAL_BACKEND=live FZD_GLOBAL_MINLEN=2
  export FZD_GLOBAL_MAXDEPTH=6 FZD_GLOBAL_MAXRESULTS=100
  export FZD_EXCLUDES=.git,node_modules FZD_GLOBAL_XEXCLUDES=proc,sys,dev,run
  export FZD_STUB_RESULTS="$BATS_TEST_TMPDIR/results"
  export FZD_STUB_LOG="$BATS_TEST_TMPDIR/backend-arguments"
  unset FZD_GLOBAL_ROOTS FZD_LOCATE_DBS FZD_TMP_DIR
  export FZD_GLOBAL_FULLPATH=0
  unset FZD_STATE_DIR FZD_CACHE_DIR FZD_COLOR_DIR FZD_COLOR_FILE
  unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE FZD_STUB_LOCATE_STATUS
  unset FZD_STUB_FD_STATUS FZD_STUB_ACTION FZD_STUB_SELECTION FZD_STUB_PLAN FZD_STUB_FZF_LOG
  : >"$FZD_STUB_RESULTS"
  for utility in bash sh env base64 tr find head sort awk sed grep cut dirname basename mktemp mkdir rm sleep cat ls file timeout ln wc chmod tail; do
    ln -s "$(command -v "$utility")" "$UTILITY_BIN/$utility"
  done
  ln -s "$FZD_REPO/tests/helpers/fzf-stub" "$TEST_BIN/fzf"
  export PATH="$TEST_BIN:$UTILITY_BIN"
}

plan_action() {
  printf '%s\t%s\n' "$1" "$(printf '%s' "$2" | base64 | tr -d '\n')" >>"$FZD_STUB_PLAN"
}

run_planned_session() {
  # shellcheck disable=SC2016 # Positional parameters belong to the child shell.
  run --separate-stderr bash -c 'cd -- "$1"; exec bash "$2"' _ "$FIXTURE_ROOT" "$FZD_SCRIPT"
}

use_fd_stub() {
  ln -s "$FZD_REPO/tests/helpers/backend-stub" "$TEST_BIN/fd"
}

use_locate_stub() {
  ln -s "$FZD_REPO/tests/helpers/backend-stub" "$TEST_BIN/plocate"
}

set_results() {
  printf '%s\0' "$@" >"$FZD_STUB_RESULTS"
}

assert_record_path() {
  local expected=$1 line encoded actual
  while IFS= read -r line; do
    encoded=${line%%$'\t'*}
    actual=$(
      printf '%s' "$encoded" | base64 -d
      printf '.'
    )
    actual=${actual%.}
    [[ "$actual" == "$expected" ]] && return 0
  done <<<"$output"
  printf 'Missing path: %q\nOutput: %s\n' "$expected" "$output" >&2
  return 1
}

assert_no_record_path() {
  ! assert_record_path "$1" 2>/dev/null
}
