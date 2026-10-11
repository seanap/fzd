#!/usr/bin/env bats
load helpers/installer

profile_install() {
  [[ -n $REAL_BWRAP ]] || skip 'distribution profile isolation needs bubblewrap/user namespaces'
  local id=$1 expected=$2 tool
  printf 'ID=%s\n' "$id" >"$BATS_TEST_TMPDIR/os-release"
  export FZD_TEST_FIND=$(readlink -f "$TEST_BIN/find")
  rm "$TEST_BIN/find"
  stub_managers
  cat >"$TEST_BIN/package-stub" <<'STUB'
#!/bin/bash
printf '%s' "${0##*/}" >>"$CALLS"
printf ' <%s>' "$@" >>"$CALLS"
printf '\n' >>"$CALLS"
if [[ $1 == install || $1 == -S ]]; then ln -s "$FZD_TEST_FIND" "$TEST_BIN/find"; fi
STUB
  chmod +x "$TEST_BIN/package-stub"
  for tool in apt-get dnf pacman; do
    rm "$TEST_BIN/$tool"
    ln -s "$TEST_BIN/package-stub" "$TEST_BIN/$tool"
  done
  # Ubuntu userspace with simulated distribution metadata/manager commands.
  # The entire host, including the real home, is read-only; only this fixture
  # can be written. Network/PID isolation prevents accidental external effects.
  run "$REAL_BWRAP" --unshare-user --unshare-pid --unshare-net --die-with-parent \
    --ro-bind / / --bind "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" \
    --ro-bind "$BATS_TEST_TMPDIR/os-release" /etc/os-release --proc /proc --dev /dev \
    -- bash "$REPO/install.sh" --noninteractive --deps required --shell none --no-config
  assert_installed
  grep -q "$expected" "$CALLS"
  [ ! -e "$HOME/.bashrc" ]
}

@test "isolated Ubuntu profile detects apt installs missing findutils and completes" {
  profile_install ubuntu 'apt-get <install> <--no-install-recommends> <-y> <findutils>'
}

@test "isolated Debian profile detects apt installs missing findutils and completes" {
  profile_install debian 'apt-get <install> <--no-install-recommends> <-y> <findutils>'
}

@test "isolated Fedora profile detects dnf installs missing findutils and completes" {
  profile_install fedora 'dnf <install> <-y> <findutils>'
}

@test "isolated Arch profile detects pacman installs missing findutils and completes" {
  profile_install arch 'pacman <-S> <--needed> <--noconfirm> <findutils>'
}
