import XCTest
@testable import TomatoCore

final class TomatoEngineTests: XCTestCase {
    func testUpgradeNudgeEveryFifthCompletion() {
        let clock = MockClock()
        var settings = AppSettings.default
        settings.focusDurationMin = 1
        settings.cooldownDurationMin = 1
        settings.maxPerDay = 20
        let engine = TomatoEngine(clock: clock, settings: settings)

        func completeCycle() {
            XCTAssertTrue(engine.sendRequest())
            clock.advance(by: PhaseTiming.sending)
            engine.tick()
            clock.advance(by: 60)
            engine.tick()
            clock.advance(by: PhaseTiming.completed)
            engine.tick()
            engine.skipCooldown()
        }

        for _ in 0..<4 { completeCycle() }
        XCTAssertFalse(engine.shouldNudgeUpgrade)
        completeCycle()
        XCTAssertTrue(engine.shouldNudgeUpgrade)
        engine.clearUpgradeNudgeFlag()
        XCTAssertFalse(engine.shouldNudgeUpgrade)
        for _ in 0..<5 { completeCycle() }
        XCTAssertTrue(engine.shouldNudgeUpgrade)
    }
    // 用固定起点日历，跨天测试可重现。
    private var calendar: Calendar!
    private var day1: Date!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = cal
        var c = DateComponents()
        c.year = 2026
        c.month = 7
        c.day = 8
        c.hour = 10
        c.minute = 0
        c.second = 0
        self.day1 = cal.date(from: c)
    }

    private func makeEngine(
        settings: AppSettings = .default,
        quota: DailyQuota? = nil
    ) -> (TomatoEngine, MockClock) {
        let clock = MockClock(start: day1)
        let engine = TomatoEngine(clock: clock, calendar: calendar, settings: settings, quota: quota)
        return (engine, clock)
    }

    // MARK: - Initial state

    func testInitialState() {
        let (engine, _) = makeEngine()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.currentSession)
        XCTAssertEqual(engine.quota.usedToday, 0)
        XCTAssertEqual(engine.remaining, 8)
        XCTAssertEqual(engine.maxPerDay, 8)
        XCTAssertFalse(engine.isQuotaExhausted)
        XCTAssertFalse(engine.didDailyReset)
    }

    // MARK: - Full happy path

    func testFullCycleIdleToIdle() {
        let (engine, clock) = makeEngine()
        XCTAssertTrue(engine.sendRequest())
        XCTAssertEqual(engine.phase, .sending)
        XCTAssertEqual(engine.quota.usedToday, 1)
        XCTAssertNotNil(engine.currentSession)

        // SENDING 1.5s -> FOCUSING
        clock.advance(by: 1.4)
        engine.tick()
        XCTAssertEqual(engine.phase, .sending)
        clock.advance(by: 0.2)
        engine.tick()
        XCTAssertEqual(engine.phase, .focusing)

        // FOCUSING 25 min -> COMPLETED
        clock.advance(by: TimeInterval(25 * 60))
        engine.tick()
        XCTAssertEqual(engine.phase, .completed)
        XCTAssertEqual(engine.currentSession?.status, .completed)
        XCTAssertEqual(engine.currentSession?.durationMin, 25)
        XCTAssertEqual(engine.quota.completedCount, 1)

        // COMPLETED 2s -> RATE_LIMITED
        clock.advance(by: 1.9)
        engine.tick()
        XCTAssertEqual(engine.phase, .completed)
        clock.advance(by: 0.2)
        engine.tick()
        XCTAssertEqual(engine.phase, .rateLimited)

        // RATE_LIMITED 5 min -> RESET
        clock.advance(by: TimeInterval(5 * 60))
        engine.tick()
        XCTAssertEqual(engine.phase, .reset)

        // RESET 2s -> IDLE
        clock.advance(by: 1.9)
        engine.tick()
        XCTAssertEqual(engine.phase, .reset)
        clock.advance(by: 0.2)
        engine.tick()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.currentSession)
    }

    // MARK: - SENDING transition boundary

    func testSendingToFocusingExactlyAtThreshold() {
        let (engine, clock) = makeEngine()
        engine.sendRequest()
        XCTAssertEqual(engine.phase, .sending)
        clock.advance(by: 1.5)
        engine.tick()
        XCTAssertEqual(engine.phase, .focusing)
    }

    func testSendingHoldsUnderThreshold() {
        let (engine, clock) = makeEngine()
        engine.sendRequest()
        clock.advance(by: 1.499)
        engine.tick()
        XCTAssertEqual(engine.phase, .sending)
    }

    // MARK: - FOCUSING transition boundary

    func testFocusingToCompletedAtThreshold() {
        let (engine, clock) = makeEngine()
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        XCTAssertEqual(engine.phase, .focusing)
        clock.advance(by: TimeInterval(25 * 60))
        engine.tick()
        XCTAssertEqual(engine.phase, .completed)
    }

    // MARK: - ABORTED

    func testFocusingAbortGoesToAborted() {
        let (engine, clock) = makeEngine()
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        // 现在 FOCUSING
        clock.advance(by: 5 * 60)  // 5 min 实际专注
        engine.abortRequest()
        XCTAssertEqual(engine.phase, .aborted)
        XCTAssertEqual(engine.currentSession?.status, .aborted)
        XCTAssertEqual(engine.currentSession?.durationMin, 5)
        XCTAssertEqual(engine.quota.abortedCount, 1)
        XCTAssertEqual(engine.quota.completedCount, 0)
        XCTAssertEqual(engine.quota.usedToday, 1)
    }

    func testAbortRequestNoOpsOutsideFocusing() {
        let (engine, _) = makeEngine()
        // IDLE
        engine.abortRequest()
        XCTAssertEqual(engine.phase, .idle)
    }

    // MARK: - skipCooldown

    func testSkipCooldownFromRateLimited() {
        let (engine, clock) = makeEngine()
        runUntilPhase(engine: engine, clock: clock, target: .rateLimited)
        engine.skipCooldown()
        XCTAssertEqual(engine.phase, .idle)
    }

    func testSkipCooldownFromAborted() {
        let (engine, clock) = makeEngine()
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: 60)
        engine.abortRequest()
        XCTAssertEqual(engine.phase, .aborted)
        engine.skipCooldown()
        XCTAssertEqual(engine.phase, .idle)
    }

    func testSkipCooldownNoOpsFromIdle() {
        let (engine, _) = makeEngine()
        engine.skipCooldown()
        XCTAssertEqual(engine.phase, .idle)
    }

    // MARK: - startCooldown

    func testStartCooldownFromAborted() {
        let (engine, clock) = makeEngine()
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: 60)
        engine.abortRequest()
        engine.startCooldown()
        XCTAssertEqual(engine.phase, .rateLimited)
    }

    func testStartCooldownNoOpsFromIdle() {
        let (engine, _) = makeEngine()
        engine.startCooldown()
        XCTAssertEqual(engine.phase, .idle)
    }

    // MARK: - Teapot

    func testTeapotTriggersOnThreeAbortsIn30Min() {
        let (engine, clock) = makeEngine()
        for i in 0..<3 {
            engine.sendRequest()
            clock.advance(by: 1.6)
            engine.tick()
            XCTAssertEqual(engine.phase, .focusing, "iter \(i) should be focusing")
            clock.advance(by: 60)
            engine.abortRequest()
            if i < 2 {
                engine.skipCooldown()
                XCTAssertEqual(engine.phase, .idle, "iter \(i) should return to idle after skip")
            }
        }
        XCTAssertEqual(engine.phase, .teapot)
        XCTAssertEqual(engine.quota.abortedCount, 3)
    }

    func testTeapotInterruptedByCompleted() {
        let (engine, clock) = makeEngine()
        // 2 aborts
        for _ in 0..<2 {
            engine.sendRequest()
            clock.advance(by: 1.6)
            engine.tick()
            clock.advance(by: 60)
            engine.abortRequest()
            engine.skipCooldown()
        }
        // 1 complete
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: TimeInterval(25 * 60))
        engine.tick()
        // 1 more abort
        clock.advance(by: 2.0)
        engine.tick()
        clock.advance(by: TimeInterval(5 * 60))
        engine.tick()
        clock.advance(by: 2.0)
        engine.tick()
        // 现在 IDLE
        XCTAssertEqual(engine.phase, .idle)
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: 60)
        engine.abortRequest()
        XCTAssertEqual(engine.phase, .aborted, "completed should reset abort chain")
    }

    func testCompletedSessionBreaksAbortChainWithinThirtyMinuteWindow() {
        var settings = AppSettings.default
        settings.focusDurationMin = 1
        settings.cooldownDurationMin = 1
        let (engine, clock) = makeEngine(settings: settings)

        for _ in 0..<2 {
            engine.sendRequest()
            clock.advance(by: PhaseTiming.sending)
            engine.tick()
            clock.advance(by: 5)
            engine.abortRequest()
            engine.skipCooldown()
        }
        XCTAssertEqual(engine.consecutiveAborts.count, 2)

        engine.sendRequest()
        clock.advance(by: PhaseTiming.sending)
        engine.tick()
        clock.advance(by: 60)
        engine.tick()
        XCTAssertEqual(engine.phase, .completed)
        XCTAssertEqual(engine.consecutiveAborts, [], "正常完成必须立即打断连续中止链")
        clock.advance(by: PhaseTiming.completed)
        engine.tick()
        engine.skipCooldown()

        engine.sendRequest()
        clock.advance(by: PhaseTiming.sending)
        engine.tick()
        clock.advance(by: 5)
        engine.abortRequest()
        XCTAssertEqual(engine.phase, .aborted)
        XCTAssertEqual(engine.consecutiveAborts.count, 1)
    }

    func testTeapotNoTriggerOver30MinWindow() {
        let (engine, clock) = makeEngine()
        // 第 1 次 abort
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: 60)
        engine.abortRequest()
        engine.skipCooldown()
        // 跳到 31 分钟之后
        clock.advance(by: 31 * 60)
        // 第 2 次 abort
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: 60)
        engine.abortRequest()
        engine.skipCooldown()
        // 第 3 次 abort 再过 1 分钟
        clock.advance(by: 60)
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: 60)
        engine.abortRequest()
        XCTAssertEqual(engine.phase, .aborted, "3rd abort outside 30 min window should NOT trigger teapot")
    }

    func testTeapotNotTriggeredByTwoAborts() {
        let (engine, clock) = makeEngine()
        for _ in 0..<2 {
            engine.sendRequest()
            clock.advance(by: 1.6)
            engine.tick()
            clock.advance(by: 60)
            engine.abortRequest()
            engine.skipCooldown()
        }
        XCTAssertEqual(engine.phase, .idle)
    }

    func testAcknowledgeTeapot() {
        let (engine, clock) = makeEngine()
        for i in 0..<3 {
            engine.sendRequest()
            clock.advance(by: 1.6)
            engine.tick()
            clock.advance(by: 60)
            engine.abortRequest()
            if i < 2 {
                engine.skipCooldown()
            }
        }
        XCTAssertEqual(engine.phase, .teapot)
        engine.acknowledgeTeapot()
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertNil(engine.currentSession)
        XCTAssertEqual(engine.consecutiveAborts.count, 0)
    }

    // MARK: - Quota

    func testQuotaDeduction() {
        let (engine, _) = makeEngine()
        XCTAssertTrue(engine.sendRequest())
        XCTAssertEqual(engine.quota.usedToday, 1)
        XCTAssertEqual(engine.remaining, 7)
    }

    func testQuotaExhaustion() {
        let settings = AppSettings(
            focusDurationMin: 25,
            cooldownDurationMin: 5,
            longBreakMin: 15,
            maxPerDay: 2,
            provider: .a,
            language: "zh-CN",
            showFakeLogs: true,
            showFakeHeaders: true,
            soundEnabled: true,
            globalShortcut: "",
            parodyDisclaimerAck: true
        )
        let (engine, clock) = makeEngine(settings: settings)
        // 第 1 次完整循环
        runFullCycle(engine: engine, clock: clock)
        XCTAssertEqual(engine.quota.usedToday, 1)
        // 第 2 次完整循环
        runFullCycle(engine: engine, clock: clock)
        XCTAssertEqual(engine.quota.usedToday, 2)
        XCTAssertTrue(engine.isQuotaExhausted)
        // 第 3 次 sendRequest 应该被拒绝
        XCTAssertFalse(engine.sendRequest())
        XCTAssertEqual(engine.phase, .idle)
        XCTAssertEqual(engine.quota.usedToday, 2)
    }

    // MARK: - Daily reset

    func testDailyReset() {
        let (engine, clock) = makeEngine()
        // 用 1 次完整 + 1 次 abort，回到 IDLE，已用 2 次。
        runFullCycle(engine: engine, clock: clock)
        XCTAssertEqual(engine.quota.usedToday, 1)
        XCTAssertEqual(engine.quota.completedCount, 1)
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: 60)
        engine.abortRequest()
        engine.skipCooldown()
        XCTAssertEqual(engine.quota.usedToday, 2)
        XCTAssertEqual(engine.quota.abortedCount, 1)
        XCTAssertEqual(engine.phase, .idle)

        // 跳到次日（+25h）
        clock.advance(by: 25 * 3600)
        engine.tick()
        XCTAssertEqual(engine.quota.usedToday, 0)
        XCTAssertEqual(engine.quota.completedCount, 0)
        XCTAssertEqual(engine.quota.abortedCount, 0)
        XCTAssertTrue(engine.didDailyReset)
        // 标志是一次性的
        engine.clearDailyResetFlag()
        XCTAssertFalse(engine.didDailyReset)
    }

    func testDailyResetDoesNotReFlagOnSameDay() {
        let (engine, clock) = makeEngine()
        engine.clearDailyResetFlag()
        clock.advance(by: 60)
        engine.tick()
        XCTAssertFalse(engine.didDailyReset)
    }

    func testEveryUserActionChecksDailyResetBeforePhaseGuard() {
        let actions: [(String, (TomatoEngine) -> Void)] = [
            ("abort", { $0.abortRequest() }),
            ("skip cooldown", { $0.skipCooldown() }),
            ("start cooldown", { $0.startCooldown() }),
            ("acknowledge teapot", { $0.acknowledgeTeapot() }),
        ]

        for (name, action) in actions {
            let (engine, clock) = makeEngine()
            let previousDate = engine.quota.date
            clock.advance(by: 25 * 60 * 60)

            action(engine)

            XCTAssertNotEqual(engine.quota.date, previousDate, "\(name) skipped daily reset")
            XCTAssertEqual(engine.quota.date, TomatoEngine.dateKey(now: clock.now(), calendar: calendar))
            XCTAssertTrue(engine.didDailyReset, "\(name) did not publish the daily reset")
            XCTAssertEqual(engine.phase, .idle, "\(name) should remain a phase no-op")
        }
    }

    func testSessionCompletedAcrossMidnightBelongsToStartDayWithoutPollutingNewQuota() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 8
        components.hour = 23
        components.minute = 59
        components.second = 30
        let start = calendar.date(from: components)!
        let clock = MockClock(start: start)
        var settings = AppSettings.default
        settings.focusDurationMin = 1
        let engine = TomatoEngine(clock: clock, calendar: calendar, settings: settings)

        XCTAssertTrue(engine.sendRequest())
        let startDay = engine.currentSession?.date
        clock.advance(by: PhaseTiming.sending)
        engine.tick()
        clock.advance(by: 60)
        engine.tick()

        XCTAssertEqual(engine.phase, .completed)
        XCTAssertEqual(engine.currentSession?.date, startDay)
        XCTAssertEqual(startDay, "2026-07-08")
        XCTAssertEqual(engine.quota.date, "2026-07-09")
        XCTAssertEqual(engine.quota.usedToday, 0)
        XCTAssertEqual(engine.quota.completedCount, 0)
        XCTAssertEqual(engine.quota.abortedCount, 0)
    }

    func testSessionAbortedAcrossMidnightBelongsToStartDayWithoutPollutingNewQuota() {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 8
        components.hour = 23
        components.minute = 59
        components.second = 30
        let start = calendar.date(from: components)!
        let clock = MockClock(start: start)
        let engine = TomatoEngine(clock: clock, calendar: calendar)

        XCTAssertTrue(engine.sendRequest())
        clock.advance(by: PhaseTiming.sending)
        engine.tick()
        clock.advance(by: 60)
        engine.abortRequest()

        XCTAssertEqual(engine.phase, .aborted)
        XCTAssertEqual(engine.currentSession?.date, "2026-07-08")
        XCTAssertEqual(engine.quota.date, "2026-07-09")
        XCTAssertEqual(engine.quota.usedToday, 0)
        XCTAssertEqual(engine.quota.completedCount, 0)
        XCTAssertEqual(engine.quota.abortedCount, 0)
        XCTAssertEqual(engine.consecutiveAborts.count, 1)
    }

    func testRestoringOldDaySnapshotDoesNotResetValidTodayQuotaOnNextTick() {
        let todayKey = TomatoEngine.dateKey(now: day1, calendar: calendar)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day1)!
        let yesterdayKey = TomatoEngine.dateKey(now: yesterday, calendar: calendar)
        let quota = DailyQuota(
            date: todayKey,
            usedToday: 3,
            maxPerDay: AppSettings.default.maxPerDay,
            completedCount: 2,
            abortedCount: 1
        )
        let (engine, _) = makeEngine(quota: quota)
        let snapshot = EngineSnapshot(
            phase: .aborted,
            phaseEnteredAt: yesterday.addingTimeInterval(60),
            currentSession: FocusSession(
                id: "focus_old_day",
                createdAt: yesterday,
                date: yesterdayKey,
                startHour: 10,
                startMinute: 0,
                durationMin: 1,
                status: .aborted,
                quality: 0,
                fakeTokens: 0,
                fakeModel: "tomato-test",
                note: nil,
                provider: .a
            ),
            consecutiveAborts: [yesterday.addingTimeInterval(60)],
            currentDayKey: yesterdayKey
        )

        engine.restore(from: snapshot)
        XCTAssertEqual(engine.currentDayKey, todayKey)
        XCTAssertEqual(engine.quota.usedToday, 3)
        XCTAssertTrue(engine.didDailyReset)
        XCTAssertTrue(engine.consecutiveAborts.isEmpty)

        engine.tick()
        XCTAssertEqual(engine.quota.usedToday, 3)
        XCTAssertEqual(engine.quota.completedCount, 2)
        XCTAssertEqual(engine.quota.abortedCount, 1)
    }

    // MARK: - Focus/cooldown timers

    func testFocusRemainingShrinksAsTimePasses() {
        let (engine, clock) = makeEngine()
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        XCTAssertEqual(engine.phase, .focusing)
        let total = TimeInterval(25 * 60)
        XCTAssertEqual(engine.focusRemaining, total, accuracy: 0.01)
        clock.advance(by: 5 * 60)
        XCTAssertEqual(engine.focusRemaining, total - 5 * 60, accuracy: 0.01)
        XCTAssertEqual(engine.focusElapsed, 5 * 60, accuracy: 0.01)
    }

    func testCooldownResetAtMatchesEnteredAtPlusDuration() {
        let (engine, clock) = makeEngine()
        runUntilPhase(engine: engine, clock: clock, target: .rateLimited)
        let expected = clock.now().addingTimeInterval(TimeInterval(engine.settings.cooldownDurationMin * 60))
        XCTAssertEqual(engine.cooldownResetAt.timeIntervalSince(expected), 0, accuracy: 0.01)
    }

    func testCooldownRemaining() {
        let (engine, clock) = makeEngine()
        runUntilPhase(engine: engine, clock: clock, target: .rateLimited)
        let total = TimeInterval(5 * 60)
        XCTAssertEqual(engine.cooldownRemaining, total, accuracy: 0.01)
        clock.advance(by: 60)
        XCTAssertEqual(engine.cooldownRemaining, total - 60, accuracy: 0.01)
    }

    // MARK: - Settings

    func testUpdateSettingsSyncsMaxPerDay() {
        let (engine, _) = makeEngine()
        var s = engine.settings
        s.maxPerDay = 4
        engine.updateSettings(s)
        XCTAssertEqual(engine.maxPerDay, 4)
        XCTAssertEqual(engine.quota.maxPerDay, 4)
    }

    // MARK: - Helpers

    /// 把引擎一路推进到 target 阶段。
    private func runUntilPhase(
        engine: TomatoEngine,
        clock: MockClock,
        target: AppPhase
    ) {
        var safety = 0
        while engine.phase != target {
            XCTAssertLessThan(safety, 200, "runUntilPhase 死循环（target=\(target), current=\(engine.phase)）")
            safety += 1
            switch engine.phase {
            case .idle:
                engine.sendRequest()
            case .sending:
                clock.advance(by: 1.6)
                engine.tick()
            case .focusing:
                clock.advance(by: TimeInterval(engine.settings.focusDurationMin * 60))
                engine.tick()
            case .completed:
                clock.advance(by: 2.1)
                engine.tick()
            case .rateLimited:
                clock.advance(by: TimeInterval(engine.settings.cooldownDurationMin * 60))
                engine.tick()
            case .reset:
                clock.advance(by: 2.1)
                engine.tick()
            case .aborted, .teapot:
                XCTFail("unexpected phase \(engine.phase) in runUntilPhase")
            }
        }
    }

    private func runFullCycle(engine: TomatoEngine, clock: MockClock) {
        // 假设当前 IDLE，跑完一整个 send→focus→complete→cool→reset→idle 循环。
        XCTAssertEqual(engine.phase, .idle, "runFullCycle expects IDLE start")
        XCTAssertTrue(engine.sendRequest())
        clock.advance(by: 1.6)
        engine.tick()
        XCTAssertEqual(engine.phase, .focusing)
        clock.advance(by: TimeInterval(engine.settings.focusDurationMin * 60))
        engine.tick()
        XCTAssertEqual(engine.phase, .completed)
        clock.advance(by: 2.1)
        engine.tick()
        XCTAssertEqual(engine.phase, .rateLimited)
        clock.advance(by: TimeInterval(engine.settings.cooldownDurationMin * 60))
        engine.tick()
        XCTAssertEqual(engine.phase, .reset)
        clock.advance(by: 2.1)
        engine.tick()
        XCTAssertEqual(engine.phase, .idle)
    }
}
