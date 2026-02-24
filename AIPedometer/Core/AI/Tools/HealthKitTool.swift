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
        return await formatSummaries(summaries, unitName: settings.activityMode.unitName)
    }
    
    private func formatSummaries(_ summaries: [DailyStepSummary], unitName: String) async -> String {
        guard !summaries.isEmpty else {
            return String(
                localized: "No activity data available for the requested period.",
                comment: "AI tool response when no activity data is available"
            )
        }
        
        let lines = await MainActor.run { summaries.map { summary in
            let goalStatus = summary.steps >= summary.goal
                ? L10n.localized("Goal Met", comment: "AI tool goal status when met")
                : L10n.localized("Goal Not Met", comment: "AI tool goal status when not met")
            let distanceText = Formatters.distanceString(meters: summary.distance)
            let caloriesText = Formatters.caloriesString(summary.calories)
            return """
            \(Localization.format(
                "Date: %@",
                comment: "AI tool summary line for date",
                summary.date.formatted(date: .abbreviated, time: .omitted)
            ))
            \(Localization.format(
                "%@: %@",
                comment: "AI tool summary line for activity unit and value",
                unitName.capitalized,
                summary.steps.formatted()
            ))
            \(Localization.format(
                "Distance: %@",
                comment: "AI tool summary line for distance",
                distanceText
            ))
            \(Localization.format(
                "Floors: %lld",
                comment: "AI tool summary line for floors climbed",
                Int64(summary.floors)
            ))
            \(Localization.format(
                "Calories: %@",
                comment: "AI tool summary line for calories burned",
                caloriesText
            ))
            \(Localization.format(
                "Goal: %@ %@",
                comment: "AI tool summary line for daily goal with unit",
                summary.goal.formatted(),
                unitName
            ))
            \(Localization.format(
                "Status: %@",
                comment: "AI tool summary line for goal status",
                goalStatus
            ))
            """
        } }
        
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
        return Localization.format(
            "Current daily goal: %@ %@",
            comment: "AI tool response for current daily goal",
            currentGoal.formatted(),
            unitName
        )
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
        return Localization.format(
            "Current streak: %lld days",
            comment: "AI tool response for current streak",
            Int64(currentStreak)
        )
    }
}
