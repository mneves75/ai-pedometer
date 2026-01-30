import Foundation
import SwiftData

@Model
final class DailyStepRecord {
    @Attribute(.unique) var date: Date
    var steps: Int
    var distance: Double
    var floorsAscended: Int
    var floorsDescended: Int
    var activeCalories: Double
    var goalSteps: Int
    var sourceRaw: String
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        date: Date,
        steps: Int,
        distance: Double,
        floorsAscended: Int,
        floorsDescended: Int,
        activeCalories: Double,
        goalSteps: Int,
        source: StepSource,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.date = date
        self.steps = steps
        self.distance = distance
        self.floorsAscended = floorsAscended
        self.floorsDescended = floorsDescended
        self.activeCalories = activeCalories
        self.goalSteps = goalSteps
        self.sourceRaw = source.rawValue
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    var source: StepSource {
        StepSource(rawValue: sourceRaw) ?? .combined
    }
}
