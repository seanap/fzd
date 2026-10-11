#!/usr/bin/env bash
# Optional Ubuntu/Debian test tooling: extract packages, install no services.
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work="$repo/.test-work/tools"
mkdir -p "$work/downloads" "$work/root"
cd -- "$work/downloads"
apt-get download plocate liburing2
for package in ./*.deb; do
  dpkg-deb -x "$package" "$work/root"
done
printf 'Private locate test binaries are ready in %s\n' "$work/root"
