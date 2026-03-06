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

        #expect(controller.isPresenting)
        #expect(controller.isActive)
        #expect(controller.metrics?.targetSteps == 4000)
        #expect(metricsSource.startCount == 1)
        #expect(metricsSource.lastStartDate == fixedNow)
        #expect(liveActivity.startCount == 1)

        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.endTime == nil)
        await controller.discardWorkout()
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

        await controller.discardWorkout()
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

        await controller.discardWorkout()
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

        await controller.discardWorkout()
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
    func discardWhilePreparingAbortsPendingStartWithoutLiveActivityLeak() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        let liveActivity = MockLiveActivityManager()
        let healthKit = BlockingWorkoutSessionHealthKitStub()
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity
        )

        let startTask = Task {
            await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        }

        await healthKit.waitUntilAuthorizationRequested()
        await controller.discardWorkout()
        healthKit.unblockAuthorization()
        await startTask.value

        #expect(controller.state == .idle)
        #expect(!controller.isActive)
        #expect(!controller.isPresenting)
        #expect(metricsSource.startCount == 0)
        #expect(liveActivity.startCount == 0)

        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.deletedAt != nil)
    }

    @Test
    func finishWhilePreparingDoesNotLeaveControllerInPreparingState() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        let liveActivity = MockLiveActivityManager()
        let healthKit = BlockingWorkoutSessionHealthKitStub()
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity
        )

        let startTask = Task {
            await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        }

        await healthKit.waitUntilAuthorizationRequested()
        await controller.finishWorkout()
        healthKit.unblockAuthorization()
        await startTask.value

        #expect(!controller.isActive)
        #expect(!controller.isPresenting)
        #expect(metricsSource.startCount == 0)
        #expect(liveActivity.startCount == 0)
        #expect(healthKit.saveCount == 1)
        if case .completed = controller.state {
            // expected
        } else {
            Issue.record("Expected completed state after finishing while preparing")
        }
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

    @Test
    func refreshMetricsIgnoresWarmupNoData() async {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        metricsSource.snapshotErrorToThrow = MotionError.noData
        let liveActivity = MockLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        await controller.refreshMetrics()

        #expect(controller.lastError == nil)
        await controller.discardWorkout()
    }

    @Test
    func discardWorkoutWaitsForLiveActivityEnd() async {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        let liveActivity = MockLiveActivityManager()
        liveActivity.endDelayNanoseconds = 80_000_000
        let healthKit = WorkoutSessionHealthKitStub()
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        await controller.discardWorkout()

        #expect(liveActivity.endCount == 1)
        #expect(!controller.isPresenting)
        #expect(!controller.isActive)
    }

    @Test
    func finishWorkoutSeparatesHealthKitIdPersistenceFailure() async {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        metricsSource.snapshotErrorToThrow = MotionError.noData
        let liveActivity = MockLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        var saveCalls = 0
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity,
            saveModelContext: { context in
                saveCalls += 1
                if saveCalls == 3 {
                    throw CocoaError(.validationMultipleErrors)
                }
                try context.save()
            }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        await controller.finishWorkout()

        #expect(healthKit.saveCount == 1)
        #expect(controller.lastError?.id.contains("saveFailed") == true)
    }
}

@MainActor
final class MockMetricsSource: WorkoutLiveMetricsSource {
    var startCount = 0
    var stopCount = 0
    var snapshotToReturn = PedometerSnapshot(steps: 0, distance: 0, floorsAscended: 0)
    var startErrorToThrow: (any Error)?
    var snapshotErrorToThrow: (any Error)?
    private(set) var lastStartDate: Date?

    func start(from startDate: Date) throws {
        startCount += 1
        lastStartDate = startDate
        if let startErrorToThrow { throw startErrorToThrow }
    }

    func stop() {
        stopCount += 1
    }

    func snapshot() async throws -> PedometerSnapshot {
        if let snapshotErrorToThrow { throw snapshotErrorToThrow }
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
    var endDelayNanoseconds: UInt64 = 0

    func start(type: WorkoutType) {
        startCount += 1
        lastType = type
    }

    func update(steps: Int, distance: Double, calories: Double) async {
        updateCount += 1
        lastUpdate = (steps, distance, calories)
    }

    func end() async {
        if endDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: endDelayNanoseconds)
        }
        endCount += 1
    }
}

@MainActor
final class WorkoutSessionHealthKitStub: HealthKitServiceProtocol {
    var saveCount = 0
    var requestCount = 0
    var assignedWorkoutID = UUID()

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
    func fetchDailySummaries(
        from _: Date,
        to _: Date,
        activityMode _: ActivityTrackingMode,
        distanceMode _: DistanceEstimationMode,
        manualStepLength _: Double,
        dailyGoal _: Int
    ) async throws -> [DailyStepSummary] { [] }

    func saveWorkout(_ session: WorkoutSession) async throws {
        session.healthKitWorkoutID = assignedWorkoutID
        saveCount += 1
    }
}

@MainActor
final class BlockingWorkoutSessionHealthKitStub: HealthKitServiceProtocol {
    var saveCount = 0
    var requestCount = 0

    private var requestContinuation: CheckedContinuation<Void, Never>?
    private var unblockContinuation: CheckedContinuation<Void, Never>?
    private var isUnblocked = false

    func waitUntilAuthorizationRequested() async {
        if requestCount > 0 { return }
        await withCheckedContinuation { continuation in
            requestContinuation = continuation
        }
    }

    func unblockAuthorization() {
        isUnblocked = true
        unblockContinuation?.resume()
        unblockContinuation = nil
    }

    func requestAuthorization() async throws {
        requestCount += 1
        requestContinuation?.resume()
        requestContinuation = nil
        if isUnblocked { return }
        await withCheckedContinuation { continuation in
            unblockContinuation = continuation
        }
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
    func fetchDailySummaries(
        from _: Date,
        to _: Date,
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
