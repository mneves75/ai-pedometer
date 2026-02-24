import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

enum WorkoutType: String, Codable, CaseIterable, Equatable, Sendable {
    case indoorWalk = "Indoor Walk"
    case outdoorWalk = "Outdoor Walk"
    case indoorRun = "Indoor Run"
    case outdoorRun = "Outdoor Run"
    case hike = "Hike"

    var displayName: String {
        switch self {
        case .indoorWalk: L10n.localized("Indoor Walk", comment: "Workout type: walking indoors")
        case .outdoorWalk: L10n.localized("Outdoor Walk", comment: "Workout type: walking outdoors")
        case .indoorRun: L10n.localized("Indoor Run", comment: "Workout type: running indoors")
        case .outdoorRun: L10n.localized("Outdoor Run", comment: "Workout type: running outdoors")
        case .hike: L10n.localized("Hike", comment: "Workout type: hiking")
        }
    }

    var icon: String {
        switch self {
        case .indoorWalk, .outdoorWalk: "figure.walk"
        case .indoorRun, .outdoorRun: "figure.run"
        case .hike: "figure.hiking"
        }
    }

    #if canImport(HealthKit)
    var healthKitType: HKWorkoutActivityType {
        switch self {
        case .indoorWalk, .outdoorWalk: .walking
        case .indoorRun, .outdoorRun: .running
        case .hike: .hiking
        }
    }
    #endif
}
