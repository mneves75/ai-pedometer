import Foundation
import SwiftData

@Model
final class StepGoal {
    var dailySteps: Int
    var startDate: Date
    var endDate: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        dailySteps: Int,
        startDate: Date,
        endDate: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.dailySteps = dailySteps
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
