import Foundation

enum ActivityTrackingMode: String, Codable, CaseIterable, Sendable {
    case steps
    case wheelchairPushes

    var localizedName: String {
        switch self {
        case .steps:
            L10n.localized("Count Steps", comment: "Activity tracking mode: counting walking steps")
        case .wheelchairPushes:
            L10n.localized("Count Pushes", comment: "Activity tracking mode: counting wheelchair pushes")
        }
    }

    var localizedDescription: String {
        switch self {
        case .steps:
            L10n.localized("Track your daily walking steps", comment: "Steps mode description")
        case .wheelchairPushes:
            L10n.localized("Use Apple Watch to measure daily wheelchair pushes instead of steps", comment: "Wheelchair mode description")
        }
    }

    /// Accessibility value for a daily progress ring, shared by the watch and the goal-ring widget.
    func progressAccessibilityValue(count: Int, goal: Int, percent: Int) -> String {
        switch self {
        case .steps:
            Localization.format(
                "%@ steps of %@ goal, %lld percent",
                comment: "Accessibility value for daily progress ring",
                count.formatted(),
                goal.formatted(),
                Int64(percent)
            )
        case .wheelchairPushes:
            Localization.format(
                "%@ of %@ %@",
                comment: "Accessibility value for daily progress with current and goal counts",
                count.formatted(),
                goal.formatted(),
                unitName
            )
        }
    }

    var unitName: String {
        switch self {
        case .steps:
            L10n.localized("steps", comment: "Unit name for steps")
        case .wheelchairPushes:
            L10n.localized("pushes", comment: "Unit name for wheelchair pushes")
        }
    }

    var iconName: String {
        switch self {
        case .steps:
            "figure.walk"
        case .wheelchairPushes:
            "figure.roll"
        }
    }
}
