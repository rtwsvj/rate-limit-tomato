import Foundation
import TomatoCore
import UserNotifications

/// 将系统通知中心的写操作收口，测试可注入内存探针而不访问 TCC 或通知数据库。
@MainActor
protocol NotificationCenterClient: AnyObject {
    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?)
    func requestAuthorization(options: UNAuthorizationOptions)
    func setNotificationCategories(_ categories: Set<UNNotificationCategory>)
    func add(_ request: UNNotificationRequest)
}

@MainActor
private final class SystemNotificationCenterClient: NotificationCenterClient {
    private var center: UNUserNotificationCenter { .current() }

    func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
        center.delegate = delegate
    }

    func requestAuthorization(options: UNAuthorizationOptions) {
        center.requestAuthorization(options: options) { _, _ in }
    }

    func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
        center.setNotificationCategories(categories)
    }

    func add(_ request: UNNotificationRequest) {
        center.add(request)
    }
}

/// 系统通知（可交互，改写自 TomatoBar Notifications.swift 的模式，
/// 见 docs/pinhaoma-sources.md）。文案戏仿主行 + 正经副行，随 settings.language 双语。
///
/// 仅在真实 .app 环境注册：裸 SPM 可执行/XCTest 下 UNUserNotificationCenter
/// 会因缺 bundle proxy 崩溃，`isAvailable` 挡掉。
@MainActor
final class NotificationService: NSObject {
    enum Action: String {
        case startNext = "RLT_START_NEXT"
        case skipCooldown = "RLT_SKIP_COOLDOWN"
    }

    static let categoryCompleted = "RLT_COMPLETED"
    static let categoryReset = "RLT_RESET"

    /// 用户点通知本体/按钮时回调（主线程）。
    var onAction: ((Action?) -> Void)?

    private let isAvailable: Bool
    private let center: any NotificationCenterClient
    private var isActivated = false

    init(isAvailable: Bool = Bundle.main.bundleURL.pathExtension == "app"
         && NSClassFromString("XCTestCase") == nil,
         center: (any NotificationCenterClient)? = nil) {
        // 只在真 .app 形态启用：XCTest（环境变量在新 Xcode 下不可靠，改查 XCTestCase 类）
        // 和裸 SPM 二进制下 UNUserNotificationCenter 会因 bundleProxy 为 nil 直接崩
        self.isAvailable = isAvailable
        self.center = center ?? SystemNotificationCenterClient()
        super.init()
    }

    /// 首次免责确认后才启用系统通知。构造服务本身不得弹权限框或写系统状态。
    func activate(language: String) {
        guard isAvailable else { return }
        if !isActivated {
            isActivated = true
            center.setDelegate(self)
            center.requestAuthorization(options: [.alert, .sound])
        }
        registerCategories(language: language)
    }

    /// 语言切换后重注册类别，让通知按钮文案跟随（vm.applySettings 调用）。
    func refreshCategories(language: String) {
        guard isAvailable, isActivated else { return }
        registerCategories(language: language)
    }

    private func registerCategories(language: String = AppLocale.zhCN.rawValue) {
        let skip = UNNotificationAction(
            identifier: Action.skipCooldown.rawValue,
            title: L10n.t("action.skip_cooldown", locale: language), options: []
        )
        let start = UNNotificationAction(
            identifier: Action.startNext.rawValue,
            title: L10n.t("notif.action_start", locale: language), options: []
        )
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryCompleted, actions: [skip],
                                   intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.categoryReset, actions: [start],
                                   intentIdentifiers: [], options: []),
        ])
    }

    /// 专注完成 → 进入限流：`429` 戏仿主行 + 正经副行。
    func notifyCompleted(language: String, cooldownMinutes: Int) {
        send(
            title: L10n.t("notif.completed_title", locale: language),
            body: L10n.t("notif.completed_body", locale: language,
                         args: ["min": "\(cooldownMinutes)"]),
            category: Self.categoryCompleted
        )
    }

    /// 冷却结束 → 额度恢复：邀请开始下一轮。
    func notifyReset(language: String) {
        send(
            title: L10n.t("notif.reset_title", locale: language),
            body: L10n.t("notif.reset_body", locale: language),
            category: Self.categoryReset
        )
    }

    private func send(title: String, body: String, category: String) {
        guard isAvailable, isActivated else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        // 音效由 SoundService 统一管（避免双响）
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        center.add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// App 在前台也照常横幅展示（菜单栏 App 永远"在前台"）。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = Action(rawValue: response.actionIdentifier)
        Task { @MainActor in
            self.onAction?(action)
        }
        completionHandler()
    }
}
