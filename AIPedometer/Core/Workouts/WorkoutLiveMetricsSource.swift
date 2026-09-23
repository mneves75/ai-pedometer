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
    /// Bumped on every start and stop. CoreMotion can still deliver a callback queued before
    /// `stop()`; without this, a paused segment's total would be counted again after resuming.
    private var segment = 0

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
        segment += 1
        let startedSegment = segment
        try motionService.startLiveUpdates(from: startDate) { [weak self] snapshot in
            guard let self, self.segment == startedSegment else { return }
            self.latestSnapshot = snapshot
        }
    }

    func stop() {
        segment += 1
        motionService.stopLiveUpdates()
    }

    func snapshot() async throws -> PedometerSnapshot {
        if let latestSnapshot {
            return latestSnapshot
        }
        throw MotionError.noData
    }
}
