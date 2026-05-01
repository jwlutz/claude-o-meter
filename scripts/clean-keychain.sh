#!/usr/bin/env bash
# Prune orphan "ClaudeMeter Dev" certs from the login keychain, keeping only
# the SHA-1 currently pinned in cert-sha1.txt. Safe to run anytime — the
# pinned cert is what build.sh signs against, so deleting orphans never
# breaks the daemon's signature.
set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
HASH_FILE="$HOME/Library/Application Support/Claude-o-Meter/cert-sha1.txt"
IDENTITY="ClaudeMeter Dev"

if [[ ! -f "$HASH_FILE" ]]; then
  echo "no pinned cert found at $HASH_FILE — nothing to do" >&2
  exit 0
fi
KEEP="$(cat "$HASH_FILE")"
echo "Keeping pinned cert: $KEEP"

ORPHANS=()
while read -r sha; do
  [[ "$sha" != "$KEEP" ]] && ORPHANS+=("$sha")
done < <(security find-certificate -a -c "$IDENTITY" -Z 2>/dev/null \
         | awk '/^SHA-1 hash:/ {print toupper($3)}')

if [[ ${#ORPHANS[@]} -eq 0 ]]; then
  echo "No orphans. Keychain is clean."
  exit 0
fi

echo "Found ${#ORPHANS[@]} orphan cert(s). Deleting:"
for sha in "${ORPHANS[@]}"; do
  echo "  $sha"
  security delete-certificate -Z "$sha" "$KEYCHAIN" 2>&1 | sed 's/^/    /' || true
done
echo "Done."
