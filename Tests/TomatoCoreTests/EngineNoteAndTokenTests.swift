import XCTest
@testable import TomatoCore

/// note 贯穿 session 生命周期，并在 finalize 时生成 fakeTokens。
final class EngineNoteAndTokenTests: XCTestCase {
    func testNoteFlowsIntoSessionAndFakeTokensSetOnCompletion() {
        let clock = MockClock()
        let engine = TomatoEngine(clock: clock, settings: .default)

        XCTAssertTrue(engine.sendRequest(note: "写 SPEC 文档"))
        XCTAssertEqual(engine.currentSession?.note, "写 SPEC 文档")

        clock.advance(by: 2)
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.phase, .focusing)

        clock.advance(by: 25 * 60)
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.phase, .completed)
        XCTAssertEqual(engine.currentSession?.note, "写 SPEC 文档")
        XCTAssertGreaterThan(engine.currentSession?.fakeTokens ?? 0, 0)
    }

    func testSendRequestWithoutNoteKeepsNil() {
        let clock = MockClock()
        let engine = TomatoEngine(clock: clock, settings: .default)
        XCTAssertTrue(engine.sendRequest())
        XCTAssertNil(engine.currentSession?.note)
    }

    func testFakeTokensSetOnAbort() {
        let clock = MockClock()
        let engine = TomatoEngine(clock: clock, settings: .default)
        engine.sendRequest()
        clock.advance(by: 2)
        engine.tick(now: clock.now())
        clock.advance(by: 10 * 60)
        engine.tick(now: clock.now())
        engine.abortRequest()
        XCTAssertEqual(engine.currentSession?.status, .aborted)
        XCTAssertGreaterThan(engine.currentSession?.fakeTokens ?? 0, 0)
    }

    func testFakeTokensDeterministicPerSession() {
        // 同一 session 的 fakeTokens 只由 durationMin + id 决定，重复 finalize 不漂移
        let clock = MockClock()
        let engine = TomatoEngine(clock: clock, settings: .default)
        engine.sendRequest()
        clock.advance(by: 2)
        engine.tick(now: clock.now())
        clock.advance(by: 25 * 60)
        engine.tick(now: clock.now())
        let first = engine.currentSession?.fakeTokens
        engine.tick(now: clock.now())
        XCTAssertEqual(engine.currentSession?.fakeTokens, first)
    }
}
