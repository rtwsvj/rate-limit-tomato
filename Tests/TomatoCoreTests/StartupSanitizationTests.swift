import XCTest
@testable import TomatoCore

/// 快照时间戳、结构合法性与 AppSettings sanitized()。
final class StartupSanitizationTests: XCTestCase {
    // MARK: - AppSettings.sanitized()

    func testAppSettingsSanitizedClampsAllDurationFields() {
        let s = AppSettings(
            focusDurationMin: 100_000,
            cooldownDurationMin: -10,
            longBreakMin: 999_999,
            maxPerDay: 0,
            provider: .a,
            language: "zh-CN",
            showFakeLogs: false,
            showFakeHeaders: false,
            soundEnabled: false,
            globalShortcut: "",
            parodyDisclaimerAck: false
        )
        let c = s.sanitized()
        XCTAssertEqual(c.focusDurationMin, AppSettings.focusRange.upperBound)
        XCTAssertEqual(c.cooldownDurationMin, AppSettings.cooldownRange.lowerBound)
        XCTAssertEqual(c.longBreakMin, AppSettings.longBreakRange.upperBound)
        XCTAssertEqual(c.maxPerDay, AppSettings.maxPerDayRange.lowerBound)
        XCTAssertFalse(c.parodyDisclaimerAck, "sanitized 不动非数值字段")
    }

    func testAppSettingsSanitizedLowerBounds() {
        let s = AppSettings(
            focusDurationMin: -500,
            cooldownDurationMin: -1,
            longBreakMin: -1,
            maxPerDay: -10,
            provider: .a,
            language: "en",
            showFakeLogs: true, showFakeHeaders: true, soundEnabled: true,
            globalShortcut: "", parodyDisclaimerAck: true
        )
        let c = s.sanitized()
        XCTAssertEqual(c.focusDurationMin, AppSettings.focusRange.lowerBound)
        XCTAssertEqual(c.cooldownDurationMin, AppSettings.cooldownRange.lowerBound)
        XCTAssertEqual(c.longBreakMin, AppSettings.longBreakRange.lowerBound)
        XCTAssertEqual(c.maxPerDay, AppSettings.maxPerDayRange.lowerBound)
    }

    func testAppSettingsSanitizedPassesThroughValidValues() {
        let s = AppSettings(
            focusDurationMin: 30,
            cooldownDurationMin: 5,
            longBreakMin: 20,
            maxPerDay: 6,
            provider: .b,
            language: "en",
            showFakeLogs: false, showFakeHeaders: true, soundEnabled: false,
            globalShortcut: "cmd+shift+z", parodyDisclaimerAck: true
        )
        let c = s.sanitized()
        XCTAssertEqual(c.focusDurationMin, 30)
        XCTAssertEqual(c.cooldownDurationMin, 5)
        XCTAssertEqual(c.longBreakMin, 20)
        XCTAssertEqual(c.maxPerDay, 6)
        XCTAssertEqual(c.language, "en")
        XCTAssertEqual(c.provider, .b)
        XCTAssertEqual(c.globalShortcut, "cmd+shift+z", "sanitized 不动字符串字段")
    }

    func testAppSettingsSanitizedLanguageFallsBackToZhCN() {
        for bad in ["ja-JP", "fr", "", "EN_us"] {
            var s = AppSettings.default
            s.language = bad
            XCTAssertEqual(s.sanitized().language, AppSettings.default.language,
                           "非法语言 \"\(bad)\" 应回落 zh-CN")
        }
    }

    func testAppSettingsSanitizedPreservesSupportedLanguages() {
        for lang in ["zh-CN", "en"] {
            var s = AppSettings.default
            s.language = lang
            XCTAssertEqual(s.sanitized().language, lang)
        }
    }

    // MARK: - isValidSnapshot

