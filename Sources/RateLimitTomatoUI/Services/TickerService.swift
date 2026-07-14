import AppKit
import Foundation

/// 秒级心跳（改写自 TomatoBar Timer.swift 的计时模式，见 docs/pinhaoma-sources.md）。
/// - `DispatchSourceTimer` 后台队列驱动：与主 RunLoop 模式解耦，面板开合/菜单追踪
///   不会饿死 tick（`Timer.scheduledTimer` 的经典坑）；
/// - 监听系统唤醒（`NSWorkspace.didWakeNotification`）立即补 tick：引擎是墙钟差值
///   驱动，唤醒瞬间即可校正显示，无须等下一秒。
@MainActor
final class TickerService {
    private var timer: DispatchSourceTimer?
    private var wakeObserver: NSObjectProtocol?
    private let onTick: () -> Void

    init(onTick: @escaping () -> Void) {
        self.onTick = onTick
    }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .global(qos: .userInteractive))
        t.schedule(deadline: .now() + 1, repeating: .seconds(1), leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            Task { @MainActor in self?.onTick() }
        }
        t.resume()
        timer = t

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
    }

    func stop() {
        timer?.cancel()
        timer = nil
        if let o = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            wakeObserver = nil
        }
    }

    deinit {
        timer?.cancel()
        if let o = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
    }
}
