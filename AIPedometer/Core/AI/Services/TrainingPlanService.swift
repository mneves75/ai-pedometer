import Foundation
import FoundationModels
import Observation
import SwiftData

enum TrainingGoalType: String, Codable, Sendable, CaseIterable {
    case startWalking = "start_walking"
    case reach10k = "reach_10k"
    case improveConsistency = "improve_consistency"
    case buildEndurance = "build_endurance"
    case weightManagement = "weight_management"
    
    var displayName: String {
        aiGoal.localizedTitle
    }
    
    var description: String {
        switch self {
        case .startWalking:
            L10n.localized("Perfect for beginners looking to establish a daily walking habit", comment: "Training goal description")
        case .reach10k:
            L10n.localized("Progressively increase your daily steps to reach the 10K milestone", comment: "Training goal description")
        case .improveConsistency:
            L10n.localized("Focus on meeting your goals more days per week", comment: "Training goal description")
        case .buildEndurance:
            L10n.localized("Increase walking duration and intensity over time", comment: "Training goal description")
        case .weightManagement:
            L10n.localized("Structured plan to support your weight management journey", comment: "Training goal description")
        }
    }
    
    var aiGoal: TrainingGoal {
        switch self {
        case .startWalking:
            return .startWalking
        case .reach10k:
            return .reach10k
        case .improveConsistency:
            return .improveConsistency
        case .buildEndurance:
            return .buildEndurance
        case .weightManagement:
            return .weightManagement
        }
    }
}

enum FitnessLevel: String, Codable, Sendable, CaseIterable {
    case beginner
    case intermediate
    case advanced
    
    var displayName: String {
        switch self {
        case .beginner:
            L10n.localized("Beginner", comment: "Fitness level")
        case .intermediate:
            L10n.localized("Intermediate", comment: "Fitness level")
        case .advanced:
            L10n.localized("Advanced", comment: "Fitness level")
        }
    }
    
    var description: String {
        switch self {
        case .beginner:
            L10n.localized("New to regular exercise or returning after a break", comment: "Fitness level description")
        case .intermediate:
            L10n.localized("Currently active but looking to improve", comment: "Fitness level description")
        case .advanced:
            L10n.localized("Regularly active, ready for a challenge", comment: "Fitness level description")
        }
    }
}

@MainActor
@Observable
final class TrainingPlanService {
    private let foundationModelsService: any FoundationModelsServiceProtocol
    private let healthKitService: any HealthKitServiceProtocol
    private let goalService: any GoalServiceProtocol
    private let modelContext: ModelContext
    private let userDefaults: UserDefaults

    private(set) var isGenerating = false
    private(set) var lastError: AIServiceError?

    init(
        foundationModelsService: any FoundationModelsServiceProtocol,
        healthKitService: any HealthKitServiceProtocol,
        goalService: any GoalServiceProtocol,
        modelContext: ModelContext,
        userDefaults: UserDefaults = .standard
    ) {
        self.foundationModelsService = foundationModelsService
        self.healthKitService = healthKitService
        self.goalService = goalService
        self.modelContext = modelContext
        self.userDefaults = userDefaults
    }
    
    func generatePlan(
        goal: TrainingGoalType,
        level: FitnessLevel,
        daysPerWeek: Int
    ) async throws(AIServiceError) -> TrainingPlanRecord {
        guard foundationModelsService.availability.isAvailable else {
            throw AIServiceError.modelUnavailable(.modelNotReady)
        }
        
        isGenerating = true
        lastError = nil
        defer { isGenerating = false }
        
        do {
            let recentData = try await fetchRecentActivityData()
            let prompt = buildPlanPrompt(
                goal: goal,
                level: level,
                daysPerWeek: daysPerWeek,
                recentData: recentData
            )
            
            let aiPlan: AITrainingPlan = try await foundationModelsService.respond(
                to: prompt,
                as: AITrainingPlan.self
            )
            
            let record = createPlanRecord(from: aiPlan, goal: goal)
            modelContext.insert(record)
            try modelContext.save()
            
            Loggers.ai.info("ai.training_plan_generated", metadata: [
                "goal": goal.rawValue,
                "level": level.rawValue,
                "weeks": "\(aiPlan.weeklyTargets.count)"
            ])
            
            return record
        } catch let error as AIServiceError {
            lastError = error
            throw error
        } catch {
            let mappedError = AIServiceError.generationFailed(underlying: error.localizedDescription)
            lastError = mappedError
            throw mappedError
        }
    }
    
