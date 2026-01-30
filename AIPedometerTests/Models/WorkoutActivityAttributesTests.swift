import Foundation
import Testing

@testable import AIPedometer

struct WorkoutActivityAttributesTests {
    @Test
    func contentStateEncodesAndDecodes() throws {
        let state = WorkoutActivityAttributes.ContentState(steps: 5000, distance: 3.5, calories: 250)
        let encoder = JSONEncoder()
        let data = try encoder.encode(state)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkoutActivityAttributes.ContentState.self, from: data)
        #expect(decoded.steps == 5000)
        #expect(decoded.distance == 3.5)
        #expect(decoded.calories == 250)
    }

    @Test
    func contentStateIsHashable() {
        let state1 = WorkoutActivityAttributes.ContentState(steps: 100, distance: 1.0, calories: 50)
        let state2 = WorkoutActivityAttributes.ContentState(steps: 100, distance: 1.0, calories: 50)
        let state3 = WorkoutActivityAttributes.ContentState(steps: 200, distance: 1.0, calories: 50)
        #expect(state1 == state2)
        #expect(state1 != state3)
    }

    @Test
    func attributesHasWorkoutType() {
        let attributes = WorkoutActivityAttributes(workoutType: "running")
        #expect(attributes.workoutType == "running")
    }
}
