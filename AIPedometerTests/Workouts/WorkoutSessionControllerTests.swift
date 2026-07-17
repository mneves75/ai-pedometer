import Foundation
import SwiftData
import Testing

@testable import AIPedometer

@MainActor
struct WorkoutSessionControllerTests {
    @Test("HealthKit failure leaves a completed workout pending for durable retry")
    func failedHealthKitExportLeavesPendingWorkout() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let healthKit = WorkoutSessionHealthKitStub()
        healthKit.saveError = HealthKitError.queryFailed
        let controller = WorkoutSessionController(
            modelContext: context,
            healthKitService: healthKit,
            metricsSource: MockMetricsSource()
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        await controller.finishWorkout()

        let workouts = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(workouts.count == 1)
        #expect(workouts[0].endTime != nil)
        #expect(workouts[0].healthKitExportState == .pending)
        #expect(workouts[0].healthKitExportFailureCount == 1)
        #expect(workouts[0].healthKitWorkoutID == nil)
    }

    @Test("HealthKit save without an identifier leaves the workout pending")
    func healthKitSaveWithoutIdentifierLeavesPendingWorkout() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let healthKit = WorkoutSessionHealthKitStub()
        healthKit.assignedWorkoutID = nil
        let controller = WorkoutSessionController(
            modelContext: context,
            healthKitService: healthKit,
            metricsSource: MockMetricsSource()
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        await controller.finishWorkout()

        let workouts = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(workouts.count == 1)
        #expect(workouts[0].endTime != nil)
        #expect(workouts[0].healthKitExportState == .pending)
        #expect(workouts[0].healthKitWorkoutID == nil)
    }

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

    @Test("Fresh controller blocks a duplicate when an unfinished workout exists")
    func freshControllerBlocksDuplicateUnfinishedWorkout() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let unfinished = WorkoutSession(
            type: .outdoorWalk,
            startTime: Date(timeIntervalSince1970: 1_000),
            steps: 321,
            distance: 250,
            updatedAt: Date(timeIntervalSince1970: 1_100)
        )
        context.insert(unfinished)
        try context.save()

        let controller = WorkoutSessionController(
            modelContext: context,
            healthKitService: WorkoutSessionHealthKitStub(),
            metricsSource: MockMetricsSource(),
            liveActivityManager: MockLiveActivityManager()
        )

        #expect(controller.requiresWorkoutRecovery)
        #expect(controller.recoverableSession === unfinished)

        await controller.startWorkout(type: .hike, targetSteps: nil)

