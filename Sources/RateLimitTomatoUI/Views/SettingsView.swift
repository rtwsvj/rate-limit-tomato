import KeyboardShortcuts
import LaunchAtLogin
import SwiftUI
import TomatoCore

/// 设置窗口（功能完整基础版；R3 按 UI-SPEC §4.5 做分组卡视觉精修）。
public struct SettingsView: View {
    public init() {}

    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            group(L("settings.section_session")) {
                stepperRow(L("settings.focus_duration"), value: vm.settings.focusDurationMin, range: AppSettings.focusInteractionRange, unit: L("unit.minute_short")) { v in
                    vm.applySettings { $0.focusDurationMin = v }
                }
                stepperRow(L("settings.cooldown_duration"), value: vm.settings.cooldownDurationMin, range: AppSettings.cooldownInteractionRange, unit: L("unit.minute_short")) { v in
                    vm.applySettings { $0.cooldownDurationMin = v }
                }
                stepperRow(L("settings.daily_quota"), value: vm.settings.maxPerDay, range: AppSettings.maxPerDayInteractionRange, unit: L("unit.request_short"), showsDivider: false) { v in
                    vm.applySettings { $0.maxPerDay = v }
                }
            }
            .disabled(!vm.settings.parodyDisclaimerAck || vm.phase != .idle)
            Group {
                group(L("settings.section_general")) {
                    settingsRow(L("settings.hotkey")) {
                        KeyboardShortcuts.Recorder(for: .sendOrAbort)
                            .controlSize(.small)
                    }
                    if Bundle.main.bundlePath.hasSuffix(".app") {
                        // 仅打包形态显示（SMAppService 需要真 .app；dev/测试环境隐藏）
                        settingsRow(L("settings.launch_at_login"), showsDivider: false) {
                            LaunchAtLogin.Toggle { EmptyView() }
                                .toggleStyle(.switch)
                                .tint(theme.accent)
                                .controlSize(.small)
                                .labelsHidden()
                                .accessibilityLabel(L("settings.launch_at_login"))
                        }
                    }
                }
                group(L("settings.section_appearance")) {
                    settingsRow(L("settings.provider")) {
                        ThemedSegment(
                            options: [("A", Provider.a), ("B", Provider.b), ("C", Provider.c)],
                            selection: Binding(
                                get: { vm.settings.provider },
                                set: { p in vm.applySettings { $0.provider = p } }
                            )
                        )
                    }
                    settingsRow(L("settings.language"), showsDivider: false) {
                        ThemedSegment(
                            options: [(L("settings.language_zh_cn"), AppLocale.zhCN.rawValue),
                                      (L("settings.language_en"), AppLocale.en.rawValue)],
                            selection: Binding(
                                get: { vm.settings.language },
                                set: { updateLanguage($0) }
                            )
                        )
                    }
                }
                group(L("settings.section_parody")) {
                    toggleRow(L("settings.fake_logs"), isOn: vm.settings.showFakeLogs) { v in
                        vm.applySettings { $0.showFakeLogs = v }
                    }
                    toggleRow(L("settings.fake_headers"), isOn: vm.settings.showFakeHeaders) { v in
                        vm.applySettings { $0.showFakeHeaders = v }
                    }
                    toggleRow(L("settings.sound"), isOn: vm.settings.soundEnabled, showsDivider: false) { v in
                        vm.applySettings { $0.soundEnabled = v }
                    }
                }
            }
            .disabled(!vm.settings.parodyDisclaimerAck)
            Spacer()
            VStack(alignment: .leading, spacing: 2) {
                BilingualText("settings.telemetry_disabled", alignment: .leading)
                // 内存态或读写失败时的小字警示（仅降级显示）。
                if vm.persistenceDegraded {
                    BilingualText(
                        "settings.storage_unavailable",
                        primaryColor: theme.accentDeep,
                        alignment: .leading
                    )
                }
                Text(L("settings.local_only", args: ["version": appVersion]))
                    .font(theme.monoTag).foregroundColor(theme.textTertiary)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
        .frame(minHeight: 520, alignment: .top)
        .background(theme.bg)
    }

    /// 设置页标签：主行随语言（v2.2 反馈#1——设置窗口此前全是硬编码英文）。
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? L("settings.version_development")
    }

    private func L(_ key: String, args: [String: String] = [:]) -> String {
        L10n.t(key, locale: vm.settings.language, args: args)
    }

    // MARK: 行构件

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(theme.title).foregroundColor(theme.textPrimary)
            VStack(spacing: 0) { content() }
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .stroke(theme.border, lineWidth: 1))
        }
    }

    private func stepperRow(_ label: String, value: Int, range: ClosedRange<Int>,
                            unit: String, showsDivider: Bool = true,
                            onChange: @escaping (Int) -> Void) -> some View {
        settingsRow(label, showsDivider: showsDivider) {
            Text("\(value) \(unit)")
                .font(theme.monoBody).foregroundColor(theme.textSecondary)
            Stepper("", value: Binding(get: { value }, set: onChange), in: range)
                .labelsHidden()
                .controlSize(.small)
                .accessibilityLabel(label)
                .accessibilityValue("\(value) \(unit)")
        }
    }

    private func toggleRow(_ label: String, isOn: Bool, showsDivider: Bool = true,
                           onChange: @escaping (Bool) -> Void) -> some View {
        settingsRow(label, showsDivider: showsDivider) {
            Toggle("", isOn: Binding(get: { isOn }, set: onChange))
                .toggleStyle(.switch)
                .tint(theme.accent)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(label)
        }
    }

    private func settingsRow<Content: View>(
        _ label: String,
        showsDivider: Bool = true,
        @ViewBuilder trailing: () -> Content
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(theme.body13)
                .foregroundColor(theme.textPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(theme.border)
                    .frame(height: 1)
            }
        }
    }

    private func updateLanguage(_ language: String) {
        vm.applySettings { $0.language = language }
    }
}
