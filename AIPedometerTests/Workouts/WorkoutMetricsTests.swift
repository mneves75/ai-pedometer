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
