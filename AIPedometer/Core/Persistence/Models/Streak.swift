import Foundation
import SwiftData

@Model
final class Streak {
    var startDate: Date
    var endDate: Date?
    var currentCount: Int
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    init(
        startDate: Date,
        endDate: Date? = nil,
        currentCount: Int,
        isActive: Bool,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.currentCount = currentCount
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
