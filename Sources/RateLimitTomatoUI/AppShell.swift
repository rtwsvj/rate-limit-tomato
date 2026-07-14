import AppKit
import SwiftUI
import TomatoCore

// App 壳所需的公开入口（菜单栏 label、窗口容器、窗口辅助）。

/// 菜单栏 label（UI-SPEC §2）：⏱ + 状态文字（额度/倒计时/429/503）。
public struct MenuBarLabel: View {
    @ObservedObject var viewModel: AppViewModel

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            Text(viewModel.menuBarText).monospacedDigit()
        }
        .font(.system(size: 12, weight: .medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.t(
            "app.menu_bar_status",
            locale: viewModel.settings.language,
            args: [
                "state": viewModel.phasePresentation.label,
                "value": viewModel.menuBarText,
            ]
        ))
    }

    /// 状态化图标（菜单栏为模板渲染，形状即语义）
    private var symbol: String {
        switch viewModel.phase {
        case .focusing: return "timer"
        case .rateLimited: return "snowflake"
        case .teapot: return "mug"
        case .sending, .completed, .reset: return "timer"
        case .idle, .aborted:
            return viewModel.isQuotaExhausted ? "moon.zzz" : "timer"
        }
    }
}

/// 用量窗口容器：出现时从磁盘重读一次（不在 body 里做 I/O）。
public struct UsageWindowContainer: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var sessions: [FocusSession] = []

    public init(viewModel: AppViewModel) { self.viewModel = viewModel }

    public var body: some View {
        UsageDashboardView(
            sessions: sessions,
            endingAt: Date(),
            onRefresh: { sessions = viewModel.loadSessions() }
        )
        .environment(\.rltShowSecondary, !viewModel.settings.isEnglish)
        .environment(\.rltPrimaryLocale, viewModel.settings.language)
        .environmentObject(viewModel)
        .environment(\.tomatoTheme, viewModel.theme)
        .onAppear { sessions = viewModel.loadSessions() }
    }
}

// MARK: - 窗口辅助

@MainActor
public enum WindowOpener {
    public static func openUsage(_ openWindow: OpenWindowAction) {
        openWindow(id: WindowID.usage)
        NSApp.activate(ignoringOtherApps: true)
    }
    public static func openSettings(_ openWindow: OpenWindowAction) {
        openWindow(id: WindowID.settings)
        NSApp.activate(ignoringOtherApps: true)
    }
}

public enum WindowID {
    public static let usage = "usage"
    public static let settings = "settings"
}
