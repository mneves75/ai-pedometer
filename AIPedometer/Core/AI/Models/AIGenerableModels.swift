import Foundation
import FoundationModels

@Generable
struct DailyInsight: Sendable {
    @Guide(description: "A motivational greeting based on user's activity level today")
    let greeting: String

    @Guide(description: "Factual observation about today's progress. Must be grounded in the actual data provided - never claim achievements that weren't reached. For low or zero progress, acknowledge current state honestly.")
    let highlight: String

    @Guide(description: "One actionable suggestion to improve, appropriate to current progress level")
    let suggestion: String

    @Guide(description: "Encouraging closing statement that matches actual progress - supportive for low progress, celebratory only for real achievements")
    let encouragement: String
}

@Generable
struct WeeklyTrendAnalysis: Sendable {
    @Guide(description: "Summary of the week's activity in 1-2 sentences")
    let summary: String
    
    @Guide(description: "Notable trend direction")
    let trend: TrendDirection
    
    @Guide(description: "Specific observation about patterns noticed")
    let observation: String
    
    @Guide(description: "Actionable recommendation for next week")
    let recommendation: String
}

@Generable
enum TrendDirection: String, Codable, Sendable {
    case increasing
    case decreasing
    case stable
}

@Generable
struct GoalRecommendation: Sendable {
    @Guide(description: "Recommended daily step goal", .range(1000...50000))
    let recommendedGoal: Int
    
    @Guide(description: "Clear reasoning for this recommendation in 1-2 sentences")
    let reasoning: String
    
    @Guide(description: "Whether this goal is more challenging than current")
    let isChallenge: Bool
    
    @Guide(description: "Percentage change from current goal", .range(-50...100))
    let percentageChange: Int
}

@Generable
enum WorkoutIntent: String, Codable, Sendable, CaseIterable {
    case maintain
    case build
    case explore
    case recover
    
    var localizedTitle: String {
        switch self {
        case .maintain:
            L10n.localized("Maintain", comment: "Workout intent - maintain current fitness")
        case .build:
            L10n.localized("Build", comment: "Workout intent - push for improvement")
        case .explore:
            L10n.localized("Explore", comment: "Workout intent - try new activities")
        case .recover:
            L10n.localized("Recover", comment: "Workout intent - light restorative")
        }
    }
    
    var localizedDescription: String {
        switch self {
        case .maintain:
            L10n.localized("Keep your current fitness level steady", comment: "Maintain description")
        case .build:
            L10n.localized("Push yourself to improve", comment: "Build description")
        case .explore:
            L10n.localized("Try new routes or activities", comment: "Explore description")
        case .recover:
            L10n.localized("Light activity for recovery", comment: "Recover description")
        }
    }
}

@Generable
struct AIWorkoutRecommendation: Sendable {
    @Guide(description: "The intent category for this workout")
    let intent: WorkoutIntent
    
    @Guide(description: "Difficulty level 1-5", .range(1...5))
    let difficulty: Int
    
    @Guide(description: "Clear rationale for why this workout is recommended")
    let rationale: String
    
    @Guide(description: "Target step count for this workout", .range(1000...30000))
    let targetSteps: Int
    
    @Guide(description: "Estimated duration in minutes", .range(10...180))
    let estimatedMinutes: Int
    
    @Guide(description: "Best time of day to do this workout")
    let suggestedTimeOfDay: TimeOfDay
}

@Generable
enum TimeOfDay: String, Codable, Sendable {
    case morning
    case afternoon
    case evening
    case anytime
    
    var localizedTitle: String {
        switch self {
        case .morning:
            L10n.localized("Morning", comment: "Time of day")
        case .afternoon:
            L10n.localized("Afternoon", comment: "Time of day")
        case .evening:
            L10n.localized("Evening", comment: "Time of day")
        case .anytime:
            L10n.localized("Anytime", comment: "Time of day")
        }
    }
}

@Generable
struct AITrainingPlan: Sendable {
    @Guide(description: "Name of the training plan")
    let name: String
    
    @Guide(description: "Brief description of the plan's focus and goals")
    let planDescription: String
    
    @Guide(description: "Duration in weeks", .range(1...12))
    let durationWeeks: Int
    
    @Guide(description: "List of weekly targets")
    let weeklyTargets: [WeeklyTarget]
    
    @Guide(description: "The primary goal this plan helps achieve")
    let primaryGoal: TrainingGoal
}

@Generable
struct WeeklyTarget: Sendable, Codable {
    @Guide(description: "Week number", .range(1...12))
    let weekNumber: Int
    
    @Guide(description: "Daily step target for this week", .range(1000...50000))
    let dailyStepTarget: Int
    
    @Guide(description: "Number of active days required", .range(3...7))
    let activeDaysRequired: Int
    
    @Guide(description: "Focus tip for this week")
    let focusTip: String
    
    var targetDescription: String {
        "\(activeDaysRequired) active days, \(dailyStepTarget.formatted()) steps/day"
    }
}

@Generable
enum TrainingGoal: String, Codable, Sendable, CaseIterable {
    case startWalking = "start_walking"
    case reach10k = "reach_10k"
    case improveConsistency = "improve_consistency"
    case buildEndurance = "build_endurance"
    case weightManagement = "weight_management"
    
    var localizedTitle: String {
        switch self {
        case .startWalking:
            L10n.localized("Start Walking Regularly", comment: "Training goal")
        case .reach10k:
            L10n.localized("Reach 10,000 Steps Daily", comment: "Training goal")
        case .improveConsistency:
            L10n.localized("Improve Consistency", comment: "Training goal")
        case .buildEndurance:
            L10n.localized("Build Endurance", comment: "Training goal")
        case .weightManagement:
            L10n.localized("Support Weight Goals", comment: "Training goal")
        }
    }
}

@Generable
struct CoachResponse: Sendable {
    @Guide(description: "The main response to the user's question")
    let message: String
    
    @Guide(description: "Whether this response includes health-related advice")
    let containsHealthAdvice: Bool
    
    @Guide(description: "Suggested follow-up questions the user might ask", .count(0...3))
    let suggestedFollowUps: [String]
}

@Generable
struct AchievementCelebration: Sendable {
    @Guide(description: "Personalized congratulatory message")
    let congratulation: String
    
    @Guide(description: "What this achievement means for the user's journey")
    let significance: String
    
    @Guide(description: "Encouragement to keep going with next challenge")
    let nextChallenge: String
}

@Generable
struct ActivityPrediction: Sendable {
    @Guide(description: "Predicted step count by end of day", .range(0...100000))
    let predictedSteps: Int
    
    @Guide(description: "Confidence level 0-100", .range(0...100))
    let confidencePercent: Int
    
    @Guide(description: "Explanation of the prediction")
    let explanation: String
    
    @Guide(description: "Whether user is likely to meet their goal")
    let willMeetGoal: Bool
    
    @Guide(description: "Suggested time to reach goal if currently behind")
    let suggestedCompletionTime: String?
}
