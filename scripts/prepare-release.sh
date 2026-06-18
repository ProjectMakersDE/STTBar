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

# Notarize + staple when App Store Connect API credentials are present (CI).
# Stapling must happen before the release zip is created so the ticket ships
# inside the bundle. Without credentials this is skipped (self-signed/ad-hoc dev
# build). A rejected notarization fails the release on purpose.
if [[ -n "${MACOS_NOTARY_KEY_P8_BASE64:-}" && -n "${MACOS_NOTARY_KEY_ID:-}" && -n "${MACOS_NOTARY_ISSUER_ID:-}" ]]; then
    printf '%s' "$MACOS_NOTARY_KEY_P8_BASE64" | base64 --decode > "$DIST/notary.p8"
    ditto -c -k --keepParent "$DIST/STTBar.app" "$DIST/notarize.zip"
    xcrun notarytool submit "$DIST/notarize.zip" \
        --key "$DIST/notary.p8" --key-id "$MACOS_NOTARY_KEY_ID" --issuer "$MACOS_NOTARY_ISSUER_ID" \
        --wait
    xcrun stapler staple "$DIST/STTBar.app"
    rm -f "$DIST/notary.p8" "$DIST/notarize.zip"
    echo "Notarized + stapled STTBar.app"
else
    echo "Notary credentials absent — skipping notarization (dev build)."
fi

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
