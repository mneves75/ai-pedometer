import Foundation

@MainActor
protocol WorkoutLiveMetricsSource: Sendable {
    func start(from startDate: Date) throws
    func stop()
    func snapshot() async throws -> PedometerSnapshot
}

@MainActor
final class MotionLiveMetricsSource: WorkoutLiveMetricsSource {
    private let motionService: any MotionServiceProtocol
    private let now: () -> Date
    private var latestSnapshot: PedometerSnapshot?
    private var startDate: Date?

    init(
        motionService: any MotionServiceProtocol,
        now: @escaping () -> Date = { .now }
    ) {
        self.motionService = motionService
        self.now = now
    }

    func start(from startDate: Date) throws {
        self.startDate = startDate
        latestSnapshot = nil
        try motionService.startLiveUpdates(from: startDate) { [weak self] snapshot in
            self?.latestSnapshot = snapshot
        }
    }

    func stop() {
        motionService.stopLiveUpdates()
    }

    func snapshot() async throws -> PedometerSnapshot {
        if let latestSnapshot {
            return latestSnapshot
        }
        throw MotionError.noData
    }
}
