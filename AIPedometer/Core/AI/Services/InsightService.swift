import Foundation
import FoundationModels

@MainActor
@Observable
final class InsightService {
    private let foundationModelsService: any FoundationModelsServiceProtocol
    private let healthKitService: any HealthKitServiceProtocol
    private let goalService: GoalService
    private let dataStore: SharedDataStore
    private let userDefaults: UserDefaults
    
    private var cachedDailyInsight: (date: Date, steps: Int, goal: Int, insight: DailyInsight)?
    private var cachedWeeklyAnalysis: (weekStart: Date, analysis: WeeklyTrendAnalysis)?
    private var cachedWorkoutRecommendation: (date: Date, steps: Int, goal: Int, recommendation: AIWorkoutRecommendation)?
    private var lastSeenDay: Date?

    private(set) var isGeneratingDailyInsight = false
    private(set) var isGeneratingWeeklyAnalysis = false
    private var isGeneratingWorkoutRecommendation = false
    private(set) var lastError: AIServiceError?
    
    init(
        foundationModelsService: any FoundationModelsServiceProtocol,
        healthKitService: any HealthKitServiceProtocol,
        goalService: GoalService,
        dataStore: SharedDataStore,
        userDefaults: UserDefaults = .standard
    ) {
        self.foundationModelsService = foundationModelsService
        self.healthKitService = healthKitService
        self.goalService = goalService
        self.dataStore = dataStore
        self.userDefaults = userDefaults
    }
    
    func generateDailyInsight(forceRefresh: Bool = false) async throws(AIServiceError) -> DailyInsight {
        checkDayRolloverAndClearCache()
        let today = Calendar.current.startOfDay(for: Date())
        let todayData = await fetchTodayActivityData()
        
        if !forceRefresh, let cached = cachedDailyInsight {
            if Calendar.current.isDate(cached.date, inSameDayAs: today),
               cached.steps == todayData.steps,
               cached.goal == todayData.goal {
                return cached.insight
            }
        }

        if isGeneratingDailyInsight {
            if let cached = cachedDailyInsight,
               Calendar.current.isDate(cached.date, inSameDayAs: today) {
                return cached.insight
            }
            throw AIServiceError.generationFailed(underlying: "Please try again in a moment")
        }
        
        isGeneratingDailyInsight = true
        lastError = nil
        defer { isGeneratingDailyInsight = false }
        
        let prompt = buildDailyInsightPrompt(data: todayData)

        let signpostState = Signposts.ai.begin("DailyInsight")
        defer { Signposts.ai.end("DailyInsight", signpostState) }

        do {
            let insight: DailyInsight = try await foundationModelsService.respond(
                to: prompt,
                as: DailyInsight.self
            )

            cachedDailyInsight = (today, todayData.steps, todayData.goal, insight)
            Loggers.ai.info("ai.daily_insight_generated")
            return insight
        } catch {
            lastError = error
            Loggers.ai.error("ai.daily_insight_failed", metadata: ["error": error.logDescription])
            throw error
        }
    }
    
    func generateWeeklyAnalysis(forceRefresh: Bool = false) async throws(AIServiceError) -> WeeklyTrendAnalysis {
        checkDayRolloverAndClearCache()
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        
        if !forceRefresh,
           let cached = cachedWeeklyAnalysis,
           calendar.isDate(cached.weekStart, equalTo: weekStart, toGranularity: .weekOfYear) {
            return cached.analysis
        }

        if isGeneratingWeeklyAnalysis {
            if let cached = cachedWeeklyAnalysis,
               calendar.isDate(cached.weekStart, equalTo: weekStart, toGranularity: .weekOfYear) {
                return cached.analysis
            }
            throw AIServiceError.generationFailed(underlying: "Please try again in a moment")
        }
        
        isGeneratingWeeklyAnalysis = true
        lastError = nil
        defer { isGeneratingWeeklyAnalysis = false }
        
        let signpostState = Signposts.ai.begin("WeeklyAnalysis")
        defer { Signposts.ai.end("WeeklyAnalysis", signpostState) }

        do {
            let weekData = try await fetchWeekActivityData()
            if weekData.summaries.isEmpty {
                Loggers.ai.info("ai.weekly_analysis_fallback", metadata: [
                    "reason": "no_data"
                ])
                return fallbackWeeklyAnalysis()
            }
            let prompt = buildWeeklyAnalysisPrompt(data: weekData)

            let analysis: WeeklyTrendAnalysis = try await foundationModelsService.respond(
                to: prompt,
                as: WeeklyTrendAnalysis.self
            )

            cachedWeeklyAnalysis = (weekStart, analysis)
            Loggers.ai.info("ai.weekly_analysis_generated")
            return analysis
        } catch let error as AIServiceError {
            lastError = error
            Loggers.ai.error("ai.weekly_analysis_failed", metadata: ["error": error.logDescription])
            throw error
        } catch {
            let mappedError = AIServiceError.generationFailed(underlying: error.localizedDescription)
            lastError = mappedError
            Loggers.ai.error("ai.weekly_analysis_failed", metadata: ["error": mappedError.logDescription])
            throw mappedError
        }
    }
    
