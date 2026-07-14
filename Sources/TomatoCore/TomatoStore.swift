import Foundation

/// JSON 文件持久化（docs/CHANGES.md C2）。
/// - 四个独立文件：sessions.json / quota.json / settings.json / engine.json；
/// - 原子写：写到临时文件再 rename，避免崩溃时文件半截（详见 `atomicWrite`）。
///
/// ## 缓存 + 后台队列
/// - 启动时一次读盘填充内存缓存（`loadFromDiskIntoCache`）；
/// - `load*` 直接返回缓存；`save*` 同步更新缓存 + 异步写盘（私有串行队列批量合并）；
/// - `flush()` 同步等待队列中全部写盘完成，退出路径调用；
/// - 缓存读走 `NSLock`（短临界区），文件 I/O 走 `writeQueue`，互不阻塞。
///
/// ## 内存态兜底
/// - `inMemory()` 工厂产出无目录 store，所有 save/update 仅更新缓存不落盘；
/// - `isPersistent == false` 时 `flush()` 为 no-op；
/// - AppViewModel 在耐久目录初始化失败时改用 inMemory，永远不崩且不伪装持久化。
///
/// ## 错误暴露 + 导入校验
/// - `writeErrorHandler` 在异步写盘失败时回调（供 UI 切 `persistenceDegraded=true`）；
/// - `importAll(_:)` 校验 version / sessions 数量上限 / 时长范围，过滤后落地；
/// - 导入在兄弟暂存目录完成备份与编码，再目录级替换提交。
public final class TomatoStore {
    public enum Filename {
        public static let sessions = "sessions.json"
        public static let quota = "quota.json"
        public static let settings = "settings.json"
        public static let engine = "engine.json"
    }

    /// `importAll` 可能抛的校验错；外部 switch 友好（`Equatable`）。
    public enum ValidationError: Error, Equatable {
        case unsupportedVersion(Int)
        case sessionLimitExceeded(Int)
        case durationOutOfRange(focus: Int?, longBreak: Int?)
        case dataTooLarge(actualBytes: Int, limitBytes: Int)
        case stringTooLong(field: String, actualCharacters: Int, limitCharacters: Int)
        case stringTooLarge(field: String, actualBytes: Int, limitBytes: Int)
        case abortHistoryLimitExceeded(Int)
    }

    /// 导入事务在备份或最终目录替换阶段失败。两种错误都保证导入前目录与缓存不变。
    public enum ImportError: Error {
        case backupFailed(Error)
        case commitFailed(Error)
    }

    /// 仅供单测稳定注入文件系统故障，不暴露为产品 API。
    enum ImportFaultPoint {
        case backup
        case commit
    }

    /// 会话导入与本地历史上限。
    public static let importSessionLimit = 100_000

    /// 任一 JSON 文件或导入/导出包的硬上限。先查文件元数据再读盘，避免损坏或
    /// 人工构造的本地文件在启动时把整个进程内存吃光。
    public static let maximumPayloadBytes = 64 * 1024 * 1024
    public static let sessionIDCharacterLimit = 128
    public static let sessionNoteCharacterLimit = 4_096
    public static let modelNameCharacterLimit = 128
    public static let shortcutCharacterLimit = 256
    public static let sessionIDByteLimit = 512
    public static let sessionNoteByteLimit = 16 * 1_024
    public static let modelNameByteLimit = 512
    public static let shortcutByteLimit = 1_024
    public static let dateKeyByteLimit = 10
    public static let languageByteLimit = 16

    /// 单会话 `durationMin` 允许的合法区间。
    public static let durationRange: ClosedRange<Int> = 0...1440

    /// `false` ⇒ 纯内存态（不落盘）。`true` ⇒ 写到 `directory`。
    public let isPersistent: Bool

    /// 物理目录。`nil` 时为内存态。
    public let directory: URL?

