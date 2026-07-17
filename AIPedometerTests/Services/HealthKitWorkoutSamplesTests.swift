import Foundation
import HealthKit
import Testing

@testable import AIPedometer

struct HealthKitWorkoutSamplesTests {
    @Test("Quantity query specifications keep cumulative sums and strict start boundaries")
    func quantityQuerySpecificationsAreStable() {
        let steps = HealthKitService.statisticsQuerySpec(for: .stepCount)
        let distance = HealthKitService.statisticsQuerySpec(for: .distanceWalkingRunning)
        let floors = HealthKitService.statisticsQuerySpec(for: .flightsClimbed)

        #expect(steps.options == .cumulativeSum)
        #expect(steps.predicateOptions == .strictStartDate)
        #expect(steps.unit == .count())
        #expect(distance.unit == .meter())
        #expect(floors.unit == .count())
    }

    @Test("Injected statistics adapter converts nil to zero and executes once")
    @MainActor
    func injectedStatisticsAdapterHandlesNilExactlyOnce() async throws {
        var calls = 0
        let service = HealthKitService(statisticsSumExecutor: { spec, _, _ in
            calls += 1
            #expect(spec.type == .stepCount)
            #expect(spec.options == .cumulativeSum)
            return nil
        })

        let value = try await service.fetchSteps(from: .now.addingTimeInterval(-60), to: .now)

        #expect(value == 0)
        #expect(calls == 1)
    }

    @Test("Injected statistics adapter propagates cancellation")
    @MainActor
    func injectedStatisticsAdapterPropagatesCancellation() async {
        let service = HealthKitService(statisticsSumExecutor: { _, _, _ in
            throw CancellationError()
        })

        await #expect(throws: CancellationError.self) {
            _ = try await service.fetchDistance(from: .now.addingTimeInterval(-60), to: .now)
        }
    }

    @Test("Injected daily adapter preserves calendar-day conversion")
    @MainActor
    func injectedDailyAdapterBuildsSummaries() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        var calls: [HKQuantityTypeIdentifier] = []
        let service = HealthKitService(calendar: calendar, dailyTotalsExecutor: { spec, _, _ in
            calls.append(spec.type)
            switch spec.type {
            case .stepCount: return [day: 4_000]
            case .distanceWalkingRunning: return [day: 2_500]
            case .flightsClimbed: return [day: 3]
            default: return [:]
            }
        })

        let summaries = try await service.fetchDailySummaries(
            from: day,
            to: day.addingTimeInterval(60),
            activityMode: .steps,
            distanceMode: .automatic,
            manualStepLength: 0.75,
            dailyGoal: 8_000
        )

        #expect(calls.count == 3)
        #expect(summaries.count == 1)
        #expect(summaries[0].date == day)
        #expect(summaries[0].steps == 4_000)
        #expect(summaries[0].distance == 2_500)
        #expect(summaries[0].floors == 3)
        #expect(summaries[0].calories == 160)
        #expect(summaries[0].goal == 8_000)
    }

    @Test("Concurrent exports with the same stable identifier create one HealthKit workout")
    @MainActor
    func concurrentExportsAreSingleFlight() async throws {
        let exportIdentifier = UUID()
        let createdWorkoutID = UUID()
        var lookupCalls = 0
        var creationCalls = 0
        let service = HealthKitService(
            workoutLookupExecutor: { externalIdentifier in
                lookupCalls += 1
                #expect(externalIdentifier == exportIdentifier.uuidString)
                for _ in 0..<10 { await Task.yield() }
                return nil
            },
            workoutCreationExecutor: { _, externalIdentifier in
                creationCalls += 1
                #expect(externalIdentifier == exportIdentifier.uuidString)
                for _ in 0..<10 { await Task.yield() }
                return createdWorkoutID
            }
        )
        let first = WorkoutSession(
            type: .outdoorWalk,
            startTime: .now.addingTimeInterval(-600),
            endTime: .now,
            healthKitExportIdentifier: exportIdentifier
        )
        let second = WorkoutSession(
            type: .outdoorWalk,
            startTime: first.startTime,
            endTime: first.endTime,
            healthKitExportIdentifier: exportIdentifier
        )

        let firstExport = Task { @MainActor in try await service.saveWorkout(first) }
        let secondExport = Task { @MainActor in try await service.saveWorkout(second) }
        let firstOutcome = try await firstExport.value
        let secondOutcome = try await secondExport.value

        #expect(lookupCalls == 1)
        #expect(creationCalls == 1)
        #expect(first.healthKitWorkoutID == createdWorkoutID)
        #expect(second.healthKitWorkoutID == createdWorkoutID)
        #expect(firstOutcome == .exported(createdWorkoutID))
        #expect(secondOutcome == .exported(createdWorkoutID))
    }

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
