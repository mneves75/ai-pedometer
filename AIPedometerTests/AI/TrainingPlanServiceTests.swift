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
        #expect(fetched.first?.name == TrainingGoalType.reach10k.displayName)
        #expect(fetched.first?.planDescription == TrainingGoalType.reach10k.description)
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

    @Test("generatePlan preserves the concrete model unavailability reason")
    func generatePlanPreservesModelUnavailabilityReason() async {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let foundationModels = MockFoundationModelsService()
        foundationModels.availability = .unavailable(reason: .appleIntelligenceNotEnabled)

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
                #expect(reason == .appleIntelligenceNotEnabled)
            default:
                #expect(Bool(false), "Expected modelUnavailable error, got \(error)")
            }
        }
    }

    @Test("generateWeeklyRecommendation preserves the concrete model unavailability reason")
    func generateWeeklyRecommendationPreservesModelUnavailabilityReason() async {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let foundationModels = MockFoundationModelsService()
        foundationModels.availability = .unavailable(reason: .deviceNotEligible)

        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: persistence),
            modelContext: context
        )

        do {
            _ = try await service.generateWeeklyRecommendation()
            #expect(Bool(false), "Expected error to be thrown")
        } catch {
            switch error {
            case .modelUnavailable(let reason):
                #expect(reason == .deviceNotEligible)
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
            daysPerWeek: 5
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
            daysPerWeek: 5
        )

        #expect(healthKit.lastFetchDailySummariesArgs == nil)
        #expect(foundationModels.lastPrompt?.contains("DATA RELIABILITY WARNING") ?? false)
    }

    @Test("generatePlan falls back when the model exceeds requested active days")
    func generatePlanFallsBackForOverScheduledPlan() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let goalService = GoalService(persistence: persistence)
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(
            AITrainingPlan(
                name: "Too Much",
                planDescription: "Invalid",
                durationWeeks: 1,
                weeklyTargets: [
                    WeeklyTarget(weekNumber: 1, dailyStepTarget: 6000, activeDaysRequired: 6, focusTip: "Nope")
                ],
                primaryGoal: .reach10k
            )
        )

        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: goalService,
            modelContext: context
        )

        let record = try await service.generatePlan(goal: .reach10k, level: .beginner, daysPerWeek: 4)

        #expect(record.name == TrainingGoalType.reach10k.displayName)
        #expect(record.weeklyTargets.allSatisfy { $0.activeDaysRequired <= 4 })
        #expect(record.weeklyTargets.allSatisfy { !$0.focusTip.isEmpty })
    }

    @Test("generatePlan prompt includes language directive")
    func generatePlanPromptIncludesLanguageDirective() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let goalService = GoalService(persistence: persistence)
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(makeAITrainingPlan())

        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: goalService,
            modelContext: context
        )

        _ = try await service.generatePlan(goal: .reach10k, level: .beginner, daysPerWeek: 5)

        #expect(foundationModels.lastPrompt?.contains("Language:") ?? false)
        #expect(foundationModels.lastPrompt?.contains(AppLanguage.promptInstruction()) ?? false)
    }

    @Test("generatePlan rejects overlapping requests")
    func generatePlanRejectsOverlappingRequests() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let goalService = GoalService(persistence: persistence)
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .success(makeAITrainingPlan())
        foundationModels.respondDelayNanoseconds = 100_000_000

        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: goalService,
            modelContext: context
        )

        let first = Task {
            let record = try await service.generatePlan(goal: .reach10k, level: .beginner, daysPerWeek: 5)
            return record.id
        }
        await Task.yield()
        let second = Task {
            let record = try await service.generatePlan(goal: .reach10k, level: .beginner, daysPerWeek: 5)
            return record.id
        }

        _ = try await first.value
        await #expect(throws: AIServiceError.self) {
            _ = try await second.value
        }
    }

    @Test("pausePlan rolls back state when save fails")
    func pausePlanRollsBackOnSaveFailure() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let foundationModels = MockFoundationModelsService()
        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: persistence),
            modelContext: context,
            saveModelContext: { _ in throw CocoaError(.validationMultipleErrors) }
        )

        let plan = TrainingPlanRecord()
        plan.status = TrainingPlanRecord.PlanStatus.active.rawValue
        plan.updatedAt = Date(timeIntervalSince1970: 100)
        context.insert(plan)

        service.pausePlan(plan)

        #expect(plan.status == TrainingPlanRecord.PlanStatus.active.rawValue)
        #expect(plan.updatedAt == Date(timeIntervalSince1970: 100))
    }

    @Test("generatePlan falls back to localized deterministic content when the model returns an invalid response")
    func generatePlanFallsBackWhenModelResponseIsInvalid() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let foundationModels = MockFoundationModelsService()
        foundationModels.respondResult = .failure(.invalidResponse)

        let service = TrainingPlanService(
            foundationModelsService: foundationModels,
            healthKitService: MockHealthKitService(),
            goalService: GoalService(persistence: persistence),
            modelContext: context
        )

        let record = try await service.generatePlan(goal: .reach10k, level: .beginner, daysPerWeek: 5)

        #expect(record.name == TrainingGoalType.reach10k.displayName)
        #expect(record.planDescription == TrainingGoalType.reach10k.description)
        #expect(record.weeklyTargets.count == 4)
        #expect(record.weeklyTargets.allSatisfy { !$0.focusTip.isEmpty })
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
