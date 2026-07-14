import Foundation

public enum AppLocale: String, Codable, Sendable, CaseIterable {
    case zhCN = "zh-CN"
    case en = "en"
}

// MARK: - Session Status

public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case focusing
    case completed
    case aborted
}

// MARK: - Provider (戏仿皮肤)

public enum Provider: String, Codable, Sendable, CaseIterable {
    case a
    case b
    case c
}

// MARK: - FocusSession

/// 一次专注会话。SPEC §11.1。
/// 字段顺序与命名严格按规格；字段类型选用最小可表达语义（分钟/整数），不嵌业务判断。
public struct FocusSession: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let createdAt: Date
    public let date: String
    public let startHour: Int
    public let startMinute: Int
    public var durationMin: Int
    public var status: SessionStatus
    public var quality: Int
    public var fakeTokens: Int
    public var fakeModel: String
    public var note: String?
    public var provider: Provider

    public init(
        id: String,
        createdAt: Date,
        date: String,
        startHour: Int,
        startMinute: Int,
        durationMin: Int,
        status: SessionStatus,
        quality: Int,
        fakeTokens: Int,
        fakeModel: String,
        note: String?,
        provider: Provider
    ) {
        self.id = id
        self.createdAt = createdAt
        self.date = date
        self.startHour = startHour
        self.startMinute = startMinute
        self.durationMin = durationMin
        self.status = status
        self.quality = quality
        self.fakeTokens = fakeTokens
        self.fakeModel = fakeModel
        self.note = note
        self.provider = provider
    }

    /// 合成确定性 ID，便于测试；业务默认走 `SessionID.generate()`。
    public static func makeID(_ suffix: String) -> String {
        "focus_\(suffix)"
    }
}

// MARK: - DailyQuota

public struct DailyQuota: Codable, Sendable, Equatable {
    public var date: String
    public var usedToday: Int
    public var maxPerDay: Int
    public var completedCount: Int
    public var abortedCount: Int

    public init(
        date: String,
        usedToday: Int,
        maxPerDay: Int,
        completedCount: Int,
        abortedCount: Int
    ) {
        self.date = date
        self.usedToday = usedToday
        self.maxPerDay = maxPerDay
        self.completedCount = completedCount
        self.abortedCount = abortedCount
    }

    /// 正常设置允许的最大每日计数。`usedToday` 不能直接钳到当前设置值：
    /// 用户可能在已经使用若干次后调低每日上限，此时保留真实用量并显示额度耗尽。
    public static let maximumTrackedCount = AppSettings.maxPerDayRange.upperBound

    /// 清洗手改 JSON、旧版本或导入数据中的不可能组合，保证后续加减法不会溢出。
    ///
    /// 不变量：
    /// - `maxPerDay` 与已清洗的有效设置一致；
    /// - 所有计数均非负且不超过产品允许的最大每日计数；
    /// - `completedCount + abortedCount <= usedToday`。
    public func sanitized(effectiveMaxPerDay: Int) -> DailyQuota {
        let effectiveMax = min(
            AppSettings.maxPerDayRange.upperBound,
            max(AppSettings.maxPerDayRange.lowerBound, effectiveMaxPerDay)
        )
        let used = min(Self.maximumTrackedCount, max(0, usedToday))
        let completed = min(used, max(0, completedCount))
        let aborted = min(used - completed, max(0, abortedCount))
        return DailyQuota(
            date: date,
            usedToday: used,
            maxPerDay: effectiveMax,
            completedCount: completed,
            abortedCount: aborted
        )
    }
}

// MARK: - AppSettings

/// 命名 `AppSettings` 避免与 SwiftUI.Settings 冲突。
public struct AppSettings: Codable, Sendable, Equatable {
    public var focusDurationMin: Int
    public var cooldownDurationMin: Int
    public var longBreakMin: Int
    public var maxPerDay: Int
    public var provider: Provider
    public var language: String
    public var showFakeLogs: Bool
    public var showFakeHeaders: Bool
    public var soundEnabled: Bool
    public var globalShortcut: String
    public var parodyDisclaimerAck: Bool

    public var appLocale: AppLocale { AppLocale(rawValue: language) ?? .zhCN }
    public var isEnglish: Bool { appLocale == .en }

    public init(
        focusDurationMin: Int,
        cooldownDurationMin: Int,
        longBreakMin: Int,
        maxPerDay: Int,
        provider: Provider,
        language: String,
        showFakeLogs: Bool,
        showFakeHeaders: Bool,
        soundEnabled: Bool,
        globalShortcut: String,
        parodyDisclaimerAck: Bool
    ) {
        self.focusDurationMin = focusDurationMin
        self.cooldownDurationMin = cooldownDurationMin
        self.longBreakMin = longBreakMin
        self.maxPerDay = maxPerDay
        self.provider = provider
        self.language = language
        self.showFakeLogs = showFakeLogs
        self.showFakeHeaders = showFakeHeaders
        self.soundEnabled = soundEnabled
        self.globalShortcut = globalShortcut
        self.parodyDisclaimerAck = parodyDisclaimerAck
    }

    public static let `default` = AppSettings(
        focusDurationMin: 25,
        cooldownDurationMin: 5,
        longBreakMin: 15,
        maxPerDay: 8,
        provider: .a,
        language: AppLocale.zhCN.rawValue,
        showFakeLogs: true,
        showFakeHeaders: true,
        soundEnabled: true,
        globalShortcut: "",
        parodyDisclaimerAck: false
    )

    // MARK: - Sanitization（防手改 JSON 异常值）

    public static let focusRange: ClosedRange<Int> = 1...480
    public static let cooldownRange: ClosedRange<Int> = 1...120
    public static let longBreakRange: ClosedRange<Int> = 1...240
    public static let maxPerDayRange: ClosedRange<Int> = 1...64
    /// 设置界面允许用户直接选择的产品范围；比 JSON 防御性清洗范围更窄。
    public static let focusInteractionRange: ClosedRange<Int> = 1...120
    public static let cooldownInteractionRange: ClosedRange<Int> = 1...60
    public static let maxPerDayInteractionRange: ClosedRange<Int> = 1...24
    public static let supportedLanguages: Set<String> = Set(AppLocale.allCases.map(\.rawValue))

    /// 把可能来自手改 JSON / 旧版本的脏值钳到合法区间。
    /// `language` 只允许 `"zh-CN"` / `"en"`，其他回落 `zh-CN`。
    /// 不修改 `provider` / 开关位 / 文案类字段。
    public func sanitized() -> AppSettings {
        var s = self
        s.focusDurationMin = min(Self.focusRange.upperBound,
                                  max(Self.focusRange.lowerBound, focusDurationMin))
        s.cooldownDurationMin = min(Self.cooldownRange.upperBound,
                                    max(Self.cooldownRange.lowerBound, cooldownDurationMin))
        s.longBreakMin = min(Self.longBreakRange.upperBound,
                             max(Self.longBreakRange.lowerBound, longBreakMin))
        s.maxPerDay = min(Self.maxPerDayRange.upperBound,
                          max(Self.maxPerDayRange.lowerBound, maxPerDay))
        s.language = Self.supportedLanguages.contains(language) ? language : AppSettings.default.language
        return s
    }
}

// MARK: - Session ID

public enum SessionID {
    public static func generate() -> String {
        let hex = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
            .prefix(8)
        return "focus_\(hex)"
    }
}
