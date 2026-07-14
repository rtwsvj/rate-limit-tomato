import XCTest
@testable import TomatoCore

final class TomatoCoreScaffoldTests: XCTestCase {
    func testScaffold() {
        XCTAssertFalse(TomatoCoreInfo.version.isEmpty)
    }
}
