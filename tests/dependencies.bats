#!/usr/bin/env bats
load helpers/installer

@test "Explorer dependency detection reports missing flock and maps distribution providers" {
  rm "$TEST_BIN/flock"
  install_fzd --deps none
  [ "$status" -ne 0 ]
  [[ "$output" == *'Missing prerequisites: flock'* ]]
  [ ! -e "$PREFIX/bin/fzd" ]
  run bash -euo pipefail -c '
    source "$1/installer/dependencies.bash"
    for PM in apt dnf pacman; do package_for flock; printf "%s:%s\n" "$PM" "$REPLY"; done
  ' _ "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'apt:util-linux\ndnf:util-linux-core\npacman:util-linux' ]
}

@test "Ubuntu and Debian apt transaction authenticates once and refreshes metadata once" {
  stub_managers
  dependency_shell apt
  [ "$status" -eq 0 ]
  [[ $(cat "$CALLS") == *'apt-get <install> <--no-install-recommends> <-y> <fzf> <tree>'* ]]
  [ "$(grep -c 'apt-get <update>' "$CALLS")" -eq 1 ]
  [ "$(grep -c 'sudo <-n> <-v>' "$CALLS")" -eq 1 ]
}

@test "Fedora dnf and Arch pacman use bounded deduplicated package transactions" {
  stub_managers
  dependency_shell dnf
  [ "$status" -eq 0 ]
  grep -q 'dnf <install> <-y> <fzf> <tree>' "$CALLS"
  dependency_shell pacman
  [ "$status" -eq 0 ]
  grep -q 'pacman <-S> <--needed> <--noconfirm> <fzf> <tree>' "$CALLS"
  ! grep -q '<update>' "$CALLS"
}

@test "interactive sudo authenticates normally while noninteractive authentication failures stop" {
  stub_managers
  dependency_shell apt 0
  [ "$status" -eq 0 ]
  grep -q 'sudo <-v>' "$CALLS"
  export SUDO_STATUS=1
  : >"$CALLS"
  dependency_shell apt 1
  [ "$status" -ne 0 ]
  [[ "$output" == *'sudo authentication is required'* ]]
  ! grep -q apt-get "$CALLS"
}

@test "dependency package failures are propagated without continuing installation" {
  stub_managers
  export PM_STATUS=42
  dependency_shell apt
  [ "$status" -ne 0 ]
  [[ "$output" == *'metadata refresh failed'* ]]
}

@test "dependency mappings and versions handle executable aliases and numerical comparison" {
  run bash -c 'source "$1/installer/dependencies.bash"; for PM in apt dnf pacman; do package_for fd; printf "%s:%s\n" "$PM" "$REPLY"; done; version_ge "0.100.0 (distro)" 0.44.0; ! version_ge 0.9.1 0.44.0; ! version_ge unknown 0.44.0' _ "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'apt:fd-find\ndnf:fd-find\npacman:fd' ]
}

@test "fd bat executable aliases and an existing configured editor prevent unnecessary installs" {
  ln -s /usr/bin/true "$TEST_BIN/fdfind"
  ln -s /usr/bin/true "$TEST_BIN/batcat"
  ln -s /usr/bin/true "$TEST_BIN/editor"
  rm "$TEST_BIN/micro"
  run bash -c 'set -euo pipefail; source "$1/installer/dependencies.bash"; DEPS=recommended; FZF_VERSION=""; EDITOR=editor; collect_missing; [[ ${#MISSING[@]} == 0 ]]' _ "$REPO"
  [ "$status" -eq 0 ]
}

@test "fzf capability detection ignores hostile inherited defaults and rejects unsupported bindings" {
  export FZF_DEFAULT_OPTS='--invalid-fzd-test-option' FZF_DEFAULT_OPTS_FILE="$HOME/missing-options"
  run bash -c 'set -euo pipefail; source "$1/installer/dependencies.bash"; check_fzf "$2"' _ "$REPO" "$REAL_FZF"
  [ "$status" -eq 0 ]
  rm "$TEST_BIN/fzf"
  printf '#!/bin/bash\n[[ $1 == --version ]] && { printf "0.65.2\\n"; exit; }; exit 2\n' >"$TEST_BIN/fzf"
  chmod +x "$TEST_BIN/fzf"
  run bash -c 'source "$1/installer/dependencies.bash"; check_fzf "$2"' _ "$REPO" "$TEST_BIN/fzf"
  [ "$status" -ne 0 ]
}