    func generateGoalRecommendation() async throws(AIServiceError) -> GoalRecommendation {
        lastError = nil

        let signpostState = Signposts.ai.begin("GoalRecommendation")
        defer { Signposts.ai.end("GoalRecommendation", signpostState) }

        do {
            let recentData = try await fetchRecentActivityData(days: 14)
            let currentGoal = goalService.currentGoal
            let unitName = ActivitySettings.current(userDefaults: userDefaults).activityMode.unitName
            let prompt = buildGoalRecommendationPrompt(
                data: recentData,
                currentGoal: currentGoal,
                unitName: unitName
            )

            let recommendation: GoalRecommendation = try await foundationModelsService.respond(
                to: prompt,
                as: GoalRecommendation.self
            )

            Loggers.ai.info("ai.goal_recommendation_generated", metadata: [
                "recommended": "\(recommendation.recommendedGoal)",
                "current": "\(currentGoal)"
            ])
            return recommendation
        } catch let error as AIServiceError {
            lastError = error
            throw error
        } catch {
            let mappedError = AIServiceError.generationFailed(underlying: error.localizedDescription)
            lastError = mappedError
            throw mappedError
        }
    }
    
    func generateWorkoutRecommendation(forceRefresh: Bool = false) async throws(AIServiceError) -> AIWorkoutRecommendation {
        lastError = nil

        checkDayRolloverAndClearCache()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayData = await fetchTodayActivityData()
        let currentGoal = goalService.currentGoal

        if !forceRefresh, let cached = cachedWorkoutRecommendation {
            if calendar.isDate(cached.date, inSameDayAs: today),
               cached.steps == todayData.steps,
               cached.goal == currentGoal {
                return cached.recommendation
            }
        }

        if isGeneratingWorkoutRecommendation {
            if let cached = cachedWorkoutRecommendation,
               calendar.isDate(cached.date, inSameDayAs: today) {
                return cached.recommendation
            }
            throw AIServiceError.generationFailed(underlying: "Please try again in a moment")
        }

        isGeneratingWorkoutRecommendation = true
        defer { isGeneratingWorkoutRecommendation = false }

        let signpostState = Signposts.ai.begin("WorkoutRecommendation")
        defer { Signposts.ai.end("WorkoutRecommendation", signpostState) }

        do {
            let weekData = try await fetchWeekActivityData()
            let prompt = buildWorkoutRecommendationPrompt(
                weekData: weekData,
                todayData: todayData,
                currentGoal: currentGoal
            )

            let recommendation: AIWorkoutRecommendation = try await foundationModelsService.respond(
                to: prompt,
                as: AIWorkoutRecommendation.self
            )

            cachedWorkoutRecommendation = (today, todayData.steps, currentGoal, recommendation)
            Loggers.ai.info("ai.workout_recommendation_generated", metadata: [
                "intent": recommendation.intent.rawValue,
                "targetSteps": "\(recommendation.targetSteps)"
            ])
            return recommendation
        } catch let error as AIServiceError {
            lastError = error
            throw error
        } catch {
            let mappedError = AIServiceError.generationFailed(underlying: error.localizedDescription)
            lastError = mappedError
            throw mappedError
        }
    }
    
