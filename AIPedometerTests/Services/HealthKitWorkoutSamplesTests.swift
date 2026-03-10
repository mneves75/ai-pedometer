import Foundation
import HealthKit
import Testing

@testable import AIPedometer

struct HealthKitWorkoutSamplesTests {
    @Test
    func makeWorkoutSamplesIncludesStepsDistanceAndCalories() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(1_800)
        let session = WorkoutSession(
            type: .outdoorWalk,
            startTime: start,
            endTime: end,
            steps: 4_200,
            distance: 3_100,
            activeCalories: 180
        )

        let samples = HealthKitService.makeWorkoutSamples(for: session, start: start, end: end)

        #expect(samples.count == 3)
        #expect(samples.contains { ($0.sampleType as? HKQuantityType)?.identifier == HKQuantityTypeIdentifier.stepCount.rawValue })
        #expect(samples.contains { ($0.sampleType as? HKQuantityType)?.identifier == HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue })
        #expect(samples.contains { ($0.sampleType as? HKQuantityType)?.identifier == HKQuantityTypeIdentifier.activeEnergyBurned.rawValue })
    }

    @Test
    func makeWorkoutSamplesSkipsZeroValues() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(600)
        let session = WorkoutSession(type: .outdoorWalk, startTime: start, endTime: end)

        let samples = HealthKitService.makeWorkoutSamples(for: session, start: start, end: end)

        #expect(samples.isEmpty)
    }
}
