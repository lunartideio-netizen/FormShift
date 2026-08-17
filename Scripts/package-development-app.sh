#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "Usage: $0 /absolute/output/directory" >&2
    exit 64
fi

OUTPUT_DIR="$1"
APP_PATH="$OUTPUT_DIR/FormShift.app"
[[ ! -e "$APP_PATH" ]] || {
    echo "error: refusing to overwrite existing app: $APP_PATH" >&2
    exit 73
}
[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || {
    echo "error: development packaging requires Apple Silicon macOS" >&2
    exit 69
}

FFMPEG_ARTIFACTS="$PROJECT_DIR/Artifacts/FFmpeg/bin"
[[ -x "$FFMPEG_ARTIFACTS/ffmpeg" && -x "$FFMPEG_ARTIFACTS/ffprobe" ]] || {
    echo "error: verified local FFmpeg artifacts are required" >&2
    exit 66
}

cd "$PROJECT_DIR"
swift build -c release --arch arm64 --product FormShift
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
EXECUTABLE="$BIN_DIR/FormShift"
[[ -x "$EXECUTABLE" ]] || {
    echo "error: release executable not found: $EXECUTABLE" >&2
    exit 70
}

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$APP_PATH/Contents/Helpers"
cp "$SCRIPT_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_PATH/Contents/MacOS/FormShift"
[[ -f "$PROJECT_DIR/Assets/AppIcon/FormShift.icns" ]] || "$SCRIPT_DIR/build-app-icon.sh"
cp "$PROJECT_DIR/Assets/AppIcon/FormShift.icns" "$APP_PATH/Contents/Resources/FormShift.icns"
cp "$FFMPEG_ARTIFACTS/ffmpeg" "$FFMPEG_ARTIFACTS/ffprobe" "$APP_PATH/Contents/Helpers/"
mkdir -p "$APP_PATH/Contents/Resources/Licenses/FFmpeg"
cp "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$PROJECT_DIR/PRIVACY.md" \
    "$APP_PATH/Contents/Resources/Licenses/"
cp "$PROJECT_DIR/Artifacts/FFmpeg/compliance/build-manifest.txt" \
    "$PROJECT_DIR/Artifacts/FFmpeg/compliance/ffmpeg.lock" \
    "$APP_PATH/Contents/Resources/Licenses/FFmpeg/"

while IFS= read -r -d '' bundle; do
    ditto "$bundle" "$APP_PATH/Contents/Resources/$(basename "$bundle")"
done < <(find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -print0)

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION:-0.6.3-dev}" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP_PATH/Contents/Info.plist"
plutil -lint "$APP_PATH/Contents/Info.plist"

for helper in "$APP_PATH"/Contents/Helpers/*; do
    codesign --force --sign - "$helper"
done
codesign --force --sign - --entitlements "$SCRIPT_DIR/FormShift.entitlements" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "Created ad-hoc signed development app: $APP_PATH"
echo "This is not Developer ID signing and the app has not been notarized."
