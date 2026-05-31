import Foundation
import Testing

@testable import AIPedometer

/// Regression coverage for `StreakCalculator`. Before 2026-05-28 this core, date-sensitive
/// feature had no direct tests, and it issued one HealthKit query per day (up to 400 serial
/// round-trips). These tests pin both the streak semantics and the "single bucketed query"
/// performance contract.
@MainActor
struct StreakCalculatorTests {
    private let calendar = Calendar.autoupdatingCurrent

    /// Start-of-day for `offset` days relative to today, matching how `StreakCalculator`
    /// keys its prefetched daily-step dictionary.
    private func day(_ offset: Int) -> Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: offset, to: today) ?? today
    }

    private func makeCalculator(
        todaySteps: Int,
        daily: [Date: Int],
        currentGoal: Int,
        goalForDate: @escaping @MainActor (Date) -> Int? = { _ in nil }
    ) -> (StreakCalculator, FakeStepHistory) {
        let history = FakeStepHistory(todaySteps: todaySteps, daily: daily)
        let goals = FakeGoalService(currentGoal: currentGoal, goalForDate: goalForDate)
        let calculator = StreakCalculator(
            calendar: calendar,
            stepAggregator: history,
            goalService: goals
        )
        return (calculator, history)
    }

    @Test("Counts consecutive met days including today")
    func countsConsecutiveMetDaysIncludingToday() async throws {
        let (calculator, _) = makeCalculator(
            todaySteps: 12_000,
            daily: [day(-1): 11_000, day(-2): 10_000, day(-3): 3_000],
            currentGoal: 10_000
        )

        let result = try await calculator.calculateCurrentStreak()

        #expect(result.count == 3) // today + day-1 + day-2, broken at day-3
        #expect(result.todayIncluded)
        #expect(result.isActive)
    }

    @Test("Preserves prior streak when today's goal is not yet met")
    func preservesPriorStreakWhenTodayNotMet() async throws {
        let (calculator, _) = makeCalculator(
            todaySteps: 2_000,
            daily: [day(-1): 11_000, day(-2): 11_000, day(-3): 0],
            currentGoal: 10_000
        )

        let result = try await calculator.calculateCurrentStreak()

        #expect(result.count == 2) // day-1 + day-2; today not counted
        #expect(result.todayIncluded == false)
    }

    @Test("A gap immediately before today breaks the historical streak")
    func gapBreaksStreak() async throws {
        let (calculator, _) = makeCalculator(
            todaySteps: 12_000,
            daily: [day(-1): 0, day(-2): 11_000],
            currentGoal: 10_000
        )

        let result = try await calculator.calculateCurrentStreak()

        #expect(result.count == 1) // only today; yesterday's gap stops the walk
        #expect(result.todayIncluded)
    }

    @Test("Uses the per-day historical goal, not just the current goal")
    func usesHistoricalGoalPerDay() async throws {
        // day-1 met the historical 5,000 goal but would fail today's 10,000 goal.
        let (calculator, _) = makeCalculator(
            todaySteps: 12_000,
            daily: [day(-1): 6_000, day(-2): 0],
            currentGoal: 10_000,
            goalForDate: { date in
                self.calendar.isDate(date, inSameDayAs: self.day(-1)) ? 5_000 : nil
            }
        )

        let result = try await calculator.calculateCurrentStreak()

        #expect(result.count == 2) // today + day-1 (against its historical goal)
    }

    @Test("Empty history yields a zero, inactive streak")
    func emptyHistoryYieldsZeroStreak() async throws {
        let (calculator, _) = makeCalculator(
            todaySteps: 0,
            daily: [:],
            currentGoal: 10_000
        )

        let result = try await calculator.calculateCurrentStreak()

        #expect(result.count == 0)
        #expect(result.isActive == false)
        #expect(result.todayIncluded == false)
        // A zero-length streak has no start date. The previous implementation computed a date
        // one day in the *future* here (`-(0 - 1)` = +1 day).
        #expect(result.streakStartDate == nil)
    }

    @Test("Active streak reports the first day of the streak as its start date")
    func activeStreakReportsStartDate() async throws {
        let (calculator, _) = makeCalculator(
            todaySteps: 12_000,
            daily: [day(-1): 11_000, day(-2): 10_000, day(-3): 3_000],
            currentGoal: 10_000
        )

        let result = try await calculator.calculateCurrentStreak()

        #expect(result.count == 3) // today + day-1 + day-2
        let expectedStart = calendar.startOfDay(for: day(-2))
        #expect(result.streakStartDate.map { calendar.startOfDay(for: $0) } == expectedStart)
    }

    @Test("Streak walk is bounded by maxLookbackDays even with an unbroken history")
    func boundedByMaxLookback() async throws {
        var daily: [Date: Int] = [:]
        for offset in 1...(StreakCalculator.maxLookbackDays + 50) {
            daily[day(-offset)] = 20_000
        }
        let (calculator, _) = makeCalculator(
            todaySteps: 20_000,
            daily: daily,
            currentGoal: 10_000
        )

        let result = try await calculator.calculateCurrentStreak()

        // maxLookbackDays historical days + today.
        #expect(result.count == StreakCalculator.maxLookbackDays + 1)
    }

    @Test("Performance contract: one daily-window query, no per-day fan-out")
    func issuesSingleBucketedQuery() async throws {
        var daily: [Date: Int] = [:]
        for offset in 1...30 {
            daily[day(-offset)] = 15_000
        }
        let (calculator, history) = makeCalculator(
            todaySteps: 15_000,
            daily: daily,
            currentGoal: 10_000
        )

        _ = try await calculator.calculateCurrentStreak()

        // Exactly one partial "today" query + one bucketed daily-window query, regardless of
        // streak length. This guards against regressing to the old one-query-per-day loop.
        #expect(await history.fetchStepsCallCount == 1)
        #expect(await history.fetchDailyStepsCallCount == 1)
    }
}

// MARK: - Test doubles

private actor FakeStepHistory: StepHistoryProviding {
    private let todayStepsValue: Int
    private let daily: [Date: Int]
    private(set) var fetchStepsCallCount = 0
    private(set) var fetchDailyStepsCallCount = 0

    init(todaySteps: Int, daily: [Date: Int]) {
        self.todayStepsValue = todaySteps
        self.daily = daily
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        fetchStepsCallCount += 1
        return todayStepsValue
    }

    func fetchDailySteps(from startDate: Date, to endDate: Date) async throws -> [Date: Int] {
        fetchDailyStepsCallCount += 1
        return daily
    }
}

@MainActor
private final class FakeGoalService: GoalServiceProtocol {
    private let currentGoalValue: Int
    private let goalForDate: @MainActor (Date) -> Int?

    init(currentGoal: Int, goalForDate: @escaping @MainActor (Date) -> Int?) {
        self.currentGoalValue = currentGoal
        self.goalForDate = goalForDate
    }

    var currentGoal: Int { currentGoalValue }
    func goal(for date: Date) -> Int? { goalForDate(date) }
    func setGoal(_ value: Int) {}
}
