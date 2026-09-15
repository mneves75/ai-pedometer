import Foundation

struct BadgeDefinition: Sendable {
    let type: BadgeType
    let requiredValue: Int
}

enum BadgeDefinitions {
    static let all: [BadgeDefinition] = [
        BadgeDefinition(type: .steps5K, requiredValue: 5_000),
        BadgeDefinition(type: .steps10K, requiredValue: 10_000),
        BadgeDefinition(type: .steps15K, requiredValue: 15_000),
        BadgeDefinition(type: .steps20K, requiredValue: 20_000),
        BadgeDefinition(type: .steps25K, requiredValue: 25_000),
        BadgeDefinition(type: .streak3, requiredValue: 3),
        BadgeDefinition(type: .streak7, requiredValue: 7),
        BadgeDefinition(type: .streak14, requiredValue: 14),
        BadgeDefinition(type: .streak30, requiredValue: 30),
        BadgeDefinition(type: .streak100, requiredValue: 100),
        BadgeDefinition(type: .streak365, requiredValue: 365),
        // Distance thresholds are in meters, matched against the day's walking/running distance.
        // 42_195 (marathon) fits in a 32-bit Int, so this stays safe on the watchOS arm64_32 slice.
        BadgeDefinition(type: .distance5km, requiredValue: 5_000),
        BadgeDefinition(type: .distance10km, requiredValue: 10_000),
        BadgeDefinition(type: .distanceMarathon, requiredValue: 42_195)
    ]
}
