import Testing
import UserNotifications

@testable import AIPedometer

@MainActor
final class FakeUserNotificationCenter: UserNotificationCenterProtocol {
    var status: UNAuthorizationStatus = .notDetermined
    var requestedOptions: UNAuthorizationOptions?
    var granted = true
    var addedRequests: [UNNotificationRequest] = []
    var removedIdentifiers: [String] = []

    func authorizationStatus() async -> UNAuthorizationStatus {
        status
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestedOptions = options
        return granted
    }

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        removedIdentifiers.append(contentsOf: identifiers)
    }
}

@Suite("NotificationService")
@MainActor
struct NotificationServiceTests {
    @Test("Requests authorization with alert, badge, and sound")
    func requestAuthorizationUsesExpectedOptions() async throws {
        let center = FakeUserNotificationCenter()
        let service = NotificationService(center: center)

        _ = try await service.requestAuthorization()

        #expect(center.requestedOptions?.contains(.alert) == true)
        #expect(center.requestedOptions?.contains(.badge) == true)
        #expect(center.requestedOptions?.contains(.sound) == true)
    }

    @Test("Schedules daily goal reminder with configured identifier and time")
    func scheduleDailyGoalReminderUsesIdentifierAndTime() async throws {
        let center = FakeUserNotificationCenter()
        let service = NotificationService(center: center)

        try await service.scheduleDailyGoalReminder(hour: 8, minute: 30)

        #expect(center.addedRequests.count == 1)
        let request = center.addedRequests.first
        #expect(request?.identifier == AppConstants.Notifications.dailyGoalReminder)

        let trigger = request?.trigger as? UNCalendarNotificationTrigger
        #expect(trigger?.dateComponents.hour == 8)
        #expect(trigger?.dateComponents.minute == 30)
        #expect(trigger?.repeats == true)
    }

    @Test("Cancels daily goal reminder by identifier")
    func cancelDailyGoalReminderUsesIdentifier() {
        let center = FakeUserNotificationCenter()
        let service = NotificationService(center: center)

        service.cancelDailyGoalReminder()

        #expect(center.removedIdentifiers == [AppConstants.Notifications.dailyGoalReminder])
    }

    @Test("Authorization status is reported from notification center")
    func authorizationStatusReflectsCenter() async {
        let center = FakeUserNotificationCenter()
        center.status = .authorized
        let service = NotificationService(center: center)

        let status = await service.authorizationStatus()

        #expect(status == .authorized)
    }
}
