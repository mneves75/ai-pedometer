import Foundation

@MainActor
protocol StreakCalculating: AnyObject {
    func calculateCurrentStreak() async throws -> StreakResult
}

@MainActor
final class StreakCalculator {
    private let calendar: Calendar
    private let stepAggregator: StepDataAggregator
    private let goalService: GoalService

    init(
        calendar: Calendar = .autoupdatingCurrent,
        stepAggregator: StepDataAggregator,
        goalService: GoalService
    ) {
        self.calendar = calendar
        self.stepAggregator = stepAggregator
        self.goalService = goalService
    }

    func calculateCurrentStreak() async throws -> StreakResult {
        let today = calendar.startOfDay(for: .now)
        let goal = goalService.currentGoal
        let todaySteps = try await stepAggregator.fetchSteps(from: today, to: .now)
        let todayGoalMet = todaySteps >= goal

        var streakCount = 0
        var currentDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        for _ in 0..<400 {
            let start = calendar.startOfDay(for: currentDate)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let steps = try await stepAggregator.fetchSteps(from: start, to: end)
            let historicalGoal = goalService.goal(for: currentDate) ?? goal
            if steps >= historicalGoal {
                streakCount += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            } else {
                break
            }
        }

        if todayGoalMet {
            streakCount += 1
        }

        let startDate = calendar.date(byAdding: .day, value: -(streakCount - 1), to: today)
        return StreakResult(count: streakCount, todayIncluded: todayGoalMet, streakStartDate: startDate)
    }
}

extension StreakCalculator: StreakCalculating {}

struct StreakResult: Sendable {
    let count: Int
    let todayIncluded: Bool
    let streakStartDate: Date?

    var isActive: Bool {
        count > 0
    }
}
