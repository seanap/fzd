#!/usr/bin/env bash
# Resolve a Git revision once; all build inputs then come from that commit.
set -euo pipefail
export LC_ALL=C TZ=UTC
repo=$(cd -- "${BASH_SOURCE[0]%/*}/.." && pwd)
commit=$(git -C "$repo" rev-parse --verify "${1:?Git revision required}^{commit}")
output=$(realpath -m -- "${2:?empty output directory required}")
[[ ! -e $output ]] || {
  printf 'Output already exists; choose a fresh directory: %s\n' "$output" >&2
  exit 2
}
version=$(git -C "$repo" show "$commit:VERSION")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-rc\.[1-9][0-9]*)?$ ]] || exit 2
export SOURCE_DATE_EPOCH
SOURCE_DATE_EPOCH=$(git -C "$repo" show -s --format=%ct "$commit")
mkdir -p "$repo/.test-work" "$output"
work=$(mktemp -d "$repo/.test-work/release.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
archive=fzd-$version.tar.gz
git -C "$repo" archive --format=tar --prefix="fzd-$version/" "$commit" | gzip -n -9 >"$output/$archive"
tar -xzf "$output/$archive" -C "$work"
source_root=$work/fzd-$version
# Use the builder belonging to the chosen revision, not the working tree.
TMPDIR=$work bash "$source_root/packaging/build-deb.sh" "$source_root" "$output"
digest=$(sha256sum <"$output/$archive")
sed -e "s/@VERSION@/$version/g" -e "s/@ARCH_VERSION@/${version/-/}/g" \
  -e "s/@SHA256@/${digest%% *}/g" "$source_root/packaging/arch/PKGBUILD.in" >"$output/PKGBUILD"
printf 'version=%s\ncommit=%s\nsource_date_epoch=%s\n' "$version" "$commit" "$SOURCE_DATE_EPOCH" >"$output/SOURCE"
(cd "$output" && sha256sum "$archive" ./*.deb PKGBUILD SOURCE >SHA256SUMS)
printf 'Local release artifacts: %s\n' "$output"
