#!/bin/bash
# Creates a stable, self-signed code-signing identity in the login keychain.
#
# A stable identity keeps macOS Screen Recording approval across rebuilds.
# Ad-hoc signing changes identity every build, so macOS treats each build as a
# new app. Run this once, then ./scripts/build.sh picks it up automatically.
set -euo pipefail

NAME="${1:-VibeShot Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
SSL=/usr/bin/openssl

if [[ ! -x "$SSL" ]]; then
  echo "Missing $SSL" >&2
  exit 1
fi

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  echo "Signing identity '$NAME' already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The system OpenSSL (LibreSSL) is used deliberately: a newer Homebrew OpenSSL
# writes a PKCS#12 that macOS `security import` rejects with a MAC error.
"$SSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

"$SSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/identity.p12" -passout pass:vibeshot

# -T grants codesign access without a keychain prompt.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P vibeshot \
  -T /usr/bin/codesign -T /usr/bin/security

echo "Created signing identity '$NAME' in the login keychain."
echo "Rebuild with: ./scripts/build.sh"
