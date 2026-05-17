import Foundation

public enum CodexRateLimitParseError: Error, Equatable, Sendable {
    case authRequired(String)
    case transient(String)

    public var message: String {
        switch self {
        case .authRequired(let message), .transient(let message):
            return message
        }
    }
}

public enum CodexRateLimitParser {
    public static func parseOutput(_ output: String, queriedAt: Date = Date()) -> Result<ProviderUsageStats, CodexRateLimitParseError>? {
        for line in output.split(whereSeparator: \.isNewline).map(String.init) {
            if let parsed = parseLine(line, queriedAt: queriedAt) {
                return parsed
            }
        }
        return nil
    }

    public static func parseLine(_ line: String, queriedAt: Date = Date()) -> Result<ProviderUsageStats, CodexRateLimitParseError>? {
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(CodexRPCEnvelope.self, from: data),
              envelope.id == 2
        else { return nil }

        if let error = envelope.error {
            return .failure(classifyError(error.message ?? "Codex rate limits unavailable."))
        }
        guard let response = envelope.result else {
            return .failure(.transient("Codex rate limits are temporarily unavailable."))
        }
        guard let snapshot = response.preferredSnapshot else {
            return .failure(.transient("Codex rate limit response did not include a Codex limit."))
        }

        let windows = snapshot.usageWindows
        guard !windows.isEmpty else {
            return .failure(.transient("Codex rate limit response did not include usage windows."))
        }

        return .success(ProviderUsageStats(
            provider: .codex,
            plan: snapshot.planType ?? "codex",
            windows: windows,
            credits: snapshot.credits?.usageCredits,
            queriedAt: queriedAt
        ))
    }

    private static func classifyError(_ message: String) -> CodexRateLimitParseError {
        let lower = message.lowercased()
        if lower.contains("auth")
            || lower.contains("login")
            || lower.contains("log in")
            || lower.contains("sign in")
            || lower.contains("unauthorized") {
            return .authRequired("Codex is not signed in. Open Codex and sign in, then refresh.")
        }
        return .transient("Codex rate limits are temporarily unavailable: \(message)")
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
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let credits: CodexCreditsSnapshot?
    let planType: String?

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
