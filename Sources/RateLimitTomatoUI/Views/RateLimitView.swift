import SwiftUI
import TomatoCore

/// RATE_LIMITED（UI-SPEC §3.5）——梗高潮。米色纸面，温柔地拒绝。
struct RateLimitView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 8)

            Text(L10n.t(theme.rateLimitHeadlineKey, locale: vm.settings.language))
                .font(theme.display())
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 8)
            subHeadline
            Spacer().frame(height: 4)
            if !vm.settings.isEnglish {
                Text(L10n.t("status.usage_limit_reached", locale: vm.settings.language,
                            args: ["time": vm.resetTimeDisplay()]))
                    .font(theme.caption)
                    .foregroundColor(theme.textSecondary)
            }

            Spacer().frame(height: 20)
            CapsuleProgress(fraction: vm.cooldownFraction(), height: 4, reversed: true, solidDeep: true)
                .frame(width: 200)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("status.rate_limited", locale: vm.settings.language))
                .accessibilityValue("\(Int((vm.cooldownFraction() * 100).rounded()))%")

            if vm.settings.showFakeHeaders {
                Spacer().frame(height: 20)
                CollapsibleCodeBlock(
                    summary: L10n.t("parody.http_429", locale: vm.settings.language),
                    lines: FakeHeaderGenerator.rateLimited(
                        limit: vm.maxPerDay,
                        remaining: 0,
                        resetAt: vm.engine.cooldownResetAt,
                        retryAfter: vm.cooldownRemaining
                    ).components(separatedBy: "\n")
                )
            }

            Spacer().frame(height: 20)
            TomatoButton(
                variant: .primary,
                title: "\(L10n.t("action.upgrade", locale: AppLocale.en.rawValue)) →",
                height: 44
            ) {
                vm.showUpgradeSheet = true
            }

            Spacer().frame(height: 8)
            TomatoButton(
                variant: .text,
                title: LocalizedPair("action.skip_cooldown", locale: vm.settings.language).inline
            ) {
                vm.skipCooldown()
            }

            Spacer().frame(height: 16)
            Text(L10n.t("status.reset_at_midnight", locale: vm.settings.language))
                .font(theme.monoTag)
                .foregroundColor(theme.textTertiary)
        }
        .onAppear {
            if vm.consumeUpgradeNudge() { vm.showUpgradeSheet = true }
        }
    }

    /// "your limit will reset at 14:32"，时间用 mono semibold accentDeep。
    private var subHeadline: some View {
        var time = AttributedString(vm.resetTimeDisplay())
        time.font = .system(size: 17, weight: .semibold, design: .monospaced)
        time.foregroundColor = theme.accentDeep
        var prefix = AttributedString(L10n.t(
            "status.reset_time_prefix",
            locale: vm.settings.language
        ))
        prefix.foregroundColor = theme.textPrimary
        return Text(prefix + time).font(theme.displaySub)
    }
}
