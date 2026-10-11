#!/usr/bin/env bash
# DESTRUCTIVE ONLY INSIDE AN EPHEMERAL CONTAINER. Never run on the host.
set -euo pipefail
[[ -f /run/.containerenv || -f /.dockerenv ]] || {
  printf 'This validator requires a disposable container\n' >&2
  exit 2
}
target=${1:?ubuntu, debian, arch or fedora required}
[[ $target == ubuntu || $target == debian || $target == arch || $target == fedora ]] || exit 2
export LC_ALL=C.UTF-8 TERM=xterm-256color USER=root
mkdir -p /work /results
cat /etc/os-release
cat /artifacts/SOURCE
(cd /artifacts && sha256sum -c SHA256SUMS)
archive=(/artifacts/fzd-*.tar.gz)
tar -xzf "${archive[0]}" -C /work
source_dirs=(/work/fzd-*)
source_root=${source_dirs[0]}
export HOME=/work/home ZDOTDIR=/work/zsh
mkdir -p "$HOME/.config/fzd" "$HOME/.local/state/fzd" "$ZDOTDIR"
printf '# user Bash settings\nlf() { printf existing; }\n' >"$HOME/.bashrc"
printf '# user zsh settings\nlf() { printf existing; }\n' >"$ZDOTDIR/.zshrc"
printf 'FZD_GLOBAL_BACKEND=live\n' >"$HOME/.config/fzd/fzd.conf"
printf 'retained state\n' >"$HOME/.local/state/fzd/retained"
(cd /work && sha256sum home/.bashrc zsh/.zshrc home/.config/fzd/fzd.conf home/.local/state/fzd/retained) >/results/home-before.sha256

