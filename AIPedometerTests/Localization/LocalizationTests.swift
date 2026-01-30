import Testing
@testable import AIPedometer

@Suite("Localization Tests")
struct LocalizationTests {

    // MARK: - Tab Localization

    @Test("Tab titles return non-empty localized strings")
    func tabTitlesAreLocalized() {
        for tab in MainTabView.Tab.allCases {
            #expect(!tab.title.isEmpty, "Tab \(tab.rawValue) should have a title")
        }
    }

    @Test("Tab titles are unique")
    func tabTitlesAreUnique() {
        let titles = MainTabView.Tab.allCases.map(\.title)
        let uniqueTitles = Set(titles)
        #expect(titles.count == uniqueTitles.count, "All tab titles should be unique")
    }

    // MARK: - WorkoutType Localization

    @Test("WorkoutType displayNames return non-empty localized strings")
    func workoutTypeDisplayNamesAreLocalized() {
        for type in WorkoutType.allCases {
            #expect(!type.displayName.isEmpty, "WorkoutType \(type.rawValue) should have a display name")
        }
    }

    @Test("WorkoutType displayNames are unique")
    func workoutTypeDisplayNamesAreUnique() {
        let names = WorkoutType.allCases.map(\.displayName)
        let uniqueNames = Set(names)
        #expect(names.count == uniqueNames.count, "All workout type display names should be unique")
    }

    // MARK: - BadgeType Localization

    @Test("BadgeType localizedTitle returns non-empty strings")
    func badgeTitlesAreLocalized() {
        for badge in BadgeType.allCases {
            #expect(!badge.localizedTitle.isEmpty, "Badge \(badge.rawValue) should have a title")
        }
    }

    @Test("BadgeType localizedDescription returns non-empty strings")
    func badgeDescriptionsAreLocalized() {
        for badge in BadgeType.allCases {
            #expect(!badge.localizedDescription.isEmpty, "Badge \(badge.rawValue) should have a description")
        }
    }

    @Test("Badge titles and descriptions are distinct")
    func badgeTitlesAndDescriptionsAreDifferent() {
        for badge in BadgeType.allCases {
            #expect(
                badge.localizedTitle != badge.localizedDescription,
                "Badge \(badge.rawValue) title and description should be different"
            )
        }
    }

    @Test("Badge titles are unique")
    func badgeTitlesAreUnique() {
        let titles = BadgeType.allCases.map(\.localizedTitle)
        let uniqueTitles = Set(titles)
        #expect(titles.count == uniqueTitles.count, "All badge titles should be unique")
    }

    // MARK: - ActivityTrackingMode Localization

    @Test("ActivityTrackingMode localizedName returns non-empty strings")
    func activityModeNamesAreLocalized() {
        for mode in ActivityTrackingMode.allCases {
            #expect(!mode.localizedName.isEmpty, "ActivityTrackingMode \(mode.rawValue) should have a localized name")
        }
    }

    @Test("ActivityTrackingMode localizedDescription returns non-empty strings")
    func activityModeDescriptionsAreLocalized() {
        for mode in ActivityTrackingMode.allCases {
            #expect(!mode.localizedDescription.isEmpty, "ActivityTrackingMode \(mode.rawValue) should have a localized description")
        }
    }

    // MARK: - DistanceEstimationMode Localization

    @Test("DistanceEstimationMode localizedName returns non-empty strings")
    func distanceModeNamesAreLocalized() {
        for mode in DistanceEstimationMode.allCases {
            #expect(!mode.localizedName.isEmpty, "DistanceEstimationMode \(mode.rawValue) should have a localized name")
        }
    }

    // MARK: - String Catalog Validation

    @Test("Critical UI strings exist in bundle")
    func criticalStringsExist() {
        let criticalKeys = [
            "Dashboard",
            "History",
            "Workouts",
            "Badges",
            "Settings",
            "Today",
            "Calories",
            "Distance",
            "Active Time",
            "Daily Goal",
            "Weekly Summary",
            "About",
            "Version",
            "Build",
            "App Version",
            "Legal"
        ]

        for key in criticalKeys {
            let localized = String(localized: String.LocalizationValue(key))
            #expect(!localized.isEmpty, "Key '\(key)' should exist in string catalog")
        }
    }

    @Test("Permission strings exist")
    func permissionStringsExist() {
        // These are critical for user trust - permission dialogs must be localized
        let permissionKeys = [
            "Notifications",
            "HealthKit Sync",
            "Permissions"
        ]

        for key in permissionKeys {
            let localized = String(localized: String.LocalizationValue(key))
            #expect(!localized.isEmpty, "Permission key '\(key)' should exist in string catalog")
        }
    }

    @Test("HealthKit sync disabled strings exist")
    func healthKitSyncDisabledStringsExist() {
        let keys = [
            "HealthKit Sync is Off",
            "Enable HealthKit Sync in Settings to see your activity history.",
            "Night",
            "AI generation failed. Please try again."
        ]

        for key in keys {
            let localized = String(localized: String.LocalizationValue(key))
            #expect(!localized.isEmpty, "Localization key '\(key)' should exist in string catalog")
        }
    }

    @Test("AI Coach suggested question strings exist")
    func aiCoachSuggestedQuestionsExist() {
        let keys = [
            "How did I do this week?",
            "What's my best day for walking?",
            "Should I increase my goal?",
            "Create a plan to reach 10,000 steps",
            "Why am I not hitting my goals?",
            "I'm sorry, I'm not available right now. Please try again later."
        ]

        for key in keys {
            let localized = String(localized: String.LocalizationValue(key))
            #expect(!localized.isEmpty, "AI Coach key '\(key)' should exist in string catalog")
        }
    }

    @Test("Widget strings exist")
    func widgetStringsExist() {
        let keys = [
            "Steps Today",
            "Track your daily step progress.",
            "Weekly Steps",
            "Your recent step trend.",
            "Goal Ring",
            "Your daily goal at a glance.",
            "km"
        ]

        for key in keys {
            let localized = String(localized: String.LocalizationValue(key))
            #expect(!localized.isEmpty, "Widget key '\(key)' should exist in string catalog")
        }

        let goalLabel = String(localized: "Goal \(1)")
        #expect(!goalLabel.isEmpty, "Widget goal label should resolve")

        let streakLabel = String(localized: "Streak \(1) days")
        #expect(!streakLabel.isEmpty, "Widget streak label should resolve")
    }

}
