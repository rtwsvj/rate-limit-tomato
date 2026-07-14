import SwiftUI
import TomatoCore

/// 用量看板组合视图（SPEC §12）。上半年度热力图 + 点击某天展开钻取层。
/// 内部调用 `HeatmapAggregator`，对外只暴露 `sessions`。
public struct UsageDashboardView: View {
    public let sessions: [FocusSession]
    public let endingAt: Date
    public let onRefresh: () -> Void

    @State private var selectedDay: String?
    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltPrimaryLocale) private var locale

    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = HeatmapAggregator.firstWeekday
        return cal
    }()

    public init(
        sessions: [FocusSession],
        endingAt: Date = Date(),
        onRefresh: @escaping () -> Void = {}
    ) {
        self.sessions = sessions
        self.endingAt = endingAt
        self.onRefresh = onRefresh
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleRow
            if sessions.isEmpty {
                emptyState
            } else {
                yearSection
                if let selectedDay, !selectedDay.isEmpty {
                    daySection(date: selectedDay)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg)
    }

    // MARK: - Title

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 12) {
            BilingualText("nav.usage", primaryFont: theme.display(20), alignment: .leading)
            Spacer()
            RefreshButton(action: onRefresh)
            Text(L10n.t("usage.last_24h", locale: locale))
                .font(theme.monoTag)
                .foregroundColor(theme.textTertiary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            BilingualText(
                "usage.empty",
                primaryFont: theme.body13,
                primaryColor: theme.textPrimary
            )
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: - Year section

    private var yearSection: some View {
        let cells = HeatmapAggregator.yearGrid(
            sessions: sessions,
            endingAt: endingAt,
            calendar: calendar
        )
        let monthLabels = HeatmapAggregator.monthLabels(
            endingAt: endingAt,
            calendar: calendar
        )
        let uptime = HeatmapAggregator.uptimeDays(
            sessions: sessions,
            endingAt: endingAt,
            calendar: calendar
        )
        let total = HeatmapAggregator.yearTotal(
            sessions: sessions,
            year: calendar.component(.year, from: endingAt)
        )
        return HeatmapYearView(
            cells: cells,
            monthLabels: monthLabels,
            uptimeDays: uptime,
            yearTotal: total,
            endingAt: endingAt,
            onSelectDay: { date in
                if selectedDay == date {
                    selectedDay = nil
                } else {
                    selectedDay = date
                }
            }
        )
    }

    // MARK: - Day section (drill-down)

    private func daySection(date: String) -> some View {
        let distribution = HeatmapAggregator.dayDistribution(
            sessions: sessions,
            date: date
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button(action: { selectedDay = nil }) {
                    Text("×")
                        .font(theme.title)
                        .foregroundColor(theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .help(L10n.t("usage.close_drilldown", locale: locale))
                .accessibilityLabel(L10n.t("usage.close_drilldown", locale: locale))
            }
            HeatmapDayView(date: date, distribution: distribution)
        }
    }
}

private struct RefreshButton: View {
    let action: () -> Void

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltPrimaryLocale) private var locale
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("⟳ \(L10n.t("action.refresh", locale: locale))")
                .font(theme.monoBody)
                .foregroundColor(theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous))
                .brightness(hovering ? -0.06 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(L10n.t("usage.refresh_hint", locale: locale))
        .accessibilityLabel(L10n.t("action.refresh", locale: locale))
        .accessibilityHint(L10n.t("usage.refresh_hint", locale: locale))
    }
}
