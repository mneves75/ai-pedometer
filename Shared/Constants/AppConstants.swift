import Foundation

enum AppConstants {
    static let appGroupID = "group.com.mneves.aipedometer"
    static let bundleIdentifier = "com.mneves.aipedometer"
    static var appStoreID: String { resolveAppStoreID() }
    private static let placeholderAppStoreID = "123456789"
    static let defaultDailyGoal = 10_000
    static let maxHistoryDays = 365

    static func resolveAppStoreID(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let envValue = environment["APP_STORE_ID"], !envValue.isEmpty {
            return envValue
        }
        if let value = bundle.object(forInfoDictionaryKey: "AppStoreID") as? String,
           !value.isEmpty {
            if value.contains("$(") {
                return placeholderAppStoreID
            }
            return value
        }
        return placeholderAppStoreID
    }

    static var isValidAppStoreID: Bool {
        guard appStoreID != placeholderAppStoreID else { return false }
        return appStoreID.count >= 8 && appStoreID.allSatisfy(\.isNumber)
    }

    static var appStoreReviewURL: URL? {
        guard isValidAppStoreID else { return nil }
        return URL(string: "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review")
    }

    enum AppStoreReviewAction: Equatable {
        case openURL(URL)
        case requestInApp
    }

    static func reviewAction(appStoreURL: URL?) -> AppStoreReviewAction {
        guard let url = appStoreURL else {
            return .requestInApp
        }
        return .openURL(url)
    }

    enum Metrics {
        static let averageStepLengthKm = 0.000762
        static let averageStepLengthMeters = 0.762
        static let caloriesPerStep = 0.04
    }

    enum UserDefaultsKeys {
        static let dailyGoal = "dailyGoal"
        static let lastSyncDate = "lastSyncDate"
        static let todaySteps = "todaySteps"
        static let currentStreak = "currentStreak"
        static let onboardingCompleted = "onboardingCompleted"
        static let sharedStepData = "sharedStepData"
        static let lastWidgetRefresh = "lastWidgetRefresh"
        static let activityTrackingMode = "activityTrackingMode"
        static let distanceEstimationMode = "distanceEstimationMode"
        static let manualStepLengthMeters = "manualStepLengthMeters"
        static let healthKitSyncEnabled = "healthKitSyncEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let smartRemindersEnabled = "smartRemindersEnabled"
        static let smartNotificationLastDate = "smartNotificationLastDate"
        static let smartNotificationCount = "smartNotificationCount"
    }

    enum Defaults {
        static let manualStepLengthMeters: Double = 0.762
    }

    enum TipJar {
        static let productID = "com.mneves.aipedometer.coffee"
    }

    enum BackgroundTaskIdentifiers {
        static let refresh = "com.mneves.aipedometer.refresh"
        static let processing = "com.mneves.aipedometer.processing"
    }

    enum Notifications {
        static let dailyGoalReminder = "daily_goal_reminder"
        static let defaultDailyReminderHour = 20
        static let defaultDailyReminderMinute = 0
        static let defaultSmartReminderHour = 9
        static let defaultSmartReminderMinute = 0
    }
}
