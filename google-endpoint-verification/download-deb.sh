#!/bin/bash

# Download Google's Endpoint Verification .deb next to this script and verify
# its SHA-256. URL comes from the .info file; name and hash from the SlackBuild.
#
# Usage: ./download-deb.sh
# Environment: DEST overrides the output directory (default: script directory).

set -euo pipefail

PRGNAM=google-endpoint-verification
HERE=$(cd "$(dirname "$0")" && pwd)
DEST=${DEST:-$HERE}

die() {
  echo "download-deb: $*" >&2
  exit 1
}

# Print the value of KEY=value from a file, without quotes.
read_var() {
  local key=$1 file=$2
  sed -n "s/^${key}=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" "$file" | head -n 1
}

# Succeed if $1 has the SHA-256 $2.
verify() {
  [ "$(sha256sum "$1" | cut -d ' ' -f 1)" = "$2" ]
}

fetch() {
  local url=$1 out=$2
  if command -v curl >/dev/null; then
    curl --proto '=https' --tlsv1.2 -fL --retry 3 --progress-bar -o "$out" "$url"
  elif command -v wget >/dev/null; then
    wget --https-only -O "$out" "$url"
  else
    die "neither curl nor wget found"
  fi
}

SLACKBUILD=$HERE/$PRGNAM.SlackBuild
INFO=$HERE/$PRGNAM.info
[ -r "$SLACKBUILD" ] && [ -r "$INFO" ] || die "$PRGNAM.SlackBuild and $PRGNAM.info must be next to this script"

url=$(read_var DOWNLOAD_x86_64 "$INFO")
debnam=$(read_var DEBNAM "$SLACKBUILD")
debver=$(read_var DEBVER "$SLACKBUILD")
sha256=$(read_var DEBSHA256 "$SLACKBUILD")
[ -n "$url" ] && [ -n "$debnam" ] && [ -n "$debver" ] && [ -n "$sha256" ] \
  || die "could not read url/name/version/sha256 from $INFO and $SLACKBUILD"
case "$url" in https://*) ;; *) die "refusing non-https url: $url" ;; esac

debfile=${debnam}_${debver}_amd64.deb
target=$DEST/$debfile
mkdir -p "$DEST"

if [ -f "$target" ] && verify "$target" "$sha256"; then
  echo "$debfile already present, sha256 OK"
  exit 0
fi

# Download to a temporary name so a bad file is never left under the real one.
part=$(mktemp "$DEST/.$debfile.XXXXXX")
trap 'rm -f "$part"' EXIT

echo "Downloading $url"
fetch "$url" "$part"

verify "$part" "$sha256" \
  || die "sha256 mismatch for $debfile (expected $sha256); file discarded"

chmod 644 "$part"
mv -f "$part" "$target"
echo "$debfile downloaded, sha256 OK"
