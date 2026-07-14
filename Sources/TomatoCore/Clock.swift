import Foundation

/// 抽象时钟，便于测试时用假时钟推进时间。
/// 所有核心逻辑一律经注入的 clock 取时间，禁止直接 `Date()`。
public protocol TomatoClock: Sendable {
    func now() -> Date
}

public struct SystemClock: TomatoClock {
    public init() {}
    public func now() -> Date { Date() }
}

/// 包装时钟并按比例加速流逝时间，供 QA 与可控演示使用。
public struct ScaledClock: TomatoClock {
    public let base: TomatoClock
    public let anchor: Date
    public let scale: Double

    public init(base: TomatoClock, anchor: Date, scale: Double) {
        self.base = base
        self.anchor = anchor
        self.scale = scale
    }

    public func now() -> Date {
        anchor.addingTimeInterval(base.now().timeIntervalSince(anchor) * scale)
    }
}

/// 测试用假时钟。线程安全由 `NSLock` 保护（测试同步推进即可，单测无需 lock-free 优化）。
public final class MockClock: TomatoClock, @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    public init(start: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self._now = start
    }

    public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        _now = _now.addingTimeInterval(interval)
    }

    public func set(now: Date) {
        lock.lock()
        defer { lock.unlock() }
        _now = now
    }
}
