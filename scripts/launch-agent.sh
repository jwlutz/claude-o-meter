#!/usr/bin/env bash
# Shared LaunchAgent loading helpers for local and release installers.

load_claude_o_meter_agent() {
  local label="$1"
  local plist_path="$2"
  local legacy_label="com.claudometer.menubar"
  local domain="gui/$(id -u)"

  launchctl bootout "$domain/$legacy_label" 2>/dev/null || true
  launchctl bootout "$domain/$label" 2>/dev/null || true

  # launchd can report I/O errors while the previous agent is still winding
  # down. Give it a short, bounded settle window before bootstrapping again.
  for _ in 1 2 3 4 5; do
    if ! launchctl print "$domain/$label" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
  done

  if ! launchctl bootstrap "$domain" "$plist_path"; then
    echo "launchctl bootstrap failed; retrying once after bootout..." >&2
    launchctl bootout "$domain/$label" 2>/dev/null || true
    sleep 0.5
    launchctl bootstrap "$domain" "$plist_path"
  fi

  launchctl kickstart -k "$domain/$label"
}
