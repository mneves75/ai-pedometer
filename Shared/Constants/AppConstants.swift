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
        static let expeditionModeEnabled = "expeditionModeEnabled"
        static let importedGPXRoute = "importedGPXRoute"
    }

    enum Defaults {
        static let manualStepLengthMeters: Double = 0.762
    }

    enum TipJar {
        static let productID = "com.mneves.aipedometer.coffee"
    }

    struct RevenueCatConfiguration: Sendable, Equatable {
        let apiKey: String?
        let entitlementID: String
        let offeringID: String?

        var isConfigured: Bool {
            guard let apiKey else { return false }
            return !apiKey.isEmpty
        }
    }

    enum RevenueCat {
        private static let placeholderAPIKey = "REVENUECAT_API_KEY"
        private static let placeholderEntitlementID = "premium"

        static func resolveConfiguration(
            bundle: Bundle = .main,
            environment: [String: String] = ProcessInfo.processInfo.environment,
            allowsEnvironmentOverrides: Bool = environmentOverridesEnabled,
            allowsTestStoreAPIKeys: Bool = testStoreAPIKeysEnabled
        ) -> RevenueCatConfiguration {
            var resolvedKey = resolveValue(
                environmentKey: "REVENUECAT_API_KEY",
                infoDictionaryKey: "RevenueCatAPIKey",
                placeholder: placeholderAPIKey,
                bundle: bundle,
                environment: environment,
                allowsEnvironmentOverrides: allowsEnvironmentOverrides
            )

            // RevenueCat deliberately fatalErrors when configured with a Test Store ("test_")
            // key in a non-DEBUG build; resolve such keys to nil so premium fails closed instead.
            if !allowsTestStoreAPIKeys, let key = resolvedKey, key.hasPrefix(testStoreAPIKeyPrefix) {
                resolvedKey = nil
            }

            return RevenueCatConfiguration(
                apiKey: resolvedKey,
                entitlementID: resolveValue(
                    environmentKey: "REVENUECAT_ENTITLEMENT_ID",
                    infoDictionaryKey: "RevenueCatEntitlementID",
                    placeholder: placeholderEntitlementID,
                    bundle: bundle,
                    environment: environment,
                    allowsEnvironmentOverrides: allowsEnvironmentOverrides
                ) ?? placeholderEntitlementID,
                offeringID: resolveValue(
                    environmentKey: "REVENUECAT_OFFERING_ID",
                    infoDictionaryKey: "RevenueCatOfferingID",
                    placeholder: "",
                    bundle: bundle,
                    environment: environment,
                    allowsEnvironmentOverrides: allowsEnvironmentOverrides
                )
            )
        }

        static var environmentOverridesEnabled: Bool {
            #if DEBUG
            true
            #else
            false
            #endif
        }

        private static let testStoreAPIKeyPrefix = "test_"

        static var testStoreAPIKeysEnabled: Bool {
            #if DEBUG
            true
            #else
            false
            #endif
        }

        private static func resolveValue(
            environmentKey: String,
            infoDictionaryKey: String,
            placeholder: String,
            bundle: Bundle,
            environment: [String: String],
            allowsEnvironmentOverrides: Bool
        ) -> String? {
            if allowsEnvironmentOverrides,
               let envValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !envValue.isEmpty,
               envValue != placeholder {
                return envValue
            }

            if let bundleValue = bundle.object(forInfoDictionaryKey: infoDictionaryKey) as? String {
                let trimmed = bundleValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty, !trimmed.contains("$("), trimmed != placeholder {
                    return trimmed
                }
            }

            return nil
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
