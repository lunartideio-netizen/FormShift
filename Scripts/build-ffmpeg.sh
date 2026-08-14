#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOCK_FILE="$SCRIPT_DIR/ffmpeg.lock"

usage() {
    echo "Usage: $0 /absolute/path/to/ffmpeg-source.tar.xz /absolute/output/directory" >&2
    exit 64
}

[[ $# -eq 2 ]] || usage
SOURCE_ARCHIVE="$1"
OUTPUT_DIR="$2"

[[ "$SOURCE_ARCHIVE" = /* && "$OUTPUT_DIR" = /* ]] || {
    echo "error: source archive and output directory must be absolute paths" >&2
    exit 64
}
[[ -f "$SOURCE_ARCHIVE" ]] || {
    echo "error: source archive does not exist: $SOURCE_ARCHIVE" >&2
    exit 66
}
[[ ! -e "$OUTPUT_DIR" ]] || {
    echo "error: refusing to overwrite existing output: $OUTPUT_DIR" >&2
    exit 73
}
[[ -f "$LOCK_FILE" ]] || {
    echo "error: missing lock file: $LOCK_FILE" >&2
    exit 66
}

# shellcheck disable=SC1090
source "$LOCK_FILE"
for value in \
    FFMPEG_VERSION \
    FFMPEG_SOURCE_URL \
    FFMPEG_SOURCE_SIGNATURE_URL \
    FFMPEG_SOURCE_SIGNING_FINGERPRINT \
    FFMPEG_SOURCE_SHA256; do
    [[ -n "${!value:-}" && "${!value}" != REPLACE_* ]] || {
        echo "error: $value must be pinned in Scripts/ffmpeg.lock before building" >&2
        exit 78
    }
done

for tool in make shasum tar xcrun; do
    command -v "$tool" >/dev/null || {
        echo "error: required tool not found: $tool" >&2
        exit 69
    }
done

ACTUAL_SHA256="$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL_SHA256" == "$FFMPEG_SOURCE_SHA256" ]] || {
    echo "error: FFmpeg source SHA-256 mismatch" >&2
    echo "expected: $FFMPEG_SOURCE_SHA256" >&2
    echo "actual:   $ACTUAL_SHA256" >&2
    exit 65
}

[[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]] || {
    echo "error: this release build is restricted to Apple Silicon macOS" >&2
    exit 69
}

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/formshift-ffmpeg.XXXXXX")"
cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

mkdir -p "$WORK_DIR/source" "$WORK_DIR/prefix"
tar -xf "$SOURCE_ARCHIVE" -C "$WORK_DIR/source"
SOURCE_DIR="$(find "$WORK_DIR/source" -mindepth 1 -maxdepth 1 -type d -print -quit)"
[[ -n "$SOURCE_DIR" && -x "$SOURCE_DIR/configure" ]] || {
    echo "error: archive does not contain one FFmpeg source directory" >&2
    exit 65
}

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
CLANG_PATH="$(xcrun --sdk macosx --find clang)"
MINIMUM_MACOS="15.0"
CONFIGURE_ARGS=(
    "--prefix=$WORK_DIR/prefix"
    "--cc=$CLANG_PATH"
    "--host-cc=$CLANG_PATH"
    "--host-cflags=-isysroot $SDK_PATH -mmacosx-version-min=$MINIMUM_MACOS"
    "--host-ldflags=-isysroot $SDK_PATH -mmacosx-version-min=$MINIMUM_MACOS"
    "--arch=arm64"
    "--target-os=darwin"
    "--extra-cflags=-arch arm64 -mmacosx-version-min=$MINIMUM_MACOS -isysroot $SDK_PATH"
    "--extra-ldflags=-arch arm64 -mmacosx-version-min=$MINIMUM_MACOS -isysroot $SDK_PATH"
    "--enable-gpl"
    "--enable-version3"
    "--enable-static"
    "--disable-shared"
    "--disable-debug"
    "--disable-doc"
    "--disable-ffplay"
    "--disable-network"
    "--disable-autodetect"
    "--enable-audiotoolbox"
    "--enable-videotoolbox"
)

pushd "$SOURCE_DIR" >/dev/null
./configure "${CONFIGURE_ARGS[@]}"
make -j "$(sysctl -n hw.logicalcpu)"
make install
popd >/dev/null

mkdir -p "$OUTPUT_DIR/bin" "$OUTPUT_DIR/compliance"
for executable in ffmpeg ffprobe; do
    [[ -x "$WORK_DIR/prefix/bin/$executable" ]] || {
        echo "error: expected executable was not built: $executable" >&2
        exit 70
    }
    ARCHS="$(lipo -archs "$WORK_DIR/prefix/bin/$executable")"
    [[ "$ARCHS" == "arm64" ]] || {
        echo "error: $executable has unexpected architectures: $ARCHS" >&2
        exit 70
    }
    cp "$WORK_DIR/prefix/bin/$executable" "$OUTPUT_DIR/bin/$executable"
done

{
    echo "FormShift FFmpeg build manifest"
    echo "source_version=$FFMPEG_VERSION"
    echo "source_url=$FFMPEG_SOURCE_URL"
    echo "source_signature_url=$FFMPEG_SOURCE_SIGNATURE_URL"
    echo "source_signing_fingerprint=$FFMPEG_SOURCE_SIGNING_FINGERPRINT"
    echo "source_sha256=$FFMPEG_SOURCE_SHA256"
    echo "minimum_macos=$MINIMUM_MACOS"
    echo "sdk_path=$SDK_PATH"
    echo "clang=$($CLANG_PATH --version | head -n 1)"
    printf 'configure='
    printf '%q ' "${CONFIGURE_ARGS[@]}"
    printf '\n\n'
    "$OUTPUT_DIR/bin/ffmpeg" -version
    "$OUTPUT_DIR/bin/ffmpeg" -buildconf
} > "$OUTPUT_DIR/compliance/build-manifest.txt" 2>&1

cp "$LOCK_FILE" "$OUTPUT_DIR/compliance/ffmpeg.lock"
echo "Built local FFmpeg tools at: $OUTPUT_DIR"
echo "This output is unsigned and has not been notarized. Complete the release compliance checklist before distribution."
