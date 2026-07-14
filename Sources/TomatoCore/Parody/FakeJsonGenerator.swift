import Foundation

/// 生成 "focus_" + 8 位小写 hex 的会话 ID（§9.1.3 / §11.1）。
/// 由 SplitMix64 派生，同一种子 → 同一 ID；不同种子 → 不同 ID。
public enum FocusIdGenerator {
    public static func generate(seed: UInt64) -> String {
        var rng = SplitMix64(state: seed)
        let value = rng.next()
        let hex = String(value, radix: 16, uppercase: false)
        let suffixLen = min(8, hex.count)
        let suffix = String(hex.suffix(suffixLen))
        if suffix.count < 8 {
            let pad = String(repeating: "0", count: 8 - suffix.count)
            return "focus_" + pad + suffix
        }
        return "focus_" + suffix
    }
}

/// 戏仿 §9.1.3 假 JSON 响应体模板（专注完成 / 走神中断）。
/// 输出为 prettyPrinted JSON 字符串，可被 JSONSerialization 解析。
public enum FakeJsonGenerator {
    public static func completed(
        id: String,
        createdAt: Date,
        durationMs: Int,
        tokensUsed: Int
    ) -> String {
        let dict: [String: Any] = [
            "id": id,
            "object": "focus_session",
            "created_at": boundedEpoch(createdAt.timeIntervalSince1970),
            "duration_ms": durationMs,
            "tokens_used": tokensUsed,
            "model": "tomato-1.0",
            "status": "completed",
        ]
        return encode(dict)
    }

    private static func boundedEpoch(_ value: Double) -> Int {
        guard value.isFinite else { return value.sign == .minus ? Int(Int32.min) : Int(Int32.max) }
        return Int(min(Double(Int32.max), max(Double(Int32.min), value)))
    }

    public static func aborted(id: String, durationMs: Int) -> String {
        let error: [String: Any] = [
            "type": "request_timeout",
            "code": "408",
            "message": "Focus was interrupted by user.",
        ]
        let dict: [String: Any] = [
            "id": id,
            "object": "focus_session",
            "duration_ms": durationMs,
            "status": "aborted",
            "error": error,
        ]
        return encode(dict)
    }

    private static func encode(_ dict: [String: Any]) -> String {
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: dict,
                options: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
