import XCTest
@testable import ClaudeoMeterCore

final class CodexRateLimitParserTests: XCTestCase {
    func testParsesRateLimitsByCodexLimitId() throws {
        let queriedAt = Date(timeIntervalSinceReferenceDate: 500)
        let output = """
        {"id":1,"result":{"userAgent":"Codex"}}
        {"method":"remoteControl/status/changed","params":{"status":"disabled"}}
        {"id":2,"result":{"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":92,"windowDurationMins":300,"resetsAt":1779055217},"secondary":{"usedPercent":46,"windowDurationMins":10080,"resetsAt":1779582243},"credits":{"hasCredits":false,"unlimited":false,"balance":"0"},"planType":"plus"}}}}
        """

        let stats = try XCTUnwrapSuccess(CodexRateLimitParser.parseOutput(output, queriedAt: queriedAt))

        XCTAssertEqual(stats.provider, .codex)
        XCTAssertEqual(stats.plan, "plus")
        XCTAssertEqual(stats.queriedAt, queriedAt)
        XCTAssertEqual(stats.primaryWindow?.title, "5-hour window")
        XCTAssertEqual(stats.primaryWindow?.usedPercent, 92)
        XCTAssertEqual(stats.secondaryWindow?.title, "Weekly")
        XCTAssertEqual(stats.secondaryWindow?.usedPercent, 46)
        XCTAssertEqual(stats.credits, UsageCredits(hasCredits: false, unlimited: false, balance: "0"))
    }

    func testParsesLegacyTopLevelRateLimits() throws {
        let output = """
        {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":120,"resetsAt":1779055217},"secondary":{"usedPercent":34,"windowDurationMins":1440,"resetsAt":1779582243},"planType":"pro"}}}
        """

        let stats = try XCTUnwrapSuccess(CodexRateLimitParser.parseOutput(output))

        XCTAssertEqual(stats.plan, "pro")
        XCTAssertEqual(stats.windows.map(\.title), ["Primary window", "Secondary window"])
        XCTAssertEqual(stats.primaryWindow?.usedPercent, 12)
        XCTAssertEqual(stats.secondaryWindow?.usedPercent, 34)
    }

    func testIgnoresNonRateLimitMessages() {
        let output = """
        {"id":1,"result":{"userAgent":"Codex"}}
        {"method":"remoteControl/status/changed","params":{"status":"disabled"}}
        """

        XCTAssertNil(CodexRateLimitParser.parseOutput(output))
    }

    func testClassifiesAuthErrorsAsAuthRequired() throws {
        let output = #"{"id":2,"error":{"message":"Unauthorized: please sign in"}}"#

        let error = try XCTUnwrapFailure(CodexRateLimitParser.parseOutput(output))

        XCTAssertEqual(error, .authRequired("Codex is not signed in. Open Codex and sign in, then refresh."))
    }

    func testClassifiesNonAuthErrorsAsTransient() throws {
        let output = #"{"id":2,"error":{"message":"app-server still warming"}}"#

        let error = try XCTUnwrapFailure(CodexRateLimitParser.parseOutput(output))

        XCTAssertEqual(error, .transient("Codex rate limits are temporarily unavailable: app-server still warming"))
    }

    func testMissingWindowsIsTransient() throws {
        let output = #"{"id":2,"result":{"rateLimitsByLimitId":{"codex":{"planType":"plus"}}}}"#

        let error = try XCTUnwrapFailure(CodexRateLimitParser.parseOutput(output))

        XCTAssertEqual(error, .transient("Codex rate limit response did not include usage windows."))
    }
}

private func XCTUnwrapSuccess<T, E: Error>(
    _ result: Result<T, E>?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> T {
    switch try XCTUnwrap(result, file: file, line: line) {
    case .success(let value):
        return value
    case .failure(let error):
        XCTFail("Expected success, got \(error)", file: file, line: line)
        throw error
    }
}

private func XCTUnwrapFailure<T, E: Error>(
    _ result: Result<T, E>?,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> E {
    switch try XCTUnwrap(result, file: file, line: line) {
    case .success(let value):
        XCTFail("Expected failure, got \(value)", file: file, line: line)
        throw NSError(domain: "CodexRateLimitParserTests", code: 1)
    case .failure(let error):
        return error
    }
}
