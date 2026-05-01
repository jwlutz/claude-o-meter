import Foundation
import CommonCrypto
import SQLite3
import ClaudeoMeterCore

/// Calls the same `claude.ai/api/organizations/<orgId>/usage` endpoint the
/// Claude desktop app's Settings → Usage page uses. Pure Swift — no Python,
/// no third-party deps. Pipeline:
///
/// 1. Read `Claude Safe Storage` key from the macOS login keychain via
///    `/usr/bin/security` (system tool already trusted by the keychain ACL).
/// 2. Derive Chromium AES-128-CBC key (PBKDF2-HMAC-SHA1, salt="saltysalt",
///    iter=1003, dkLen=16) using CommonCrypto.
/// 3. Open the Claude.app Cookies SQLite, decrypt every `.claude.ai` cookie,
///    stripping the 3-byte "v10" prefix and 32-byte SHA-256(host) integrity
///    prefix.
/// 4. Read `organizationUuid` from `~/.claude.json:oauthAccount`.
/// 5. GET the usage endpoint with the cookie jar + Claude desktop UA.
final class UsageProbe: @unchecked Sendable {
    enum Result {
        case ok(SubscriptionStats)
        case failed(String)
    }

    private let queue = DispatchQueue(label: "ClaudeoMeter.probe", qos: .background)
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
        let (keyOpt, keyErr) = readKeychainKey()
        guard let keyPw = keyOpt else { return .failed(humanize(keyErr ?? "keychain")) }

        let aesKey = pbkdf2(password: keyPw,
                            salt: Data("saltysalt".utf8),
                            iterations: 1003, keyLen: 16)

