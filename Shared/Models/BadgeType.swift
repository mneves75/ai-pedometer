import Foundation

enum BadgeType: String, Codable, CaseIterable, Sendable {
    case steps5K
    case steps10K
    case steps15K
    case steps20K
    case steps25K
    case streak3
    case streak7
    case streak14
    case streak30
    case streak100
    case streak365
    case distance5km
    case distance10km
    case distanceMarathon
    case monthlyChallenge

    var localizedTitle: String {
        switch self {
        case .steps5K: String(localized: "5K Steps", comment: "Badge title for 5000 steps achievement")
        case .steps10K: String(localized: "10K Steps", comment: "Badge title for 10000 steps achievement")
        case .steps15K: String(localized: "15K Steps", comment: "Badge title for 15000 steps achievement")
        case .steps20K: String(localized: "20K Steps", comment: "Badge title for 20000 steps achievement")
        case .steps25K: String(localized: "25K Steps", comment: "Badge title for 25000 steps achievement")
        case .streak3: String(localized: "3-Day Streak", comment: "Badge title for 3 day goal streak")
        case .streak7: String(localized: "Week Warrior", comment: "Badge title for 7 day goal streak")
        case .streak14: String(localized: "Two Week Champion", comment: "Badge title for 14 day goal streak")
        case .streak30: String(localized: "Monthly Master", comment: "Badge title for 30 day goal streak")
        case .streak100: String(localized: "Century Club", comment: "Badge title for 100 day goal streak")
        case .streak365: String(localized: "Year of Excellence", comment: "Badge title for 365 day goal streak")
        case .distance5km: String(localized: "5K Distance", comment: "Badge title for 5km total distance")
        case .distance10km: String(localized: "10K Distance", comment: "Badge title for 10km total distance")
        case .distanceMarathon: String(localized: "Marathoner", comment: "Badge title for marathon distance")
        case .monthlyChallenge: String(localized: "Monthly Challenge", comment: "Badge title for monthly challenge completion")
        }
    }

    var localizedDescription: String {
        switch self {
        case .steps5K: String(localized: "Walk 5,000 steps in a day", comment: "Badge description for 5K steps")
        case .steps10K: String(localized: "Walk 10,000 steps in a day", comment: "Badge description for 10K steps")
        case .steps15K: String(localized: "Walk 15,000 steps in a day", comment: "Badge description for 15K steps")
        case .steps20K: String(localized: "Walk 20,000 steps in a day", comment: "Badge description for 20K steps")
        case .steps25K: String(localized: "Walk 25,000 steps in a day", comment: "Badge description for 25K steps")
        case .streak3: String(localized: "Reach your goal 3 days in a row", comment: "Badge description for 3-day streak")
        case .streak7: String(localized: "Reach your goal 7 days in a row", comment: "Badge description for 7-day streak")
        case .streak14: String(localized: "Reach your goal 14 days in a row", comment: "Badge description for 14-day streak")
        case .streak30: String(localized: "Reach your goal 30 days in a row", comment: "Badge description for 30-day streak")
        case .streak100: String(localized: "Reach your goal 100 days in a row", comment: "Badge description for 100-day streak")
        case .streak365: String(localized: "Reach your goal every day for a year", comment: "Badge description for 365-day streak")
        case .distance5km: String(localized: "Walk a total of 5 kilometers", comment: "Badge description for 5km distance")
        case .distance10km: String(localized: "Walk a total of 10 kilometers", comment: "Badge description for 10km distance")
        case .distanceMarathon: String(localized: "Walk a total of 42.195 kilometers", comment: "Badge description for marathon distance")
        case .monthlyChallenge: String(localized: "Complete a monthly challenge", comment: "Badge description for monthly challenge")
        }
    }
}

enum BadgeCategory: String, Sendable {
    case steps
    case streak
    case distance
    case challenge
}

extension BadgeType {
    var category: BadgeCategory {
        switch self {
        case .steps5K, .steps10K, .steps15K, .steps20K, .steps25K:
            return .steps
        case .streak3, .streak7, .streak14, .streak30, .streak100, .streak365:
            return .streak
        case .distance5km, .distance10km, .distanceMarathon:
            return .distance
        case .monthlyChallenge:
            return .challenge
        }
    }
}
