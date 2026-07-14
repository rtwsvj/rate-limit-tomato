import XCTest
@testable import TomatoCore

final class FakeLogStreamGeneratorTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_735_689_600)

    func testDeterministicForSameSeed() {
        let g1 = FakeLogStreamGenerator(seed: 42, startDate: fixedDate)
        let g2 = FakeLogStreamGenerator(seed: 42, startDate: fixedDate)
        XCTAssertEqual(g1.lines(elapsed: 300), g2.lines(elapsed: 300))
    }

    func testDifferentSeedsProduceDifferentOutput() {
        let g1 = FakeLogStreamGenerator(seed: 1, startDate: fixedDate)
        let g2 = FakeLogStreamGenerator(seed: 2, startDate: fixedDate)
        XCTAssertNotEqual(g1.lines(elapsed: 300), g2.lines(elapsed: 300))
    }

    func testZeroElapsedProducesNoLines() {
        let g = FakeLogStreamGenerator(seed: 42, startDate: fixedDate)
        XCTAssertTrue(g.lines(elapsed: 0).isEmpty)
    }

    func testContainsInitialRequestAndResponse() {
        let g = FakeLogStreamGenerator(seed: 42, startDate: fixedDate)
        let lines = g.lines(elapsed: 1)
        XCTAssertTrue(lines.contains(where: { $0.contains("POST /v1/focus") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("← 200 OK") }))
        XCTAssertTrue(lines.contains(where: { $0.contains("latency:") }))
    }

    func testTokensMonotonicAcrossLines() {
        let g = FakeLogStreamGenerator(seed: 42, startDate: fixedDate)
        let lines = g.lines(elapsed: 1500)
        let values = extractTokenValues(from: lines)
        XCTAssertFalse(values.isEmpty, "expected at least one tokens used: line")
        for i in 1..<values.count {
            XCTAssertGreaterThanOrEqual(
                values[i], values[i - 1],
                "tokens decreased at line \(i): \(values[i - 1]) -> \(values[i])"
            )
        }
    }

    func testThousandsSeparatorInTokens() {
        let g = FakeLogStreamGenerator(seed: 42, startDate: fixedDate)
        let lines = g.lines(elapsed: 1500)
        let tokenLines = lines.filter { $0.contains("tokens used:") }
        XCTAssertFalse(tokenLines.isEmpty)

        let regex = try! NSRegularExpression(pattern: #"tokens used: \d{1,3}(,\d{3})*$"#)
        for line in tokenLines {
            let range = NSRange(line.startIndex..., in: line)
            XCTAssertNotNil(
                regex.firstMatch(in: line, range: range),
                "line '\(line)' does not match thousands format"
            )
        }
    }

    func testIncludesStreamingLines() {
        let g = FakeLogStreamGenerator(seed: 42, startDate: fixedDate)
        let lines = g.lines(elapsed: 1500)
        XCTAssertTrue(lines.contains(where: { $0.contains("streaming...") }))
    }

    private func extractTokenValues(from lines: [String]) -> [Int] {
        let pattern = #"tokens used: ([\d,]+)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        var values: [Int] = []
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: range),
                  match.numberOfRanges >= 2 else { continue }
            let valueRange = match.range(at: 1)
            guard let swiftRange = Range(valueRange, in: line) else { continue }
            let raw = line[swiftRange].replacingOccurrences(of: ",", with: "")
            if let n = Int(raw) { values.append(n) }
        }
        return values
    }
}
