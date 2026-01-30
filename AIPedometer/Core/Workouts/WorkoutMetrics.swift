import Foundation

struct WorkoutMetrics: Equatable, Sendable {
    var steps: Int
    var distance: Double
    var calories: Double
    var startTime: Date
    var lastUpdated: Date
    var targetSteps: Int?

    static func initial(startTime: Date, targetSteps: Int?) -> WorkoutMetrics {
        WorkoutMetrics(
            steps: 0,
            distance: 0,
            calories: 0,
            startTime: startTime,
            lastUpdated: startTime,
            targetSteps: targetSteps
        )
    }

    var targetProgress: Double? {
        guard let targetSteps, targetSteps > 0 else { return nil }
        return min(max(Double(steps) / Double(targetSteps), 0), 1)
    }
}
