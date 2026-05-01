# Claude-o-Meter

macOS menu-bar app showing your real-time Claude Pro/Max **5-hour** and
**weekly** subscription usage. Pulls live numbers from the same endpoint
the Claude desktop app's Settings → Usage page uses, so the percentages
match exactly — no estimation, no hardcoded plan limits.

The icon is a Claude burst that drains clockwise as you use the 5-hour
window: full bright orange when fresh, gray ghost when exhausted.

![Claude-o-Meter menu bar icon and popover](docs/screenshot.png)

## How it works

1. Reads the `Claude Safe Storage` AES key from your macOS login keychain
   via `/usr/bin/security`.
2. Decrypts the `.claude.ai` cookies stored by the Claude desktop app
   (Chromium AES-128-CBC, PBKDF2-HMAC-SHA1, 1003 iterations) using
   CommonCrypto.
3. Reads `organizationUuid` from `~/.claude.json:oauthAccount`.
4. `GET https://claude.ai/api/organizations/<orgId>/usage` with the
   decrypted cookie jar and the Claude desktop User-Agent.
5. Re-fetches every 60 seconds.

There are no fallback estimators, no token thresholds, and no
plan-specific defaults — the API returns `utilization` percentages
directly.

## Requirements

- macOS 13+
- Claude desktop app installed and signed in (provides the cookies + key)
- Claude Code subscription (Pro / Max 5x / Max 20x)

That's it. No Python, no pip dependencies. Cookie decryption uses
CommonCrypto; SQLite uses the libsqlite3 in the SDK.

## Install

### macOS — prebuilt (recommended)

Grab the latest `claude-o-meter-macos-arm64.tar.gz` from
[Releases](https://github.com/jwlutz/claude-o-meter/releases/latest), then:

```bash
tar xzf claude-o-meter-macos-arm64.tar.gz
cd claude-o-meter
./install.sh
```

First launch will trigger one keychain prompt — click **Always Allow**.
The binary is ad-hoc signed; if Gatekeeper warns, right-click the
`claude-o-meter` binary → **Open** once.

### Windows — prebuilt

Download `Claude-o-Meter_*_x64-setup.exe` (NSIS) or `.msi` (WiX) from
[Releases](https://github.com/jwlutz/claude-o-meter/releases/latest) and
run it. The app registers itself as a login item on first run.

### Build from source (developers)

```bash
git clone git@github.com:jwlutz/claude-o-meter.git
cd claude-o-meter
./scripts/install.sh    # macOS — builds + signs locally
# or for Windows:
cd windows/src-tauri && cargo tauri build
```

Builds, signs with a self-signed cert ("ClaudeMeter Dev" — kept legacy
for keychain-ACL stability), copies the binary to
`~/Library/Application Support/Claude-o-Meter/bin/claude-o-meter`,
registers a LaunchAgent at
`~/Library/LaunchAgents/com.claude-o-meter.menubar.plist`, and starts it.

The first launch will trigger one "Claude Safe Storage" keychain prompt
— click **Always Allow** and you're done. Future rebuilds reuse the same
designated requirement, so no further prompts.

To stop and remove:

```bash
./scripts/uninstall.sh
```

## Layout

```
claude-o-meter/
  Package.swift
  scripts/
    build.sh                             # build + ad-hoc signed
    install.sh                           # build + LaunchAgent register
    uninstall.sh                         # remove LaunchAgent + binary
  Sources/
    ClaudeoMeterCore/
      UsageSnapshot.swift                # UsageMode + SubscriptionStats
      Formatting.swift                   # "4h12m" helpers
    ClaudeoMeterApp/
      main.swift, AppDelegate.swift      # NSStatusItem wiring
      ClaudeBadge.swift                  # NSImage drain-pie compositor
      PopoverView.swift                  # SwiftUI popover
      UsageStore.swift                   # 60s probe loop
      UsageProbe.swift                   # CommonCrypto + SQLite + URLSession
```

## Reset semantics

Both percentages and reset timestamps come from Anthropic's response —
nothing computed locally. The 5-hour window resets 5 hours after the
first request in it; the weekly window resets at a fixed weekly cadence.
