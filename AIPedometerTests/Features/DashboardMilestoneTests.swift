import Foundation
import Testing

@testable import AIPedometer

@MainActor
@Suite("Dashboard milestone bucketing")
struct DashboardMilestoneTests {
    @Test(
        "Quarter-goal buckets cross at 25/50/75/100 percent",
        arguments: zip(
            [0.0, 0.1, 0.24, 0.25, 0.49, 0.5, 0.74, 0.75, 0.99, 1.0, 1.5],
            [0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4]
        )
    )
    func milestoneBucketCrossesAtQuarters(progress: Double, expected: Int) {
        #expect(DashboardView.milestoneBucket(progress: progress) == expected)
    }

    @Test("Zero and negative progress never report a milestone")
    func milestoneBucketGuardsNonPositiveProgress() {
        #expect(DashboardView.milestoneBucket(progress: 0) == 0)
        #expect(DashboardView.milestoneBucket(progress: -0.5) == 0)
    }

    @Test("Bucket is monotonic across the goal range so haptics never fire twice for one quarter")
    func milestoneBucketIsMonotonic() {
        var previous = DashboardView.milestoneBucket(progress: 0)
        for step in stride(from: 0.0, through: 1.0, by: 0.01) {
            let bucket = DashboardView.milestoneBucket(progress: step)
            #expect(bucket >= previous)
            previous = bucket
        }
    }
}
