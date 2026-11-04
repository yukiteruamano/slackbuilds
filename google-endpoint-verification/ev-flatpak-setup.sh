#!/bin/bash

# Wire Google Endpoint Verification to a Flatpak Google Chrome (per user).
#
# Usage: ev-flatpak-setup [--spawn] [--remove]
#   (default)  write the native messaging manifest; the sandbox runs apihelper
#              itself, it only needs /opt/google/endpoint-verification read-only.
#   --spawn    fallback: run apihelper on the host through flatpak-spawn. Needs
#              the much broader org.freedesktop.Flatpak talk permission.
#   --remove   delete what this script wrote.
# EV_FLATPAK_APP overrides the application id (default com.google.Chrome).

set -euo pipefail

APP=${EV_FLATPAK_APP:-com.google.Chrome}
PREFIX=/opt/google/endpoint-verification
HOST_NAME=com.google.endpoint_verification.api_helper
APPDIR=$HOME/.var/app/$APP
MANIFEST=$APPDIR/config/google-chrome/NativeMessagingHosts/$HOST_NAME.json
WRAPPER=$APPDIR/data/bin/endpoint-verification-wrapper.sh
TEMPLATE=$PREFIX/share/native-messaging-hosts/chrome-endpoint-verification.json

die() {
  echo "ev-flatpak-setup: $*" >&2
  exit 1
}

remove() {
  rm -f "$MANIFEST" "$WRAPPER"
  echo "Removed $MANIFEST and $WRAPPER (if present)."
  echo "To drop the permissions: flatpak override --user --reset $APP"
}

write_wrapper() {
  mkdir -p "$(dirname "$WRAPPER")"
  cat > "$WRAPPER" <<EOF
#!/bin/sh
if [ "\${container-}" = flatpak ]; then
  exec flatpak-spawn --host $PREFIX/bin/apihelper "\$@"
fi
exec $PREFIX/bin/apihelper "\$@"
EOF
  chmod 755 "$WRAPPER"
}

# Copy Google's manifest (allowed_origins included), changing only "path".
write_manifest() {
  local helper=$1
  mkdir -p "$(dirname "$MANIFEST")"
  sed "s|\"path\": *\"[^\"]*\"|\"path\": \"$helper\"|" "$TEMPLATE" > "$MANIFEST"
  chmod 644 "$MANIFEST"
  grep -q "\"path\": \"$helper\"" "$MANIFEST" || die "could not set path in $MANIFEST"
}

mode=sandbox
for arg in "$@"; do
  case "$arg" in
    --spawn) mode=spawn ;;
    --remove) mode=remove ;;
    *) die "unknown option: $arg" ;;
  esac
done

[ "$(id -u)" -ne 0 ] || die "run as your normal user, not root"
[ "$mode" = remove ] && { remove; exit 0; }

[ -x "$PREFIX/bin/apihelper" ] || die "$PREFIX/bin/apihelper not found, install the package first"
[ -r "$TEMPLATE" ] || die "$TEMPLATE not found"
command -v flatpak >/dev/null || die "flatpak not found"
flatpak info "$APP" >/dev/null 2>&1 || echo "warning: $APP is not installed" >&2

if [ "$mode" = spawn ]; then
  write_wrapper
  write_manifest "$WRAPPER"
  override="--talk-name=org.freedesktop.Flatpak"
  echo "WARNING: this permission lets anything inside $APP run commands on the host."
else
  write_manifest "$PREFIX/bin/apihelper"
  override="--filesystem=$PREFIX:ro"
fi

echo "Manifest written: $MANIFEST"
echo
echo "Now grant the permission (not applied automatically) and restart Chrome:"
echo "  flatpak override --user $override $APP"
