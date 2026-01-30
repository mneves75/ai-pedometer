import Foundation

struct SharedStepData: Codable, Sendable {
    let todaySteps: Int
    let goalSteps: Int
    let goalProgress: Double
    let currentStreak: Int
    let lastUpdated: Date
    let weeklySteps: [Int]

    var isStale: Bool {
        Date.now.timeIntervalSince(lastUpdated) > 3600
    }
}