    func testValidSnapshotWithinWindowIsAccepted() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar(identifier: .gregorian)
        let snap = EngineSnapshot(
            phase: .idle, phaseEnteredAt: now,
            currentSession: nil, consecutiveAborts: [], currentDayKey: "2026-07-08")
        XCTAssertTrue(TomatoEngine.isValidSnapshot(snap, now: now))
        // now 后退 4 分钟，相对偏移 = +4min（轻微时钟回拨，合法）
        XCTAssertTrue(TomatoEngine.isValidSnapshot(snap, now: now.addingTimeInterval(-4 * 60)))
        // now 前进 2 小时，相对偏移 = -2h（合法）
        XCTAssertTrue(TomatoEngine.isValidSnapshot(snap, now: now.addingTimeInterval(7200)))
        // snapshot = now - 6d（合法，位于长期恢复窗口内）
        let sixDaysAgo = EngineSnapshot(phase: .idle,
                                        phaseEnteredAt: now.addingTimeInterval(-6 * 86400),
                                        currentSession: nil, consecutiveAborts: [],
                                        currentDayKey: "2026-07-08")
        XCTAssertTrue(TomatoEngine.isValidSnapshot(sixDaysAgo, now: now))
        // now 推后 23h，相对偏移为过去 23h，仍在长期恢复下界内
        XCTAssertTrue(TomatoEngine.isValidSnapshot(snap, now: now.addingTimeInterval(23 * 3600)))
        _ = cal
    }

    func testSnapshotMoreThanFiveMinutesInFutureIsRejected() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = EngineSnapshot(
            phase: .idle,
            phaseEnteredAt: now.addingTimeInterval(5 * 60 + 1),
            currentSession: nil, consecutiveAborts: [], currentDayKey: "2026-07-08")
        XCTAssertFalse(TomatoEngine.isValidSnapshot(snap, now: now))
        XCTAssertFalse(TomatoEngine.isValidSnapshot(snap, now: Date.distantPast),
                      "相对当前时钟明显位于未来的快照必须拒绝")
    }

    func testSnapshotOlderThanTenYearRecoveryWindowIsRejected() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = EngineSnapshot(
            phase: .idle,
            phaseEnteredAt: now.addingTimeInterval(-(TomatoEngine.snapshotPastDays + 1) * 86400),
            currentSession: nil, consecutiveAborts: [], currentDayKey: "2026-07-08")
        XCTAssertFalse(TomatoEngine.isValidSnapshot(snap, now: now))
    }

    func testDistantPastAndDistantFutureAreRejected() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let farFutureSnap = EngineSnapshot(phase: .idle,
                                           phaseEnteredAt: .distantFuture,
                                           currentSession: nil,
                                           consecutiveAborts: [],
                                           currentDayKey: "9999-99-99")
        XCTAssertFalse(TomatoEngine.isValidSnapshot(farFutureSnap, now: now))
        let farPastSnap = EngineSnapshot(phase: .idle,
                                         phaseEnteredAt: .distantPast,
                                         currentSession: nil,
                                         consecutiveAborts: [],
                                         currentDayKey: "0000-01-01")
        XCTAssertFalse(TomatoEngine.isValidSnapshot(farPastSnap, now: now))
    }

    func testIsValidSnapshotWithClockOverload() {
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let snap = EngineSnapshot(phase: .idle,
                                  phaseEnteredAt: clock.now(),
                                  currentSession: nil,
                                  consecutiveAborts: [],
                                  currentDayKey: "2026-07-08")
        XCTAssertTrue(TomatoEngine.isValidSnapshot(snap, clock: clock))
    }

    func testSnapshotExactlyAtRecoveryBoundaryIsAccepted() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let at = now.addingTimeInterval(TomatoEngine.snapshotPastWindow)
        let snap = EngineSnapshot(phase: .idle, phaseEnteredAt: at,
                                  currentSession: nil, consecutiveAborts: [],
                                  currentDayKey: "2026-07-08")
        XCTAssertTrue(TomatoEngine.isValidSnapshot(snap, now: now),
                      "长期恢复边界内接受；正好位于下界时通过")
    }

    func testSnapshotExactlyAtFutureToleranceBoundaryIsAccepted() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let at = now.addingTimeInterval(TomatoEngine.snapshotFutureWindow)
        let snap = EngineSnapshot(phase: .idle, phaseEnteredAt: at,
                                  currentSession: nil, consecutiveAborts: [],
                                  currentDayKey: "2026-07-08")
        XCTAssertTrue(TomatoEngine.isValidSnapshot(snap, now: now))
    }

    func testSnapshotJustBeyondFutureToleranceIsRejected() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let at = now.addingTimeInterval(TomatoEngine.snapshotFutureWindow + 1)
        let snap = EngineSnapshot(phase: .idle, phaseEnteredAt: at,
                                  currentSession: nil, consecutiveAborts: [],
                                  currentDayKey: "2026-07-08")
        XCTAssertFalse(TomatoEngine.isValidSnapshot(snap, now: now))
    }

    func testSnapshotPastOver6DaysStillAccepted() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snap = EngineSnapshot(phase: .idle,
                                  phaseEnteredAt: now.addingTimeInterval(-6 * 86400 - 23 * 3600),
                                  currentSession: nil, consecutiveAborts: [],
                                  currentDayKey: "2026-07-08")
        XCTAssertTrue(TomatoEngine.isValidSnapshot(snap, now: now))
    }

    func testSnapshotRejectsPhaseSessionStatusMismatchAndInvalidDateKey() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(
            id: "focus_snapshot",
            createdAt: now.addingTimeInterval(-60),
            date: TomatoEngine.dateKey(now: now, calendar: calendar),
            startHour: 0, startMinute: 0, durationMin: 0,
            status: .focusing, quality: 0, fakeTokens: 0,
            fakeModel: "tomato-1.0", note: nil, provider: .a
        )
        let mismatched = EngineSnapshot(
            phase: .completed,
            phaseEnteredAt: now,
            currentSession: session,
            consecutiveAborts: [],
            currentDayKey: session.date
        )
        XCTAssertNil(TomatoEngine.validatedSnapshot(mismatched, now: now, calendar: calendar))

        var badDate = EngineSnapshot(
            phase: .focusing,
            phaseEnteredAt: now,
            currentSession: session,
            consecutiveAborts: [],
            currentDayKey: "2026-02-31"
        )
        XCTAssertNil(TomatoEngine.validatedSnapshot(badDate, now: now, calendar: calendar))
        badDate.currentDayKey = session.date
        XCTAssertNotNil(TomatoEngine.validatedSnapshot(badDate, now: now, calendar: calendar))

        var inconsistentSession = session
        inconsistentSession = FocusSession(
            id: inconsistentSession.id,
            createdAt: inconsistentSession.createdAt,
            date: "2026-07-08",
            startHour: 24,
            startMinute: inconsistentSession.startMinute,
            durationMin: inconsistentSession.durationMin,
            status: inconsistentSession.status,
            quality: inconsistentSession.quality,
            fakeTokens: inconsistentSession.fakeTokens,
            fakeModel: inconsistentSession.fakeModel,
            note: inconsistentSession.note,
            provider: inconsistentSession.provider
        )
        badDate.currentSession = inconsistentSession
        XCTAssertNil(TomatoEngine.validatedSnapshot(badDate, now: now, calendar: calendar))
    }

    func testSnapshotRejectsSessionDurationAtIntMax() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let dateKey = TomatoEngine.dateKey(now: now, calendar: calendar)
        let session = FocusSession(
            id: "focus_duration_overflow",
            createdAt: now.addingTimeInterval(-60),
            date: dateKey,
            startHour: 22,
            startMinute: 0,
            durationMin: Int.max,
            status: .completed,
            quality: 0,
            fakeTokens: 0,
            fakeModel: "tomato-1.0",
            note: nil,
            provider: .a
        )
        let snapshot = EngineSnapshot(
            phase: .completed,
            phaseEnteredAt: now,
            currentSession: session,
            consecutiveAborts: [],
            currentDayKey: dateKey
        )

        XCTAssertNil(TomatoEngine.validatedSnapshot(snapshot, now: now, calendar: calendar))
    }

    func testSnapshotAcceptsSessionDurationAtUpperBoundary() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let dateKey = TomatoEngine.dateKey(now: now, calendar: calendar)
        let upperBound = TomatoStore.durationRange.upperBound
        XCTAssertEqual(upperBound, 1_440, "snapshot 与 Store 必须共用 24 小时上限")
        let session = FocusSession(
            id: "focus_duration_boundary",
            createdAt: now.addingTimeInterval(-60),
            date: dateKey,
            startHour: 22,
            startMinute: 0,
            durationMin: upperBound,
            status: .completed,
            quality: 0,
            fakeTokens: 0,
            fakeModel: "tomato-1.0",
            note: nil,
            provider: .a
        )
        let snapshot = EngineSnapshot(
            phase: .completed,
            phaseEnteredAt: now,
            currentSession: session,
            consecutiveAborts: [],
            currentDayKey: dateKey
        )

        let validated = TomatoEngine.validatedSnapshot(snapshot, now: now, calendar: calendar)
        XCTAssertEqual(validated?.currentSession?.durationMin, upperBound)
    }

    func testSnapshotCleansAbortChainAndRequiresThreeForTeapot() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let dateKey = TomatoEngine.dateKey(now: now, calendar: calendar)
        let aborted = FocusSession(
            id: "focus_aborted",
            createdAt: now.addingTimeInterval(-20 * 60),
            date: dateKey,
            startHour: 0, startMinute: 0, durationMin: 5,
            status: .aborted, quality: 0, fakeTokens: 0,
            fakeModel: "tomato-1.0", note: nil, provider: .a
        )
        let rawDates = [
            now.addingTimeInterval(-31 * 60),
            now.addingTimeInterval(-2 * 60),
            now.addingTimeInterval(10),
            now.addingTimeInterval(-10 * 60),
            now.addingTimeInterval(-5 * 60),
        ]
        let abortedSnapshot = EngineSnapshot(
            phase: .aborted, phaseEnteredAt: now,
            currentSession: aborted, consecutiveAborts: rawDates,
            currentDayKey: dateKey
        )
        let cleaned = TomatoEngine.validatedSnapshot(
            abortedSnapshot, now: now, calendar: calendar
        )
        XCTAssertEqual(cleaned?.consecutiveAborts, [
            now.addingTimeInterval(-5 * 60),
            now.addingTimeInterval(-2 * 60),
        ])

        var teapot = abortedSnapshot
        teapot.phase = .teapot
        teapot.consecutiveAborts = Array(rawDates.suffix(2))
        XCTAssertNil(TomatoEngine.validatedSnapshot(teapot, now: now, calendar: calendar))
        teapot.consecutiveAborts = [
            now.addingTimeInterval(-10 * 60),
            now.addingTimeInterval(-5 * 60),
            now.addingTimeInterval(-2 * 60),
        ]
        XCTAssertEqual(
            TomatoEngine.validatedSnapshot(teapot, now: now, calendar: calendar)?.consecutiveAborts.count,
            3
        )
    }

    func testSnapshotCompletedSessionClearsLegacyAbortChainOnRestore() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let dateKey = TomatoEngine.dateKey(now: now, calendar: calendar)
        let completed = FocusSession(
            id: "focus_completed",
            createdAt: now.addingTimeInterval(-25 * 60),
            date: dateKey,
            startHour: 0, startMinute: 0, durationMin: 25,
            status: .completed, quality: 0, fakeTokens: 0,
            fakeModel: "tomato-1.0", note: nil, provider: .a
        )
        let snapshot = EngineSnapshot(
            phase: .completed, phaseEnteredAt: now,
            currentSession: completed,
            consecutiveAborts: [now.addingTimeInterval(-60)],
            currentDayKey: dateKey
        )
        let engine = TomatoEngine(clock: MockClock(start: now), calendar: calendar)
        engine.restore(from: snapshot)

        XCTAssertEqual(engine.phase, .completed)
        XCTAssertEqual(engine.consecutiveAborts, [])
    }
}
