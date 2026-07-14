import XCTest
@testable import TomatoCore

final class TimeMapperTests: XCTestCase {
    // MARK: - progressFraction

    func testProgressFractionZero() {
        XCTAssertEqual(TimeMapper.progressFraction(elapsed: 0, total: 100), 0)
    }

    func testProgressFractionHalf() {
        XCTAssertEqual(TimeMapper.progressFraction(elapsed: 50, total: 100), 0.5, accuracy: 0.0001)
    }

    func testProgressFractionFull() {
        XCTAssertEqual(TimeMapper.progressFraction(elapsed: 100, total: 100), 1)
    }

    func testProgressFractionOverClamps() {
        XCTAssertEqual(TimeMapper.progressFraction(elapsed: 150, total: 100), 1)
    }

    func testProgressFractionNegativeClamps() {
        XCTAssertEqual(TimeMapper.progressFraction(elapsed: -10, total: 100), 0)
    }

    func testProgressFractionZeroTotalReturnsZero() {
        XCTAssertEqual(TimeMapper.progressFraction(elapsed: 50, total: 0), 0)
    }

    func testProgressFractionNegativeTotalReturnsZero() {
        XCTAssertEqual(TimeMapper.progressFraction(elapsed: 50, total: -10), 0)
    }

    // MARK: - focusWindowDisplay

    func testFocusWindowDisplayZero() {
        XCTAssertEqual(
            TimeMapper.focusWindowDisplay(elapsed: 0, total: 25 * 60),
            "0h 00m 00s / 5h00m00s"
        )
    }

    func testFocusWindowDisplayHalf() {
        // 12.5 min / 25 min = 0.5 -> 2.5h -> 2h 30m
        XCTAssertEqual(
            TimeMapper.focusWindowDisplay(elapsed: 12.5 * 60, total: 25 * 60),
            "2h 30m 00s / 5h00m00s"
        )
    }

    func testFocusWindowDisplayFull() {
        XCTAssertEqual(
            TimeMapper.focusWindowDisplay(elapsed: 25 * 60, total: 25 * 60),
            "5h 00m 00s / 5h00m00s"
        )
    }

    func testFocusWindowDisplayOverClamps() {
        XCTAssertEqual(
            TimeMapper.focusWindowDisplay(elapsed: 99 * 60, total: 25 * 60),
            "5h 00m 00s / 5h00m00s"
        )
    }

    func testFocusWindowDisplayZeroTotalClamps() {
        // 0 total 时 progressFraction 返回 0
        XCTAssertEqual(
            TimeMapper.focusWindowDisplay(elapsed: 100, total: 0),
            "0h 00m 00s / 5h00m00s"
        )
    }

    func testFocusWindowDisplaySecondsPadded() {
        // 0.001/25 min ≈ 0.0000007 of 5h = 0.001*12s = 0.012s → 0s
        // 6.25 min / 25 min = 0.25 -> 1.25h -> 1h 15m
        XCTAssertEqual(
            TimeMapper.focusWindowDisplay(elapsed: 6.25 * 60, total: 25 * 60),
            "1h 15m 00s / 5h00m00s"
        )
    }

    // MARK: - resetTimeDisplay

    func testResetTimeDisplayFormat() {
        // 14:32 local
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 7
        comps.day = 8
        comps.hour = 14
        comps.minute = 32
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(
            TimeMapper.resetTimeDisplay(resetAt: date, calendar: Calendar(identifier: .gregorian)),
            "14:32"
        )
    }

    func testResetTimeDisplayPaddedHour() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 1
        comps.day = 1
        comps.hour = 3
        comps.minute = 5
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(
            TimeMapper.resetTimeDisplay(resetAt: date, calendar: Calendar(identifier: .gregorian)),
            "03:05"
        )
    }
}
