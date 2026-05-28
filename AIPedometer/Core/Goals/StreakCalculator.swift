import Foundation

@MainActor
protocol StreakCalculating: AnyObject {
    func calculateCurrentStreak() async throws -> StreakResult
}

@MainActor
final class StreakCalculator {
    /// Maximum consecutive days the streak walk will consider. Also bounds the single
    /// historical-window query below, so it must stay in sync with the lookback span.
    static let maxLookbackDays = 400

    private let calendar: Calendar
    private let stepAggregator: any StepHistoryProviding
    private let goalService: any GoalServiceProtocol

    init(
        calendar: Calendar = .autoupdatingCurrent,
        stepAggregator: any StepHistoryProviding,
        goalService: any GoalServiceProtocol
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

        // Prefetch the entire historical window in ONE bucketed query instead of issuing one
        // HKStatisticsQuery per day (previously up to `maxLookbackDays` serial round-trips, which
        // got slower the longer a user's streak grew). The per-day comparison below is unchanged.
        let windowStart = calendar.date(byAdding: .day, value: -Self.maxLookbackDays, to: today) ?? today
        let dailySteps = try await stepAggregator.fetchDailySteps(from: windowStart, to: today)

        var streakCount = 0
        var currentDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        for _ in 0..<Self.maxLookbackDays {
            let dayStart = calendar.startOfDay(for: currentDate)
            let steps = dailySteps[dayStart] ?? 0
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
