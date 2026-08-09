#!/bin/zsh

set -euo pipefail

IDENTITY_NAME="${CLIPALL_SIGNING_IDENTITY:-ClipAll Local Development}"
KEYCHAIN_PATH="${CLIPALL_KEYCHAIN_PATH:-$HOME/Library/Keychains/login.keychain-db}"

if [[ -x /opt/homebrew/bin/openssl ]]; then
  OPENSSL_BIN=/opt/homebrew/bin/openssl
else
  OPENSSL_BIN="$(command -v openssl)"
fi

find_identity_hash() {
  security find-identity -v -p codesigning "$KEYCHAIN_PATH" 2>/dev/null \
    | awk -v name="$IDENTITY_NAME" 'index($0, "\"" name "\"") { print $2; exit }'
}

if [[ -n "$(find_identity_hash)" ]]; then
  print "Local signing identity already available: $IDENTITY_NAME"
  exit 0
fi

TEMP_DIR="$(mktemp -d /private/tmp/clipall-local-signing.XXXXXX)"
trap 'rm -rf -- "$TEMP_DIR"' EXIT
umask 077

CERTIFICATE_PATH="$TEMP_DIR/ClipAll-Local.crt"

if security find-certificate -c "$IDENTITY_NAME" -p "$KEYCHAIN_PATH" \
  > "$CERTIFICATE_PATH" 2>/dev/null && [[ -s "$CERTIFICATE_PATH" ]]; then
  print "Found an existing certificate; refreshing its code-signing trust…"
else
  PRIVATE_KEY_PATH="$TEMP_DIR/ClipAll-Local.key"
  PKCS12_PATH="$TEMP_DIR/ClipAll-Local.p12"
  IMPORT_PASSWORD="$(uuidgen | tr -d '-')"

  "$OPENSSL_BIN" req \
    -new \
    -x509 \
    -sha256 \
    -days 3650 \
    -newkey rsa:3072 \
    -nodes \
    -keyout "$PRIVATE_KEY_PATH" \
    -out "$CERTIFICATE_PATH" \
    -subj "/CN=$IDENTITY_NAME/O=ClipAll Local Development" \
    -addext 'basicConstraints=critical,CA:TRUE' \
    -addext 'keyUsage=critical,digitalSignature,keyCertSign' \
    -addext 'extendedKeyUsage=critical,codeSigning'

  "$OPENSSL_BIN" pkcs12 \
    -export \
    -legacy \
    -inkey "$PRIVATE_KEY_PATH" \
    -in "$CERTIFICATE_PATH" \
    -out "$PKCS12_PATH" \
    -name "$IDENTITY_NAME" \
    -passout "pass:$IMPORT_PASSWORD"

  security import "$PKCS12_PATH" \
    -k "$KEYCHAIN_PATH" \
    -f pkcs12 \
    -P "$IMPORT_PASSWORD" \
    -x \
    -T /usr/bin/codesign \
    -T /usr/bin/security
fi

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN_PATH" \
  "$CERTIFICATE_PATH"

IDENTITY_HASH="$(find_identity_hash)"
if [[ -z "$IDENTITY_HASH" ]]; then
  print -u2 "Unable to create a valid code-signing identity: $IDENTITY_NAME"
  print -u2 "Open Keychain Access and confirm that the certificate and private key are present."
  exit 1
fi

print "Local signing identity is ready: $IDENTITY_NAME ($IDENTITY_HASH)"
print "Future builds can reuse the current Accessibility permission."
