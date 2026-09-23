import Foundation

enum AppConstants {
    static let appGroupID = "group.com.mneves.aipedometer"
    static let bundleIdentifier = "com.mneves.aipedometer"
    static var appStoreID: String { resolveAppStoreID() }
    private static let placeholderAppStoreID = "123456789"
    static let defaultDailyGoal = 10_000

    static func resolveAppStoreID(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        allowsEnvironmentOverrides: Bool = LaunchConfiguration.isOverridable
    ) -> String {
        // Launch environment is attacker input in Release (anyone with devicectl access sets it), so
        // it may only redirect the review link in Debug, like every other launch override.
        if allowsEnvironmentOverrides, let envValue = environment["APP_STORE_ID"], !envValue.isEmpty {
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
        static let activityTrackingMode = "activityTrackingMode"
        static let distanceEstimationMode = "distanceEstimationMode"
        static let manualStepLengthMeters = "manualStepLengthMeters"
        static let healthKitSyncEnabled = "healthKitSyncEnabled"
        static let notificationsEnabled = "notificationsEnabled"
        static let smartRemindersEnabled = "smartRemindersEnabled"
        static let smartNotificationLastDate = "smartNotificationLastDate"
        static let smartNotificationCount = "smartNotificationCount"
        static let expeditionModeEnabled = "expeditionModeEnabled"
        static let importedGPXRoute = "importedGPXRoute"
    }

    enum Defaults {
        static let manualStepLengthMeters: Double = 0.762
    }

    enum TipJar {
        static let productID = "com.mneves.aipedometer.coffee"
    }

    /// Public pages App Review and users reach from inside the app. They must match the Privacy
    /// Policy and Support URLs of the App Store listing (`store/app-store/`), in the app language.
    enum Links {
        static let privacyPolicy = privacyPolicy(languageCode: AppLanguage.defaultLanguageCode)
        static let support = support(languageCode: AppLanguage.defaultLanguageCode)

        static func privacyPolicy(languageCode: String) -> URL? {
            sitePage(pt: "privacidade", en: "privacy", languageCode: languageCode)
        }

        static func support(languageCode: String) -> URL? {
            sitePage(pt: "suporte", en: "support", languageCode: languageCode)
        }

        /// Only pt-BR gets the Portuguese page; every other language gets the English one.
        private static func sitePage(pt: String, en: String, languageCode: String) -> URL? {
            let path = AppLanguage.supportedLanguageCode(for: languageCode) == AppLanguage.portugueseBrazilCode
                ? "pt/apps/\(pt)"
                : "en/apps/\(en)"
            return URL(string: "https://www.conhecendotudo.com.br/\(path)/aipedometer/")
        }
    }

    enum BackgroundTaskIdentifiers {
        static let refresh = "com.mneves.aipedometer.refresh"
    }

    enum Notifications {
        static let dailyGoalReminder = "daily_goal_reminder"
        static let defaultDailyReminderHour = 20
        static let defaultDailyReminderMinute = 0
        static let defaultSmartReminderHour = 9
        static let defaultSmartReminderMinute = 0
    }
}
