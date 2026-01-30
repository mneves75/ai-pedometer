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

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    var currentGoal: Int {
        let context = persistence.container.mainContext
        let descriptor = FetchDescriptor<StepGoal>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let goals: [StepGoal]
        do {
            goals = try context.fetch(descriptor)
        } catch {
            Loggers.tracking.error("goal.fetch_failed", metadata: [
                "scope": "current",
                "error": error.localizedDescription
            ])
            goals = []
        }
        if let goal = goals.first {
            return goal.dailySteps
        }
        return AppConstants.defaultDailyGoal
    }

    func goal(for date: Date) -> Int? {
        let context = persistence.container.mainContext
        let descriptor = FetchDescriptor<StepGoal>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let goals: [StepGoal]
        do {
            goals = try context.fetch(descriptor)
        } catch {
            Loggers.tracking.error("goal.fetch_failed", metadata: [
                "scope": "date",
                "error": error.localizedDescription
            ])
            goals = []
        }
        return goals.first(where: { goal in
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
        let goal = StepGoal(dailySteps: value, startDate: .now)
        context.insert(goal)
        do {
            try context.save()
        } catch {
            Loggers.tracking.error("goal.save_failed", metadata: ["error": error.localizedDescription])
        }
    }
}
