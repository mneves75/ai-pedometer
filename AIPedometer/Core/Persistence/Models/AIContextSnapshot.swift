import Foundation
import SwiftData

/// Caches aggregated user data for fast AI context injection.
/// Updated on sync; AI services read from this instead of querying HealthKit directly.
@Model
final class AIContextSnapshot {
    // MARK: - Last 7 Days
    
    /// Daily step totals for the past 7 days (index 0 = oldest, 6 = today)
    var last7DaysSteps: [Int]
    
    /// Average steps per day over the last 7 days
    var last7DaysAverage: Int
    
    /// Number of days goal was hit in the last 7 days
    var last7DaysGoalHitCount: Int
    
    // MARK: - Last 4 Weeks
    
    /// Weekly averages for the past 4 weeks (index 0 = oldest, 3 = current)
    var last4WeeksAverages: [Int]
    
    /// Trend direction: "increasing", "decreasing", or "stable"
    var weekOverWeekTrend: String
    
    // MARK: - Streaks
    
    var currentStreak: Int
    var longestStreak: Int
    
    // MARK: - Recent Activity
    
    var recentWorkoutCount: Int
    var lastWorkoutDate: Date?
    var totalBadgesEarned: Int
    
    // MARK: - Goals
    
    var currentDailyGoal: Int
    
    // MARK: - Metadata
    
    var snapshotDate: Date
    var lastUpdated: Date
    var deletedAt: Date?
    
    init(
        last7DaysSteps: [Int] = [],
        last7DaysAverage: Int = 0,
        last7DaysGoalHitCount: Int = 0,
        last4WeeksAverages: [Int] = [],
        weekOverWeekTrend: String = "stable",
        currentStreak: Int = 0,
        longestStreak: Int = 0,
        recentWorkoutCount: Int = 0,
        lastWorkoutDate: Date? = nil,
        totalBadgesEarned: Int = 0,
        currentDailyGoal: Int = 10000
    ) {
        self.last7DaysSteps = last7DaysSteps
        self.last7DaysAverage = last7DaysAverage
        self.last7DaysGoalHitCount = last7DaysGoalHitCount
        self.last4WeeksAverages = last4WeeksAverages
        self.weekOverWeekTrend = weekOverWeekTrend
        self.currentStreak = currentStreak
        self.longestStreak = longestStreak
        self.recentWorkoutCount = recentWorkoutCount
        self.lastWorkoutDate = lastWorkoutDate
        self.totalBadgesEarned = totalBadgesEarned
        self.currentDailyGoal = currentDailyGoal
        self.snapshotDate = Date.now
        self.lastUpdated = Date.now
    }
    
    /// Formats the snapshot as a prompt-friendly string for AI consumption.
    var aiPromptContext: String {
        var lines: [String] = []
        
        lines.append("User Activity Summary:")
        lines.append("- Current daily goal: \(currentDailyGoal.formatted()) steps")
        lines.append("- Current streak: \(currentStreak) days")
        lines.append("- Longest streak: \(longestStreak) days")
        lines.append("- Total badges earned: \(totalBadgesEarned)")
        
        if !last7DaysSteps.isEmpty {
            lines.append("\nLast 7 Days:")
            lines.append("- Daily steps: \(last7DaysSteps.map { $0.formatted() }.joined(separator: ", "))")
            lines.append("- Average: \(last7DaysAverage.formatted()) steps/day")
            lines.append("- Days goal met: \(last7DaysGoalHitCount) of 7")
        }
        
        if !last4WeeksAverages.isEmpty {
            lines.append("\nWeekly Trend:")
            lines.append("- Weekly averages: \(last4WeeksAverages.map { $0.formatted() }.joined(separator: ", "))")
            lines.append("- Trend: \(weekOverWeekTrend)")
        }
        
        if recentWorkoutCount > 0 {
            lines.append("\nWorkouts:")
            lines.append("- Recent workouts (30 days): \(recentWorkoutCount)")
            if let lastDate = lastWorkoutDate {
                lines.append("- Last workout: \(lastDate.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}
