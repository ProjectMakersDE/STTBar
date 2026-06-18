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

COMMIT="unknown"
if command -v git >/dev/null 2>&1 && git -C "$HERE/.." rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    COMMIT="$(git -C "$HERE/.." rev-parse --short HEAD 2>/dev/null || echo unknown)"
fi
VERSION="unknown"
BUILD="unknown"
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
    BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
fi
printf 'version=%s\nbuild=%s\ncommit=%s\nbuilt_at=%s\n' "$VERSION" "$BUILD" "$COMMIT" "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$APP/Contents/Resources/version.txt"
if command -v /usr/libexec/PlistBuddy >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Delete :STTGitCommit" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :STTGitCommit string $COMMIT" "$APP/Contents/Info.plist" >/dev/null 2>&1 || true
fi

ENTITLEMENTS="$HERE/Resources/STTBar.entitlements"
IDENTITY=""

# 1) Release path: a Developer ID Application cert supplied via env (CI secrets
#    MACOS_CERT_P12_BASE64 + MACOS_CERT_PASSWORD). Sign with Hardened Runtime +
#    entitlements + a secure timestamp so the build can be notarized. The
#    Developer ID Designated Requirement is anchored to the Apple Team ID, so
#    TCC grants (Accessibility / microphone) survive every future update.
if [[ -n "${MACOS_CERT_P12_BASE64:-}" ]]; then
    TMPD="${RUNNER_TEMP:-$(mktemp -d)}"
    KEYCHAIN="$TMPD/sttbar-signing.keychain-db"
    KP="sttbar-$$-${RANDOM}"
    printf '%s' "$MACOS_CERT_P12_BASE64" | base64 --decode > "$TMPD/sttbar-cert.p12"
    security create-keychain -p "$KP" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$KP" "$KEYCHAIN"
    security import "$TMPD/sttbar-cert.p12" -k "$KEYCHAIN" -P "${MACOS_CERT_PASSWORD:-}" -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KP" "$KEYCHAIN" >/dev/null 2>&1 || true
    # Put the temp keychain on the search list so codesign can find the identity.
    security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | sed s/\"//g)
    IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'"' '/Developer ID Application/{print $2; exit}')"
    rm -f "$TMPD/sttbar-cert.p12"
    if [[ -n "$IDENTITY" ]]; then
        if codesign --force --options runtime --timestamp \
                --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP"; then
            echo "Signed (Developer ID + hardened runtime): $IDENTITY"
        else
            echo "WARN: Developer ID signing failed."
            IDENTITY=""
        fi
    else
        echo "WARN: no Developer ID Application identity found in the provided cert."
    fi
fi

# 2) Local/dev path: a STABLE self-signed identity so the Designated Requirement
#    is anchored to the certificate (not the cdhash); TCC grants survive local
#    rebuilds. Used when no Developer ID cert is supplied.
if [[ -z "$IDENTITY" ]] && IDENTITY="$(bash "$HERE/setup-signing-cert.sh" 2>/dev/null | tail -1)" && [[ -n "$IDENTITY" ]]; then
    if codesign --force --sign "$IDENTITY" --timestamp=none "$APP" >/dev/null 2>&1; then
        echo "Signed (stable identity): $IDENTITY"
    else
        echo "WARN: signing with '$IDENTITY' failed; falling back to ad-hoc."
        IDENTITY=""
    fi
fi

# 3) Last resort: ad-hoc (cdhash-anchored; grant lost on every rebuild).
if [[ -z "$IDENTITY" ]]; then
    codesign --force --sign - --timestamp=none "$APP" >/dev/null 2>&1 \
        && echo "Signed (ad-hoc — grant will be lost on next rebuild): $APP" \
        || echo "WARN: ad-hoc signing failed (continuing)"
fi

echo "Built $APP"
