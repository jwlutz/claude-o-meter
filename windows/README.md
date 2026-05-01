# Claude-o-Meter — Windows (Tauri 2)

Same idea as the macOS app, ported to Windows as a Tauri 2 system-tray
binary. No window — the icon in the notification area (right edge of the
taskbar) is the whole UI. Hover for "5h: 24% · 4h12m / Week: 19%".
Right-click for Refresh / Quit.

## What's different from macOS

| Layer | macOS | Windows |
|---|---|---|
| Cookie cipher | AES-128-CBC, PBKDF2(SHA1, 1003) | AES-256-GCM, DPAPI-wrapped key |
| Master-key store | Keychain `Claude Safe Storage` | `%APPDATA%\Claude\Local State` |
| Cookies path | `~/Library/Application Support/Claude/Cookies` | `%APPDATA%\Claude\Network\Cookies` |
| Tray API | `NSStatusItem` | Tauri `TrayIconBuilder` |
| Autostart | LaunchAgent plist | `tauri-plugin-autostart` (Registry HKCU\…\Run) |
| Code signing | self-signed cert in Keychain | not strictly required for personal use |

## Prerequisites

On the Windows machine:

1. **Rust** — install from https://rustup.rs (pick the MSVC toolchain).
2. **Visual Studio Build Tools 2022** with the "Desktop development with
   C++" workload (Tauri needs `link.exe`).
3. **WebView2 Runtime** — already installed on Windows 11.
4. **Claude desktop app** — installed and signed in to your Pro/Max
   account (provides the cookies + master key).

Optional: `cargo install tauri-cli@2` if you want `cargo tauri build` to
produce a proper `.msi` installer. Plain `cargo build --release` is enough
for a working binary.

## Build & run

```cmd
cd windows\src-tauri
cargo build --release
.\target\release\claude-o-meter.exe
```

The first run registers the binary as a login item via the autostart
plugin (HKCU `Run` key), and starts the tray icon.

To stop autostart: Task Manager → Startup, disable "Claude-o-Meter".
Or just delete the `Run` registry entry.

## Layout

```
windows/
  src-tauri/
    Cargo.toml
    tauri.conf.json
    build.rs
    icons/
      burst.png         # the Claude burst (embedded into the binary)
      icon.png          # bundle icon
    src/
      main.rs           # tray + probe loop
      cookies.rs        # DPAPI + AES-GCM Chromium cookie decryption
      probe.rs          # /api/organizations/<orgId>/usage call
      icon_render.rs    # tiny-skia drain-pie compositor
      types.rs          # UsageSnapshot + parse helpers
  dist/
    index.html          # required-by-Tauri placeholder; never shown
```

## How it works at runtime

1. Read `%APPDATA%\Claude\Local State`, base64-decode
   `os_crypt.encrypted_key`, strip the `DPAPI` prefix, decrypt with
   `CryptUnprotectData` → 32-byte AES-256 master key.
2. Copy `%APPDATA%\Claude\Network\Cookies` to `%TEMP%`, open with
   rusqlite, decrypt every `.claude.ai` cookie blob (v10 + 12-byte
   nonce + ciphertext+tag) with AES-256-GCM.
3. Read `organizationUuid` and `organizationRateLimitTier` from
   `%USERPROFILE%\.claude.json`.
4. `GET https://claude.ai/api/organizations/<orgId>/usage` with the full
   cookie jar. Same JSON shape as macOS.
5. Render a 32×32 RGBA tray icon with the burst silhouette plus a
   clockwise pie wedge that drains as the 5-hour utilization rises.
6. Re-fetch every 60 seconds.

## Troubleshooting

- **`dpapi:` error in tooltip** — you're logged into a different Windows
  user than the one that runs Claude.app. DPAPI keys are per-user.
- **`no_cookies_db`** — install/run Claude.app at least once.
- **`http_403`** — Cloudflare invalidated your cookies. Reopen Claude.app
  to refresh, then right-click the tray icon → Refresh.
- **Icon hidden in chevron overflow** — Windows 11 hides new tray icons
  by default. Click the `^` chevron, drag the Claude-o-Meter icon out
  next to the clock.
