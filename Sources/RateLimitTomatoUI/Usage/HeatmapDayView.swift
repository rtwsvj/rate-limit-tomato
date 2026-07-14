import SwiftUI
import TomatoCore

/// 监控面板式小时钻取层。
///
/// 展示某一天 24 小时的小时分布。`completed` 用主题强调色绘制主柱，
/// `aborted` 以浅灰色堆叠在完成柱顶部单独显示（SPEC §12.4）。纯展示组件，不做业务计算。
public struct HeatmapDayView: View {
    public let date: String
    public let distribution: [HourBucket]

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltPrimaryLocale) private var locale

    public init(date: String, distribution: [HourBucket]) {
        self.date = date
        self.distribution = distribution
    }

    private let barWidth: CGFloat = 16
    private let barSpacing: CGFloat = 6

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow
            chartArea
            xAxisRow
            legendRow
        }
        .padding(16)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    // MARK: - Title + Peak

    private var titleRow: some View {
        let peak = HeatmapAggregator.peakHour(distribution: distribution)
        return HStack(alignment: .firstTextBaseline) {
            Text(date)
                .font(theme.monoBody)
                .foregroundColor(theme.textSecondary)
            Spacer()
            if let peak {
                let next = (peak.hour + 1) % 24
                Text(L10n.t(
                    "usage.peak",
                    locale: locale,
                    args: [
                        "start": String(format: "%02d", peak.hour),
                        "end": String(format: "%02d", next),
                        "count": "\(peak.count)",
                    ]
                ))
                    .font(theme.monoBody)
                    .foregroundColor(theme.textPrimary)
            } else {
                Text(L10n.t("usage.peak_empty", locale: locale))
                    .font(theme.monoBody)
                    .foregroundColor(theme.textSecondary)
            }
        }
    }

    // MARK: - Chart

    private var chartArea: some View {
        let maxValue = max(distribution.map(\.totalCount).max() ?? 0, 1)
        return HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(distribution, id: \.hour) { bucket in
                bar(for: bucket, maxValue: maxValue)
            }
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func bar(for bucket: HourBucket, maxValue: Int) -> some View {
        let total = bucket.totalCount
        let completedHeight = CGFloat(bucket.completedCount) / CGFloat(maxValue) * 100
        let abortedHeight = CGFloat(bucket.abortedCount) / CGFloat(maxValue) * 100
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(theme.border.opacity(total == 0 ? 0.45 : 0))
                .frame(width: barWidth, height: 2)
            VStack(spacing: 0) {
                if bucket.abortedCount > 0 {
                    Rectangle()
                        .fill(theme.border)
                        .frame(height: abortedHeight)
                }
                if bucket.completedCount > 0 {
                    Rectangle()
                        .fill(theme.accent)
                        .frame(height: completedHeight)
                }
            }
            .frame(width: barWidth)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
        }
        .frame(width: barWidth, height: 120, alignment: .bottom)
        .help(tooltip(for: bucket))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tooltip(for: bucket))
        .accessibilityHidden(total == 0)
    }

    private func tooltip(for bucket: HourBucket) -> String {
        if bucket.totalCount == 0 {
            return L10n.t(
                "usage.hour_empty",
                locale: locale,
                args: ["hour": String(format: "%02d", bucket.hour)]
            )
        }
        return L10n.t(
            "usage.hour_counts",
            locale: locale,
            args: [
                "hour": String(format: "%02d", bucket.hour),
                "completed": "\(bucket.completedCount)",
                "aborted": "\(bucket.abortedCount)",
            ]
        )
    }

    // MARK: - X axis

    private var xAxisRow: some View {
        HStack(spacing: barSpacing) {
            ForEach(distribution.indices, id: \.self) { idx in
                Text(idx % 6 == 0 ? String(format: "%02d", idx) : "·")
                    .font(theme.monoTag)
                    .foregroundColor(theme.textTertiary)
                    .frame(width: barWidth)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 10) {
            legendSwatch(
                color: theme.accent,
                label: L10n.t("unit.fast_requests", locale: locale)
            )
            legendSwatch(
                color: theme.border,
                label: L10n.t("unit.aborted_requests", locale: locale)
            )
            Spacer()
        }
        .font(theme.monoTag)
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Text("■")
                .foregroundColor(color)
            Text(label)
                .foregroundColor(theme.textTertiary)
        }
    }
}