    /// 写盘失败时异步回调；UI 层借此把 `persistenceDegraded` 置 true。
    /// getter/setter 受缓存锁保护，且回调不在 writeQueue 上执行，允许安全重入 `flush()`。
    /// `inMemory` store 永不触发。
    public var writeErrorHandler: ((Error) -> Void)? {
        get {
            lock.lock(); defer { lock.unlock() }
            return _writeErrorHandler
        }
        set {
            lock.lock(); defer { lock.unlock() }
            _writeErrorHandler = newValue
        }
    }

    /// 启动时无法解码的文件名。原始文件会尽力复制为 `*.corrupt.bak`，供用户恢复。
    public private(set) var startupReadFailures: [String] = []

    // MARK: 缓存与队列

    /// 缓存互斥。lock 只保护状态对象与 dirty 集合，不做文件 I/O。
    private let lock = NSLock()
    /// 串行化 save/clear 与整次导入，防止导入排干写队列后又插入新写任务。
    private let mutationLock = NSRecursiveLock()
    private var _sessions: [FocusSession] = []
    private var _quota: DailyQuota?
    private var _settings: AppSettings?
    private var _snapshot: EngineSnapshot?
    private var _writeErrorHandler: ((Error) -> Void)?
    /// 待写盘的脏文件名集合。
    private var dirty: Set<String> = []

    /// 串行写盘队列（仅文件 I/O 用，单线程天然排序）。
    private let writeQueue: DispatchQueue

    var importFaultInjector: ((ImportFaultPoint) throws -> Void)?
    /// 仅供测试注入普通 flush 的单文件写故障。
    var writeFaultInjector: ((String) throws -> Void)?

    // MARK: - Init

