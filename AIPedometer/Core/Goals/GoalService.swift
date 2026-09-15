import Foundation
import SwiftData

@MainActor
protocol GoalServiceProtocol: AnyObject, Sendable {
    var currentGoal: Int { get }
    func goal(for date: Date) -> Int?
    /// The goal a whole calendar day is judged by: the one that took effect last on that day.
    ///
    /// Daily summaries are dated at start-of-day, so `goal(for: summary.date)` judged a day on which the goal
    /// changed at 14:00 by the goal from before the change, while the dashboard already showed the new one.
    func goal(forDayContaining date: Date, calendar: Calendar) -> Int?
    @discardableResult
    func setGoal(_ value: Int) -> Bool
}

extension GoalServiceProtocol {
    func goal(forDayContaining date: Date) -> Int? {
        goal(forDayContaining: date, calendar: .autoupdatingCurrent)
    }

    /// Instant-based approximation for conformers that only know `goal(for:)`.
    func goal(forDayContaining date: Date, calendar: Calendar) -> Int? {
        let dayStart = calendar.startOfDay(for: date)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return goal(for: date)
        }
        return goal(for: nextDayStart.addingTimeInterval(-0.001)) ?? goal(for: dayStart)
    }
}

@MainActor
final class GoalService: GoalServiceProtocol, Sendable {
    private let persistence: PersistenceController
    private let saveModelContext: @MainActor (ModelContext) throws -> Void
    private let fetchGoals: @MainActor (ModelContext, FetchDescriptor<StepGoal>) throws -> [StepGoal]

    /// Non-deleted goals sorted by `startDate` descending. Every `StepGoal` read and write
    /// in the app goes through this service, so `setGoal` is the only invalidation point.
    /// Without this cache each `goal(for:)`/`currentGoal` call ran a full-table fetch —
    /// `StreakCalculator` calls `goal(for:)` once per streak day (up to 400× per refresh).
    private var cachedGoals: [StepGoal]?

    init(
        persistence: PersistenceController,
        saveModelContext: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        fetchGoals: @escaping @MainActor (ModelContext, FetchDescriptor<StepGoal>) throws -> [StepGoal] = {
            try $0.fetch($1)
        }
    ) {
        self.persistence = persistence
        self.saveModelContext = saveModelContext
        self.fetchGoals = fetchGoals
    }

    private func sortedGoals() -> [StepGoal] {
        if let cachedGoals {
            return cachedGoals
        }
        let context = persistence.container.mainContext
        let descriptor = FetchDescriptor<StepGoal>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        do {
            let goals = try fetchGoals(context, descriptor)
            cachedGoals = goals
            return goals
        } catch {
            // Do not cache the failure result; the next call should retry the fetch.
            Loggers.tracking.error("goal.fetch_failed", metadata: [
                "scope": "goals",
                "error": error.localizedDescription
            ])
            return []
        }
    }

    var currentGoal: Int {
        sortedGoals().first?.dailySteps ?? AppConstants.defaultDailyGoal
    }

    func goal(for date: Date) -> Int? {
        sortedGoals().first(where: { goal in
            goal.startDate <= date && (goal.endDate ?? date) >= date
        })?.dailySteps
    }

    /// The latest-starting goal that was active at any moment of that day. Overlap rather than a single
    /// end-of-day instant, because stores written before `setGoal` shared one `now` between the closed and
    /// the new goal can hold a gap at the boundary, where an instant would match no goal at all.
    func goal(forDayContaining date: Date, calendar: Calendar) -> Int? {
        let dayStart = calendar.startOfDay(for: date)
        guard let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return goal(for: date)
        }
        // `sortedGoals()` is ordered by `startDate` descending, so the first overlap is the latest to start.
        return sortedGoals().first(where: { goal in
            goal.startDate < nextDayStart && (goal.endDate ?? nextDayStart) >= dayStart
        })?.dailySteps
    }

    @discardableResult
    func setGoal(_ value: Int) -> Bool {
        let context = persistence.container.mainContext
        let descriptor = FetchDescriptor<StepGoal>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endDate == nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let activeGoals: [StepGoal]
        do {
            activeGoals = try fetchGoals(context, descriptor)
        } catch {
            // A failed read does not prove there is no open goal. Inserting anyway would leave two open
            // goals, and every later lookup would pick one arbitrarily, so refuse the change instead.
            Loggers.tracking.error("goal.fetch_failed", metadata: [
                "scope": "active",
                "error": error.localizedDescription
            ])
            return false
        }
        let now = Date()
        let previousActiveGoalState = activeGoals.map { goal in
            (goal: goal, endDate: goal.endDate, updatedAt: goal.updatedAt)
        }
        for goal in activeGoals {
            goal.endDate = now
            goal.updatedAt = now
        }
        // Reuse the single `now` for the new goal's start so the previous goal's `endDate`
        // and the new goal's `startDate` are identical. Two separate `Date()` reads leave a
        // sub-millisecond window in which `goal(for:)` matches neither goal and falls back to
        // the default daily goal.
        let goal = StepGoal(dailySteps: value, startDate: now)
        context.insert(goal)
        do {
            try saveModelContext(context)
        } catch {
            context.delete(goal)
            for previousState in previousActiveGoalState {
                previousState.goal.endDate = previousState.endDate
                previousState.goal.updatedAt = previousState.updatedAt
            }
            Loggers.tracking.error("goal.save_failed", metadata: ["error": error.localizedDescription])
            cachedGoals = nil
            return false
        }
        cachedGoals = nil
        return true
    }
}
