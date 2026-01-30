import Foundation
import SwiftData
import Testing

@testable import AIPedometer

@MainActor
struct GoalServiceTests {
    @Test("Current goal returns most recent active goal")
    func currentGoalReturnsMostRecentActiveGoal() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let older = StepGoal(dailySteps: 8000, startDate: Date(timeIntervalSince1970: 1_600_000_000))
        let newer = StepGoal(dailySteps: 12000, startDate: Date(timeIntervalSince1970: 1_700_000_000))
        context.insert(older)
        context.insert(newer)
        try context.save()

        let service = GoalService(persistence: persistence)

        #expect(service.currentGoal == 12000)
    }

    @Test("setGoal closes previous active goal")
    func setGoalClosesPreviousActiveGoal() throws {
        let persistence = PersistenceController(inMemory: true)
        let service = GoalService(persistence: persistence)

        service.setGoal(9000)
        service.setGoal(11000)

        let context = persistence.container.mainContext
        let descriptor = FetchDescriptor<StepGoal>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let goals = try context.fetch(descriptor)
        let activeGoals = goals.filter { $0.endDate == nil }

        #expect(goals.count == 2)
        #expect(activeGoals.count == 1)
        #expect(activeGoals.first?.dailySteps == 11000)
    }

    @Test("goal(for:) returns goal that matches date range")
    func goalForDateReturnsMatchingGoal() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let windowStart = Date(timeIntervalSince1970: 1_700_000_000)
        let windowEnd = Date(timeIntervalSince1970: 1_700_086_400)
        let inRangeGoal = StepGoal(dailySteps: 10000, startDate: windowStart, endDate: windowEnd)
        let outOfRangeGoal = StepGoal(dailySteps: 5000, startDate: Date(timeIntervalSince1970: 1_600_000_000))
        context.insert(inRangeGoal)
        context.insert(outOfRangeGoal)
        try context.save()

        let service = GoalService(persistence: persistence)
        let midpoint = windowStart.addingTimeInterval(3600)

        #expect(service.goal(for: midpoint) == 10000)
    }
}
