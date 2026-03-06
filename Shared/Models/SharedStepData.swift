import Foundation

struct SharedStepData: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let todaySteps: Int
    let goalSteps: Int
    let goalProgress: Double
    let currentStreak: Int
    let lastUpdated: Date
    let weeklySteps: [Int]

    init(
        todaySteps: Int,
        goalSteps: Int,
        goalProgress: Double,
        currentStreak: Int,
        lastUpdated: Date,
        weeklySteps: [Int],
        schemaVersion: Int = SharedStepData.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.todaySteps = todaySteps
        self.goalSteps = goalSteps
        self.goalProgress = goalProgress
        self.currentStreak = currentStreak
        self.lastUpdated = lastUpdated
        self.weeklySteps = weeklySteps
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case todaySteps
        case goalSteps
        case goalProgress
        case currentStreak
        case lastUpdated
        case weeklySteps
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        todaySteps = try container.decode(Int.self, forKey: .todaySteps)
        goalSteps = try container.decode(Int.self, forKey: .goalSteps)
        goalProgress = try container.decode(Double.self, forKey: .goalProgress)
        currentStreak = try container.decode(Int.self, forKey: .currentStreak)
        lastUpdated = try container.decode(Date.self, forKey: .lastUpdated)
        weeklySteps = try container.decode([Int].self, forKey: .weeklySteps)
    }

    var isStale: Bool {
        isStale(referenceDate: .now)
    }

    func isStale(referenceDate: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        guard calendar.isDate(lastUpdated, inSameDayAs: referenceDate) else { return true }
        let age = referenceDate.timeIntervalSince(lastUpdated)
        return !(0...3600).contains(age)
    }
}
