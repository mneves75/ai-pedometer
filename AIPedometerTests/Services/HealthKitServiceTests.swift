import Foundation
import os
import Testing

@testable import AIPedometer

// MARK: - DailyStepSummary Tests

@Suite("DailyStepSummary Tests")
struct DailyStepSummaryTests {

    @Test("Goal met when steps exceed goal")
    func goalMetWhenStepsExceedGoal() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 12000,
            distance: 8500,
            floors: 5,
            calories: 400,
            goal: 10000
        )

        #expect(summary.goalMet == true)
        #expect(summary.progress == 1.2)
    }

    @Test("Goal not met when steps below goal")
    func goalNotMetWhenStepsBelowGoal() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 10000
        )

        #expect(summary.goalMet == false)
        #expect(summary.progress == 0.5)
    }

    @Test("Progress handles zero goal safely")
    func progressHandlesZeroGoalSafely() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 0
        )

        #expect(summary.progress == 0)
    }

    @Test("Summary is Identifiable using date")
    func summaryIsIdentifiable() {
        let date = Date.now
        let summary = DailyStepSummary(
            date: date,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 10000
        )

        #expect(summary.id == date)
    }

    @Test("DateString returns abbreviated date format")
    func dateStringReturnsAbbreviatedFormat() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 10000
        )

        // dateString should not be empty and should contain the year or month
        #expect(!summary.dateString.isEmpty)
    }

    @Test("DayName returns weekday abbreviation")
    func dayNameReturnsWeekdayAbbreviation() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 10000
        )

        // dayName should be a short weekday like "Mon", "Tue", etc.
        #expect(summary.dayName.count >= 2)
        #expect(summary.dayName.count <= 4)
    }
}

// MARK: - HealthKitQueryBridge Tests

@Suite("HealthKitQueryBridge")
struct HealthKitQueryBridgeTests {
    @Test("A completed query returns its value without being stopped")
    func completedQueryReturnsValue() async throws {
        let bridge = HealthKitQueryBridge<Int>()
        let stops = OSAllocatedUnfairLock(initialState: 0)

        let value = try await bridge.run(
            execute: { bridge.resume(with: .success(42)) },
            stop: { stops.withLock { $0 += 1 } }
        )

        #expect(value == 42)
        #expect(stops.withLock { $0 } == 0)
    }

    @Test("Cancelling the awaiting task stops the query and resumes exactly once")
    func cancellationStopsQueryAndResumesOnce() async {
        let bridge = HealthKitQueryBridge<Int>()
        let stops = OSAllocatedUnfairLock(initialState: 0)
        let (executed, executedContinuation) = AsyncStream<Void>.makeStream()

        let task = Task {
            try await bridge.run(
                execute: {
                    executedContinuation.yield()
                    executedContinuation.finish()
                },
                stop: { stops.withLock { $0 += 1 } }
            )
        }
        for await _ in executed {}

        task.cancel()
        // HealthKit can still deliver its results after `stop(_:)`; that late callback must be a no-op.
        bridge.resume(with: .success(7))

        switch await task.result {
        case .success(let value):
            Issue.record("Expected CancellationError, got value \(value)")
        case .failure(let error):
            #expect(error is CancellationError)
        }
        #expect(stops.withLock { $0 } >= 1)
    }

    @Test("Cancellation that lands as the query starts still stops the started query")
    func cancellationDuringStartStopsStartedQuery() async {
        let bridge = HealthKitQueryBridge<Int>()
        let started = OSAllocatedUnfairLock(initialState: false)
        let stopsAfterStart = OSAllocatedUnfairLock(initialState: 0)

        let task = Task {
            try await bridge.run(
                execute: {
                    // The cancellation handler runs here, before the query below has started.
                    withUnsafeCurrentTask { $0?.cancel() }
                    started.withLock { $0 = true }
                },
                stop: {
                    if started.withLock({ $0 }) {
                        stopsAfterStart.withLock { $0 += 1 }
                    }
                }
            )
        }

        switch await task.result {
        case .success(let value):
            Issue.record("Expected CancellationError, got value \(value)")
        case .failure(let error):
            #expect(error is CancellationError)
        }
        #expect(stopsAfterStart.withLock { $0 } >= 1)
    }
}
