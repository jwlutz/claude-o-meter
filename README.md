# ClaudeMeter

macOS menu-bar app showing your real-time Claude Pro/Max **5-hour** and
**weekly** subscription usage. Pulls live numbers from the same endpoint
the Claude desktop app's Settings → Usage page uses, so the percentages
match exactly — no estimation, no hardcoded plan limits.

The icon is a Claude burst that drains clockwise as you use the 5-hour
window: full bright orange when fresh, gray ghost when exhausted.

## How it works

1. Reads the `Claude Safe Storage` AES key from your macOS login keychain.
2. Decrypts the `.claude.ai` cookies stored by the Claude desktop app
   (Chromium AES-128-CBC, PBKDF2-HMAC-SHA1, 1003 iterations).
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
CommonCrypto (system framework); SQLite uses the libsqlite3 in the SDK.

## Build & run

```bash
cd ~/Desktop/Projects/github/claudometer
./scripts/build.sh
.build/debug/ClaudeMeter
```

`scripts/build.sh` creates a stable self-signed code-signing identity
("ClaudeMeter Dev") in your login keychain on first run, then signs
every build with it. This keeps the keychain ACL stable across rebuilds
so you only ever see one "Claude Safe Storage" prompt — click
**Always Allow** and you're done.

The first launch after signing will trigger that single keychain prompt;
subsequent rebuilds (with the same cert) reuse the standing ACL.

## Layout

```
claudometer/
  Package.swift
  scripts/build.sh                       # build + ad-hoc signed
  Sources/
    ClaudeMeterCore/
      UsageSnapshot.swift                # UsageMode + SubscriptionStats
      Formatting.swift                   # "4h12m" helpers
    ClaudeMeterApp/
      main.swift, AppDelegate.swift      # NSStatusItem wiring
      ClaudeBadge.swift                  # NSImage compositor (drain effect)
      PopoverView.swift                  # SwiftUI popover
      UsageStore.swift                   # 60s probe loop
      UsageProbe.swift                   # spawns the Python fetch helper
```

## Reset semantics

Both percentages and reset timestamps come from Anthropic's response.
The 5-hour window resets 5 hours after the first request in it; the
weekly window resets at a fixed weekly cadence. ClaudeMeter just
displays what the API returns.