@test "distribution detection uses os-release rather than an unrelated package manager on PATH" {
  stub_managers
  run bash -c 'die() { exit 1; }; source "$1/installer/dependencies.bash"; detect_pm; printf "%s" "$PM"' _ "$REPO"
  [ "$status" -eq 0 ]
  # This assertion explicitly describes the host OS used by this test run.
  local ID='' ID_LIKE=''
  source /etc/os-release
  case " $ID $ID_LIKE " in
  *' ubuntu '* | *' debian '*) [ "$output" = apt ] ;;
  *' fedora '* | *' rhel '*) [ "$output" = dnf ] ;;
  *' arch '*) [ "$output" = pacman ] ;;
  *) skip 'host distribution has no automatic dependency manager mapping' ;;
  esac
}

@test "present but incompatible GNU serialization tools fail their capability checks" {
  local tool original
  for tool in base64 sort; do
    original=$(readlink -f "$TEST_BIN/$tool")
    rm "$TEST_BIN/$tool"
    printf '#!/bin/sh\nexit 2\n' >"$TEST_BIN/$tool"
    chmod +x "$TEST_BIN/$tool"
    run bash -c 'set -euo pipefail; die() { printf "%s\n" "$*"; exit 1; }; source "$1/installer/dependencies.bash"; DEPS=none; FZF_VERSION=""; ensure_dependencies' _ "$REPO"
    [ "$status" -ne 0 ]
    [[ "$output" == *"GNU-compatible $tool"* ]]
    rm "$TEST_BIN/$tool"
    ln -s "$original" "$TEST_BIN/$tool"
  done
}

@test "zoxide is required before installation and maps to each supported distribution package" {
  rm "$TEST_BIN/zoxide"
  install_fzd --deps none
  [ "$status" -ne 0 ]
  [[ "$output" == *'Missing prerequisites: zoxide'* ]]
  [ ! -e "$PREFIX/bin/fzd" ]
  run bash -ec 'source "$1/installer/dependencies.bash"; for PM in apt pacman dnf; do package_for zoxide; [[ $REPLY == zoxide ]]; done' _ "$REPO"
  [ "$status" -eq 0 ]
}

@test "source installer installs missing upstream zoxide through the native package manager" {
  local real_zoxide
  real_zoxide=$(readlink -f "$TEST_BIN/zoxide")
  export FZD_TEST_ZOXIDE=$real_zoxide
  rm "$TEST_BIN/zoxide"
  stub_managers
  local manager
  for manager in apt-get pacman dnf; do
    # Replace the stub's exit with a simulated successful package transaction.
    sed -i '/^exit /d' "$TEST_BIN/$manager"
    printf 'for arg; do [[ $arg != zoxide ]] || ln -s "$FZD_TEST_ZOXIDE" "$TEST_BIN/zoxide"; done\n' >>"$TEST_BIN/$manager"
  done
  install_fzd --deps required
  assert_installed
  grep -q '<zoxide>' "$CALLS"
  install_fzd --verify
  [ "$status" -eq 0 ]
}

@test "unsupported zoxide version is rejected before application files change" {
  rm "$TEST_BIN/zoxide"
  printf '#!/bin/sh\nprintf "zoxide 0.8.0\\n"\n' >"$TEST_BIN/zoxide"
  chmod +x "$TEST_BIN/zoxide"
  install_fzd --deps none
  [ "$status" -ne 0 ]
  [[ "$output" == *'zoxide >= 0.9.0 is required'* ]]
  [ ! -e "$PREFIX/bin/fzd" ]
}

@test "apt transactions are noninteractive and retain existing modified conffiles" {
  stub_managers
  sed -i '/^exit /i [[ ${DEBIAN_FRONTEND:-} == noninteractive ]] || exit 42' "$TEST_BIN/apt-get"
  dependency_shell apt
  [ "$status" -eq 0 ]
  grep -q '<Dpkg::Options::=--force-confdef>' "$CALLS"
  grep -q '<Dpkg::Options::=--force-confold>' "$CALLS"
}

@test "required optional and retry transactions share one APT metadata refresh" {
  stub_managers
  run bash -euc 'source "$1/installer/dependencies.bash"; warn() { echo "$*"; }; log() { :; }; PM=apt; NONINTERACTIVE=1; install_packages plocate; install_packages eza chafa; install_packages tree' _ "$REPO"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'apt-get <update>' "$CALLS")" -eq 1 ]
  [ "$(grep -c 'apt-get <install>' "$CALLS")" -eq 3 ]
}
