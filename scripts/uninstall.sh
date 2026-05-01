#!/usr/bin/env bash
# Stop the running agent, remove the LaunchAgent plist, and delete the
# installed binary. The signing cert in your keychain is left in place so
# you can re-install with `scripts/install.sh` without re-prompting.
set -euo pipefail

LABEL="com.claude-o-meter.menubar"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALL_PATH="$HOME/Library/Application Support/Claude-o-Meter/bin/claude-o-meter"

# Bootout current and legacy labels just in case.
launchctl bootout "gui/$(id -u)/com.claudometer.menubar" 2>/dev/null || true
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST_PATH"
rm -f "$INSTALL_PATH"
pkill -x claude-o-meter 2>/dev/null || true
pkill -x claudometer 2>/dev/null || true
echo "Claude-o-Meter uninstalled."
echo "Kept: signing cert (\"ClaudeMeter Dev\") and ~/Library/Application Support/Claude-o-Meter/cert-sha1.txt"
