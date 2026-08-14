#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 || "$1" != /* || "$2" != /* ]]; then
    echo "Usage: $0 /absolute/path/FormShift.app /absolute/path/FormShift.dmg" >&2
    exit 64
fi

APP_PATH="$1"
DMG_PATH="$2"
[[ -d "$APP_PATH" && -f "$APP_PATH/Contents/Info.plist" ]] || {
    echo "error: input is not a packaged macOS app: $APP_PATH" >&2
    exit 66
}
[[ ! -e "$DMG_PATH" ]] || {
    echo "error: refusing to overwrite existing DMG: $DMG_PATH" >&2
    exit 73
}

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/formshift-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

ditto "$APP_PATH" "$STAGING_DIR/FormShift.app"
ln -s /Applications "$STAGING_DIR/Applications"
mkdir -p "$(dirname "$DMG_PATH")"
hdiutil create \
    -volname "FormShift" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"
hdiutil imageinfo "$DMG_PATH" >/dev/null

echo "Created DMG: $DMG_PATH"
echo "No DMG signing, Developer ID verification, notarization, or stapling was performed."
