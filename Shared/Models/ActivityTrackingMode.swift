import Foundation

enum ActivityTrackingMode: String, Codable, CaseIterable, Sendable {
    case steps
    case wheelchairPushes

    var localizedName: String {
        switch self {
        case .steps:
            String(localized: "Count Steps", comment: "Activity tracking mode: counting walking steps")
        case .wheelchairPushes:
            String(localized: "Count Pushes", comment: "Activity tracking mode: counting wheelchair pushes")
        }
    }

    var localizedDescription: String {
        switch self {
        case .steps:
            String(localized: "Track your daily walking steps", comment: "Steps mode description")
        case .wheelchairPushes:
            String(localized: "Use Apple Watch to measure daily wheelchair pushes instead of steps", comment: "Wheelchair mode description")
        }
    }

    var unitName: String {
        switch self {
        case .steps:
            String(localized: "steps", comment: "Unit name for steps")
        case .wheelchairPushes:
            String(localized: "pushes", comment: "Unit name for wheelchair pushes")
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
