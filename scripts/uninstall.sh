#!/usr/bin/env bash
# Stop the running agent, remove the LaunchAgent plist, and delete the
# installed binary. The signing cert in your keychain is left in place so
# you can re-install with `scripts/install.sh` without re-prompting.
set -euo pipefail

LABEL="com.claudometer.menubar"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
INSTALL_PATH="$HOME/Library/Application Support/ClaudeMeter/bin/claudometer"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST_PATH"
rm -f "$INSTALL_PATH"
pkill -x claudometer 2>/dev/null || true
echo "ClaudeMeter uninstalled."
echo "Kept: signing cert (\"ClaudeMeter Dev\") and ~/Library/Application Support/ClaudeMeter/{cert-sha1.txt,fetch_usage.py}"
