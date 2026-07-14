import XCTest
@testable import TomatoCore

/// 闪退专项（v3.1）：核心层在任意输入/任意事件序列下不崩、不变量恒成立。
final class CrashHardeningTests: XCTestCase {
    // MARK: 引擎事件模糊测试

    /// 5000 步随机事件 + 随机时间推进：任何序列都不崩，额度/阶段不变量恒成立。
    func testEngineEventFuzz() {
        var rng = SplitMix64(state: 20260709)
        for round in 0..<10 {
            let clock = MockClock(start: Date(timeIntervalSince1970: 1_700_000_000))
            let engine = TomatoEngine(clock: clock, settings: .default)
            for step in 0..<500 {
                switch rng.next() % 8 {
                case 0: engine.sendRequest(note: step % 3 == 0 ? "模糊测试 🍅\u{202E}!" : nil)
                case 1: engine.abortRequest()
                case 2: engine.skipCooldown()
                case 3: engine.startCooldown()
                case 4: engine.acknowledgeTeapot()
                case 5: clock.advance(by: TimeInterval(rng.next() % 4000))
                case 6: clock.advance(by: 0.5)
                default: break
                }
                engine.tick(now: clock.now())

                XCTAssertGreaterThanOrEqual(engine.quota.usedToday, 0, "r\(round)s\(step)")
                XCTAssertGreaterThanOrEqual(engine.remaining, 0, "r\(round)s\(step)")
                XCTAssertLessThanOrEqual(engine.quota.usedToday,
                                         engine.settings.maxPerDay + 1, "r\(round)s\(step)")
                if engine.phase == .focusing || engine.phase == .sending {
                    XCTAssertNotNil(engine.currentSession, "进行中必须有会话 r\(round)s\(step)")
                }
            }
        }
    }

    /// 时钟倒退（NTP 校时）：不崩，派生量不为负/NaN。
    func testClockGoingBackwards() {
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let engine = TomatoEngine(clock: clock, settings: .default)
        engine.sendRequest()
        clock.advance(by: 2)
        engine.tick(now: clock.now())
        clock.advance(by: -3600) // 倒退一小时
        engine.tick(now: clock.now())
        XCTAssertGreaterThanOrEqual(engine.focusElapsed, 0)
        XCTAssertGreaterThanOrEqual(engine.focusRemaining, 0)
        XCTAssertLessThanOrEqual(
            engine.focusRemaining,
            TimeInterval(engine.settings.focusDurationMin * 60)
        )
        let display = TimeMapper.focusWindowDisplay(elapsed: engine.focusElapsed, total: 25 * 60)
        XCTAssertFalse(display.contains("-"), "倒退时钟不许出现负数显示")
    }

    func testClockGoingBackAcrossMidnightDoesNotResetQuota() {
        let calendar = Calendar.current
        let start = Date(timeIntervalSince1970: 1_751_965_200)
        let clock = MockClock(start: start)
        let engine = TomatoEngine(clock: clock, calendar: calendar, settings: .default)
        XCTAssertTrue(engine.sendRequest())
        let originalDay = engine.quota.date
        let originalUsed = engine.quota.usedToday

        clock.advance(by: -TomatoEngine.secondsPerDay)
        engine.tick(now: clock.now())

        XCTAssertEqual(engine.quota.date, originalDay)
        XCTAssertEqual(engine.quota.usedToday, originalUsed)
        XCTAssertFalse(engine.didDailyReset)
    }

