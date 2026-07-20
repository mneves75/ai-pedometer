import Foundation
import Observation
import SwiftData

enum WorkoutSessionError: Error, Equatable, Sendable, Identifiable {
    case unableToStart(String)
    case metricsUnavailable
    case saveFailed(String)
    case discardFailed(String)
    case sessionUnavailable

    var id: String {
        switch self {
        case .unableToStart(let message):
            "unableToStart-\(message)"
        case .metricsUnavailable:
            "metricsUnavailable"
        case .saveFailed(let message):
            "saveFailed-\(message)"
        case .discardFailed(let message):
            "discardFailed-\(message)"
        case .sessionUnavailable:
            "sessionUnavailable"
        }
    }
}

extension WorkoutSessionError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unableToStart:
            L10n.localized("Unable to start workout", comment: "Workout error title")
        case .metricsUnavailable:
            L10n.localized("Workout metrics unavailable", comment: "Workout error when live metrics cannot be read")
        case .saveFailed:
            L10n.localized("Unable to save workout", comment: "Workout error when saving fails")
        case .discardFailed:
            L10n.localized("Unable to discard workout", comment: "Workout error when discarding fails")
        case .sessionUnavailable:
            L10n.localized("Workout session unavailable", comment: "Workout error when no active session is found")
        }
    }
}

@Observable
@MainActor
final class WorkoutSessionController {
    private let modelContext: ModelContext
    private let healthKitService: any HealthKitServiceProtocol
    private let metricsSource: any WorkoutLiveMetricsSource
    private let liveActivityManager: any LiveActivityManaging
    private let fetchRecoverableSession: @MainActor (ModelContext, FetchDescriptor<WorkoutSession>) throws -> WorkoutSession?
    private let saveModelContext: @MainActor (ModelContext) throws -> Void
    private let now: () -> Date
    private let isExpeditionModeEnabled: () -> Bool
    private var stateMachine = WorkoutStateMachine()

    private var updateTask: Task<Void, Never>?
    private var activeSession: WorkoutSession?
    private var pauseStartedAt: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var lastPersistedAt: Date?
    private var accumulatedSteps: Int = 0
    private var accumulatedDistance: Double = 0
    private var isTerminatingSession = false
    private var recoveryLookupSucceeded = false

    private(set) var state: WorkoutState = .idle
    private(set) var metrics: WorkoutMetrics?
    var lastError: WorkoutSessionError?
    private(set) var workoutType: WorkoutType?
    private(set) var recoverableSession: WorkoutSession?
    private(set) var isExpeditionModeActive = false
    var isPresenting = false

