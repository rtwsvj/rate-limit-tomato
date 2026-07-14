import XCTest
@testable import TomatoCore

final class HeatmapAggregatorTests: XCTestCase {

    // MARK: - Fixtures

    /// 测试用日历：UTC 时区，避免依赖宿主时区导致日期漂移。
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = HeatmapAggregator.firstWeekday
        return cal
    }

    /// 固定 weekday 让断言可控。
    /// 2026-07-08 是 Wednesday（UTC）。所在周（Mon-first）的周一 = 2026-07-06；
    /// 网格第一列的周一 = 51 周前 = 2025-07-14。
    private var fixedEndingAt: Date {
        var c = DateComponents()
        c.year = 2026
        c.month = 7
        c.day = 8
        c.hour = 12
        c.minute = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return utcCalendar.date(from: c)!
    }

    /// 构造一个指定 (date, startHour, status) 的会话。
    private func session(
        date: String,
        hour: Int = 10,
        status: SessionStatus = .completed
    ) -> FocusSession {
        FocusSession(
            id: FocusSession.makeID("\(date)-\(hour)-\(status.rawValue)"),
            createdAt: Date(timeIntervalSince1970: 0),
            date: date,
            startHour: hour,
            startMinute: 0,
            durationMin: status == .completed ? 25 : 5,
            status: status,
            quality: 80,
            fakeTokens: 0,
            fakeModel: "tomato-1.0",
            note: nil,
            provider: .a
        )
    }

    // MARK: - level thresholds

    func testLevelBoundaries() {
        // SPEC §12.1：0/1-2/3-4/5-6/7+。
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 0), 0)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 1), 1)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 2), 1)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 3), 2)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 4), 2)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 5), 3)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 6), 3)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 7), 4)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 8), 4)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: 42), 4)
        XCTAssertEqual(HeatmapAggregator.level(forCompletedCount: -1), 0)
    }

    // MARK: - yearGrid: 尺寸 & 末列含 endingAt

    func testYearGridDimensions() {
        let grid = HeatmapAggregator.yearGrid(
            sessions: [],
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        XCTAssertEqual(grid.count, HeatmapAggregator.weeksPerYear)
        XCTAssertEqual(grid.first?.count, HeatmapAggregator.daysPerWeek)
        XCTAssertEqual(grid.last?.count, HeatmapAggregator.daysPerWeek)
        // 整张网格恒为 52×7
        for week in grid {
            XCTAssertEqual(week.count, HeatmapAggregator.daysPerWeek)
        }
    }

    func testYearGridLastColumnContainsEndingAt() {
        let grid = HeatmapAggregator.yearGrid(
            sessions: [],
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        let lastWeek = grid.last!
        let contains = lastWeek.contains { $0.date == "2026-07-08" }
        XCTAssertTrue(contains, "last column must contain endingAt date 2026-07-08")
    }

    func testYearGridFirstColumnMondayIsCorrect() {
        // 2026-07-08 (Wed) 所在周（firstWeekday=Mon）的周一 = 2026-07-06。
        // 第一列 = 51 周前 = 2025-07-14 (Mon)。
        let grid = HeatmapAggregator.yearGrid(
            sessions: [],
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        XCTAssertEqual(grid.first?.first?.date, "2025-07-14")
    }

    func testYearGridEmptyCellsDefaultToZero() {
        let grid = HeatmapAggregator.yearGrid(
            sessions: [],
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        // 任意取一个早期日期，未填 session 应为 level 0 / count 0
        let cell = grid[0][3]  // 2025-07-14 + 3 = 2025-07-17 (Thu)
        XCTAssertEqual(cell.completedCount, 0)
        XCTAssertEqual(cell.level, 0)
        XCTAssertFalse(cell.date.isEmpty)
    }

    // MARK: - yearGrid: 实际计数与分级

    func testYearGridAggregatesCompletedOnly() {
        // 5 个 completed + 3 个 aborted 在同一天 → level 3 (5-6)
        let date = "2026-07-08"
        var sessions: [FocusSession] = []
        for _ in 0..<5 {
            sessions.append(session(date: date, hour: 9, status: .completed))
        }
        for _ in 0..<3 {
            sessions.append(session(date: date, hour: 10, status: .aborted))
        }
        // 1 个 focusing 也不计
        sessions.append(session(date: date, hour: 11, status: .focusing))

        let grid = HeatmapAggregator.yearGrid(
            sessions: sessions,
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        let cell = grid.last!.first { $0.date == date }!
        XCTAssertEqual(cell.completedCount, 5, "aborted/focusing must not count")
        XCTAssertEqual(cell.level, 3)
    }

    func testYearGridMapsCompletedCountToLevelBoundaries() {
        // 用 8 个不同日期，每档一个数；日期从 2026-07-01 到 2026-07-08，
        // 跨倒数第二列和最后一列。验证每档分级 + 边界都跑通。
        var sessions: [FocusSession] = []
        let plans: [(date: String, count: Int, expectedLevel: Int)] = [
            ("2026-07-01", 1, 1),  // 1 → level 1
            ("2026-07-02", 2, 1),  // 2 → level 1（边界）
            ("2026-07-03", 3, 2),  // 3 → level 2
            ("2026-07-04", 4, 2),  // 4 → level 2（边界）
            ("2026-07-05", 5, 3),  // 5 → level 3
            ("2026-07-06", 6, 3),  // 6 → level 3（边界）
            ("2026-07-07", 7, 4),  // 7 → level 4
            ("2026-07-08", 8, 4),  // 8 → level 4（7+ 仍为 4）
        ]
        for plan in plans {
            for h in 0..<plan.count {
                sessions.append(session(date: plan.date, hour: 8 + h, status: .completed))
            }
        }
        let grid = HeatmapAggregator.yearGrid(
            sessions: sessions,
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        func findCell(_ date: String) -> DayCell? {
            for week in grid {
                if let c = week.first(where: { $0.date == date }) { return c }
            }
            return nil
        }
        for plan in plans {
            let cell = findCell(plan.date)
            XCTAssertNotNil(cell, "missing cell for \(plan.date)")
            XCTAssertEqual(cell?.completedCount, plan.count, "count mismatch on \(plan.date)")
            XCTAssertEqual(cell?.level, plan.expectedLevel, "level mismatch on \(plan.date)")
        }
    }

    func testYearGridMissingDatesDefaultToZero() {
        // 完全空数据 → 所有格子 level 0，但 date 非空
        let grid = HeatmapAggregator.yearGrid(
            sessions: [],
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        let emptyCount = grid.flatMap { $0 }.filter { $0.completedCount == 0 && $0.level == 0 && !$0.date.isEmpty }.count
        XCTAssertEqual(emptyCount, HeatmapAggregator.weeksPerYear * HeatmapAggregator.daysPerWeek)
    }

    func testYearGridRowsAreMondayToSunday() {
        // 第一列第一个是 Monday, 最后一个是 Sunday
        let grid = HeatmapAggregator.yearGrid(
            sessions: [],
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        let firstWeek = grid.first!
        // 第一列周一 = 2025-07-14
        XCTAssertEqual(firstWeek[0].date, "2025-07-14")
        XCTAssertEqual(firstWeek[1].date, "2025-07-15")
        XCTAssertEqual(firstWeek[2].date, "2025-07-16")
        XCTAssertEqual(firstWeek[3].date, "2025-07-17")
        XCTAssertEqual(firstWeek[4].date, "2025-07-18")
        XCTAssertEqual(firstWeek[5].date, "2025-07-19")
        XCTAssertEqual(firstWeek[6].date, "2025-07-20")
    }

    // MARK: - uptimeDays

    func testUptimeDaysEmpty() {
        XCTAssertEqual(
            HeatmapAggregator.uptimeDays(
                sessions: [],
                endingAt: fixedEndingAt,
                calendar: utcCalendar
            ),
            0
        )
    }

    func testUptimeDaysOnlyAbortedDoesNotCount() {
        // 只有 aborted → streak = 0
        let sessions = [
            session(date: "2026-07-08", status: .aborted),
            session(date: "2026-07-07", status: .aborted),
        ]
        XCTAssertEqual(
            HeatmapAggregator.uptimeDays(
                sessions: sessions,
                endingAt: fixedEndingAt,
                calendar: utcCalendar
            ),
            0
        )
    }

    func testUptimeDaysConsecutiveFromToday() {
        // 今天 + 昨天 + 前天 = streak 3
        let sessions = [
            session(date: "2026-07-08", hour: 9, status: .completed),
            session(date: "2026-07-08", hour: 14, status: .completed),
            session(date: "2026-07-07", hour: 10, status: .completed),
            session(date: "2026-07-06", hour: 10, status: .completed),
        ]
        XCTAssertEqual(
            HeatmapAggregator.uptimeDays(
                sessions: sessions,
                endingAt: fixedEndingAt,
                calendar: utcCalendar
            ),
            3
        )
    }

    func testUptimeDaysBrokenStreak() {
        // 7/8 + 7/7 有，7/6 缺 → streak = 2
        let sessions = [
            session(date: "2026-07-08", hour: 9, status: .completed),
            session(date: "2026-07-07", hour: 9, status: .completed),
            session(date: "2026-07-05", hour: 9, status: .completed),
            session(date: "2026-07-04", hour: 9, status: .completed),
        ]
        XCTAssertEqual(
            HeatmapAggregator.uptimeDays(
                sessions: sessions,
                endingAt: fixedEndingAt,
                calendar: utcCalendar
            ),
            2
        )
    }

    func testUptimeDaysTodayEmptyStartsFromYesterday() {
        // 今天无记录，昨天起算：昨天有、前天无 → streak = 1
        let sessions = [
            session(date: "2026-07-07", hour: 9, status: .completed),
            session(date: "2026-07-05", hour: 9, status: .completed),
        ]
        XCTAssertEqual(
            HeatmapAggregator.uptimeDays(
                sessions: sessions,
                endingAt: fixedEndingAt,
                calendar: utcCalendar
            ),
            1
        )
    }

    func testUptimeDaysTodayEmptyYesterdayEmpty() {
        // 今天 + 昨天都空 → streak = 0
        let sessions = [
            session(date: "2026-07-06", hour: 9, status: .completed),
            session(date: "2026-07-05", hour: 9, status: .completed),
        ]
        XCTAssertEqual(
            HeatmapAggregator.uptimeDays(
                sessions: sessions,
                endingAt: fixedEndingAt,
                calendar: utcCalendar
            ),
            0
        )
    }

    func testUptimeDaysLongStreak() {
        // 7/8 往前 30 天连续 → 30
        var sessions: [FocusSession] = []
        for offset in 0..<30 {
            let date = formatOffsetDate(daysBeforeEnding: offset)
            sessions.append(session(date: date, hour: 9, status: .completed))
        }
        XCTAssertEqual(
            HeatmapAggregator.uptimeDays(
                sessions: sessions,
                endingAt: fixedEndingAt,
                calendar: utcCalendar
            ),
            30
        )
    }

    func testUptimeDaysMultipleCompletionsPerDayCountOnce() {
        // 同一天 5 个 completed 也只算 1 天
        var sessions: [FocusSession] = []
        for h in 8..<13 {
            sessions.append(session(date: "2026-07-08", hour: h, status: .completed))
        }
        XCTAssertEqual(
            HeatmapAggregator.uptimeDays(
                sessions: sessions,
                endingAt: fixedEndingAt,
                calendar: utcCalendar
            ),
            1
        )
    }

    // MARK: - yearTotal

    func testYearTotalCountsOnlyCompletedInYear() {
        let sessions: [FocusSession] = [
            // 2026 完成 3 个
            session(date: "2026-01-15", status: .completed),
            session(date: "2026-06-30", status: .completed),
            session(date: "2026-12-31", status: .completed),
            // 2025 完成 2 个
            session(date: "2025-03-01", status: .completed),
            session(date: "2025-12-31", status: .completed),
            // 2026 aborted/focusing 不计
            session(date: "2026-02-01", status: .aborted),
            session(date: "2026-03-01", status: .focusing),
        ]
        XCTAssertEqual(HeatmapAggregator.yearTotal(sessions: sessions, year: 2026), 3)
        XCTAssertEqual(HeatmapAggregator.yearTotal(sessions: sessions, year: 2025), 2)
        XCTAssertEqual(HeatmapAggregator.yearTotal(sessions: sessions, year: 2024), 0)
    }

    func testYearTotalCrossYearBoundary() {
        // 跨年：从 2025-12-28 到 2026-01-05 每天 1 个
        // 2025: 28,29,30,31 = 4
        // 2026: 1,2,3,4,5 = 5
        var sessions: [FocusSession] = []
        for day in 28...31 {
            sessions.append(session(date: "2025-12-\(day)", status: .completed))
        }
        for day in 1...5 {
            sessions.append(session(date: "2026-01-0\(day)", status: .completed))
        }
        XCTAssertEqual(HeatmapAggregator.yearTotal(sessions: sessions, year: 2025), 4)
        XCTAssertEqual(HeatmapAggregator.yearTotal(sessions: sessions, year: 2026), 5)
    }

    func testYearTotalEmpty() {
        XCTAssertEqual(HeatmapAggregator.yearTotal(sessions: [], year: 2026), 0)
    }

    // MARK: - dayDistribution

    func testDayDistributionAlwaysReturns24Buckets() {
        let distribution = HeatmapAggregator.dayDistribution(sessions: [], date: "2026-07-08")
        XCTAssertEqual(distribution.count, 24)
        for (i, bucket) in distribution.enumerated() {
            XCTAssertEqual(bucket.hour, i)
            XCTAssertEqual(bucket.completedCount, 0)
            XCTAssertEqual(bucket.abortedCount, 0)
        }
    }

    func testDayDistributionAggregatesCompletedAndAbortedPerHour() {
        let date = "2026-07-08"
        let sessions: [FocusSession] = [
            // hour 9: 2 completed + 1 aborted
            session(date: date, hour: 9, status: .completed),
            session(date: date, hour: 9, status: .completed),
            session(date: date, hour: 9, status: .aborted),
            // hour 14: 3 completed
            session(date: date, hour: 14, status: .completed),
            session(date: date, hour: 14, status: .completed),
            session(date: date, hour: 14, status: .completed),
            // hour 23: 1 aborted
            session(date: date, hour: 23, status: .aborted),
            // 不同日期的会话不进此分布
            session(date: "2026-07-07", hour: 9, status: .completed),
            // focusing 不计入
            session(date: date, hour: 10, status: .focusing),
        ]
        let distribution = HeatmapAggregator.dayDistribution(sessions: sessions, date: date)
        XCTAssertEqual(distribution[9].completedCount, 2)
        XCTAssertEqual(distribution[9].abortedCount, 1)
        XCTAssertEqual(distribution[14].completedCount, 3)
        XCTAssertEqual(distribution[14].abortedCount, 0)
        XCTAssertEqual(distribution[23].completedCount, 0)
        XCTAssertEqual(distribution[23].abortedCount, 1)
        XCTAssertEqual(distribution[10].completedCount, 0)
        XCTAssertEqual(distribution[10].abortedCount, 0)
        XCTAssertEqual(distribution[15].completedCount, 0)
    }

    func testDayDistributionIgnoresOutOfRangeHour() {
        // 即使构造出 startHour 越界也不应崩溃
        let bad = FocusSession(
            id: "focus_bad",
            createdAt: Date(),
            date: "2026-07-08",
            startHour: 25,
            startMinute: 0,
            durationMin: 1,
            status: .completed,
            quality: 0,
            fakeTokens: 0,
            fakeModel: "x",
            note: nil,
            provider: .a
        )
        let distribution = HeatmapAggregator.dayDistribution(sessions: [bad], date: "2026-07-08")
        XCTAssertEqual(distribution.count, 24)
        let totalCompleted = distribution.reduce(0) { $0 + $1.completedCount }
        XCTAssertEqual(totalCompleted, 0)
    }

    // MARK: - peakHour

    func testPeakHourReturnsHighestHour() {
        let buckets: [HourBucket] = (0..<24).map { h in
            HourBucket(hour: h, completedCount: h == 14 ? 4 : 1, abortedCount: 0)
        }
        let peak = HeatmapAggregator.peakHour(distribution: buckets)
        XCTAssertEqual(peak?.hour, 14)
        XCTAssertEqual(peak?.count, 4)
    }

    func testPeakHourAllZeroReturnsNil() {
        let buckets = (0..<24).map { HourBucket(hour: $0, completedCount: 0, abortedCount: 0) }
        XCTAssertNil(HeatmapAggregator.peakHour(distribution: buckets))
    }

    func testPeakHourEmptyReturnsNil() {
        XCTAssertNil(HeatmapAggregator.peakHour(distribution: []))
    }

    func testPeakHourIgnoresAbortedCount() {
        // aborted 不参与 peak 计算
        let buckets: [HourBucket] = (0..<24).map { h in
            HourBucket(hour: h, completedCount: 0, abortedCount: h == 9 ? 99 : 0)
        }
        XCTAssertNil(HeatmapAggregator.peakHour(distribution: buckets))
    }

    func testPeakHourTieBreakingReturnsEarliest() {
        let buckets: [HourBucket] = (0..<24).map { h in
            HourBucket(hour: h, completedCount: h == 10 || h == 18 ? 5 : 0, abortedCount: 0)
        }
        let peak = HeatmapAggregator.peakHour(distribution: buckets)
        XCTAssertEqual(peak?.hour, 10)
        XCTAssertEqual(peak?.count, 5)
    }

    // MARK: - monthLabels

    func testMonthLabelsCountIs52() {
        let labels = HeatmapAggregator.monthLabels(
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        XCTAssertEqual(labels.count, HeatmapAggregator.weeksPerYear)
        for weekIdx in 0..<HeatmapAggregator.weeksPerYear {
            XCTAssertNotNil(labels[weekIdx])
            let m = labels[weekIdx]!
            XCTAssertTrue((1...12).contains(m), "month must be 1-12, got \(m)")
        }
    }

    func testMonthLabelsFirstColumnIsJuly2025() {
        let labels = HeatmapAggregator.monthLabels(
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        XCTAssertEqual(labels[0], 7)  // 2025-07-07 是第一列周一
    }

    func testMonthLabelsShowYearTransition() {
        // 2026-01-01 是 Thursday；所在周周一 = 2025-12-29 → 月 = 12
        // 第一列往回数 51 周：从 2025-12-29 起算...
        // 实际上我们用 fixedEndingAt = 2026-07-08，第一列是 2025-07-07。
        // 这里验证：至少在某处会出现月份切换（labels 列表里相邻列月份不等）。
        let labels = HeatmapAggregator.monthLabels(
            endingAt: fixedEndingAt,
            calendar: utcCalendar
        )
        var transitions = 0
        var lastMonth = labels[0]
        for weekIdx in 1..<HeatmapAggregator.weeksPerYear {
            if labels[weekIdx] != lastMonth {
                transitions += 1
                lastMonth = labels[weekIdx]
            }
        }
        XCTAssertGreaterThan(transitions, 0, "expected at least one month transition in 52 weeks")
    }

    // MARK: - Helpers

    /// 把"距 endingAt 多少天"的偏移换算成 `YYYY-MM-DD` 字符串。
    /// 依赖 `utcCalendar`（已在 `setUp` 风格的字段里初始化），保证测试可重现。
    private func formatOffsetDate(daysBeforeEnding offset: Int) -> String {
        guard let d = utcCalendar.date(byAdding: .day, value: -offset, to: fixedEndingAt) else {
            return ""
        }
        return TomatoEngine.dateKey(now: d, calendar: utcCalendar)
    }
}
