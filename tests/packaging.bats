#!/usr/bin/env bats

setup_file() {
  export PACKAGE_REPO
  PACKAGE_REPO=$(cd -- "$BATS_TEST_DIRNAME/.." && pwd)
  export PACKAGE_FIXTURE="$BATS_FILE_TMPDIR/packages"
  mkdir -p "$PACKAGE_FIXTURE" "$BATS_FILE_TMPDIR/home"
  HOME="$BATS_FILE_TMPDIR/home" SOURCE_DATE_EPOCH=1700000000 \
    bash "$PACKAGE_REPO/packaging/build-deb.sh" "$PACKAGE_REPO" "$PACKAGE_FIXTURE" >/dev/null
  export PACKAGE_DEB
  PACKAGE_DEB=$(printf '%s\n' "$PACKAGE_FIXTURE/"*.deb)
  dpkg-deb -R "$PACKAGE_DEB" "$PACKAGE_FIXTURE/root"
}

@test "Debian payload includes all Explorer modules and opt-in integration" {
  for path in bin/fzd share/fzd/integration.sh share/fzd/integration.zsh share/fzd/inline.sh share/fzd/fzd.conf.example \
    share/fzd/lib/state.bash share/fzd/lib/operations.bash share/fzd/lib/ui.bash \
    share/doc/fzd/copyright share/doc/fzd/README.md.gz share/doc/fzd/TECHNICAL.md.gz share/man/man1/fzd.1.gz; do
    [ -f "$PACKAGE_FIXTURE/root/usr/$path" ]
  done
  [ -x "$PACKAGE_FIXTURE/root/usr/bin/fzd" ]
  [ "$(head -n1 "$PACKAGE_FIXTURE/root/usr/bin/fzd")" = '#!/bin/bash' ]
  diff <(tail -n +2 "$PACKAGE_REPO/fzd.sh") <(tail -n +2 "$PACKAGE_FIXTURE/root/usr/bin/fzd")
}

@test "Debian package has no maintainer scripts home files or source lifecycle" {
  for path in preinst postinst prerm postrm conffiles triggers; do
    [ ! -e "$PACKAGE_FIXTURE/root/DEBIAN/$path" ]
  done
  [ ! -e "$PACKAGE_FIXTURE/root/home" ]
  [ ! -e "$PACKAGE_FIXTURE/root/etc" ]
  [ ! -e "$PACKAGE_FIXTURE/root/usr/share/fzd/install.sh" ]
  [ ! -e "$PACKAGE_FIXTURE/root/usr/share/fzd/install.manifest" ]
}

@test "Debian dependencies explicitly cover interpreter fzf flock GNU tools and default editor" {
  run dpkg-deb -f "$PACKAGE_DEB" Depends
  [ "$status" -eq 0 ]
  for requirement in 'bash (>= 4.4)' 'fzf (>= 0.44.0)' 'zoxide (>= 0.9.0)' coreutils findutils util-linux grep sed micro; do
    [[ "$output" == *"$requirement"* ]]
  done
  [ "$(dpkg-deb -f "$PACKAGE_DEB" Architecture)" = all ]
  run dpkg-deb -f "$PACKAGE_DEB" Recommends
  [[ "$output" == *'libglib2.0-bin | trash-cli'* ]]
  [[ "$output" == *'eza'* ]]
}

