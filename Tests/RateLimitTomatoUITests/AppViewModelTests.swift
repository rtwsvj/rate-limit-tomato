import XCTest
@testable import RateLimitTomatoUI
@testable import TomatoCore

@MainActor
final class AppViewModelTests: XCTestCase {
    private final class GlobalShortcutInstallerProbe: GlobalShortcutInstalling {
        private(set) var installCount = 0
        private(set) var installedAction: (() -> Void)?

        func installSendOrAbort(action: @escaping () -> Void) {
            installCount += 1
            installedAction = action
        }
    }

    private func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlt-ui-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    private func makeVM(directory: URL? = nil, start: Date = Date(timeIntervalSince1970: 1_751_965_200)) throws -> (AppViewModel, MockClock, URL) {
        let dir = try directory ?? makeDirectory()
        let clock = MockClock(start: start)
        let vm = AppViewModel(storeDirectory: dir, clock: clock)
        vm.stop()
        vm.acknowledgeDisclaimer()
        vm.applySettings {
            $0.soundEnabled = false
        }
        return (vm, clock, dir)
    }

    private func advance(_ vm: AppViewModel, _ clock: MockClock, by seconds: TimeInterval) {
        clock.advance(by: seconds)
        vm.tick()
    }

    private func enterFocus(_ vm: AppViewModel, _ clock: MockClock) {
        vm.sendRequest()
        advance(vm, clock, by: PhaseTiming.sending + 0.5)
        XCTAssertEqual(vm.phase, .focusing)
    }

    private func enterRateLimited(_ vm: AppViewModel, _ clock: MockClock) {
        enterFocus(vm, clock)
        advance(vm, clock, by: TimeInterval(vm.settings.focusDurationMin * 60))
        XCTAssertEqual(vm.phase, .completed)
        advance(vm, clock, by: PhaseTiming.completed + 0.5)
        XCTAssertEqual(vm.phase, .rateLimited)
    }

    private func runCompleteCycle(_ vm: AppViewModel, _ clock: MockClock) {
        enterRateLimited(vm, clock)
        advance(vm, clock, by: TimeInterval(vm.settings.cooldownDurationMin * 60))
        XCTAssertEqual(vm.phase, .reset)
        advance(vm, clock, by: PhaseTiming.reset + 0.5)
        XCTAssertEqual(vm.phase, .idle)
    }

    func testInitRestoresFromStore() throws {
        let (vm, clock, dir) = try makeVM()
        enterFocus(vm, clock)
        let expectedRemaining = vm.remaining
        let restoreStart = clock.now()
        vm.flush()

        let (restored, _, _) = try makeVM(directory: dir, start: restoreStart)
        XCTAssertEqual(restored.phase, .focusing)
        XCTAssertEqual(restored.remaining, expectedRemaining)
    }

    func testMultiTransitionCatchUpPersistsCompletedSession() throws {
        let (vm, clock, _) = try makeVM()
        enterFocus(vm, clock)
        clock.advance(by: 40 * 60)
        vm.tick()
        vm.flush()

        let sessions = try vm.store.loadSessions()
        XCTAssertEqual(sessions.filter { $0.status == .completed }.count, 1)
        XCTAssertEqual(vm.phase, .idle)
    }

    func testLiveCatchUpAfterEightDaysStillReachesIdle() throws {
        let (vm, clock, _) = try makeVM()
        enterFocus(vm, clock)

        clock.advance(by: 8 * TomatoEngine.secondsPerDay)
        vm.tick()
        vm.flush()

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertEqual(
            try vm.store.loadSessions().filter { $0.status == .completed }.count,
            1
        )
        XCTAssertEqual(
            vm.engine.quota.date,
            TomatoEngine.dateKey(now: clock.now(), calendar: vm.engine.calendar)
        )
    }

