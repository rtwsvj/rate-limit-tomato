import SwiftUI
import TomatoCore

/// IDLE（UI-SPEC §3.1）。503 变体在额度耗尽时切换。
struct IdleView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme
    @State private var noteDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 4)

            if vm.isQuotaExhausted {
                Text(L10n.t("status.service_unavailable_title", locale: vm.settings.language))
                    .font(theme.display())
                    .foregroundColor(theme.textPrimary)
                Spacer().frame(height: 2)
                Text(L10n.t("status.service_unavailable", locale: vm.settings.language))
                    .font(theme.caption)
                    .foregroundColor(theme.textSecondary)
            } else {
                BilingualText("status.ready", primaryFont: theme.display())
            }

            Spacer().frame(height: 20)

            if !vm.isQuotaExhausted {
                TextField(L10n.t("idle.note_placeholder", locale: vm.settings.language), text: $noteDraft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(theme.body13)
                    .foregroundColor(theme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .padding(10)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: theme.buttonRadius, style: .continuous)
                        .stroke(theme.border, lineWidth: 1))
                Spacer().frame(height: 16)
            }

            TomatoButton(
                variant: .primary,
                title: sendPair.title,
                subtitle: sendPair.subtitle,
                height: 48,
                disabled: vm.isQuotaExhausted
            ) {
                vm.pendingNote = noteDraft
                vm.sendRequest()
                noteDraft = ""
            }

            Spacer().frame(height: 12)

            quotaLine
            Spacer().frame(height: 6)
            QuotaDots(remaining: vm.remaining, max: vm.maxPerDay)

            Spacer().frame(height: 16)
            Text(L10n.t("parody.endpoint_focus", locale: vm.settings.language))
                .font(theme.monoTag)
                .foregroundColor(theme.textTertiary)
        }
    }

    private var sendPair: LocalizedPair {
        LocalizedPair("action.send_request", locale: vm.settings.language)
    }

    /// 额度行：数字部分 mono semibold（UI-SPEC §3.1）；主行随语言，副行英文原声。
    private var quotaLine: some View {
        let pair = LocalizedPair("quota.remaining", locale: vm.settings.language,
                                 args: ["remaining": "\(vm.remaining)", "max": "\(vm.maxPerDay)"])
        return VStack(spacing: 2) {
            Text(quotaAttributed(remaining: vm.remaining, max: vm.maxPerDay,
                                 locale: vm.settings.language,
                                 font: .system(size: 13, weight: .semibold, design: .monospaced)))
                .font(theme.body13)
                .foregroundColor(theme.textPrimary)
            if let s = pair.subtitle {
                Text(s)
                    .font(theme.caption)
                    .foregroundColor(theme.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pair.title)
    }

}