@test "Debian downloadable filename is GitHub safe while metadata retains Debian prerelease ordering" {
  local version internal
  IFS= read -r version <"$PACKAGE_REPO/VERSION"
  [ "${PACKAGE_DEB##*/}" = "fzd-$version-debian-all.deb" ]
  [[ ${PACKAGE_DEB##*/} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]$ ]]
  internal=$(dpkg-deb -f "$PACKAGE_DEB" Version)
  [ "$internal" = "${version/-/'~'}-1" ]
  if [[ $version == *-rc.* ]]; then
    dpkg --compare-versions "$internal" lt "${version%-rc.*}"
  fi
}

@test "Stable and future candidate builds automatically use GitHub safe Debian filenames" {
  local source version deb
  source=$PACKAGE_FIXTURE/future-source
  mkdir -p "$source"
  git -C "$PACKAGE_REPO" archive HEAD | tar -xf - -C "$source"
  for version in 0.1.0 0.2.0-rc.17; do
    printf '%s\n' "$version" >"$source/VERSION"
    SOURCE_DATE_EPOCH=1700000000 run bash "$PACKAGE_REPO/packaging/build-deb.sh" "$source" "$PACKAGE_FIXTURE/$version"
    [ "$status" -eq 0 ]
    deb=$PACKAGE_FIXTURE/$version/fzd-$version-debian-all.deb
    [ -f "$deb" ]
    [ "$(dpkg-deb -f "$deb" Version)" = "${version/-/'~'}-1" ]
  done
}

@test "Debian build is byte reproducible with fixed source epoch" {
  SOURCE_DATE_EPOCH=1700000000 run bash "$PACKAGE_REPO/packaging/build-deb.sh" "$PACKAGE_REPO" "$PACKAGE_FIXTURE/repeated"
  [ "$status" -eq 0 ]
  cmp "$PACKAGE_DEB" "$PACKAGE_FIXTURE/repeated/${PACKAGE_DEB##*/}"
}

@test "Debian revision supports ordered package upgrades" {
  SOURCE_DATE_EPOCH=1700000000 FZD_DEB_REVISION=2 run bash "$PACKAGE_REPO/packaging/build-deb.sh" "$PACKAGE_REPO" "$PACKAGE_FIXTURE/upgrade"
  [ "$status" -eq 0 ]
  local next upstream
  next=$(printf '%s\n' "$PACKAGE_FIXTURE/upgrade/"*.deb)
  dpkg --compare-versions "$(dpkg-deb -f "$next" Version)" gt "$(dpkg-deb -f "$PACKAGE_DEB" Version)"
  IFS= read -r upstream <"$PACKAGE_REPO/VERSION"
  if [[ $upstream == *-rc.* ]]; then
    dpkg --compare-versions "$(dpkg-deb -f "$PACKAGE_DEB" Version)" lt "${upstream%-rc.*}-1"
  fi
}

@test "Build rejects invalid source epoch and package revisions" {
  SOURCE_DATE_EPOCH=invalid run bash "$PACKAGE_REPO/packaging/build-deb.sh" "$PACKAGE_REPO" "$PACKAGE_FIXTURE/invalid"
  [ "$status" -eq 2 ]
  SOURCE_DATE_EPOCH=1700000000 FZD_DEB_REVISION='1;touch bad' run bash "$PACKAGE_REPO/packaging/build-deb.sh" "$PACKAGE_REPO" "$PACKAGE_FIXTURE/invalid"
  [ "$status" -eq 2 ]
}

@test "Immutable release build ignores untracked inputs and validates checksums" {
  # Only runnable after the release builder itself has been committed.
  git -C "$PACKAGE_REPO" cat-file -e HEAD:packaging/build-release.sh
  run bash "$PACKAGE_REPO/packaging/build-release.sh" HEAD "$PACKAGE_FIXTURE/release"
  [ "$status" -eq 0 ]
  (cd "$PACKAGE_FIXTURE/release" && sha256sum -c SHA256SUMS)
  local commit version
  commit=$(git -C "$PACKAGE_REPO" rev-parse HEAD)
  version=$(git -C "$PACKAGE_REPO" show HEAD:VERSION)
  grep -Fx "commit=$commit" "$PACKAGE_FIXTURE/release/SOURCE"
  grep -Fx "# Source commit: $commit" "$PACKAGE_FIXTURE/release/PKGBUILD"
  diff <(git -C "$PACKAGE_REPO" show HEAD:fzd.sh) \
    <(tar -xOzf "$PACKAGE_FIXTURE/release/fzd-$version.tar.gz" "fzd-$version/fzd.sh")
  run tar -tzf "$PACKAGE_FIXTURE/release/fzd-$version.tar.gz"
  [ "$status" -eq 0 ]
  [[ "$output" != *'/.test-work/'* ]]
  run bash "$PACKAGE_REPO/packaging/build-release.sh" HEAD "$PACKAGE_FIXTURE/release"
  [ "$status" -eq 2 ]
  [[ "$output" == *'Output already exists'* ]]
}

@test "Release manifest uses exact GitHub safe asset names and pins matching Arch metadata" {
  local version release asset archive_digest
  version=$(git -C "$PACKAGE_REPO" show HEAD:VERSION)
  release=$PACKAGE_FIXTURE/names-release
  run bash "$PACKAGE_REPO/packaging/build-release.sh" HEAD "$release"
  [ "$status" -eq 0 ]
  diff <(printf '%s\n' "fzd-$version.tar.gz" "fzd-$version-debian-all.deb" PKGBUILD SOURCE | sort) \
    <(awk '{print $2}' "$release/SHA256SUMS" | sort)
  for asset in "$release"/*; do
    [[ ${asset##*/} =~ ^[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9]$ ]]
  done
  (cd "$release" && sha256sum -c SHA256SUMS)
  grep -Fx "pkgver=${version/-/}" "$release/PKGBUILD"
  grep -Fx "source=('https://github.com/seanap/fzd/releases/download/v$version/fzd-$version.tar.gz')" "$release/PKGBUILD"
  archive_digest=$(sha256sum <"$release/fzd-$version.tar.gz")
  grep -Fx "sha256sums=('${archive_digest%% *}')" "$release/PKGBUILD"
}

@test "Current release installation documentation matches the generated Debian filename" {
  local version document
  IFS= read -r version <"$PACKAGE_REPO/VERSION"
  for document in docs/TECHNICAL.md docs/packaging.md "docs/releases/v$version.md"; do
    grep -Fx "sudo apt install ./${PACKAGE_DEB##*/}" "$PACKAGE_REPO/$document"
  done
  diff "$PACKAGE_REPO/README.md" <(gzip -dc "$PACKAGE_FIXTURE/root/usr/share/doc/fzd/README.md.gz")
}

@test "Package files have only standard root ownership and data permissions" {
  run dpkg-deb -c "$PACKAGE_DEB"
  [ "$status" -eq 0 ]
  [[ "$output" != *'htpc/'* ]]
  [[ "$output" != *'-rwxrwx'* ]]
  [[ "$output" != *'install.manifest'* ]]
  (cd "$PACKAGE_FIXTURE/root" && md5sum -c DEBIAN/md5sums)
}
