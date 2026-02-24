import Foundation
import Testing

@testable import AIPedometer

@MainActor
struct InsightServiceTests {
    @Test("Daily insight uses live steps when higher than HealthKit summary")
    func dailyInsightUsesLiveSteps() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(DailyInsight(
            greeting: "Hello",
            highlight: "Highlight",
            suggestion: "Suggestion",
            encouragement: "Encourage"
        ))

        let healthKit = StubHealthKitService(dailySummaries: [
            DailyStepSummary(
                date: .now,
                steps: 0,
                distance: 0,
                floors: 0,
                calories: 0,
                goal: 10_000
            )
        ])

        let dataStore = SharedDataStore(userDefaults: testDefaults.defaults)
        dataStore.update(SharedStepData(
            todaySteps: 46,
            goalSteps: 10_000,
            goalProgress: 0.0046,
            currentStreak: 0,
            lastUpdated: .now,
            weeklySteps: []
        ))

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: dataStore,
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generateDailyInsight(forceRefresh: true)

        let unitName = ActivityTrackingMode.steps.unitName
        let prompt = foundationModels.lastPrompt ?? ""
        #expect(prompt.contains("\(unitName.capitalized): 46"))
        #expect(goalValue(from: prompt) == 10_000)
    }

    @Test("Daily insight skips HealthKit when sync disabled")
    func dailyInsightSkipsHealthKitWhenSyncDisabled() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(DailyInsight(
            greeting: "Hello",
            highlight: "Highlight",
            suggestion: "Suggestion",
            encouragement: "Encourage"
        ))

        let healthKit = StubHealthKitService(dailySummaries: [
            DailyStepSummary(
                date: .now,
                steps: 9999,
                distance: 0,
                floors: 0,
                calories: 0,
                goal: 10_000
            )
        ])

        let dataStore = SharedDataStore(userDefaults: testDefaults.defaults)
        dataStore.update(SharedStepData(
            todaySteps: 123,
            goalSteps: 10_000,
            goalProgress: 0.0123,
            currentStreak: 0,
            lastUpdated: .now,
            weeklySteps: []
        ))

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: dataStore,
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generateDailyInsight(forceRefresh: true)

        #expect(healthKit.fetchDailySummariesCallCount == 0)
        let unitName = ActivityTrackingMode.steps.unitName
        let prompt = foundationModels.lastPrompt ?? ""
        #expect(prompt.contains("\(unitName.capitalized): 123"))
        #expect(!prompt.contains("DATA RELIABILITY WARNING"))
    }

    @Test("Daily insight prompt with zero steps includes NO_ACTIVITY tier and grounding rules")
    func dailyInsightZeroStepsHasGroundingRules() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(DailyInsight(
            greeting: "Hello",
            highlight: "No activity yet",
            suggestion: "Start moving",
            encouragement: "You can do it"
        ))

        let healthKit = StubHealthKitService(dailySummaries: [
            DailyStepSummary(
                date: .now,
                steps: 0,
                distance: 0,
                floors: 0,
                calories: 0,
                goal: 10_000
            )
        ])

        let dataStore = SharedDataStore(userDefaults: testDefaults.defaults)
        dataStore.update(SharedStepData(
            todaySteps: 0,
            goalSteps: 10_000,
            goalProgress: 0,
            currentStreak: 0,
            lastUpdated: .now,
            weeklySteps: []
        ))

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: dataStore,
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generateDailyInsight(forceRefresh: true)

        let unitName = ActivityTrackingMode.steps.unitName
        let prompt = foundationModels.lastPrompt ?? ""

        // Verify zero steps in prompt (using dynamic unit name for locale independence)
        #expect(prompt.contains("\(unitName.capitalized): 0"))

        // Verify NO_ACTIVITY tier is present
        #expect(prompt.contains("NO_ACTIVITY"))

        // Verify grounding rules are present
        #expect(prompt.contains("CRITICAL GROUNDING RULES"))
        #expect(prompt.contains("NEVER mention"))
    }

    @Test("Daily insight prompt includes uncertainty warning when data is unreliable")
    func dailyInsightUncertainDataIncludesWarning() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(DailyInsight(
            greeting: "Hello",
            highlight: "Uncertain",
            suggestion: "Wait",
            encouragement: "Data syncing"
        ))

        // HealthKit returns empty (simulating unavailable or no data)
        let healthKit = StubHealthKitService(dailySummaries: [])

        // SharedDataStore is fresh but shows 0 steps - but this is actually "not stale"
        // so it should be reliable. Let's test the uncertain case by using stale data.
        let dataStore = SharedDataStore(userDefaults: testDefaults.defaults)
        // Don't update dataStore - leave it nil (simulating first launch before data loads)

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: dataStore,
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generateDailyInsight(forceRefresh: true)

        let prompt = foundationModels.lastPrompt ?? ""

        // When SharedDataStore is nil AND HealthKit returns empty AND steps=0,
        // the prompt should include DATA RELIABILITY WARNING
        #expect(prompt.contains("DATA RELIABILITY WARNING"))
        #expect(prompt.contains("data hasn't loaded yet"))
    }

    @Test("Daily insight prompt does not include uncertainty warning when data is reliable")
    func dailyInsightReliableDataNoWarning() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(DailyInsight(
            greeting: "Hello",
            highlight: "Reliable",
            suggestion: "Keep going",
            encouragement: "Great"
        ))

        // HealthKit returns valid data
        let healthKit = StubHealthKitService(dailySummaries: [
            DailyStepSummary(
                date: .now,
                steps: 5000,
                distance: 3500,
                floors: 2,
                calories: 150,
                goal: 10_000
            )
        ])

        let dataStore = SharedDataStore(userDefaults: testDefaults.defaults)
        dataStore.update(SharedStepData(
            todaySteps: 5000,
            goalSteps: 10_000,
            goalProgress: 0.5,
            currentStreak: 1,
            lastUpdated: .now,
            weeklySteps: []
        ))

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: dataStore,
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generateDailyInsight(forceRefresh: true)

        let prompt = foundationModels.lastPrompt ?? ""

        // When HealthKit returns data, the prompt should NOT include uncertainty warning
        #expect(!prompt.contains("DATA RELIABILITY WARNING"))
    }

    @Test("Daily insight cache invalidates when steps change")
    func dailyInsightCacheInvalidatesOnStepChange() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(DailyInsight(
            greeting: "Hello",
            highlight: "Highlight",
            suggestion: "Suggestion",
            encouragement: "Encourage"
        ))

        let healthKit = StubHealthKitService(dailySummaries: [
            DailyStepSummary(
                date: .now,
                steps: 0,
                distance: 0,
                floors: 0,
                calories: 0,
                goal: 10_000
            )
        ])

        let dataStore = SharedDataStore(userDefaults: testDefaults.defaults)
        let goalService = GoalService(persistence: PersistenceController(inMemory: true))

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            dataStore: dataStore,
            userDefaults: testDefaults.defaults
        )

        dataStore.update(SharedStepData(
            todaySteps: 10,
            goalSteps: 10_000,
            goalProgress: 0.001,
            currentStreak: 0,
            lastUpdated: .now,
            weeklySteps: []
        ))

        _ = try await service.generateDailyInsight(forceRefresh: false)
        #expect(foundationModels.respondCallCount == 1)

        dataStore.update(SharedStepData(
            todaySteps: 20,
            goalSteps: 10_000,
            goalProgress: 0.002,
            currentStreak: 0,
            lastUpdated: .now,
            weeklySteps: []
        ))

        _ = try await service.generateDailyInsight(forceRefresh: false)
        #expect(foundationModels.respondCallCount == 2)
    }

    @Test("Workout recommendation uses historical goals for goalMetDays")
    func workoutRecommendationUsesHistoricalGoals() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(
            AIWorkoutRecommendation(
                intent: .maintain,
                difficulty: 2,
                rationale: "Maintain routine",
                targetSteps: 6000,
                estimatedMinutes: 30,
                suggestedTimeOfDay: .anytime
            )
        )
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let dayMinus2 = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        let dayMinus1 = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let goal1Start = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let goal1End = calendar.date(byAdding: .second, value: -1, to: dayMinus1) ?? dayMinus1
        let goal2End = calendar.date(byAdding: .second, value: -1, to: today) ?? today

        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        context.insert(StepGoal(dailySteps: 8000, startDate: goal1Start, endDate: goal1End))
        context.insert(StepGoal(dailySteps: 9000, startDate: dayMinus1, endDate: goal2End))
        context.insert(StepGoal(dailySteps: 10000, startDate: today))
        try context.save()

        let healthKit = StubHealthKitService(dailySummaries: [
            DailyStepSummary(date: today, steps: 1000, distance: 0, floors: 0, calories: 0, goal: 10_000),
            DailyStepSummary(date: dayMinus2, steps: 8500, distance: 0, floors: 0, calories: 0, goal: 10_000),
            DailyStepSummary(date: dayMinus1, steps: 9500, distance: 0, floors: 0, calories: 0, goal: 10_000)
        ])

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: persistence),
            dataStore: SharedDataStore(userDefaults: testDefaults.defaults),
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generateWorkoutRecommendation(forceRefresh: true)
        let prompt = foundationModels.lastPrompt ?? ""

        #expect(prompt.contains("Goals achieved: 2/7"))
        #expect(prompt.contains(AppLanguage.promptInstruction()))
    }

    @Test("Workout recommendation uses cache when steps and goal are unchanged")
    func workoutRecommendationCachesByDayAndSteps() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(
            AIWorkoutRecommendation(
                intent: .maintain,
                difficulty: 2,
                rationale: "Maintain routine",
                targetSteps: 6000,
                estimatedMinutes: 30,
                suggestedTimeOfDay: .anytime
            )
        )

        let healthKit = StubHealthKitService(dailySummaries: [
            DailyStepSummary(
                date: .now,
                steps: 4000,
                distance: 0,
                floors: 0,
                calories: 0,
                goal: 10_000
            )
        ])

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: SharedDataStore(userDefaults: testDefaults.defaults),
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generateWorkoutRecommendation()
        _ = try await service.generateWorkoutRecommendation()

        #expect(foundationModels.respondCallCount == 1)
    }

    @Test("Weekly analysis uses fallback when no data is available")
    func weeklyAnalysisFallsBackWhenNoData() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
        let foundationModels = MockFoundationModelsService()
        let healthKit = StubHealthKitService(dailySummaries: [])
        let dataStore = SharedDataStore(userDefaults: testDefaults.defaults)

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: dataStore,
            userDefaults: testDefaults.defaults
        )

        let analysis = try await service.generateWeeklyAnalysis(forceRefresh: true)

        #expect(foundationModels.respondCallCount == 0)
        #expect(analysis.summary == String(localized: "No Activity Data", comment: "Weekly trend summary when no data is available"))
        #expect(analysis.observation == String(localized: "Start walking to see your activity history here. Make sure Health access is enabled in Settings.", comment: "Weekly trend observation when no data is available"))
        #expect(analysis.recommendation == String(localized: "Enable HealthKit Sync in Settings to see your activity history.", comment: "Weekly trend recommendation when no data is available"))
    }

    @Test("Weekly analysis concurrent calls return fallback instead of throwing")
    func weeklyAnalysisConcurrentCallsAvoidSessionContentionError() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondDelayNanoseconds = 120_000_000
        foundationModels.respondResult = .success(WeeklyTrendAnalysis(
            summary: "AI Summary",
            trend: .stable,
            observation: "AI Observation",
            recommendation: "AI Recommendation"
        ))

        let summaries = [
            DailyStepSummary(
                date: .now,
                steps: 6_200,
                distance: 4_900,
                floors: 3,
                calories: 250,
                goal: 7_000
            )
        ]

        let healthKit = StubHealthKitService(dailySummaries: summaries)
        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: SharedDataStore(userDefaults: testDefaults.defaults),
            userDefaults: testDefaults.defaults
        )

        async let first: WeeklyTrendAnalysis = service.generateWeeklyAnalysis(forceRefresh: true)
        async let second: WeeklyTrendAnalysis = service.generateWeeklyAnalysis(forceRefresh: true)

        let (firstResult, secondResult) = try await (first, second)

        #expect(foundationModels.respondCallCount == 1)
        #expect(firstResult.summary == "AI Summary")
        #expect(secondResult.summary != String(localized: "No Activity Data", comment: "Weekly trend summary when no data is available"))
        #expect(secondResult.observation.contains("still processing"))
    }

    @Test("Weekly analysis falls back to history summary when guardrail blocks response")
    func weeklyAnalysisFallsBackOnGuardrailUsingHistory() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .failure(.guardrailViolation)

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let summaries = (0..<7).compactMap { offset -> DailyStepSummary? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let steps = 3_000 + ((6 - offset) * 900)
            return DailyStepSummary(
                date: date,
                steps: steps,
                distance: Double(steps) * 0.75,
                floors: offset % 3,
                calories: Double(steps) * 0.04,
                goal: 5_500
            )
        }

        let healthKit = StubHealthKitService(dailySummaries: summaries)
        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: SharedDataStore(userDefaults: testDefaults.defaults),
            userDefaults: testDefaults.defaults
        )

        let analysis = try await service.generateWeeklyAnalysis(forceRefresh: true)

        #expect(foundationModels.respondCallCount == 1)
        #expect(!analysis.summary.isEmpty)
        #expect(analysis.summary != String(localized: "No Activity Data", comment: "Weekly trend summary when no data is available"))
        #expect(analysis.observation.contains("safe summary"))
        #expect(analysis.recommendation.contains("next week"))
    }

    @Test("Weekly analysis prompt includes non-medical safety rules")
    func weeklyAnalysisPromptContainsNonMedicalSafetyRules() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(WeeklyTrendAnalysis(
            summary: "Steady week",
            trend: .stable,
            observation: "Consistent pattern",
            recommendation: "Keep going"
        ))

        let healthKit = StubHealthKitService(dailySummaries: [
            DailyStepSummary(
                date: .now,
                steps: 6_000,
                distance: 4_200,
                floors: 4,
                calories: 240,
                goal: 7_000
            )
        ])

        let service = InsightService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: GoalService(persistence: PersistenceController(inMemory: true)),
            dataStore: SharedDataStore(userDefaults: testDefaults.defaults),
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generateWeeklyAnalysis(forceRefresh: true)

        let prompt = foundationModels.lastPrompt ?? ""
        #expect(prompt.contains("NON-MEDICAL SAFETY RULES"))
        #expect(prompt.contains("Do not provide diagnosis"))
    }
}

