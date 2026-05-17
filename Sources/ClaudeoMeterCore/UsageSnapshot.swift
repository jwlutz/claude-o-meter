import Foundation

public enum UsageProviderID: String, CaseIterable, Identifiable, Sendable, Equatable {
    case claudeCode
    case codex

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        }
    }
}

public struct UsageSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let providers: [ProviderUsageSnapshot]

    public init(generatedAt: Date, providers: [ProviderUsageSnapshot]) {
        self.generatedAt = generatedAt
        self.providers = providers
    }

    public static let empty = UsageSnapshot(
        generatedAt: Date(),
        providers: UsageProviderID.allCases.map { ProviderUsageSnapshot(provider: $0, generatedAt: Date(), mode: .unknown(nil)) }
    )

    public func provider(_ id: UsageProviderID) -> ProviderUsageSnapshot? {
        providers.first { $0.provider == id }
    }
}

public struct ProviderUsageSnapshot: Identifiable, Equatable, Sendable {
    public let provider: UsageProviderID
    public let generatedAt: Date
    public let mode: UsageMode
    public let staleReason: String?

    public var id: UsageProviderID { provider }

    public init(provider: UsageProviderID,
                generatedAt: Date,
                mode: UsageMode,
                staleReason: String? = nil) {
        self.provider = provider
        self.generatedAt = generatedAt
        self.mode = mode
        self.staleReason = staleReason
    }
}

public enum UsageMode: Equatable, Sendable {
    /// Optional reason — surfaced in popover (e.g. "keychain access denied").
    case unknown(String?)
    case subscription(ProviderUsageStats)
}

/// Live subscription usage for one provider. Percentages and reset times come
/// from the provider source; nothing is computed from local token totals.
public struct ProviderUsageStats: Equatable, Sendable {
    public let provider: UsageProviderID
    public let plan: String
    public let windows: [UsageWindow]
    public let credits: UsageCredits?
    public let queriedAt: Date

    public init(provider: UsageProviderID,
                plan: String,
                windows: [UsageWindow],
                credits: UsageCredits?,
                queriedAt: Date) {
        self.provider = provider
        self.plan = plan
        self.windows = windows
        self.credits = credits
        self.queriedAt = queriedAt
    }

    public var primaryWindow: UsageWindow? {
        windows.first { $0.id == "fiveHour" } ?? windows.first
    }

    public var secondaryWindow: UsageWindow? {
        windows.first { $0.id == "weekly" }
    }
}

public struct UsageWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let usedPercent: Double
    public let resetAt: Date?
    public let durationMinutes: Int?

    public init(id: String,
                title: String,
                usedPercent: Double,
                resetAt: Date?,
                durationMinutes: Int?) {
        self.id = id
        self.title = title
        self.usedPercent = usedPercent
        self.resetAt = resetAt
        self.durationMinutes = durationMinutes
    }

    public func resetText(relativeTo now: Date = Date()) -> String? {
        guard let resetAt else { return nil }
        return Formatting.compactDuration(max(0, resetAt.timeIntervalSince(now)))
    }
}

public struct UsageCredits: Equatable, Sendable {
    public let hasCredits: Bool
    public let unlimited: Bool
    public let balance: String?

    public init(hasCredits: Bool, unlimited: Bool, balance: String?) {
        self.hasCredits = hasCredits
        self.unlimited = unlimited
        self.balance = balance
    }
}
