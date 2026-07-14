import XCTest
@testable import TomatoCore

/// 持久化层资源、并发、恢复和事务边界测试。
final class TomatoStoreHardeningTests: XCTestCase {
    private func session(id: String, note: String? = nil) -> FocusSession {
        FocusSession(
            id: id,
            createdAt: Date(timeIntervalSince1970: 1_751_965_200),
            date: "2025-07-08",
            startHour: 9,
            startMinute: 0,
            durationMin: 25,
            status: .completed,
            quality: 0,
            fakeTokens: 500,
            fakeModel: "tomato-1.0",
            note: note,
            provider: .a
        )
    }

    func testInitRejectsPathThatIsARegularFile() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("RLTStoreFile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let file = parent.appendingPathComponent("not-a-directory")
        try Data("occupied".utf8).write(to: file)

        XCTAssertThrowsError(try TomatoStore(directory: file))
    }

    func testOversizedStartupFileIsNotReadAndGetsRecoveryCopy() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RLTStoreOversized-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let sessions = dir.appendingPathComponent(TomatoStore.Filename.sessions)
        FileManager.default.createFile(atPath: sessions.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sessions)
        try handle.truncate(atOffset: UInt64(TomatoStore.maximumPayloadBytes + 1))
        try handle.close()

        let store = try TomatoStore(directory: dir)

        XCTAssertEqual(try store.loadSessions(), [])
        XCTAssertEqual(store.startupReadFailures, [TomatoStore.Filename.sessions])
        let recovery = dir.appendingPathComponent(TomatoStore.Filename.sessions + ".corrupt.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path))
        XCTAssertEqual(
            try recovery.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            TomatoStore.maximumPayloadBytes + 1
        )
    }

    func testImportRejectsOversizedPayloadBeforeDecoding() throws {
        let store = TomatoStore.inMemory()
        let data = Data(count: TomatoStore.maximumPayloadBytes + 1)

        XCTAssertThrowsError(try store.importAll(data)) { error in
            XCTAssertEqual(
                error as? TomatoStore.ValidationError,
                .dataTooLarge(
                    actualBytes: TomatoStore.maximumPayloadBytes + 1,
                    limitBytes: TomatoStore.maximumPayloadBytes
                )
            )
        }
    }

    func testAppendSessionByteCapDropsOldestAndKeepsNewest() throws {
        let store = TomatoStore.inMemory()
        try store.saveSessions([
            session(id: "old-1", note: String(repeating: "a", count: 200)),
            session(id: "old-2", note: String(repeating: "b", count: 200)),
            session(id: "old-3", note: String(repeating: "c", count: 200)),
        ])
        let newest = session(id: "newest", note: "keep me")
        let singleSize = try TomatoStore.makeEncoder().encode([newest]).count

        try store.appendSessionKeepingNewest(
            newest,
            maximumPayloadBytes: singleSize + 16,
            maximumSessionCount: 100
        )

        let history = try store.loadSessions()
        XCTAssertEqual(history.map(\.id), ["newest"])
        XCTAssertLessThanOrEqual(
            try TomatoStore.makeEncoder().encode(history).count,
            singleSize + 16
        )
    }

    func testAppendSessionCountCapDropsOldestAndKeepsNewest() throws {
        let store = TomatoStore.inMemory()
        try store.saveSessions((0..<5).map { session(id: "old-\($0)") })

        try store.appendSessionKeepingNewest(
            session(id: "newest"),
            maximumPayloadBytes: TomatoStore.maximumPayloadBytes,
            maximumSessionCount: 3
        )

        XCTAssertEqual(try store.loadSessions().map(\.id), ["old-3", "old-4", "newest"])
    }

