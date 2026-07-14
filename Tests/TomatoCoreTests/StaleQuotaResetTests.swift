import XCTest
@testable import TomatoCore

/// 冷启动加载昨日额度必须换新（否则 usedToday 沿用且
/// checkDailyReset 因 currentDayKey 已是今天而永不触发 → 永锁 503）。
final class StaleQuotaResetTests: XCTestCase {
    func testStaleQuotaIsReplacedOnInit() {
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_751_965_200))
        let today = TomatoEngine.dateKey(now: clock.now(), calendar: .current)
        let stale = DailyQuota(date: "2001-01-01", usedToday: 8, maxPerDay: 8,
                               completedCount: 8, abortedCount: 0)
        let engine = TomatoEngine(clock: clock, settings: .default, quota: stale)

        XCTAssertEqual(engine.quota.date, today)
        XCTAssertEqual(engine.quota.usedToday, 0)
        XCTAssertFalse(engine.isQuotaExhausted)
        XCTAssertTrue(engine.didDailyReset, "换新旧额度应标记日终重置（UI 显示 Good morning）")
        XCTAssertTrue(engine.sendRequest())
    }

    func testTodayQuotaIsKeptOnInit() {
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_751_965_200))
        let today = TomatoEngine.dateKey(now: clock.now(), calendar: .current)
        let current = DailyQuota(date: today, usedToday: 3, maxPerDay: 8,
                                 completedCount: 3, abortedCount: 0)
        let engine = TomatoEngine(clock: clock, settings: .default, quota: current)

        XCTAssertEqual(engine.quota.usedToday, 3)
        XCTAssertFalse(engine.didDailyReset)
    }

    func testFutureQuotaIsKeptAcrossClockRollbackAndRestart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let live = Date(timeIntervalSince1970: 1_751_965_200)
        let future = calendar.date(byAdding: .day, value: 1, to: live)!
        let futureKey = TomatoEngine.dateKey(now: future, calendar: calendar)
        let clock = MockClock(start: live)
        let persisted = DailyQuota(
            date: futureKey,
            usedToday: 8,
            maxPerDay: 8,
            completedCount: 8,
            abortedCount: 0
        )

        let engine = TomatoEngine(
            clock: clock,
            calendar: calendar,
            settings: .default,
            quota: persisted
        )

        XCTAssertEqual(engine.currentDayKey, futureKey)
        XCTAssertEqual(engine.quota, persisted)
        XCTAssertTrue(engine.isQuotaExhausted)
        XCTAssertFalse(engine.didDailyReset)

        let snapshot = EngineSnapshot(
            phase: .idle,
            phaseEnteredAt: live,
            currentSession: nil,
            consecutiveAborts: [],
            currentDayKey: futureKey
        )
        engine.restore(from: snapshot)
        XCTAssertEqual(engine.currentDayKey, futureKey)
        XCTAssertEqual(engine.quota.usedToday, 8)

        clock.advance(by: TomatoEngine.secondsPerDay)
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.quota.usedToday, 8, "returning to the persisted day is not a new day")

        clock.advance(by: TomatoEngine.secondsPerDay)
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.quota.usedToday, 0)
        XCTAssertTrue(engine.didDailyReset)
    }
}
