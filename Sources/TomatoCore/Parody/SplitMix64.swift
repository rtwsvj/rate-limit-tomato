import Foundation

/// SplitMix64 — 确定性 64-bit 伪随机数生成器（无第三方依赖）。
/// 用于 TokenMeter、FakeLogStreamGenerator、FocusIdGenerator 的种子化随机源。
/// 算法参考 Stafford variant of SplitMix64，分布均匀且状态可复现。
struct SplitMix64 {
    private var state: UInt64

    init(state: UInt64) {
        self.state = state
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