    func testColdStartAfterEightDaysRecoversFocusingSessionIntoHistory() throws {
        let dir = try makeDirectory()
        let now = Date(timeIntervalSince1970: 1_751_965_200)
        let enteredAt = now.addingTimeInterval(-8 * TomatoEngine.secondsPerDay)
        let calendar = Calendar.current
        let createdAt = enteredAt.addingTimeInterval(-PhaseTiming.sending)
        let dayKey = TomatoEngine.dateKey(now: createdAt, calendar: calendar)
        let session = FocusSession(
            id: "cold-eight-day-recovery",
            createdAt: createdAt,
            date: dayKey,
            startHour: calendar.component(.hour, from: createdAt),
            startMinute: calendar.component(.minute, from: createdAt),
            durationMin: 0,
            status: .focusing,
            quality: 0,
            fakeTokens: 0,
            fakeModel: "tomato-1.0",
            note: "recover after a long sleep",
            provider: .a
        )
        var settings = AppSettings.default
        settings.parodyDisclaimerAck = true
        let store = try TomatoStore(directory: dir)
        try store.saveSettings(settings)
        try store.saveEngineSnapshot(EngineSnapshot(
            phase: .focusing,
            phaseEnteredAt: enteredAt,
            currentSession: session,
            consecutiveAborts: [],
            currentDayKey: dayKey
        ))
        store.flush()

        let vm = AppViewModel(
            storeDirectory: dir,
            clock: MockClock(start: now),
            calendar: calendar,
            enableGlobalIntegrations: false
        )
        vm.stop()
        vm.tick()
        vm.flush()

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertEqual(try vm.store.loadSessions().map(\.id), [session.id])
        XCTAssertNil(try vm.store.loadEngineSnapshot())
    }

    func testSessionSettingsStayLockedDuringFocusWhileAppearanceCanChange() throws {
        let (vm, clock, _) = try makeVM()
        let original = vm.settings
        enterFocus(vm, clock)

        vm.applySettings {
            $0.focusDurationMin = 1
            $0.cooldownDurationMin = 1
            $0.longBreakMin = 1
            $0.maxPerDay = 1
            $0.provider = .b
            $0.language = AppLocale.en.rawValue
        }

        XCTAssertEqual(vm.settings.focusDurationMin, original.focusDurationMin)
        XCTAssertEqual(vm.settings.cooldownDurationMin, original.cooldownDurationMin)
        XCTAssertEqual(vm.settings.longBreakMin, original.longBreakMin)
        XCTAssertEqual(vm.settings.maxPerDay, original.maxPerDay)
        XCTAssertEqual(vm.settings.provider, .b)
        XCTAssertEqual(vm.settings.language, AppLocale.en.rawValue)

        advance(vm, clock, by: 60)
        XCTAssertEqual(vm.phase, .focusing, "a rejected duration edit must not end the active focus")
    }

    func testSessionSettingsCanChangeWhileIdle() throws {
        let (vm, _, _) = try makeVM()

        vm.applySettings {
            $0.focusDurationMin = 12
            $0.cooldownDurationMin = 3
            $0.longBreakMin = 7
            $0.maxPerDay = 4
        }

        XCTAssertEqual(vm.settings.focusDurationMin, 12)
        XCTAssertEqual(vm.settings.cooldownDurationMin, 3)
        XCTAssertEqual(vm.settings.longBreakMin, 7)
        XCTAssertEqual(vm.settings.maxPerDay, 4)
    }

    func testValidatedTimeScaleRejectsNonFiniteAndExtremeValues() {
        XCTAssertNil(AppViewModel.validatedTimeScale(nil))
        XCTAssertNil(AppViewModel.validatedTimeScale("nan"))
        XCTAssertNil(AppViewModel.validatedTimeScale("inf"))
        XCTAssertNil(AppViewModel.validatedTimeScale("0"))
        XCTAssertNil(AppViewModel.validatedTimeScale("-1"))
        XCTAssertNil(AppViewModel.validatedTimeScale("86401"))
        XCTAssertEqual(AppViewModel.validatedTimeScale("1"), 1)
        XCTAssertEqual(AppViewModel.validatedTimeScale("60"), 60)
    }

