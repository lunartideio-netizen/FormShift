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
    echo "error: release packaging requires Apple Silicon macOS" >&2
    exit 69
}

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
[[ "$DEVELOPER_DIR" == *Xcode.app/Contents/Developer* ]] || {
    echo "error: full Xcode is required; Command Line Tools alone are insufficient" >&2
    exit 69
}

cd "$PROJECT_DIR"
swift build -c release --arch arm64 --product FormShift
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
EXECUTABLE="$BIN_DIR/FormShift"
[[ -x "$EXECUTABLE" ]] || {
    echo "error: release executable not found: $EXECUTABLE" >&2
    exit 70
}

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$SCRIPT_DIR/Info.plist" "$APP_PATH/Contents/Info.plist"
cp "$EXECUTABLE" "$APP_PATH/Contents/MacOS/FormShift"
[[ -f "$PROJECT_DIR/Assets/AppIcon/FormShift.icns" ]] || "$SCRIPT_DIR/build-app-icon.sh"
cp "$PROJECT_DIR/Assets/AppIcon/FormShift.icns" "$APP_PATH/Contents/Resources/FormShift.icns"
mkdir -p "$APP_PATH/Contents/Resources/Licenses"
cp "$PROJECT_DIR/LICENSE" "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$PROJECT_DIR/PRIVACY.md" \
    "$APP_PATH/Contents/Resources/Licenses/"

while IFS= read -r -d '' bundle; do
    ditto "$bundle" "$APP_PATH/Contents/Resources/$(basename "$bundle")"
done < <(find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -print0)

FFMPEG_ARTIFACTS="$PROJECT_DIR/Artifacts/FFmpeg/bin"
if [[ -x "$FFMPEG_ARTIFACTS/ffmpeg" && -x "$FFMPEG_ARTIFACTS/ffprobe" ]]; then
    mkdir -p "$APP_PATH/Contents/Helpers"
    cp "$FFMPEG_ARTIFACTS/ffmpeg" "$FFMPEG_ARTIFACTS/ffprobe" "$APP_PATH/Contents/Helpers/"
    mkdir -p "$APP_PATH/Contents/Resources/Licenses/FFmpeg"
    cp "$PROJECT_DIR/Artifacts/FFmpeg/compliance/build-manifest.txt" \
        "$PROJECT_DIR/Artifacts/FFmpeg/compliance/ffmpeg.lock" \
        "$APP_PATH/Contents/Resources/Licenses/FFmpeg/"
elif [[ "${REQUIRE_FFMPEG:-0}" == "1" ]]; then
    echo "error: REQUIRE_FFMPEG=1 but verified FFmpeg artifacts are missing" >&2
    exit 66
else
    echo "warning: packaging a development app without bundled FFmpeg"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION:-0.3.0-dev}" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP_PATH/Contents/Info.plist"
plutil -lint "$APP_PATH/Contents/Info.plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    SIGN_OPTIONS=(--force --sign "$CODESIGN_IDENTITY")
    if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
        SIGN_OPTIONS+=(--options runtime --timestamp)
    fi
    if [[ -d "$APP_PATH/Contents/Helpers" ]]; then
        for helper in "$APP_PATH"/Contents/Helpers/*; do
            codesign "${SIGN_OPTIONS[@]}" "$helper"
        done
    fi
    codesign "${SIGN_OPTIONS[@]}" --entitlements "$SCRIPT_DIR/FormShift.entitlements" "$APP_PATH"
    codesign --verify --deep --strict --verbose=2 "$APP_PATH"
    if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
        echo "Created ad-hoc signed local app: $APP_PATH"
        echo "Ad-hoc signing is not Developer ID signing and is not suitable evidence of notarization."
    else
        echo "Created signed app: $APP_PATH"
        echo "This script did not submit or verify Apple notarization."
    fi
else
    echo "Created unsigned development app: $APP_PATH"
    echo "No signing or notarization was performed."
fi
