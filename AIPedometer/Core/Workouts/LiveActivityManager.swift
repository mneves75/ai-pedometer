#if os(iOS)
import ActivityKit
import Foundation

/// How one existing workout activity should be ended. Pure data so the policy is unit-testable without ActivityKit.
struct LiveActivityEndRequest: Equatable, Sendable {
    let activityID: String
    /// The final content to leave on screen, or nil to keep whatever the activity last showed.
    let finalState: WorkoutActivityAttributes.ContentState?
    let dismissImmediately: Bool
}

/// The parts of an `Activity` the end policy needs, captured on the main actor.
struct LiveActivitySnapshot: Equatable, Sendable {
    let id: String
    let isEnded: Bool
}

@MainActor
final class LiveActivityManager {
    private var currentActivityID: String?
    private var latestState: WorkoutActivityAttributes.ContentState?

    /// How long a published state stays fresh. The system renders the activity as stale past this point,
    /// so one orphaned by a crash or force-quit stops presenting frozen metrics as live.
    private static let staleInterval: TimeInterval = 5 * 60

    func start(type: WorkoutType) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Captured before the request, so the sweep below can never include the activity requested here.
        // A previous process may have left one running; its id died with that process, so it can only be
        // found by enumeration. Clear it or the Lock Screen stacks two.
        let orphans = Self.endRequests(
            for: Self.snapshotActivities(),
            currentActivityID: nil,
            latestState: nil,
            discarded: false
        )
        let attributes = WorkoutActivityAttributes(workoutType: type.rawValue)
        let state = WorkoutActivityAttributes.ContentState(steps: 0, distance: 0, calories: 0)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: Date.now.addingTimeInterval(Self.staleInterval)),
                pushType: nil
            )
            currentActivityID = activity.id
            latestState = state
            Task { await Self.perform(orphans) }
        } catch {
            Loggers.workouts.error("workout.live_activity_start_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }

    func update(steps: Int, distance: Double, calories: Double) async {
        guard let activityID = currentActivityID else { return }
        let state = WorkoutActivityAttributes.ContentState(steps: steps, distance: distance, calories: calories)
        latestState = state
        await Self.updateActivity(id: activityID, state: state)
    }

    func end(discarded: Bool) async {
        // Not limited to `currentActivityID`: that is in-memory only, so an activity started before a crash
        // must still be found by enumeration, or it stays pinned through Finish and Discard alike.
        let requests = Self.endRequests(
            for: Self.snapshotActivities(),
            currentActivityID: currentActivityID,
            latestState: latestState,
            discarded: discarded
        )
        currentActivityID = nil
        latestState = nil
        await Self.perform(requests)
    }

    /// Ends every workout activity left over from a previous process. Safe to call when none exist.
    ///
    /// The snapshot is taken synchronously on the main actor and excludes the current activity, so this can
    /// never end one this process started, however late the call runs.
    func endOrphanedActivities() async {
        let orphans = Self.snapshotActivities().filter { $0.id != currentActivityID }
        await Self.perform(
            Self.endRequests(for: orphans, currentActivityID: nil, latestState: nil, discarded: false)
        )
    }

    /// The end policy. The workout this process is tracking ends on its latest metrics: a finished workout
    /// keeps its final numbers on the Lock Screen for the system's default window, a discarded one leaves at
    /// once. Anything else is an orphan whose last content is frozen, so it is dismissed immediately.
    /// Activities already ended — such as an earlier workout's final card — are left alone.
    nonisolated static func endRequests(
        for activities: [LiveActivitySnapshot],
        currentActivityID: String?,
        latestState: WorkoutActivityAttributes.ContentState?,
        discarded: Bool
    ) -> [LiveActivityEndRequest] {
        activities.compactMap { activity in
            if activity.id == currentActivityID, let latestState {
                return LiveActivityEndRequest(
                    activityID: activity.id,
                    finalState: latestState,
                    dismissImmediately: discarded
                )
            }
            guard !activity.isEnded else { return nil }
            return LiveActivityEndRequest(activityID: activity.id, finalState: nil, dismissImmediately: true)
        }
    }

    private static func snapshotActivities() -> [LiveActivitySnapshot] {
        Activity<WorkoutActivityAttributes>.activities.map { activity in
            let state = activity.activityState
            return LiveActivitySnapshot(id: activity.id, isEnded: state == .ended || state == .dismissed)
        }
    }

    nonisolated static func updateActivity(id: String, state: WorkoutActivityAttributes.ContentState) async {
        guard let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(.init(state: state, staleDate: Date.now.addingTimeInterval(staleInterval)))
    }

    nonisolated static func perform(_ requests: [LiveActivityEndRequest]) async {
        guard !requests.isEmpty else { return }
        let requestsByID = Dictionary(requests.map { ($0.activityID, $0) }, uniquingKeysWith: { first, _ in first })
        for activity in Activity<WorkoutActivityAttributes>.activities {
            guard let request = requestsByID[activity.id] else { continue }
            let content = request.finalState.map { ActivityContent(state: $0, staleDate: nil) }
            await activity.end(content, dismissalPolicy: request.dismissImmediately ? .immediate : .default)
        }
    }
}

extension LiveActivityManager: LiveActivityManaging {}
#endif
