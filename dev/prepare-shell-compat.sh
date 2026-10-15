#!/usr/bin/env bash
# Test fixtures only: never install or modify the user's suggestion engines.
set -euo pipefail
repo=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
work=$repo/.test-work/compat
mkdir -p "$work"
fetch_fixture() {
  local name=$1 url=$2 commit=$3
  if [[ ! -d $work/$name/.git ]]; then
    git init -q "$work/$name"
    git -C "$work/$name" remote add origin "$url"
    git -C "$work/$name" fetch -q --depth 1 origin "$commit"
    git -C "$work/$name" checkout -q --detach FETCH_HEAD
  fi
  [[ $(git -C "$work/$name" rev-parse HEAD) == "$commit" ]] || {
    printf 'Unexpected %s fixture revision; preserve it and prepare a clean fixture\n' "$name" >&2
    exit 1
  }
}
fetch_fixture blesh https://github.com/akinomyoga/ble.sh.git d81fd54feb0d996fdff20dca27eaf0201f7015cc
fetch_fixture zsh-autosuggestions https://github.com/zsh-users/zsh-autosuggestions.git 85919cd1ffa7d2d5412f6d3fe437ebdbeeec4fc5
# ble.sh's build includes its pinned contrib submodule; use upstream's build.
git -C "$work/blesh" submodule update --init --recursive
make -s -C "$work/blesh" -j2
archive=$work/ble-0.4.0-devel3-2.tar.xz
if [[ ! -f $archive ]]; then
  curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    --connect-timeout 15 --max-time 120 --retry 2 --output "$archive" \
    https://github.com/akinomyoga/ble.sh/releases/download/v0.4.0-devel3/ble-0.4.0-devel3-2.tar.xz
fi
printf '%s  %s\n' bdcdcfff216495403adf82a701fe41675f64b64644dc77caabd3e015871ebd61 "$archive" | sha256sum -c -
printf 'Prepared pinned ble.sh and zsh-autosuggestions fixtures under %s\n' "$work"
