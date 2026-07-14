import Foundation

/// 状态机阶段（SPEC §6）。
public enum AppPhase: String, Codable, Sendable, CaseIterable {
    case idle
    case sending
    case focusing
    case completed
    case rateLimited
    case aborted
    case reset
    case teapot
}

/// 瞬时态的展示时长（按 SPEC §6.2）。
public enum PhaseTiming {
    /// 假请求飞过动画（SPEC §6.2 状态 2）。
    public static let sending: TimeInterval = 1.5
    /// 完成卡片闪现（SPEC §6.2 状态 4）。
    public static let completed: TimeInterval = 2.0
    /// 额度恢复提示（SPEC §6.2 状态 7）。
    public static let reset: TimeInterval = 2.0
    /// 茶壶彩蛋时间窗（SPEC §6.3）：30 分钟内连续 3 次 abort。
    public static let teapotWindow: TimeInterval = 30 * 60
}

/// 引擎的瞬时态快照（持久化用）。
/// 只含"会随运行变化的状态"：phase、进入时刻、当前 session、连续 abort 时间戳、当前日键。
/// 设置与每日额度由独立文件持久化，启动时分别加载。
public struct EngineSnapshot: Codable, Sendable, Equatable {
    public var phase: AppPhase
    public var phaseEnteredAt: Date
    public var currentSession: FocusSession?
    public var consecutiveAborts: [Date]
    public var currentDayKey: String

    public init(
        phase: AppPhase,
        phaseEnteredAt: Date,
        currentSession: FocusSession?,
        consecutiveAborts: [Date],
        currentDayKey: String
    ) {
        self.phase = phase
        self.phaseEnteredAt = phaseEnteredAt
        self.currentSession = currentSession
        self.consecutiveAborts = consecutiveAborts
        self.currentDayKey = currentDayKey
    }
}

/// 状态机（SPEC §6 全文）。
/// 计时一律走注入的 `clock`；所有状态时长判定都基于 `phaseEnteredAt` 墙钟差，
/// 对系统睡眠/时钟跳变天然鲁棒（暂停时差值不会推进）。
/// 此类型非 `Sendable`，生产环境须由 `@MainActor` 隔离的拥有者使用。
public final class TomatoEngine {
    // MARK: - Public state

    public private(set) var phase: AppPhase = .idle
    public private(set) var currentSession: FocusSession?
    public private(set) var settings: AppSettings
    public private(set) var quota: DailyQuota
    public private(set) var consecutiveAborts: [Date] = []
    public private(set) var phaseEnteredAt: Date
    public private(set) var currentDayKey: String

    /// 跨天事件的一次性标记，UI 读后调用 `clearDailyResetFlag()` 清除。
    public private(set) var didDailyReset: Bool = false
    /// 完成次数达到五的倍数时置位；UI 读后调用 `clearUpgradeNudgeFlag()` 清除。
    public private(set) var shouldNudgeUpgrade: Bool = false

    // MARK: - Dependencies

    public let clock: TomatoClock
    public let calendar: Calendar

    // MARK: - Init

    public init(
        clock: TomatoClock = SystemClock(),
        calendar: Calendar = .current,
        settings: AppSettings = .default,
        quota: DailyQuota? = nil
    ) {
        self.clock = clock
        self.calendar = calendar
        let sanitizedSettings = settings.sanitized()
        self.settings = sanitizedSettings
        let now = clock.now()
        self.phaseEnteredAt = now
        let dayKey = TomatoEngine.dateKey(now: now, calendar: calendar)
        self.currentDayKey = dayKey
        // 昨日额度要换新；但若持久化日期晚于当前系统日期，说明时钟发生回拨，
        // 必须保留已用额度与未来日键，直到墙钟真正越过它，防止重启刷新额度。
        if let q = quota,
           Self.isValidDateKey(q.date, calendar: calendar),
           q.date >= dayKey {
            self.quota = q.sanitized(effectiveMaxPerDay: sanitizedSettings.maxPerDay)
            self.currentDayKey = q.date
        } else {
            self.quota = DailyQuota(
                date: dayKey,
                usedToday: 0,
                maxPerDay: sanitizedSettings.maxPerDay,
                completedCount: 0,
                abortedCount: 0
            )
            if quota != nil { self.didDailyReset = true }
        }
    }

