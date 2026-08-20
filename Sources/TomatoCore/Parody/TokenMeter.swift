import Foundation

/// 戏仿 token 数的千分位格式化（"1204" → "1,204"）。
/// 展示用的 token 计数由 `FakeLogStreamGenerator`（log 流）与
/// `TomatoEngine.fakeTokenCount`（会话记录）各自确定性生成。
public enum TokenMeter {
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
}
