import Foundation
import Testing

@testable import AIPedometer

struct WorkoutMetricsTests {
    @Test
    func targetProgressClampsAndHandlesNilTarget() {
        var metrics = WorkoutMetrics.initial(startTime: Date(timeIntervalSince1970: 0), targetSteps: nil)
        #expect(metrics.targetProgress == nil)

        metrics = WorkoutMetrics.initial(startTime: Date(timeIntervalSince1970: 0), targetSteps: 1000)
        metrics.steps = 500
        #expect(metrics.targetProgress == 0.5)

        metrics.steps = 2000
        #expect(metrics.targetProgress == 1.0)
    }
}

@MainActor
@Suite("Motion live metrics source")
struct MotionLiveMetricsSourceTests {
    // Pausing stops CoreMotion, but a callback already queued can still arrive. The controller
    // then adds that previous segment's total on top of the steps it saved at pause.
    @Test("A snapshot from a stopped segment is ignored after the workout resumes")
    func staleSegmentSnapshotIsIgnoredAfterRestart() async throws {
        let motion = MockMotionService()
        let source = MotionLiveMetricsSource(motionService: motion)

        try source.start(from: Date(timeIntervalSince1970: 0))
        let firstSegmentHandler = try #require(motion.liveUpdateHandlers.first)
        source.stop()
        try source.start(from: Date(timeIntervalSince1970: 60))
        firstSegmentHandler(PedometerSnapshot(steps: 500, distance: 400, floorsAscended: 1))

        await #expect(throws: MotionError.self) { try await source.snapshot() }

        motion.simulateLiveUpdate(PedometerSnapshot(steps: 20, distance: 15, floorsAscended: 0))
        #expect(try await source.snapshot().steps == 20)
    }
}
