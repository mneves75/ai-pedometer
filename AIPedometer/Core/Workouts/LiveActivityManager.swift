#if os(iOS)
import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var currentActivityID: String?

    func start(type: WorkoutType) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(workoutType: type.rawValue)
        let state = WorkoutActivityAttributes.ContentState(steps: 0, distance: 0, calories: 0)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            currentActivityID = activity.id
        } catch {
            Loggers.workouts.error("workout.live_activity_start_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }

    func update(steps: Int, distance: Double, calories: Double) async {
        guard let activityID = currentActivityID else { return }
        let state = WorkoutActivityAttributes.ContentState(steps: steps, distance: distance, calories: calories)
        await Self.updateActivity(id: activityID, state: state)
    }

    func end() async {
        guard let activityID = currentActivityID else { return }
        let state = WorkoutActivityAttributes.ContentState(steps: 0, distance: 0, calories: 0)
        await Self.endActivity(id: activityID, state: state)
        currentActivityID = nil
    }

    nonisolated static func updateActivity(id: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(.init(state: state, staleDate: nil))
    }

    nonisolated static func endActivity(id: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
    }
}

extension LiveActivityManager: LiveActivityManaging {}
#endif
