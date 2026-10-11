#!/usr/bin/env bash
set -euo pipefail
repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$repo/.test-work/tmp"
export TMPDIR="$repo/.test-work/tmp"
if (($#)); then
  exec bats "$@"
fi
exec bats "$repo/tests/"*.bats
