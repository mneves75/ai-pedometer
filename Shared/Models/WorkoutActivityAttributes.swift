#if os(iOS) && canImport(ActivityKit)
import ActivityKit
import Foundation

struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var steps: Int
        var distance: Double
        var calories: Double
    }

    var workoutType: String

    var workoutDisplayName: String {
        WorkoutType(rawValue: workoutType)?.displayName ?? workoutType
    }
}
#endif
