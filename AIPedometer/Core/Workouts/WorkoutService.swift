import HealthKit
import SwiftData

@MainActor
final class WorkoutService {
    private let healthStore: HKHealthStore
    private let persistence: PersistenceController

    init(healthStore: HKHealthStore = HKHealthStore(), persistence: PersistenceController) {
        self.healthStore = healthStore
        self.persistence = persistence
    }

    func startSession(type: WorkoutType) throws -> WorkoutSession {
        let session = WorkoutSession(type: type, startTime: .now)
        let context = persistence.container.mainContext
        context.insert(session)
        try context.save()
        return session
    }

    func finishSession(_ session: WorkoutSession) throws {
        session.endTime = .now
        session.updatedAt = .now
        let context = persistence.container.mainContext
        try context.save()

        let workoutType = session.type
        let start = session.startTime
        let end = session.endTime ?? .now
        Task { [healthStore] in
            try await Self.saveToHealthKit(
                healthStore: healthStore,
                workoutType: workoutType,
                start: start,
                end: end
            )
        }
    }

    private static func saveToHealthKit(
        healthStore: HKHealthStore,
        workoutType: WorkoutType,
        start: Date,
        end: Date
    ) async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = workoutType.healthKitType
        config.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: start) { success, error in
                if let error {
                    Loggers.workouts.error("workout.begin_failed", metadata: ["error": String(describing: error)])
                    continuation.resume(throwing: error)
                    return
                }
                if !success {
                    continuation.resume(throwing: WorkoutError.unableToStart)
                    return
                }
                builder.endCollection(withEnd: end) { _, endError in
                    if let endError {
                        Loggers.workouts.error("workout.end_failed", metadata: ["error": String(describing: endError)])
                        continuation.resume(throwing: endError)
                        return
                    }
                    builder.finishWorkout { _, finishError in
                        if let finishError {
                            Loggers.workouts.error("workout.finish_failed", metadata: ["error": String(describing: finishError)])
                            continuation.resume(throwing: finishError)
                            return
                        }
                        continuation.resume()
                    }
                }
            }
        }
    }
}
