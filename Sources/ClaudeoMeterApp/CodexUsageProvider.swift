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
                guard let parsed = Self.probeResult(from: CodexRateLimitParser.parseLine(line)) else { continue }
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
            result = Self.probeResult(from: CodexRateLimitParser.parseOutput(bufferedOutput))
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

    private static func probeResult(from parseResult: Result<ProviderUsageStats, CodexRateLimitParseError>?) -> ProviderProbeResult? {
        guard let parseResult else { return nil }
        switch parseResult {
        case .success(let stats):
            return .ok(stats)
        case .failure(.authRequired(let message)):
            return .failed(message)
        case .failure(.transient(let message)):
            return .transientFailure(message)
        }
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
