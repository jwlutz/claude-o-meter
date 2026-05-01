import Foundation

public struct UsageSnapshot: Equatable, Sendable {
    public let generatedAt: Date
    public let mode: UsageMode

    public init(generatedAt: Date, mode: UsageMode) {
        self.generatedAt = generatedAt
        self.mode = mode
    }

    public static let empty = UsageSnapshot(generatedAt: Date(), mode: .unknown)
}

public enum UsageMode: Sendable, Equatable {
    case unknown
    case api(ApiStats)
    case subscription(SubscriptionStats)
}

public struct ApiStats: Sendable, Equatable {
    public let today: PeriodStats
    public let week: PeriodStats
    public let dailyBudgetUSD: Double
    public let topModels: [ModelTotal]
    public let topProjects: [ProjectTotal]

    public init(today: PeriodStats, week: PeriodStats, dailyBudgetUSD: Double,
                topModels: [ModelTotal], topProjects: [ProjectTotal]) {
        self.today = today
        self.week = week
        self.dailyBudgetUSD = dailyBudgetUSD
        self.topModels = topModels
        self.topProjects = topProjects
    }

    public var todayBudgetFraction: Double {
        guard dailyBudgetUSD > 0 else { return 0 }
        return min(1.0, today.costUSD / dailyBudgetUSD)
    }

    public static let empty = ApiStats(
        today: .empty, week: .empty, dailyBudgetUSD: 20.0,
        topModels: [], topProjects: []
    )
}

public struct PeriodStats: Sendable, Equatable {
    public let messages: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreate: Int
    public let cacheRead: Int
    public let costUSD: Double

    public init(messages: Int, inputTokens: Int, outputTokens: Int,
                cacheCreate: Int, cacheRead: Int, costUSD: Double) {
        self.messages = messages
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreate = cacheCreate
        self.cacheRead = cacheRead
        self.costUSD = costUSD
    }

    public var totalTokens: Int { inputTokens + outputTokens + cacheCreate + cacheRead }

    public static let empty = PeriodStats(messages: 0, inputTokens: 0, outputTokens: 0, cacheCreate: 0, cacheRead: 0, costUSD: 0)
}

public struct ModelTotal: Sendable, Equatable, Identifiable {
    public let model: String
    public let messages: Int
    public let costUSD: Double
    public var id: String { model }

    public init(model: String, messages: Int, costUSD: Double) {
        self.model = model
        self.messages = messages
        self.costUSD = costUSD
    }
}

public struct ProjectTotal: Sendable, Equatable, Identifiable {
    public let name: String
    public let messages: Int
    public let costUSD: Double
    public var id: String { name }

    public init(name: String, messages: Int, costUSD: Double) {
        self.name = name
        self.messages = messages
        self.costUSD = costUSD
    }
}

public struct SubscriptionStats: Sendable, Equatable {
    public let plan: String
    public let fiveHourPct: Double
    public let fiveHourResetText: String?
    public let weeklyPct: Double
    public let weeklyResetText: String?
    public let queriedAt: Date

    public init(plan: String, fiveHourPct: Double, fiveHourResetText: String?,
                weeklyPct: Double, weeklyResetText: String?, queriedAt: Date) {
        self.plan = plan
        self.fiveHourPct = fiveHourPct
        self.fiveHourResetText = fiveHourResetText
        self.weeklyPct = weeklyPct
        self.weeklyResetText = weeklyResetText
        self.queriedAt = queriedAt
    }
}