    // MARK: - Derived (read-only views)

    public var isQuotaExhausted: Bool {
        quota.usedToday >= settings.maxPerDay
    }

    public var remaining: Int {
        max(0, settings.maxPerDay - quota.usedToday)
    }

    public var maxPerDay: Int {
        settings.maxPerDay
    }

    public var focusElapsed: TimeInterval {
        guard phase == .focusing else { return 0 }
        return max(0, clock.now().timeIntervalSince(phaseEnteredAt))
    }

    public var focusRemaining: TimeInterval {
        guard phase == .focusing else { return 0 }
        let total = TimeInterval(settings.focusDurationMin * 60)
        let elapsed = max(0, clock.now().timeIntervalSince(phaseEnteredAt))
        return min(total, max(0, total - elapsed))
    }

    public var cooldownRemaining: TimeInterval {
        guard phase == .rateLimited else { return 0 }
        let total = TimeInterval(settings.cooldownDurationMin * 60)
        let elapsed = max(0, clock.now().timeIntervalSince(phaseEnteredAt))
        return min(total, max(0, total - elapsed))
    }

    /// 冷却重置的具体时刻（SPEC §8.1：限流文案用具体时刻，非倒计时）。
    public var cooldownResetAt: Date {
        phaseEnteredAt.addingTimeInterval(TimeInterval(settings.cooldownDurationMin * 60))
    }

    /// 清除 UI 已消费的跨天重置标志。
    public func clearDailyResetFlag() {
        didDailyReset = false
    }

    /// 清除一次性升级提示标志。
    public func clearUpgradeNudgeFlag() {
        shouldNudgeUpgrade = false
    }

    // MARK: - Settings