case $target in
ubuntu | debian)
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  # First transaction exercises Depends without Recommended preview/Trash tools.
  apt-get install --no-install-recommends -y /artifacts/*.deb
  dpkg-query -W bash fzf coreutils findutils util-linux micro fzd
  dpkg -V fzd
  ;;
arch)
  pacman -Syu --noconfirm --needed base-devel
  useradd -m builder
  printf 'builder ALL=(ALL) NOPASSWD: /usr/bin/pacman\n' >/etc/sudoers.d/fzd-builder
  chmod 440 /etc/sudoers.d/fzd-builder
  mkdir /work/arch
  cp /artifacts/PKGBUILD "${archive[0]}" /work/arch/
  chown -R builder:builder /work/arch
  # makepkg -s resolves the actual recipe dependencies through pacman.
  (cd /work/arch && runuser -u builder -- makepkg -s --noconfirm)
  (cd /work/arch && runuser -u builder -- makepkg --printsrcinfo) >/results/.SRCINFO
  pacman -U --noconfirm /work/arch/fzd-*-any.pkg.tar.zst
  pacman -Q bash fzf coreutils findutils util-linux micro fzd
  pacman -Qkk fzd
  cp /work/arch/fzd-*-any.pkg.tar.zst /results/
  ;;
fedora)
  dnf install -y bash fzf coreutils findutils util-linux-core grep sed gawk micro
  # Compatibility assessment only: this phase does not supply an RPM recipe.
  bash "$source_root/install.sh" --stage /work/stage --prefix /usr
  cp -a /work/stage/usr/. /usr/
  rpm -q bash fzf coreutils findutils util-linux-core micro
  ;;
esac
(cd /work && sha256sum -c /results/home-before.sha256)
command -v flock
flock --version
cp --version | head -n1
fzf --version

# Upgrade preserves user files; the same source is rebuilt at package revision 2.
case $target in
ubuntu | debian)
  export SOURCE_DATE_EPOCH
  SOURCE_DATE_EPOCH=$(sed -n 's/^source_date_epoch=//p' /artifacts/SOURCE)
  FZD_DEB_REVISION=2 bash "$source_root/packaging/build-deb.sh" "$source_root" /work/upgrade
  apt-get install --no-install-recommends -y /work/upgrade/*.deb
  dpkg-query -W fzd
  ;;
arch)
  sed -i 's/^pkgrel=1$/pkgrel=2/' /work/arch/PKGBUILD
  (cd /work/arch && runuser -u builder -- makepkg --force --noconfirm)
  pacman -U --noconfirm /work/arch/fzd-*-2-any.pkg.tar.zst
  pacman -Q fzd
  ;;
esac
(cd /work && sha256sum -c /results/home-before.sha256)

case $target in
ubuntu | debian)
  apt-get install --no-install-recommends -y zsh tmux bats bubblewrap file tree curl ca-certificates git bat fd-find libglib2.0-bin plocate
  ;;
arch)
  pacman -S --noconfirm --needed zsh tmux bats bubblewrap file tree curl git bat fd glib2 plocate
  ;;
fedora)
  dnf install -y zsh tmux bats bubblewrap file tree curl git bat fd-find glib2 plocate diffutils which tar gzip xz
  ;;
esac
printf '. /usr/share/fzd/integration.sh\n' >>"$HOME/.bashrc"
printf '. /usr/share/fzd/integration.sh\n' >>"$ZDOTDIR/.zshrc"
bash --noprofile -ic '[[ $(lf) == existing ]]; declare -F fzd_cd'
zsh -ic '[[ $(lf) == existing ]]; whence -w fzd_cd'
(cd /work && sha256sum home/.bashrc zsh/.zshrc home/.config/fzd/fzd.conf home/.local/state/fzd/retained) >/results/home-opt-in.sha256

# Exercise the exact installed executable/data through the existing 201 tests.
# Packaging tests run on the Git checkout separately (archives contain no .git).
cp /usr/bin/fzd "$source_root/fzd.sh"
cp /usr/share/fzd/integration.sh "$source_root/shell/integration.sh"
cp /usr/share/fzd/lib/*.bash "$source_root/lib/"
mkdir -p "$source_root/.test-work/phase-three"
cp /fixtures/fzf-0.65.2-linux_amd64.tar.gz "$source_root/.test-work/phase-three/"
cd "$source_root"
test_files=()
for test_file in tests/*.bats; do
  [[ $test_file == tests/packaging.bats ]] || test_files+=("$test_file")
done
useradd -m validator
chown -R validator:validator "$source_root" /results
runuser -u validator -- env HOME=/work bash tests/run.sh "${test_files[@]}" --print-output-on-failure >/results/tests.tap
if grep -Eq '^(not ok|ok .*# skip)' /results/tests.tap; then exit 1; fi
tail -n5 /results/tests.tap

# Source-to-package transition: uninstall only private source ownership, then
# opt in to the package integration. No real user's home is mounted here.
transition=/work/transition
mkdir -p "$transition"
HOME=$transition ZDOTDIR=$transition bash install.sh --noninteractive --deps none
HOME=$transition ZDOTDIR=$transition bash "$transition/.local/share/fzd/install.sh" --uninstall
[[ ! -e $transition/.local/bin/fzd && -x /usr/bin/fzd ]]
HOME=$transition bash --noprofile --norc -c '. /usr/share/fzd/integration.sh; [[ $(command -v fzd) == /usr/bin/fzd ]]; declare -F fzd_cd'

case $target in
ubuntu | debian) apt-get purge -y fzd ;;
arch) pacman -R --noconfirm fzd ;;
fedora)
  # Stage-only cleanup of the exact owned files, no dependency removals.
  find /work/stage/usr -type f -printf '%P\0' | while IFS= read -r -d '' path; do rm -- "/usr/$path"; done
  ;;
esac
[[ ! -e /usr/bin/fzd && ! -e /usr/share/fzd/integration.sh ]]
(cd /work && sha256sum -c /results/home-opt-in.sha256)
command -v fzf micro flock
printf 'PASS: %s actual userspace, lifecycle, shell startup, packaged regression suite\n' "$target" | tee /results/RESULT
