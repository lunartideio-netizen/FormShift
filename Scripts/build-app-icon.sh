#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSET_DIR="$PROJECT_DIR/Assets/AppIcon"
MASTER="$ASSET_DIR/FormShiftIcon-1024.png"
ICNS="$ASSET_DIR/FormShift.icns"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/formshift-icon.XXXXXX")"
ICONSET_DIR="$TEMP_ROOT/FormShift.iconset"

cleanup() {
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT

mkdir -p "$ASSET_DIR"
mkdir -p "$ICONSET_DIR"
swift "$SCRIPT_DIR/generate-app-icon.swift" "$MASTER"

make_icon() {
    local pixels="$1"
    local filename="$2"
    sips --resampleHeightWidth "$pixels" "$pixels" "$MASTER" --out "$ICONSET_DIR/$filename" >/dev/null
}

make_icon 16 icon_16x16.png
make_icon 32 icon_16x16@2x.png
make_icon 32 icon_32x32.png
make_icon 64 icon_32x32@2x.png
make_icon 128 icon_128x128.png
make_icon 256 icon_128x128@2x.png
make_icon 256 icon_256x256.png
make_icon 512 icon_256x256@2x.png
make_icon 512 icon_512x512.png
cp "$MASTER" "$ICONSET_DIR/icon_512x512@2x.png"

iconutil -c icns "$ICONSET_DIR" -o "$ICNS"
echo "Created app icon: $ICNS"
