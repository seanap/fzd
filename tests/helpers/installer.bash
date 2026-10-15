# shellcheck disable=SC2034,SC2154 # Fixture globals are consumed by Bats bodies.
setup() {
  bats_require_minimum_version 1.5.0
  REPO=$(cd -- "$BATS_TEST_DIRNAME/.." && pwd)
  export HOME="$BATS_TEST_TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/config" XDG_STATE_HOME="$HOME/state" XDG_CACHE_HOME="$HOME/cache"
  export XDG_RUNTIME_DIR="$HOME/runtime"
  export BASH_ENV=/dev/null ENV=/dev/null
  export TEST_BIN="$BATS_TEST_TMPDIR/bin" CALLS="$BATS_TEST_TMPDIR/calls"
  HOST_PATH=$PATH
  REAL_BASH=$(command -v bash)
  REAL_ZSH=$(command -v zsh || true)
  REAL_TMUX=$(command -v tmux || true)
  REAL_BWRAP=$(command -v bwrap || true)
  REAL_FZF=$(command -v fzf)
  FZD_REAL_MV=$(command -v mv)
  export FZD_REAL_MV
  PREFIX="$HOME/.local"
  DATA="$PREFIX/share/fzd"
  mkdir -p "$HOME" "$TEST_BIN"
  unset FZD_CONF_FILE FZD_BIN FZD_GLOBAL_ROOTS ZDOTDIR EDITOR VISUAL
  unset FZD_STATE_DIR FZD_CACHE_DIR FZD_TMP_DIR
  unset FZF_DEFAULT_OPTS FZF_DEFAULT_OPTS_FILE
  unset FZD_FAULT FZD_FAULT_TARGET FZD_FAULT_MARKER
  # No real package manager or sudo is reachable in this fixture.
  local tool
  export _ZO_DATA_DIR="$BATS_TEST_TMPDIR/zoxide"
  unset _ZO_EXCLUDE_DIRS _ZO_RESOLVE_SYMLINKS _ZO_MAXAGE
  for tool in zoxide bash sh env cat base64 sort mktemp install sha256sum readlink truncate find file tree micro cp mv rm rmdir mkdir chmod cmp tail uname tar gzip curl sleep kill wc grep head ln touch date tr awk sed cut ls timeout basename dirname realpath flock stat; do
    ln -s "$(command -v "$tool")" "$TEST_BIN/$tool"
  done
  ln -s "$REAL_FZF" "$TEST_BIN/fzf"
  export PATH="$TEST_BIN"
}

teardown() {
  if [[ -n ${INSTALL_SOCKET:-} ]]; then "$REAL_TMUX" -S "$INSTALL_SOCKET" kill-server 2>/dev/null || true; fi
}

install_fzd() { run bash "$REPO/install.sh" --noninteractive "$@"; }
assert_installed() {
  [ "$status" -eq 0 ]
  [ -x "$PREFIX/bin/fzd" ]
  cmp "$REPO/fzd.sh" "$PREFIX/bin/fzd"
}
dependency_shell() {
  # Function-level package-manager tests use real installer logic and stubs.
  run bash -c 'set -euo pipefail; die() { printf "%s\n" "$*"; exit 1; }; log() { :; }; source "$1/installer/dependencies.bash"; PM=$2; NONINTERACTIVE=$3; install_packages fzf fzf tree' _ "$REPO" "$1" "${2:-1}"
}

inject_fault() {
  rm "$TEST_BIN/mv"
  ln -s "$REPO/tests/helpers/installer-mv-stub" "$TEST_BIN/mv"
  export FZD_FAULT=$1 FZD_FAULT_TARGET="$HOME/.zshrc" FZD_FAULT_MARKER="$HOME/fault-fired"
}
stub_managers() {
  local tool
  for tool in apt-get dnf pacman; do
    # shellcheck disable=SC2016 # These variables belong to the generated stub.
    printf '#!/bin/bash\nprintf "%%s" "${0##*/}" >>"$CALLS"\nprintf " <%%s>" "$@" >>"$CALLS"\nprintf "\\n" >>"$CALLS"\nexit "${PM_STATUS:-0}"\n' >"$TEST_BIN/$tool"
    chmod +x "$TEST_BIN/$tool"
  done
  cat >"$TEST_BIN/sudo" <<'STUB'
#!/bin/bash
printf 'sudo' >>"$CALLS"
printf ' <%s>' "$@" >>"$CALLS"
printf '\n' >>"$CALLS"
[[ ${SUDO_STATUS:-0} == 0 ]] || exit "$SUDO_STATUS"
[[ ${1:-} != -n ]] || shift
[[ ${1:-} != -v ]] || exit 0
exec "$@"
STUB
  chmod +x "$TEST_BIN/sudo"
}
