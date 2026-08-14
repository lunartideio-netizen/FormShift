#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

for script in Scripts/*.sh; do
    bash -n "$script"
done
plutil -lint Scripts/Info.plist Scripts/FormShift.entitlements

if find . \
    -path './.build' -prune -o \
    -path './Artifacts' -prune -o \
    -path './dist' -prune -o \
    -type f \( -name '*.p12' -o -name '*.mobileprovision' -o -name '*.cer' -o -name '*.key' \) \
    -print | grep -q .; then
    echo "error: repository contains a release credential file" >&2
    exit 65
fi

if find . \
    -path './.build' -prune -o \
    -path './Artifacts' -prune -o \
    -path './dist' -prune -o \
    -type f \( -name ffmpeg -o -name ffprobe \) \
    -print | grep -q .; then
    echo "error: repository contains an FFmpeg executable" >&2
    exit 65
fi

swift build
if [[ "${SKIP_TESTS:-0}" == "1" ]]; then
    echo "warning: tests skipped by explicit SKIP_TESTS=1"
else
    swift test
fi

echo "Repository checks passed. This does not prove UI behavior, media conversion, signing, or notarization."
