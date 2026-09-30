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
    private let activityMode: @MainActor () -> ActivityTrackingMode

    init(
        calendar: Calendar = .autoupdatingCurrent,
        stepAggregator: any StepHistoryProviding,
        goalService: any GoalServiceProtocol,
        activityMode: @escaping @MainActor () -> ActivityTrackingMode = { ActivitySettings.current().activityMode }
    ) {
        self.calendar = calendar
        self.stepAggregator = stepAggregator
        self.goalService = goalService
        self.activityMode = activityMode
    }

    func calculateCurrentStreak() async throws -> StreakResult {
        let today = calendar.startOfDay(for: .now)
        let goal = goalService.currentGoal
        let mode = activityMode()
        let todaySteps = try await stepAggregator.fetchSteps(from: today, to: .now, activityMode: mode)
        let todayGoalMet = todaySteps >= goal

        // Prefetch the entire historical window in ONE bucketed query instead of issuing one
        // HKStatisticsQuery per day (previously up to `maxLookbackDays` serial round-trips, which
        // got slower the longer a user's streak grew). The per-day comparison below is unchanged.
        let windowStart = calendar.date(byAdding: .day, value: -Self.maxLookbackDays, to: today) ?? today
        let dailySteps = try await stepAggregator.fetchDailySteps(from: windowStart, to: today, activityMode: mode)

        var streakCount = 0
        var currentDate = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        for _ in 0..<Self.maxLookbackDays {
            let dayStart = calendar.startOfDay(for: currentDate)
            let steps = dailySteps[dayStart] ?? 0
            let historicalGoal = goalService.goal(forDayContaining: currentDate, calendar: calendar) ?? goal
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

        // A zero-length streak has no start date. Computing `-(streakCount - 1)` when
        // `streakCount == 0` would resolve to *tomorrow*, an incoherent value for an
        // inactive streak.
        let startDate = streakCount > 0
            ? calendar.date(byAdding: .day, value: -streakCount + (todayGoalMet ? 1 : 0), to: today)
            : nil
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
