import Foundation
import SwiftData

@Model
final class EarnedBadge {
    var badgeRaw: String
    var earnedAt: Date
    var metadata: [String: String]
    var createdAt: Date
    var deletedAt: Date?

    init(
        badgeType: BadgeType,
        earnedAt: Date = .now,
        metadata: [String: String] = [:],
        createdAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.badgeRaw = badgeType.rawValue
        self.earnedAt = earnedAt
        self.metadata = metadata
        self.createdAt = createdAt
        self.deletedAt = deletedAt
    }

    var badgeType: BadgeType {
        BadgeType(rawValue: badgeRaw) ?? .monthlyChallenge
    }
}
