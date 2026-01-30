import Foundation
import Testing

@testable import AIPedometer

@Suite("DailyStepSummary Extensions")
struct DailyStepSummaryExtensionsTests {
    @Test
    func maxStepsValueDefaultsToOneWhenEmpty() {
        let summaries: [DailyStepSummary] = []
        #expect(summaries.maxStepsValue == 1)
    }

    @Test
    func maxStepsValueUsesHighestValue() {
        let summaries = [
            DailyStepSummary(date: Date(), steps: 1200, distance: 0, floors: 0, calories: 0, goal: 1000),
            DailyStepSummary(date: Date().addingTimeInterval(-86400), steps: 5400, distance: 0, floors: 0, calories: 0, goal: 1000)
        ]
        #expect(summaries.maxStepsValue == 5400)
    }

    @Test
    func sortedByDateDescendingOrdersNewestFirst() {
        let newest = Date()
        let oldest = newest.addingTimeInterval(-86400)
        let summaries = [
            DailyStepSummary(date: oldest, steps: 1200, distance: 0, floors: 0, calories: 0, goal: 1000),
            DailyStepSummary(date: newest, steps: 5400, distance: 0, floors: 0, calories: 0, goal: 1000)
        ]

        let sorted = summaries.sortedByDateDescending
        #expect(sorted.first?.date == newest)
        #expect(sorted.last?.date == oldest)
    }
}