@MainActor
private final class StubHealthKitService: HealthKitServiceProtocol, Sendable {
    private let dailySummaries: [DailyStepSummary]
    private(set) var fetchDailySummariesCallCount = 0

    init(dailySummaries: [DailyStepSummary]) {
        self.dailySummaries = dailySummaries
    }

    func requestAuthorization() async throws {}

    func fetchTodaySteps() async throws -> Int { 0 }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int { 0 }

    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int { 0 }

    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double { 0 }

    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int { 0 }

    func fetchDailySummaries(
        days: Int,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] {
        fetchDailySummariesCallCount += 1
        return dailySummaries
    }

    func fetchDailySummaries(
        from startDate: Date,
        to endDate: Date,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] {
        fetchDailySummariesCallCount += 1
        return dailySummaries
    }

    func saveWorkout(_ session: WorkoutSession) async throws {}
}

private func goalValue(from prompt: String) -> Int? {
    let pattern = "Goal: ([0-9][0-9\\.,]*)"
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(prompt.startIndex..<prompt.endIndex, in: prompt)
    guard let match = regex.firstMatch(in: prompt, range: range),
          let valueRange = Range(match.range(at: 1), in: prompt) else {
        return nil
    }
    let raw = prompt[valueRange]
    let digits = raw.filter(\.isNumber)
    return Int(digits)
}