    public init(directory: URL) throws {
        self.isPersistent = true
        self.directory = directory
        self.writeQueue = DispatchQueue(
            label: "rlt.tomato.store.write.\(UUID().uuidString)",
            qos: .utility
        )
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw NSError(
                    domain: "TomatoStore",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "store path is not a directory"]
                )
            }
        } else {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        // 初始化即验证目录可写，避免首次异步保存时才发现所谓“持久化”其实不可用。
        let probe = directory.appendingPathComponent(".rlt-write-probe-\(UUID().uuidString)")
        do {
            try Data().write(to: probe, options: .atomic)
            try fm.removeItem(at: probe)
        } catch {
            try? fm.removeItem(at: probe)
            throw error
        }
        try loadFromDiskIntoCache()
    }

    /// 内存态工厂（永不抛错、不落盘）。`isPersistent == false`。
    public static func inMemory() -> TomatoStore {
        TomatoStore(inMemoryMarker: ())
    }

    private init(inMemoryMarker: Void) {
        self.isPersistent = false
        self.directory = nil
        self.writeQueue = DispatchQueue(
            label: "rlt.tomato.store.inmem.\(UUID().uuidString)",
            qos: .utility
        )
    }

    /// 默认目录：`~/Library/Application Support/RateLimitTomato/`。
    public static func defaultDirectory() throws -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
        guard let base = base else {
            throw NSError(
                domain: "TomatoStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Application Support directory unavailable"]
            )
        }
        return base.appendingPathComponent("RateLimitTomato", isDirectory: true)
    }

    /// 启动时一次性把四个文件读入缓存。损坏文件降级为空，同时保留恢复副本并暴露告警。
    private func loadFromDiskIntoCache() throws {
        guard isPersistent, directory != nil else { return }
        if let sessions = decodeFile([FocusSession].self, from: Filename.sessions) {
            do {
                try Self.validateSessions(sessions)
                _sessions = sessions
            } catch {
                recordStartupReadFailure(Filename.sessions)
                _sessions = []
            }
        }
        if let quota = decodeFile(DailyQuota.self, from: Filename.quota) {
            do {
                try Self.validateQuotaResourceBounds(quota)
                _quota = quota
            } catch {
                recordStartupReadFailure(Filename.quota)
                _quota = nil
            }
        }
        if let settings = decodeFile(AppSettings.self, from: Filename.settings) {
            do {
                try Self.validateSettings(settings)
                _settings = settings
            } catch {
                recordStartupReadFailure(Filename.settings)
                _settings = nil
            }
        }
        if let snapshot = decodeFile(EngineSnapshot.self, from: Filename.engine) {
            do {
                try Self.validateSnapshotResourceBounds(snapshot)
                _snapshot = snapshot
            } catch {
                recordStartupReadFailure(Filename.engine)
                _snapshot = nil
            }
        }
    }

    private func decodeFile<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        do {
            return try self.read(type, from: filename)
        } catch {
            recordStartupReadFailure(filename)
            return nil
        }
    }

    private func recordStartupReadFailure(_ filename: String) {
        if !startupReadFailures.contains(filename) { startupReadFailures.append(filename) }
        preserveUnreadableFile(named: filename)
    }

    /// 只创建第一份恢复副本，避免后续启动覆盖最早仍可人工修复的原始数据。
    /// 同目录 rename 不读取或复制 payload，因此超大损坏文件也不会放大启动内存/磁盘压力。
    private func preserveUnreadableFile(named filename: String) {
        guard let directory else { return }
        let fm = FileManager.default
        let source = directory.appendingPathComponent(filename)
        let backup = directory.appendingPathComponent(filename + ".corrupt.bak")
        guard fm.fileExists(atPath: source.path), !fm.fileExists(atPath: backup.path) else { return }
        try? fm.moveItem(at: source, to: backup)
    }

    // MARK: - Coders

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Generic atomic JSON I/O

    public func write<T: Encodable>(_ value: T, to filename: String) throws {
        let url = directory?.appendingPathComponent(filename)
        let encoder = Self.makeEncoder()
        let data = try encoder.encode(value)
        if let url = url {
            try Self.atomicWrite(data: data, to: url)
        }
    }

    public func read<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
        guard let url = directory?.appendingPathComponent(filename) else {
            throw NSError(
                domain: "TomatoStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "in-memory store cannot read \(filename)"]
            )
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        if fileSize > UInt64(Self.maximumPayloadBytes) {
            throw ValidationError.dataTooLarge(
                actualBytes: fileSize > UInt64(Int.max) ? Int.max : Int(fileSize),
                limitBytes: Self.maximumPayloadBytes
            )
        }
        try handle.seek(toOffset: 0)
        // 即使另一个进程在 seek 后继续追加，也最多读取 limit + 1 字节。
        let data = try handle.read(upToCount: Self.maximumPayloadBytes + 1) ?? Data()
        try Self.validatePayloadSize(data.count)
        let decoder = Self.makeDecoder()
        return try decoder.decode(T.self, from: data)
    }

    static func validatePayloadSize(_ byteCount: Int) throws {
        guard byteCount <= maximumPayloadBytes else {
            throw ValidationError.dataTooLarge(
                actualBytes: byteCount,
                limitBytes: maximumPayloadBytes
            )
        }
    }

    private static func validateString(
        _ value: String,
        field: String,
        characterLimit: Int,
        byteLimit: Int
    ) throws {
        let byteCount = value.utf8.count
        guard byteCount <= byteLimit else {
            throw ValidationError.stringTooLarge(
                field: field,
                actualBytes: byteCount,
                limitBytes: byteLimit
            )
        }
        let count = value.count
        guard count <= characterLimit else {
            throw ValidationError.stringTooLong(
                field: field,
                actualCharacters: count,
                limitCharacters: characterLimit
            )
        }
    }

    private static func validateSession(_ session: FocusSession) throws {
        try validateString(
            session.id,
            field: "session.id",
            characterLimit: sessionIDCharacterLimit,
            byteLimit: sessionIDByteLimit
        )
        try validateString(
            session.date,
            field: "session.date",
            characterLimit: dateKeyByteLimit,
            byteLimit: dateKeyByteLimit
        )
        try validateString(
            session.fakeModel,
            field: "session.fakeModel",
            characterLimit: modelNameCharacterLimit,
            byteLimit: modelNameByteLimit
        )
        if let note = session.note {
            try validateString(
                note,
                field: "session.note",
                characterLimit: sessionNoteCharacterLimit,
                byteLimit: sessionNoteByteLimit
            )
        }
    }

    private static func validateSessions(_ sessions: [FocusSession]) throws {
        guard sessions.count <= importSessionLimit else {
            throw ValidationError.sessionLimitExceeded(sessions.count)
        }
        for session in sessions { try validateSession(session) }
    }

    private static func validateSessionsPayload(
        _ sessions: [FocusSession],
        maximumPayloadBytes: Int
    ) throws {
        try validateSessions(sessions)
        let data = try makeEncoder().encode(sessions)
        guard data.count <= maximumPayloadBytes else {
            throw ValidationError.dataTooLarge(
                actualBytes: data.count,
                limitBytes: maximumPayloadBytes
            )
        }
    }

    private static func validateSettings(_ settings: AppSettings) throws {
        try validateString(
            settings.globalShortcut,
            field: "settings.globalShortcut",
            characterLimit: shortcutCharacterLimit,
            byteLimit: shortcutByteLimit
        )
        try validateString(
            settings.language,
            field: "settings.language",
            characterLimit: languageByteLimit,
            byteLimit: languageByteLimit
        )
    }

    private static func validateQuotaResourceBounds(_ quota: DailyQuota) throws {
        try validateString(
            quota.date,
            field: "quota.date",
            characterLimit: dateKeyByteLimit,
            byteLimit: dateKeyByteLimit
        )
    }

    private static func validateSnapshotResourceBounds(_ snapshot: EngineSnapshot) throws {
        guard snapshot.consecutiveAborts.count <= TomatoEngine.maximumAbortDatesToValidate else {
            throw ValidationError.abortHistoryLimitExceeded(snapshot.consecutiveAborts.count)
        }
        try validateString(
            snapshot.currentDayKey,
            field: "engine.currentDayKey",
            characterLimit: dateKeyByteLimit,
            byteLimit: dateKeyByteLimit
        )
        if let session = snapshot.currentSession { try validateSession(session) }
    }

    /// 在不遍历扩展字素簇的情况下，按 UTF-8 字节安全截断外部文本。
    public static func utf8Prefix(_ value: String, maximumBytes: Int) -> String {
        guard maximumBytes > 0 else { return "" }
        var result = String.UnicodeScalarView()
        var used = 0
        for scalar in value.unicodeScalars {
            let scalarBytes: Int
            switch scalar.value {
            case 0...0x7F: scalarBytes = 1
            case 0x80...0x7FF: scalarBytes = 2
            case 0x800...0xFFFF: scalarBytes = 3
            default: scalarBytes = 4
            }
            guard used + scalarBytes <= maximumBytes else { break }
            result.append(scalar)
            used += scalarBytes
        }
        return String(result)
    }

    public func delete(_ filename: String) throws {
        guard let url = directory?.appendingPathComponent(filename) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    public static func atomicWrite(data: Data, to url: URL) throws {
        try validatePayloadSize(data.count)
        let fm = FileManager.default
        let tmp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        defer {
            if fm.fileExists(atPath: tmp.path) { try? fm.removeItem(at: tmp) }
        }
        try data.write(to: tmp, options: .atomic)
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: tmp)
        } else {
            try fm.moveItem(at: tmp, to: url)
        }
    }

    // MARK: - Typed accessors（缓存优先）

    public func loadSessions() throws -> [FocusSession] {
        lock.lock(); defer { lock.unlock() }
        return _sessions
    }

    public func saveSessions(_ sessions: [FocusSession]) throws {
        try Self.validateSessionsPayload(sessions, maximumPayloadBytes: Self.maximumPayloadBytes)
        mutationLock.lock(); defer { mutationLock.unlock() }
        lock.lock()
        _sessions = sessions
        dirty.insert(Filename.sessions)
        lock.unlock()
        scheduleFlush()
    }

    /// 追加一个最终会话，并同时满足数量与序列化字节上限。若历史逼近上限，优先
    /// 删除最旧记录，且永远保留本次新会话。容量检查在改缓存前同步完成，因此调用
    /// 返回成功时，后台 flush 不会再因 payload 大小失败。
    public func appendSessionKeepingNewest(_ session: FocusSession) throws {
        try appendSessionKeepingNewest(
            session,
            maximumPayloadBytes: Self.maximumPayloadBytes,
            maximumSessionCount: Self.importSessionLimit
        )
    }

    /// 可注入边界仅用于确定性单测；生产调用使用上方公开入口。
    func appendSessionKeepingNewest(
        _ session: FocusSession,
        maximumPayloadBytes: Int,
        maximumSessionCount: Int
    ) throws {
        guard maximumSessionCount > 0 else {
            throw ValidationError.sessionLimitExceeded(1)
        }
        guard maximumPayloadBytes > 0 else {
            throw ValidationError.dataTooLarge(
                actualBytes: 0,
                limitBytes: maximumPayloadBytes
            )
        }
        try Self.validateSession(session)
        mutationLock.lock(); defer { mutationLock.unlock() }

        lock.lock()
        let existing = _sessions
        lock.unlock()

        let existingLimit = max(0, maximumSessionCount - 1)
        var candidate = existing.count > existingLimit
            ? Array(existing.suffix(existingLimit))
            : existing
        candidate.append(session)
        let encoder = Self.makeEncoder()
        let emptyArrayBytes = try encoder.encode([FocusSession]()).count

        while true {
            let data = try encoder.encode(candidate)
            if data.count <= maximumPayloadBytes { break }
            guard candidate.count > 1 else {
                throw ValidationError.dataTooLarge(
                    actualBytes: data.count,
                    limitBytes: maximumPayloadBytes
                )
            }

            // 首次全量编码得到精确 overflow；随后只编码最旧的单条记录并累计其
            // 数组贡献，一次删除足够大的前缀。这样既不会因总体平均值失真而过度
            // 淘汰，也不会反复编码接近 64 MiB 的整份历史形成边界 DoS。
            let overflow = data.count - maximumPayloadBytes
            let targetRelease = overflow
            var estimatedRelease = 0
            var dropCount = 0
            for oldSession in candidate.dropLast() {
                let singleArrayBytes = try encoder.encode([oldSession]).count
                // 多元素 pretty JSON 中每个被删元素还释放 `,\n` 两个分隔字节。
                estimatedRelease += max(1, singleArrayBytes - emptyArrayBytes + 2)
                dropCount += 1
                if estimatedRelease >= targetRelease { break }
            }
            candidate.removeFirst(max(1, min(candidate.count - 1, dropCount)))
        }

        lock.lock()
        _sessions = candidate
        dirty.insert(Filename.sessions)
        lock.unlock()
        scheduleFlush()
    }

    /// `true` 表示最近的会话缓存尚未成功写入磁盘。调用方应先 `flush()`，再读取。
    public var hasPendingSessionWrite: Bool {
        lock.lock(); defer { lock.unlock() }
        return isPersistent && dirty.contains(Filename.sessions)
    }

    public func loadQuota() throws -> DailyQuota? {
        lock.lock(); defer { lock.unlock() }
        return _quota
    }

    public func saveQuota(_ quota: DailyQuota) throws {
        try Self.validateQuotaResourceBounds(quota)
        try Self.validatePayloadSize(Self.makeEncoder().encode(quota).count)
        mutationLock.lock(); defer { mutationLock.unlock() }
        lock.lock()
        _quota = quota
        dirty.insert(Filename.quota)
        lock.unlock()
        scheduleFlush()
    }

    public func loadSettings() throws -> AppSettings? {
        lock.lock(); defer { lock.unlock() }
        return _settings
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try Self.validateSettings(settings)
        try Self.validatePayloadSize(Self.makeEncoder().encode(settings).count)
        mutationLock.lock(); defer { mutationLock.unlock() }
        lock.lock()
        _settings = settings
        dirty.insert(Filename.settings)
        lock.unlock()
        scheduleFlush()
    }

    public func loadEngineSnapshot() throws -> EngineSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return _snapshot
    }

    public func saveEngineSnapshot(_ snapshot: EngineSnapshot) throws {
        try Self.validateSnapshotResourceBounds(snapshot)
        try Self.validatePayloadSize(Self.makeEncoder().encode(snapshot).count)
        mutationLock.lock(); defer { mutationLock.unlock() }
        lock.lock()
        _snapshot = snapshot
        dirty.insert(Filename.engine)
        lock.unlock()
        scheduleFlush()
    }

    public func clearEngineSnapshot() throws {
        mutationLock.lock(); defer { mutationLock.unlock() }
        lock.lock()
        _snapshot = nil
        dirty.insert(Filename.engine)
        lock.unlock()
        scheduleFlush()
    }

    // MARK: - Bulk export / import

    /// 把缓存里的所有数据打包为单个 JSON（SPEC §11.3 导出/导入）。
    /// 缓存读失败概率为 0，但仍用 `do/catch` 让编码错（如 cyclic struct）能向上抛。
    public func exportAll() throws -> Data {
        let bundle: ExportBundle
        do {
            lock.lock()
            let snapshot = ExportBundle(
                version: 1,
                exportedAt: Date(),
                sessions: _sessions,
                quota: _quota,
                settings: _settings,
                engine: _snapshot
            )
            lock.unlock()
            bundle = snapshot
        }
        let data = try Self.makeEncoder().encode(bundle)
        try Self.validatePayloadSize(data.count)
        return data
    }

    /// 导入并替换当前所有数据。持久化路径会在兄弟目录构建带 `*.bak` 的完整候选，
    /// 再用一次目录替换同步提交；返回成功时缓存与磁盘已经一致。
    /// - version 必须等于 1；
    /// - sessions 数量上限 100_000；
    /// - durationMin 钳到 0...1440；
    /// - settings 走 `sanitized()`（clamp + language 白名单）。
    public func importAll(
        _ data: Data,
        now: Date? = nil,
        calendar: Calendar = .current
    ) throws {
        try Self.validatePayloadSize(data.count)
        let bundle: ExportBundle
        do {
            bundle = try Self.makeDecoder().decode(ExportBundle.self, from: data)
        } catch {
            throw error
        }
        guard bundle.version == 1 else {
            throw ValidationError.unsupportedVersion(bundle.version)
        }
        if bundle.sessions.count > Self.importSessionLimit {
            throw ValidationError.sessionLimitExceeded(bundle.sessions.count)
        }
        try Self.validateSessions(bundle.sessions)
        if let quota = bundle.quota { try Self.validateQuotaResourceBounds(quota) }
        if let settings = bundle.settings { try Self.validateSettings(settings) }
        if let engine = bundle.engine { try Self.validateSnapshotResourceBounds(engine) }
        let clampedSessions: [FocusSession] = bundle.sessions.map { session in
            var c = session
            c.durationMin = min(Self.durationRange.upperBound,
                                max(Self.durationRange.lowerBound, session.durationMin))
            return c
        }
        let sanitizedSettings = bundle.settings?.sanitized()
        let effectiveMax = sanitizedSettings?.maxPerDay ?? AppSettings.default.maxPerDay
        let sanitizedQuota = bundle.quota?.sanitized(effectiveMaxPerDay: effectiveMax)
        // 默认相对快照自身的进入时刻做结构校验，以保持 v1 export/import 的无损往返；
        // 真正恢复运行态时 TomatoEngine.restore 仍会相对当前注入时钟再次拒绝过期快照。
        let snapshotReferenceDate = now ?? bundle.engine?.phaseEnteredAt ?? bundle.exportedAt
        let sanitizedEngine = bundle.engine.flatMap {
            TomatoEngine.validatedSnapshot($0, now: snapshotReferenceDate, calendar: calendar)
        }

        mutationLock.lock(); defer { mutationLock.unlock() }
        // mutationLock 阻止新 save 插队；flush 排干此前已经排队的全部旧写任务。
        flush()
        if isPersistent && hasPendingWrites {
            let error = NSError(
                domain: "TomatoStore.Import",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "pending writes could not be flushed before import"]
            )
            throw ImportError.backupFailed(error)
        }
        if isPersistent {
            try commitPersistentImport(
                sessions: clampedSessions,
                quota: sanitizedQuota,
                settings: sanitizedSettings,
                engine: sanitizedEngine
            )
        }
        replaceCacheAfterImport(
            sessions: clampedSessions,
            quota: sanitizedQuota,
            settings: sanitizedSettings,
            engine: sanitizedEngine
        )
    }

    private func replaceCacheAfterImport(sessions: [FocusSession],
                                         quota: DailyQuota?,
                                         settings: AppSettings?,
                                         engine: EngineSnapshot?) {
        lock.lock()
        _sessions = sessions
        _quota = quota
        _settings = settings
        _snapshot = engine
        // 持久化导入已同步完成；内存态无需写盘。两者都不应留下脏任务。
        dirty.removeAll()
        lock.unlock()
    }

    private var hasPendingWrites: Bool {
        lock.lock(); defer { lock.unlock() }
        return !dirty.isEmpty
    }

    /// 在同一文件系统的兄弟目录构建完整候选，再以一次目录替换提交。
    /// 备份与候选构建期间不会触碰当前目录；任何错误都 fail-closed。
    private func commitPersistentImport(sessions: [FocusSession],
                                        quota: DailyQuota?,
                                        settings: AppSettings?,
                                        engine: EngineSnapshot?) throws {
        guard let directory = directory else { return }
        let fm = FileManager.default
        let parent = directory.deletingLastPathComponent()
        let transactionID = UUID().uuidString
        let staging = parent.appendingPathComponent(
            ".\(directory.lastPathComponent).import-\(transactionID)",
            isDirectory: true
        )
        let replacedBackupName = ".\(directory.lastPathComponent).preimport-\(transactionID)"
        let replacedBackup = parent.appendingPathComponent(replacedBackupName, isDirectory: true)
        defer {
            if fm.fileExists(atPath: staging.path) { try? fm.removeItem(at: staging) }
        }

        let filenames = [Filename.sessions, Filename.quota, Filename.settings, Filename.engine]
        do {
            try importFaultInjector?(.backup)
            try fm.copyItem(at: directory, to: staging)
            for filename in filenames {
                let source = directory.appendingPathComponent(filename)
                let backup = staging.appendingPathComponent(filename + ".bak")
                if fm.fileExists(atPath: source.path) {
                    if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
                    // 备份可能正是一个超大或损坏文件；文件级复制避免把它再次整块读入内存。
                    try fm.copyItem(at: source, to: backup)
                } else if fm.fileExists(atPath: backup.path) {
                    try fm.removeItem(at: backup)
                }
            }
        } catch {
            throw ImportError.backupFailed(error)
        }

        do {
            let payloads: [(String, Data?)] = [
                (Filename.sessions, try Self.makeEncoder().encode(sessions)),
                (Filename.quota, try quota.map { try Self.makeEncoder().encode($0) }),
                (Filename.settings, try settings.map { try Self.makeEncoder().encode($0) }),
                (Filename.engine, try engine.map { try Self.makeEncoder().encode($0) }),
            ]
            for (filename, payload) in payloads {
                let target = staging.appendingPathComponent(filename)
                if let payload {
                    try Self.atomicWrite(data: payload, to: target)
                } else if fm.fileExists(atPath: target.path) {
                    try fm.removeItem(at: target)
                }
            }
            try importFaultInjector?(.commit)
            _ = try fm.replaceItemAt(
                directory,
                withItemAt: staging,
                backupItemName: replacedBackupName,
                options: []
            )
        } catch {
            throw ImportError.commitFailed(error)
        }

        // 目录替换已成功；系统留下的 preimport 目录只用于原子交换，逐文件 .bak
        // 已包含在新目录中，故可清理。清理失败不改变导入成功语义。
        if fm.fileExists(atPath: replacedBackup.path) { try? fm.removeItem(at: replacedBackup) }
    }

    // MARK: - Flush

    /// 同步等待队列里全部待写盘任务完成。退出路径（Cmd+Q / deinit）调用。
    /// 内存态 store 为 no-op；调多次也安全（幂等）。
    public func flush() {
        mutationLock.lock(); defer { mutationLock.unlock() }
        guard isPersistent else { return }
        // writeQueue 是串行队列，sync 会先等待 in-flight 任务完成再跑本闭包。
        // processDirty 内部按缓存快照编码→ atomicWrite，全部文件 I/O 阻塞此处。
        writeQueue.sync { [weak self] in
            self?.processDirty()
        }
    }

    /// 把 `dirty` 集合里的全部文件落盘；调用者负责把 `writeQueue` 上锁。
    private func processDirty() {
        guard let directory = directory, isPersistent else { return }
        lock.lock()
        let toFlush = dirty
        dirty.removeAll()
        let dirtyQuota: DailyQuota? = (toFlush.contains(Filename.quota)) ? _quota : nil
        let dirtySettings: AppSettings? = (toFlush.contains(Filename.settings)) ? _settings : nil
        let dirtySnapshot: EngineSnapshot? = (toFlush.contains(Filename.engine)) ? _snapshot : nil
        let dirtySessions: [FocusSession]? = (toFlush.contains(Filename.sessions)) ? _sessions : nil
        lock.unlock()

        // history 必须先于 quota/snapshot 落盘：若进程在跨文件 flush 中途退出，
        // 启动对账仍可从旧快照重放，不能出现“最终态快照已写、历史却永久缺失”。
        let flushOrder = [Filename.sessions, Filename.quota, Filename.settings, Filename.engine]
        for (index, filename) in flushOrder.enumerated() where toFlush.contains(filename) {
            do {
                let url = directory.appendingPathComponent(filename)
                try writeFaultInjector?(filename)
                if let data = try encodeForFlush(filename: filename,
                                                sessions: dirtySessions,
                                                quota: dirtyQuota,
                                                settings: dirtySettings,
                                                snapshot: dirtySnapshot) {
                    try Self.atomicWrite(data: data, to: url)
                } else {
                    // cache 为 nil ⇒ 用户已显式 clear 或文件本来就缺；删除磁盘上的旧文件
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                }
            } catch {
                // 严格按前缀提交：任一较早文件失败时，本批次后续文件全部保持 dirty。
                // 特别是 sessions 失败后绝不能继续覆盖/删除 engine，否则会同时失去
                // 新历史与最终态恢复点。
                lock.lock()
                for pending in flushOrder[index...] where toFlush.contains(pending) {
                    dirty.insert(pending)
                }
                lock.unlock()
                if let handler = writeErrorHandler {
                    DispatchQueue.global(qos: .utility).async {
                        handler(error)
                    }
                }
                break
            }
        }
    }

    /// 用前面取出的快照把脏文件编码成 Data；返回 nil 表示"应删除"。
    private func encodeForFlush(filename: String,
                                sessions: [FocusSession]?,
                                quota: DailyQuota?,
                                settings: AppSettings?,
                                snapshot: EngineSnapshot?) throws -> Data? {
        switch filename {
        case Filename.sessions:
            return try Self.makeEncoder().encode(sessions ?? [])
        case Filename.quota:
            guard let q = quota else { return nil }
            return try Self.makeEncoder().encode(q)
        case Filename.settings:
            guard let s = settings else { return nil }
            return try Self.makeEncoder().encode(s)
        case Filename.engine:
            guard let s = snapshot else { return nil }
            return try Self.makeEncoder().encode(s)
        default:
            return nil
        }
    }

    /// 触发一次后台写盘；如已有 in-flight 任务则会自然合并最近 dirty 内容。
    private func scheduleFlush() {
        guard isPersistent else { return }
        writeQueue.async { [weak self] in
            self?.processDirty()
        }
    }

    public struct ExportBundle: Codable, Sendable {
        public var version: Int
        public var exportedAt: Date
        public var sessions: [FocusSession]
        public var quota: DailyQuota?
        public var settings: AppSettings?
        public var engine: EngineSnapshot?
    }
}
