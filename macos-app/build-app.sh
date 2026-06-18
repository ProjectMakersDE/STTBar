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

# Sign with a STABLE self-signed identity so the Designated Requirement is
# anchored to the certificate (not the cdhash). TCC (Accessibility / Automation)
# grants survive rebuilds, so the user only grants the ⌘V paste permission once.
# Falls back to ad-hoc (cdhash-anchored, lost on every rebuild) if the identity
# can't be set up — e.g. openssl missing.
IDENTITY=""
if IDENTITY="$(bash "$HERE/setup-signing-cert.sh" 2>/dev/null | tail -1)" && [[ -n "$IDENTITY" ]]; then
    if codesign --force --sign "$IDENTITY" --timestamp=none "$APP" >/dev/null 2>&1; then
        echo "Signed (stable identity): $IDENTITY"
    else
        echo "WARN: signing with '$IDENTITY' failed; falling back to ad-hoc."
        IDENTITY=""
    fi
fi
if [[ -z "$IDENTITY" ]]; then
    codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
        && echo "Signed (ad-hoc — grant will be lost on next rebuild): $APP" \
        || echo "WARN: ad-hoc signing failed (continuing)"
fi

echo "Built $APP"