    func testNonFiniteClockAbortDoesNotTrapOrOverflowDuration() {
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_751_965_200))
        let engine = TomatoEngine(clock: clock, settings: .default)
        XCTAssertTrue(engine.sendRequest())
        clock.advance(by: PhaseTiming.sending)
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.phase, .focusing)

        clock.set(now: Date(timeIntervalSince1970: .infinity))
        engine.abortRequest()

        XCTAssertEqual(engine.phase, .aborted)
        XCTAssertEqual(engine.currentSession?.durationMin, TomatoStore.durationRange.upperBound)
    }

    /// 极端设置：0/负数/巨值时长——不崩、不除零。
    func testExtremeSettings() {
        for (focus, cooldown, maxPerDay) in [(0, 0, 0), (-5, -5, -1), (100_000, 100_000, 10_000)] {
            var s = AppSettings.default
            s.focusDurationMin = focus
            s.cooldownDurationMin = cooldown
            s.maxPerDay = maxPerDay
            let clock = MockClock()
            let engine = TomatoEngine(clock: clock, settings: s)
            engine.sendRequest()
            for _ in 0..<10 {
                clock.advance(by: 100)
                engine.tick(now: clock.now())
            }
            _ = TimeMapper.progressFraction(elapsed: engine.focusElapsed,
                                            total: TimeInterval(focus * 60))
            XCTAssertGreaterThanOrEqual(engine.remaining, 0)
        }
    }

    // MARK: 存储损坏

    /// 四类损坏文件：乱码 / 类型错位 / 空文件 / 巨型垃圾——load 全部安全返回 nil/空。
    func testCorruptStoreFilesDoNotCrash() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlt-crash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let corruptions: [String: String] = [
            TomatoStore.Filename.sessions: "{not json at all🍅",
            TomatoStore.Filename.quota: "[1,2,3]",
            TomatoStore.Filename.settings: "",
            TomatoStore.Filename.engine: String(repeating: "A", count: 1_000_000),
        ]
        for (file, garbage) in corruptions {
            try garbage.data(using: .utf8)!.write(to: dir.appendingPathComponent(file))
        }
        // 必须在损坏文件写完后重新构建 store，才真正覆盖启动读盘路径。
        let store = try TomatoStore(directory: dir)
        XCTAssertNoThrow({
            _ = try? store.loadSessions()
            _ = try? store.loadQuota()
            _ = try? store.loadSettings()
            _ = try? store.loadEngineSnapshot()
        }())
        XCTAssertEqual(Set(store.startupReadFailures), Set(corruptions.keys))
        for file in corruptions.keys {
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: dir.appendingPathComponent(file + ".corrupt.bak").path
            ))
        }
        // importAll 对垃圾数据必须抛错而不是崩
        XCTAssertThrowsError(try store.importAll("garbage".data(using: .utf8)!))
    }

    /// 语义损坏的快照（未来时刻/远古时刻/负时长会话）：恢复后 tick 不崩、自然推进。
    func testSemanticGarbageSnapshotRestore() {
        let clock = MockClock(start: Date(timeIntervalSince1970: 1_700_000_000))
        let engine = TomatoEngine(clock: clock, settings: .default)
        let garbageSession = FocusSession(
            id: "focus_deadbeef", createdAt: Date.distantFuture, date: "9999-99-99",
            startHour: 99, startMinute: -1, durationMin: -100, status: .focusing,
            quality: -1, fakeTokens: Int.min, fakeModel: "", note: String(repeating: "🫖", count: 10_000),
            provider: .a
        )
        for enteredAt in [Date.distantFuture, Date.distantPast, clock.now()] {
            engine.restore(from: EngineSnapshot(
                phase: .focusing, phaseEnteredAt: enteredAt,
                currentSession: garbageSession, consecutiveAborts: [Date.distantPast],
                currentDayKey: "not-a-date"
            ))
            for _ in 0..<5 {
                clock.advance(by: 600)
                engine.tick(now: clock.now())
            }
            XCTAssertGreaterThanOrEqual(engine.focusElapsed, 0)
        }
    }

    // MARK: 纯函数边界

    func testPureFunctionEdgeInputs() {
        // TimeMapper：NaN/无穷/负值全部钳制
        for bad in [Double.nan, .infinity, -.infinity, -1, 0] {
            let f = TimeMapper.progressFraction(elapsed: bad, total: 25 * 60)
            XCTAssertTrue(f >= 0 && f <= 1, "fraction 越界: \(bad) -> \(f)")
            _ = TimeMapper.focusWindowDisplay(elapsed: bad, total: 25 * 60)
            _ = TimeMapper.progressFraction(elapsed: 100, total: bad)
        }
        // TokenMeter / 假数据生成器：负值与巨值
        let meter = TokenMeter(seed: 1)
        XCTAssertEqual(meter.tokens(forElapsedSeconds: -100), 0)
        _ = meter.tokens(forElapsedSeconds: 100_000)
        _ = FakeLogStreamGenerator(seed: 0).lines(elapsed: -5)
        _ = FakeLogStreamGenerator(seed: 0).lines(elapsed: 1e6)
        _ = FakeJsonGenerator.aborted(id: "", durationMs: -1)
        XCTAssertFalse(TokenMeter.insertThousandsSeparator(Int.min).isEmpty)
        XCTAssertFalse(FakeHeaderGenerator.rateLimited(
            limit: Int.max,
            remaining: Int.min,
            resetAt: Date(timeIntervalSince1970: .infinity),
            retryAfter: .infinity
        ).isEmpty)
        XCTAssertFalse(FakeJsonGenerator.completed(
            id: "extreme",
            createdAt: Date(timeIntervalSince1970: .infinity),
            durationMs: Int.max,
            tokensUsed: Int.max
        ).isEmpty)
        XCTAssertEqual(
            FakeLogStreamGenerator(seed: 1, baseTokensPerMinute: .infinity)
                .lines(elapsed: .infinity),
            []
        )
        // L10n：缺失 key/占位符/怪 locale
        _ = L10n.t("no.such.key", locale: "xx-YY")
        _ = L10n.t("quota.remaining", locale: "zh-CN", args: [:])
        _ = L10n.bilingual("status.usage_limit_reached", primaryLocale: "", args: ["time": ""])
        // 聚合器：空数据 / 单条怪数据
        _ = HeatmapAggregator.yearGrid(sessions: [], endingAt: .distantPast, calendar: .current)
        _ = HeatmapAggregator.uptimeDays(sessions: [], endingAt: .distantFuture, calendar: .current)
        _ = HeatmapAggregator.dayDistribution(sessions: [], date: "")
        XCTAssertNil(HeatmapAggregator.peakHour(distribution: []))
    }
}

extension CrashHardeningTests {
    /// 非有限输入不得触发 Int 转换陷阱。
    func testTokenMeterNonFiniteInputsDoNotTrap() {
        let meter = TokenMeter(seed: 7)
        _ = meter.tokens(forElapsedSeconds: 60)
        XCTAssertGreaterThanOrEqual(meter.tokens(forElapsedSeconds: .nan), 0)
        XCTAssertGreaterThanOrEqual(meter.tokens(forElapsedSeconds: .infinity), 0)
        XCTAssertGreaterThanOrEqual(meter.tokens(forElapsedSeconds: -.infinity), 0)
        XCTAssertGreaterThanOrEqual(
            TokenMeter(seed: 1, baseTokensPerMinute: 1_000_000)
                .tokens(forElapsedSeconds: Double.greatestFiniteMagnitude),
            0
        )
        XCTAssertGreaterThan(TokenMeter.safeInt(Double.greatestFiniteMagnitude), 0)
        XCTAssertEqual(TokenMeter.safeInt(-Double.greatestFiniteMagnitude), 0)
    }
}