    func testAppendByteCapDropsOnlyNecessaryLargeOldestPrefix() throws {
        let store = TomatoStore.inMemory()
        let largeOldest = session(id: "large-oldest", note: String(repeating: "x", count: 4_000))
        let small = (0..<20).map { session(id: "small-\($0)", note: "s") }
        let newest = session(id: "newest", note: "n")
        try store.saveSessions([largeOldest] + small)
        let expected = small + [newest]
        let exactLimit = try TomatoStore.makeEncoder().encode(expected).count

        try store.appendSessionKeepingNewest(
            newest,
            maximumPayloadBytes: exactLimit,
            maximumSessionCount: 100
        )

        XCTAssertEqual(try store.loadSessions().map(\.id), expected.map(\.id))
    }

    func testSingleGraphemeCannotBypassUTF8ResourceLimit() throws {
        let combining = "a" + String(
            repeating: "\u{0301}",
            count: TomatoStore.sessionNoteByteLimit
        )
        XCTAssertEqual(combining.count, 1, "fixture must remain one extended grapheme")

        XCTAssertThrowsError(
            try TomatoStore.inMemory().saveSessions([
                session(id: "combining", note: combining)
            ])
        ) { error in
            guard let validation = error as? TomatoStore.ValidationError,
                  case let .stringTooLarge(field, actual, limit) = validation else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(field, "session.note")
            XCTAssertGreaterThan(actual, limit)
            XCTAssertEqual(limit, TomatoStore.sessionNoteByteLimit)
        }
    }

    func testSessionsWriteFailureDoesNotClearRecoverySnapshot() throws {
        enum Injected: Error { case sessions }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlt-prefix-write-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try TomatoStore(directory: dir)
        let finalized = session(id: "recover-after-write-failure")
        let snapshot = EngineSnapshot(
            phase: .completed,
            phaseEnteredAt: finalized.createdAt,
            currentSession: finalized,
            consecutiveAborts: [],
            currentDayKey: finalized.date
        )
        try store.saveEngineSnapshot(snapshot)
        store.flush()

        store.writeFaultInjector = { filename in
            if filename == TomatoStore.Filename.sessions { throw Injected.sessions }
        }
        try store.saveSessions([finalized])
        try store.clearEngineSnapshot()
        store.flush()

        XCTAssertTrue(store.hasPendingSessionWrite)
        let failedDiskState = try TomatoStore(directory: dir)
        XCTAssertEqual(try failedDiskState.loadSessions(), [])
        XCTAssertEqual(try failedDiskState.loadEngineSnapshot(), snapshot)

        store.writeFaultInjector = nil
        store.flush()
        let recoveredDiskState = try TomatoStore(directory: dir)
        XCTAssertEqual(try recoveredDiskState.loadSessions().map(\.id), [finalized.id])
        XCTAssertNil(try recoveredDiskState.loadEngineSnapshot())
    }

    func testWriteErrorHandlerCanReenterFlushWithoutDeadlock() throws {
        enum Injected: Error { case once }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlt-reentrant-handler-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try TomatoStore(directory: dir)
        var shouldFail = true
        store.writeFaultInjector = { filename in
            if filename == TomatoStore.Filename.sessions, shouldFail {
                shouldFail = false
                throw Injected.once
            }
        }
        let callback = expectation(description: "error callback reentered flush")
        store.writeErrorHandler = { [weak store] _ in
            store?.flush()
            callback.fulfill()
        }

        try store.saveSessions([session(id: "reentrant")])
        store.flush()
        wait(for: [callback], timeout: 2)

        XCTAssertFalse(store.hasPendingSessionWrite)
        XCTAssertEqual(try TomatoStore(directory: dir).loadSessions().map(\.id), ["reentrant"])
    }

    func testStartupRejectsValidJSONWithOversizedSessionField() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RLTStoreLongField-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = FocusSession(
            id: "ok",
            createdAt: Date(timeIntervalSince1970: 1),
            date: "2026-07-08",
            startHour: 0,
            startMinute: 0,
            durationMin: 1,
            status: .completed,
            quality: 0,
            fakeTokens: 0,
            fakeModel: "tomato-1.0",
            note: String(repeating: "x", count: TomatoStore.sessionNoteCharacterLimit + 1),
            provider: .a
        )
        let data = try TomatoStore.makeEncoder().encode([session])
        try data.write(to: dir.appendingPathComponent(TomatoStore.Filename.sessions))

