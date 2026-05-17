import AppKit
import ClaudeoMeterCore

// CLI sub-mode for tests/diagnostics: run the probe once, print one line, exit.
if CommandLine.arguments.contains("--probe-once") {
    let providerID = providerArgument() ?? .claudeCode
    let probe: UsageProvider = MainActor.assumeIsolated {
        switch providerID {
        case .claudeCode: ClaudeUsageProvider()
        case .codex: CodexUsageProvider()
        }
    }
    let sem = DispatchSemaphore(value: 0)
    var line = "no result"
    probe.run { result in
        switch result {
        case .ok(let s):
            let five = s.primaryWindow
            let week = s.secondaryWindow
            line = "OK provider=\(s.provider.displayName) plan=\(PlanLabel.display(s.plan)) 5h=\(percent(five)) week=\(percent(week)) reset5h=\(five?.resetText() ?? "-") resetWeek=\(week?.resetText() ?? "-")"
        case .failed(let r):
            line = "FAILED: \(r)"
        case .transientFailure(let r):
            line = "TRANSIENT: \(r)"
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + (providerID == .codex ? 100 : 30))
    print(line)
    exit(0)
}

private func providerArgument() -> UsageProviderID? {
    let args = CommandLine.arguments
    for (index, arg) in args.enumerated() {
        if arg == "--provider", index + 1 < args.count {
            return parseProvider(args[index + 1])
        }
        if arg.hasPrefix("--provider=") {
            return parseProvider(String(arg.dropFirst("--provider=".count)))
        }
    }
    return nil
}

private func parseProvider(_ raw: String) -> UsageProviderID? {
    switch raw.lowercased() {
    case "claude", "claude-code", "claudecode": return .claudeCode
    case "codex", "openai": return .codex
    default: return UsageProviderID(rawValue: raw)
    }
}

private func percent(_ window: UsageWindow?) -> String {
    guard let window else { return "-" }
    return "\(Int(window.usedPercent.rounded()))%"
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
