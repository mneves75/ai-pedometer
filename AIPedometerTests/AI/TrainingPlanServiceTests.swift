import Foundation
import SwiftData
import Testing

@testable import AIPedometer

@MainActor
struct TrainingPlanServiceTests {
    @Test("generatePlan persists record and returns expected fields")
    func generatePlanPersistsRecord() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let goalService = GoalService(persistence: persistence)
        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                steps: 4200,
                distance: 0,
                floors: 0,
                calories: 0,
                goal: AppConstants.defaultDailyGoal
            )
        ]

        let foundationModels = MockFoundationModelsService()
        let aiPlan = makeAITrainingPlan()
        foundationModels.respondResult = .success(aiPlan)

        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            modelContext: context
        )

        let record = try await service.generatePlan(
            goal: .reach10k,
            level: .beginner,
            daysPerWeek: 5
        )

        let fetched = service.fetchAllPlans()
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == record.id)
        #expect(fetched.first?.name == aiPlan.name)
        #expect(fetched.first?.weeklyTargets.count == aiPlan.weeklyTargets.count)
        #expect(record.primaryGoal == TrainingGoalType.reach10k.rawValue)
    }

    @Test("fetchAllPlans sorts by createdAt descending")
    func fetchAllPlansSortsByCreatedAtDescending() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let service = TrainingPlanService(
            foundationModelsService: MockFoundationModelsService(),
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: persistence),
            modelContext: context
        )

        let older = TrainingPlanRecord()
        older.name = "Older"
        older.createdAt = Date(timeIntervalSince1970: 1_600_000_000)
        older.updatedAt = older.createdAt

        let newer = TrainingPlanRecord()
        newer.name = "Newer"
        newer.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        newer.updatedAt = newer.createdAt

        context.insert(older)
        context.insert(newer)
        try context.save()

        let fetched = service.fetchAllPlans()
        #expect(fetched.map(\.name) == ["Newer", "Older"])
    }

    @Test("generatePlan throws when model unavailable")
    func generatePlanThrowsWhenModelUnavailable() async {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let foundationModels = MockFoundationModelsService()
        foundationModels.availability = .unavailable(reason: .modelNotReady)

        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: persistence),
            modelContext: context
        )

        do {
            _ = try await service.generatePlan(
                goal: .reach10k,
                level: .beginner,
                daysPerWeek: 5
            )
            #expect(Bool(false), "Expected error to be thrown")
        } catch {
            switch error {
            case .modelUnavailable(let reason):
                #expect(reason == .modelNotReady)
            default:
                #expect(Bool(false), "Expected modelUnavailable error, got \(error)")
            }
        }
    }

    @Test("generatePlan uses activity mode units from user defaults")
    func generatePlanUsesActivityModeUnits() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(
            ActivityTrackingMode.wheelchairPushes.rawValue,
            forKey: AppConstants.UserDefaultsKeys.activityTrackingMode
        )

        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let goalService = GoalService(persistence: persistence)
        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                steps: 2100,
                distance: 0,
                floors: 0,
                calories: 0,
                goal: AppConstants.defaultDailyGoal
            )
        ]

        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(makeAITrainingPlan())

        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            modelContext: context,
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generatePlan(
            goal: .reach10k,
            level: .beginner,
            daysPerWeek: 4
        )

        let unitName = ActivityTrackingMode.wheelchairPushes.unitName

        #expect(healthKit.lastFetchDailySummariesArgs?.activityMode == .wheelchairPushes)
        #expect(foundationModels.lastPrompt?.contains(unitName) ?? false)
    }

    @Test("generatePlan skips HealthKit when sync disabled")
    func generatePlanSkipsHealthKitWhenSyncDisabled() async throws {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)

        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let goalService = GoalService(persistence: persistence)
        let healthKit = MockHealthKitService()
        healthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: Date(timeIntervalSince1970: 1_700_000_000),
                steps: 2100,
                distance: 0,
                floors: 0,
                calories: 0,
                goal: AppConstants.defaultDailyGoal
            )
        ]

        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(makeAITrainingPlan())

        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: healthKit,
            goalService: goalService,
            modelContext: context,
            userDefaults: testDefaults.defaults
        )

        _ = try await service.generatePlan(
            goal: .reach10k,
            level: .beginner,
            daysPerWeek: 4
        )

        #expect(healthKit.lastFetchDailySummariesArgs == nil)
        #expect(foundationModels.lastPrompt?.contains("DATA RELIABILITY WARNING") ?? false)
    }
}

private func makeAITrainingPlan() -> AITrainingPlan {
    AITrainingPlan(
        name: "Starter Plan",
        planDescription: "Build a daily walking habit.",
        durationWeeks: 2,
        weeklyTargets: [
            WeeklyTarget(weekNumber: 1, dailyStepTarget: 6000, activeDaysRequired: 5, focusTip: "Start steady."),
            WeeklyTarget(weekNumber: 2, dailyStepTarget: 7000, activeDaysRequired: 5, focusTip: "Keep the momentum.")
        ],
        primaryGoal: .reach10k
    )
}