        let store = try TomatoStore(directory: dir)

        XCTAssertEqual(try store.loadSessions(), [])
        XCTAssertEqual(store.startupReadFailures, [TomatoStore.Filename.sessions])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: dir.appendingPathComponent(TomatoStore.Filename.sessions + ".corrupt.bak").path
        ))
    }

    func testImportRejectsUnboundedAbortHistory() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = EngineSnapshot(
            phase: .idle,
            phaseEnteredAt: now,
            currentSession: nil,
            consecutiveAborts: Array(
                repeating: now,
                count: TomatoEngine.maximumAbortDatesToValidate + 1
            ),
            currentDayKey: "2023-11-14"
        )
        let bundle = TomatoStore.ExportBundle(
            version: 1,
            exportedAt: now,
            sessions: [],
            quota: nil,
            settings: nil,
            engine: snapshot
        )

        XCTAssertThrowsError(
            try TomatoStore.inMemory().importAll(TomatoStore.makeEncoder().encode(bundle), now: now)
        ) { error in
            XCTAssertEqual(
                error as? TomatoStore.ValidationError,
                .abortHistoryLimitExceeded(TomatoEngine.maximumAbortDatesToValidate + 1)
            )
        }
    }

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        let name = "TomatoStoreHardening-\(UUID().uuidString)"
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    private func makeStore() throws -> TomatoStore {
        try TomatoStore(directory: tempDir.appendingPathComponent("d-\(UUID().uuidString)"))
    }

    // MARK: - 内存态 store

    func testInMemoryStoreIsPersistentFalse() {
        let store = TomatoStore.inMemory()
        XCTAssertFalse(store.isPersistent)
        XCTAssertNil(store.directory)
    }

    func testInMemoryStoreLoadsEmptyWhenNothingSaved() {
        let store = TomatoStore.inMemory()
        XCTAssertEqual(try store.loadSessions(), [])
        XCTAssertNil(try store.loadQuota())
        XCTAssertNil(try store.loadSettings())
        XCTAssertNil(try store.loadEngineSnapshot())
    }

    func testInMemoryStoreRoundtripsAllTypes() throws {
        let store = TomatoStore.inMemory()
        let sessions = [
            FocusSession(
                id: FocusSession.makeID("imm001"),
                createdAt: Date(timeIntervalSince1970: 1_000_000),
                date: "2026-07-08",
                startHour: 9, startMinute: 30, durationMin: 25,
                status: .completed, quality: 80, fakeTokens: 12_000,
                fakeModel: "tomato-1.0", note: "in mem", provider: .a
            )
        ]
        try store.saveSessions(sessions)
        try store.saveQuota(DailyQuota(date: "2026-07-08", usedToday: 1,
                                       maxPerDay: 8, completedCount: 1, abortedCount: 0))
        try store.saveSettings(AppSettings.default)
        try store.saveEngineSnapshot(EngineSnapshot(
            phase: .focusing,
            phaseEnteredAt: Date(timeIntervalSince1970: 1_100_000),
            currentSession: nil, consecutiveAborts: [], currentDayKey: "2026-07-08"))

        XCTAssertEqual(try store.loadSessions(), sessions)
        XCTAssertEqual(try store.loadQuota()?.date, "2026-07-08")
        XCTAssertEqual(try store.loadSettings()?.focusDurationMin, 25)
        XCTAssertEqual(try store.loadEngineSnapshot()?.phase, .focusing)
    }

    func testInMemoryStoreFlushIsNoOp() throws {
        let store = TomatoStore.inMemory()
        try store.saveQuota(DailyQuota(date: "x", usedToday: 0, maxPerDay: 1,
                                       completedCount: 0, abortedCount: 0))
        // flush 在内存态上为 no-op，不会抛错、不会落盘
        store.flush()
    }

    func testInMemoryStoreExportImport() throws {
        let storeA = TomatoStore.inMemory()
        try storeA.saveSessions([
            FocusSession(
                id: FocusSession.makeID("exp1"),
                createdAt: Date(timeIntervalSince1970: 1), date: "2026-07-08",
                startHour: 9, startMinute: 0, durationMin: 25,
                status: .completed, quality: 100, fakeTokens: 0,
                fakeModel: "tomato-1.0", note: "imm export", provider: .a)
        ])
        try storeA.saveSettings(AppSettings.default)
        let data = try storeA.exportAll()
        XCTAssertFalse(data.isEmpty)

        let storeB = TomatoStore.inMemory()
        try storeB.importAll(data)
        XCTAssertEqual(try storeB.loadSessions().first?.note, "imm export")
    }

    // MARK: - 并发读写

    func testConcurrentReadWritesAreRaceFree() throws {
        let store = try makeStore()
        let iterations = 200
        let group = DispatchGroup()
        let concurrentQueue = DispatchQueue(
            label: "rlt.store.test.concurrent", attributes: .concurrent)

        // 8 个写线程抢同一个 store
        for tid in 0..<8 {
            group.enter()
            concurrentQueue.async {
                defer { group.leave() }
                for i in 0..<iterations {
                    let payload: [FocusSession] = [
                        FocusSession(
                            id: FocusSession.makeID("t\(tid)i\(i)"),
                            createdAt: Date(timeIntervalSince1970: TimeInterval(i)),
                            date: "2026-07-08",
                            startHour: tid, startMinute: i % 60, durationMin: i % 30,
                            status: .completed, quality: i % 100, fakeTokens: i,
                            fakeModel: "tomato-1.0", note: "concurrent", provider: .a)
                    ]
                    try? store.saveSessions(payload)
                }
            }
        }

        // 4 个读线程
        for _ in 0..<4 {
            group.enter()
            concurrentQueue.async {
                defer { group.leave() }
                for _ in 0..<iterations {
                    _ = try? store.loadSessions()
                    _ = try? store.loadQuota()
                    _ = try? store.loadSettings()
                }
            }
        }

        let expectation = self.expectation(description: "concurrent group")
        group.notify(queue: .main) { expectation.fulfill() }
        wait(for: [expectation], timeout: 30.0)

        // 写完之后，最终的 session 数应该是最后一次写里 8 个线程其中之一。
        let final = try store.loadSessions()
        XCTAssertEqual(final.count, 1, "每次只追加 1 条 session；并发不腐坏")
        store.flush()
        // flush 之后从磁盘读回也应只看到一条；保证写后缓存=磁盘。
        let fromDisk = try store.loadSessions()
        XCTAssertEqual(fromDisk.count, 1)
    }

    func testConcurrentQuotaAndSnapshotDoNotCorrupt() throws {
        let store = try makeStore()
        let group = DispatchGroup()
        let concurrentQueue = DispatchQueue(
            label: "rlt.store.test.conc.qs", attributes: .concurrent)

        for tid in 0..<6 {
            group.enter()
            concurrentQueue.async {
                defer { group.leave() }
                for i in 0..<50 {
                    try? store.saveQuota(DailyQuota(
                        date: "2026-07-08",
                        usedToday: tid * 50 + i,
                        maxPerDay: 100,
                        completedCount: tid,
                        abortedCount: i
                    ))
                    try? store.saveEngineSnapshot(EngineSnapshot(
                        phase: .focusing,
                        phaseEnteredAt: Date(timeIntervalSince1970: TimeInterval(tid * 1_000 + i)),
                        currentSession: nil, consecutiveAborts: [], currentDayKey: "2026-07-08"))
                }
            }
        }

        let expectation = self.expectation(description: "quota group")
        group.notify(queue: .main) { expectation.fulfill() }
        wait(for: [expectation], timeout: 30.0)

        store.flush()
        let quota = try store.loadQuota()
        let snap = try store.loadEngineSnapshot()
        XCTAssertNotNil(quota, "quota 必须存在")
        XCTAssertNotNil(snap, "snapshot 必须存在")
        XCTAssertEqual(quota?.date, "2026-07-08")
        XCTAssertEqual(snap?.currentDayKey, "2026-07-08")
    }

    func testFlushDrainsPendingWrites() throws {
        let store = try makeStore()
        for i in 0..<20 {
            try store.saveSessions([
                FocusSession(
                    id: FocusSession.makeID("flush\(i)"),
                    createdAt: Date(timeIntervalSince1970: TimeInterval(i)),
                    date: "2026-07-08",
                    startHour: i, startMinute: 0, durationMin: i,
                    status: .completed, quality: 0, fakeTokens: 0,
                    fakeModel: "tomato-1.0", note: nil, provider: .a)
            ])
        }
        store.flush()
        // 写盘后再 spawn 一个新 store 从同目录读，应能拿到最后一次的内容
        let dirURL = store.directory!
        let reloaded = try TomatoStore(directory: dirURL)
        let finalLoaded = try reloaded.loadSessions()
        XCTAssertEqual(finalLoaded.count, 1)
        XCTAssertEqual(finalLoaded.first?.id, FocusSession.makeID("flush19"))
    }

    // MARK: - importAll 校验 + 备份

    func testImportAllRejectsUnsupportedVersion() throws {
        let store = try makeStore()
        let bundle = TomatoStore.ExportBundle(
            version: 999,
            exportedAt: Date(),
            sessions: [], quota: nil, settings: nil, engine: nil
        )
        let data = try TomatoStore.makeEncoder().encode(bundle)
        XCTAssertThrowsError(try store.importAll(data)) { error in
            XCTAssertEqual(error as? TomatoStore.ValidationError,
                           .unsupportedVersion(999))
        }
    }

    func testImportAllRejectsTooManySessions() throws {
        let store = try makeStore()
        // 构造 100_001 条最小化的 session（用最少字段）
        let many: [FocusSession] = (0...TomatoStore.importSessionLimit).map { i in
            FocusSession(
                id: "overflow_\(i)",
                createdAt: Date(timeIntervalSince1970: 0),
                date: "2026-07-08",
                startHour: 0, startMinute: 0, durationMin: 0,
                status: .focusing, quality: 0, fakeTokens: 0,
                fakeModel: "x", note: nil, provider: .a
            )
        }
        let bundle = TomatoStore.ExportBundle(
            version: 1, exportedAt: Date(),
            sessions: many, quota: nil, settings: nil, engine: nil
        )
        let data = try TomatoStore.makeEncoder().encode(bundle)
        XCTAssertThrowsError(try store.importAll(data)) { error in
            XCTAssertEqual(error as? TomatoStore.ValidationError,
                           .sessionLimitExceeded(many.count))
        }
    }

    func testImportAllClampsSessionDuration() throws {
        let store = try makeStore()
        let tooLong = FocusSession(
            id: "huge",
            createdAt: Date(timeIntervalSince1970: 1),
            date: "2026-07-08",
            startHour: 0, startMinute: 0, durationMin: 99_999,
            status: .completed, quality: 0, fakeTokens: 0,
            fakeModel: "x", note: nil, provider: .a
        )
        let negative = FocusSession(
            id: "neg",
            createdAt: Date(timeIntervalSince1970: 2),
            date: "2026-07-08",
            startHour: 0, startMinute: 0, durationMin: -500,
            status: .completed, quality: 0, fakeTokens: 0,
            fakeModel: "x", note: nil, provider: .a
        )
        let bundle = TomatoStore.ExportBundle(
            version: 1, exportedAt: Date(),
            sessions: [tooLong, negative], quota: nil, settings: nil, engine: nil)
        let data = try TomatoStore.makeEncoder().encode(bundle)
        try store.importAll(data)
        let loaded = try store.loadSessions()
        XCTAssertEqual(loaded.first(where: { $0.id == "huge" })?.durationMin,
                       TomatoStore.durationRange.upperBound)
        XCTAssertEqual(loaded.first(where: { $0.id == "neg" })?.durationMin,
                       TomatoStore.durationRange.lowerBound)
    }

    func testImportAllSanitizesSettingsLanguage() throws {
        let store = try makeStore()
        var s = AppSettings.default
        s.language = "ja-JP"
        s.focusDurationMin = 9_999_999
        let bundle = TomatoStore.ExportBundle(
            version: 1, exportedAt: Date(),
            sessions: [], quota: nil, settings: s, engine: nil)
        let data = try TomatoStore.makeEncoder().encode(bundle)
        try store.importAll(data)
        let loaded = try store.loadSettings()
        XCTAssertEqual(loaded?.language, AppSettings.default.language, "非法语言回落 zh-CN")
        XCTAssertEqual(loaded?.focusDurationMin, AppSettings.focusRange.upperBound)
    }

    func testImportAllBacksUpExistingFiles() throws {
        // 先在磁盘上写有效的旧版本（sessions.json + quota.json + settings.json + engine.json），
        // 再 importAll，确保每份都被备份成 .bak。
        let dir = tempDir.appendingPathComponent("bak-\(UUID().uuidString)")
        let store = try TomatoStore(directory: dir)
        let originalSessions = [
            FocusSession(id: FocusSession.makeID("orig"),
                         createdAt: Date(timeIntervalSince1970: 1),
                         date: "2026-07-08",
                         startHour: 9, startMinute: 0, durationMin: 25,
                         status: .completed, quality: 50, fakeTokens: 0,
                         fakeModel: "tomato-1.0", note: "original", provider: .a)
        ]
        try store.saveSessions(originalSessions)
        try store.saveQuota(DailyQuota(date: "2026-07-08", usedToday: 1, maxPerDay: 8,
                                       completedCount: 1, abortedCount: 0))
        try store.saveSettings(AppSettings.default)
        try store.saveEngineSnapshot(EngineSnapshot(phase: .idle,
                                                    phaseEnteredAt: Date(timeIntervalSince1970: 1),
                                                    currentSession: nil,
                                                    consecutiveAborts: [],
                                                    currentDayKey: "2026-07-08"))
        store.flush()

        // 现在 import 一份新的，版本要等于 1
        let newBundle = TomatoStore.ExportBundle(
            version: 1, exportedAt: Date(),
            sessions: [
                FocusSession(
                    id: FocusSession.makeID("new"),
                    createdAt: Date(timeIntervalSince1970: 2),
                    date: "2026-07-08",
                    startHour: 10, startMinute: 0, durationMin: 25,
                    status: .completed, quality: 100, fakeTokens: 0,
                    fakeModel: "tomato-1.0", note: "imported", provider: .a)
            ],
            quota: nil, settings: nil, engine: nil)
        let data = try TomatoStore.makeEncoder().encode(newBundle)
        try store.importAll(data)
        store.flush()

        // 验证新内容
        XCTAssertEqual(try store.loadSessions().first?.id,
                       FocusSession.makeID("new"),
                       "import 后 sessions 应是新值")

        // 验证备份存在并保留原内容
        let fm = FileManager.default
        for filename in [TomatoStore.Filename.sessions,
                         TomatoStore.Filename.quota,
                         TomatoStore.Filename.settings,
                         TomatoStore.Filename.engine] {
            let backupURL = dir.appendingPathComponent(filename + ".bak")
            XCTAssertTrue(fm.fileExists(atPath: backupURL.path),
                          "backup missing for \(filename)")
        }
        // 备份里 sessions.json.bak 应该有原始那条 session
        let backupData = try Data(contentsOf: dir.appendingPathComponent("sessions.json.bak"))
        let backupSessions = try TomatoStore.makeDecoder().decode([FocusSession].self, from: backupData)
        XCTAssertEqual(backupSessions.first?.id, FocusSession.makeID("orig"),
                       "备份保留导入前的原始数据")
    }

    func testImportAllBackupUsesExistingDirectoryEvenWhenOnlyQuotaExists() throws {
        // 只有 quota.json 存在；其他不存在时 backupExistingFiles 不应报错也不应创建空 .bak
        let dir = tempDir.appendingPathComponent("partial-\(UUID().uuidString)")
        let store = try TomatoStore(directory: dir)
        try store.saveQuota(DailyQuota(date: "2026-07-08", usedToday: 1, maxPerDay: 8,
                                       completedCount: 1, abortedCount: 0))
        store.flush()

        let bundle = TomatoStore.ExportBundle(
            version: 1, exportedAt: Date(),
            sessions: [], quota: nil, settings: nil, engine: nil)
        let data = try TomatoStore.makeEncoder().encode(bundle)
        try store.importAll(data)

        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(
            atPath: dir.appendingPathComponent("quota.json.bak").path))
        // 不存在的 .bak 不应被凭空创建
        XCTAssertFalse(fm.fileExists(
            atPath: dir.appendingPathComponent("sessions.json.bak").path))
    }

    // MARK: - isPersistent + writeErrorHandler

    func testPersistentStoreReportsTrue() throws {
        let store = try makeStore()
        XCTAssertTrue(store.isPersistent)
        XCTAssertNotNil(store.directory)
    }

    func testInMemoryStoreNeverInvokesWriteErrorHandler() throws {
        let store = TomatoStore.inMemory()
        var fired = false
        store.writeErrorHandler = { _ in fired = true }
        try store.saveSessions([
            FocusSession(id: FocusSession.makeID("e"),
                         createdAt: Date(timeIntervalSince1970: 1),
                         date: "2026-07-08",
                         startHour: 9, startMinute: 0, durationMin: 25,
                         status: .completed, quality: 0, fakeTokens: 0,
                         fakeModel: "x", note: nil, provider: .a)
        ])
        store.flush()
        XCTAssertFalse(fired, "内存态永不写盘，handler 不应触发")
    }
}