    func generateWeeklyRecommendation() async throws(AIServiceError) -> AIWorkoutRecommendation {
        guard foundationModelsService.availability.isAvailable else {
            throw AIServiceError.modelUnavailable(.modelNotReady)
        }

        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        do {
            let recentData = try await fetchRecentActivityData()
            let prompt = buildWeeklyRecommendationPrompt(recentData: recentData)

            let recommendation: AIWorkoutRecommendation = try await foundationModelsService.respond(
                to: prompt,
                as: AIWorkoutRecommendation.self
            )

            Loggers.ai.info("ai.workout_recommendation_generated", metadata: [
                "intent": recommendation.intent.rawValue,
                "difficulty": "\(recommendation.difficulty)"
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
    
    func fetchActivePlans() -> [TrainingPlanRecord] {
        let descriptor = FetchDescriptor<TrainingPlanRecord>(
            predicate: #Predicate { $0.deletedAt == nil && $0.status == "active" },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Loggers.ai.error("ai.training_plan_fetch_failed", metadata: [
                "scope": "active",
                "error": error.localizedDescription
            ])
            return []
        }
    }

    func fetchAllPlans() -> [TrainingPlanRecord] {
        let descriptor = FetchDescriptor<TrainingPlanRecord>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Loggers.ai.error("ai.training_plan_fetch_failed", metadata: [
                "scope": "all",
                "error": error.localizedDescription
            ])
            return []
        }
    }
    
    func pausePlan(_ plan: TrainingPlanRecord) {
        plan.status = TrainingPlanRecord.PlanStatus.paused.rawValue
        plan.updatedAt = Date()
        savePlanChange(action: "pause")
    }
    
    func resumePlan(_ plan: TrainingPlanRecord) {
        plan.status = TrainingPlanRecord.PlanStatus.active.rawValue
        plan.updatedAt = Date()
        savePlanChange(action: "resume")
    }
    
    func completePlan(_ plan: TrainingPlanRecord) {
        plan.status = TrainingPlanRecord.PlanStatus.completed.rawValue
        plan.endDate = Date()
        plan.updatedAt = Date()
        savePlanChange(action: "complete")
    }
    
    func deletePlan(_ plan: TrainingPlanRecord) {
        plan.deletedAt = Date()
        plan.updatedAt = Date()
        savePlanChange(action: "delete")
    }

    private func savePlanChange(action: String) {
        do {
            try modelContext.save()
            Loggers.ai.info("ai.training_plan_\(action)")
        } catch {
            Loggers.ai.error("ai.training_plan_\(action)_failed", metadata: ["error": error.localizedDescription])
        }
    }
}

private extension TrainingPlanService {
    
    func fetchRecentActivityData() async throws -> [DailyStepSummary] {
        guard HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) else {
            Loggers.sync.info("healthkit.fetch_skipped", metadata: [
                "reason": "sync_disabled",
                "scope": "training_plan_recent"
            ])
            return []
        }
        let settings = ActivitySettings.current(userDefaults: userDefaults)
        return try await healthKitService.fetchDailySummaries(
            days: 14,
            activityMode: settings.activityMode,
            distanceMode: settings.distanceMode,
            manualStepLength: settings.manualStepLength,
            dailyGoal: goalService.currentGoal
        )
    }
    
