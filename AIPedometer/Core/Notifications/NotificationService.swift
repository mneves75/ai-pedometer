import Foundation
import Observation
import UserNotifications

@MainActor
protocol NotificationServiceProtocol: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func scheduleDailyGoalReminder(hour: Int, minute: Int) async throws
    func cancelDailyGoalReminder()
}

@MainActor
protocol UserNotificationCenterProtocol: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCenterProtocol {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }
}

@MainActor
@Observable
final class NotificationService: NotificationServiceProtocol {
    private let center: any UserNotificationCenterProtocol

    init(center: any UserNotificationCenterProtocol = UNUserNotificationCenter.current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.authorizationStatus()
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge, .sound])
    }

    func scheduleDailyGoalReminder(hour: Int, minute: Int) async throws {
        let content = UNMutableNotificationContent()
        content.title = L10n.localized("Daily Goal", comment: "Notification title for daily goal reminder")
        content.body = L10n.localized("Keep moving to reach your step goal today.", comment: "Notification body for daily goal reminder")
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: AppConstants.Notifications.dailyGoalReminder,
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }

    func cancelDailyGoalReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [AppConstants.Notifications.dailyGoalReminder])
    }
}
