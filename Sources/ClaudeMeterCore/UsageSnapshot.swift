import Foundation

public struct UsageSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let mode: UsageMode

    public init(generatedAt: Date, mode: UsageMode) {
        self.generatedAt = generatedAt
        self.mode = mode
    }

    public static let empty = UsageSnapshot(generatedAt: Date(), mode: .unknown(nil))
}

public enum UsageMode: Sendable, Equatable {
    /// Optional reason — surfaced in popover (e.g. "keychain access denied").
    case unknown(String?)
    case subscription(SubscriptionStats)
}

/// Live subscription usage from
/// `https://claude.ai/api/organizations/<orgId>/usage`. Both percentages and
/// reset times come from Anthropic — nothing is computed locally, nothing is
/// hardcoded.
public struct SubscriptionStats: Sendable, Equatable {
    public let plan: String
    public let fiveHourPct: Double
    public let fiveHourResetText: String?
    public let weeklyPct: Double
    public let weeklyResetText: String?
    public let weeklySonnetPct: Double?
    public let weeklySonnetResetText: String?
    public let weeklyOpusPct: Double?
    public let weeklyOpusResetText: String?
    public let queriedAt: Date

    public init(plan: String,
                fiveHourPct: Double, fiveHourResetText: String?,
                weeklyPct: Double, weeklyResetText: String?,
                weeklySonnetPct: Double?, weeklySonnetResetText: String?,
                weeklyOpusPct: Double?, weeklyOpusResetText: String?,
                queriedAt: Date) {
        self.plan = plan
        self.fiveHourPct = fiveHourPct
        self.fiveHourResetText = fiveHourResetText
        self.weeklyPct = weeklyPct
        self.weeklyResetText = weeklyResetText
        self.weeklySonnetPct = weeklySonnetPct
        self.weeklySonnetResetText = weeklySonnetResetText
        self.weeklyOpusPct = weeklyOpusPct
        self.weeklyOpusResetText = weeklyOpusResetText
        self.queriedAt = queriedAt
    }
}