    func clearCache() {
        cachedDailyInsight = nil
        cachedWeeklyAnalysis = nil
        cachedWorkoutRecommendation = nil
        Loggers.ai.info("ai.cache_cleared")
    }

    /// Checks if a new day has started since last check, clearing stale cache if so.
    /// Call this on app foregrounding or before generating insights.
    func checkDayRolloverAndClearCache() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastSeen = lastSeenDay, !calendar.isDate(lastSeen, inSameDayAs: today) {
            clearCache()
            Loggers.ai.info("ai.day_rollover_cache_cleared", metadata: [
                "previousDay": lastSeen.ISO8601Format(),
                "newDay": today.ISO8601Format()
            ])
        }
        lastSeenDay = today
    }
}

private extension InsightService {

    /// Indicates reliability of activity data.
    /// - `reliable`: Data confirmed from HealthKit or recent SharedDataStore
    /// - `uncertain`: Both sources unavailable/stale; zero values may be false negatives
    enum DataConfidence {
        case reliable
        case uncertain
    }

    struct ActivityData {
        let steps: Int
        let goal: Int
        let distance: Double
        let floors: Int
        let calories: Int
        let goalMet: Bool
        let percentOfGoal: Int
        let unitName: String
        let confidence: DataConfidence
    }
    
    struct WeekActivityData {
        let summaries: [DailyStepSummary]
        let totalSteps: Int
        let averageSteps: Int
        let goalMetDays: Int
        let bestDay: DailyStepSummary?
        let worstDay: DailyStepSummary?
        let trend: TrendDirection
        let unitName: String
        let confidence: DataConfidence
    }