    func buildPlanPrompt(
        goal: TrainingGoalType,
        level: FitnessLevel,
        daysPerWeek: Int,
        recentData: [DailyStepSummary]
    ) -> String {
        let unitLabel = ActivitySettings.current(userDefaults: userDefaults).activityMode.unitName
        let averageSteps = recentData.isEmpty ? 0 : recentData.reduce(0) { $0 + $1.steps } / recentData.count
        let goalMetDays = recentData.filter { $0.steps >= $0.goal }.count
        let dataReliabilityNote = recentData.isEmpty
            ? """

            DATA RELIABILITY WARNING:
            Recent activity data is unavailable (HealthKit sync disabled or still syncing). Avoid strong assumptions about past activity and keep the plan conservative.
            """
            : ""
        
        return """
        Create a personalized training plan with the following parameters:
        
        Goal: \(goal.displayName) (internal: \(goal.aiGoal.rawValue))
        Fitness Level: \(level.displayName)
        Available Days: \(daysPerWeek) days per week
        
        User's Current Status (last 14 days):
        - Average daily \(unitLabel): \(averageSteps.formatted())
        - Goal achievement rate: \(recentData.isEmpty ? 0 : (goalMetDays * 100) / recentData.count)%
        \(dataReliabilityNote)

        Create a progressive 4-week plan that:
        1. Starts at an achievable level based on current activity
        2. Gradually increases intensity (5-10% per week)
        3. Includes specific daily step targets for each week
        4. Has clear milestones and checkpoints

        Safety constraints:
        - Do not provide medical advice or discuss injuries/conditions
        - Avoid weight-loss promises or numbers; keep weight-management guidance general
        - Keep the tone encouraging and non-judgmental

        Keep the plan realistic and motivating.
        """
    }
    
    func buildWeeklyRecommendationPrompt(recentData: [DailyStepSummary]) -> String {
        let unitLabel = ActivitySettings.current(userDefaults: userDefaults).activityMode.unitName
        let averageSteps = recentData.isEmpty ? 0 : recentData.reduce(0) { $0 + $1.steps } / recentData.count
        let maxSteps = recentData.max(by: { $0.steps < $1.steps })?.steps ?? 0
        let goalMetDays = recentData.filter { $0.steps >= $0.goal }.count
        let dataReliabilityNote = recentData.isEmpty
            ? """

            DATA RELIABILITY WARNING:
            Recent activity data is unavailable (HealthKit sync disabled or still syncing). Recommend a gentle, low-risk workout and suggest enabling HealthKit sync.
            """
            : ""
        
        return """
        Recommend a workout for today based on:
        
        Recent Activity (last 14 days):
        - Average daily \(unitLabel): \(averageSteps.formatted())
        - Best day: \(maxSteps.formatted()) \(unitLabel)
        - Goal achievement: \(recentData.isEmpty ? 0 : (goalMetDays * 100) / recentData.count)%
        \(dataReliabilityNote)
        
        Consider:
        - Recovery needs if recent days were very active
        - Opportunity to push if activity has been low
        - Best time of day based on patterns
        - Appropriate difficulty level

        Safety constraints:
        - Do not provide medical advice
        - Avoid weight-loss promises or numbers
        - Keep the recommendation realistic and encouraging

        Provide a single, actionable workout recommendation.
        """
    }
    
    func createPlanRecord(from aiPlan: AITrainingPlan, goal: TrainingGoalType) -> TrainingPlanRecord {
        let record = TrainingPlanRecord()
        record.name = aiPlan.name
        record.planDescription = aiPlan.planDescription
        record.primaryGoal = goal.rawValue
        record.startDate = Date()
        
        do {
            record.weeklyTargetsJSON = try JSONEncoder().encode(aiPlan.weeklyTargets)
        } catch {
            Loggers.ai.error("ai.training_plan_weekly_targets_encode_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
        
        if aiPlan.primaryGoal != goal.aiGoal {
            Loggers.ai.warning("ai.training_plan_goal_mismatch", metadata: [
                "requested_goal": goal.rawValue,
                "ai_goal": aiPlan.primaryGoal.rawValue
            ])
        }
        
        return record
    }
}
