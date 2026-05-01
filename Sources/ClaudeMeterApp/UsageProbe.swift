import Foundation
import ClaudeMeterCore

/// Calls the same `claude.ai/api/organizations/<orgId>/usage` endpoint the
/// Claude desktop app's Settings → Usage page uses. Auth is the user's
/// existing `.claude.ai` cookie jar, decrypted with the macOS keychain
/// "Claude Safe Storage" key.
///
/// Returns either parsed `SubscriptionStats` or a string explaining why the
/// probe failed (so the popover can show actionable guidance).
final class UsageProbe: @unchecked Sendable {
    enum Result {
        case ok(SubscriptionStats)
        case failed(String)
    }

    private let queue = DispatchQueue(label: "ClaudeMeter.probe", qos: .background)
    private var inFlight = false

    func run(completion: @escaping (Result) -> Void) {
        if inFlight { return }
        inFlight = true
        queue.async { [weak self] in
            defer { self?.inFlight = false }
            completion(self?.runOnce() ?? .failed("probe deinit"))
        }
    }

    private func runOnce() -> Result {
        guard let scriptURL = ensureScript() else { return .failed("could not write probe script") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", scriptURL.path]
        let outPipe = Pipe(); process.standardOutput = outPipe
        process.standardError = Pipe()
        do { try process.run() } catch { return .failed("python3 failed to launch: \(error)") }

        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        if process.isRunning { process.terminate(); return .failed("probe timed out") }

        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("could not parse probe output")
        }
        if let err = obj["error"] as? String {
            return .failed(humanize(err))
        }

        let plan = (obj["plan"] as? String) ?? "subscription"
        let five = obj["five_hour"] as? [String: Any]
        let week = obj["seven_day"] as? [String: Any]
        let sonnet = obj["seven_day_sonnet"] as? [String: Any]
        let opus = obj["seven_day_opus"] as? [String: Any]

        guard let fivePct = (five?["utilization"] as? Double) else {
            return .failed("usage response missing five_hour.utilization")
        }
        let weekPct = (week?["utilization"] as? Double) ?? 0

        return .ok(SubscriptionStats(
            plan: plan,
            fiveHourPct: fivePct,
            fiveHourResetText: relativeReset(from: five?["resets_at"] as? String),
            weeklyPct: weekPct,
            weeklyResetText: relativeReset(from: week?["resets_at"] as? String),
            weeklySonnetPct: sonnet?["utilization"] as? Double,
            weeklySonnetResetText: relativeReset(from: sonnet?["resets_at"] as? String),
            weeklyOpusPct: opus?["utilization"] as? Double,
            weeklyOpusResetText: relativeReset(from: opus?["resets_at"] as? String),
            queriedAt: Date()
        ))
    }

    private func humanize(_ raw: String) -> String {
        switch true {
        case raw.hasPrefix("keychain"):
            return "Keychain access denied. Re-run and choose Always Allow on the Claude Safe Storage prompt."
        case raw.hasPrefix("pycryptodome"):
            return "Missing dependency. Run: pip3 install --user pycryptodome"
        case raw.hasPrefix("no_session"):
            return "Not signed in to Claude.app — sign in there, then refresh."
        case raw.hasPrefix("no_org"):
            return "Couldn't find your org in ~/.claude.json — sign in to Claude Code first."
        case raw.hasPrefix("no_cookies"):
            return "Claude.app cookies missing — install/run Claude.app once."
        case raw.hasPrefix("http_403"):
            return "Anthropic blocked the request (cookies expired?). Reopen Claude.app to refresh."
        default:
            return raw
        }
    }

    private func relativeReset(from iso: String?) -> String? {
        guard let iso else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let g = ISO8601DateFormatter()
        g.formatOptions = [.withInternetDateTime]
        guard let date = f.date(from: iso) ?? g.date(from: iso) else { return nil }
        return Formatting.compactDuration(max(0, date.timeIntervalSince(Date())))
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
"""Fetch live Anthropic subscription usage and emit JSON to stdout."""
import os, sys, json, sqlite3, shutil, tempfile, subprocess, urllib.request, urllib.error

def fail(msg):
    print(json.dumps({"error": msg}))
    sys.exit(0)

try:
    from Crypto.Cipher import AES
    from Crypto.Protocol.KDF import PBKDF2
    from Crypto.Hash import SHA1
except ImportError:
    fail("pycryptodome_not_installed")

try:
    key_pw = subprocess.run(
        ["security", "find-generic-password", "-w", "-s", "Claude Safe Storage"],
        capture_output=True, text=True, check=True, timeout=15,
    ).stdout.strip()
except Exception as e:
    fail(f"keychain:{e}")

key = PBKDF2(key_pw, b"saltysalt", dkLen=16, count=1003, hmac_hash_module=SHA1)

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

claude_json = os.path.expanduser("~/.claude.json")
try:
    with open(claude_json) as f:
        d = json.load(f)
    org_id = d["oauthAccount"]["organizationUuid"]
except Exception as e:
    fail(f"no_org:{e}")

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
        data["plan"] = (d.get("oauthAccount", {}) or {}).get("organizationRateLimitTier") or "subscription"
        print(json.dumps(data))
except urllib.error.HTTPError as e:
    fail(f"http_{e.code}")
except Exception as e:
    fail(f"network:{e}")
"""#
}
