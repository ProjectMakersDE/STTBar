#!/usr/bin/env bash
# Builds the Mac App Store package: STTBar.app compiled with -DAPPSTORE, signed
# with the Apple Distribution identity and the Mac App Store provisioning
# profile, wrapped in a signed installer package for upload with Transporter.
#
# Usage: build-appstore.sh <profile.provisionprofile> [dest-dir]
#
# Needs in the login keychain:
#   - "Apple Distribution: …"          (signs the app)
#   - "3rd Party Mac Developer Installer: …" or "Mac Installer Distribution: …"
#                                      (signs the package)
# Optional environment:
#   STT_APPSTORE_APP_IDENTITY, STT_APPSTORE_INSTALLER_IDENTITY  override the
#       identities found in the keychain
#   STT_BUILD_NUMBER  CFBundleVersion for this upload; every upload needs a
#       higher number than the one before
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="${1:?Usage: build-appstore.sh <profile.provisionprofile> [dest-dir]}"
DEST="${2:-$HERE/../dist-appstore}"
APP="$DEST/STTBar.app"
BUNDLE_ID="de.projectmakers.sttbar"

[[ -f "$PROFILE" ]] || { echo "ERROR: provisioning profile not found: $PROFILE" >&2; exit 1; }

APP_IDENTITY="${STT_APPSTORE_APP_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Distribution/{print $2; exit}')}"
INSTALLER_IDENTITY="${STT_APPSTORE_INSTALLER_IDENTITY:-$(security find-identity -v | awk -F'"' '/3rd Party Mac Developer Installer|Mac Installer Distribution/{print $2; exit}')}"
[[ -n "$APP_IDENTITY" ]] || { echo "ERROR: no Apple Distribution identity in the keychain." >&2; exit 1; }
[[ -n "$INSTALLER_IDENTITY" ]] || { echo "ERROR: no Mac installer distribution identity in the keychain." >&2; exit 1; }

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# The profile decides the team and the application identifier the signature
# must carry. A profile for another bundle id would fail App Store validation.
security cms -D -i "$PROFILE" > "$TMPD/profile.plist"
TEAM_ID="$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$TMPD/profile.plist")"
APP_ID="$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$TMPD/profile.plist")"
if [[ "$APP_ID" != "$TEAM_ID.$BUNDLE_ID" ]]; then
    echo "ERROR: profile is for '$APP_ID', expected '$TEAM_ID.$BUNDLE_ID'." >&2
    exit 1
fi

rm -rf "$DEST"
STT_APPSTORE=1 bash "$HERE/build-app.sh" "$DEST"

if [[ -n "${STT_BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $STT_BUILD_NUMBER" "$APP/Contents/Info.plist"
fi

cp "$HERE/Resources/STTBar.entitlements" "$TMPD/appstore.entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" "$TMPD/appstore.entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$TMPD/appstore.entitlements"

cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
# A profile downloaded with a browser carries com.apple.quarantine, and the
# App Store rejects any file with that attribute (ITMS 91109). Clear all
# extended attributes before signing.
xattr -cr "$APP"
if xattr -r "$APP" 2>/dev/null | grep -q com.apple.quarantine; then
    echo "ERROR: com.apple.quarantine is still set inside $APP." >&2
    exit 1
fi
codesign --force --options runtime --timestamp \
    --entitlements "$TMPD/appstore.entitlements" --sign "$APP_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

productbuild --component "$APP" /Applications --sign "$INSTALLER_IDENTITY" "$DEST/STTBar.pkg"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")"
echo "Built $DEST/STTBar.pkg (version $VERSION, build $BUILD). Upload it with Transporter."
