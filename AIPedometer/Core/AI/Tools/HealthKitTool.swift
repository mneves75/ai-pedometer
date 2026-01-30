import Foundation
import FoundationModels

struct HealthKitDataTool: Tool, Sendable {
    let name = "fetchActivityData"
    let description = "Fetches user's step count, distance, floors, and activity data for a specified number of days"
    
    private let healthKitService: any HealthKitServiceProtocol
    private let goalService: GoalService
    private let userDefaultsSuiteName: String?
    
    @MainActor
    init(
        healthKitService: any HealthKitServiceProtocol,
        goalService: GoalService,
        userDefaultsSuiteName: String? = nil
    ) {
        self.healthKitService = healthKitService
        self.goalService = goalService
        self.userDefaultsSuiteName = userDefaultsSuiteName
    }
    
    @Generable
    struct Arguments: Sendable {
        @Guide(description: "Number of days to fetch data for, between 1 and 90", .range(1...90))
        let days: Int
    }
    
    func call(arguments: Arguments) async throws -> String {
        let defaults = userDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        guard HealthKitSyncSettings.isEnabled(userDefaults: defaults) else {
            Loggers.sync.info("healthkit.fetch_skipped", metadata: [
                "reason": "sync_disabled",
                "scope": "ai_tool"
            ])
            let title = String(
                localized: "HealthKit Sync is Off",
                comment: "AI tool response title when HealthKit sync is disabled"
            )
            let detail = String(
                localized: "Enable HealthKit Sync in Settings to see your activity history.",
                comment: "AI tool response detail when HealthKit sync is disabled"
            )
            return "\(title). \(detail)"
        }
        let settings = ActivitySettings.current(userDefaults: defaults)
        let dailyGoal = await MainActor.run { goalService.currentGoal }
        let summaries = try await healthKitService.fetchDailySummaries(
            days: arguments.days,
            activityMode: settings.activityMode,
            distanceMode: settings.distanceMode,
            manualStepLength: settings.manualStepLength,
            dailyGoal: dailyGoal
        )
        return formatSummaries(summaries, unitName: settings.activityMode.unitName)
    }
    
    private func formatSummaries(_ summaries: [DailyStepSummary], unitName: String) -> String {
        guard !summaries.isEmpty else {
            return "No activity data available for the requested period."
        }
        
        let lines = summaries.map { summary in
            let goalStatus = summary.steps >= summary.goal ? "Goal Met" : "Goal Not Met"
            let distanceKm = summary.distance / 1000
            return """
            Date: \(summary.date.formatted(date: .abbreviated, time: .omitted))
            \(unitName.capitalized): \(summary.steps.formatted())
            Distance: \(String(format: "%.1f", distanceKm)) km
            Floors: \(summary.floors)
            Calories: \(Int(summary.calories))
            Goal: \(summary.goal.formatted()) \(unitName)
            Status: \(goalStatus)
            """
        }
        
        return lines.joined(separator: "\n---\n")
    }
}

struct GoalDataTool: Tool, Sendable {
    let name = "fetchGoalData"
    let description = "Fetches user's current daily step goal"
    
    private let goalService: GoalService
    private let userDefaultsSuiteName: String?
    
    @MainActor
    init(goalService: GoalService, userDefaultsSuiteName: String? = nil) {
        self.goalService = goalService
        self.userDefaultsSuiteName = userDefaultsSuiteName
    }
    
    @Generable
    struct Arguments: Sendable {}
    
    func call(arguments: Arguments) async throws -> String {
        let defaults = userDefaultsSuiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        let unitName = ActivitySettings.current(userDefaults: defaults).activityMode.unitName
        let currentGoal = await MainActor.run { goalService.currentGoal }
        return "Current daily goal: \(currentGoal.formatted()) \(unitName)"
    }
}

struct StreakDataTool: Tool {
    let name = "fetchStreakData"
    let description = "Fetches user's current streak information"
    private let suiteName: String?

    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }
    
    @Generable
    struct Arguments: Sendable {}
    
    func call(arguments: Arguments) async throws -> String {
        let userDefaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .shared
        let currentStreak = await MainActor.run {
            userDefaults.sharedStepData?.currentStreak ?? 0
        }
        return "Current streak: \(currentStreak) days"
    }
}
