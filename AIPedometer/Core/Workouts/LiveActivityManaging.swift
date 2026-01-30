import Foundation

@MainActor
protocol LiveActivityManaging: Sendable {
    func start(type: WorkoutType)
    func update(steps: Int, distance: Double, calories: Double) async
    func end() async
}

struct NoopLiveActivityManager: LiveActivityManaging {
    func start(type: WorkoutType) {}
    func update(steps: Int, distance: Double, calories: Double) async {}
    func end() async {}
}
