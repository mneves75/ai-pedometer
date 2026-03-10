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
    private let saveModelContext: @MainActor (ModelContext) throws -> Void
    private let userDefaults: UserDefaults

    private(set) var isGenerating = false
    private(set) var lastError: AIServiceError?

    init(
        foundationModelsService: any FoundationModelsServiceProtocol,
        healthKitService: any HealthKitServiceProtocol,
        goalService: any GoalServiceProtocol,
        modelContext: ModelContext,
        saveModelContext: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        userDefaults: UserDefaults = .standard
    ) {
        self.foundationModelsService = foundationModelsService
        self.healthKitService = healthKitService
        self.goalService = goalService
        self.modelContext = modelContext
        self.saveModelContext = saveModelContext
        self.userDefaults = userDefaults
    }
    
    func generatePlan(
        goal: TrainingGoalType,
        level: FitnessLevel,
        daysPerWeek: Int
    ) async throws(AIServiceError) -> TrainingPlanRecord {
        guard !isGenerating else {
            throw AIServiceError.generationFailed(underlying: "Please try again in a moment")
        }
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

            let fallbackPlan = makeFallbackPlan(
                goal: goal,
                level: level,
                daysPerWeek: daysPerWeek,
                recentData: recentData
            )
            let resolvedPlan: AITrainingPlan

            do {
                let aiPlan: AITrainingPlan = try await foundationModelsService.respond(
                    to: prompt,
                    as: AITrainingPlan.self
                )
                try validate(aiPlan: aiPlan, expectedGoal: goal, daysPerWeek: daysPerWeek)
                resolvedPlan = localizedPlan(aiPlan, goal: goal)
            } catch let error {
                guard shouldUseFallback(for: error) else {
                    throw error
                }
                resolvedPlan = fallbackPlan
                Loggers.ai.warning("ai.training_plan_fallback", metadata: [
                    "goal": goal.rawValue,
                    "level": level.rawValue,
                    "reason": error.logDescription
                ])
            }

            let record = try createPlanRecord(from: resolvedPlan, goal: goal)
            modelContext.insert(record)
            try saveModelContext(modelContext)
            
            Loggers.ai.info("ai.training_plan_generated", metadata: [
                "goal": goal.rawValue,
                "level": level.rawValue,
                "weeks": "\(resolvedPlan.weeklyTargets.count)"
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
        guard !isGenerating else {
            throw AIServiceError.generationFailed(underlying: "Please try again in a moment")
        }
        guard foundationModelsService.availability.isAvailable else {
            throw AIServiceError.modelUnavailable(.modelNotReady)
        }

        isGenerating = true
        lastError = nil
        defer { isGenerating = false }

        do {
            let recentData = try await fetchRecentActivityData()
            let prompt = buildWeeklyRecommendationPrompt(recentData: recentData)
            let recommendation: AIWorkoutRecommendation

            do {
                recommendation = try await foundationModelsService.respond(
                    to: prompt,
                    as: AIWorkoutRecommendation.self
                )
            } catch let error {
                guard shouldUseFallback(for: error) else {
                    throw error
                }
                let fallback = makeFallbackWeeklyRecommendation(recentData: recentData)
                Loggers.ai.warning("ai.training_plan_weekly_recommendation_fallback", metadata: [
                    "reason": error.logDescription
                ])
                return fallback
            }

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
            return try modelContext.fetch(descriptor).filter(\.isActive)
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
        applyPlanMutation(action: "pause", to: plan) {
            plan.status = TrainingPlanRecord.PlanStatus.paused.rawValue
            plan.updatedAt = Date()
        }
    }
    
    func resumePlan(_ plan: TrainingPlanRecord) {
        applyPlanMutation(action: "resume", to: plan) {
            plan.status = TrainingPlanRecord.PlanStatus.active.rawValue
            plan.updatedAt = Date()
        }
    }
    
    func completePlan(_ plan: TrainingPlanRecord) {
        applyPlanMutation(action: "complete", to: plan) {
            plan.status = TrainingPlanRecord.PlanStatus.completed.rawValue
            plan.endDate = Date()
            plan.updatedAt = Date()
        }
    }
    
    func deletePlan(_ plan: TrainingPlanRecord) {
        applyPlanMutation(action: "delete", to: plan) {
            plan.deletedAt = Date()
            plan.updatedAt = Date()
        }
    }

    private func applyPlanMutation(
        action: String,
        to plan: TrainingPlanRecord,
        mutation: () -> Void
    ) {
        let previousStatus = plan.status
        let previousEndDate = plan.endDate
        let previousUpdatedAt = plan.updatedAt
        let previousDeletedAt = plan.deletedAt
        mutation()
        do {
            try saveModelContext(modelContext)
            Loggers.ai.info("ai.training_plan_\(action)")
        } catch {
            plan.status = previousStatus
            plan.endDate = previousEndDate
            plan.updatedAt = previousUpdatedAt
            plan.deletedAt = previousDeletedAt
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
        let languageInstruction = AppLanguage.promptInstruction()
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

        Language:
        - \(languageInstruction)
        
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
        let languageInstruction = AppLanguage.promptInstruction()
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

        Language:
        - \(languageInstruction)
        
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
    
    func createPlanRecord(from aiPlan: AITrainingPlan, goal: TrainingGoalType) throws(AIServiceError) -> TrainingPlanRecord {
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
            throw .invalidResponse
        }
        
        if aiPlan.primaryGoal != goal.aiGoal {
            Loggers.ai.warning("ai.training_plan_goal_mismatch", metadata: [
                "requested_goal": goal.rawValue,
                "ai_goal": aiPlan.primaryGoal.rawValue
            ])
        }
        
        return record
    }

    func validate(aiPlan: AITrainingPlan, expectedGoal: TrainingGoalType, daysPerWeek: Int) throws(AIServiceError) {
        guard aiPlan.primaryGoal == expectedGoal.aiGoal else {
            throw .invalidResponse
        }
        guard aiPlan.durationWeeks == aiPlan.weeklyTargets.count else {
            throw .invalidResponse
        }
        guard !aiPlan.weeklyTargets.isEmpty else {
            throw .invalidResponse
        }

        for (expectedWeek, target) in aiPlan.weeklyTargets.enumerated() {
            guard target.weekNumber == expectedWeek + 1 else {
                throw .invalidResponse
            }
            guard target.activeDaysRequired <= daysPerWeek else {
                throw .invalidResponse
            }
        }
    }

    func shouldUseFallback(for error: AIServiceError) -> Bool {
        switch error {
        case .sessionNotConfigured, .modelUnavailable:
            return false
        case .generationFailed, .tokenLimitExceeded, .guardrailViolation, .invalidResponse:
            return true
        }
    }

    func localizedPlan(_ aiPlan: AITrainingPlan, goal: TrainingGoalType) -> AITrainingPlan {
        let localizedTargets = aiPlan.weeklyTargets.enumerated().map { index, target in
            WeeklyTarget(
                weekNumber: index + 1,
                dailyStepTarget: target.dailyStepTarget,
                activeDaysRequired: target.activeDaysRequired,
                focusTip: localizedFocusTip(for: index)
            )
        }

        return AITrainingPlan(
            name: goal.displayName,
            planDescription: goal.description,
            durationWeeks: localizedTargets.count,
            weeklyTargets: localizedTargets,
            primaryGoal: goal.aiGoal
        )
    }

    func makeFallbackPlan(
        goal: TrainingGoalType,
        level: FitnessLevel,
        daysPerWeek: Int,
        recentData: [DailyStepSummary]
    ) -> AITrainingPlan {
        let targets = fallbackWeeklyTargets(
            goal: goal,
            level: level,
            daysPerWeek: daysPerWeek,
            recentData: recentData
        )

        return AITrainingPlan(
            name: goal.displayName,
            planDescription: goal.description,
            durationWeeks: targets.count,
            weeklyTargets: targets,
            primaryGoal: goal.aiGoal
        )
    }

    func fallbackWeeklyTargets(
        goal: TrainingGoalType,
        level: FitnessLevel,
        daysPerWeek: Int,
        recentData: [DailyStepSummary]
    ) -> [WeeklyTarget] {
        let baseline = max(
            recentData.isEmpty
                ? defaultBaseline(for: level)
                : recentData.reduce(0) { $0 + $1.steps } / max(recentData.count, 1),
            1_500
        )
        let desiredTarget = desiredTargetSteps(goal: goal, level: level, baseline: baseline)
        let startMultiplier: Double
        switch level {
        case .beginner:
            startMultiplier = 0.9
        case .intermediate:
            startMultiplier = 1.0
        case .advanced:
            startMultiplier = 1.08
        }
        let firstWeekTarget = min(
            desiredTarget,
            roundedStepTarget(Int(Double(baseline) * startMultiplier))
        )
        let activeDays = min(daysPerWeek, max(3, daysPerWeek - (level == .beginner ? 1 : 0)))

        return (0..<4).map { index in
            let progress = Double(index) / 3.0
            let interpolatedTarget = Int(
                Double(firstWeekTarget) + Double(desiredTarget - firstWeekTarget) * progress
            )

            return WeeklyTarget(
                weekNumber: index + 1,
                dailyStepTarget: roundedStepTarget(interpolatedTarget),
                activeDaysRequired: activeDays,
                focusTip: localizedFocusTip(for: index)
            )
        }
    }

    func makeFallbackWeeklyRecommendation(recentData: [DailyStepSummary]) -> AIWorkoutRecommendation {
        let baseline = recentData.isEmpty
            ? goalService.currentGoal / 2
            : recentData.reduce(0) { $0 + $1.steps } / max(recentData.count, 1)
        let goalMetDays = recentData.filter { $0.steps >= $0.goal }.count
        let intent: WorkoutIntent = if goalMetDays <= 2 {
            .build
        } else if goalMetDays >= 5 {
            .recover
        } else {
            .maintain
        }
        let targetSteps = min(max(roundedStepTarget(max(baseline / 2, 2_000)), 2_000), 10_000)
        let estimatedMinutes = min(max(Int(Double(targetSteps) / 110), 15), 75)

        return AIWorkoutRecommendation(
            intent: intent,
            difficulty: fallbackDifficulty(for: intent),
            rationale: intent.localizedDescription,
            targetSteps: targetSteps,
            estimatedMinutes: estimatedMinutes,
            suggestedTimeOfDay: .anytime
        )
    }

    func desiredTargetSteps(goal: TrainingGoalType, level: FitnessLevel, baseline: Int) -> Int {
        let currentGoal = goalService.currentGoal
        let rawTarget: Int
        switch goal {
        case .startWalking:
            rawTarget = max(4_000, baseline + 1_000)
        case .reach10k:
            rawTarget = max(10_000, currentGoal)
        case .improveConsistency:
            rawTarget = max(baseline, Int(Double(currentGoal) * 0.85))
        case .buildEndurance:
            rawTarget = max(baseline + 2_000, currentGoal)
        case .weightManagement:
            rawTarget = max(baseline + 1_500, Int(Double(currentGoal) * 0.9))
        }

        let levelAdjustment: Int
        switch level {
        case .beginner:
            levelAdjustment = -500
        case .intermediate:
            levelAdjustment = 0
        case .advanced:
            levelAdjustment = 1_000
        }

        return roundedStepTarget(max(3_000, rawTarget + levelAdjustment))
    }

    func defaultBaseline(for level: FitnessLevel) -> Int {
        switch level {
        case .beginner:
            3_500
        case .intermediate:
            6_000
        case .advanced:
            8_000
        }
    }

    func roundedStepTarget(_ value: Int) -> Int {
        let rounded = Int((Double(value) / 250.0).rounded()) * 250
        return max(1_500, rounded)
    }

    func localizedFocusTip(for index: Int) -> String {
        switch index {
        case 0:
            return L10n.localized(
                "Start a little below your limit and make the routine easy to repeat.",
                comment: "Fallback focus tip for the first training week"
            )
        case 1:
            return L10n.localized(
                "Add volume gradually and protect your recovery between sessions.",
                comment: "Fallback focus tip for the second training week"
            )
        case 2:
            return L10n.localized(
                "Keep your strongest routine and prioritize consistency.",
                comment: "Fallback focus tip for the third training week"
            )
        default:
            return L10n.localized(
                "Finish the block with steady effort and confident form.",
                comment: "Fallback focus tip for the final training week"
            )
        }
    }

    func fallbackDifficulty(for intent: WorkoutIntent) -> Int {
        switch intent {
        case .recover:
            return 1
        case .maintain:
            return 2
        case .explore:
            return 3
        case .build:
            return 4
        }
    }
}
