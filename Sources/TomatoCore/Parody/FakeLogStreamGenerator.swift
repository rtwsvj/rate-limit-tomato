import Foundation

/// 戏仿 §9.1.4 假 log 流生成器。
/// 输入已过秒数，输出 `[HH:mm:ss] ...` 形式的 log 行数组。
/// 同一种子 + 同一 startDate + 同一 elapsed → 同一输出；
/// tokens 计数线性增长并夹紧到单调不减；千分位格式化。
public struct FakeLogStreamGenerator {
    public let seed: UInt64
    public let startDate: Date
    public let baseTokensPerMinute: Double

    public init(
        seed: UInt64,
        startDate: Date = Date(timeIntervalSince1970: 1735689600),
        baseTokensPerMinute: Double = 500.0
    ) {
        self.seed = seed == 0 ? 1 : seed
        self.startDate = startDate.timeIntervalSince1970.isFinite
            ? startDate
            : Date(timeIntervalSince1970: 0)
        self.baseTokensPerMinute = baseTokensPerMinute.isFinite
            ? min(1_000_000, max(0, baseTokensPerMinute))
            : 500.0
    }

    public func lines(elapsed: TimeInterval) -> [String] {
        guard elapsed.isFinite, elapsed > 0 else { return [] }
        var events: [(sec: Int, kind: EventKind)] = []
        events.append((0, .request))
        events.append((0, .response))
        events.append((0, .latency))

        let tokenTimes = [2, 5, 10, 15, 30, 60, 120, 240, 300, 600, 900, 1500]
        for t in tokenTimes where TimeInterval(t) <= elapsed {
            events.append((t, .tokens))
        }
        let streamTimes = [8, 25, 75, 180, 420, 720]
        for t in streamTimes where TimeInterval(t) <= elapsed {
            events.append((t, .streaming))
        }
        events.sort { lhs, rhs in
            if lhs.sec != rhs.sec { return lhs.sec < rhs.sec }
            return lhs.kind.priority < rhs.kind.priority
        }

        let basePerSec = baseTokensPerMinute / 60.0
        var lastTokens = 0
        var result: [String] = []
        for event in events {
            let linear = Int(basePerSec * Double(event.sec))
            let jitter = hashMod(salt: "tok-\(event.sec)", bound: 41) - 20
            let raw = max(0, linear + jitter)
            lastTokens = max(lastTokens, raw)

            let timestamp = formatTimestamp(secondsOffset: event.sec)
            switch event.kind {
            case .request:
                result.append("\(timestamp) POST /v1/focus")
            case .response:
                result.append("\(timestamp) ← 200 OK")
            case .latency:
                let ms = hashMod(salt: "lat", bound: 30) + 5
                result.append("\(timestamp) latency: \(ms)ms")
            case .tokens:
                result.append("\(timestamp) tokens used: \(TokenMeter.insertThousandsSeparator(lastTokens))")
            case .streaming:
                result.append("\(timestamp) streaming...")
            }
        }
        return result
    }

    // UI 单线程使用，DateFormatter 非线程安全的问题在此可接受。
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func formatTimestamp(secondsOffset: Int) -> String {
        let date = startDate.addingTimeInterval(TimeInterval(secondsOffset))
        return "[\(Self.timestampFormatter.string(from: date))]"
    }

    private func hashMod(salt: String, bound: Int) -> Int {
        var state: UInt64 = seed &+ 0x9E3779B97F4A7C15
        for byte in salt.utf8 {
            state &+= UInt64(byte)
            state &*= 0x100000001B3
        }
        return Int(state % UInt64(bound))
    }

    private enum EventKind {
        case request, response, latency, tokens, streaming
        var priority: Int {
            switch self {
            case .request: return 0
            case .response: return 1
            case .latency: return 2
            case .tokens: return 3
            case .streaming: return 4
            }
        }
    }
}
