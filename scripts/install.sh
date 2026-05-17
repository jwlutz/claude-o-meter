#!/usr/bin/env bash
# Build, sign, copy to a stable location, and register a LaunchAgent so
# Claude-o-Meter starts automatically at login (and restarts on crash).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/launch-agent.sh"

INSTALL_DIR="$HOME/Library/Application Support/Claude-o-Meter/bin"
INSTALL_PATH="$INSTALL_DIR/claude-o-meter"
LOG_PATH="$HOME/Library/Logs/claude-o-meter.log"
LABEL="com.claude-o-meter.menubar"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

# 1. Build + sign.
"$SCRIPT_DIR/build.sh"

# 2. Copy the signed binary to a stable location.
mkdir -p "$INSTALL_DIR"
cp -f "$PROJECT_ROOT/.build/debug/claude-o-meter" "$INSTALL_PATH"
echo "Installed binary: $INSTALL_PATH"

# 3. Generate the LaunchAgent plist.
mkdir -p "$(dirname "$PLIST_PATH")"
mkdir -p "$(dirname "$LOG_PATH")"
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
echo "Wrote LaunchAgent: $PLIST_PATH"

# 4. (Re)load with launchctl.
load_claude_o_meter_agent "$LABEL" "$PLIST_PATH"

echo
echo "Claude-o-Meter is installed and running. Will autostart on every login."
echo "Logs: $LOG_PATH"
echo "To uninstall: ./scripts/uninstall.sh"
