import Foundation
import Testing

@testable import AIPedometer

// MARK: - HealthKitService Protocol Tests

@Suite("HealthKitService Protocol Tests")
struct HealthKitServiceProtocolTests {

    @Test("Mock service returns configured steps")
    @MainActor
    func mockServiceReturnsConfiguredSteps() async throws {
        let mock = MockHealthKitService()
        mock.stepsToReturn = 5432

        let steps = try await mock.fetchTodaySteps()

        #expect(steps == 5432)
    }

    @Test("Mock service throws configured error")
    @MainActor
    func mockServiceThrowsConfiguredError() async {
        let mock = MockHealthKitService()
        mock.errorToThrow = HealthKitError.queryFailed

        await #expect(throws: HealthKitError.self) {
            _ = try await mock.fetchTodaySteps()
        }
    }

    @Test("Authorization request is tracked")
    @MainActor
    func authorizationRequestIsTracked() async throws {
        let mock = MockHealthKitService()

        try await mock.requestAuthorization()

        #expect(mock.authorizationRequested == true)
    }
}

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

// MARK: - PedometerSnapshot Tests

@Suite("PedometerSnapshot Tests")
struct PedometerSnapshotTests {

    @Test("Snapshot is Sendable")
    func snapshotIsSendable() async {
        let snapshot = PedometerSnapshot(steps: 100, distance: 75.5, floorsAscended: 1)

        // Verify sendable by passing across isolation boundaries
        let result = await Task.detached {
            return snapshot.steps
        }.value

        #expect(result == 100)
    }

    @Test("Snapshot stores all values correctly")
    func snapshotStoresAllValuesCorrectly() {
        let snapshot = PedometerSnapshot(steps: 9876, distance: 7234.5, floorsAscended: 12)

        #expect(snapshot.steps == 9876)
        #expect(snapshot.distance == 7234.5)
        #expect(snapshot.floorsAscended == 12)
    }
}
