import UserNotifications
import XCTest
@testable import RateLimitTomatoUI
@testable import TomatoCore

@MainActor
final class NotificationServiceTests: XCTestCase {
    private final class CenterProbe: NotificationCenterClient {
        private(set) var delegate: (any UNUserNotificationCenterDelegate)?
        private(set) var authorizationOptions: [UNAuthorizationOptions] = []
        private(set) var categorySets: [Set<UNNotificationCategory>] = []
        private(set) var requests: [UNNotificationRequest] = []

        func setDelegate(_ delegate: (any UNUserNotificationCenterDelegate)?) {
            self.delegate = delegate
        }

        func requestAuthorization(options: UNAuthorizationOptions) {
            authorizationOptions.append(options)
        }

        func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {
            categorySets.append(categories)
        }

        func add(_ request: UNNotificationRequest) {
            requests.append(request)
        }
    }

    func testUnavailableServiceHasNoSystemSideEffects() {
        let center = CenterProbe()
        let service = NotificationService(isAvailable: false, center: center)

        service.activate(language: "en")
        service.refreshCategories(language: "zh-CN")
        service.notifyCompleted(language: "en", cooldownMinutes: 5)
        service.notifyReset(language: "en")

        XCTAssertNil(center.delegate)
        XCTAssertTrue(center.authorizationOptions.isEmpty)
        XCTAssertTrue(center.categorySets.isEmpty)
        XCTAssertTrue(center.requests.isEmpty)
    }

    func testActivationRequestsAuthorizationOnceAndRefreshesLocalizedCategories() throws {
        let center = CenterProbe()
        let service = NotificationService(isAvailable: true, center: center)

        service.refreshCategories(language: "en")
        XCTAssertTrue(center.categorySets.isEmpty, "refresh before activation must be a no-op")

        service.activate(language: "en")
        service.activate(language: "zh-CN")

        XCTAssertTrue(center.delegate === service)
        XCTAssertEqual(center.authorizationOptions.count, 1)
        XCTAssertTrue(center.authorizationOptions[0].contains(.alert))
        XCTAssertTrue(center.authorizationOptions[0].contains(.sound))
        XCTAssertEqual(center.categorySets.count, 2)

        let englishCompleted = try category(
            NotificationService.categoryCompleted,
            in: center.categorySets[0]
        )
        XCTAssertEqual(
            englishCompleted.actions.first?.title,
            L10n.t("action.skip_cooldown", locale: "en")
        )

        let chineseReset = try category(
            NotificationService.categoryReset,
            in: center.categorySets[1]
        )
        XCTAssertEqual(
            chineseReset.actions.first?.title,
            L10n.t("notif.action_start", locale: "zh-CN")
        )
    }

    func testNotificationsAreBlockedUntilActivationAndUseCatalogPayloads() throws {
        let center = CenterProbe()
        let service = NotificationService(isAvailable: true, center: center)

        service.notifyCompleted(language: "en", cooldownMinutes: 7)
        XCTAssertTrue(center.requests.isEmpty)

        service.activate(language: "en")
        service.notifyCompleted(language: "en", cooldownMinutes: 7)
        service.notifyReset(language: "zh-CN")

        XCTAssertEqual(center.requests.count, 2)
        let completed = center.requests[0].content
        XCTAssertEqual(completed.categoryIdentifier, NotificationService.categoryCompleted)
        XCTAssertEqual(completed.title, L10n.t("notif.completed_title", locale: "en"))
        XCTAssertEqual(
            completed.body,
            L10n.t("notif.completed_body", locale: "en", args: ["min": "7"])
        )

        let reset = center.requests[1].content
        XCTAssertEqual(reset.categoryIdentifier, NotificationService.categoryReset)
        XCTAssertEqual(reset.title, L10n.t("notif.reset_title", locale: "zh-CN"))
        XCTAssertEqual(reset.body, L10n.t("notif.reset_body", locale: "zh-CN"))
    }

    private func category(
        _ identifier: String,
        in categories: Set<UNNotificationCategory>
    ) throws -> UNNotificationCategory {
        try XCTUnwrap(categories.first { $0.identifier == identifier })
    }
}