    init(
        modelContext: ModelContext,
        healthKitService: any HealthKitServiceProtocol,
        metricsSource: any WorkoutLiveMetricsSource,
        liveActivityManager: any LiveActivityManaging = NoopLiveActivityManager(),
        fetchRecoverableSession: @escaping @MainActor (ModelContext, FetchDescriptor<WorkoutSession>) throws -> WorkoutSession? = {
            try $0.fetch($1).first
        },
        saveModelContext: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        now: @escaping () -> Date = { .now },
        isExpeditionModeEnabled: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.expeditionModeEnabled)
        }
    ) {
        self.modelContext = modelContext
        self.healthKitService = healthKitService
        self.metricsSource = metricsSource
        self.liveActivityManager = liveActivityManager
        self.fetchRecoverableSession = fetchRecoverableSession
        self.saveModelContext = saveModelContext
        self.now = now
        self.isExpeditionModeEnabled = isExpeditionModeEnabled
        loadRecoverableSession()
    }

    var isActive: Bool {
        switch state {
        case .active, .paused, .preparing:
            return true
        default:
            return false
        }
    }

    var elapsedTime: TimeInterval {
        guard let metrics else { return 0 }
        let end = pauseStartedAt ?? now()
        let total = end.timeIntervalSince(metrics.startTime) - totalPausedDuration
        return max(total, 0)
    }

    var metricsRefreshIntervalSeconds: Int {
        isExpeditionModeActive ? 60 : 5
    }

    var requiresWorkoutRecovery: Bool {
        recoverableSession != nil
    }

    func startWorkout(type: WorkoutType, targetSteps: Int?) async {
        guard recoveryLookupSucceeded, recoverableSession == nil else { return }
        guard activeSession == nil else {
            isPresenting = true
            return
        }

        resetState()
        let startTime = now()
        let session = WorkoutSession(type: type, startTime: startTime)
        modelContext.insert(session)

        do {
            try saveModelContext(modelContext)
        } catch {
            modelContext.delete(session)
            lastError = .saveFailed(error.localizedDescription)
            transition(.error(.unableToSave))
            return
        }

        activeSession = session
        workoutType = type
        metrics = WorkoutMetrics.initial(startTime: startTime, targetSteps: targetSteps)
        isExpeditionModeActive = isExpeditionModeEnabled()
        accumulatedSteps = 0
        accumulatedDistance = 0
        transition(.start)
        isPresenting = true

        do {
            try await healthKitService.requestAuthorization()
        } catch {
            Loggers.health.warning("workout.authorization_failed", metadata: ["error": error.localizedDescription])
        }

        guard isCurrentPreparingSession(session) else {
            return
        }

        do {
            try metricsSource.start(from: startTime)
        } catch {
            lastError = .unableToStart(error.localizedDescription)
            transition(.error(.unableToStart))
            discardSessionAfterFailure()
            return
        }

        guard isCurrentPreparingSession(session) else {
            metricsSource.stop()
            return
        }

        transition(.prepared)
        guard case .active = state else {
            metricsSource.stop()
            return
        }
        liveActivityManager.start(type: type)
        startMetricsLoop()
        await refreshMetrics()
    }

    func pauseWorkout() {
        guard case .active = state else { return }
        pauseStartedAt = now()
        if let metrics {
            accumulatedSteps = metrics.steps
            accumulatedDistance = metrics.distance
        }
        metricsSource.stop()
        updateTask?.cancel()
        transition(.pause)
    }

    func resumeWorkout() {
        guard case .paused = state else { return }
        let resumedAt = now()

        do {
            try metricsSource.start(from: resumedAt)
        } catch {
            lastError = .unableToStart(error.localizedDescription)
            return
        }

        if let pauseStartedAt {
            totalPausedDuration += resumedAt.timeIntervalSince(pauseStartedAt)
            self.pauseStartedAt = nil
        }
        lastError = nil
        transition(.resume)
        startMetricsLoop()
    }

    func finishWorkout() async {
        guard !isTerminatingSession else { return }
        guard let session = activeSession else {
            lastError = .sessionUnavailable
            transition(.error(.unableToSave))
            return
        }
        isTerminatingSession = true
        defer { isTerminatingSession = false }

        let endTime = now()
        let previousEndTime = session.endTime
        let previousUpdatedAt = session.updatedAt
        let previousSteps = session.steps
        let previousDistance = session.distance
        let previousActiveCalories = session.activeCalories
        session.endTime = endTime
        session.updatedAt = endTime

        if let metrics {
            session.steps = metrics.steps
            session.distance = metrics.distance
            session.activeCalories = metrics.calories
        }
        session.healthKitExportState = .pending
        _ = session.stableHealthKitExportIdentifier
        session.healthKitExportLastFailureAt = nil
        session.healthKitExportLastErrorCode = nil

        do {
            try saveModelContext(modelContext)
        } catch {
            session.endTime = previousEndTime
            session.updatedAt = previousUpdatedAt
            session.steps = previousSteps
            session.distance = previousDistance
            session.activeCalories = previousActiveCalories
            lastError = .saveFailed(error.localizedDescription)
            return
        }

        await endLiveMetrics()
        pauseStartedAt = nil
        lastError = nil

        await reconcileHealthKitExport(for: session)

        let summary = WorkoutSummary(
            type: session.type,
            startTime: session.startTime,
            endTime: session.endTime ?? endTime,
            steps: session.steps,
            distance: session.distance,
            activeCalories: session.activeCalories
        )
        transition(.finish(summary: summary))
        resetSession()
    }

    func finishRecoverableWorkout() async {
        guard !isTerminatingSession else { return }
        guard let session = recoverableSession else {
            lastError = .sessionUnavailable
            return
        }
        isTerminatingSession = true
        defer { isTerminatingSession = false }

        let checkpoint = max(session.updatedAt, session.startTime)
        let previousEndTime = session.endTime
        let previousUpdatedAt = session.updatedAt
        let previousExportStateRaw = session.healthKitExportStateRaw
        let previousExportIdentifier = session.healthKitExportIdentifier
        let previousFailureCount = session.healthKitExportFailureCountValue
        let previousFailureAt = session.healthKitExportLastFailureAt
        let previousErrorCode = session.healthKitExportLastErrorCode

        session.endTime = checkpoint
        session.updatedAt = checkpoint
        session.healthKitExportState = .pending
        _ = session.stableHealthKitExportIdentifier
        session.healthKitExportLastFailureAt = nil
        session.healthKitExportLastErrorCode = nil

        do {
            try saveModelContext(modelContext)
        } catch {
            session.endTime = previousEndTime
            session.updatedAt = previousUpdatedAt
            session.healthKitExportStateRaw = previousExportStateRaw
            session.healthKitExportIdentifier = previousExportIdentifier
            session.healthKitExportFailureCountValue = previousFailureCount
            session.healthKitExportLastFailureAt = previousFailureAt
            session.healthKitExportLastErrorCode = previousErrorCode
            lastError = .saveFailed(error.localizedDescription)
            return
        }

        await liveActivityManager.end()
        lastError = nil
        await reconcileHealthKitExport(for: session)
        loadRecoverableSession()
    }

    func discardRecoverableWorkout() async {
        guard !isTerminatingSession else { return }
        guard let session = recoverableSession else {
            lastError = .sessionUnavailable
            return
        }
        isTerminatingSession = true
        defer { isTerminatingSession = false }

        let discardedAt = now()
        let previousDeletedAt = session.deletedAt
        let previousUpdatedAt = session.updatedAt
        session.deletedAt = discardedAt
        session.updatedAt = discardedAt

        do {
            try saveModelContext(modelContext)
        } catch {
            session.deletedAt = previousDeletedAt
            session.updatedAt = previousUpdatedAt
            lastError = .discardFailed(error.localizedDescription)
            return
        }

        await liveActivityManager.end()
        lastError = nil
        loadRecoverableSession()
    }

    nonisolated private static func errorCode(for error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain):\(nsError.code)"
    }

    func discardWorkout() async {
        guard !isTerminatingSession else { return }
        guard let session = activeSession else {
            lastError = .sessionUnavailable
            transition(.error(.unableToSave))
            return
        }
        isTerminatingSession = true
        defer { isTerminatingSession = false }

        let discardedAt = now()
        let previousDeletedAt = session.deletedAt
        let previousUpdatedAt = session.updatedAt
        session.deletedAt = discardedAt
        session.updatedAt = discardedAt

        do {
            try saveModelContext(modelContext)
        } catch {
            session.deletedAt = previousDeletedAt
            session.updatedAt = previousUpdatedAt
            lastError = .discardFailed(error.localizedDescription)
            return
        }

        await endLiveMetrics()
        lastError = nil
        transition(.discard)
        resetSession()
    }

    func refreshMetrics() async {
        guard case .active = state else { return }
        do {
            let snapshot = try await metricsSource.snapshot()
            await updateMetrics(from: snapshot)
        } catch let error as MotionError {
            if case .noData = error {
                return
            }
            lastError = .metricsUnavailable
        } catch {
            lastError = .metricsUnavailable
        }
    }
}

