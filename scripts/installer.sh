#!/usr/bin/env bash
# Installer for the prebuilt macOS tarball shipped on GitHub Releases.
# Differs from scripts/install.sh (which builds from source) — this one
# just copies the bundled binary into place and registers the LaunchAgent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/Library/Application Support/Claude-o-Meter/bin"
INSTALL_PATH="$INSTALL_DIR/claude-o-meter"
LOG_PATH="$HOME/Library/Logs/claude-o-meter.log"
LABEL="com.claude-o-meter.menubar"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ ! -x "$SCRIPT_DIR/claude-o-meter" ]]; then
  echo "FATAL: claude-o-meter binary not found next to this script." >&2
  echo "       Make sure you extracted the tarball before running install.sh." >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
cp -f "$SCRIPT_DIR/claude-o-meter" "$INSTALL_PATH"

# Strip the macOS quarantine xattr so Gatekeeper doesn't block launchd.
# (Files downloaded from the browser get com.apple.quarantine; running
# them once via Finder normally clears it, but launchd doesn't trigger
# the user-prompted clear.)
xattr -d com.apple.quarantine "$INSTALL_PATH" 2>/dev/null || true

mkdir -p "$(dirname "$PLIST_PATH")" "$(dirname "$LOG_PATH")"
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>Program</key>
    <string>$INSTALL_PATH</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>$LOG_PATH</string>
    <key>StandardErrorPath</key>
    <string>$LOG_PATH</string>
</dict>
</plist>
PLIST

# Bootstrap fresh — tolerate any prior install (current or legacy label).
launchctl bootout "gui/$(id -u)/com.claudometer.menubar" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL"                  2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

cat <<DONE

Claude-o-Meter is installed and starts automatically on every login.
Binary: $INSTALL_PATH
Logs:   $LOG_PATH

First launch will prompt once: "security wants to access Claude Safe
Storage." Click ALWAYS ALLOW. After that, no more prompts on this Mac.

To uninstall: $SCRIPT_DIR/uninstall.sh
DONE
