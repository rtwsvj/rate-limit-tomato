import XCTest
@testable import TomatoCore

final class ModelsTests: XCTestCase {
    // MARK: - Defaults

    func testAppSettingsDefaults() {
        let s = AppSettings.default
        XCTAssertEqual(s.focusDurationMin, 25)
        XCTAssertEqual(s.cooldownDurationMin, 5)
        XCTAssertEqual(s.longBreakMin, 15)
        XCTAssertEqual(s.maxPerDay, 8)
        XCTAssertEqual(s.provider, .a)
        XCTAssertEqual(s.language, "zh-CN")
        XCTAssertTrue(s.showFakeLogs)
        XCTAssertTrue(s.showFakeHeaders)
        XCTAssertTrue(s.soundEnabled)
        XCTAssertEqual(s.globalShortcut, "")
        XCTAssertFalse(s.parodyDisclaimerAck)
    }

    func testAppSettingsInteractionRangesMatchProductControls() {
        XCTAssertEqual(AppSettings.focusInteractionRange, 1...120)
        XCTAssertEqual(AppSettings.cooldownInteractionRange, 1...60)
        XCTAssertEqual(AppSettings.maxPerDayInteractionRange, 1...24)
        XCTAssertTrue(AppSettings.focusRange.contains(AppSettings.focusInteractionRange.upperBound))
        XCTAssertTrue(AppSettings.cooldownRange.contains(AppSettings.cooldownInteractionRange.upperBound))
        XCTAssertTrue(AppSettings.maxPerDayRange.contains(AppSettings.maxPerDayInteractionRange.upperBound))
    }

    // MARK: - Enum roundtrip

    func testSessionStatusRoundtrip() throws {
        for status in SessionStatus.allCases {
            let data = try JSONEncoder().encode(status)
            let decoded = try JSONDecoder().decode(SessionStatus.self, from: data)
            XCTAssertEqual(decoded, status)
        }
    }

    func testProviderRoundtrip() throws {
        for p in Provider.allCases {
            let data = try JSONEncoder().encode(p)
            let decoded = try JSONDecoder().decode(Provider.self, from: data)
            XCTAssertEqual(decoded, p)
        }
    }

    func testSessionStatusRawValues() {
        XCTAssertEqual(SessionStatus.focusing.rawValue, "focusing")
        XCTAssertEqual(SessionStatus.completed.rawValue, "completed")
        XCTAssertEqual(SessionStatus.aborted.rawValue, "aborted")
    }

    func testProviderRawValues() {
        XCTAssertEqual(Provider.a.rawValue, "a")
        XCTAssertEqual(Provider.b.rawValue, "b")
        XCTAssertEqual(Provider.c.rawValue, "c")
    }

    // MARK: - FocusSession Codable

    func testFocusSessionCodable() throws {
        let date = Date(timeIntervalSince1970: 1_719_848_820)
        let session = FocusSession(
            id: "focus_a1b2c3d4",
            createdAt: date,
            date: "2026-07-08",
            startHour: 14,
            startMinute: 30,
            durationMin: 25,
            status: .completed,
            quality: 88,
            fakeTokens: 12_403,
            fakeModel: "tomato-1.0",
            note: "work on launch spec",
            provider: .a
        )
        let encoder = TomatoStore.makeEncoder()
        let decoder = TomatoStore.makeDecoder()
        let data = try encoder.encode(session)
        let decoded = try decoder.decode(FocusSession.self, from: data)
        XCTAssertEqual(decoded, session)
    }

    func testFocusSessionNoteOptional() throws {
        let session = FocusSession(
            id: "focus_x",
            createdAt: Date(timeIntervalSince1970: 0),
            date: "2026-01-01",
            startHour: 9,
            startMinute: 0,
            durationMin: 0,
            status: .focusing,
            quality: 0,
            fakeTokens: 0,
            fakeModel: "tomato-1.0",
            note: nil,
            provider: .b
        )
        let data = try TomatoStore.makeEncoder().encode(session)
        let decoded = try TomatoStore.makeDecoder().decode(FocusSession.self, from: data)
        XCTAssertNil(decoded.note)
        XCTAssertEqual(decoded, session)
    }

    // MARK: - DailyQuota Codable

    func testDailyQuotaCodable() throws {
        let quota = DailyQuota(
            date: "2026-07-08",
            usedToday: 3,
            maxPerDay: 8,
            completedCount: 2,
            abortedCount: 1
        )
        let data = try TomatoStore.makeEncoder().encode(quota)
        let decoded = try TomatoStore.makeDecoder().decode(DailyQuota.self, from: data)
        XCTAssertEqual(decoded, quota)
    }

    func testDailyQuotaSanitizedPreventsOverflowAndImpossibleCounts() {
        let dirty = DailyQuota(
            date: "2026-07-08",
            usedToday: Int.max,
            maxPerDay: Int.min,
            completedCount: Int.max,
            abortedCount: Int.max
        )
        let sanitized = dirty.sanitized(effectiveMaxPerDay: Int.max)

        XCTAssertEqual(sanitized.usedToday, DailyQuota.maximumTrackedCount)
        XCTAssertEqual(sanitized.maxPerDay, AppSettings.maxPerDayRange.upperBound)
        XCTAssertEqual(sanitized.completedCount, DailyQuota.maximumTrackedCount)
        XCTAssertEqual(sanitized.abortedCount, 0)
    }

    func testDailyQuotaSanitizedPreservesUsedCountWhenUserLowersLimit() {
        let quota = DailyQuota(
            date: "2026-07-08",
            usedToday: 8,
            maxPerDay: 8,
            completedCount: 5,
            abortedCount: 3
        )
        let sanitized = quota.sanitized(effectiveMaxPerDay: 4)

        XCTAssertEqual(sanitized.usedToday, 8)
        XCTAssertEqual(sanitized.maxPerDay, 4)
        XCTAssertEqual(sanitized.completedCount, 5)
        XCTAssertEqual(sanitized.abortedCount, 3)
    }

    func testDailyQuotaSanitizedClampsNegativeCounts() {
        let quota = DailyQuota(
            date: "2026-07-08",
            usedToday: Int.min,
            maxPerDay: 8,
            completedCount: -1,
            abortedCount: -2
        ).sanitized(effectiveMaxPerDay: Int.min)

        XCTAssertEqual(quota.usedToday, 0)
        XCTAssertEqual(quota.maxPerDay, AppSettings.maxPerDayRange.lowerBound)
        XCTAssertEqual(quota.completedCount, 0)
        XCTAssertEqual(quota.abortedCount, 0)
    }

    // MARK: - AppSettings Codable

    func testAppSettingsCodable() throws {
        let s = AppSettings(
            focusDurationMin: 30,
            cooldownDurationMin: 7,
            longBreakMin: 20,
            maxPerDay: 6,
            provider: .c,
            language: "en",
            showFakeLogs: false,
            showFakeHeaders: false,
            soundEnabled: false,
            globalShortcut: "cmd+shift+t",
            parodyDisclaimerAck: true
        )
        let data = try TomatoStore.makeEncoder().encode(s)
        let decoded = try TomatoStore.makeDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    // MARK: - SessionID

    func testSessionIDFormat() {
        let id = SessionID.generate()
        XCTAssertTrue(id.hasPrefix("focus_"))
        XCTAssertGreaterThanOrEqual(id.count, "focus_".count + 8)
    }

    func testFocusSessionMakeID() {
        XCTAssertEqual(FocusSession.makeID("abcd1234"), "focus_abcd1234")
    }
}
