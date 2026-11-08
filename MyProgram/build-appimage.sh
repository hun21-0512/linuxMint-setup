#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_APPDIR="$SCRIPT_DIR/AppDir"
OUTPUT_DIR="$SCRIPT_DIR/dist"
LINUXDEPLOY="${LINUXDEPLOY:-linuxdeploy}"

if ! command -v "$LINUXDEPLOY" >/dev/null 2>&1; then
    printf 'linuxdeploy was not found. Install linuxdeploy with the GTK and AppImage plugins.\n' >&2
    exit 1
fi
if ! command -v zenity >/dev/null 2>&1; then
    printf 'zenity must be installed on the build host so it can be bundled.\n' >&2
    exit 1
fi

BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT
STAGED_APPDIR="$BUILD_DIR/AppDir"
mkdir -p "$OUTPUT_DIR"
cp -a "$SOURCE_APPDIR" "$STAGED_APPDIR"

(
    cd "$OUTPUT_DIR"
    "$LINUXDEPLOY" \
        --appdir "$STAGED_APPDIR" \
        --executable "$(readlink -f "$(command -v zenity)")" \
        --desktop-file "$STAGED_APPDIR/myprogram.desktop" \
        --icon-file "$STAGED_APPDIR/usr/share/icons/hicolor/scalable/apps/myprogram.svg" \
        --plugin gtk \
        --output appimage
)