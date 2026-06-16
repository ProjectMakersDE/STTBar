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

# Ad-hoc sign so the bundle is valid static code — TCC (Accessibility /
# Microphone) tracks a signed bundle more reliably than an unsigned one.
codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
    && echo "Signed (ad-hoc): $APP" || echo "WARN: ad-hoc signing failed (continuing)"

echo "Built $APP"
