import SwiftUI
import TomatoCore

/// 面板骨架（UI-SPEC §2）：顶栏 44 + 内容 padding 20 + 底栏 28，宽 380 固定。
public struct MenubarPanel: View {
    public init() {}

    @EnvironmentObject private var vm: AppViewModel
    @Environment(\.tomatoTheme) private var theme
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(spacing: 0) {
            topBar
                .accessibilityHidden(modalVisible)
            Divider().overlay(theme.border)

            if vm.dailyResetBannerVisible {
                dailyResetBanner
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityHidden(modalVisible)
            }

            // 固定高度内容兜底：装得下就居中，装不下降级为滚动（长 note、
            // 日终横幅+展开 headers 叠加等边界不至于把按钮挤出窗口）
            ViewThatFits(in: .vertical) {
                stateContent
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    stateContent
                        .padding(20)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
            .accessibilityHidden(modalVisible)

            Divider().overlay(theme.border)
            footer
                .accessibilityHidden(modalVisible)
        }
        .frame(width: 380, height: 540) // 固定高：状态切换时窗口 resize 会露出磨砂底
        .background(theme.bg)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: vm.phase)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: vm.dailyResetBannerVisible)
        // 模态一律画在面板内部：MenuBarExtra 面板上 present .sheet 会把面板一起带崩
        .overlay { modalLayer }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: vm.showUpgradeSheet)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: vm.showDisclaimer)
        .onAppear { consumePendingUsageWindow() }
        .onChange(of: vm.pendingUsageWindow) { _, _ in consumePendingUsageWindow() }
        .onChange(of: vm.pendingSettingsWindow) { _, _ in consumePendingUsageWindow() }
    }

    private var modalVisible: Bool { vm.showDisclaimer || vm.showUpgradeSheet }

    /// rlt://usage：面板具备 openWindow 上下文后打开用量窗口
    private func consumePendingUsageWindow() {
        if vm.pendingUsageWindow {
            vm.pendingUsageWindow = false
            WindowOpener.openUsage(openWindow)
        }
        if vm.pendingSettingsWindow {
            vm.pendingSettingsWindow = false
            WindowOpener.openSettings(openWindow)
        }
    }

    /// 面板内模态叠层：遮罩 + 卡片（免责优先于升级页）。
    @ViewBuilder private var modalLayer: some View {
        if vm.showDisclaimer || vm.showUpgradeSheet {
            ZStack {
                theme.textPrimary.opacity(0.25)
                    .onTapGesture {
                        // 免责必须显式确认，不许点遮罩关闭（SPEC §13.5）
                        if !vm.showDisclaimer { vm.showUpgradeSheet = false }
                    }
                Group {
                    if vm.showDisclaimer {
                        DisclaimerSheet()
                    } else {
                        UpgradeSheet(onDismiss: { vm.showUpgradeSheet = false })
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: theme.cardRadius, style: .continuous)
                    .stroke(theme.border, lineWidth: 1))
            }
            .transition(.opacity)
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        let meta = vm.statusMeta
        return HStack(spacing: 8) {
            StatusDot(kind: meta.dotKind)
            Text(meta.label)
                .font(theme.monoBody)
                .foregroundColor(theme.textSecondary)
            Spacer()
            IconButton(systemName: "chart.bar.doc.horizontal",
                       help: LocalizedPair("nav.usage", locale: vm.settings.language).inline) {
                WindowOpener.openUsage(openWindow)
            }
            IconButton(systemName: "gearshape",
                       help: LocalizedPair("nav.settings", locale: vm.settings.language).inline) {
                WindowOpener.openSettings(openWindow)
            }
            IconButton(systemName: "power",
                       help: LocalizedPair("nav.quit", locale: vm.settings.language).inline) {
                vm.flush()
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    // MARK: 日终横幅

    private var dailyResetBanner: some View {
        BilingualText("quota.reset_daily", alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(theme.card)
    }

    // MARK: 状态内容

    @ViewBuilder private var stateContent: some View {
        switch vm.phase {
        case .idle: IdleView()
        case .sending: SendingView()
        case .focusing: FocusingView()
        case .completed: CompletedView()
        case .rateLimited: RateLimitView()
        case .aborted: AbortedView()
        case .teapot: TeapotView()
        case .reset: ResetView()
        }
    }

    // MARK: 底栏

    private var footer: some View {
        Text(L10n.t("app.footer", locale: vm.settings.language))
            .font(theme.monoTag)
            .foregroundColor(theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
    }
}

/// 顶栏状态点（8px；sending/focusing 脉冲）。
struct StatusDot: View {
    let kind: StatusDotKind

    @Environment(\.tomatoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .opacity(!reduceMotion && kind == .accentPulse && pulsing ? 0.35 : 1)
            .animation(
                !reduceMotion && kind == .accentPulse
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : nil,
                value: pulsing
            )
            .onAppear { pulsing = true }
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch kind {
        case .success: return theme.success
        case .accentPulse: return theme.accent
        case .deep: return theme.accentDeep
        case .muted: return theme.textTertiary
        }
    }
}
