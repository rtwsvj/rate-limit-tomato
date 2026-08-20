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
