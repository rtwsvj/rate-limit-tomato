import Foundation
import SwiftUI
import TomatoCore

public enum MenuBarStyle { case remaining, countdown, rateLimited }

public struct PhasePresentation {
    public let label: String
    public let dotKind: StatusDotKind
    public let menuBarStyle: MenuBarStyle
    let soundCue: SoundService.Cue?

    static func forPhase(_ phase: AppPhase, quotaExhausted: Bool, locale: String) -> Self {
        switch phase {
        case .idle:
            let key = quotaExhausted ? "status.meta_exhausted" : "status.meta_ready"
            return .init(label: L10n.t(key, locale: locale), dotKind: quotaExhausted ? .muted : .success, menuBarStyle: .remaining, soundCue: nil)
        case .sending: return .init(label: L10n.t("parody.endpoint_focus", locale: locale), dotKind: .accentPulse, menuBarStyle: .remaining, soundCue: nil)
        case .focusing: return .init(label: L10n.t("status.meta_focusing", locale: locale), dotKind: .accentPulse, menuBarStyle: .countdown, soundCue: nil)
        case .completed: return .init(label: L10n.t("parody.status_ok", locale: locale), dotKind: .success, menuBarStyle: .remaining, soundCue: .completed)
        case .rateLimited: return .init(label: L10n.t("status.meta_rate_limited", locale: locale), dotKind: .deep, menuBarStyle: .rateLimited, soundCue: .rateLimited)
        case .aborted: return .init(label: L10n.t("status.meta_aborted", locale: locale), dotKind: .muted, menuBarStyle: .remaining, soundCue: nil)
        case .reset: return .init(label: L10n.t("status.meta_reset", locale: locale), dotKind: .success, menuBarStyle: .remaining, soundCue: .quotaReplenished)
        case .teapot: return .init(label: L10n.t("status.meta_teapot", locale: locale), dotKind: .deep, menuBarStyle: .remaining, soundCue: .teapot)
        }
    }
}

// MARK: - AppViewModel

/// UI 接线层 v2（UI-SPEC §5）。
/// 与 v1 的关键差异：
/// 1. 计时器随 init 启动，不依赖面板 onAppear（v1 最重的交互 bug：不开面板状态永远不走）；
/// 2. @Published 派生量只在真变化时赋值，避免整面板每秒无效重绘；
/// 3. RLT_TIME_SCALE 设定时用 ScaledClock + 隔离临时存储（QA 数据不混生产）。
@MainActor
public final class AppViewModel: ObservableObject {
    private static let maximumCatchUpTransitions = 8
    /// QA 加速只接受有限正数，避免 `inf`/极端倍率生成无效 `Date`。
    static let maximumTimeScale = 86_400.0
    private static let dailyResetBannerNanoseconds: UInt64 = 4_000_000_000
    public let store: TomatoStore
    public let engine: TomatoEngine

    // MARK: 发布给 UI 的镜像（赋值前都做变化检测）

    @Published public private(set) var phase: AppPhase = .idle
    @Published public private(set) var focusElapsed: TimeInterval = 0
    @Published public private(set) var cooldownRemaining: TimeInterval = 0
    @Published public private(set) var remaining: Int = 0
    @Published public private(set) var maxPerDay: Int = 8
    @Published public private(set) var isQuotaExhausted: Bool = false
    @Published public private(set) var providerTheme: Provider = .a
    @Published public var showUpgradeSheet: Bool = false
    @Published public var showDisclaimer: Bool = false
    /// 日终横幅（4s 自动淡出由视图控制，读取即消费）
    @Published public private(set) var dailyResetBannerVisible: Bool = false
    /// 每第 5 次完成的荒诞升级 nudge（SPEC §13.1）
    @Published public private(set) var pendingUpgradeNudge: Bool = false
    /// 持久化降级：内存态 store、启动读盘或后台写盘失败时为 true。
    @Published public private(set) var persistenceDegraded: Bool = false

    public var pendingNote: String = ""

    public var theme: TomatoTheme { TomatoTheme.theme(for: providerTheme) }
    public var settings: AppSettings { engine.settings }
    public var currentSession: FocusSession? { engine.currentSession }
    /// 流式回显文本（随 session 持久化，重启可恢复）
    public var sessionNote: String? { engine.currentSession?.note }

    // MARK: 私有

