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
            String(localized: "Unable to start workout", comment: "Workout error title")
        case .metricsUnavailable:
            String(localized: "Workout metrics unavailable", comment: "Workout error when live metrics cannot be read")
        case .saveFailed:
            String(localized: "Unable to save workout", comment: "Workout error when saving fails")
        case .discardFailed:
            String(localized: "Unable to discard workout", comment: "Workout error when discarding fails")
        case .sessionUnavailable:
            String(localized: "Workout session unavailable", comment: "Workout error when no active session is found")
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
    private let now: () -> Date
    private var stateMachine = WorkoutStateMachine()

    private var updateTask: Task<Void, Never>?
    private var activeSession: WorkoutSession?
    private var pauseStartedAt: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var lastPersistedAt: Date?
    private var accumulatedSteps: Int = 0
    private var accumulatedDistance: Double = 0

    private(set) var state: WorkoutState = .idle
    private(set) var metrics: WorkoutMetrics?
    var lastError: WorkoutSessionError?
    private(set) var workoutType: WorkoutType?
    var isPresenting = false

    init(
        modelContext: ModelContext,
        healthKitService: any HealthKitServiceProtocol,
        metricsSource: any WorkoutLiveMetricsSource,
        liveActivityManager: any LiveActivityManaging = NoopLiveActivityManager(),
        now: @escaping () -> Date = { .now }
    ) {
        self.modelContext = modelContext
        self.healthKitService = healthKitService
        self.metricsSource = metricsSource
        self.liveActivityManager = liveActivityManager
        self.now = now
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

    func startWorkout(type: WorkoutType, targetSteps: Int?) async {
        guard activeSession == nil else {
            isPresenting = true
            return
        }

        resetState()
        let startTime = now()
        let session = WorkoutSession(type: type, startTime: startTime)
        modelContext.insert(session)

        do {
            try modelContext.save()
        } catch {
            lastError = .saveFailed(error.localizedDescription)
            transition(.error(.unableToSave))
            return
        }

        activeSession = session
        workoutType = type
        metrics = WorkoutMetrics.initial(startTime: startTime, targetSteps: targetSteps)
        accumulatedSteps = 0
        accumulatedDistance = 0
        transition(.start)
        isPresenting = true

        do {
            try await healthKitService.requestAuthorization()
        } catch {
            Loggers.health.warning("workout.authorization_failed", metadata: ["error": error.localizedDescription])
        }

        do {
            try metricsSource.start(from: startTime)
        } catch {
            lastError = .unableToStart(error.localizedDescription)
            transition(.error(.unableToStart))
            discardSessionAfterFailure()
            return
        }

        transition(.prepared)
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
        if let pauseStartedAt {
            totalPausedDuration += now().timeIntervalSince(pauseStartedAt)
            self.pauseStartedAt = nil
        }

        do {
            try metricsSource.start(from: now())
        } catch {
            lastError = .unableToStart(error.localizedDescription)
            transition(.error(.unableToStart))
            return
        }

        transition(.resume)
        startMetricsLoop()
    }

    func finishWorkout() async {
        guard let session = activeSession else {
            lastError = .sessionUnavailable
            transition(.error(.unableToSave))
            return
        }

        await endLiveMetrics()
        pauseStartedAt = nil

        let endTime = now()
        session.endTime = endTime
        session.updatedAt = endTime

        if let metrics {
            session.steps = metrics.steps
            session.distance = metrics.distance
            session.activeCalories = metrics.calories
        }

        do {
            try modelContext.save()
        } catch {
            lastError = .saveFailed(error.localizedDescription)
            transition(.error(.unableToSave))
            return
        }

        do {
            try await healthKitService.saveWorkout(session)
        } catch {
            Loggers.health.warning("workout.healthkit_save_failed", metadata: ["error": error.localizedDescription])
        }

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

    func discardWorkout() {
        guard let session = activeSession else {
            lastError = .sessionUnavailable
            transition(.error(.unableToSave))
            return
        }

        endLiveMetricsDetached()
        session.deletedAt = now()
        session.updatedAt = now()

        do {
            try modelContext.save()
        } catch {
            lastError = .discardFailed(error.localizedDescription)
            return
        }

        transition(.discard)
        resetSession()
    }

    func refreshMetrics() async {
        guard case .active = state else { return }
        do {
            let snapshot = try await metricsSource.snapshot()
            await updateMetrics(from: snapshot)
        } catch {
            lastError = .metricsUnavailable
        }
    }
}

private extension WorkoutSessionController {
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
                    try await Task.sleep(for: .seconds(5))
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
                try modelContext.save()
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

    func endLiveMetricsDetached() {
        updateTask?.cancel()
        metricsSource.stop()
        Task {
            await liveActivityManager.end()
        }
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
        isPresenting = false
    }

    func discardSessionAfterFailure() {
        guard let session = activeSession else { return }
        session.deletedAt = now()
        session.updatedAt = now()
        do {
            try modelContext.save()
        } catch {
            Loggers.workouts.error("workout.session_discard_save_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
        resetSession()
        resetState()
    }
}
