import XCTest
@testable import TomatoCore

final class FakeHeaderGeneratorTests: XCTestCase {
    func testRateLimitedHeadersLineByLine() {
        let reset = Date(timeIntervalSince1970: 1_719_850_320)
        let result = FakeHeaderGenerator.rateLimited(
            limit: 8,
            remaining: 0,
            resetAt: reset,
            retryAfter: 300
        )
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.count, 6, "header block must have exactly 6 lines")
        XCTAssertEqual(lines[0], "HTTP/1.1 429 Too Many Requests")
        XCTAssertEqual(lines[1], "Content-Type: application/json")
        XCTAssertEqual(lines[2], "X-RateLimit-Limit: 8")
        XCTAssertEqual(lines[3], "X-RateLimit-Remaining: 0")
        XCTAssertEqual(lines[4], "X-RateLimit-Reset: 1719850320")
        XCTAssertEqual(lines[5], "Retry-After: 300")
    }

    func testEpochEncoding() {
        let reset = Date(timeIntervalSince1970: 1_700_000_000)
        let result = FakeHeaderGenerator.rateLimited(
            limit: 5,
            remaining: 1,
            resetAt: reset,
            retryAfter: 60
        )
        XCTAssertTrue(result.contains("X-RateLimit-Reset: 1700000000"))
        XCTAssertTrue(result.contains("Retry-After: 60"))
    }

    func testRetryAfterRoundsToInt() {
        let reset = Date(timeIntervalSince1970: 1_700_000_000)
        let result = FakeHeaderGenerator.rateLimited(
            limit: 1,
            remaining: 0,
            resetAt: reset,
            retryAfter: 300.7
        )
        XCTAssertTrue(result.contains("Retry-After: 301"))
    }
}
