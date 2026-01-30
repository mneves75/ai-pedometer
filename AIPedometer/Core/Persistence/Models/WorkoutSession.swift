import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var typeRaw: String
    var startTime: Date
    var endTime: Date?
    var steps: Int
    var distance: Double
    var activeCalories: Double
    var routeData: Data?
    var healthKitWorkoutID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        type: WorkoutType,
        startTime: Date,
        endTime: Date? = nil,
        steps: Int = 0,
        distance: Double = 0,
        activeCalories: Double = 0,
        routeData: Data? = nil,
        healthKitWorkoutID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.typeRaw = type.rawValue
        self.startTime = startTime
        self.endTime = endTime
        self.steps = steps
        self.distance = distance
        self.activeCalories = activeCalories
        self.routeData = routeData
        self.healthKitWorkoutID = healthKitWorkoutID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var type: WorkoutType {
        WorkoutType(rawValue: typeRaw) ?? .outdoorWalk
    }
}
