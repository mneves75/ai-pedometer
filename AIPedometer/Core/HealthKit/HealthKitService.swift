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
    func fetchDailySummaries(from startDate: Date, to endDate: Date, activityMode: ActivityTrackingMode, distanceMode: DistanceEstimationMode, manualStepLength: Double, dailyGoal: Int) async throws -> [DailyStepSummary]
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
        guard days > 0 else { return [] }
        let now = Date.now
        let endDate = now
        let endDay = calendar.startOfDay(for: now)
        let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) ?? endDay
        return try await fetchDailySummaries(
            from: startDay,
            to: endDate,
            activityMode: activityMode,
            distanceMode: distanceMode,
            manualStepLength: manualStepLength,
            dailyGoal: dailyGoal
        )
    }

    func fetchDailySummaries(
        from startDate: Date,
        to endDate: Date,
        activityMode: ActivityTrackingMode = .steps,
        distanceMode: DistanceEstimationMode = .automatic,
        manualStepLength: Double = AppConstants.Defaults.manualStepLengthMeters,
        dailyGoal: Int = AppConstants.defaultDailyGoal
    ) async throws -> [DailyStepSummary] {
        let startDay = calendar.startOfDay(for: startDate)
        guard startDay <= endDate else { return [] }
        let endDay = calendar.startOfDay(for: endDate)

        let activityType: HKQuantityTypeIdentifier = activityMode == .steps ? .stepCount : .pushCount
        let activityTotals = try await fetchDailyTotals(
            typeIdentifier: activityType,
            unit: .count(),
            from: startDay,
            to: endDate
        )

        let distanceTotals: [Date: Double]
        var distanceUnavailable = false
        do {
            distanceTotals = try await fetchDailyTotals(
                typeIdentifier: .distanceWalkingRunning,
                unit: .meter(),
                from: startDay,
                to: endDate
            )
        } catch {
            distanceUnavailable = true
            Loggers.health.warning("healthkit.distance_unavailable", metadata: [
                "error": error.localizedDescription
            ])
            distanceTotals = [:]
        }

        let floorsTotals: [Date: Double]
        var floorsUnavailable = false
        do {
            floorsTotals = try await fetchDailyTotals(
                typeIdentifier: .flightsClimbed,
                unit: .count(),
                from: startDay,
                to: endDate
            )
        } catch {
            floorsUnavailable = true
            Loggers.health.warning("healthkit.floors_unavailable", metadata: [
                "error": error.localizedDescription
            ])
            floorsTotals = [:]
        }

        var summaries: [DailyStepSummary] = []
        var current = startDay
        while current <= endDay {
            let activityCount = Int(activityTotals[current] ?? 0)

            let distance: Double
            switch distanceMode {
            case .manual:
                distance = Double(activityCount) * manualStepLength
            case .automatic:
                if distanceUnavailable {
                    distance = Double(activityCount) * manualStepLength
                } else {
                    distance = distanceTotals[current] ?? 0
                }
            }

            let floors = floorsUnavailable ? 0 : Int(floorsTotals[current] ?? 0)

            summaries.append(
                DailyStepSummary(
                    date: current,
                    steps: activityCount,
                    distance: distance,
                    floors: floors,
                    calories: Double(activityCount) * AppConstants.Metrics.caloriesPerStep,
                    goal: dailyGoal
                )
            )

            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
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

    private func fetchDailyTotals(
        typeIdentifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [Date: Double] {
        let calendar = calendar
        let quantityType = HKQuantityType(typeIdentifier)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let anchorDate = calendar.startOfDay(for: startDate)
        let interval = DateComponents(day: 1)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, collection, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [:])
                        return
                    }
                    Loggers.health.error("healthkit.collection_query_failed", metadata: [
                        "error": String(describing: error),
                        "type": typeIdentifier.rawValue
                    ])
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }

                var totals: [Date: Double] = [:]
                if let collection {
                    collection.enumerateStatistics(from: anchorDate, to: endDate) { statistics, _ in
                        let total = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
                        totals[calendar.startOfDay(for: statistics.startDate)] = total
                    }
                }
                continuation.resume(returning: totals)
            }
            healthStore.execute(query)
        }
    }
}