    /// 更新运行中设置并同步每日配额上限。
    public func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings.sanitized()
        // maxPerDay 可能被改，跟随同步；同时维持计数不变量。
        quota = quota.sanitized(effectiveMaxPerDay: settings.maxPerDay)
    }

    // MARK: - Events

    /// 用户在 IDLE 点击 Send Request。
    /// 额度耗尽时无效；返回是否真的发起了请求。
    /// `note`：用户填的"这次专注什么"（流式回显彩蛋 §9.4.3 用），随 session 持久化。
    @discardableResult
    public func sendRequest(note: String? = nil) -> Bool {
        let now = clock.now()
        checkDailyReset(now: now)
        guard phase == .idle else { return false }
        if isQuotaExhausted { return false }
        let session = Self.makeSession(now: now, settings: settings, calendar: calendar, note: note)
        currentSession = session
        quota.usedToday += 1
        transition(to: .sending, now: now)
        return true
    }

    /// FOCUSING 中用户点击 Abort。
    /// 若触发茶壶彩蛋则跳到 TEAPOT；否则到 ABORTED。
    public func abortRequest() {
        let now = clock.now()
        checkDailyReset(now: now)
        guard phase == .focusing else { return }

        // 只保留真实位于 30 分钟窗口内的历史，再记录本次中止。
        let chain = Self.sanitizedAbortChain(consecutiveAborts, now: now) + [now]
        if chain.count >= 3 {
            let oldest = chain[chain.count - 3]
            if now.timeIntervalSince(oldest) <= PhaseTiming.teapotWindow {
                consecutiveAborts = Array(chain.suffix(3))
                finalizeAbortedSession(now: now)
                recordAbortedOutcomeIfCurrentDay()
                transition(to: .teapot, now: now)
                return
            }
        }
        consecutiveAborts = Array(chain.suffix(3))
        finalizeAbortedSession(now: now)
        recordAbortedOutcomeIfCurrentDay()
        transition(to: .aborted, now: now)
    }

    /// ABORTED 选择"跳过休息"，或 RATE_LIMITED 选择"跳过休息"。
    public func skipCooldown() {
        let now = clock.now()
        checkDailyReset(now: now)
        guard phase == .aborted || phase == .rateLimited else { return }
        // 跳过冷却：当前 session 仍保留（aborted 状态），回到 idle 让用户可再发。
        // RATE_LIMITED 跳过的语义是"放弃这轮休息"，不立即归零 usedToday；
        // 配额已在 SENDING 扣减，按 SPEC §6.2 状态 5 此处只是视觉恢复。
        transition(to: .idle, now: now)
    }

    /// ABORTED 选择"还是去休息"。
    public func startCooldown() {
        let now = clock.now()
        checkDailyReset(now: now)
        guard phase == .aborted else { return }
        transition(to: .rateLimited, now: now)
    }

    /// 茶壶彩蛋退出。
    public func acknowledgeTeapot() {
        let now = clock.now()
        checkDailyReset(now: now)
        guard phase == .teapot else { return }
        consecutiveAborts = []
        currentSession = nil
        transition(to: .idle, now: now)
    }

    // MARK: - Tick

    /// 用注入的 `now` 推进状态机（测试友好）。
    /// 业务主循环可包装一个无参版本 `tick()`，调 `tick(now: clock.now())`。
    public func tick(now: Date) {
        checkDailyReset(now: now)

        switch phase {
        case .sending:
            if now.timeIntervalSince(phaseEnteredAt) >= PhaseTiming.sending {
                transition(to: .focusing, now: now)
            }
        case .focusing:
            let total = TimeInterval(settings.focusDurationMin * 60)
            if now.timeIntervalSince(phaseEnteredAt) >= total {
                finalizeCompletedSession(now: now)
                // 一次正常完成会打断“连续摸鱼”链。
                consecutiveAborts = []
                recordCompletedOutcomeIfCurrentDay()
                transition(to: .completed, now: now)
            }
        case .completed:
            if now.timeIntervalSince(phaseEnteredAt) >= PhaseTiming.completed {
                transition(to: .rateLimited, now: now)
            }
        case .rateLimited:
            let total = TimeInterval(settings.cooldownDurationMin * 60)
            if now.timeIntervalSince(phaseEnteredAt) >= total {
                transition(to: .reset, now: now)
            }
        case .reset:
            if now.timeIntervalSince(phaseEnteredAt) >= PhaseTiming.reset {
                currentSession = nil
                transition(to: .idle, now: now)
            }
        case .idle, .aborted, .teapot:
            break
        }
    }

    /// 便捷无参 tick（生产代码使用）。
    public func tick() {
        tick(now: clock.now())
    }

    // MARK: - Snapshot

    /// 生成可持久化的运行状态快照。
    public func snapshot() -> EngineSnapshot {
        EngineSnapshot(
            phase: phase,
            phaseEnteredAt: phaseEnteredAt,
            currentSession: currentSession,
            consecutiveAborts: consecutiveAborts,
            currentDayKey: currentDayKey
        )
    }

    /// 从快照恢复运行状态。即便调用方漏做预检，这里也只接受语义合法的快照，
    /// 并应用可安全修复的 abort 链清洗结果。
    public func restore(from snapshot: EngineSnapshot) {
        guard let validated = Self.validatedSnapshot(
            snapshot,
            now: clock.now(),
            calendar: calendar
        ) else { return }
        self.phase = validated.phase
        self.phaseEnteredAt = validated.phaseEnteredAt
        self.currentSession = validated.currentSession
        let liveDayKey = Self.dateKey(now: clock.now(), calendar: calendar)
        if Self.isValidDateKey(quota.date, calendar: calendar), quota.date > liveDayKey {
            // 冷启动时 init 已识别到系统日期回拨。旧/当前快照都不得把受保护的
            // quota 日键降回 liveDayKey，否则系统时间恢复时会再次赠送额度。
            self.currentDayKey = quota.date
            self.consecutiveAborts = validated.currentDayKey == quota.date
                ? validated.consecutiveAborts
                : []
        } else if validated.currentDayKey == liveDayKey {
            self.consecutiveAborts = validated.consecutiveAborts
            self.currentDayKey = liveDayKey
        } else {
            // 会话仍归开始日，但当日 quota 已由 init 按真实今天恢复；旧快照不可把
            // currentDayKey 拨回昨天，否则下一次 tick 会再次把今天的有效额度清零。
            self.consecutiveAborts = []
            self.currentDayKey = liveDayKey
            if quota.date != liveDayKey {
                self.quota = DailyQuota(
                    date: liveDayKey,
                    usedToday: 0,
                    maxPerDay: settings.maxPerDay,
                    completedCount: 0,
                    abortedCount: 0
                )
            }
            self.didDailyReset = true
        }
    }

    // MARK: - Snapshot 时间戳与结构校验

    /// 恢复窗口覆盖长期休眠/停用后重开；状态机每次最多八次有界追赶，资源字段也
    /// 已在 Store 层封顶，因此无需为了防御旧时间戳而丢弃合法未结会话。
    /// 十年前的快照仍拒绝，避免极端/手改日期进入运行态。
    public static let snapshotPastDays: TimeInterval = 3_650
    public static let secondsPerDay: TimeInterval = 86_400
    public static let snapshotPastWindow: TimeInterval = -snapshotPastDays * secondsPerDay
    /// 只容忍 5 分钟的轻微时钟回拨。更远的未来快照会冻结计时或制造错误恢复，必须拒绝。
    public static let snapshotFutureWindow: TimeInterval = 5 * 60
    /// 外部快照只需保留最近三次中止；给迁移数据留余量，同时阻止无界排序。
    public static let maximumAbortDatesToValidate = 64

    /// 验证并清洗可恢复快照。结构性矛盾（phase/session/status/date）直接拒绝；
    /// 过期、乱序或过量的 abort 时间戳属于可修复数据，会被裁剪后返回。
    public static func validatedSnapshot(
        _ snapshot: EngineSnapshot,
        now: Date,
        calendar: Calendar = .current
    ) -> EngineSnapshot? {
        let offset = snapshot.phaseEnteredAt.timeIntervalSince(now)
        guard offset >= snapshotPastWindow && offset <= snapshotFutureWindow,
              isValidDateKey(snapshot.currentDayKey, calendar: calendar) else {
            return nil
        }

        if let session = snapshot.currentSession {
            guard isValidDateKey(session.date, calendar: calendar) else { return nil }
            let createdOffset = session.createdAt.timeIntervalSince(now)
            guard createdOffset >= snapshotPastWindow - secondsPerDay,
                  createdOffset <= snapshotFutureWindow,
                  session.createdAt <= snapshot.phaseEnteredAt.addingTimeInterval(snapshotFutureWindow),
                  dateKey(now: session.createdAt, calendar: calendar) == session.date,
                  (0...23).contains(session.startHour),
                  (0...59).contains(session.startMinute),
                  TomatoStore.durationRange.contains(session.durationMin) else { return nil }
        }

        switch snapshot.phase {
        case .idle:
            guard snapshot.currentSession == nil else { return nil }
        case .sending, .focusing:
            guard snapshot.currentSession?.status == .focusing else { return nil }
        case .completed:
            guard snapshot.currentSession?.status == .completed else { return nil }
        case .aborted, .teapot:
            guard snapshot.currentSession?.status == .aborted else { return nil }
        case .rateLimited, .reset:
            guard let status = snapshot.currentSession?.status,
                  status == .completed || status == .aborted else { return nil }
        }

        var cleaned = snapshot
        let boundedAbortDates = snapshot.consecutiveAborts.count > maximumAbortDatesToValidate
            ? Array(snapshot.consecutiveAborts.suffix(maximumAbortDatesToValidate))
            : snapshot.consecutiveAborts
        cleaned.consecutiveAborts = sanitizedAbortChain(boundedAbortDates, now: now)
        if snapshot.phase == .teapot {
            guard cleaned.consecutiveAborts.count == 3 else { return nil }
        } else if snapshot.currentSession?.status == .completed {
            cleaned.consecutiveAborts = []
        } else if cleaned.consecutiveAborts.count >= 3 {
            // 非 TEAPOT 状态不可能同时带着窗口内三连中止；保留最近两次可继续使用。
            cleaned.consecutiveAborts = Array(cleaned.consecutiveAborts.suffix(2))
        }
        return cleaned
    }

    /// 兼容既有调用点的布尔预检。
    public static func isValidSnapshot(_ snapshot: EngineSnapshot, now: Date) -> Bool {
        validatedSnapshot(snapshot, now: now) != nil
    }

    /// 使用注入时钟检查快照时间戳是否位于允许窗口内。
    public static func isValidSnapshot(_ snapshot: EngineSnapshot, clock: TomatoClock) -> Bool {
        isValidSnapshot(snapshot, now: clock.now())
    }

    // MARK: - Helpers

    private func transition(to newPhase: AppPhase, now: Date) {
        phase = newPhase
        phaseEnteredAt = now
    }

    private func finalizeCompletedSession(now: Date) {
        guard var s = currentSession else { return }
        s.status = .completed
        s.durationMin = settings.focusDurationMin
        s.fakeTokens = Self.fakeTokenCount(durationMin: s.durationMin, id: s.id)
        currentSession = s
    }

    private func finalizeAbortedSession(now: Date) {
        guard var s = currentSession else { return }
        s.status = .aborted
        let elapsedMinutes = now.timeIntervalSince(s.createdAt) / 60
        if elapsedMinutes.isNaN || elapsedMinutes <= 0 {
            s.durationMin = 0
        } else if !elapsedMinutes.isFinite {
            s.durationMin = TomatoStore.durationRange.upperBound
        } else {
            s.durationMin = Int(min(
                Double(TomatoStore.durationRange.upperBound),
                elapsedMinutes.rounded(.down)
            ))
        }
        s.fakeTokens = Self.fakeTokenCount(durationMin: s.durationMin, id: s.id)
        currentSession = s
    }

    private func recordCompletedOutcomeIfCurrentDay() {
        guard currentSession?.date == quota.date else { return }
        quota.completedCount = min(DailyQuota.maximumTrackedCount, quota.completedCount + 1)
        quota = quota.sanitized(effectiveMaxPerDay: settings.maxPerDay)
        if quota.completedCount.isMultiple(of: 5) {
            shouldNudgeUpgrade = true
        }
    }

    private func recordAbortedOutcomeIfCurrentDay() {
        guard currentSession?.date == quota.date else { return }
        quota.abortedCount = min(DailyQuota.maximumTrackedCount, quota.abortedCount + 1)
        quota = quota.sanitized(effectiveMaxPerDay: settings.maxPerDay)
    }

    private static func sanitizedAbortChain(_ dates: [Date], now: Date) -> [Date] {
        let lowerBound = now.addingTimeInterval(-PhaseTiming.teapotWindow)
        return Array(dates
            .filter { $0 >= lowerBound && $0 <= now }
            .sorted()
            .suffix(3))
    }

    private static func isValidDateKey(_ key: String, calendar: Calendar) -> Bool {
        let pieces = key.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces[0].count == 4, pieces[1].count == 2, pieces[2].count == 2,
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2]) else {
            return false
        }
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let parsed = calendar.date(from: components) else { return false }
        return dateKey(now: parsed, calendar: calendar) == key
    }

    /// 装饰用假 token 数（§9.1.3）：约 500/分钟 + 按 id 的确定性扰动。
    private static func fakeTokenCount(durationMin: Int, id: String) -> Int {
        let jitter = id.utf8.reduce(0) { ($0 &* 31 &+ Int($1)) & 0x3FF }
        return max(0, durationMin * 500 + jitter - 512)
    }

    private func checkDailyReset(now: Date) {
        // 刻意设计（非漏洞）：跨天时进行中的专注/冷却不被打断——真内核优先（SPEC §3.2），
        // 计时可靠性高于额度戏仿；额度归零本身就是 §6.4 的日终语义。
        let today = Self.dateKey(now: now, calendar: calendar)
        // NTP/手动改时区造成日期倒退时不得凭空补一份额度；只在日键向前时重置。
        if today > currentDayKey {
            currentDayKey = today
            quota = DailyQuota(
                date: today,
                usedToday: 0,
                maxPerDay: settings.maxPerDay,
                completedCount: 0,
                abortedCount: 0
            )
            // 新的一天：清掉旧 abort 链，避免昨天残留今天也凑成茶壶。
            consecutiveAborts = []
            didDailyReset = true
        }
    }

    private static func makeSession(
        now: Date,
        settings: AppSettings,
        calendar: Calendar,
        note: String? = nil
    ) -> FocusSession {
        let comps = calendar.dateComponents([.hour, .minute], from: now)
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let dateKey = Self.dateKey(now: now, calendar: calendar)
        return FocusSession(
            id: SessionID.generate(),
            createdAt: now,
            date: dateKey,
            startHour: hour,
            startMinute: minute,
            durationMin: 0,
            status: .focusing,
            quality: 0,
            fakeTokens: 0,
            fakeModel: "tomato-1.0",
            note: note,
            provider: settings.provider
        )
    }

    /// 按指定日历生成稳定的 `YYYY-MM-DD` 日期键。
    public static func dateKey(now: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: now)
        let year = comps.year ?? 1970
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