    func resolveSummaryGoals(_ summaries: [DailyStepSummary], fallbackGoal: Int) -> [DailyStepSummary] {
        summaries.map { summary in
            let resolvedGoal = goalService.goal(for: summary.date) ?? fallbackGoal
            guard resolvedGoal != summary.goal else {
                return summary
            }
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
    
    func fetchTodayActivityData() async -> ActivityData {
        let settings = ActivitySettings.current(userDefaults: userDefaults)
        let syncEnabled = HealthKitSyncSettings.isEnabled(userDefaults: userDefaults)
        dataStore.refresh()
        let sharedData = dataStore.sharedData
        let liveSteps = sharedData?.todaySteps ?? 0
        let liveGoal = goalService.currentGoal

        // Check if SharedDataStore has fresh data (non-nil and not stale)
        let hasRecentSharedData = sharedData?.isStale == false

        if !syncEnabled {
            Loggers.sync.info("healthkit.fetch_skipped", metadata: [
                "reason": "sync_disabled",
                "scope": "insight_today"
            ])
            let confidence: DataConfidence = (liveSteps > 0 || hasRecentSharedData) ? .reliable : .uncertain
            return ActivityData(
                steps: liveSteps,
                goal: liveGoal,
                distance: 0,
                floors: 0,
                calories: 0,
                goalMet: liveGoal > 0 ? liveSteps >= liveGoal : false,
                percentOfGoal: liveGoal > 0 ? (liveSteps * 100) / liveGoal : 0,
                unitName: settings.activityMode.unitName,
                confidence: confidence
            )
        }

        let summaries: [DailyStepSummary]
        do {
            summaries = try await healthKitService.fetchDailySummaries(
                days: 1,
                activityMode: settings.activityMode,
                distanceMode: settings.distanceMode,
                manualStepLength: settings.manualStepLength,
                dailyGoal: goalService.currentGoal
            )
        } catch {
            Loggers.ai.error("ai.healthkit_daily_summaries_fetch_failed", metadata: [
                "error": error.localizedDescription
            ])
            summaries = []
        }

        guard let today = summaries.first else {
            // No HealthKit data - confidence depends on SharedDataStore freshness
            // If steps > 0 OR we have recent shared data, the data is reliable
            let confidence: DataConfidence = (liveSteps > 0 || hasRecentSharedData) ? .reliable : .uncertain
            return ActivityData(
                steps: liveSteps,
                goal: liveGoal,
                distance: 0,
                floors: 0,
                calories: 0,
                goalMet: liveGoal > 0 ? liveSteps >= liveGoal : false,
                percentOfGoal: liveGoal > 0 ? (liveSteps * 100) / liveGoal : 0,
                unitName: settings.activityMode.unitName,
                confidence: confidence
            )
        }

        // HealthKit returned data - this is reliable
        let resolvedSteps = max(liveSteps, today.steps)

        return ActivityData(
            steps: resolvedSteps,
            goal: liveGoal,
            distance: today.distance,
            floors: today.floors,
            calories: Int(today.calories),
            goalMet: liveGoal > 0 ? resolvedSteps >= liveGoal : false,
            percentOfGoal: liveGoal > 0 ? (resolvedSteps * 100) / liveGoal : 0,
            unitName: settings.activityMode.unitName,
            confidence: .reliable
        )
    }
    
    func fetchWeekActivityData() async throws -> WeekActivityData {
        let settings = ActivitySettings.current(userDefaults: userDefaults)
        guard HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) else {
            Loggers.sync.info("healthkit.fetch_skipped", metadata: [
                "reason": "sync_disabled",
                "scope": "insight_week"
            ])
            return WeekActivityData(
                summaries: [],
                totalSteps: 0,
                averageSteps: 0,
                goalMetDays: 0,
                bestDay: nil,
                worstDay: nil,
                trend: .stable,
                unitName: settings.activityMode.unitName,
                confidence: .uncertain
            )
        }
        let rawSummaries = try await healthKitService.fetchDailySummaries(
            days: 7,
            activityMode: settings.activityMode,
            distanceMode: settings.distanceMode,
            manualStepLength: settings.manualStepLength,
            dailyGoal: goalService.currentGoal
        )
        let summaries = resolveSummaryGoals(rawSummaries, fallbackGoal: goalService.currentGoal)
        
        let totalSteps = summaries.reduce(0) { $0 + $1.steps }
        let averageSteps = summaries.isEmpty ? 0 : totalSteps / summaries.count
        let goalMetDays = summaries.filter { $0.steps >= $0.goal }.count
        let bestDay = summaries.max(by: { $0.steps < $1.steps })
        let worstDay = summaries.min(by: { $0.steps < $1.steps })
        
        let trend = calculateTrend(summaries: summaries)
        let confidence: DataConfidence = summaries.isEmpty ? .uncertain : .reliable
        
        return WeekActivityData(
            summaries: summaries,
            totalSteps: totalSteps,
            averageSteps: averageSteps,
            goalMetDays: goalMetDays,
            bestDay: bestDay,
            worstDay: worstDay,
            trend: trend,
            unitName: settings.activityMode.unitName,
            confidence: confidence
        )
    }
    
    func fetchRecentActivityData(days: Int) async throws -> [DailyStepSummary] {
        guard HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) else {
            Loggers.sync.info("healthkit.fetch_skipped", metadata: [
                "reason": "sync_disabled",
                "scope": "insight_recent"
            ])
            return []
        }
        let settings = ActivitySettings.current(userDefaults: userDefaults)
        let summaries = try await healthKitService.fetchDailySummaries(
            days: days,
            activityMode: settings.activityMode,
            distanceMode: settings.distanceMode,
            manualStepLength: settings.manualStepLength,
            dailyGoal: goalService.currentGoal
        )
        return resolveSummaryGoals(summaries, fallbackGoal: goalService.currentGoal)
    }

    func fallbackWeeklyAnalysis() -> WeeklyTrendAnalysis {
        WeeklyTrendAnalysis(
            summary: String(
                localized: "No Activity Data",
                comment: "Weekly trend summary when no data is available"
            ),
            trend: .stable,
            observation: String(
                localized: "Start walking to see your activity history here. Make sure Health access is enabled in Settings.",
                comment: "Weekly trend observation when no data is available"
            ),
            recommendation: String(
                localized: "Enable HealthKit Sync in Settings to see your activity history.",
                comment: "Weekly trend recommendation when no data is available"
            )
        )
    }
    
