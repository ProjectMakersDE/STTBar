#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:?Usage: prepare-release.sh <version>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/macos-app/Resources/Info.plist"
BUILD="${GITHUB_RUN_NUMBER:-1}"
DIST="$ROOT/dist"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"

rm -rf "$DIST"
mkdir -p "$DIST"
bash "$ROOT/macos-app/build-app.sh" "$DIST"
ditto -c -k --sequesterRsrc --keepParent "$DIST/STTBar.app" "$DIST/STTBar.app.zip"
shasum -a 256 "$DIST/STTBar.app.zip" | awk '{print $1}' > "$DIST/STTBar.app.zip.sha256"
