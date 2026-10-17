#!/bin/sh
# Download the pinned WebKit prebuilt iOS-simulator archive (minified, ~315 MB), verify size and sha256 against
# src/archive.json, and extract it into a NEW empty directory. Never commits anything: the target belongs under
# .cache/ (gitignored) or a runner temp dir.
#   fetch-archive.sh <zip-dir> <root-dir>
# <zip-dir> keeps the zip (the CI cache path); <root-dir> must not exist or be empty.
set -eu
zipdir=${1:?zip dir}; rootdir=${2:?root dir}
here=$(cd "$(dirname "$0")/.." && pwd)
field() { sed -n "s/.*\"$1\": *\"\{0,1\}\([^\",]*\)\"\{0,1\},\{0,1\}\$/\1/p" "$here/src/archive.json"; }
url=$(field url); bytes=$(field bytes); sha=$(field sha256); rev=$(field revision)
zip="$zipdir/${rev%@*}.zip"
mkdir -p "$zipdir"
if [ ! -f "$zip" ]; then
  echo "downloading $url"
  curl --fail --silent --show-error --location --retry 5 --retry-delay 5 --output "$zip.part" "$url"
  mv "$zip.part" "$zip"
fi
got=$(wc -c < "$zip" | tr -d ' ')
[ "$got" = "$bytes" ] || { echo "size $got, expected $bytes" >&2; exit 1; }
echo "$sha  $zip" | shasum -a 256 -c -
if [ -d "$rootdir" ] && [ -n "$(ls -A "$rootdir")" ]; then echo "$rootdir is not empty" >&2; exit 1; fi
mkdir -p "$rootdir"
unzip -q "$zip" -d "$rootdir"
# the archive is not code signed beyond ad-hoc; drop quarantine bits if any (no-op on a runner)
xattr -dr com.apple.quarantine "$rootdir" 2>/dev/null || true
ls "$rootdir"
