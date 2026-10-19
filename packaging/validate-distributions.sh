#!/usr/bin/env bash
# Rootless Podman or Docker; invoke with sudo only when your runtime needs it.
set -euo pipefail
repo=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
artifacts=$(realpath -e -- "${1:?artifact directory required}")
target=${2:?ubuntu, debian, arch or fedora required}
case $target in
ubuntu) image=docker.io/library/ubuntu:24.04 ;;
debian) image=docker.io/library/debian:trixie-slim ;;
arch) image=docker.io/library/archlinux:base ;;
fedora) image=registry.fedoraproject.org/fedora:44 ;;
*) exit 2 ;;
esac
runtime=${FZD_CONTAINER_RUNTIME:-podman}
runtime_options=()
run_options=()
if [[ $runtime == podman ]]; then
  # Locked proc submounts prevent nested bubblewrap from mounting its private
  # procfs on hosted Ubuntu kernels. Keep /sys masks and the normal capability
  # budget; unmask only /proc inside this disposable test container.
  run_options=(--cgroups=disabled --security-opt 'unmask=/proc/*')
fi
if [[ $runtime == podman && ${FZD_CONTAINER_LOCAL_STORAGE:-0} == 1 ]]; then
  runtime_options=(--root "$repo/.test-work/containers/storage" --runroot /tmp/fzd-containers-run --storage-driver vfs)
fi
result="$repo/.test-work/phase-four-a/$target"
fixture="$repo/.test-work/phase-three/fzf-0.65.2-linux_amd64.tar.gz"
compat="$repo/.test-work/compat"
[[ -f $compat/blesh/out/ble.sh && -f $compat/zsh-autosuggestions/zsh-autosuggestions.zsh ]] || {
  printf 'Prepare suggestion fixtures first: bash dev/prepare-shell-compat.sh\n' >&2
  exit 2
}
[[ -f $compat/glow_3.0.0_Linux_x86_64.tar.gz ]] || {
  printf 'Prepare Glow fixture first: bash dev/prepare-glow-test.sh\n' >&2
  exit 2
}
[[ -f $fixture && $(uname -m) == x86_64 ]] || {
  printf 'Prepare the x86_64 fixture first: bash dev/prepare-fzf-test.sh\n' >&2
  exit 2
}
if [[ -e $result ]]; then
  prior=$(mktemp -d "$repo/.test-work/phase-four-a/$target.previous.XXXXXXXX")
  chmod 755 "$prior"
  mv -- "$result" "$prior/results"
fi
mkdir -p "$result"
"$runtime" "${runtime_options[@]}" pull "$image"
"$runtime" "${runtime_options[@]}" image inspect "$image" >"$result/image.json"
# Nested bubblewrap is used by safety tests. The container gets no host home,
# Docker socket, devices, or privileged mode. Network permits distro downloads.
"$runtime" "${runtime_options[@]}" run --rm "${run_options[@]}" --network=host \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  -v "$artifacts:/artifacts:ro" -v "$repo/packaging:/validation:ro" \
  -v "$fixture:/fixtures/fzf-0.65.2-linux_amd64.tar.gz:ro" -v "$result:/results" \
  -v "$compat:/fixtures/compat:ro" \
  "$image" bash /validation/validate-container.sh "$target" 2>&1 | tee "$result/validation.log"
