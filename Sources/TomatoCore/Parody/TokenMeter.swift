import Foundation

/// 戏仿 §9.1.4 假 token 计数器。
/// 线性基线（默认 500 token / 分钟）+ 小幅种子扰动；实例内部累加，保证单调不减。
/// 同一种子 + 同一调用序列 → 同一结果。
public final class TokenMeter {
    public let baseTokensPerMinute: Double
    public let seed: UInt64

    private var rng: SplitMix64
    private var lastElapsed: TimeInterval = 0
    private var accumulated: Double = 0

    public init(seed: UInt64, baseTokensPerMinute: Double = 500.0) {
        self.seed = seed
        self.baseTokensPerMinute = baseTokensPerMinute.isFinite
            ? min(1_000_000, max(0, baseTokensPerMinute))
            : 500.0
        self.rng = SplitMix64(state: seed == 0 ? 1 : seed)
    }

    /// 累计到指定已过秒数的假 token 数。elapsed <= 0 返回 0；
    /// elapsed < 内部上一次记录则视为新序列并重置。
    public func tokens(forElapsedSeconds elapsed: TimeInterval) -> Int {
        // NaN 会穿过 <=0 比较（任何 NaN 比较都是 false）直达 Int 转换陷阱
        guard elapsed.isFinite else { return Self.safeInt(accumulated) }
        if elapsed <= 0 { return 0 }
        if elapsed < lastElapsed {
            rng = SplitMix64(state: seed == 0 ? 1 : seed)
            lastElapsed = 0
            accumulated = 0
        }
        let basePerSec = baseTokensPerMinute / 60.0
        // dt 钳制一年：防 Double→Int 转换在天文输入（distantFuture 级）上溢陷阱
        let dt = min(elapsed - lastElapsed, 86_400 * 365)
        let tickCount = max(1, Int(dt.rounded(.up)))
        // 时钟跳变时 dt 可能巨大（如睡眠唤醒）；封顶扰动循环上限 7200，
        // 剩余秒数走无扰动线性基线一次性累加，避免无界循环卡死主线程。
        let cappedTicks = min(tickCount, 7200)
        for _ in 0..<cappedTicks {
            // 扰动 ±2 token/秒；Double 累加使长期均值精确等于 basePerSec
            let jitter = Double(rng.next() % 4001) / 1000.0 - 2.0
            accumulated += max(0, basePerSec + jitter)
        }
        if tickCount > 7200 {
            accumulated += basePerSec * Double(tickCount - cappedTicks)
        }
        lastElapsed = elapsed
        return Self.safeInt(accumulated)
    }

    /// 千分位格式化（"1204" → "1,204"）。
    public static func format(_ tokens: Int) -> String {
        insertThousandsSeparator(tokens)
    }

    public static func insertThousandsSeparator(_ n: Int) -> String {
        let negative = n < 0
        // `Int.min` 不能取负；magnitude 可无溢出地得到无符号绝对值。
        let digits = String(n.magnitude)
        if digits.count <= 3 { return negative ? "-" + digits : digits }
        let chars = Array(digits)
        let firstGroupLen = chars.count % 3
        var result = ""
        if firstGroupLen > 0 {
            result.append(contentsOf: chars[0..<firstGroupLen])
        }
        var i = firstGroupLen
        while i < chars.count {
            if !result.isEmpty { result.append(",") }
            result.append(chars[i])
            result.append(chars[i + 1])
            result.append(chars[i + 2])
            i += 3
        }
        return negative ? "-" + result : result
    }

    static func safeInt(_ value: Double) -> Int {
        guard value.isFinite else { return value.sign == .minus ? 0 : Int.max }
        // Double(Int.max) 在 64 位平台舍入为 2^63；nextDown 才是可安全转 Int 的上界。
        let upper = Double(Int.max).nextDown
        return Int(min(upper, max(0, value)))
    }
}
