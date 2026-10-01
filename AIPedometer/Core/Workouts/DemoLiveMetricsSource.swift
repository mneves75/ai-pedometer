import Foundation

@MainActor
struct DemoLiveMetricsSource: WorkoutLiveMetricsSource {
    func start(from startDate: Date) throws {}

    func stop() {}

    func currentSnapshot() -> PedometerSnapshot? {
        PedometerSnapshot(steps: 0, distance: 0, floorsAscended: 0)
    }

    func snapshot() async throws -> PedometerSnapshot {
        PedometerSnapshot(steps: 0, distance: 0, floorsAscended: 0)
    }
}
