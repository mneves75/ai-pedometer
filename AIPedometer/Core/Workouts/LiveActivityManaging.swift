import Foundation

@MainActor
protocol LiveActivityManaging: Sendable {
    func start(type: WorkoutType)
    func update(steps: Int, distance: Double, calories: Double) async

    /// Ends the workout's activity. A finished workout (`discarded == false`) leaves its final metrics on the
    /// Lock Screen for the system's default window; a discarded one is dismissed immediately.
    func end(discarded: Bool) async

    /// Ends any activity left running by a previous process.
    ///
    /// A Live Activity outlives the app, but the handle to it does not, so one started before a crash or
    /// force-quit can only be reached by enumeration on the next launch. Defaulted to a no-op so test
    /// doubles and the widget-less path need no changes.
    func endOrphanedActivities() async
}

extension LiveActivityManaging {
    func endOrphanedActivities() async {}
}

struct NoopLiveActivityManager: LiveActivityManaging {
    func start(type: WorkoutType) {}
    func update(steps: Int, distance: Double, calories: Double) async {}
    func end(discarded: Bool) async {}
}