    func calculateTrend(summaries: [DailyStepSummary]) -> TrendDirection {
        guard summaries.count >= 3 else { return .stable }
        
        let sortedByDate = summaries.sorted { $0.date < $1.date }
        let midpoint = sortedByDate.count / 2
        
        let firstHalf = sortedByDate.prefix(midpoint)
        let secondHalf = sortedByDate.suffix(midpoint)
        
        let firstAvg = firstHalf.isEmpty ? 0 : firstHalf.reduce(0) { $0 + $1.steps } / firstHalf.count
        let secondAvg = secondHalf.isEmpty ? 0 : secondHalf.reduce(0) { $0 + $1.steps } / secondHalf.count
        
        let percentChange = firstAvg > 0 ? ((secondAvg - firstAvg) * 100) / firstAvg : 0
        
        if percentChange > 10 {
            return .increasing
        } else if percentChange < -10 {
            return .decreasing
        } else {
            return .stable
        }
    }
    
    func buildDailyInsightPrompt(data: ActivityData) -> String {
        let unitLabel = data.unitName
        let unitLabelCapitalized = unitLabel.capitalized

        // Determine progress tier for context-appropriate messaging
        let progressTier: String
        if data.steps == 0 {
            progressTier = "NO_ACTIVITY (0 \(unitLabel) recorded)"
        } else if data.percentOfGoal < 25 {
            progressTier = "EARLY_START (under 25% of goal)"
        } else if data.percentOfGoal < 50 {
            progressTier = "BUILDING_MOMENTUM (25-49% of goal)"
        } else if data.percentOfGoal < 100 {
            progressTier = "GOOD_PROGRESS (50-99% of goal)"
        } else {
            progressTier = "GOAL_ACHIEVED (100%+ of goal)"
        }

        // Determine data reliability note for uncertain data
        let dataReliabilityNote: String
        switch data.confidence {
        case .reliable:
            dataReliabilityNote = ""
        case .uncertain:
            dataReliabilityNote = """

            DATA RELIABILITY WARNING:
            Activity data could not be fully verified (HealthKit unavailable or still syncing).
            If \(unitLabel) = 0, it may be because data hasn't loaded yet, NOT because the user is inactive.
            Phrase your response to acknowledge this uncertainty (e.g., "Once your data syncs..." or "Your activity will appear shortly...").
            """
        }

        return """
        Generate a daily fitness insight for this user:

        Today's Activity:
        - \(unitLabelCapitalized): \(data.steps.formatted()) (Goal: \(data.goal.formatted()))
        - Progress: \(data.percentOfGoal)% of daily goal
        - Progress Tier: \(progressTier)
        - Goal Status: \(data.goalMet ? "ACHIEVED" : "NOT ACHIEVED")
        - Distance: \(String(format: "%.1f", data.distance / 1000)) km
        - Floors climbed: \(data.floors)
        - Estimated calories: \(data.calories)\(dataReliabilityNote)

        CRITICAL GROUNDING RULES:
        1. ONLY reference achievements that are TRUE based on the data above.
        2. If \(unitLabel) = 0, acknowledge the day is just starting or activity hasn't been recorded yet.
        3. NEVER mention "first day of X \(unitLabel)" or any milestone unless the actual count meets that milestone.
        4. For NO_ACTIVITY or EARLY_START tiers, focus on encouragement to begin, not celebration.
        5. Match your tone to the Progress Tier - be supportive but honest.
        6. Keep it concise and actionable.
        """
    }
    
