#!/usr/bin/env bash
# Build + codesign with a stable self-signed identity. SHA-1 of the cert is
# pinned in cert-sha1.txt so codesign never matches by ambiguous name.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IDENTITY="ClaudeMeter Dev"
DATA_DIR="$HOME/Library/Application Support/ClaudeMeter"
KEY_PATH="$DATA_DIR/dev-signing.key"
CRT_PATH="$DATA_DIR/dev-signing.crt"
P12_PATH="$DATA_DIR/dev-signing.p12"
CFG_PATH="$DATA_DIR/dev-signing.cnf"
HASH_FILE="$DATA_DIR/cert-sha1.txt"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

mkdir -p "$DATA_DIR"

cert_in_keychain() {
  security find-certificate -a -c "$IDENTITY" -Z 2>/dev/null \
    | awk '/^SHA-1 hash:/ {print toupper($3)}' \
    | grep -qx "$1"
}

ensure_identity() {
  if [[ -f "$HASH_FILE" ]]; then
    local hash="$(cat "$HASH_FILE")"
    if cert_in_keychain "$hash"; then
      echo "Using pinned ClaudeMeter Dev cert ($hash)"
      return 0
    fi
    echo "Pinned cert no longer in keychain; regenerating."
  fi

  echo "Creating self-signed code-signing identity '$IDENTITY'…"
  cat > "$CFG_PATH" <<'CFG'
[req]
distinguished_name = dn
x509_extensions = v3_req
prompt = no
[dn]
CN = ClaudeMeter Dev
[v3_req]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
CFG

  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$KEY_PATH" -out "$CRT_PATH" \
    -days 3650 -config "$CFG_PATH" >/dev/null 2>&1

  openssl pkcs12 -export -legacy -inkey "$KEY_PATH" -in "$CRT_PATH" \
    -out "$P12_PATH" -name "$IDENTITY" -passout pass:tmp >/dev/null 2>&1

  security import "$P12_PATH" -k "$KEYCHAIN" -P "tmp" \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

  security set-key-partition-list -S apple-tool:,apple: \
    -k "$(security default-keychain | tr -d ' "')" "$KEYCHAIN" >/dev/null 2>&1 || true

  # Pin the SHA-1 of the cert we just installed.
  local sha
  sha="$(openssl x509 -in "$CRT_PATH" -outform DER | shasum | awk '{print toupper($1)}')"
  echo "$sha" > "$HASH_FILE"

  rm -f "$P12_PATH" "$CFG_PATH"
  echo "Identity created. Cert SHA-1 pinned: $sha"
}

ensure_identity
HASH="$(cat "$HASH_FILE")"

cd "$PROJECT_ROOT"
swift build "$@"

BIN="$PROJECT_ROOT/.build/debug/claudometer"
[[ -x "$BIN" ]] || BIN="$PROJECT_ROOT/.build/release/claudometer"

# Sign by SHA-1 (unambiguous even with duplicate-name certs).
# --identifier "ClaudeMeter" pins the codesign identifier to the legacy name
# so the keychain ACL set against the original-named binary keeps recognizing
# rebuilds after the executable rename to "claudometer".
codesign --force --sign "$HASH" --identifier "ClaudeMeter" --timestamp=none "$BIN"

# Hard-fail if signature isn't a real cert signature
REQ="$(codesign -d -r- "$BIN" 2>&1 | awk -F'=> ' '/designated =>/ {print $2}')"
if [[ "$REQ" != *"certificate leaf = H"* ]]; then
  echo "FATAL: codesign fell back to ad-hoc — designated requirement is: $REQ" >&2
  exit 1
fi

codesign --verify --verbose=2 "$BIN" 2>&1 | sed 's/^/  /'
echo "Built and signed: $BIN"
echo "Designated requirement: $REQ"
