#if os(iOS)
import ActivityKit
import Foundation

@MainActor
final class LiveActivityManager {
    private var currentActivityID: String?

    /// How long a published state stays fresh. The system renders the activity as stale past this point,
    /// so one orphaned by a crash or force-quit stops presenting frozen metrics as live.
    private static let staleInterval: TimeInterval = 5 * 60

    func start(type: WorkoutType) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(workoutType: type.rawValue)
        let state = WorkoutActivityAttributes.ContentState(steps: 0, distance: 0, calories: 0)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date.now.addingTimeInterval(Self.staleInterval)),
                pushType: nil
            )
            currentActivityID = activity.id
            // A previous process may have left an activity running; its id died with that process, so it
            // can only be found by enumeration. Clear it here or the Lock Screen stacks two.
            Task { await Self.endActivities(excluding: activity.id) }
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
        currentActivityID = nil
        // Deliberately not keyed on `currentActivityID`: it is in-memory only, so after a relaunch the
        // guard that used to be here made `end()` an unconditional no-op and the activity a user started
        // before a crash stayed pinned to the Lock Screen through Finish and Discard alike.
        await Self.endAllActivities()
    }

    /// Ends every workout activity left over from a previous process. Safe to call when none exist.
    func endOrphanedActivities() async {
        await Self.endAllActivities()
    }

    nonisolated static func updateActivity(id: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(.init(state: state, staleDate: Date.now.addingTimeInterval(staleInterval)))
    }

    nonisolated static func endActivity(id: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
    }

    nonisolated static func endAllActivities() async {
        await endActivities(excluding: nil)
    }

    nonisolated static func endActivities(excluding keptActivityID: String?) async {
        let state = WorkoutActivityAttributes.ContentState(steps: 0, distance: 0, calories: 0)
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.id != keptActivityID {
            await activity.end(.init(state: state, staleDate: nil), dismissalPolicy: .default)
        }
    }
}

extension LiveActivityManager: LiveActivityManaging {}
#endif
