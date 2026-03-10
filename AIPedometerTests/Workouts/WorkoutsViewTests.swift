import Foundation
import Testing

@testable import AIPedometer

@MainActor
struct WorkoutsViewTests {
    @Test("recentCompletedWorkouts excludes in-progress sessions and limits results")
    func recentCompletedWorkoutsExcludesInProgressAndCapsList() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        var workouts: [WorkoutSession] = []
        workouts.reserveCapacity(8)

        for index in 0..<8 {
            let startTime = baseDate.addingTimeInterval(Double(index) * 600)
            let endTime = index == 2 ? nil : startTime.addingTimeInterval(300)
            let workout = WorkoutSession(
                type: .outdoorWalk,
                startTime: startTime,
                endTime: endTime,
                steps: 1_000 + index,
                distance: Double(500 + index),
                activeCalories: Double(80 + index)
            )
            workouts.append(workout)
        }

        let visible = WorkoutsView.recentCompletedWorkouts(from: workouts)

        #expect(visible.count == 6)
        #expect(visible.allSatisfy { $0.endTime != nil })
        #expect(visible.contains { $0.steps == 1_000 })
        #expect(!visible.contains { $0.steps == 1_002 })
        #expect(!visible.contains { $0.steps == 1_007 })
    }
}
