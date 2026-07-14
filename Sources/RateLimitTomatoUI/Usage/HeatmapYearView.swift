import SwiftUI
import TomatoCore

/// 年度活动网格式热力图。
///
/// 纯展示组件，零业务计算：调用方须先把 `[FocusSession]` 喂给
/// `HeatmapAggregator.yearGrid` / `monthLabels` / `uptimeDays` / `yearTotal`。
public struct HeatmapYearView: View {
    public let cells: [[DayCell]]
    public let monthLabels: [Int: Int]
    public let uptimeDays: Int
    public let yearTotal: Int
    public let endingAt: Date
    public let onSelectDay: (String) -> Void

    @Environment(\.tomatoTheme) private var theme

    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 3

    public init(
        cells: [[DayCell]],
        monthLabels: [Int: Int],
        uptimeDays: Int,
        yearTotal: Int,
        endingAt: Date,
        onSelectDay: @escaping (String) -> Void
    ) {
        self.cells = cells
        self.monthLabels = monthLabels
        self.uptimeDays = uptimeDays
        self.yearTotal = yearTotal
        self.endingAt = endingAt
        self.onSelectDay = onSelectDay
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statsRow
            gridScrollView
        }
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(uptimeDays)", key: "stats.uptime",
                     args: ["days": String(uptimeDays)])
            statCard(value: "\(yearTotal)", key: "stats.year_total",
                     args: ["count": String(yearTotal)])
        }
    }

    private func statCard(value: String, key: String, args: [String: String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(theme.monoBig)
                .foregroundColor(theme.accent)
            BilingualText(
                key,
                primaryFont: theme.caption,
                primaryColor: theme.textSecondary,
                alignment: .leading,
                args: args
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
    }

    // MARK: - Grid (horizontally scrollable)

    private var gridScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HeatmapGrid(cells: cells, monthLabels: monthLabels, onSelectDay: onSelectDay)
        }
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

}

/// 网格本体（独立 View：环境在自身 body 解析，供 ScrollView 与快照测试两处使用——
/// 直接从父 struct 属性提取子树会让 @Environment 落到默认值）。
struct HeatmapGrid: View {
    let cells: [[DayCell]]
    let monthLabels: [Int: Int]
    let onSelectDay: (String) -> Void

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltPrimaryLocale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredDate: String?

    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            monthLabelRow
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(Array(cells.enumerated()), id: \.offset) { (weekIdx, week) in
                    VStack(spacing: cellSpacing) {
                        ForEach(Array(week.enumerated()), id: \.offset) { (_, cell) in
                            dayCellView(cell)
                        }
                    }
                }
            }
        }
        .padding(16)
    }

    private var monthLabelRow: some View {
        HStack(alignment: .center, spacing: cellSpacing) {
            Spacer().frame(width: 0)
            ForEach(Array(cells.enumerated()), id: \.offset) { (weekIdx, _) in
                Text(monthLabel(for: weekIdx))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(theme.textTertiary)
                    .fixedSize() // 11px 列宽下不许竖排换行，向右溢出即可
                    .frame(width: cellSize, alignment: .leading)
                    .accessibilityHidden(true)
            }
        }
    }

/// 仅当月份相比前一列变化时画标签。
    private func monthLabel(for weekIdx: Int) -> String {
        let current = monthLabels[weekIdx] ?? 0
        if weekIdx == 0 { return shortMonth(current) }
        let previous = monthLabels[weekIdx - 1] ?? 0
        return current == previous ? "" : shortMonth(current)
    }

    private func shortMonth(_ m: Int) -> String {
        // 固定英文缩写避免中文 locale 的“10月”在窄列中竖排。
        guard (1...12).contains(m) else { return "" }
        return L10n.t("usage.month_\(m)", locale: locale)
    }

    private func dayCellView(_ cell: DayCell) -> some View {
        let color = HeatmapYearView.colorForLevel(cell.level, theme: theme)
        let tooltip = L10n.t(
            "usage.day_tooltip",
            locale: locale,
            args: ["count": "\(cell.completedCount)", "date": cell.date]
        )
        return Button(action: { onSelectDay(cell.date) }) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: cellSize, height: cellSize)
                .scaleEffect(!reduceMotion && hoveredDate == cell.date ? 1.15 : 1.0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveredDate)
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredDate = hovering ? cell.date : nil }
        .help(tooltip)
        .accessibilityLabel(tooltip)
        .accessibilityHint(L10n.t("usage.open_day_hint", locale: locale))
        .accessibilityHidden(cell.completedCount == 0)
    }
}

extension HeatmapYearView {
    /// 等级色阶：Provider A 用 SPEC §12.1 固定五档；B/C 按主题 accent
    /// 的透明度阶梯生成（UI-SPEC §1.4 令牌全换）。
    public static func colorForLevel(_ level: Int, theme: TomatoTheme) -> Color {
        if !theme.usesHeatmapAccentScale {
            switch level {
            case 0: return Color(hex: 0xEBEAE3)
            case 1: return Color(hex: 0xF0D9C8)
            case 2: return Color(hex: 0xE5B89A)
            case 3: return Color(hex: 0xD97757)
            default: return Color(hex: 0xC96442)
            }
        }
        switch level {
        case 0: return theme.border
        case 1: return theme.accent.opacity(0.25)
        case 2: return theme.accent.opacity(0.5)
        case 3: return theme.accent.opacity(0.75)
        default: return theme.accent
        }
    }
}

// Color(hex:) 定义在 Theme/Theme.swift
