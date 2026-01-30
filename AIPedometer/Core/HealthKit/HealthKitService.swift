import Foundation
import HealthKit

@MainActor
protocol HealthKitServiceProtocol: Sendable {
    func requestAuthorization() async throws
    func fetchTodaySteps() async throws -> Int
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int
    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int
    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double
    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int
    func fetchDailySummaries(days: Int, activityMode: ActivityTrackingMode, distanceMode: DistanceEstimationMode, manualStepLength: Double, dailyGoal: Int) async throws -> [DailyStepSummary]
    func saveWorkout(_ session: WorkoutSession) async throws
}

@MainActor
final class HealthKitService: HealthKitServiceProtocol, Sendable {
    private let healthStore: HKHealthStore
    private let calendar: Calendar

    init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .autoupdatingCurrent) {
        self.healthStore = healthStore
        self.calendar = calendar
    }

    func requestAuthorization() async throws {
        let authorization = HealthKitAuthorization()
        try await authorization.requestAuthorization()
    }

    func fetchTodaySteps() async throws -> Int {
        let start = calendar.startOfDay(for: .now)
        return try await fetchSteps(from: start, to: .now)
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        try await fetchCumulativeCount(type: .stepCount, from: startDate, to: endDate)
    }

    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int {
        try await fetchCumulativeCount(type: .pushCount, from: startDate, to: endDate)
    }

    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double {
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: distanceType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: 0)
                        return
                    }
                    Loggers.health.error("healthkit.distance_query_failed", metadata: ["error": String(describing: error)])
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                let meters = statistics?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                continuation.resume(returning: meters)
            }
            healthStore.execute(query)
        }
    }

    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int {
        let floorsType = HKQuantityType(.flightsClimbed)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: floorsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: 0)
                        return
                    }
                    Loggers.health.error("healthkit.floors_query_failed", metadata: ["error": String(describing: error)])
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                let floors = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(floors))
            }
            healthStore.execute(query)
        }
    }

    private func fetchCumulativeCount(type: HKQuantityTypeIdentifier, from startDate: Date, to endDate: Date) async throws -> Int {
        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: 0)
                        return
                    }
                    Loggers.health.error("healthkit.query_failed", metadata: ["error": String(describing: error), "type": type.rawValue])
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                let count = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(count))
            }
            healthStore.execute(query)
        }
    }

    nonisolated static func isNoDataError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == HKErrorDomain
            && nsError.code == HKError.Code.errorNoData.rawValue
    }

    func fetchDailySummaries(
        days: Int,
        activityMode: ActivityTrackingMode = .steps,
        distanceMode: DistanceEstimationMode = .automatic,
        manualStepLength: Double = AppConstants.Defaults.manualStepLengthMeters,
        dailyGoal: Int = AppConstants.defaultDailyGoal
    ) async throws -> [DailyStepSummary] {
        let now = Date.now
        var summaries: [DailyStepSummary] = []
        let builder = HealthKitSummaryBuilder(
            activityMode: activityMode,
            distanceMode: distanceMode,
            manualStepLength: manualStepLength,
            dailyGoal: dailyGoal
        )

        // Fetch all days concurrently for better performance
        try await withThrowingTaskGroup(of: (Int, DailyStepSummary).self) { group in
            for offset in (0..<days).reversed() {
                guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
                let start = calendar.startOfDay(for: date)
                let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now

                group.addTask {
                    let summary = try await builder.build(
                        date: start,
                        fetchSteps: { try await self.fetchSteps(from: start, to: end) },
                        fetchWheelchairPushes: { try await self.fetchWheelchairPushes(from: start, to: end) },
                        fetchDistance: { try await self.fetchDistance(from: start, to: end) },
                        fetchFloors: { try await self.fetchFloors(from: start, to: end) }
                    )
                    return (offset, summary)
                }
            }

            // Collect results
            var results: [(Int, DailyStepSummary)] = []
            for try await result in group {
                results.append(result)
            }

            // Sort by offset (reversed) to maintain chronological order
            summaries = results.sorted { $0.0 > $1.0 }.map(\.1)
        }

        return summaries
    }

    func saveWorkout(_ session: WorkoutSession) async throws {
        let config = HKWorkoutConfiguration()
        config.activityType = session.type.healthKitType
        config.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        let start = session.startTime
        let end = session.endTime ?? .now
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.beginCollection(withStart: start) { success, error in
                if let error {
                    Loggers.health.error("healthkit.workout_begin_failed", metadata: ["error": String(describing: error)])
                    continuation.resume(throwing: error)
                    return
                }
                if !success {
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                builder.endCollection(withEnd: end) { _, endError in
                    if let endError {
                        Loggers.health.error("healthkit.workout_end_failed", metadata: ["error": String(describing: endError)])
                        continuation.resume(throwing: endError)
                        return
                    }
                    builder.finishWorkout { _, finishError in
                        if let finishError {
                            Loggers.health.error("healthkit.workout_finish_failed", metadata: ["error": String(describing: finishError)])
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
