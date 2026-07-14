import Foundation

/// 纯函数：专注进度展示 / 重置时刻展示 / 进度比例。
/// 不持有状态，可独立单测；不依赖时钟。
public enum TimeMapper {
    public static let focusWindowSeconds: TimeInterval = 5 * 3600

    /// 戏仿五小时窗口的分钟粒度展示对。
    public static func focusWindowMinutePair(elapsed: TimeInterval, total: TimeInterval) -> (elapsed: String, total: String) {
        let mapped = Int(progressFraction(elapsed: elapsed, total: total) * focusWindowSeconds)
        return (String(format: "%dh %02dm", mapped / 3600, (mapped % 3600) / 60), "/ 5h 00m")
    }
    /// 戏仿 5h 窗口展示：把实际 `elapsed` 相对 `total` 的比例线性映射到 5 小时窗口。
    /// 格式：`"4h 23m 12s / 5h00m00s"`（SPEC §9.2.1）
    /// - 左半：`Xh YYm ZZs`（小时不补零，分钟与秒补零到两位）。
    /// - 右半：固定 `5h00m00s`（窗口总长）。
    public static func focusWindowDisplay(elapsed: TimeInterval, total: TimeInterval) -> String {
        let fraction = progressFraction(elapsed: elapsed, total: total)
        let mapped = Int((fraction * focusWindowSeconds).rounded(.down))
        let hours = mapped / 3600
        let minutes = (mapped % 3600) / 60
        let seconds = mapped % 60
        return String(format: "%dh %02dm %02ds / 5h%02dm%02ds", hours, minutes, seconds, 0, 0)
    }

    /// 具体时刻展示（SPEC §8.1）：用本地时区 24h 格式 `HH:mm`。
/// 不用倒计时（`5:00`），保留滚动窗口式显示。
    public static func resetTimeDisplay(
        resetAt: Date,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: resetAt)
    }

    /// 进度比例，钳制到 `0...1`。
    public static func progressFraction(elapsed: TimeInterval, total: TimeInterval) -> Double {
        guard total > 0 else { return 0 }
        let raw = elapsed / total
        if raw.isNaN { return 0 }
        return min(1.0, max(0.0, raw))
    }
}