        let unfinishedWorkouts = try context.fetch(FetchDescriptor<WorkoutSession>()).filter {
            $0.endTime == nil && $0.deletedAt == nil
        }
        #expect(unfinishedWorkouts.count == 1)
    }

    @Test("Recovered workout can be explicitly finished from its last durable checkpoint")
    func recoveredWorkoutCanBeFinished() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let checkpoint = Date(timeIntervalSince1970: 1_100)
        let unfinished = WorkoutSession(
            type: .outdoorWalk,
            startTime: Date(timeIntervalSince1970: 1_000),
            steps: 321,
            distance: 250,
            updatedAt: checkpoint
        )
        context.insert(unfinished)
        try context.save()
        let healthKit = WorkoutSessionHealthKitStub()
        let liveActivity = MockLiveActivityManager()
        let controller = WorkoutSessionController(
            modelContext: context,
            healthKitService: healthKit,
            metricsSource: MockMetricsSource(),
            liveActivityManager: liveActivity
        )

        await controller.finishRecoverableWorkout()

        #expect(unfinished.endTime == checkpoint)
        #expect(unfinished.healthKitWorkoutID == healthKit.assignedWorkoutID)
        #expect(unfinished.healthKitExportState == .exported)
        #expect(!controller.requiresWorkoutRecovery)
        #expect(liveActivity.endCount == 1)
    }

    @Test("Recovered workout is discarded only through the explicit recovery action")
    func recoveredWorkoutCanBeDiscarded() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        let unfinished = WorkoutSession(
            type: .hike,
            startTime: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_100)
        )
        context.insert(unfinished)
        try context.save()
        let liveActivity = MockLiveActivityManager()
        let controller = WorkoutSessionController(
            modelContext: context,
            healthKitService: WorkoutSessionHealthKitStub(),
            metricsSource: MockMetricsSource(),
            liveActivityManager: liveActivity,
            now: { Date(timeIntervalSince1970: 1_200) }
        )

        await controller.discardRecoverableWorkout()

        #expect(unfinished.deletedAt == Date(timeIntervalSince1970: 1_200))
        #expect(!controller.requiresWorkoutRecovery)
        #expect(liveActivity.endCount == 1)
    }

    @Test
    func failedStartDoesNotPersistPhantomSessionOnRetry() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        metricsSource.snapshotErrorToThrow = MotionError.noData
        var saveCalls = 0
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: WorkoutSessionHealthKitStub(),
            metricsSource: metricsSource,
            liveActivityManager: MockLiveActivityManager(),
            saveModelContext: { context in
                saveCalls += 1
                if saveCalls == 1 {
                    throw CocoaError(.fileWriteUnknown)
                }
                try context.save()
            }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        await controller.startWorkout(type: .hike, targetSteps: nil)

        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.type == WorkoutType.hike)
        #expect(controller.isActive)

        await controller.discardWorkout()
    }

    @Test("Workout startup error remains observable after failed session cleanup")
    func workoutStartupErrorRemainsObservableAfterCleanup() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        let startupError = CocoaError(.fileReadUnknown)
        metricsSource.startErrorToThrow = startupError
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: WorkoutSessionHealthKitStub(),
            metricsSource: metricsSource,
            liveActivityManager: MockLiveActivityManager()
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)

        #expect(controller.lastError == .unableToStart(startupError.localizedDescription))
        #expect(!controller.isPresenting)
        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions[0].deletedAt != nil)
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
    func failedResumeRemainsPausedAndCanRetry() async {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        metricsSource.snapshotErrorToThrow = MotionError.noData
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: WorkoutSessionHealthKitStub(),
            metricsSource: metricsSource,
            liveActivityManager: MockLiveActivityManager()
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        controller.pauseWorkout()
        metricsSource.startErrorToThrow = CocoaError(.fileReadUnknown)

        controller.resumeWorkout()

        #expect(controller.state == .paused)
        #expect(controller.isPresenting)

        metricsSource.startErrorToThrow = nil
        controller.resumeWorkout()

        #expect(controller.state == .active)
        #expect(metricsSource.startCount == 3)

        await controller.discardWorkout()
    }

    @Test
    func expeditionModeUsesReducedMetricsCadenceAndClearsOnDiscard() async {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        let liveActivity = MockLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity,
            isExpeditionModeEnabled: { true }
        )

        await controller.startWorkout(type: .hike, targetSteps: nil)

        #expect(controller.isExpeditionModeActive)
        #expect(controller.metricsRefreshIntervalSeconds == 60)

        await controller.discardWorkout()

        #expect(!controller.isExpeditionModeActive)
        #expect(controller.metricsRefreshIntervalSeconds == 5)
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
    func concurrentFinishRequestsTerminateWorkoutOnce() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        metricsSource.snapshotErrorToThrow = MotionError.noData
        let liveActivity = BlockingLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        var saveCalls = 0
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity,
            saveModelContext: { context in
                saveCalls += 1
                try context.save()
            }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        let firstFinish = Task { await controller.finishWorkout() }
        await liveActivity.waitUntilEndRequested()
        let secondFinish = Task { await controller.finishWorkout() }
        await Task.yield()

        liveActivity.unblockEnd()
        await firstFinish.value
        await secondFinish.value

        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.endTime != nil)
        #expect(sessions.first?.deletedAt == nil)
        #expect(healthKit.saveCount == 1)
        #expect(liveActivity.endCount == 1)
        #expect(saveCalls == 3)
    }

    @Test
    func concurrentFinishAndDiscardKeepCompletedWorkoutVisible() async throws {
        let persistence = PersistenceController(inMemory: true)
        let metricsSource = MockMetricsSource()
        metricsSource.snapshotErrorToThrow = MotionError.noData
        let liveActivity = BlockingLiveActivityManager()
        let healthKit = WorkoutSessionHealthKitStub()
        var saveCalls = 0
        let controller = WorkoutSessionController(
            modelContext: persistence.container.mainContext,
            healthKitService: healthKit,
            metricsSource: metricsSource,
            liveActivityManager: liveActivity,
            saveModelContext: { context in
                saveCalls += 1
                try context.save()
            }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        let finish = Task { await controller.finishWorkout() }
        await liveActivity.waitUntilEndRequested()
        let discard = Task { await controller.discardWorkout() }
        await Task.yield()

        liveActivity.unblockEnd()
        await finish.value
        await discard.value

        let sessions = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 1)
        #expect(sessions.first?.endTime != nil)
        #expect(sessions.first?.deletedAt == nil)
        #expect(healthKit.saveCount == 1)
        #expect(liveActivity.endCount == 1)
        #expect(saveCalls == 3)
    }

    @Test
    func failedFinishKeepsWorkoutActiveAndRetryCompletesOnce() async throws {
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
                if saveCalls == 2 {
                    throw CocoaError(.fileWriteUnknown)
                }
                try context.save()
            }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        await controller.finishWorkout()

        let sessionsAfterFailure = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(controller.state == .active)
        #expect(controller.isPresenting)
        #expect(sessionsAfterFailure.first?.endTime == nil)
        #expect(liveActivity.endCount == 0)
        #expect(metricsSource.stopCount == 0)
        #expect(healthKit.saveCount == 0)

        await controller.finishWorkout()

        #expect(healthKit.saveCount == 1)
        #expect(liveActivity.endCount == 1)
        #expect(!controller.isPresenting)
        if case .completed = controller.state {
            // expected
        } else {
            Issue.record("Expected completed state after retrying finish")
        }
    }

    @Test
    func failedDiscardCanFinishWithoutPersistingSoftDelete() async throws {
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
                if saveCalls == 2 {
                    throw CocoaError(.fileWriteUnknown)
                }
                try context.save()
            }
        )

        await controller.startWorkout(type: .outdoorWalk, targetSteps: nil)
        await controller.discardWorkout()

        let sessionsAfterFailure = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(controller.state == .active)
        #expect(controller.isPresenting)
        #expect(sessionsAfterFailure.first?.deletedAt == nil)
        #expect(liveActivity.endCount == 0)
        #expect(metricsSource.stopCount == 0)

        await controller.finishWorkout()

        let sessionsAfterFinish = try persistence.container.mainContext.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessionsAfterFinish.count == 1)
        #expect(sessionsAfterFinish.first?.endTime != nil)
        #expect(sessionsAfterFinish.first?.deletedAt == nil)
        #expect(healthKit.saveCount == 1)
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
                    throw CocoaError(.fileWriteUnknown)
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
final class BlockingLiveActivityManager: LiveActivityManaging {
    private(set) var endCount = 0
    private var endRequestedContinuation: CheckedContinuation<Void, Never>?
    private var endWaiters: [CheckedContinuation<Void, Never>] = []
    private var isEndUnblocked = false

