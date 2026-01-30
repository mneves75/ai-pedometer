import Foundation
import SwiftData
import Testing

@testable import AIPedometer

@MainActor
struct WorkoutSessionControllerTests {
    @Test
    func startWorkoutCreatesSessionAndStartsMetrics() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        let liveActivity = MockLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        let fixedNow = Date(timeIntervalSince1970: 1000)
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity,
            now: { fixedNow }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: 4000)
        defer { controller.discardWorkout() }

        #expect(controller.isPresenting)
        #expect(controller.isActive)
        #expect(controller.metrics?.targetSteps == 4000)
        #expect(metricsSource.startCount == 1)
        #expect(metricsSource.lastStartDate == fixedNow)
        #expect(liveActivity.startCount == 1)

        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.endTime == nil)
    }

    @Test
    func pauseAndResumeStopsAndRestartsMetrics() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        let liveActivity = MockLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        var now = Date(timeIntervalSince1970: 1000)
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity,
            now: { now }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        controller.pauseWorkout()
        #expect(metricsSource.stopCount == 1)

        now = Date(timeIntervalSince1970: 2000)
        controller.resumeWorkout()
        #expect(metricsSource.startCount == 2)
        #expect(metricsSource.lastStartDate == now)

        controller.discardWorkout()
    }

    @Test
    func refreshMetricsUpdatesSessionAndLiveActivity() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        metricsSource.snapshotToReturn = PedometerSnapshot(steps: 2500, distance: 2000, floorsAscended: 0)
        let liveActivity = MockLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: 3000)
        await controller.refreshMetrics()

        #expect(controller.metrics?.steps == 2500)
        #expect(controller.metrics?.distance == 2000)
        #expect(liveActivity.lastUpdate?.distance == 2.0)

        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.first?.steps == 2500)

        controller.discardWorkout()
    }

    @Test
    func pausedStepsAreNotIncludedAfterResume() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        let liveActivity = MockLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        var now = Date(timeIntervalSince1970: 1000)
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity,
            now: { now }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        metricsSource.snapshotToReturn = PedometerSnapshot(steps: 500, distance: 400, floorsAscended: 0)
        await controller.refreshMetrics()
        #expect(controller.metrics?.steps == 500)

        controller.pauseWorkout()
        now = Date(timeIntervalSince1970: 2000)
        controller.resumeWorkout()

        metricsSource.snapshotToReturn = PedometerSnapshot(steps: 120, distance: 100, floorsAscended: 0)
        await controller.refreshMetrics()

        #expect(controller.metrics?.steps == 620)
        #expect(controller.metrics?.distance == 500)

        controller.discardWorkout()
    }

    @Test
    func finishWorkoutEndsSessionAndPersists() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        let liveActivity = MockLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        await controller.finishWorkout()

        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.first?.endTime != nil)
        #expect(healthKit.saveCount == 1)
        #expect(liveActivity.endCount == 1)
        #expect(!controller.isPresenting)
    }

    @Test
    func demoLiveMetricsSourceReturnsZeroSnapshot() async throws {
        let source = DemoLiveMetricsSource()
        try source.start(from: Date())
        let snapshot = try await source.snapshot()
        #expect(snapshot.steps == 0)
        #expect(snapshot.distance == 0)
        #expect(snapshot.floorsAscended == 0)
        source.stop()
    }
}

@MainActor
final class MockMetricsSource: WorkoutLiveMetricsSource {
    var startCount = 0
    var stopCount = 0
    var snapshotToReturn = PedometerSnapshot(steps: 0, distance: 0, floorsAscended: 0)
    var errorToThrow: (any Error)?
    private(set) var lastStartDate: Date?

    func start(from startDate: Date) throws {
        startCount += 1
        lastStartDate = startDate
        if let errorToThrow { throw errorToThrow }
    }

    func stop() {
        stopCount += 1
    }

    func snapshot() async throws -> PedometerSnapshot {
        if let errorToThrow { throw errorToThrow }
        return snapshotToReturn
    }
}

@MainActor
final class MockLiveActivityManager: LiveActivityManaging {
    var startCount = 0
    var updateCount = 0
    var endCount = 0
    var lastType: WorkoutType?
    var lastUpdate: (steps: Int, distance: Double, calories: Double)?

    func start(type: WorkoutType) {
        startCount += 1
        lastType = type
    }

    func update(steps: Int, distance: Double, calories: Double) async {
        updateCount += 1
        lastUpdate = (steps, distance, calories)
    }

    func end() async {
        endCount += 1
    }
}

@MainActor
final class WorkoutSessionHealthKitStub: HealthKitServiceProtocol {
    var saveCount = 0
    var requestCount = 0

    func requestAuthorization() async throws {
        requestCount += 1
    }

    func fetchTodaySteps() async throws -> Int { 0 }
    func fetchSteps(from _: Date, to _: Date) async throws -> Int { 0 }
    func fetchWheelchairPushes(from _: Date, to _: Date) async throws -> Int { 0 }
    func fetchDistance(from _: Date, to _: Date) async throws -> Double { 0 }
    func fetchFloors(from _: Date, to _: Date) async throws -> Int { 0 }
    func fetchDailySummaries(
        days _: Int,
        activityMode _: ActivityTrackingMode,
        distanceMode _: DistanceEstimationMode,
        manualStepLength _: Double,
        dailyGoal _: Int
    ) async throws -> [DailyStepSummary] { [] }

    func saveWorkout(_ session: WorkoutSession) async throws {
        _ = session
        saveCount += 1
    }
}
