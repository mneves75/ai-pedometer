import Foundation

struct BadgeDefinition: Sendable {
    let type: BadgeType
    let title: String
    let description: String
    let requiredValue: Int
}

enum BadgeDefinitions {
    static let all: [BadgeDefinition] = [
        BadgeDefinition(type: .steps5K, title: BadgeType.steps5K.localizedTitle, description: BadgeType.steps5K.localizedDescription, requiredValue: 5_000),
        BadgeDefinition(type: .steps10K, title: BadgeType.steps10K.localizedTitle, description: BadgeType.steps10K.localizedDescription, requiredValue: 10_000),
        BadgeDefinition(type: .steps15K, title: BadgeType.steps15K.localizedTitle, description: BadgeType.steps15K.localizedDescription, requiredValue: 15_000),
        BadgeDefinition(type: .steps20K, title: BadgeType.steps20K.localizedTitle, description: BadgeType.steps20K.localizedDescription, requiredValue: 20_000),
        BadgeDefinition(type: .steps25K, title: BadgeType.steps25K.localizedTitle, description: BadgeType.steps25K.localizedDescription, requiredValue: 25_000),
        BadgeDefinition(type: .streak3, title: BadgeType.streak3.localizedTitle, description: BadgeType.streak3.localizedDescription, requiredValue: 3),
        BadgeDefinition(type: .streak7, title: BadgeType.streak7.localizedTitle, description: BadgeType.streak7.localizedDescription, requiredValue: 7),
        BadgeDefinition(type: .streak14, title: BadgeType.streak14.localizedTitle, description: BadgeType.streak14.localizedDescription, requiredValue: 14),
        BadgeDefinition(type: .streak30, title: BadgeType.streak30.localizedTitle, description: BadgeType.streak30.localizedDescription, requiredValue: 30),
        BadgeDefinition(type: .streak100, title: BadgeType.streak100.localizedTitle, description: BadgeType.streak100.localizedDescription, requiredValue: 100),
        BadgeDefinition(type: .streak365, title: BadgeType.streak365.localizedTitle, description: BadgeType.streak365.localizedDescription, requiredValue: 365)
    ]
}