    private var persistedSessionIds: Set<String> = []
    /// 会话已进入缓存但尚未确认写盘时保留其 ID；此期间不得用 idle 快照覆盖
    /// 最终态恢复证据，也不得清除 engine.json。
    private var pendingFinalizedSessionID: String?
    private var ticker: TickerService?
    private var notifications: NotificationService?
    private var bannerDismissTask: Task<Void, Never>?
    private let globalIntegrationsEnabled: Bool
    private let globalShortcutInstaller: any GlobalShortcutInstalling
    private var didInstallGlobalShortcut = false
    /// MenuBarExtra 面板显隐（App 壳经 MenuBarExtraAccess 绑定；通知点击时置 true）
    @Published public var panelPresented: Bool = false
    /// rlt://usage 待开的用量窗口（面板 openWindow 上下文中消费）
    @Published public var pendingUsageWindow: Bool = false
    /// rlt://settings 待开的设置窗口
    @Published public var pendingSettingsWindow: Bool = false

    // MARK: Init

    public init(
        storeDirectory: URL? = nil,
        clock injectedClock: TomatoClock? = nil,
        calendar: Calendar = .current,
        urlCommands injectedURLCommands: URLCommandService? = nil,
        globalShortcutInstaller injectedGlobalShortcutInstaller: (any GlobalShortcutInstalling)? = nil,
        enableGlobalIntegrations: Bool = NSClassFromString("XCTestCase") == nil
            && ProcessInfo.processInfo.environment["RLT_DISABLE_GLOBAL_INTEGRATIONS"] != "1"
    ) {
        self.globalIntegrationsEnabled = enableGlobalIntegrations
        self.globalShortcutInstaller = injectedGlobalShortcutInstaller ?? SystemGlobalShortcutInstaller()

        // 1. 时钟：QA 缩放或系统钟
        let timeScale = Self.validatedTimeScale(
            ProcessInfo.processInfo.environment["RLT_TIME_SCALE"]
        )
        let clock: TomatoClock
        if let injected = injectedClock {
            clock = injected
        } else if let s = timeScale, s != 1 {
            clock = ScaledClock(base: SystemClock(), anchor: Date(), scale: s)
        } else {
            clock = SystemClock()
        }
        let isQA = timeScale != nil || injectedClock != nil

        // 2. 存储：QA 模式保留隔离临时目录；生产只认 Application Support。
        // 生产目录失败时必须明确降级为内存态，禁止用随机 /tmp 冒充可持久化存储。
        let s: TomatoStore
        if let directory = storeDirectory {
            s = (try? TomatoStore(directory: directory)) ?? TomatoStore.inMemory()
        } else if isQA {
            let qaDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RateLimitTomato-QA-\(UUID().uuidString)", isDirectory: true)
            s = (try? TomatoStore(directory: qaDirectory)) ?? TomatoStore.inMemory()
        } else if let directory = try? TomatoStore.defaultDirectory(),
                  let persistent = try? TomatoStore(directory: directory) {
            s = persistent
        } else {
            s = TomatoStore.inMemory()
        }
        self.store = s
        // 内存态即为降级；写盘失败在下方绑定的 handler 里降级。
        self.persistenceDegraded = !s.isPersistent || !s.startupReadFailures.isEmpty

        // 3. 引擎装配 + 恢复
        // settings 启动经过 sanitized()，防止手改 JSON 异常值进入运行态。
        let storedSettings = try? store.loadSettings()
        let loadedSettings = (storedSettings ?? .default).sanitized()
        let loadedQuota = try? store.loadQuota()
        self.engine = TomatoEngine(clock: clock, calendar: calendar,
                                   settings: loadedSettings, quota: loadedQuota)
        if let storedSettings, storedSettings != loadedSettings {
            try? store.saveSettings(loadedSettings)
        }
        if let loadedQuota, loadedQuota != engine.quota {
            try? store.saveQuota(engine.quota)
        }
        let existing = (try? store.loadSessions()) ?? []
        self.persistedSessionIds = Set(existing.map(\.id))
        // 恢复前做语义校验；可修复数据规范化回写，结构矛盾则清除，避免每次启动重复尝试。
        if (storeDirectory != nil || !isQA), let snapshot = try? store.loadEngineSnapshot() {
            if let validated = TomatoEngine.validatedSnapshot(
                snapshot,
                now: clock.now(),
                calendar: calendar
            ) {
                engine.restore(from: validated)
                if validated != snapshot { try? store.saveEngineSnapshot(validated) }
            } else {
                try? store.clearEngineSnapshot()
            }
        }
        if !loadedSettings.parodyDisclaimerAck {
            showDisclaimer = true
            panelPresented = true
        }

        // 必须在 self 完全初始化后再挂 handler（Swift 5.9 在 init 内闭包捕获 self 的限制）。
        s.writeErrorHandler = { [weak self] _ in
            Task { @MainActor in self?.persistenceDegraded = true }
        }

        // 分文件异步持久化可能在 sessions 写入前被进程终止；只要最终态快照幸存，
        // 启动时就把缺失的 completed/aborted 会话补回历史（ID 去重，幂等）。
        persistFinalizedSessionIfNeeded()
        syncDerived()
        start() // UI-SPEC §5.1：启动即走

        // 实用层装配（拼好码 v3）：通知 / 全局快捷键 / URL 命令。
        // NotificationService 在 XCTest / 无 bundle 环境自动降级为 no-op。
        let notif = NotificationService(isAvailable: enableGlobalIntegrations
                                        && Bundle.main.bundleURL.pathExtension == "app")
        notif.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .skipCooldown: self.skipCooldown()
            case .startNext: self.sendRequest()
            case .none:
                self.panelPresented = true // 点通知本体 → 弹面板
                _ = self.requireDisclaimerAuthorization()
            }
        }
        self.notifications = notif
        if loadedSettings.parodyDisclaimerAck {
            notif.activate(language: loadedSettings.language)
        }

        if enableGlobalIntegrations {
            let urlCommands = injectedURLCommands ?? URLCommandService.shared
            urlCommands.handler = { [weak self] command in
                self?.handle(command)
            }
        }
        installGlobalShortcutIfAuthorized()
    }

    /// 默认快捷键与 handler 只能在免责声明确认后安装；多入口重复调用保持幂等。
    private func installGlobalShortcutIfAuthorized() {
        guard globalIntegrationsEnabled,
              engine.settings.parodyDisclaimerAck,
              !didInstallGlobalShortcut else { return }
        didInstallGlobalShortcut = true
        globalShortcutInstaller.installSendOrAbort { [weak self] in
            Task { @MainActor in self?.hotkeyToggle() }
        }
    }

    /// 全局快捷键语义：idle→发起，focusing→中止，rateLimited/aborted→跳过，teapot→确认。
    private func hotkeyToggle() {
        guard requireDisclaimerAuthorization() else { return }
        switch engine.phase {
        case .idle: sendRequest()
        case .focusing: abortRequest()
        case .rateLimited, .aborted: skipCooldown()
        case .teapot: acknowledgeTeapot()
        case .sending, .completed, .reset: break
        }
    }

    private func handle(_ command: URLCommandService.Command) {
        switch command {
        case .startStop:
            guard requireDisclaimerAuthorization() else { return }
            hotkeyToggle()
        case .send:
            guard requireDisclaimerAuthorization() else { return }
            sendRequest()
        case .abort:
            guard requireDisclaimerAuthorization() else { return }
            abortRequest()
        case .skip:
            guard requireDisclaimerAuthorization() else { return }
            skipCooldown()
        case .usage:
            // openWindow 需要视图上下文：先弹面板，面板出现后消费此标记打开窗口
            pendingUsageWindow = true
            panelPresented = true
        case .settings:
            pendingSettingsWindow = true
            panelPresented = true
        }
    }

    // MARK: 主循环

    /// 启动每秒 ticker 与唤醒追平。
    public func start() {
        stop()
        let t = TickerService { [weak self] in self?.tick() }
        t.start()
        ticker = t
    }

    /// 停止 ticker 与唤醒监听。
    public func stop() {
        ticker?.stop()
        ticker = nil
    }

    /// 推进引擎直至当前墙钟下状态稳定并同步副作用。
    public func tick() {
        guard requireDisclaimerAuthorization(presentPanel: false) else { return }
        // 睡眠唤醒后墙钟可能一次跨多个阶段（focusing→completed→rateLimited→…），
        // 引擎每次 tick 最多推进一个转移——循环推进直到稳定。
        // 持久化必须逐转移即时做（引擎在 reset→idle 会清 currentSession，
        // 晚了就抓不住 completed 会话）；通知/音效只给最终稳定态，
        // 避免唤醒瞬间连环轰炸。
        var lastTransition: AppPhase? = nil
        var steps = 0
        while steps < Self.maximumCatchUpTransitions {
            let beforeSnapshot = engine.snapshot()
            let before = engine.phase
            let now = engine.clock.now()
            // 若睡眠跨过了一个或多个阶段，就在每个阶段的自然边界推进。
            // 这样 phaseEnteredAt 不会被错误地重置为唤醒时刻，也不依赖外部快照
            // 时效窗口，超长睡眠同样可以一次追平到稳定态。
            let transitionNow: Date
            if let duration = catchUpDuration(for: before) {
                transitionNow = min(now, beforeSnapshot.phaseEnteredAt.addingTimeInterval(duration))
            } else {
                transitionNow = now
            }
            engine.tick(now: transitionNow)
            guard engine.phase != before else { break }
            persistAfterTransition()
            lastTransition = engine.phase
            steps += 1
        }
        if let final = lastTransition {
            applyEffects(for: final)
        }
        if engine.didDailyReset {
            engine.clearDailyResetFlag()
            persistQuotaAndSnapshot() // 跨天归零立即落盘，防冷启动沿用昨日额度
            showDailyResetBanner()
        }
        syncDerived()
    }

    private func catchUpDuration(for phase: AppPhase) -> TimeInterval? {
        switch phase {
        case .sending: return PhaseTiming.sending
        case .focusing: return TimeInterval(engine.settings.focusDurationMin * 60)
        case .completed: return PhaseTiming.completed
        case .rateLimited: return TimeInterval(engine.settings.cooldownDurationMin * 60)
        case .reset: return PhaseTiming.reset
        case .idle, .aborted, .teapot: return nil
        }
    }

    /// 变化检测后再赋值（UI-SPEC §5.3）。
    private func syncDerived() {
        setIfChanged(\.phase, engine.phase)
        setIfChanged(\.remaining, engine.remaining)
        setIfChanged(\.maxPerDay, engine.maxPerDay)
        setIfChanged(\.isQuotaExhausted, engine.isQuotaExhausted)
        setIfChanged(\.providerTheme, engine.settings.provider)
        // 计时量在对应 phase 才更新（值每秒必变，无须比较）
        if engine.phase == .focusing { focusElapsed = engine.focusElapsed }
        else if focusElapsed != 0 { focusElapsed = 0 }
        if engine.phase == .rateLimited { cooldownRemaining = engine.cooldownRemaining }
        else if cooldownRemaining != 0 { cooldownRemaining = 0 }
    }

    private func setIfChanged<T: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<AppViewModel, T>, _ value: T
    ) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    /// 每个转移后的持久化（在下一次 engine.tick 前调用，见 tick 注释）。
    private func persistAfterTransition() {
        persistFinalizedSessionIfNeeded()
        persistQuotaAndSnapshot()
        if engine.phase == .idle && pendingFinalizedSessionID == nil {
            try? store.clearEngineSnapshot()
        }
    }

    /// 通知 / 音效 / 升级 nudge——只给最终稳定态。
    private func applyEffects(for new: AppPhase) {
        if engine.shouldNudgeUpgrade {
            pendingUpgradeNudge = true
            engine.clearUpgradeNudgeFlag()
        }
        if let cue = PhasePresentation.forPhase(
            new,
            quotaExhausted: engine.isQuotaExhausted,
            locale: engine.settings.language
        ).soundCue {
            SoundService.play(cue, enabled: engine.settings.soundEnabled)
        }
        // 系统通知（面板关着也能收到节律信号——真番茄钟的底线）
        switch new {
        case .rateLimited:
            notifications?.notifyCompleted(
                language: engine.settings.language,
                cooldownMinutes: engine.settings.cooldownDurationMin
            )
        case .reset:
            notifications?.notifyReset(language: engine.settings.language)
        default: break
        }
    }

    private func showDailyResetBanner() {
        dailyResetBannerVisible = true
        bannerDismissTask?.cancel()
        bannerDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.dailyResetBannerNanoseconds)
            if !Task.isCancelled { dailyResetBannerVisible = false }
        }
    }

    // MARK: 持久化

    /// finalized session 双路径落盘（tick 转移 + 用户动作）；失败时保留恢复证据。
    private func persistFinalizedSessionIfNeeded() {
        if let session = engine.currentSession,
           session.status == .completed || session.status == .aborted,
           !persistedSessionIds.contains(session.id) {
            pendingFinalizedSessionID = session.id
            let alreadyCached = ((try? store.loadSessions()) ?? []).contains {
                $0.id == session.id
            }
            if !alreadyCached {
                do {
                    try store.appendSessionKeepingNewest(session)
                } catch {
                    persistenceDegraded = true
                    return
                }
            }
        }

        guard let pendingID = pendingFinalizedSessionID else { return }
        // 会话历史是恢复事实的第一优先级。同步确认这一条真正落盘后，后续状态
        // 才能安全覆盖/删除 engine.json；失败时 dirty 与最终态快照都会保留重试。
        store.flush()
        guard !store.hasPendingSessionWrite else {
            persistenceDegraded = true
            return
        }
        persistedSessionIds.insert(pendingID)
        pendingFinalizedSessionID = nil
    }

    private func persistQuotaAndSnapshot() {
        try? store.saveQuota(engine.quota)
        // reset→idle 会清 currentSession。若历史仍未确认落盘，继续保留之前带会话的
        // 最终态快照，而不是用一个空 idle 快照覆盖唯一恢复证据。
        if engine.phase == .idle && pendingFinalizedSessionID != nil { return }
        try? store.saveEngineSnapshot(engine.snapshot())
    }

    /// 同步持久化当前会话、配额与引擎快照。
    public func flush() {
        persistFinalizedSessionIfNeeded()
        persistQuotaAndSnapshot()
        if engine.phase == .idle && pendingFinalizedSessionID == nil {
            try? store.clearEngineSnapshot()
        }
        store.flush()
    }

    /// 进程退出前同步等待队列里全部写盘任务完成。
    /// Swift 5.9 deinit 是非隔离的，TomatoStore.flush 内部自己排队，安全。
    deinit {
        store.flush()
    }

    // MARK: 用户动作

    /// 使用当前草稿发起一次专注请求。
    public func sendRequest() {
        guard requireDisclaimerAuthorization() else { return }
        // 额度判定交给 engine：它会先做日切，避免跨午夜后第一次点击仍被昨日额度拦住。
        guard engine.phase == .idle else { return }
        let byteBoundedNote = TomatoStore.utf8Prefix(
            pendingNote,
            maximumBytes: TomatoStore.sessionNoteByteLimit
        )
        let trimmedNote = byteBoundedNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = String(trimmedNote.prefix(TomatoStore.sessionNoteCharacterLimit))
        guard engine.sendRequest(note: note.isEmpty ? nil : note) else { return }
        pendingNote = ""
        persistQuotaAndSnapshot()
        syncDerived()
    }

    /// 中止当前专注请求并持久化结果。
    public func abortRequest() {
        guard requireDisclaimerAuthorization() else { return }
        engine.abortRequest()
        persistFinalizedSessionIfNeeded()
        persistQuotaAndSnapshot()
        syncDerived()
    }

    /// 跳过中止或限流后的冷却阶段。
    public func skipCooldown() {
        guard requireDisclaimerAuthorization() else { return }
        engine.skipCooldown()
        persistFinalizedSessionIfNeeded()
        persistQuotaAndSnapshot()
        if engine.phase == .idle && pendingFinalizedSessionID == nil {
            try? store.clearEngineSnapshot()
        }
        syncDerived()
    }

    /// 从中止态进入冷却阶段。
    public func startCooldown() {
        guard requireDisclaimerAuthorization() else { return }
        engine.startCooldown()
        persistQuotaAndSnapshot()
        syncDerived()
    }

    /// 确认茶壶彩蛋并返回空闲态。
    public func acknowledgeTeapot() {
        guard requireDisclaimerAuthorization() else { return }
        engine.acknowledgeTeapot()
        persistFinalizedSessionIfNeeded()
        persistQuotaAndSnapshot()
        if pendingFinalizedSessionID == nil { try? store.clearEngineSnapshot() }
        syncDerived()
    }

    /// 记录用户已确认戏仿免责声明。
    public func acknowledgeDisclaimer() {
        updateSettings { $0.parodyDisclaimerAck = true }
        installGlobalShortcutIfAuthorized()
        notifications?.activate(language: engine.settings.language)
        showDisclaimer = false
    }

    /// 读取并清除待展示的升级提示。
    public func consumeUpgradeNudge() -> Bool {
        let v = pendingUpgradeNudge
        pendingUpgradeNudge = false
        return v
    }

    /// 设置页统一写回入口。
    public func applySettings(_ mutate: (inout AppSettings) -> Void) {
        guard requireDisclaimerAuthorization() else { return }
        let sessionSettingsAreLocked = engine.phase != .idle
        let activeSettings = engine.settings
        updateSettings { settings in
            mutate(&settings)
            guard sessionSettingsAreLocked else { return }
            // 运行中的阶段必须继续使用启动该轮时的节律参数。否则设置窗口里的
            // Stepper 会让当前专注/冷却瞬间提前完成，或把已经消耗的额度重新解释。
            settings.focusDurationMin = activeSettings.focusDurationMin
            settings.cooldownDurationMin = activeSettings.cooldownDurationMin
            settings.longBreakMin = activeSettings.longBreakMin
            settings.maxPerDay = activeSettings.maxPerDay
        }
    }

    /// 唯一允许绕过免责门的设置写入口，只供 acknowledgeDisclaimer 使用。
    private func updateSettings(_ mutate: (inout AppSettings) -> Void) {
        objectWillChange.send() // settings 是 computed 非 @Published，须显式发布
        let oldLanguage = engine.settings.language
        var s = engine.settings
        mutate(&s)
        // 写盘前经过 sanitized，杜绝外部 mutate 塞入超出区间的值落盘。
        s = s.sanitized()
        engine.updateSettings(s)
        try? store.saveSettings(s)
        if s.language != oldLanguage {
            notifications?.refreshCategories(language: s.language)
        }
        syncDerived()
    }

    /// 解析 QA 时钟倍率。`1` 仍代表 QA 隔离模式，但不需要包裹缩放时钟。
    static func validatedTimeScale(_ raw: String?) -> Double? {
        guard let raw,
              let scale = Double(raw),
              scale.isFinite,
              scale > 0,
              scale <= maximumTimeScale else { return nil }
        return scale
    }

    /// 状态与设置写操作的集中授权门。读取 usage/settings 仍可进行；
    /// 任何被拦截的交互都会恢复免责叠层，外部入口还会主动弹出菜单面板。
    @discardableResult
    private func requireDisclaimerAuthorization(presentPanel: Bool = true) -> Bool {
        guard engine.settings.parodyDisclaimerAck else {
            showUpgradeSheet = false
            showDisclaimer = true
            if presentPanel { panelPresented = true }
            return false
        }
        return true
    }

    /// 从本地存储读取全部历史会话。
    public func loadSessions() -> [FocusSession] {
        (try? store.loadSessions()) ?? []
    }

    // MARK: 派生显示

    /// 滚动窗口计时对（UI-SPEC §3.3）：("2h 32m", "/ 5h 00m")。
    /// 分钟粒度：映射是 12× 速率，带秒位会每秒 +12s 跳动，被用户感知为计时故障
    /// （docs/CHANGES.md C7）。
    public func focusWindowPair() -> (elapsed: String, total: String) {
        let total = TimeInterval(engine.settings.focusDurationMin * 60)
        return TimeMapper.focusWindowMinutePair(elapsed: focusElapsed, total: total)
    }

    public func focusFraction() -> Double {
        TimeMapper.progressFraction(
            elapsed: focusElapsed,
            total: TimeInterval(engine.settings.focusDurationMin * 60)
        )
    }

    public func cooldownFraction() -> Double {
        let total = TimeInterval(engine.settings.cooldownDurationMin * 60)
        guard total > 0 else { return 1 }
        return min(1, max(0, 1 - cooldownRemaining / total))
    }

    /// 限流重置具体时刻 "HH:mm"（SPEC §8.1）。
    public func resetTimeDisplay() -> String {
        TimeMapper.resetTimeDisplay(resetAt: engine.cooldownResetAt)
    }

    /// 菜单栏文字（UI-SPEC §2 表）。
    public var menuBarText: String {
        switch phasePresentation.menuBarStyle {
        case .countdown:
            let r = Int(max(0, engine.focusRemaining))
            return String(format: "%d:%02d", r / 60, r % 60)
        case .rateLimited:
            return L10n.t("parody.status_rate_limited_code", locale: engine.settings.language)
        case .remaining:
            return isQuotaExhausted
                ? L10n.t("parody.status_unavailable_code", locale: engine.settings.language)
                : "\(remaining)"
        }
    }

    public var phasePresentation: PhasePresentation {
        PhasePresentation.forPhase(
            engine.phase,
            quotaExhausted: isQuotaExhausted,
            locale: engine.settings.language
        )
    }

    /// 顶栏状态点与标签（UI-SPEC §2 表）。
    public var statusMeta: (label: String, dotKind: StatusDotKind) {
        (phasePresentation.label, phasePresentation.dotKind)
    }
}

public enum StatusDotKind { case success, accentPulse, deep, muted }