extension TomatoStoreHardeningTests {
    /// 导入不含 quota/settings 的包后，重启（新 store 实例）不得复活旧数据。
    func testImportWithNilFieldsDoesNotResurrectOldDataAfterRestart() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlt-import-\(UUID().uuidString)", isDirectory: true)
        let store = try TomatoStore(directory: dir)
        try store.saveQuota(DailyQuota(date: "2026-07-08", usedToday: 8, maxPerDay: 8,
                                       completedCount: 8, abortedCount: 0))
        try store.saveSettings(.default)
        store.flush()

        let bundle = TomatoStore.ExportBundle(
            version: 1, exportedAt: Date(), sessions: [], quota: nil, settings: nil, engine: nil
        )
        try store.importAll(TomatoStore.makeEncoder().encode(bundle))
        store.flush()

        let reopened = try TomatoStore(directory: dir)
        XCTAssertNil(try reopened.loadQuota(), "导入 nil quota 后重启不得读到旧 quota")
        XCTAssertNil(try reopened.loadSettings(), "导入 nil settings 后重启不得读到旧 settings")
    }

    func testImportBackupFailureLeavesCacheAndDiskUnchanged() throws {
        enum Injected: Error { case backup }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlt-import-backup-fail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try TomatoStore(directory: dir)
        let original = FocusSession(
            id: "original", createdAt: Date(timeIntervalSince1970: 1), date: "2026-07-08",
            startHour: 9, startMinute: 0, durationMin: 25,
            status: .completed, quality: 0, fakeTokens: 0,
            fakeModel: "tomato-1.0", note: nil, provider: .a
        )
        try store.saveSessions([original])
        store.flush()
        store.importFaultInjector = { point in
            if case .backup = point { throw Injected.backup }
        }
        let replacement = FocusSession(
            id: "replacement", createdAt: Date(timeIntervalSince1970: 2), date: "2026-07-08",
            startHour: 10, startMinute: 0, durationMin: 25,
            status: .completed, quality: 0, fakeTokens: 0,
            fakeModel: "tomato-1.0", note: nil, provider: .a
        )
        let bundle = TomatoStore.ExportBundle(
            version: 1, exportedAt: Date(), sessions: [replacement],
            quota: nil, settings: nil, engine: nil
        )

        XCTAssertThrowsError(try store.importAll(TomatoStore.makeEncoder().encode(bundle))) { error in
            guard case TomatoStore.ImportError.backupFailed = error else {
                return XCTFail("expected backupFailed, got \(error)")
            }
        }
        XCTAssertEqual(try store.loadSessions().map(\.id), ["original"])
        let reopened = try TomatoStore(directory: dir)
        XCTAssertEqual(try reopened.loadSessions().map(\.id), ["original"])
    }

    func testImportCommitFailureLeavesCacheAndDiskUnchanged() throws {
        enum Injected: Error { case commit }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("rlt-import-commit-fail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try TomatoStore(directory: dir)
        let original = FocusSession(
            id: "original", createdAt: Date(timeIntervalSince1970: 1), date: "2026-07-08",
            startHour: 9, startMinute: 0, durationMin: 25,
            status: .completed, quality: 0, fakeTokens: 0,
            fakeModel: "tomato-1.0", note: nil, provider: .a
        )
        try store.saveSessions([original])
        store.flush()
        store.importFaultInjector = { point in
            if case .commit = point { throw Injected.commit }
        }
        let replacement = FocusSession(
            id: "replacement", createdAt: Date(timeIntervalSince1970: 2), date: "2026-07-08",
            startHour: 10, startMinute: 0, durationMin: 25,
            status: .completed, quality: 0, fakeTokens: 0,
            fakeModel: "tomato-1.0", note: nil, provider: .a
        )
        let bundle = TomatoStore.ExportBundle(
            version: 1, exportedAt: Date(), sessions: [replacement],
            quota: nil, settings: nil, engine: nil
        )

        XCTAssertThrowsError(try store.importAll(TomatoStore.makeEncoder().encode(bundle))) { error in
            guard case TomatoStore.ImportError.commitFailed = error else {
                return XCTFail("expected commitFailed, got \(error)")
            }
        }
        XCTAssertEqual(try store.loadSessions().map(\.id), ["original"])
        let reopened = try TomatoStore(directory: dir)
        XCTAssertEqual(try reopened.loadSessions().map(\.id), ["original"])
    }

    func testImportSanitizesQuotaAndDropsInvalidRuntimeSnapshot() throws {
        var settings = AppSettings.default
        settings.maxPerDay = 4
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let invalidSnapshot = EngineSnapshot(
            phase: .focusing,
            phaseEnteredAt: now,
            currentSession: nil,
            consecutiveAborts: [.distantFuture],
            currentDayKey: "2026-07-08"
        )
        let bundle = TomatoStore.ExportBundle(
            version: 1,
            exportedAt: now,
            sessions: [],
            quota: DailyQuota(
                date: "2026-07-08",
                usedToday: Int.max,
                maxPerDay: Int.max,
                completedCount: Int.max,
                abortedCount: Int.max
            ),
            settings: settings,
            engine: invalidSnapshot
        )
        let store = try makeStore()
        try store.importAll(TomatoStore.makeEncoder().encode(bundle), now: now)

        XCTAssertEqual(try store.loadQuota()?.maxPerDay, 4)
        XCTAssertEqual(try store.loadQuota()?.usedToday, DailyQuota.maximumTrackedCount)
        XCTAssertEqual(try store.loadQuota()?.completedCount, DailyQuota.maximumTrackedCount)
        XCTAssertEqual(try store.loadQuota()?.abortedCount, 0)
        XCTAssertNil(try store.loadEngineSnapshot())
    }
}
