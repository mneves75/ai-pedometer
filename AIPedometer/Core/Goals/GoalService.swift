import Foundation
import SwiftData

@MainActor
protocol GoalServiceProtocol: AnyObject, Sendable {
    var currentGoal: Int { get }
    func goal(for date: Date) -> Int?
    func setGoal(_ value: Int)
}

@MainActor
final class GoalService: GoalServiceProtocol, Sendable {
    private let persistence: PersistenceController

    /// Non-deleted goals sorted by `startDate` descending. Every `StepGoal` read and write
    /// in the app goes through this service, so `setGoal` is the only invalidation point.
    /// Without this cache each `goal(for:)`/`currentGoal` call ran a full-table fetch —
    /// `StreakCalculator` calls `goal(for:)` once per streak day (up to 400× per refresh).
    private var cachedGoals: [StepGoal]?

    init(persistence: PersistenceController) {
        self.persistence = persistence
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
            let goals = try context.fetch(descriptor)
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

    func setGoal(_ value: Int) {
        let context = persistence.container.mainContext
        let descriptor = FetchDescriptor<StepGoal>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endDate == nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let activeGoals: [StepGoal]
        do {
            activeGoals = try context.fetch(descriptor)
        } catch {
            Loggers.tracking.error("goal.fetch_failed", metadata: [
                "scope": "active",
                "error": error.localizedDescription
            ])
            activeGoals = []
        }
        let now = Date()
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
            try context.save()
        } catch {
            Loggers.tracking.error("goal.save_failed", metadata: ["error": error.localizedDescription])
        }
        // The context changed regardless of save success; drop the cache either way.
        cachedGoals = nil
    }
}
