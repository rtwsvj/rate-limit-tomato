import XCTest
@testable import TomatoCore

final class ClockTests: XCTestCase {
    func testSystemClockReturnsCurrentDate() {
        let clock = SystemClock()
        let before = Date()
        let now = clock.now()
        let after = Date()
        XCTAssertGreaterThanOrEqual(now, before)
        XCTAssertLessThanOrEqual(now, after)
    }

    func testMockClockAdvances() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MockClock(start: start)
        XCTAssertEqual(clock.now(), start)
        clock.advance(by: 30)
        XCTAssertEqual(clock.now().timeIntervalSince(start), 30, accuracy: 0.001)
        clock.advance(by: 70)
        XCTAssertEqual(clock.now().timeIntervalSince(start), 100, accuracy: 0.001)
    }

    func testMockClockSet() {
        let clock = MockClock(start: Date(timeIntervalSince1970: 0))
        let target = Date(timeIntervalSince1970: 99_999)
        clock.set(now: target)
        XCTAssertEqual(clock.now(), target)
    }

    func testSystemClockIsSendable() {
        // 编译期即可验证：SystemClock 标记 Sendable 通过协议约束。
        let _: any TomatoClock = SystemClock()
    }
}
