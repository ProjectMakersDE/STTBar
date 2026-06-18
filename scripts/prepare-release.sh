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

# Stage the backend scripts in install-ready layout (stt-global.sh = macOS
# variant) so the in-app updater can extract them straight into the install dir.
SCRIPTS_STAGE="$DIST/scripts-stage"
rm -rf "$SCRIPTS_STAGE"
mkdir -p "$SCRIPTS_STAGE"
cp "$ROOT/stt.zsh" "$ROOT/stt-runtime.sh" "$ROOT/stt-record.sh" \
   "$ROOT/stt-transcribe.sh" "$ROOT/stt-postprocess.sh" \
   "$ROOT/stt-replacements.tsv" "$ROOT/docker-compose.yml" \
   "$ROOT/.env.example" "$SCRIPTS_STAGE/"
cp "$ROOT/stt-global-mac.sh" "$SCRIPTS_STAGE/stt-global.sh"
chmod +x "$SCRIPTS_STAGE"/*.sh
( cd "$SCRIPTS_STAGE" && ditto -c -k --sequesterRsrc . "$DIST/stt-scripts.zip" )
shasum -a 256 "$DIST/stt-scripts.zip" | awk '{print $1}' > "$DIST/stt-scripts.zip.sha256"
rm -rf "$SCRIPTS_STAGE"
