import Foundation

// Centralized accessibility identifiers used by the app (and by UI tests via
// string literals kept in sync).
enum A11yID {
    static let mainTabBar = "main_tab_bar"
    static let mainSplitView = "main_split_view"

    static func tab(_ rawValue: String) -> String { "tab_\(rawValue)" }

    enum Dashboard {
        static let view = "dashboard_view"
        static func steps(_ steps: Int) -> String { "dashboard_steps_\(steps)" }
        static func goal(_ goal: Int) -> String { "dashboard_goal_\(goal)" }
    }

    enum History {
        static let marker = "history_view"
        static func todaySteps(_ steps: Int) -> String { "history_today_steps_\(steps)" }
        static func syncEnabled(_ enabled: Bool) -> String { "history_sync_enabled_\(enabled ? 1 : 0)" }
        static let syncOffLabel = "history_healthkit_sync_off_label"
        static let syncOffView = "history_sync_off_view"
        static let healthAccessNeededView = "history_health_access_needed_view"
    }

    enum Workouts {
        static let scroll = "workouts_scroll"
        static let startWorkoutButton = "workouts_start_workout_button"
        static let activeWorkoutBanner = "workouts_active_workout_banner"
        static let trainingPlansCard = "training_plans_card"
    }

    enum TrainingPlans {
        static let marker = "training_plans_screen"
        static let createButton = "training_plans_create_button"
    }

    enum ActiveWorkout {
        static let view = "active_workout_view"
        static let endButton = "active_workout_end_button"
    }

    enum More {
        static let marker = "more_view"
        static let list = "more_list"
        static let badgesRow = "more_badges_row"
        static let badgesRowLabel = "more_badges_row_label"
        static let supportRow = "more_support_row"
        static let supportRowLabel = "more_support_row_label"
        static let settingsRow = "more_settings_row"
        static let settingsRowLabel = "more_settings_row_label"
    }

    enum Badges {
        static let marker = "badges_view"
        static let list = "badges_list"
    }

    enum Settings {
        static let marker = "settings_view"
        static let list = "settings_list"
        static let dailyGoalRow = "settings_daily_goal_row"
        static let healthAccessRow = "settings_health_access_row"
        static let healthKitSyncToggle = "healthkit_sync_toggle"
        static let demoFakeDataToggle = "demo_fake_data_toggle"
        static let aboutRow = "about_row"
        static let notificationsToggle = "notifications_enabled_toggle"
        static let smartNotificationsToggle = "smart_notifications_enabled_toggle"
    }

    enum GoalEditor {
        static let slider = "goal_editor_slider"
        static let value = "goal_editor_value"
        static let saveButton = "goal_editor_save_button"
    }

    enum About {
        static let view = "about_view"
        static let tipJarCoffeeButton = "tipjar_coffee_button"
    }

    enum AICoach {
        static let view = "ai_coach_view"
        static let marker = "ai_coach_marker"
    }

    enum HealthAccessHelp {
        static let view = "health_access_help_view"
        static let doneButton = "health_access_help_done_button"
        static let grantAccessButton = "health_access_help_grant_access_button"
    }
}
