import SwiftUI
import TomatoCore

// 五个次级状态视图（UI-SPEC §3.2 / §3.4 / §3.6-§3.8）。
// 基础结构由设计方（Fable）落定；R3 按规格补足细节动效。

// MARK: - SENDING（§3.2）

struct SendingView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showResponseLine = false
    @State private var flashRetry = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)
            ProgressView()
                .controlSize(.small)
                .tint(theme.accent)
                .frame(width: 20, height: 20)
            Spacer().frame(height: 12)
            BilingualText("status.sending")
            Spacer().frame(height: 16)
            CodeBlock(lines: showResponseLine
                ? [focusEndpoint, okResponse]
                : [focusEndpoint])
            if flashRetry {
                Spacer().frame(height: 8)
                Text(L10n.t("status.retrying", locale: vm.settings.language))
                    .font(theme.monoBody)
                    .foregroundColor(theme.accentDeep)
                    .transition(.opacity)
            }
            Spacer().frame(height: 8)
        }
        .onAppear {
            if reduceMotion {
                showResponseLine = true
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeOut(duration: 0.22)) { showResponseLine = true }
            }
            // 假闪现彩蛋（SPEC §9.2.3）：30% 概率，300ms 后消失
            if Int.random(in: 0..<100) < 30 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { flashRetry = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation { flashRetry = false }
                    }
                }
            }
        }
    }

    private var focusEndpoint: String {
        L10n.t("parody.endpoint_focus", locale: vm.settings.language)
    }

    private var okResponse: String {
        L10n.t("parody.response_ok", locale: vm.settings.language)
    }
}

// MARK: - COMPLETED（§3.4）

struct CompletedView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 4)
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28, weight: .medium))
                .foregroundColor(theme.success)
                .accessibilityHidden(true)
            Spacer().frame(height: 12)
            // 刻意设计：完成卡片标题是英雄原声（SPEC §6.2 完成卡原文），不随语言翻译；
            // 中文释义走副行。与限流页 headline 同一原则（UI-SPEC §1.2 双语规则）。
            BilingualText(
                "status.completed_in",
                primaryFont: theme.display(20),
                args: ["min": "\(vm.settings.focusDurationMin)"]
            )
            Spacer().frame(height: 16)
            CodeBlock(
                tag: L10n.t("parody.json_tag", locale: vm.settings.language),
                lines: jsonLines
            )
            Spacer().frame(height: 8)
            Text(L10n.t("parody.cost_compute", locale: vm.settings.language))
                .font(theme.monoTag)
                .foregroundColor(theme.textTertiary)
        }
    }

    private var jsonLines: [String] {
        guard let s = vm.currentSession else { return ["{}"] }
        let boundedDurationMin = min(
            max(s.durationMin, TomatoStore.durationRange.lowerBound),
            TomatoStore.durationRange.upperBound
        )
        let durationProduct = boundedDurationMin.multipliedReportingOverflow(by: 60_000)
        return FakeJsonGenerator.completed(
            id: s.id,
            createdAt: s.createdAt,
            durationMs: durationProduct.overflow ? Int.max : durationProduct.partialValue,
            tokensUsed: s.fakeTokens
        )
        .components(separatedBy: "\n")
    }
}

// MARK: - ABORTED（§3.6）

struct AbortedView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 4)
            Text(L10n.t("parody.status_timeout_code", locale: vm.settings.language))
                .font(.system(size: 20, design: .monospaced))
                .foregroundColor(theme.textTertiary)
            Spacer().frame(height: 8)
            Text(L10n.t("status.timeout", locale: AppLocale.en.rawValue))
                .font(theme.display(20))
                .foregroundColor(theme.textPrimary)
            Spacer().frame(height: 2)
            BilingualText("status.aborted")
            Spacer().frame(height: 20)
            HStack(spacing: 12) {
                TomatoButton(
                    variant: .primary,
                    title: LocalizedPair("action.start_cooldown", locale: vm.settings.language).title,
                    subtitle: LocalizedPair("action.start_cooldown", locale: vm.settings.language).subtitle
                ) { vm.startCooldown() }
                TomatoButton(
                    variant: .ghost,
                    title: LocalizedPair("action.skip_cooldown", locale: vm.settings.language).title,
                    height: 44
                ) { vm.skipCooldown() }
            }
        }
    }
}

// MARK: - TEAPOT（§3.7）

struct TeapotView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 4)
            Text("🫖").font(.system(size: 40))
            Spacer().frame(height: 12)
            Text(L10n.t("status.teapot_headline", locale: vm.settings.language))
                .font(theme.display())
                .foregroundColor(theme.textPrimary)
            Spacer().frame(height: 4)
            Text(L10n.t("status.teapot", locale: vm.settings.language))
                .font(theme.caption)
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Spacer().frame(height: 20)
            TomatoButton(
                variant: .primary,
                title: LocalizedPair("action.teapot_ack", locale: vm.settings.language).title,
                subtitle: LocalizedPair("action.teapot_ack", locale: vm.settings.language).subtitle
            ) { vm.acknowledgeTeapot() }
        }
    }
}

// MARK: - RESET（§3.8）

struct ResetView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltShowSecondary) private var showSecondary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)
            Text(L10n.t("status.reset_headline", locale: vm.settings.language))
                .font(theme.display(20))
                .foregroundColor(theme.textPrimary)
            Spacer().frame(height: 4)
            resetCaption
            Spacer().frame(height: 12)
            quotaLine
                .foregroundColor(theme.textPrimary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: vm.remaining)
            Spacer().frame(height: 8)
        }
    }

    private var resetCaption: some View {
        BilingualText("quota.window_reset")
    }

    private var quotaLine: Text {
        Text(quotaAttributed(remaining: vm.remaining, max: vm.maxPerDay,
                             locale: vm.settings.language,
                             font: .system(size: 13, weight: .semibold, design: .monospaced)))
            .font(theme.body13)
    }
}
