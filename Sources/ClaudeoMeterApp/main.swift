import AppKit

// CLI sub-mode for tests/diagnostics: run the probe once, print one line, exit.
if CommandLine.arguments.contains("--probe-once") {
    let probe = MainActor.assumeIsolated { UsageProbe() }
    let sem = DispatchSemaphore(value: 0)
    var line = "no result"
    probe.run { result in
        switch result {
        case .ok(let s):
            line = "OK plan=\(s.plan) 5h=\(Int(s.fiveHourPct.rounded()))% week=\(Int(s.weeklyPct.rounded()))% reset5h=\(s.fiveHourResetText ?? "-") resetWeek=\(s.weeklyResetText ?? "-")"
        case .failed(let r):
            line = "FAILED: \(r)"
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 30)
    print(line)
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