        guard let cookies = readCookies(aesKey: aesKey) else {
            return .failed(humanize("no_cookies"))
        }
        guard cookies["sessionKey"] != nil else {
            return .failed(humanize("no_session"))
        }
        guard let (orgId, planTier) = readOrgInfo() else {
            return .failed(humanize("no_org"))
        }
        return fetchUsage(orgId: orgId, cookies: cookies, planTier: planTier)
    }

    // MARK: - Keychain

    private func readKeychainKey() -> (String?, String?) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-w", "-s", "Claude Safe Storage"]
        let out = Pipe(); p.standardOutput = out
        p.standardError = FileHandle.nullDevice  // unused; avoid an unread Pipe
        do { try p.run() } catch { return (nil, "keychain_launch:\(error)") }
        p.waitUntilExit()
        if p.terminationStatus != 0 { return (nil, "keychain") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let s = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty
        else { return (nil, "keychain_empty") }
        return (s, nil)
    }

    // MARK: - Crypto

    private func pbkdf2(password: String, salt: Data, iterations: Int, keyLen: Int) -> Data {
        var derived = Data(count: keyLen)
        let pwBytes = Array(password.utf8)
        derived.withUnsafeMutableBytes { dkBuf in
            salt.withUnsafeBytes { saltBuf in
                _ = CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pwBytes, pwBytes.count,
                    saltBuf.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                    UInt32(iterations),
                    dkBuf.bindMemory(to: UInt8.self).baseAddress, keyLen
                )
            }
        }
        return derived
    }

    private func aesCBCDecrypt(key: Data, iv: Data, ciphertext: Data) -> Data? {
        let bufSize = ciphertext.count + kCCBlockSizeAES128
        var buf = Data(count: bufSize)
        var moved = 0
        var status: CCCryptorStatus = CCCryptorStatus(kCCSuccess)
        buf.withUnsafeMutableBytes { bufPtr in
            ciphertext.withUnsafeBytes { ctPtr in
                iv.withUnsafeBytes { ivPtr in
                    key.withUnsafeBytes { keyPtr in
                        status = CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES128),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            ctPtr.baseAddress, ciphertext.count,
                            bufPtr.baseAddress, bufSize,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        return buf.prefix(moved)
    }

    private func decryptCookieValue(_ blob: Data, aesKey: Data) -> String? {
        guard blob.count > 3, blob.prefix(3) == Data("v10".utf8) else { return nil }
        let ciphertext = blob.dropFirst(3)
        let iv = Data(repeating: 0x20, count: 16)
        guard let plain = aesCBCDecrypt(key: aesKey,
                                        iv: iv,
                                        ciphertext: Data(ciphertext)) else { return nil }
        guard plain.count > 32 else { return nil }
        // Drop the 32-byte SHA-256(host) integrity prefix Chromium prepends.
        return String(data: Data(plain.dropFirst(32)), encoding: .utf8)
    }

    // MARK: - Cookies SQLite

    private func readCookies(aesKey: Data) -> [String: String]? {
        let src = NSString(string: "~/Library/Application Support/Claude/Cookies").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: src) else { return nil }
        let tmp = NSTemporaryDirectory() + "claude-o-meter-cookies-\(UUID().uuidString).db"
        do { try FileManager.default.copyItem(atPath: src, toPath: tmp) } catch { return nil }
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        var db: OpaquePointer?
        guard sqlite3_open(tmp, &db) == SQLITE_OK else {
            sqlite3_close(db); return nil
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT name, encrypted_value FROM cookies WHERE host_key LIKE '%claude.ai%'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }

        var cookies: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(stmt, 0),
                  let blobPtr = sqlite3_column_blob(stmt, 1) else { continue }
            let name = String(cString: nameC)
            let blobLen = Int(sqlite3_column_bytes(stmt, 1))
            let blob = Data(bytes: blobPtr, count: blobLen)
            if let v = decryptCookieValue(blob, aesKey: aesKey) {
                cookies[name] = v
            }
        }
        return cookies
    }

    // MARK: - Org info

    private func readOrgInfo() -> (orgId: String, planTier: String)? {
        let path = NSString(string: "~/.claude.json").expandingTildeInPath
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["oauthAccount"] as? [String: Any],
              let orgId = oauth["organizationUuid"] as? String
        else { return nil }
        let planTier = (oauth["organizationRateLimitTier"] as? String) ?? "subscription"
        return (orgId, planTier)
    }

    // MARK: - HTTP

    private func fetchUsage(orgId: String, cookies: [String: String], planTier: String) -> Result {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
            return .failed("invalid url")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        let cookieStr = cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        req.addValue(cookieStr, forHTTPHeaderField: "Cookie")
        req.addValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Claude/1.4758.0 Chrome/130.0.6723.137 Electron/33.4.11 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        req.addValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.addValue("https://claude.ai", forHTTPHeaderField: "Origin")
        req.addValue("https://claude.ai/", forHTTPHeaderField: "Referer")
        req.addValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.addValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.addValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")

        let sem = DispatchSemaphore(value: 0)
        var status = 0
        var bodyData: Data?
        var netError: String?
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { netError = "network:\(err.localizedDescription)" }
            if let r = resp as? HTTPURLResponse { status = r.statusCode }
            bodyData = data
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 15)

        if let netError { return .failed(humanize(netError)) }
        if status == 403 { return .failed(humanize("http_403")) }
        if status != 200 { return .failed("http_\(status)") }
        guard let data = bodyData,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failed("response parse failed")
        }

        let five = obj["five_hour"] as? [String: Any]
        let week = obj["seven_day"] as? [String: Any]
        let sonnet = obj["seven_day_sonnet"] as? [String: Any]
        let opus = obj["seven_day_opus"] as? [String: Any]

        guard let fivePct = five?["utilization"] as? Double else {
            return .failed("response missing five_hour.utilization")
        }
        let weekPct = (week?["utilization"] as? Double) ?? 0

        return .ok(SubscriptionStats(
            plan: planTier,
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
            return "Keychain access denied. The next probe will reprompt — choose Always Allow on the Claude Safe Storage dialog."
        case raw.hasPrefix("no_session"):
            return "Not signed in to Claude.app — open it and sign in, then refresh."
        case raw.hasPrefix("no_org"):
            return "Couldn't read your org from ~/.claude.json — sign in to Claude Code first."
        case raw.hasPrefix("no_cookies"):
            return "Claude.app cookies missing. Install and run Claude.app once."
        case raw.hasPrefix("http_403"):
            return "Anthropic blocked the request (cookies expired). Reopen Claude.app to refresh, then retry."
        case raw.hasPrefix("network"):
            return raw.replacingOccurrences(of: "network:", with: "Network: ")
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
}
