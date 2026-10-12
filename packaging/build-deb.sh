#!/usr/bin/env bash
# Build only from the supplied source tree; no network, root, or home edits.
set -euo pipefail
export LC_ALL=C TZ=UTC
source_root=$(cd -- "${1:?source directory required}" && pwd)
output=$(realpath -m -- "${2:?output directory required}")
epoch=${SOURCE_DATE_EPOCH:?SOURCE_DATE_EPOCH must identify the source commit}
[[ $epoch =~ ^[0-9]+$ ]] || exit 2
IFS= read -r version <"$source_root/VERSION"
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[1-9][0-9]*)?$ ]] || exit 2
revision=${FZD_DEB_REVISION:-1}
[[ $revision =~ ^[1-9][0-9]*$ ]] || exit 2
deb_version=${version/-/'~'}-$revision
# GitHub normalizes '~' in asset names. Keep Debian ordering in metadata only.
deb_asset=fzd-$version-debian-all.deb
mkdir -p -- "$output"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
stage=$work/root
bash "$source_root/install.sh" --stage "$stage" --prefix /usr
# Debian policy uses an absolute interpreter. No runtime code is changed.
sed -i '1s|^#!/usr/bin/env bash$|#!/bin/bash|' "$stage/usr/bin/fzd"
install -Dm644 "$source_root/packaging/debian/copyright" "$stage/usr/share/doc/fzd/copyright"
rm -r -- "$stage/usr/share/licenses"
install -Dm644 "$source_root/README.md" "$stage/usr/share/doc/fzd/README.md"
install -Dm644 "$source_root/docs/packaging.md" "$stage/usr/share/doc/fzd/packaging.md"
install -Dm644 "$source_root/packaging/fzd.1" "$stage/usr/share/man/man1/fzd.1"
printf 'fzd (%s) unstable; urgency=medium\n\n  * Release candidate built from immutable source.\n\n -- Sean Patrick <17012946+seanap@users.noreply.github.com>  %s\n' \
  "$deb_version" "$(date -u -R -d "@$epoch")" >"$stage/usr/share/doc/fzd/changelog.Debian"
gzip -n -9 "$stage/usr/share/man/man1/fzd.1" "$stage/usr/share/doc/fzd/README.md" \
  "$stage/usr/share/doc/fzd/packaging.md" "$stage/usr/share/doc/fzd/changelog.Debian"
mkdir -p "$stage/DEBIAN"
sed "s/@VERSION@/$deb_version/g" "$source_root/packaging/debian/control.in" >"$stage/DEBIAN/control"
printf 'Installed-Size: %s\n' "$(du -sk "$stage/usr" | cut -f1)" >>"$stage/DEBIAN/control"
(cd "$stage" && find usr -type f -print0 | LC_ALL=C sort -z | xargs -0 md5sum) >"$stage/DEBIAN/md5sums"
find "$stage" -exec touch -h -d "@$epoch" {} +
dpkg-deb --root-owner-group -Zxz -z6 --build "$stage" "$output/$deb_asset"
