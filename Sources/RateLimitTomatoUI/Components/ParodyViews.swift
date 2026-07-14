import SwiftUI
import TomatoCore

// 专注中的两个戏仿组件（UI-SPEC §3.3）

// MARK: - StreamingEcho

/// 流式专注回显（SPEC §9.4.3）：note 以打字机效果逐字蹦出。
/// 节奏：全文在 min(len/12字每秒, 30s) 内播完，步数 ≤120 防高频刷新。
struct StreamingEcho: View {
    let text: String
    var charsPerSecond: Double = 12

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltPrimaryLocale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed = ""
    @State private var task: Task<Void, Never>? = nil
    @State private var pulsing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("parody.streaming_ellipsis", locale: locale))
                .font(theme.monoTag)
                .foregroundColor(theme.accent)
                .opacity(!reduceMotion && pulsing ? 0.45 : 1)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: pulsing
                )
            Text(displayed.isEmpty ? " " : displayed)
                .font(theme.body13)
                .foregroundColor(theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(4) // 固定高面板内不许撑爆（长 note 截断展示）
                .truncationMode(.tail)
        }
        .padding(12)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
            .stroke(theme.border, lineWidth: 1))
        .onAppear { pulsing = true; restart() }
        .onChange(of: text) { _, _ in restart() }
        .onDisappear { task?.cancel() }
    }

    private func restart() {
        task?.cancel()
        displayed = ""
        guard !text.isEmpty else { return }
        if reduceMotion {
            displayed = text
            return
        }
        let totalSeconds = min(Double(text.count) / charsPerSecond, 30.0)
        let steps = max(1, min(text.count, 120))
        let chunk = max(1, Int((Double(text.count) / Double(steps)).rounded(.up)))
        let sleepNanos = UInt64(totalSeconds / Double(steps) * 1_000_000_000)
        task = Task { @MainActor in
            var shown = 0
            while shown < text.count {
                if Task.isCancelled { return }
                try? await Task.sleep(nanoseconds: sleepNanos)
                shown = min(text.count, shown + chunk)
                displayed = String(text.prefix(shown))
            }
        }
    }
}

// MARK: - FakeLogStreamView

/// 假 log 流：固定高 88 的码块，新行随 elapsed 推进从底部出现，只显示尾部若干行。
struct FakeLogStreamView: View {
    let generator: FakeLogStreamGenerator
    let elapsed: TimeInterval

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltPrimaryLocale) private var locale

    private var visibleLines: [String] {
        Array(generator.lines(elapsed: elapsed).suffix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.t("parody.logs_tag", locale: locale))
                .font(theme.monoTag)
                .foregroundColor(theme.textTertiary)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(visibleLines.enumerated()), id: \.offset) { _, line in
                        Text(line).font(theme.monoBody).foregroundColor(theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 60)
            // 顶部 12px 渐隐（UI-SPEC §3.3）
            .mask(
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .black, location: 0.18)],
                               startPoint: .top, endPoint: .bottom)
            )
        }
        .padding(12)
        .frame(height: 88)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.codeBlock)
        .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
    }
}
