import Foundation
import ClaudeoMeterCore

final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    let id: UsageProviderID = .codex

    private let queue = DispatchQueue(label: "ClaudeoMeter.codex-probe", qos: .background)
    private var inFlight = false

    func run(completion: @escaping (ProviderProbeResult) -> Void) {
        if inFlight { return }
        inFlight = true
        queue.async { [weak self] in
            defer { self?.inFlight = false }
            completion(self?.runOnce() ?? .failed("probe deinit"))
        }
    }

    private func runOnce() -> ProviderProbeResult {
        guard let executable = codexExecutable() else {
            return .failed("Codex.app not found. Install Codex and sign in, then refresh.")
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]

        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        let lock = NSLock()
        let sem = DispatchSemaphore(value: 0)
        var buffer = ""
        var result: ProviderProbeResult?
        var didFinish = false

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            lock.lock()
            buffer += chunk
            let parts = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            let completeLines = parts.dropLast().map(String.init)
            buffer = parts.last.map(String.init) ?? ""
            lock.unlock()

            for line in completeLines {
                guard let parsed = Self.parseRateLimitLine(line) else { continue }
                lock.lock()
                if !didFinish {
                    result = parsed
                    didFinish = true
                    sem.signal()
                }
                lock.unlock()
            }
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            return .failed("Couldn't start Codex usage probe: \(error.localizedDescription)")
        }

        let initialize = """
        {"method":"initialize","id":1,"params":{"clientInfo":{"name":"claude-o-meter","title":null,"version":"0.1.0"},"capabilities":{"experimentalApi":true,"requestAttestation":false}}}
        """
        let readLimits = #"{"method":"account/rateLimits/read","id":2,"params":null}"#
        let request = "\(initialize)\n\(readLimits)\n"
        if let data = request.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }

        _ = sem.wait(timeout: .now() + 15)

        stdout.fileHandleForReading.readabilityHandler = nil
        try? stdin.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        if let result { return result }
        return .failed("Codex usage unavailable. Open Codex, sign in, then refresh.")
    }

    private func codexExecutable() -> URL? {
        let appBundledPath = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.isExecutableFile(atPath: appBundledPath) {
            return URL(fileURLWithPath: appBundledPath)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["zsh", "-lc", "command -v codex"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func parseRateLimitLine(_ line: String) -> ProviderProbeResult? {
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(CodexRPCEnvelope.self, from: data),
              envelope.id == 2
        else { return nil }

        if let error = envelope.error {
            return .failed(error.message ?? "Codex rate limits unavailable.")
        }
        guard let response = envelope.result else {
            return .failed("Codex rate limits unavailable.")
        }

        let snapshot = response.rateLimitsByLimitId?["codex"] ?? response.rateLimits
        let windows = snapshot.usageWindows
        guard !windows.isEmpty else {
            return .failed("Codex rate limit response did not include usage windows.")
        }

        return .ok(ProviderUsageStats(
            provider: .codex,
            plan: snapshot.planType ?? "codex",
            windows: windows,
            credits: snapshot.credits?.usageCredits,
            queriedAt: Date()
        ))
    }
}

private struct CodexRPCEnvelope: Decodable {
    let id: Int
    let result: CodexRateLimitsResponse?
    let error: CodexRPCError?
}

private struct CodexRPCError: Decodable {
    let message: String?
}

private struct CodexRateLimitsResponse: Decodable {
    let rateLimits: CodexRateLimitSnapshot
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
}

private struct CodexRateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let credits: CodexCreditsSnapshot?
    let planType: String?
    let rateLimitReachedType: String?

    var usageWindows: [UsageWindow] {
        var windows: [UsageWindow] = []
        if let primary {
            windows.append(primary.usageWindow(
                id: "fiveHour",
                title: primary.windowDurationMins == 300 ? "5-hour window" : "Primary window"
            ))
        }
        if let secondary {
            windows.append(secondary.usageWindow(
                id: "weekly",
                title: secondary.windowDurationMins == 10_080 ? "Weekly" : "Secondary window"
            ))
        }
        return windows
    }
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Double?

    func usageWindow(id: String, title: String) -> UsageWindow {
        UsageWindow(
            id: id,
            title: title,
            usedPercent: usedPercent,
            resetAt: resetsAt.map { Date(timeIntervalSince1970: $0) },
            durationMinutes: windowDurationMins
        )
    }
}

private struct CodexCreditsSnapshot: Decodable {
    let hasCredits: Bool
    let unlimited: Bool
    let balance: String?

    var usageCredits: UsageCredits {
        UsageCredits(hasCredits: hasCredits, unlimited: unlimited, balance: balance)
    }
}
