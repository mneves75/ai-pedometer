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
        // Optional so the model never asks the user for a period before it can call the tool.
        @Guide(description: "Past days to fetch, 1 to 90. Omit for the last 7 days.", .range(1...90))
        let days: Int?
    }

    static let defaultDays = 7
    
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
        // `@Guide(.range(1...90))` steers generation; it does not bind the value the model returns.
        let summaries = try await healthKitService.fetchDailySummaries(
            days: min(max(arguments.days ?? Self.defaultDays, 1), 90),
            activityMode: settings.activityMode,
            distanceMode: settings.distanceMode,
            manualStepLength: settings.manualStepLength,
            dailyGoal: dailyGoal
        )
        let summariesWithHistoricalGoals = await MainActor.run {
            summaries.map { summary in
                let resolvedGoal = goalService.goal(forDayContaining: summary.date) ?? dailyGoal
                guard resolvedGoal != summary.goal else { return summary }
                return DailyStepSummary(
                    date: summary.date,
                    steps: summary.steps,
                    distance: summary.distance,
                    floors: summary.floors,
                    calories: summary.calories,
                    goal: resolvedGoal
                )
            }
        }
        return await formatSummaries(summariesWithHistoricalGoals, unitName: settings.activityMode.unitName)
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
                Formatters.stepCountString(summary.steps)
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
                Formatters.stepCountString(summary.goal),
                unitName
            ))
            \(Localization.format(
                "Status: %@",
                comment: "AI tool summary line for goal status",
                goalStatus
            ))
            """
        } }
        
        // The on-device model miscalculates sums and averages, so the app states them.
        let summaryLine = await MainActor.run {
            let total = summaries.reduce(0) { $0 + $1.steps }
            return Localization.format(
                "Last %@ days: total %@ %@, daily average %@ %@, goal met on %@ of them",
                comment: "AI tool summary line before the per-day activity data; the day counts are formatted numbers",
                Formatters.stepCountString(summaries.count),
                Formatters.stepCountString(total),
                unitName,
                Formatters.stepCountString(total / summaries.count),
                unitName,
                Formatters.stepCountString(summaries.filter { $0.steps >= $0.goal }.count)
            )
        }

        return summaryLine + "\n---\n" + lines.joined(separator: "\n---\n")
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
        let currentGoal = await MainActor.run { Formatters.stepCountString(goalService.currentGoal) }
        return Localization.format(
            "Current daily goal: %@ %@",
            comment: "AI tool response for current daily goal",
            currentGoal,
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
        let userDefaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .sharedAppGroup
        let currentStreak = await MainActor.run {
            userDefaults?.sharedStepData?.currentStreak ?? 0
        }
        return Localization.format(
            "Current streak: %lld days",
            comment: "AI tool response for current streak",
            Int64(currentStreak)
        )
    }
}
