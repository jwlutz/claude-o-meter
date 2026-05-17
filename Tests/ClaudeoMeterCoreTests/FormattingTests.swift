import XCTest
@testable import ClaudeoMeterCore

final class FormattingTests: XCTestCase {
    func testCompactDurationUsesMinutesBelowAnHour() {
        XCTAssertEqual(Formatting.compactDuration(0), "0m")
        XCTAssertEqual(Formatting.compactDuration(59), "0m")
        XCTAssertEqual(Formatting.compactDuration(60), "1m")
        XCTAssertEqual(Formatting.compactDuration(3_599), "59m")
    }

    func testCompactDurationUsesHoursBelowADay() {
        XCTAssertEqual(Formatting.compactDuration(3_600), "1h0m")
        XCTAssertEqual(Formatting.compactDuration(3_660), "1h1m")
        XCTAssertEqual(Formatting.compactDuration(86_399), "23h59m")
    }

    func testCompactDurationUsesDaysAboveTwentyFourHours() {
        XCTAssertEqual(Formatting.compactDuration(86_400), "1d")
        XCTAssertEqual(Formatting.compactDuration(90_000), "1d1h")
        XCTAssertEqual(Formatting.compactDuration((6 * 86_400) + (23 * 3_600)), "6d23h")
    }

    func testPlanLabelRemovesProviderBoilerplate() {
        XCTAssertEqual(PlanLabel.display("claude_max_20x"), "Max 20x")
        XCTAssertEqual(PlanLabel.display("codex plus"), "Plus")
        XCTAssertEqual(PlanLabel.display("openai_chatgpt_pro"), "Pro")
    }

    func testPlanLabelKeepsKnownCompoundWordsReadable() {
        XCTAssertEqual(PlanLabel.display("prolite"), "Pro Lite")
        XCTAssertEqual(PlanLabel.display("self_serve_usage_based"), "Self Serve Usage Based")
    }
}
