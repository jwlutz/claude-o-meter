import Foundation
import Darwin
import ClaudeoMeterCore

final class CodexUsageProvider: UsageProvider, @unchecked Sendable {
    let id: UsageProviderID = .codex

    private static let maxAttempts = 2
    private static let responseTimeoutSeconds: TimeInterval = 90

    private let queue = DispatchQueue(label: "ClaudeoMeter.codex-probe", qos: .background)
    private var inFlight = false
    private var cachedExecutable: URL?

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

        var lastResult: ProbeAttemptResult?
        for attempt in 1...Self.maxAttempts {
            let result = runAttempt(executable: executable)
            if !result.shouldRetry || attempt == Self.maxAttempts {
                return result.probeResult
            }
            lastResult = result
            Thread.sleep(forTimeInterval: 0.4)
        }

        return lastResult?.probeResult ?? .transientFailure("Codex usage is temporarily unavailable. Refresh again in a moment.")
    }

    private func runAttempt(executable: URL) -> ProbeAttemptResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

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
            return ProbeAttemptResult(
                probeResult: .transientFailure("Couldn't start Codex usage probe: \(error.localizedDescription)"),
                shouldRetry: true
            )
        }

        let initialize = """
        {"method":"initialize","id":1,"params":{"clientInfo":{"name":"claude-o-meter","title":null,"version":"0.1.0"},"capabilities":{"experimentalApi":true,"requestAttestation":false}}}
        """
        let readLimits = #"{"method":"account/rateLimits/read","id":2,"params":null}"#
        let request = "\(initialize)\n\(readLimits)\n"
        if let data = request.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }

        let waitResult = sem.wait(timeout: .now() + Self.responseTimeoutSeconds)

        stdout.fileHandleForReading.readabilityHandler = nil
        try? stdin.fileHandleForWriting.close()

        stopProcess(process)

        let stdoutTail = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        lock.lock()
        let bufferedOutput = buffer + "\n" + stdoutTail
        if result == nil {
            result = Self.parseRateLimitOutput(bufferedOutput)
        }
        let parsed = result
        lock.unlock()

        if let parsed {
            return ProbeAttemptResult(probeResult: parsed, shouldRetry: parsed.isRetryableCodexFailure)
        }

        if waitResult == .timedOut {
            return ProbeAttemptResult(
                probeResult: .transientFailure("Codex usage is still starting up. Codex is open, but its local app-server did not answer yet."),
                shouldRetry: true
            )
        }

        let detail = Self.firstUsefulLine(in: stderrText)
        let message = detail.map { "Codex usage is temporarily unavailable: \($0)" }
            ?? "Codex usage is temporarily unavailable. Refresh again in a moment."
        return ProbeAttemptResult(probeResult: .transientFailure(message), shouldRetry: true)
    }

    private func stopProcess(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }

    private func codexExecutable() -> URL? {
        if let cachedExecutable,
           FileManager.default.isExecutableFile(atPath: cachedExecutable.path) {
            return cachedExecutable
        }

        let appBundledPath = "/Applications/Codex.app/Contents/Resources/codex"
        if FileManager.default.isExecutableFile(atPath: appBundledPath) {
            let executable = URL(fileURLWithPath: appBundledPath)
            cachedExecutable = executable
            return executable
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
        let executable = URL(fileURLWithPath: path)
        cachedExecutable = executable
        return executable
    }

    private static func parseRateLimitOutput(_ output: String) -> ProviderProbeResult? {
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if let parsed = parseRateLimitLine(line) {
                return parsed
            }
        }
        return nil
    }

    private static func parseRateLimitLine(_ line: String) -> ProviderProbeResult? {
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(CodexRPCEnvelope.self, from: data),
              envelope.id == 2
        else { return nil }

        if let error = envelope.error {
            return classifyError(error.message ?? "Codex rate limits unavailable.")
        }
        guard let response = envelope.result else {
            return .transientFailure("Codex rate limits are temporarily unavailable.")
        }

        guard let snapshot = response.preferredSnapshot else {
            return .transientFailure("Codex rate limit response did not include a Codex limit.")
        }
        let windows = snapshot.usageWindows
        guard !windows.isEmpty else {
            return .transientFailure("Codex rate limit response did not include usage windows.")
        }

        return .ok(ProviderUsageStats(
            provider: .codex,
            plan: snapshot.planType ?? "codex",
            windows: windows,
            credits: snapshot.credits?.usageCredits,
            queriedAt: Date()
        ))
    }

    private static func classifyError(_ message: String) -> ProviderProbeResult {
        let lower = message.lowercased()
        if lower.contains("auth")
            || lower.contains("login")
            || lower.contains("log in")
            || lower.contains("sign in")
            || lower.contains("unauthorized") {
            return .failed("Codex is not signed in. Open Codex and sign in, then refresh.")
        }
        return .transientFailure("Codex rate limits are temporarily unavailable: \(message)")
    }

    private static func firstUsefulLine(in text: String) -> String? {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                !line.isEmpty
                    && !line.contains("failed to warm featured plugin ids cache")
                    && !line.contains("failed to auto-upgrade configured marketplace")
                    && !line.contains("failed to sync curated plugins repo")
            }
    }
}

private struct ProbeAttemptResult {
    let probeResult: ProviderProbeResult
    let shouldRetry: Bool
}

private extension ProviderProbeResult {
    var isRetryableCodexFailure: Bool {
        if case .transientFailure = self { return true }
        return false
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
    let rateLimits: CodexRateLimitSnapshot?
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?

    var preferredSnapshot: CodexRateLimitSnapshot? {
        rateLimitsByLimitId?["codex"]
            ?? rateLimitsByLimitId?.values.first { !$0.usageWindows.isEmpty }
            ?? rateLimits
    }
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
