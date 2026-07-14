import SwiftUI
import TomatoCore

/// FOCUSING（UI-SPEC §3.3）：滚动窗口计时 + 进度条 + 回显 + 假 log + 中止。
struct FocusingView: View {
    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme

    @State private var logGenerator: FakeLogStreamGenerator?

    var body: some View {
        let pair = vm.focusWindowPair()

        VStack(spacing: 0) {
            Spacer().frame(height: 4)

            // 滚动窗口计时：elapsed 大号 mono + 总量小号，基线对齐
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(pair.elapsed)
                    .font(theme.monoBig)
                    .foregroundColor(theme.textPrimary)
                Text(pair.total)
                    .font(theme.monoBody)
                    .foregroundColor(theme.textSecondary)
            }
            Spacer().frame(height: 2)
            Text("· \(L10n.t("unit.fast_requests", locale: vm.settings.language))")
                .font(theme.monoTag)
                .foregroundColor(theme.textTertiary)

            Spacer().frame(height: 12)
            CapsuleProgress(fraction: vm.focusFraction())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.t("status.streaming", locale: vm.settings.language))
                .accessibilityValue("\(Int((vm.focusFraction() * 100).rounded()))%")

            if let note = vm.sessionNote, !note.isEmpty {
                Spacer().frame(height: 16)
                StreamingEcho(text: note)
            }

            if vm.settings.showFakeLogs, let logGenerator {
                Spacer().frame(height: 12)
                FakeLogStreamView(
                    generator: logGenerator,
                    elapsed: vm.focusElapsed
                )
            }

            Spacer().frame(height: 16)
            TomatoButton(
                variant: .ghost,
                title: LocalizedPair("action.abort", locale: vm.settings.language).inline
            ) {
                vm.abortRequest()
            }
        }
        .onAppear { rebuildLogGenerator() }
        .onChange(of: vm.currentSession?.id) { _, _ in rebuildLogGenerator() }
    }

    private func rebuildLogGenerator() {
        let seed = UInt64((vm.currentSession?.id ?? "focus_524c5421").dropFirst(6), radix: 16) ?? 0x524C54
        logGenerator = FakeLogStreamGenerator(
            seed: seed,
            startDate: vm.currentSession?.createdAt ?? Date()
        )
    }
}
