#!/usr/bin/env bash
# Build and package a local macOS artifact, then verify the release tarball
# layout and code signature. This is intentionally non-installing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGE_ROOT="${TMPDIR:-/tmp}/claude-o-meter-smoke"
STAGE="$STAGE_ROOT/claude-o-meter"
TARBALL="$STAGE_ROOT/claude-o-meter-macos-arm64.tar.gz"

cd "$PROJECT_ROOT"
swift build -c release
codesign --force --sign - \
  --identifier "ClaudeMeter" \
  --timestamp=none \
  .build/release/claude-o-meter
codesign --verify --verbose=2 .build/release/claude-o-meter

rm -rf "$STAGE_ROOT"
mkdir -p "$STAGE"
cp .build/release/claude-o-meter "$STAGE/"
cp scripts/installer.sh "$STAGE/install.sh"
cp scripts/launch-agent.sh "$STAGE/launch-agent.sh"
cp scripts/uninstall.sh "$STAGE/uninstall.sh"
cp README.md "$STAGE/README.md"
chmod +x "$STAGE/claude-o-meter" "$STAGE/install.sh" "$STAGE/uninstall.sh"

(cd "$STAGE_ROOT" && tar czf "$TARBALL" claude-o-meter)

tar -tzf "$TARBALL" | grep -qx "claude-o-meter/claude-o-meter"
tar -tzf "$TARBALL" | grep -qx "claude-o-meter/install.sh"
tar -tzf "$TARBALL" | grep -qx "claude-o-meter/launch-agent.sh"
tar -tzf "$TARBALL" | grep -qx "claude-o-meter/uninstall.sh"
tar -tzf "$TARBALL" | grep -qx "claude-o-meter/README.md"
codesign --verify --verbose=2 "$STAGE/claude-o-meter"
shasum -a 256 "$TARBALL"
echo "macOS smoke artifact: $TARBALL"
