#!/usr/bin/env bash
# Verified upstream fixture only; never installed into the user's PATH.
set -euo pipefail
repo=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
[[ $(uname -m) == x86_64 ]] || {
  printf 'Glow fixture requires Linux x86_64\n' >&2
  exit 1
}
work=$repo/.test-work/compat
archive=$work/glow_3.0.0_Linux_x86_64.tar.gz
expected=13e05e4b2acc18d2aee44291aefe6325b077ec321b631a0cfa780e8e3bc33f78
mkdir -p "$work"
if [[ -f $archive ]]; then
  digest=$(sha256sum <"$archive")
  [[ ${digest%% *} != "$expected" ]] || exit 0
fi
TX=$(mktemp -d "$work/glow-fixture.XXXXXXXX")
trap 'rm -rf -- "$TX"' EXIT
warn() { printf '%s\n' "$*" >&2; }
# shellcheck source=installer/dependencies.bash
source "$repo/installer/dependencies.bash"
download_glow
mv -- "$TX/glow.tar.gz" "$archive"
printf 'Verified Glow fixture: %s\n' "$archive"
