import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// 发起/中止 fast request。默认值必须延迟到免责声明确认后再求值（SPEC §13 / §15.2）。
    public static let sendOrAbort = Self("sendOrAbort")

    /// `Name(default:)` 会立即写 UserDefaults 并注册快捷键，因此只能由授权后的安装器访问。
    fileprivate static let authorizedSendOrAbort = Self(
        "sendOrAbort",
        default: .init(.f, modifiers: [.command, .option])
    )
}

/// 可注入的全局快捷键安装边界；测试可用探针验证时机而不触碰系统快捷键。
@MainActor
public protocol GlobalShortcutInstalling {
    func installSendOrAbort(action: @escaping () -> Void)
}

/// 生产环境安装器。构造本身无副作用，调用 install 才求值默认快捷键并挂 handler。
@MainActor
public struct SystemGlobalShortcutInstaller: GlobalShortcutInstalling {
    public init() {}

    public func installSendOrAbort(action: @escaping () -> Void) {
        _ = KeyboardShortcuts.Name.authorizedSendOrAbort
        KeyboardShortcuts.onKeyUp(for: .sendOrAbort, action: action)
    }
}
