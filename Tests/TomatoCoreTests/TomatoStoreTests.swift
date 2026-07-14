import XCTest
@testable import TomatoCore

final class TomatoStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        let name = "TomatoStoreTests-\(UUID().uuidString)"
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    private func makeStore() throws -> TomatoStore {
        try TomatoStore(directory: tempDir)
    }

    // MARK: - Init

    func testInitCreatesDirectory() throws {
        let dir = tempDir.appendingPathComponent("nested/sub")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        _ = try TomatoStore(directory: dir)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
    }

    func testInitAcceptsExistingDirectory() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        _ = try TomatoStore(directory: tempDir)
    }

    // MARK: - Sessions roundtrip

    func testSessionsRoundtrip() throws {
        let store = try makeStore()
        let sessions = [
            FocusSession(
                id: FocusSession.makeID("aaa111"),
                createdAt: Date(timeIntervalSince1970: 1_000_000),
                date: "2026-07-08",
                startHour: 9,
                startMinute: 30,
                durationMin: 25,
                status: .completed,
                quality: 80,
                fakeTokens: 12_000,
                fakeModel: "tomato-1.0",
                note: "spec review",
                provider: .a
            ),
            FocusSession(
                id: FocusSession.makeID("bbb222"),
                createdAt: Date(timeIntervalSince1970: 1_100_000),
                date: "2026-07-08",
                startHour: 11,
                startMinute: 0,
                durationMin: 5,
                status: .aborted,
                quality: 0,
                fakeTokens: 0,
                fakeModel: "tomato-1.0",
                note: nil,
                provider: .b
            )
        ]
        try store.saveSessions(sessions)
        let loaded = try store.loadSessions()
        XCTAssertEqual(loaded, sessions)
    }

    func testLoadSessionsEmpty() throws {
        let store = try makeStore()
        let loaded = try store.loadSessions()
        XCTAssertEqual(loaded, [])
    }

    // MARK: - Quota roundtrip

    func testQuotaRoundtrip() throws {
        let store = try makeStore()
        let quota = DailyQuota(
            date: "2026-07-08",
            usedToday: 3,
            maxPerDay: 8,
            completedCount: 2,
            abortedCount: 1
        )
        try store.saveQuota(quota)
        let loaded = try store.loadQuota()
        XCTAssertEqual(loaded, quota)
    }

    func testLoadQuotaMissing() throws {
        let store = try makeStore()
        XCTAssertNil(try store.loadQuota())
    }

    // MARK: - Settings roundtrip

    func testSettingsRoundtrip() throws {
        let store = try makeStore()
        let s = AppSettings.default
        try store.saveSettings(s)
        let loaded = try store.loadSettings()
        XCTAssertEqual(loaded, s)
    }

    func testLoadSettingsMissing() throws {
        let store = try makeStore()
        XCTAssertNil(try store.loadSettings())
    }

    // MARK: - Engine snapshot roundtrip

    func testEngineSnapshotRoundtrip() throws {
        let store = try makeStore()
        let snap = EngineSnapshot(
            phase: .focusing,
            phaseEnteredAt: Date(timeIntervalSince1970: 1_500_000),
            currentSession: FocusSession(
                id: FocusSession.makeID("snap01"),
                createdAt: Date(timeIntervalSince1970: 1_499_900),
                date: "2026-07-08",
                startHour: 14,
                startMinute: 0,
                durationMin: 0,
                status: .focusing,
                quality: 0,
                fakeTokens: 0,
                fakeModel: "tomato-1.0",
                note: nil,
                provider: .a
            ),
            consecutiveAborts: [
                Date(timeIntervalSince1970: 1_400_000),
                Date(timeIntervalSince1970: 1_450_000)
            ],
            currentDayKey: "2026-07-08"
        )
        try store.saveEngineSnapshot(snap)
        let loaded = try store.loadEngineSnapshot()
        XCTAssertEqual(loaded, snap)
    }

    func testClearEngineSnapshot() throws {
        let store = try makeStore()
        let snap = EngineSnapshot(
            phase: .idle,
            phaseEnteredAt: Date(timeIntervalSince1970: 0),
            currentSession: nil,
            consecutiveAborts: [],
            currentDayKey: "2026-07-08"
        )
        try store.saveEngineSnapshot(snap)
        XCTAssertNotNil(try store.loadEngineSnapshot())
        try store.clearEngineSnapshot()
        XCTAssertNil(try store.loadEngineSnapshot())
    }

    // MARK: - Export / Import

    func testExportImportRoundtrip() throws {
        let store = try makeStore()
        let sessions = [
            FocusSession(
                id: FocusSession.makeID("exp001"),
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                date: "2026-07-08",
                startHour: 9,
                startMinute: 0,
                durationMin: 25,
                status: .completed,
                quality: 90,
                fakeTokens: 10_000,
                fakeModel: "tomato-1.0",
                note: "demo",
                provider: .a
            )
        ]
        let quota = DailyQuota(
            date: "2026-07-08",
            usedToday: 1,
            maxPerDay: 8,
            completedCount: 1,
            abortedCount: 0
        )
        let settings = AppSettings.default
        let snap = EngineSnapshot(
            phase: .idle,
            phaseEnteredAt: Date(timeIntervalSince1970: 1_700_000_000),
            currentSession: nil,
            consecutiveAborts: [],
            currentDayKey: "2026-07-08"
        )
        try store.saveSessions(sessions)
        try store.saveQuota(quota)
        try store.saveSettings(settings)
        try store.saveEngineSnapshot(snap)

        let data = try store.exportAll()
        XCTAssertFalse(data.isEmpty)

        // 新 store
        let newDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TomatoStoreTests-import-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: newDir) }
        let newStore = try TomatoStore(directory: newDir)
        try newStore.importAll(data)

        XCTAssertEqual(try newStore.loadSessions(), sessions)
        XCTAssertEqual(try newStore.loadQuota(), quota)
        XCTAssertEqual(try newStore.loadSettings(), settings)
        XCTAssertEqual(try newStore.loadEngineSnapshot(), snap)
    }

    func testImportWithMissingEngineClearsIt() throws {
        let store = try makeStore()
        let snap = EngineSnapshot(
            phase: .focusing,
            phaseEnteredAt: Date(timeIntervalSince1970: 1),
            currentSession: nil,
            consecutiveAborts: [],
            currentDayKey: "2026-07-08"
        )
        try store.saveEngineSnapshot(snap)
        XCTAssertNotNil(try store.loadEngineSnapshot())

        // 构造一个无 engine 字段的导出包
        let bundle = TomatoStore.ExportBundle(
            version: 1,
            exportedAt: Date(),
            sessions: [],
            quota: nil,
            settings: nil,
            engine: nil
        )
        let data = try TomatoStore.makeEncoder().encode(bundle)
        try store.importAll(data)
        XCTAssertNil(try store.loadEngineSnapshot())
    }

    // MARK: - Atomic write

    func testAtomicWriteOverwrite() throws {
        let store = try makeStore()
        let first = DailyQuota(
            date: "2026-07-08",
            usedToday: 1,
            maxPerDay: 8,
            completedCount: 1,
            abortedCount: 0
        )
        let second = DailyQuota(
            date: "2026-07-08",
            usedToday: 2,
            maxPerDay: 8,
            completedCount: 1,
            abortedCount: 1
        )
        try store.saveQuota(first)
        try store.saveQuota(second)
        let loaded = try store.loadQuota()
        XCTAssertEqual(loaded, second)
    }

    func testNoTempFileLeftAfterWrite() throws {
        let store = try makeStore()
        try store.saveQuota(DailyQuota(
            date: "2026-07-08",
            usedToday: 0,
            maxPerDay: 8,
            completedCount: 0,
            abortedCount: 0
        ))
        store.flush()
        let entries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertFalse(entries.contains { $0.hasPrefix(".") && $0.hasSuffix(".tmp") })
    }

    // MARK: - Engine + Store integration: restart recovery

    func testEngineRestoredMidFocusing() throws {
        let store = try makeStore()
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MockClock(start: start)
        let engine = TomatoEngine(clock: clock, calendar: calendar)
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        // FOCUSING 中，已走 5 分钟
        clock.advance(by: 5 * 60)
        try store.saveEngineSnapshot(engine.snapshot())
        try store.saveQuota(engine.quota)
        try store.saveSettings(engine.settings)

        // 重启模拟：新建 engine，从 store 恢复
        let clock2 = MockClock(start: clock.now())
        let loadedQuota = try store.loadQuota()!
        let loadedSettings = try store.loadSettings()!
        let engine2 = TomatoEngine(
            clock: clock2,
            calendar: calendar,
            settings: loadedSettings,
            quota: loadedQuota
        )
        engine2.restore(from: try store.loadEngineSnapshot()!)
        XCTAssertEqual(engine2.phase, .focusing)
        XCTAssertNotNil(engine2.currentSession)
        XCTAssertEqual(engine2.currentSession?.status, .focusing)

        // 继续推进 20 分钟 (总 25)，应到 COMPLETED
        clock2.advance(by: 20 * 60)
        engine2.tick()
        XCTAssertEqual(engine2.phase, .completed)
        XCTAssertEqual(engine2.currentSession?.status, .completed)
        XCTAssertEqual(engine2.currentSession?.durationMin, 25)
    }

    func testEngineRestoredMidRateLimited() throws {
        let store = try makeStore()
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MockClock(start: start)
        let engine = TomatoEngine(clock: clock, calendar: calendar)
        // 走到 RATE_LIMITED
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: TimeInterval(25 * 60))
        engine.tick()
        clock.advance(by: 2.1)
        engine.tick()
        XCTAssertEqual(engine.phase, .rateLimited)
        clock.advance(by: 2 * 60)  // 冷却中 2 分钟
        try store.saveEngineSnapshot(engine.snapshot())
        try store.saveQuota(engine.quota)
        try store.saveSettings(engine.settings)

        // 重启
        let clock2 = MockClock(start: clock.now())
        let engine2 = TomatoEngine(
            clock: clock2,
            calendar: calendar,
            settings: try store.loadSettings()!,
            quota: try store.loadQuota()!
        )
        engine2.restore(from: try store.loadEngineSnapshot()!)
        XCTAssertEqual(engine2.phase, .rateLimited)
        clock2.advance(by: 3 * 60)  // 再走 3 分钟 = 总 5 分钟 -> RESET
        engine2.tick()
        XCTAssertEqual(engine2.phase, .reset)
    }

    func testEngineRestoredExpiredFocusingCompletes() throws {
        let store = try makeStore()
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MockClock(start: start)
        let engine = TomatoEngine(clock: clock, calendar: calendar)
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        // 走 5 分钟
        clock.advance(by: 5 * 60)
        try store.saveEngineSnapshot(engine.snapshot())
        try store.saveQuota(engine.quota)
        try store.saveSettings(engine.settings)

        // 重启后"过了 1 小时"（远超 focus 时长）
        let clock2 = MockClock(start: clock.now().addingTimeInterval(3600))
        let engine2 = TomatoEngine(
            clock: clock2,
            calendar: calendar,
            settings: try store.loadSettings()!,
            quota: try store.loadQuota()!
        )
        engine2.restore(from: try store.loadEngineSnapshot()!)
        XCTAssertEqual(engine2.phase, .focusing)
        engine2.tick()
        XCTAssertEqual(engine2.phase, .completed, "已超时则自然推进")
    }

    func testEngineRestoredAbortedStaysAborted() throws {
        let store = try makeStore()
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_000_000)
        let clock = MockClock(start: start)
        let engine = TomatoEngine(clock: clock, calendar: calendar)
        engine.sendRequest()
        clock.advance(by: 1.6)
        engine.tick()
        clock.advance(by: 3 * 60)
        engine.abortRequest()
        XCTAssertEqual(engine.phase, .aborted)
        try store.saveEngineSnapshot(engine.snapshot())
        try store.saveQuota(engine.quota)
        try store.saveSettings(engine.settings)

        let clock2 = MockClock(start: clock.now().addingTimeInterval(600))
        let engine2 = TomatoEngine(
            clock: clock2,
            calendar: calendar,
            settings: try store.loadSettings()!,
            quota: try store.loadQuota()!
        )
        engine2.restore(from: try store.loadEngineSnapshot()!)
        XCTAssertEqual(engine2.phase, .aborted)
        // ABORTED 不会自动推进
        engine2.tick()
        XCTAssertEqual(engine2.phase, .aborted)
    }
}
