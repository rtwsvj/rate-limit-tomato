import AppKit
import Foundation

/// `rlt://` URL scheme 命令入口（改写自 TomatoBar 的 AppleEvent 处理模式，
/// 见 docs/pinhaoma-sources.md）。示例：`open rlt://startStop`。
/// AppDelegate 收到 kAEGetURL 后转发到这里；AppViewModel 在 init 时自注册 handler。
@MainActor
public final class URLCommandService {
    public static let shared = URLCommandService()

    public enum Command: String {
        case startStop = "startstop"   // idle→发起 / focusing→中止
        case send                       // 仅发起
        case abort                      // 仅中止
        case skip                       // 跳过冷却
        case usage                      // 打开用量窗口
        case settings                   // 打开设置窗口
    }

    var handler: ((Command) -> Void)? {
        didSet {
            // 冷启动时 kAEGetURL 可能先于 AppViewModel 装配到达：缓存并在此重放
            if let pending, let handler {
                self.pending = nil
                handler(pending)
            }
        }
    }
    private var pending: Command?

    public func register() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    static func parse(urlString: String) -> Command? {
        guard let url = URL(string: urlString),
              url.scheme == "rlt",
              let host = url.host?.lowercased() else { return nil }
        return Command(rawValue: host)
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let command = Self.parse(urlString: urlString) else { return }
        if let handler {
            handler(command)
        } else {
            pending = command
        }
    }
}