    func start(type _: WorkoutType) {}

    func update(steps _: Int, distance _: Double, calories _: Double) async {}

    func waitUntilEndRequested() async {
        if endCount > 0 { return }
        await withCheckedContinuation { continuation in
            endRequestedContinuation = continuation
        }
    }

    func unblockEnd() {
        isEndUnblocked = true
        let waiters = endWaiters
        endWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func end() async {
        endCount += 1
        endRequestedContinuation?.resume()
        endRequestedContinuation = nil
        if isEndUnblocked { return }

        await withCheckedContinuation { continuation in
            if isEndUnblocked {
                continuation.resume()
            } else {
                endWaiters.append(continuation)
            }
        }
    }
}

@MainActor
final class WorkoutSessionHealthKitStub: HealthKitServiceProtocol {
    var saveCount = 0
    var requestCount = 0
    var assignedWorkoutID: UUID? = UUID()
    var saveError: (any Error)?

    func requestAuthorization() async throws {
        requestCount += 1
    }

    func fetchTodaySteps() async throws -> Int { 0 }
    func fetchSteps(from _: Date, to _: Date) async throws -> Int { 0 }
    func fetchWheelchairPushes(from _: Date, to _: Date) async throws -> Int { 0 }
    func fetchDistance(from _: Date, to _: Date) async throws -> Double { 0 }
    func fetchWheelchairDistance(from _: Date, to _: Date) async throws -> Double { 0 }
    func fetchFloors(from _: Date, to _: Date) async throws -> Int { 0 }
    func fetchLatestHeartRateSample(from _: Date, to _: Date) async throws -> HeartRateSample? { nil }
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

    func saveWorkout(_ session: WorkoutSession) async throws -> HealthKitWorkoutSaveOutcome {
        if let saveError { throw saveError }
        saveCount += 1
        guard let assignedWorkoutID else { return .deferred }
        session.healthKitWorkoutID = assignedWorkoutID
        return .exported(assignedWorkoutID)
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
    func fetchWheelchairDistance(from _: Date, to _: Date) async throws -> Double { 0 }
    func fetchFloors(from _: Date, to _: Date) async throws -> Int { 0 }
    func fetchLatestHeartRateSample(from _: Date, to _: Date) async throws -> HeartRateSample? { nil }
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

    func saveWorkout(_ session: WorkoutSession) async throws -> HealthKitWorkoutSaveOutcome {
        _ = session
        saveCount += 1
        return .deferred
    }
}