private extension WorkoutSessionController {
    func loadRecoverableSession() {
        let predicate = #Predicate<WorkoutSession> { session in
            session.endTime == nil && session.deletedAt == nil
        }
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\WorkoutSession.updatedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        do {
            recoverableSession = try fetchRecoverableSession(modelContext, descriptor)
            recoveryLookupSucceeded = true
        } catch {
            recoverableSession = nil
            recoveryLookupSucceeded = false
            lastError = .sessionUnavailable
            Loggers.workouts.error("workout.recovery_fetch_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }

    func reconcileHealthKitExport(for session: WorkoutSession) async {
        do {
            switch try await healthKitService.saveWorkout(session) {
            case let .exported(workoutID):
                session.healthKitWorkoutID = workoutID
                session.healthKitExportState = .exported
                session.healthKitExportFailureCount = 0
                session.healthKitExportLastFailureAt = nil
                session.healthKitExportLastErrorCode = nil
            case .deferred:
                session.healthKitExportState = .pending
            case .notRequired:
                session.healthKitExportState = .notRequired
                session.healthKitExportFailureCount = 0
                session.healthKitExportLastFailureAt = nil
                session.healthKitExportLastErrorCode = nil
            }
        } catch {
            Loggers.health.warning("workout.healthkit_save_failed", metadata: ["error": error.localizedDescription])
            session.healthKitExportState = .pending
            session.healthKitExportFailureCount += 1
            session.healthKitExportLastFailureAt = now()
            session.healthKitExportLastErrorCode = Self.errorCode(for: error)
        }

        if session.healthKitExportState != .pending || session.healthKitExportFailureCount > 0 {
            do {
                try saveModelContext(modelContext)
            } catch {
                Loggers.workouts.error("workout.healthkit_id_persist_failed", metadata: [
                    "error": error.localizedDescription
                ])
                lastError = .saveFailed(error.localizedDescription)
            }
        }
    }

    func transition(_ event: WorkoutEvent) {
        stateMachine.send(event)
        state = stateMachine.state
    }

    func startMetricsLoop() {
        updateTask?.cancel()
        updateTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshMetrics()
                do {
                    try await Task.sleep(for: .seconds(self.metricsRefreshIntervalSeconds))
                } catch is CancellationError {
                    break
                } catch {
                    Loggers.workouts.error("workout.metrics_loop_sleep_failed", metadata: [
                        "error": error.localizedDescription
                    ])
                    break
                }
            }
        }
    }

