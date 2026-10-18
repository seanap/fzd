#!/usr/bin/env bash
# One local/CI static-check entry point. Preserve the application's legacy format.
set -euo pipefail
repo=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
cd "$repo"
scripts=(lib/*.bash tests/run.sh tests/helpers/*.bash install.sh installer/*.bash
  shell/integration.sh shell/inline.sh shell/launcher.bash tests/helpers/installer-mv-stub tests/helpers/fzf-stub
  tests/helpers/backend-stub tests/helpers/pty-session benchmarks/*.sh dev/*.sh packaging/*.sh)
bash -n fzd.sh
zsh -n shell/integration.zsh
shellcheck fzd.sh "${scripts[@]}"
shfmt -d -i 2 "${scripts[@]}"
shfmt -d -i 2 -ln bats tests/*.bats
bash -n packaging/arch/PKGBUILD.in
git diff --check
