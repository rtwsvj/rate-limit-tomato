import Foundation

/// 戏仿 §9.1.3 假 JSON 响应体模板（专注完成，完成卡片展示）。
/// 输出为 prettyPrinted JSON 字符串，可被 JSONSerialization 解析。
/// 会话 ID 由 `SessionID.generate()` 生成。
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