    func updateMetrics(from snapshot: PedometerSnapshot) async {
        guard let session = activeSession, var metrics else { return }

        let totalSteps = accumulatedSteps + snapshot.steps
        let totalDistance = accumulatedDistance + snapshot.distance
        let calories = Double(totalSteps) * AppConstants.Metrics.caloriesPerStep
        lastError = nil
        metrics.steps = totalSteps
        metrics.distance = totalDistance
        metrics.calories = calories
        metrics.lastUpdated = now()
        self.metrics = metrics

        session.steps = totalSteps
        session.distance = totalDistance
        session.activeCalories = calories
        session.updatedAt = now()

        if shouldPersistMetrics() {
            do {
                try saveModelContext(modelContext)
                lastPersistedAt = now()
            } catch {
                Loggers.workouts.error("workout.metrics_save_failed", metadata: ["error": error.localizedDescription])
            }
        }

        let distanceKilometers = totalDistance / 1000
        await liveActivityManager.update(
            steps: totalSteps,
            distance: distanceKilometers,
            calories: calories
        )
    }

    func shouldPersistMetrics() -> Bool {
        guard let lastPersistedAt else { return true }
        return now().timeIntervalSince(lastPersistedAt) >= 60
    }

    func endLiveMetrics() async {
        updateTask?.cancel()
        metricsSource.stop()
        await liveActivityManager.end()
    }

    func resetState() {
        lastError = nil
        pauseStartedAt = nil
        totalPausedDuration = 0
        lastPersistedAt = nil
        accumulatedSteps = 0
        accumulatedDistance = 0
        isExpeditionModeActive = false
        stateMachine = WorkoutStateMachine()
        state = .idle
    }

    func resetSession() {
        updateTask?.cancel()
        updateTask = nil
        metricsSource.stop()
        activeSession = nil
        workoutType = nil
        metrics = nil
        pauseStartedAt = nil
        totalPausedDuration = 0
        lastPersistedAt = nil
        accumulatedSteps = 0
        accumulatedDistance = 0
        isExpeditionModeActive = false
        isPresenting = false
    }

    func discardSessionAfterFailure() {
        guard let session = activeSession else { return }
        let startupError = lastError
        session.deletedAt = now()
        session.updatedAt = now()
        do {
            try saveModelContext(modelContext)
        } catch {
            Loggers.workouts.error("workout.session_discard_save_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
        resetSession()
        resetState()
        lastError = startupError
    }

    func isCurrentPreparingSession(_ session: WorkoutSession) -> Bool {
        guard activeSession === session else { return false }
        guard case .preparing = state else { return false }
        return true
    }
}