    func testDailyResetDuringFocusDoesNotInterrupt() throws {
        let calendar = Calendar.current
        let base = Date(timeIntervalSince1970: 1_751_965_200)
        let startOfNextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: base)))
        let start = startOfNextDay.addingTimeInterval(-10 * 60)
        let (vm, clock, _) = try makeVM(start: start)

        enterFocus(vm, clock)
        advance(vm, clock, by: 20 * 60)

        XCTAssertEqual(vm.phase, .focusing)
        XCTAssertEqual(vm.remaining, vm.maxPerDay)
        XCTAssertTrue(vm.dailyResetBannerVisible)
    }

    func testSendAfterMidnightRefreshesExhaustedQuotaWithoutWaitingForTicker() throws {
        let (vm, clock, _) = try makeVM()
        vm.applySettings { $0.maxPerDay = 1 }
        runCompleteCycle(vm, clock)
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.isQuotaExhausted)
        let previousDate = vm.engine.quota.date

        clock.advance(by: 25 * 60 * 60)
        vm.sendRequest()

        XCTAssertEqual(vm.phase, .sending)
        XCTAssertNotEqual(vm.engine.quota.date, previousDate)
        XCTAssertEqual(
            vm.engine.quota.date,
            TomatoEngine.dateKey(now: clock.now(), calendar: vm.engine.calendar)
        )
        XCTAssertEqual(vm.engine.quota.usedToday, 1)
    }

    func testURLCommandParse() {
        XCTAssertEqual(URLCommandService.parse(urlString: "rlt://send"), .send)
        XCTAssertEqual(URLCommandService.parse(urlString: "rlt://STARTSTOP"), .startStop)
        XCTAssertNil(URLCommandService.parse(urlString: "https://send"))
        XCTAssertNil(URLCommandService.parse(urlString: "rlt://bogus"))
        XCTAssertNil(URLCommandService.parse(urlString: "不是URL"))
    }

    func testDisclaimerGateBlocksStateSettingsAndTickUntilAcknowledged() throws {
        let dir = try makeDirectory()
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_751_965_200))
        let vm = AppViewModel(storeDirectory: dir, clock: clock, enableGlobalIntegrations: false)
        vm.stop()

        XCTAssertTrue(vm.showDisclaimer)
        XCTAssertTrue(vm.panelPresented)
        XCTAssertFalse(vm.settings.parodyDisclaimerAck)

        vm.pendingNote = "must not start"
        vm.sendRequest()
        vm.applySettings { $0.soundEnabled = false }
        clock.advance(by: 60 * 60)
        vm.tick()

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertEqual(vm.remaining, vm.maxPerDay)
        XCTAssertTrue(vm.settings.soundEnabled, "settings writes must also pass the disclaimer gate")

        vm.acknowledgeDisclaimer()
        XCTAssertTrue(vm.settings.parodyDisclaimerAck)
        XCTAssertFalse(vm.showDisclaimer)
        vm.sendRequest()
        XCTAssertEqual(vm.phase, .sending)
    }

    func testGlobalShortcutInstallsOnlyAfterDisclaimerAndOnlyOnce() throws {
        let dir = try makeDirectory()
        let probe = GlobalShortcutInstallerProbe()
        let vm = AppViewModel(
            storeDirectory: dir,
            clock: MockClock(start: Date(timeIntervalSince1970: 1_751_965_200)),
            urlCommands: URLCommandService(),
            globalShortcutInstaller: probe,
            enableGlobalIntegrations: true
        )
        vm.stop()

        XCTAssertEqual(probe.installCount, 0)
        XCTAssertNil(probe.installedAction)

        vm.acknowledgeDisclaimer()
        XCTAssertEqual(probe.installCount, 1)
        XCTAssertNotNil(probe.installedAction)

        vm.acknowledgeDisclaimer()
        XCTAssertEqual(probe.installCount, 1, "repeated acknowledgement must not duplicate handlers")
    }

    func testGlobalShortcutInstallsAtStartupWhenDisclaimerWasAlreadyAcknowledged() throws {
        let dir = try makeDirectory()
        let store = try TomatoStore(directory: dir)
        var settings = AppSettings.default
        settings.parodyDisclaimerAck = true
        try store.saveSettings(settings)
        store.flush()

        let probe = GlobalShortcutInstallerProbe()
        let vm = AppViewModel(
            storeDirectory: dir,
            clock: MockClock(start: Date(timeIntervalSince1970: 1_751_965_200)),
            urlCommands: URLCommandService(),
            globalShortcutInstaller: probe,
            enableGlobalIntegrations: true
        )
        vm.stop()

        XCTAssertEqual(probe.installCount, 1)
        XCTAssertNotNil(probe.installedAction)
    }

    func testDisabledGlobalIntegrationsNeverInstallShortcut() throws {
        let dir = try makeDirectory()
        let store = try TomatoStore(directory: dir)
        var settings = AppSettings.default
        settings.parodyDisclaimerAck = true
        try store.saveSettings(settings)
        store.flush()

        let probe = GlobalShortcutInstallerProbe()
        let vm = AppViewModel(
            storeDirectory: dir,
            clock: MockClock(start: Date(timeIntervalSince1970: 1_751_965_200)),
            urlCommands: URLCommandService(),
            globalShortcutInstaller: probe,
            enableGlobalIntegrations: false
        )
        vm.stop()
        vm.acknowledgeDisclaimer()

        XCTAssertEqual(probe.installCount, 0)
        XCTAssertNil(probe.installedAction)
    }

    func testDisclaimerGateFreezesExistingFocusAndAbort() throws {
        let (vm, clock, _) = try makeVM()
        enterFocus(vm, clock)
        vm.applySettings { $0.parodyDisclaimerAck = false }

        clock.advance(by: TimeInterval(vm.settings.focusDurationMin * 60))
        vm.tick()
        vm.abortRequest()

        XCTAssertEqual(vm.phase, .focusing)
        XCTAssertTrue(vm.showDisclaimer)
    }

    func testDisclaimerGateBlocksCooldownActions() throws {
        let (vm, clock, _) = try makeVM()
        enterFocus(vm, clock)
        vm.abortRequest()
        XCTAssertEqual(vm.phase, .aborted)
        vm.applySettings { $0.parodyDisclaimerAck = false }

        vm.startCooldown()
        vm.skipCooldown()

        XCTAssertEqual(vm.phase, .aborted)
        XCTAssertTrue(vm.showDisclaimer)
    }

    func testURLStateCommandsAreBlockedButReadOnlyWindowsRemainAvailable() throws {
        let dir = try makeDirectory()
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_751_965_200))
        let commands = URLCommandService()
        let vm = AppViewModel(
            storeDirectory: dir,
            clock: clock,
            urlCommands: commands,
            enableGlobalIntegrations: true
        )
        vm.stop()

        commands.handler?(.send)
        XCTAssertEqual(vm.phase, .idle)
        XCTAssertTrue(vm.showDisclaimer)

        commands.handler?(.usage)
        commands.handler?(.settings)
        XCTAssertTrue(vm.pendingUsageWindow)
        XCTAssertTrue(vm.pendingSettingsWindow)
        XCTAssertTrue(vm.panelPresented)
        XCTAssertEqual(vm.phase, .idle)
    }

    func testInvalidStoreDirectoryFallsBackToExplicitMemoryMode() {
        let invalid = URL(fileURLWithPath: "/dev/null/RateLimitTomato")
        let vm = AppViewModel(
            storeDirectory: invalid,
            clock: MockClock(start: Date(timeIntervalSince1970: 1_751_965_200)),
            enableGlobalIntegrations: false
        )
        vm.stop()

        XCTAssertFalse(vm.store.isPersistent)
        XCTAssertTrue(vm.persistenceDegraded)
    }

    func testInvalidEngineSnapshotIsRemovedDuringStartup() throws {
        let dir = try makeDirectory()
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_751_965_200))
        let store = try TomatoStore(directory: dir)
        let invalid = EngineSnapshot(
            phase: .focusing,
            phaseEnteredAt: clock.now(),
            currentSession: nil,
            consecutiveAborts: [],
            currentDayKey: TomatoEngine.dateKey(now: clock.now(), calendar: .current)
        )
        try store.saveEngineSnapshot(invalid)
        store.flush()

        let vm = AppViewModel(
            storeDirectory: dir,
            clock: clock,
            enableGlobalIntegrations: false
        )
        vm.stop()
        vm.store.flush()

        XCTAssertEqual(vm.phase, .idle)
        XCTAssertNil(try vm.store.loadEngineSnapshot())
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(TomatoStore.Filename.engine).path
        ))
    }

    func testStartupReconcilesFinalizedSnapshotMissingFromHistory() throws {
        let now = Date(timeIntervalSince1970: 1_751_965_200)
        let calendar = Calendar.current
        let day = TomatoEngine.dateKey(now: now, calendar: calendar)
        let cases: [(AppPhase, SessionStatus)] = [
            (.completed, .completed),
            (.rateLimited, .completed),
            (.rateLimited, .aborted),
            (.reset, .completed),
            (.aborted, .aborted),
        ]

        for (index, item) in cases.enumerated() {
            let dir = try makeDirectory().appendingPathComponent("case-\(index)", isDirectory: true)
            let store = try TomatoStore(directory: dir)
            var settings = AppSettings.default
            settings.parodyDisclaimerAck = true
            try store.saveSettings(settings)
            let session = FocusSession(
                id: "reconcile_\(index)",
                createdAt: now.addingTimeInterval(-30 * 60),
                date: day,
                startHour: calendar.component(.hour, from: now.addingTimeInterval(-30 * 60)),
                startMinute: calendar.component(.minute, from: now.addingTimeInterval(-30 * 60)),
                durationMin: 25,
                status: item.1,
                quality: 80,
                fakeTokens: 1_000,
                fakeModel: "tomato-1.0",
                note: "recover me",
                provider: .a
            )
            try store.saveEngineSnapshot(EngineSnapshot(
                phase: item.0,
                phaseEnteredAt: now.addingTimeInterval(-1),
                currentSession: session,
                consecutiveAborts: [],
                currentDayKey: day
            ))
            store.flush()

            let vm = AppViewModel(
                storeDirectory: dir,
                clock: MockClock(start: now),
                calendar: calendar,
                enableGlobalIntegrations: false
            )
            vm.stop()
            vm.flush()

            XCTAssertEqual(
                try vm.store.loadSessions().map(\.id),
                [session.id],
                "failed to reconcile \(item.0) / \(item.1)"
            )
        }
    }

    func testSendRequestTrimsAndClearsNote() throws {
        let (vm, _, _) = try makeVM()
        vm.pendingNote = "  ship UI tests  \n"
        vm.sendRequest()

        XCTAssertEqual(vm.pendingNote, "")
        XCTAssertEqual(vm.currentSession?.note, "ship UI tests")
    }

    func testSendRequestBoundsPersistedNoteLength() throws {
        let (vm, _, _) = try makeVM()
        vm.pendingNote = String(repeating: "🍅", count: TomatoStore.sessionNoteCharacterLimit + 100)

        vm.sendRequest()

        XCTAssertEqual(vm.currentSession?.note?.count, TomatoStore.sessionNoteCharacterLimit)
        XCTAssertLessThanOrEqual(
            vm.currentSession?.note?.utf8.count ?? 0,
            TomatoStore.sessionNoteByteLimit
        )
    }

    func testSendRequestBoundsSingleGraphemeByUTF8Bytes() throws {
        let (vm, _, _) = try makeVM()
        vm.pendingNote = "a" + String(
            repeating: "\u{0301}",
            count: TomatoStore.sessionNoteByteLimit
        )

        vm.sendRequest()

        XCTAssertLessThanOrEqual(
            vm.currentSession?.note?.utf8.count ?? 0,
            TomatoStore.sessionNoteByteLimit
        )
    }

    func testFinalizedWriteFailurePreservesSnapshotForRestartReconciliation() throws {
        enum Injected: Error { case sessions }
        let (vm, clock, dir) = try makeVM()
        enterFocus(vm, clock)
        let sessionID = try XCTUnwrap(vm.currentSession?.id)
        vm.store.flush() // establish the focusing recovery point before injecting failure
        vm.store.writeFaultInjector = { filename in
            if filename == TomatoStore.Filename.sessions { throw Injected.sessions }
        }

        advance(vm, clock, by: TimeInterval(vm.settings.focusDurationMin * 60))
        advance(vm, clock, by: PhaseTiming.completed + 0.5)
        advance(vm, clock, by: TimeInterval(vm.settings.cooldownDurationMin * 60))
        advance(vm, clock, by: PhaseTiming.reset + 0.5)
        XCTAssertEqual(vm.phase, .idle)
        vm.store.flush()

        let failedDiskState = try TomatoStore(directory: dir)
        XCTAssertEqual(try failedDiskState.loadSessions(), [])
        XCTAssertEqual(try failedDiskState.loadEngineSnapshot()?.currentSession?.id, sessionID)

        let (recovered, _, _) = try makeVM(directory: dir, start: clock.now())
        recovered.tick()
        recovered.flush()

        XCTAssertTrue(try recovered.store.loadSessions().contains { $0.id == sessionID })
        XCTAssertNil(try recovered.store.loadEngineSnapshot())
    }

    func testCompletedSessionPersistedOnce() throws {
        let (vm, clock, _) = try makeVM()
        enterFocus(vm, clock)
        clock.advance(by: TimeInterval(vm.settings.focusDurationMin * 60))
        vm.tick()
        vm.tick()
        vm.flush()

        let sessions = try vm.store.loadSessions()
        XCTAssertEqual(sessions.filter { $0.status == .completed }.count, 1)
    }

    func testSkipCooldownClearsSnapshot() throws {
        let (vm, clock, dir) = try makeVM()
        enterRateLimited(vm, clock)
        vm.skipCooldown()
        vm.store.flush()

        let snapshotURL = dir.appendingPathComponent(TomatoStore.Filename.engine)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    func testMenuBarTextPerPhase() throws {
        let (idle, _, _) = try makeVM()
        XCTAssertEqual(idle.menuBarText, "8")

        let (focusing, focusingClock, _) = try makeVM()
        enterFocus(focusing, focusingClock)
        advance(focusing, focusingClock, by: 2)
        XCTAssertEqual(focusing.menuBarText, "24:57")

        let (rateLimited, rateLimitedClock, _) = try makeVM()
        enterRateLimited(rateLimited, rateLimitedClock)
        XCTAssertEqual(rateLimited.menuBarText, "429")

        let (exhausted, exhaustedClock, _) = try makeVM()
        exhausted.applySettings { $0.maxPerDay = 1 }
        enterRateLimited(exhausted, exhaustedClock)
        exhausted.skipCooldown()
        XCTAssertEqual(exhausted.menuBarText, "503")
    }

    func testPhasePresentationUsesCatalogBackedSpecLabels() {
        let expected: [(AppPhase, Bool, String)] = [
            (.idle, false, "status.meta_ready"),
            (.idle, true, "status.meta_exhausted"),
            (.sending, false, "parody.endpoint_focus"),
            (.focusing, false, "status.meta_focusing"),
            (.completed, false, "parody.status_ok"),
            (.rateLimited, false, "status.meta_rate_limited"),
            (.aborted, false, "status.meta_aborted"),
            (.reset, false, "status.meta_reset"),
            (.teapot, false, "status.meta_teapot"),
        ]

        for locale in ["zh-CN", "en"] {
            for (phase, quotaExhausted, key) in expected {
                XCTAssertEqual(
                    PhasePresentation.forPhase(
                        phase,
                        quotaExhausted: quotaExhausted,
                        locale: locale
                    ).label,
                    L10n.t(key, locale: locale)
                )
            }
        }
    }

    func testUpgradeNudgeEveryFifthCompletion() throws {
        let (vm, clock, _) = try makeVM()

        for round in 1...5 {
            runCompleteCycle(vm, clock)
            if round == 4 {
                XCTAssertFalse(vm.pendingUpgradeNudge)
            }
        }

        XCTAssertTrue(vm.pendingUpgradeNudge)
    }

    /// 唤醒落在冷却中途：只补剩余冷却，不从唤醒时刻重走全程（墙钟为准）。
    func testWakeMidCooldownKeepsWallClockRemaining() throws {
        let (vm, clock, _) = try makeVM()
        vm.sendRequest()
        clock.advance(by: 2); vm.tick()                 // -> focusing
        clock.advance(by: 27 * 60); vm.tick()           // 睡过 专注25m + 完成2s + 冷却~118s
        XCTAssertEqual(vm.phase, .rateLimited)
        // 冷却已消耗 ~118s，剩余应 ≈182s；不允许接近 300s 的"重走全程"
        XCTAssertLessThan(vm.cooldownRemaining, 200)
        XCTAssertGreaterThan(vm.cooldownRemaining, 160)
    }

}
