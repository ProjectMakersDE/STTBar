#!/usr/bin/env bash
# Builds STTBar and assembles a .app bundle. Usage: build-app.sh [dest-dir]
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:-$HOME/Applications}"
APP="$DEST/STTBar.app"

swift build -c release --package-path "$HERE"
BIN="$(swift build -c release --package-path "$HERE" --show-bin-path)/STTBar"

mkdir -p "$DEST"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/STTBar"
cp "$HERE/Resources/Info.plist" "$APP/Contents/Info.plist"
echo "Built $APP"
