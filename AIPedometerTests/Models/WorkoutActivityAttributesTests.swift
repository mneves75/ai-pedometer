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

    @Test("The tracked workout ends on its latest metrics, not a zeroed state")
    func currentActivityEndsWithLatestState() {
        let latest = WorkoutActivityAttributes.ContentState(steps: 4_210, distance: 3.1, calories: 168)
        let activities = [LiveActivitySnapshot(id: "current", isEnded: false)]

        let finished = LiveActivityManager.endRequests(
            for: activities, currentActivityID: "current", latestState: latest, discarded: false
        )
        let discarded = LiveActivityManager.endRequests(
            for: activities, currentActivityID: "current", latestState: latest, discarded: true
        )

        #expect(finished == [LiveActivityEndRequest(activityID: "current", finalState: latest, dismissImmediately: false)])
        #expect(discarded == [LiveActivityEndRequest(activityID: "current", finalState: latest, dismissImmediately: true)])
    }

    @Test("Activities from a previous process are dismissed at once and ended ones are left alone")
    func orphansAreDismissedImmediately() {
        let latest = WorkoutActivityAttributes.ContentState(steps: 10, distance: 0.01, calories: 0.4)
        let activities = [
            LiveActivitySnapshot(id: "orphan", isEnded: false),
            LiveActivitySnapshot(id: "earlier-final-card", isEnded: true),
            LiveActivitySnapshot(id: "current", isEnded: false)
        ]

        let requests = LiveActivityManager.endRequests(
            for: activities, currentActivityID: "current", latestState: latest, discarded: false
        )

        #expect(requests == [
            LiveActivityEndRequest(activityID: "orphan", finalState: nil, dismissImmediately: true),
            LiveActivityEndRequest(activityID: "current", finalState: latest, dismissImmediately: false)
        ])
    }
}
