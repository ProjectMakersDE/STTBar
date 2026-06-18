#!/usr/bin/env bash
# setup-signing-cert.sh — ensure a STABLE self-signed code-signing identity for
# STTBar exists in the login keychain.
#
# Why this exists: macOS TCC (Accessibility / Automation) ties a permission grant
# to the app's *Designated Requirement*. For an ad-hoc signed bundle the DR is
# anchored to the cdhash, which changes on EVERY rebuild — so the Accessibility
# grant (needed for the ⌘V paste keystroke) is lost on every rebuild and the user
# has to re-grant it. Signing with a stable certificate anchors the DR to the
# *certificate leaf* instead, so the grant survives rebuilds and the user grants
# it exactly once.
#
# Idempotent. Safe to run on every build:
#   1. identity already in keychain          -> reuse (no-op)
#   2. backup .p12 exists                     -> re-import the SAME cert (same DR)
#   3. neither                                -> generate a new cert + back it up
#
# Prints progress to stderr; the identity name is the script's contract with
# build-app.sh (which signs with "$CERT_CN"). Exit 0 = identity is ready.
set -euo pipefail

CERT_CN="STTBar Code Signing"
LOGIN_KC="$HOME/Library/Keychains/login.keychain-db"
BACKUP_DIR="$HOME/Library/Application Support/STTBar"
BACKUP_P12="$BACKUP_DIR/stt-signing.p12"
# Low-value password for a LOCAL self-signed dev cert. The private key never
# leaves this machine and the cert grants no trust beyond signing STTBar.app.
P12_PASS="sttbar"

log() { printf '%s\n' "$*" >&2; }

identity_present() {
    security find-identity -v -p codesigning 2>/dev/null | grep -qF "$CERT_CN"
}

import_p12() {
    # -A: allow any app to use the key without an ACL prompt (login keychain is
    # already unlocked during a user session, so no password is needed at build
    # time). Trust the cert for code signing so it lists under `-v` / codesign.
    local p12="$1"
    security import "$p12" -k "$LOGIN_KC" -P "$P12_PASS" -A >/dev/null 2>&1
    security add-trusted-cert -p codeSign -k "$LOGIN_KC" \
        <(openssl pkcs12 -in "$p12" -passin "pass:$P12_PASS" -clcerts -nokeys -legacy 2>/dev/null \
            || openssl pkcs12 -in "$p12" -passin "pass:$P12_PASS" -clcerts -nokeys 2>/dev/null) \
        >/dev/null 2>&1 || true
}

# 1) Already in the keychain → nothing to do.
if identity_present; then
    log "Signing identity present: $CERT_CN"
    printf '%s\n' "$CERT_CN"
    exit 0
fi

# 2) Restore the SAME cert from backup so the Designated Requirement is unchanged
#    (no re-grant needed).
if [[ -f "$BACKUP_P12" ]]; then
    log "Restoring signing identity from backup: $BACKUP_P12"
    import_p12 "$BACKUP_P12"
    if identity_present; then
        log "Restored: $CERT_CN"
        printf '%s\n' "$CERT_CN"
        exit 0
    fi
    log "WARN: restore from backup did not yield a valid identity; regenerating."
fi

# 3) Generate a fresh self-signed code-signing certificate (10-year validity).
command -v openssl >/dev/null 2>&1 || { log "ERROR: openssl not found."; exit 1; }
log "Generating a new self-signed code-signing certificate: $CERT_CN"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CERT_CN
[v3]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -config "$WORK/cert.cnf" >/dev/null 2>&1

# OpenSSL 3.x writes PKCS#12 with a MAC/cipher the macOS Security framework
# cannot import (it misreports "wrong password"); force legacy algorithms.
# LibreSSL (the /usr/bin/openssl on macOS) already writes a compatible .p12 and
# does not understand -legacy, so only add the flags for real OpenSSL.
p12_args=(-export -inkey "$WORK/key.pem" -in "$WORK/cert.pem"
          -out "$WORK/cert.p12" -passout "pass:$P12_PASS" -name "$CERT_CN")
if ! openssl version 2>/dev/null | grep -qi libressl; then
    p12_args+=(-legacy -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES)
fi
openssl pkcs12 "${p12_args[@]}" >/dev/null 2>&1

mkdir -p "$BACKUP_DIR"
cp "$WORK/cert.p12" "$BACKUP_P12"
chmod 600 "$BACKUP_P12"
log "Backed up new cert to: $BACKUP_P12"

import_p12 "$BACKUP_P12"
if identity_present; then
    log "Created signing identity: $CERT_CN"
    printf '%s\n' "$CERT_CN"
    exit 0
fi

log "ERROR: failed to create a usable code-signing identity."
exit 1
