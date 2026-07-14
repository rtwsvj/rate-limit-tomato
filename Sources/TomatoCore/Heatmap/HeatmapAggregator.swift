import Foundation

// MARK: - DayCell

/// 热力图宏观层（年度活动网格）单格。
/// - `date`：本地日期字符串 `YYYY-MM-DD`，按用户日历的"日"划分；
/// - `completedCount`：当日 `status == .completed` 的会话数；
/// - `level`：0-4 的颜色等级（§12.1 表）。
public struct DayCell: Sendable, Equatable, Hashable {
    public let date: String
    public let completedCount: Int
    public let level: Int

    public init(date: String, completedCount: Int, level: Int) {
        self.date = date
        self.completedCount = completedCount
        self.level = level
    }
}

// MARK: - HourBucket

/// 热力图钻取层（小时分布）单桶。
/// 只在 `dayDistribution` 中返回，`completed` 用于主柱、`aborted` 用于浅灰叠加。
public struct HourBucket: Sendable, Equatable, Hashable {
    public let hour: Int
    public let completedCount: Int
    public let abortedCount: Int

    public init(hour: Int, completedCount: Int, abortedCount: Int) {
        self.hour = hour
        self.completedCount = completedCount
        self.abortedCount = abortedCount
    }

    public var totalCount: Int {
        completedCount + abortedCount
    }
}

// MARK: - HeatmapAggregator

/// 纯函数聚合器：所有时间参数均由调用方注入，禁止内部 `Date()` / `Calendar.current`。
/// 视图层（`Sources/RateLimitTomato/Usage/`）只消费此处的输出，不做业务计算。
public enum HeatmapAggregator {
    /// SPEC §12.1：宏观网格 52 周 × 7 天（52 columns × 7 rows）。
    public static let weeksPerYear = 52
    public static let daysPerWeek = 7

    /// 行序固定为"周一→周日"（§12.1）。`firstWeekday = 2`。
    public static let firstWeekday = 2

    /// SPEC §12.1 颜色分级阈值。`n >= 7` → 4（level 4 没有上限）。
    public static func level(forCompletedCount n: Int) -> Int {
        switch n {
        case ..<1: return 0
        case 1...2: return 1
        case 3...4: return 2
        case 5...6: return 3
        default: return 4
        }
    }

    // MARK: - yearGrid

    /// 52 周 × 7 天的网格（`grid[week][day]`，day 0 = 周一）。
    /// 最后一列（`grid[51]`）包含 `endingAt` 当天所在的周（周一为首）。
    /// 行序：周一(0) / 周二(1) / … / 周日(6)。
    /// 仅 `status == .completed` 计入；缺失日期 → `level 0`、`completedCount 0`。
    public static func yearGrid(
        sessions: [FocusSession],
        endingAt: Date,
        calendar: Calendar
    ) -> [[DayCell]] {
        var cal = calendar
        cal.firstWeekday = firstWeekday

        // 1. 找到 endingAt 所在周的周一（最后一列的列首）。
        guard let lastColumnStart = cal.dateInterval(of: .weekOfYear, for: endingAt)?.start else {
            return Self.emptyGrid()
        }
        // 2. 向前回溯 51 周得到第一列的列首。
        guard let firstColumnStart = cal.date(byAdding: .weekOfYear, value: -(weeksPerYear - 1), to: lastColumnStart) else {
            return Self.emptyGrid()
        }

        // 3. 预聚合：date-string → 该日 completed 数。只跑一遍，O(N)。
        var counts: [String: Int] = [:]
        for s in sessions where s.status == .completed {
            counts[s.date, default: 0] += 1
        }

        // 4. 逐格生成。
        var grid: [[DayCell]] = []
        grid.reserveCapacity(weeksPerYear)
        for weekIdx in 0..<weeksPerYear {
            var week: [DayCell] = []
            week.reserveCapacity(daysPerWeek)
            for dayIdx in 0..<daysPerWeek {
                let dayOffset = (weekIdx * daysPerWeek) + dayIdx
                guard let date = cal.date(byAdding: .day, value: dayOffset, to: firstColumnStart) else {
                    week.append(DayCell(date: "", completedCount: 0, level: 0))
                    continue
                }
                let dateString = TomatoEngine.dateKey(now: date, calendar: cal)
                let count = counts[dateString] ?? 0
                week.append(DayCell(
                    date: dateString,
                    completedCount: count,
                    level: level(forCompletedCount: count)
                ))
            }
            grid.append(week)
        }
        return grid
    }

    // MARK: - uptimeDays

