import Foundation
import ClaudeMeterCore

/// Calls the same `claude.ai/api/organizations/<orgId>/usage` endpoint the
/// Claude desktop app's Settings → Usage page uses. Auth is the user's
/// existing `.claude.ai` cookie jar, decrypted with the macOS keychain
/// "Claude Safe Storage" key. Returns nil on any failure (no cookies, no
/// keychain access, network error, non-subscription account).
final class UsageProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "ClaudeMeter.probe", qos: .background)
    private var inFlight = false

    func run(completion: @escaping (SubscriptionStats?) -> Void) {
        if inFlight { return }
        inFlight = true
        queue.async { [weak self] in
            defer { self?.inFlight = false }
            completion(self?.runOnce())
        }
    }

    private func runOnce() -> SubscriptionStats? {
        guard let scriptURL = ensureScript() else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path]
        let outPipe = Pipe(); process.standardOutput = outPipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if process.isRunning { process.terminate(); return nil }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let plan = (obj["plan"] as? String) ?? "subscription"
        let five = obj["five_hour"] as? [String: Any]
        let week = obj["seven_day"] as? [String: Any]
        guard let fivePct = five?["utilization"] as? Double else { return nil }
        let weekPct = (week?["utilization"] as? Double) ?? 0

        return SubscriptionStats(
            plan: plan,
            fiveHourPct: fivePct,
            fiveHourResetText: relativeReset(from: five?["resets_at"] as? String),
            weeklyPct: weekPct,
            weeklyResetText: relativeReset(from: week?["resets_at"] as? String),
            queriedAt: Date()
        )
    }

    private func relativeReset(from iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        g.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: iso) ?? g.date(from: iso) else { return nil }
        let remaining = max(0, date.timeIntervalSince(Date()))
        return Formatting.compactDuration(remaining)
    }

    private func ensureScript() -> URL? {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = appSupport.appendingPathComponent("ClaudeMeter", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fetch_usage.py")
        do {
            try Self.embeddedPython.write(to: url, atomically: true, encoding: .utf8)
        } catch { return nil }
        return url
    }

    private static let embeddedPython: String = #"""
#!/usr/bin/env python3
"""Fetch live Anthropic subscription usage and emit JSON to stdout.

Pipeline:
  1. Read 'Claude Safe Storage' password from macOS login keychain.
  2. Derive Chromium AES-128-CBC key (PBKDF2-HMAC-SHA1, salt='saltysalt',
     iters=1003, dkLen=16, IV=16 spaces).
  3. Decrypt every .claude.ai cookie from the Electron app's Cookies SQLite,
     stripping the 3-byte 'v10' prefix and 32-byte SHA-256(host) integrity
     prefix from the decrypted plaintext.
  4. Read organizationUuid from ~/.claude.json -> oauthAccount.
  5. GET https://claude.ai/api/organizations/<orgId>/usage with full cookie
     jar + Claude desktop User-Agent.
"""
import os, sys, json, sqlite3, shutil, tempfile, subprocess, urllib.request, urllib.error

def fail(msg, code=2):
    print(json.dumps({"error": msg}))
    sys.exit(code)

try:
    from Crypto.Cipher import AES
    from Crypto.Protocol.KDF import PBKDF2
    from Crypto.Hash import SHA1
except ImportError:
    fail("pycryptodome_not_installed")

# 1. Keychain key
try:
    key_pw = subprocess.run(
        ["security", "find-generic-password", "-w", "-s", "Claude Safe Storage"],
        capture_output=True, text=True, check=True, timeout=10,
    ).stdout.strip()
except Exception as e:
    fail(f"keychain_denied:{e}")

key = PBKDF2(key_pw, b"saltysalt", dkLen=16, count=1003, hmac_hash_module=SHA1)

# 2. Cookies
cookies_src = os.path.expanduser("~/Library/Application Support/Claude/Cookies")
if not os.path.exists(cookies_src):
    fail("no_cookies_db")
with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
    shutil.copyfile(cookies_src, f.name); db_path = f.name

con = sqlite3.connect(db_path)
def decrypt(blob):
    if not blob or blob[:3] != b"v10": return None
    plain = AES.new(key, AES.MODE_CBC, b" " * 16).decrypt(blob[3:])
    pad = plain[-1]
    if pad < 1 or pad > 16: return None
    plain = plain[:-pad]
    if len(plain) <= 32: return None
    return plain[32:].decode("utf-8", errors="replace")

cookies = {}
for name, _, ev in con.execute(
    "SELECT name, host_key, encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai%'"
):
    v = decrypt(ev)
    if v: cookies[name] = v
con.close()
try: os.unlink(db_path)
except: pass

if "sessionKey" not in cookies:
    fail("no_session_cookie")

# 3. orgId
claude_json = os.path.expanduser("~/.claude.json")
try:
    with open(claude_json) as f: d = json.load(f)
    org_id = d["oauthAccount"]["organizationUuid"]
except Exception as e:
    fail(f"no_org:{e}")

# 4. Fetch
url = f"https://claude.ai/api/organizations/{org_id}/usage"
cookie_str = "; ".join(f"{k}={v}" for k, v in cookies.items())
req = urllib.request.Request(url, headers={
    "Cookie": cookie_str,
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Claude/1.4758.0 Chrome/130.0.6723.137 Electron/33.4.11 Safari/537.36",
    "Accept": "application/json, text/plain, */*",
    "Origin": "https://claude.ai",
    "Referer": "https://claude.ai/",
    "Sec-Fetch-Dest": "empty",
    "Sec-Fetch-Mode": "cors",
    "Sec-Fetch-Site": "same-origin",
})
try:
    with urllib.request.urlopen(req, timeout=12) as resp:
        body = resp.read().decode("utf-8", errors="replace")
        data = json.loads(body)
        # Re-emit canonical shape (preserves the live API response).
        data["plan"] = (d.get("oauthAccount", {}) or {}).get("organizationRateLimitTier") or "subscription"
        print(json.dumps(data))
except urllib.error.HTTPError as e:
    fail(f"http_{e.code}")
except Exception as e:
    fail(f"network:{e}")
"""#
}
