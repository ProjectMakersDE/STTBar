#!/usr/bin/env bash
# A release build must NEVER silently fall back to a self-signed or ad-hoc
# signature. A changed signing identity changes the Designated Requirement,
# which makes macOS treat the update as a different app and drops every TCC
# grant (Accessibility, Microphone). So when STT_REQUIRE_DEVELOPER_ID=1 and no
# Developer ID cert is available, build-app.sh must FAIL instead of shipping a
# permission-breaking build.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Stub the heavy/host-specific tools so the script reaches the signing logic
# fast and deterministically: a no-op `swift` that reports a bin path, a no-op
# `codesign`, and a `setup-signing-cert.sh` that would (wrongly) offer a
# self-signed identity. With Developer ID required, none of these may win.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/swift" <<EOF
#!/usr/bin/env bash
if [[ "\${*}" == *"--show-bin-path"* ]]; then echo "$tmp/swiftbin"; fi
exit 0
EOF
mkdir -p "$tmp/swiftbin"; : > "$tmp/swiftbin/STTBar"
cat > "$tmp/bin/codesign" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/bin/swift" "$tmp/bin/codesign"

# Isolated copy of the build script + resources it reads.
mkdir -p "$tmp/app/Resources"
cp "$ROOT/macos-app/build-app.sh" "$tmp/app/"
cp "$ROOT/macos-app/Resources/Info.plist" "$tmp/app/Resources/Info.plist" 2>/dev/null || \
  printf '<?xml version="1.0"?><plist version="1.0"><dict/></plist>' > "$tmp/app/Resources/Info.plist"
cp "$ROOT/macos-app/Resources/STTBar.entitlements" "$tmp/app/Resources/STTBar.entitlements" 2>/dev/null || \
  printf '<?xml version="1.0"?><plist version="1.0"><dict/></plist>' > "$tmp/app/Resources/STTBar.entitlements"
cp "$ROOT/macos-app/Resources/PrivacyInfo.xcprivacy" "$tmp/app/Resources/PrivacyInfo.xcprivacy" 2>/dev/null || \
  printf '<?xml version="1.0"?><plist version="1.0"><dict/></plist>' > "$tmp/app/Resources/PrivacyInfo.xcprivacy"
# A setup-signing-cert.sh that would hand back a self-signed identity name.
cat > "$tmp/app/setup-signing-cert.sh" <<'EOF'
#!/usr/bin/env bash
echo "STTBar Code Signing"
EOF
chmod +x "$tmp/app/setup-signing-cert.sh"

rc=0
PATH="$tmp/bin:$PATH" STT_REQUIRE_DEVELOPER_ID=1 \
    bash "$tmp/app/build-app.sh" "$tmp/dest" >"$tmp/out.log" 2>&1 || rc=$?

if [[ "$rc" -eq 0 ]]; then
    echo "FAIL: release build succeeded without a Developer ID identity"
    cat "$tmp/out.log"
    exit 1
fi
if ! grep -qi "developer id" "$tmp/out.log"; then
    echo "FAIL: failure message did not mention the missing Developer ID requirement"
    cat "$tmp/out.log"
    exit 1
fi
echo "PASS release-requires-developer-id"