    /// 连续打卡天数。SPEC §12.1：`Uptime: N days`。
    /// - 从 `endingAt` 当天往回数；
    /// - 若当天尚无 completed 记录，从昨天起算（"今天还没打卡不该断 streak"）；
    /// - 第一个没有 completed 的日期即停。
    public static func uptimeDays(
        sessions: [FocusSession],
        endingAt: Date,
        calendar: Calendar
    ) -> Int {
        var activeDays = Set<String>()
        activeDays.reserveCapacity(sessions.count)
        for s in sessions where s.status == .completed {
            activeDays.insert(s.date)
        }
        if activeDays.isEmpty { return 0 }

        // 起点：今天若有 completed 则从今天开始，否则从昨天开始。
        let todayString = TomatoEngine.dateKey(now: endingAt, calendar: calendar)
        var cursor: Date
        if activeDays.contains(todayString) {
            cursor = endingAt
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: endingAt) {
            cursor = yesterday
        } else {
            return 0
        }

        var streak = 0
        while true {
            let key = TomatoEngine.dateKey(now: cursor, calendar: calendar)
            if activeDays.contains(key) {
                streak += 1
                guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else {
                    break
                }
                cursor = prev
            } else {
                break
            }
        }
        return streak
    }

    // MARK: - yearTotal

    /// SPEC §12.1：`{count} fast requests this year`。
    /// 按 `session.date` 前缀匹配年份（避免引入时区/Date 计算）。
    public static func yearTotal(sessions: [FocusSession], year: Int) -> Int {
        let prefix = String(format: "%04d-", year)
        var total = 0
        for s in sessions where s.status == .completed && s.date.hasPrefix(prefix) {
            total += 1
        }
        return total
    }

    // MARK: - dayDistribution

    /// SPEC §12.2：当日的 24 桶小时分布。`focusing` 状态不计入任何桶。
    /// 始终返回长度 24 的数组，缺失小时为全 0。
    public static func dayDistribution(
        sessions: [FocusSession],
        date: String
    ) -> [HourBucket] {
        var buckets: [HourBucket] = (0..<24).map {
            HourBucket(hour: $0, completedCount: 0, abortedCount: 0)
        }
        for s in sessions where s.date == date {
            guard s.startHour >= 0, s.startHour < 24 else { continue }
            let current = buckets[s.startHour]
            switch s.status {
            case .completed:
                buckets[s.startHour] = HourBucket(
                    hour: current.hour,
                    completedCount: current.completedCount + 1,
                    abortedCount: current.abortedCount
                )
            case .aborted:
                buckets[s.startHour] = HourBucket(
                    hour: current.hour,
                    completedCount: current.completedCount,
                    abortedCount: current.abortedCount + 1
                )
            case .focusing:
                continue
            }
        }
        return buckets
    }

    // MARK: - peakHour

    /// SPEC §12.2：`Peak: {H}:00-{H+1}:00 · {n} requests`。
    /// 取 `completedCount` 最大的小时；若全为 0，返回 `nil`。
    /// 多个并列时返回最早的小时（与 `for hour 0..<24` 遍历顺序一致）。
    public static func peakHour(distribution: [HourBucket]) -> (hour: Int, count: Int)? {
        var maxCount = 0
        var maxHour = -1
        for bucket in distribution {
            if bucket.completedCount > maxCount {
                maxCount = bucket.completedCount
                maxHour = bucket.hour
            }
        }
        guard maxHour >= 0 else { return nil }
        return (maxHour, maxCount)
    }

    // MARK: - monthLabels

    /// 每列首格（周一）所在的月份（1-12）。
    /// 视图层用此决定在哪里渲染 `Jan/Feb/...`：仅当月数相比前一列变化时画标签。
    public static func monthLabels(
        endingAt: Date,
        calendar: Calendar
    ) -> [Int: Int] {
        var cal = calendar
        cal.firstWeekday = firstWeekday

        guard let lastColumnStart = cal.dateInterval(of: .weekOfYear, for: endingAt)?.start,
              let firstColumnStart = cal.date(byAdding: .weekOfYear, value: -(weeksPerYear - 1), to: lastColumnStart) else {
            return [:]
        }

        var labels: [Int: Int] = [:]
        labels.reserveCapacity(weeksPerYear)
        for weekIdx in 0..<weeksPerYear {
            guard let date = cal.date(byAdding: .weekOfYear, value: weekIdx, to: firstColumnStart) else {
                continue
            }
            let month = cal.component(.month, from: date)
            labels[weekIdx] = month
        }
        return labels
    }

    // MARK: - Internals

    private static func emptyGrid() -> [[DayCell]] {
        let week = Array(repeating: DayCell(date: "", completedCount: 0, level: 0), count: daysPerWeek)
        return Array(repeating: week, count: weeksPerYear)
    }
}