    func buildWeeklyAnalysisPrompt(data: WeekActivityData) -> String {
        let unitLabel = data.unitName
        let dailyBreakdown: String
        if data.summaries.isEmpty {
            dailyBreakdown = "No daily activity data available."
        } else {
            dailyBreakdown = data.summaries.map { summary in
                let status = summary.steps >= summary.goal ? "Goal Met" : "Below Goal"
                return "\(summary.date.formatted(date: .abbreviated, time: .omitted)): \(summary.steps.formatted()) \(unitLabel) (\(status))"
            }.joined(separator: "\n")
        }

        let dataReliabilityNote: String
        switch data.confidence {
        case .reliable:
            dataReliabilityNote = ""
        case .uncertain:
            dataReliabilityNote = """

            DATA RELIABILITY WARNING:
            Health activity data may be incomplete or unavailable (HealthKit sync disabled or still syncing).
            Avoid definitive statements about trends or performance; include gentle guidance to enable syncing.
            """
        }
        
        return """
        Analyze this week's fitness activity:
        
        Weekly Summary:
        - Total \(unitLabel): \(data.totalSteps.formatted())
        - Daily average: \(data.averageSteps.formatted()) \(unitLabel)
        - Goals achieved: \(data.goalMetDays)/7 days
        - Current trend: \(data.trend.rawValue)
        
        Daily Breakdown:
        \(dailyBreakdown)
        
        \(data.bestDay.map { "Best day: \($0.date.formatted(date: .abbreviated, time: .omitted)) with \($0.steps.formatted()) \(unitLabel)" } ?? "")
        \(data.worstDay.map { "Lowest day: \($0.date.formatted(date: .abbreviated, time: .omitted)) with \($0.steps.formatted()) \(unitLabel)" } ?? "")
        \(dataReliabilityNote)

        Provide a concise weekly analysis with actionable recommendations.
        """
    }
    
    func buildGoalRecommendationPrompt(
        data: [DailyStepSummary],
        currentGoal: Int,
        unitName: String
    ) -> String {
        let unitLabel = unitName
        let averageSteps = data.isEmpty ? 0 : data.reduce(0) { $0 + $1.steps } / data.count
        let goalMetCount = data.filter { $0.steps >= $0.goal }.count
        let goalMetPercentage = data.isEmpty ? 0 : (goalMetCount * 100) / data.count
        let dataReliabilityNote = data.isEmpty
            ? """

            DATA RELIABILITY WARNING:
            Recent activity data is unavailable. Avoid aggressive goal increases and suggest enabling HealthKit sync for better recommendations.
            """
            : ""
        
        return """
        Recommend a daily step goal adjustment:
        
        Current Status:
        - Current goal: \(currentGoal.formatted()) \(unitLabel)
        - 14-day average: \(averageSteps.formatted()) \(unitLabel)
        - Goal achievement rate: \(goalMetPercentage)% (\(goalMetCount)/\(data.count) days)
        \(dataReliabilityNote)

        Provide a goal recommendation that is challenging but achievable.
        Consider gradual progression (5-10% increases are ideal).
        """
    }
    
    func buildWorkoutRecommendationPrompt(weekData: WeekActivityData, todayData: ActivityData, currentGoal: Int) -> String {
        let unitLabel = todayData.unitName
        let currentHour = Calendar.current.component(.hour, from: Date())
        let timeContext: String
        if currentHour < 12 {
            timeContext = "morning"
        } else if currentHour < 17 {
            timeContext = "afternoon"
        } else {
            timeContext = "evening"
        }
        
        let dayOfWeek = Calendar.current.component(.weekday, from: Date())
        let isWeekend = dayOfWeek == 1 || dayOfWeek == 7
        
        let dataReliabilityNote: String
        switch weekData.confidence {
        case .reliable:
            dataReliabilityNote = ""
        case .uncertain:
            dataReliabilityNote = """

            DATA RELIABILITY WARNING:
            Weekly activity data may be incomplete or unavailable. Avoid precise claims about trends and recommend enabling HealthKit sync.
            """
        }

        return """
        Recommend a workout for today based on this user's activity data:
        
        Today's Progress:
        - \(unitLabel.capitalized) so far: \(todayData.steps.formatted())
        - Goal: \(currentGoal.formatted()) \(unitLabel)
        - Progress: \(todayData.percentOfGoal)% complete
        - Distance: \(String(format: "%.1f", todayData.distance / 1000)) km
        
        This Week's Context:
        - Weekly average: \(weekData.averageSteps.formatted()) \(unitLabel)/day
        - Goals achieved: \(weekData.goalMetDays)/7 days this week
        - Trend: \(weekData.trend.rawValue)
        
        Current Time Context:
        - Time of day: \(timeContext)
        - Day type: \(isWeekend ? "Weekend" : "Weekday")
        \(dataReliabilityNote)

        Provide a personalized workout recommendation.
        Consider their current progress, weekly patterns, and time of day.
        If they're behind on their goal, suggest something achievable.
        If they're ahead, suggest an appropriate challenge or recovery.
        """
    }
}
