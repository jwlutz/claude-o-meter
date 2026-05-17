import XCTest
@testable import ClaudeoMeterCore

final class UsageSnapshotTests: XCTestCase {
    func testProviderLookupReturnsMatchingProviderSnapshot() {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 100)
        let claude = ProviderUsageSnapshot(
            provider: .claudeCode,
            generatedAt: generatedAt,
            mode: .unknown("missing")
        )
        let codex = ProviderUsageSnapshot(
            provider: .codex,
            generatedAt: generatedAt,
            mode: .unknown(nil)
        )

        let snapshot = UsageSnapshot(generatedAt: generatedAt, providers: [claude, codex])

        XCTAssertEqual(snapshot.provider(.claudeCode), claude)
        XCTAssertEqual(snapshot.provider(.codex), codex)
    }

    func testStatsPreferFiveHourAndWeeklyWindows() {
        let queriedAt = Date(timeIntervalSinceReferenceDate: 100)
        let fallback = UsageWindow(
            id: "other",
            title: "Other",
            usedPercent: 3,
            resetAt: nil,
            durationMinutes: nil
        )
        let weekly = UsageWindow(
            id: "weekly",
            title: "Weekly",
            usedPercent: 8,
            resetAt: nil,
            durationMinutes: 10_080
        )
        let fiveHour = UsageWindow(
            id: "fiveHour",
            title: "5-hour window",
            usedPercent: 13,
            resetAt: nil,
            durationMinutes: 300
        )

        let stats = ProviderUsageStats(
            provider: .codex,
            plan: "plus",
            windows: [fallback, weekly, fiveHour],
            credits: nil,
            queriedAt: queriedAt
        )

        XCTAssertEqual(stats.primaryWindow, fiveHour)
        XCTAssertEqual(stats.secondaryWindow, weekly)
    }

    func testStatsFallBackToFirstPrimaryWindowWhenFiveHourIsMissing() {
        let first = UsageWindow(
            id: "primary",
            title: "Primary",
            usedPercent: 12,
            resetAt: nil,
            durationMinutes: nil
        )
        let stats = ProviderUsageStats(
            provider: .claudeCode,
            plan: "pro",
            windows: [first],
            credits: nil,
            queriedAt: Date()
        )

        XCTAssertEqual(stats.primaryWindow, first)
        XCTAssertNil(stats.secondaryWindow)
    }

    func testResetTextUsesNonNegativeRelativeDuration() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let future = UsageWindow(
            id: "fiveHour",
            title: "5-hour window",
            usedPercent: 0,
            resetAt: now.addingTimeInterval(3_660),
            durationMinutes: 300
        )
        let past = UsageWindow(
            id: "fiveHour",
            title: "5-hour window",
            usedPercent: 0,
            resetAt: now.addingTimeInterval(-30),
            durationMinutes: 300
        )
        let missing = UsageWindow(
            id: "fiveHour",
            title: "5-hour window",
            usedPercent: 0,
            resetAt: nil,
            durationMinutes: 300
        )

        XCTAssertEqual(future.resetText(relativeTo: now), "1h1m")
        XCTAssertEqual(past.resetText(relativeTo: now), "0m")
        XCTAssertNil(missing.resetText(relativeTo: now))
    }
}
