#!/usr/bin/env bats
load helpers/installer

apt_install_fzd() {
  [[ -n $REAL_BWRAP ]] || skip 'APT profile isolation needs bubblewrap/user namespaces'
  local os_release
  os_release=$(readlink -f /etc/os-release)
  printf 'ID=ubuntu\n' >"$BATS_TEST_TMPDIR/os-release"
  # Force the unavailable-APT-package case on every validation distribution.
  # Real package managers remain unreachable; only this fixture is writable.
  run "$REAL_BWRAP" --unshare-user --unshare-pid --unshare-net --die-with-parent \
    --ro-bind / / --bind "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" \
    --ro-bind "$BATS_TEST_TMPDIR/os-release" "$os_release" --proc /proc --dev /dev \
    -- bash "$REPO/install.sh" --noninteractive --deps none "$@"
}

glow_fallback_tools() {
  stub_managers
  local tool
  for tool in eza fd bat chafa wl-copy; do
    printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/$tool"
    chmod +x "$TEST_BIN/$tool"
  done
  mkdir -p "$XDG_DATA_HOME/blesh" "$HOME/.zsh/zsh-autosuggestions"
  printf ':\n' >"$XDG_DATA_HOME/blesh/ble.sh"
  printf ':\n' >"$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
  export WSL_DISTRO_NAME=Test
  printf '#!/bin/sh\nexit 100\n' >"$TEST_BIN/apt-cache"
  rm "$TEST_BIN/curl"
  cat >"$TEST_BIN/curl" <<'SH'
#!/bin/bash
printf 'curl <%s>\n' "$*" >>"$CALLS"
[[ ${CURL_STATUS:-0} == 0 ]] || exit "$CURL_STATUS"
while (($#)); do
  if [[ $1 == --output ]]; then
    if [[ ${CORRUPT_GLOW:-0} == 1 ]]; then printf 'untrusted archive\n' >"$2"; else cp "$FZD_TEST_GLOW_ARCHIVE" "$2"; fi
    exit
  fi
  shift
done
exit 42
SH
  chmod +x "$TEST_BIN/apt-cache" "$TEST_BIN/curl"
  export FZD_TEST_GLOW_ARCHIVE="${FZD_COMPAT_ROOT:-$REPO/.test-work/compat}/glow_3.0.0_Linux_x86_64.tar.gz"
}

@test "Enhanced installs verified Glow when APT has no package and renders real Markdown" {
  glow_fallback_tools
  [[ -f $FZD_TEST_GLOW_ARCHIVE ]] || skip 'prepare fixture with bash dev/prepare-glow-test.sh'
  mkdir -p "$XDG_CONFIG_HOME/glow"
  printf 'style: dark\n' >"$XDG_CONFIG_HOME/glow/glow.yml"
  apt_install_fzd --deps recommended --enhanced
  assert_installed
  [ -x "$PREFIX/bin/glow" ]
  ! grep -q '^apt-get' "$CALLS"
  grep -q 'https://github.com/charmbracelet/glow/releases/download/v3.0.0/' "$CALLS"
  grep -q -- "--proto =https" "$CALLS"
  printf '# Glow fixture\n\n**Rendered Markdown**\n' >"$HOME/doc.md"
  run "$PREFIX/bin/glow" --style dark --width 70 --pager=false -- "$HOME/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Glow'* && "$output" == *'fixture'* && "$output" == *$'\e['* && "$output" != *'# Glow fixture'* ]]
  export PATH="$PREFIX/bin:$PATH"
  export FZD_GLOW_STYLE=dark
  run bash -euc 'source "$1"; FZD_PREVIEW_TIMEOUT=2; _glow_render 70 "$2"' _ "$REPO/fzd.sh" "$HOME/doc.md"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Rendered Markdown'* && "$output" == *$'\e['* ]]
  run "$PREFIX/bin/fzd" --_preview "$(printf %s "$HOME/doc.md" | base64 | tr -d '\n')"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Rendered Markdown'* && "$output" != *'**Rendered Markdown**'* ]]
  apt_install_fzd --enhanced
  assert_installed
  apt_install_fzd --verify
  [ "$status" -eq 0 ]
  apt_install_fzd --uninstall
  [ "$status" -eq 0 ]
  [ -x "$PREFIX/bin/glow" ]
}

@test "Glow checksum rejection and download failure keep a usable core installation" {
  glow_fallback_tools
  export CORRUPT_GLOW=1
  apt_install_fzd --deps recommended --enhanced
  assert_installed
  [[ "$output" == *'Glow SHA256 mismatch'* ]]
  [ ! -e "$PREFIX/bin/glow" ]
  unset CORRUPT_GLOW
  export CURL_STATUS=22
  apt_install_fzd --deps recommended --enhanced
  assert_installed
  [[ "$output" == *'Optional Glow download failed'* ]]
  [ ! -e "$PREFIX/bin/glow" ]
}

@test "existing Glow and nonexecutable user files are preserved" {
  glow_fallback_tools
  printf '#!/bin/sh\nexit 0\n' >"$TEST_BIN/glow"
  chmod +x "$TEST_BIN/glow"
  apt_install_fzd --deps recommended --enhanced
  assert_installed
  [ ! -e "$CALLS" ]
  rm "$TEST_BIN/glow"
  printf 'user file\n' >"$PREFIX/bin/glow"
  apt_install_fzd --deps recommended --enhanced
  assert_installed
  [ "$(cat "$PREFIX/bin/glow")" = 'user file' ]
  [ ! -e "$CALLS" ]
}

@test "a later installer failure rolls back the downloaded Glow binary" {
  glow_fallback_tools
  [[ -f $FZD_TEST_GLOW_ARCHIVE ]] || skip 'prepare fixture with bash dev/prepare-glow-test.sh'
  inject_fault fail
  apt_install_fzd --deps recommended --enhanced
  [ "$status" -ne 0 ]
  [ ! -e "$PREFIX/bin/glow" ]
  [ ! -e "$PREFIX/bin/fzd" ]
}
