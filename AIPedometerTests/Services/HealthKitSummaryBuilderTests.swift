import Foundation
import Testing

@testable import AIPedometer

@Suite("HealthKitSummaryBuilder Tests")
struct HealthKitSummaryBuilderTests {
    @Test("Falls back to manual distance when automatic distance fetch fails")
    func fallsBackToManualDistanceWhenDistanceFails() async throws {
        let builder = HealthKitSummaryBuilder(
            activityMode: .steps,
            distanceMode: .automatic,
            manualStepLength: 0.8,
            dailyGoal: 10_000
        )

        let summary = try await builder.build(
            date: Date(timeIntervalSince1970: 0),
            fetchSteps: { 1_000 },
            fetchWheelchairPushes: { 900 },
            fetchDistance: { throw HealthKitError.queryFailed },
            fetchFloors: { 3 }
        )

        #expect(summary.steps == 1_000)
        #expect(abs(summary.distance - 800) < 0.001)
        #expect(summary.floors == 3)
    }

    @Test("Returns zero floors when floors fetch fails")
    func returnsZeroFloorsWhenFloorsFail() async throws {
        let builder = HealthKitSummaryBuilder(
            activityMode: .steps,
            distanceMode: .manual,
            manualStepLength: 0.75,
            dailyGoal: 8_000
        )

        let summary = try await builder.build(
            date: Date(timeIntervalSince1970: 0),
            fetchSteps: { 2_000 },
            fetchWheelchairPushes: { 1_800 },
            fetchDistance: { 0 },
            fetchFloors: { throw HealthKitError.queryFailed }
        )

        #expect(summary.steps == 2_000)
        #expect(abs(summary.distance - 1_500) < 0.001)
        #expect(summary.floors == 0)
    }

    @Test("Wheelchair mode uses push counts")
    func wheelchairModeUsesPushCounts() async throws {
        let builder = HealthKitSummaryBuilder(
            activityMode: .wheelchairPushes,
            distanceMode: .manual,
            manualStepLength: 0.7,
            dailyGoal: 5_000
        )

        let summary = try await builder.build(
            date: Date(timeIntervalSince1970: 0),
            fetchSteps: { 3_000 },
            fetchWheelchairPushes: { 2_500 },
            fetchDistance: { 0 },
            fetchFloors: { 1 }
        )

        #expect(summary.steps == 2_500)
        #expect(abs(summary.distance - 1_750) < 0.001)
    }

    @Test("Throws when activity fetch fails")
    func throwsWhenActivityFetchFails() async {
        let builder = HealthKitSummaryBuilder(
            activityMode: .steps,
            distanceMode: .automatic,
            manualStepLength: 0.8,
            dailyGoal: 10_000
        )

        await #expect(throws: HealthKitError.self) {
            _ = try await builder.build(
                date: Date(timeIntervalSince1970: 0),
                fetchSteps: { throw HealthKitError.queryFailed },
                fetchWheelchairPushes: { 900 },
                fetchDistance: { 0 },
                fetchFloors: { 0 }
            )
        }
    }
}
