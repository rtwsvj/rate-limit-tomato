import XCTest
@testable import TomatoCore

final class FakeJsonGeneratorTests: XCTestCase {
    func testCompletedJsonParsesAndFieldTypes() throws {
        let id = "focus_a1b2c3d4"
        let createdAt = Date(timeIntervalSince1970: 1_719_848_820)
        let json = FakeJsonGenerator.completed(
            id: id,
            createdAt: createdAt,
            durationMs: 1_500_000,
            tokensUsed: 12_403
        )
        let data = try XCTUnwrap(json.data(using: .utf8))
        let raw = try JSONSerialization.jsonObject(with: data)
        let obj = try XCTUnwrap(raw as? [String: Any])

        XCTAssertEqual(obj["id"] as? String, id)
        XCTAssertEqual(obj["object"] as? String, "focus_session")
        XCTAssertEqual(obj["created_at"] as? Int, 1_719_848_820)
        XCTAssertEqual(obj["duration_ms"] as? Int, 1_500_000)
        XCTAssertEqual(obj["tokens_used"] as? Int, 12_403)
        XCTAssertEqual(obj["model"] as? String, "tomato-1.0")
        XCTAssertEqual(obj["status"] as? String, "completed")
    }

    func testAbortedJsonContainsErrorBlock() throws {
        let json = FakeJsonGenerator.aborted(id: "focus_deadbeef", durationMs: 487_000)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(obj["id"] as? String, "focus_deadbeef")
        XCTAssertEqual(obj["object"] as? String, "focus_session")
        XCTAssertEqual(obj["duration_ms"] as? Int, 487_000)
        XCTAssertEqual(obj["status"] as? String, "aborted")

        let error = try XCTUnwrap(obj["error"] as? [String: Any])
        XCTAssertEqual(error["type"] as? String, "request_timeout")
        XCTAssertEqual(error["code"] as? String, "408")
        XCTAssertEqual(error["message"] as? String, "Focus was interrupted by user.")
    }

    func testFocusIdFormat() {
        let pattern = #"^focus_[0-9a-f]{8}$"#
        let regex = try! NSRegularExpression(pattern: pattern)

        for seed: UInt64 in [0, 1, 42, 1_234_567, 9_876_543_210] {
            let id = FocusIdGenerator.generate(seed: seed)
            let range = NSRange(id.startIndex..., in: id)
            XCTAssertNotNil(
                regex.firstMatch(in: id, range: range),
                "id '\(id)' (seed=\(seed)) does not match ^focus_[0-9a-f]{8}$"
            )
        }
    }

    func testFocusIdDeterministic() {
        XCTAssertEqual(FocusIdGenerator.generate(seed: 42), FocusIdGenerator.generate(seed: 42))
    }

    func testDifferentSeedsDifferentIds() {
        XCTAssertNotEqual(FocusIdGenerator.generate(seed: 1), FocusIdGenerator.generate(seed: 2))
    }
}
