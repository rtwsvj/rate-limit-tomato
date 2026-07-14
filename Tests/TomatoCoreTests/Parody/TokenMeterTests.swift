import XCTest
@testable import TomatoCore

final class TokenMeterTests: XCTestCase {
    func testMonotonicity() {
        let meter = TokenMeter(seed: 42)
        var values: [Int] = []
        for s in 1...300 {
            values.append(meter.tokens(forElapsedSeconds: TimeInterval(s)))
        }
        XCTAssertFalse(values.isEmpty)
        for i in 1..<values.count {
            XCTAssertGreaterThanOrEqual(
                values[i], values[i - 1],
                "tokens decreased at second \(i): \(values[i - 1]) -> \(values[i])"
            )
        }
    }

    func testMonotonicityAcrossSeeds() {
        for seed: UInt64 in [1, 7, 42, 999] {
            let meter = TokenMeter(seed: seed)
            var prev = meter.tokens(forElapsedSeconds: 1)
            for s in 2...120 {
                let v = meter.tokens(forElapsedSeconds: TimeInterval(s))
                XCTAssertGreaterThanOrEqual(v, prev, "seed=\(seed) decreased at s=\(s)")
                prev = v
            }
        }
    }

    func testMonotonicityLongRange() {
        let meter = TokenMeter(seed: 42)
        var prev = meter.tokens(forElapsedSeconds: 1)
        for s in stride(from: 10, through: 100_000, by: 37) {
            let v = meter.tokens(forElapsedSeconds: TimeInterval(s))
            XCTAssertGreaterThanOrEqual(v, prev, "decreased at s=\(s)")
            prev = v
        }
    }

    func testBaselineRateAccuracy() {
        // 长期均值应贴近 500 token/分钟基线（±5% 容差）
        let meter = TokenMeter(seed: 42)
        let tokens = meter.tokens(forElapsedSeconds: 3600)
        XCTAssertGreaterThan(tokens, 28_500)
        XCTAssertLessThan(tokens, 31_500)
    }

    func testZeroElapsedReturnsZero() {
        let meter = TokenMeter(seed: 42)
        XCTAssertEqual(meter.tokens(forElapsedSeconds: 0), 0)
        XCTAssertEqual(meter.tokens(forElapsedSeconds: -1), 0)
    }

    func testNonZeroAfterTime() {
        let meter = TokenMeter(seed: 42)
        XCTAssertGreaterThan(meter.tokens(forElapsedSeconds: 60), 0)
        // 注意：第二个 tokens(60) 因 60 < 上次的 600 触发内部重置，
        // 实际比较的是同种子下两个独立序列（600s vs 60s）的累计值
        XCTAssertGreaterThan(meter.tokens(forElapsedSeconds: 600), meter.tokens(forElapsedSeconds: 60))
    }

    func testThousandsSeparator() {
        XCTAssertEqual(TokenMeter.format(0), "0")
        XCTAssertEqual(TokenMeter.format(7), "7")
        XCTAssertEqual(TokenMeter.format(42), "42")
        XCTAssertEqual(TokenMeter.format(999), "999")
        XCTAssertEqual(TokenMeter.format(1_000), "1,000")
        XCTAssertEqual(TokenMeter.format(1_204), "1,204")
        XCTAssertEqual(TokenMeter.format(12_403), "12,403")
        XCTAssertEqual(TokenMeter.format(123_456), "123,456")
        XCTAssertEqual(TokenMeter.format(1_234_567), "1,234,567")
    }
}
