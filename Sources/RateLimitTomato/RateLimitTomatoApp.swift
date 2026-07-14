import AppKit
import MenuBarExtraAccess
import RateLimitTomatoUI
import SwiftUI
import TomatoCore

/// kAEGetURL 须在 App 启动早期注册（rlt:// URL scheme）。
final class RLTAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["RLT_DISABLE_GLOBAL_INTEGRATIONS"] != "1" else {
            return
        }
        MainActor.assumeIsolated {
            URLCommandService.shared.register()
        }
    }
}

@main
struct RateLimitTomatoApp: App {
    @NSApplicationDelegateAdaptor(RLTAppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    var body: some Scene {
        MenuBarExtra {
            MenubarPanel()
                .environmentObject(viewModel)
                .environment(\.tomatoTheme, viewModel.theme)
                .environment(\.rltShowSecondary, !viewModel.settings.isEnglish)
                .environment(\.rltPrimaryLocale, viewModel.settings.language)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        // 面板显隐可编程控制（通知点击弹面板；拼好码引入 MenuBarExtraAccess）
        // 注意顺序：menuBarExtraAccess 定义在 MenuBarExtra 上，须先于 menuBarExtraStyle
        .menuBarExtraAccess(isPresented: $viewModel.panelPresented)
        .menuBarExtraStyle(.window)

        Window(L10n.t("window.usage", locale: viewModel.settings.language), id: WindowID.usage) {
            UsageWindowContainer(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 760, height: 560)
        .windowResizability(.contentMinSize)

        Window(L10n.t("window.settings", locale: viewModel.settings.language), id: WindowID.settings) {
            SettingsView()
                .environmentObject(viewModel)
                .environment(\.tomatoTheme, viewModel.theme)
                .environment(\.rltShowSecondary, !viewModel.settings.isEnglish)
                .environment(\.rltPrimaryLocale, viewModel.settings.language)
        }
        .defaultSize(width: 460, height: 560)
        .windowResizability(.contentMinSize)
    }
}
