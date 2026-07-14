import SwiftUI
import TomatoCore

// 两个红线 sheet（SPEC §13，文案一字不动；视觉按 UI-SPEC §4.6）。

// MARK: - UpgradeSheet

/// 戏仿升级页。⚠️ 红线：无支付、无跳转、无真实厂商名；免责小字永久可见。
struct UpgradeSheet: View {
    var onDismiss: () -> Void = {}
    @Environment(\.tomatoTheme) private var theme
    @Environment(\.rltPrimaryLocale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showComedy = false
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showComedy {
                comedyFeedback
            } else {
                pricing
            }
            Spacer().frame(height: 16)
            // §13.4 永久免责小字（不可隐藏）；法务文案固定中英混排整句，语言无关
            Text(L10n.t("error.parody_disclaimer", locale: locale))
                .font(theme.caption)
                .foregroundColor(theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 320)
        .background(theme.bg)
        .onAppear { titleFocused = true }
    }

    private var pricing: some View {
        VStack(spacing: 0) {
            Text(L("upgrade.plan"))
                .font(theme.display(18))
                .foregroundColor(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Spacer().frame(height: 16)
            VStack(alignment: .leading, spacing: 8) {
                benefit(L("upgrade.benefit_unlimited"))
                benefit(L("upgrade.benefit_priority"))
                benefit(L("upgrade.benefit_deep_work"))
                benefit(L("upgrade.benefit_context"))
            }
            Spacer().frame(height: 20)
            TomatoButton(variant: .primary, title: L("action.start_trial")) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    showComedy = true
                }
            }
            Spacer().frame(height: 8)
            TomatoButton(variant: .text, title: L("action.maybe_later")) { onDismiss() }
        }
    }

    /// §13.3 喜剧反馈：点"购买"不进任何支付流程。
    private var comedyFeedback: some View {
        VStack(spacing: 0) {
            Text(L("upgrade.thanks"))
                .font(theme.display(18))
                .foregroundColor(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer().frame(height: 12)
            Text(L("upgrade.comedy_primary"))
                .font(theme.body13)
                .foregroundColor(theme.textPrimary)
            Spacer().frame(height: 4)
            Text(L("upgrade.comedy_secondary"))
                .font(theme.caption)
                .foregroundColor(theme.textSecondary)
            Spacer().frame(height: 20)
            TomatoButton(variant: .primary, title: L("action.got_it")) { onDismiss() }
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("✓").font(theme.body13).foregroundColor(theme.success)
            Text(text).font(theme.body13).foregroundColor(theme.textPrimary)
        }
    }

    private func L(_ key: String) -> String {
        L10n.t(key, locale: locale)
    }
}

// MARK: - DisclaimerSheet

/// 首次启动戏仿免责确认（SPEC §13.5）。确认前不可用。
struct DisclaimerSheet: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.t("disclaimer.title", locale: vm.settings.language))
                .font(theme.display(18))
                .foregroundColor(theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused)
            Spacer().frame(height: 12)
            Text(L10n.t("disclaimer.summary", locale: vm.settings.language))
                .font(theme.body13)
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)
            Spacer().frame(height: 12)
            VStack(alignment: .leading, spacing: 6) {
                bullet(L10n.t("disclaimer.virtual", locale: vm.settings.language))
                bullet(L10n.t("disclaimer.no_charge", locale: vm.settings.language))
                bullet(L10n.t("disclaimer.local_only", locale: vm.settings.language))
            }
            Spacer().frame(height: 20)
            TomatoButton(
                variant: .primary,
                title: LocalizedPair("action.disclaimer_ack", locale: vm.settings.language).inline
            ) {
                vm.acknowledgeDisclaimer()
            }
            Spacer().frame(height: 12)
            Text(L10n.t("error.parody_disclaimer", locale: vm.settings.language))
                .font(theme.caption)
                .foregroundColor(theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 320)
        .background(theme.bg)
        .onAppear { titleFocused = true }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").font(theme.body13).foregroundColor(theme.textSecondary)
            Text(text).font(theme.caption).foregroundColor(theme.textSecondary)
        }
    }
}
