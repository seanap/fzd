#!/usr/bin/env bash
# Optional test fixture only: never install into PATH or a user's home.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
[[ $(uname -m) == x86_64 ]] || {
  printf 'This fixture is pinned for Linux x86_64\n' >&2
  exit 1
}
work="$repo/.test-work/phase-three"
archive="$work/fzf-0.65.2-linux_amd64.tar.gz"
expected=5eb8efc0e94aa559f84ea83eeba99bea7dce818e63f92b4b62e60663220f1c14
mkdir -p "$work"
verify() {
  local actual
  actual=$(sha256sum <"$1")
  [[ ${actual%% *} == "$expected" ]]
}
if [[ -f $archive ]] && verify "$archive"; then
  printf 'Verified fixture already available: %s\n' "$archive"
  exit 0
fi
temporary=$(mktemp "$work/fzf-download.XXXXXXXX")
trap 'rm -f -- "$temporary"' EXIT
curl --fail --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --connect-timeout 15 --max-time 120 --retry 2 --output "$temporary" \
  https://github.com/junegunn/fzf/releases/download/v0.65.2/fzf-0.65.2-linux_amd64.tar.gz
verify "$temporary" || {
  printf 'fzf fixture SHA256 mismatch\n' >&2
  exit 1
}
mv -- "$temporary" "$archive"
printf 'Verified fixture prepared: %s\n' "$archive"
