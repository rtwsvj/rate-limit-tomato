import Foundation

/// 戏仿 §9.1.2 假 429 响应头块（限流页可折叠展示）。
/// 输出固定 6 行，X-RateLimit-Reset 取 Unix epoch 秒，Retry-After 取整秒。
public enum FakeHeaderGenerator {
    public static func rateLimited(
        limit: Int,
        remaining: Int,
        resetAt: Date,
        retryAfter: TimeInterval
    ) -> String {
        let epoch = boundedInt(
            resetAt.timeIntervalSince1970,
            range: Int(Int32.min)...Int(Int32.max)
        )
        let retrySeconds = boundedInt(retryAfter.rounded(), range: 0...86_400)
        return """
        HTTP/1.1 429 Too Many Requests
        Content-Type: application/json
        X-RateLimit-Limit: \(limit)
        X-RateLimit-Remaining: \(remaining)
        X-RateLimit-Reset: \(epoch)
        Retry-After: \(retrySeconds)
        """
    }

    private static func boundedInt(_ value: Double, range: ClosedRange<Int>) -> Int {
        guard value.isFinite else { return value.sign == .minus ? range.lowerBound : range.upperBound }
        return Int(min(Double(range.upperBound), max(Double(range.lowerBound), value)))
    }
}
