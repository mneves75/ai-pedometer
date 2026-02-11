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
    private let authorization: HealthKitAuthorization

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        calendar: Calendar = .autoupdatingCurrent,
        authorization: HealthKitAuthorization? = nil
    ) {
        self.healthStore = healthStore
        self.calendar = calendar
        self.authorization = authorization ?? HealthKitAuthorization(healthStore: healthStore)
    }

    func requestAuthorization() async throws {
        try await authorization.requestAuthorization()
    }

    func fetchTodaySteps() async throws -> Int {
        let start = calendar.startOfDay(for: .now)
        return try await fetchSteps(from: start, to: .now)
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        Int(try await fetchSum(type: .stepCount, unit: .count(), from: startDate, to: endDate))
    }

    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int {
        Int(try await fetchSum(type: .pushCount, unit: .count(), from: startDate, to: endDate))
    }

    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double {
        try await fetchSum(type: .distanceWalkingRunning, unit: .meter(), from: startDate, to: endDate)
    }

    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int {
        Int(try await fetchSum(type: .flightsClimbed, unit: .count(), from: startDate, to: endDate))
    }

    nonisolated static func isNoDataError(_ error: any Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == HKErrorDomain
            && nsError.code == HKError.Code.errorNoData.rawValue
    }

    nonisolated static func mapQueryError(_ error: any Error) -> HealthKitError {
        let nsError = error as NSError
        guard nsError.domain == HKErrorDomain else { return .queryFailed }

        switch nsError.code {
        case HKError.Code.errorAuthorizationDenied.rawValue:
            return .authorizationFailed
        case HKError.Code.errorNoData.rawValue:
            return .noData
        default:
            return .queryFailed
        }
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

        async let activityTotals = fetchDailyTotals(type: activityType, unit: .count(), from: startDay, to: endDate)
        async let distanceTotals = fetchDailyTotalsOrNil(type: .distanceWalkingRunning, unit: .meter(), from: startDay, to: endDate)
        async let floorsTotals = fetchDailyTotalsOrNil(type: .flightsClimbed, unit: .count(), from: startDay, to: endDate)

        let activity = try await activityTotals
        let distance = await distanceTotals
        let floors = await floorsTotals

        var summaries: [DailyStepSummary] = []
        var current = startDay
        while current <= endDay {
            let activityCount = Int(activity[current] ?? 0)

            let dayDistance: Double
            switch distanceMode {
            case .manual:
                dayDistance = Double(activityCount) * manualStepLength
            case .automatic:
                if let distance {
                    dayDistance = distance[current] ?? 0
                } else {
                    dayDistance = Double(activityCount) * manualStepLength
                }
            }

            let dayFloors = floors.map { Int($0[current] ?? 0) } ?? 0

            summaries.append(
                DailyStepSummary(
                    date: current,
                    steps: activityCount,
                    distance: dayDistance,
                    floors: dayFloors,
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

    private func fetchSum(
        type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async throws -> Double {
        try await fetchStatisticsSum(type: type, unit: unit, from: startDate, to: endDate)
    }

    private func fetchDailyTotals(
        type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [Date: Double] {
        try await fetchDailyTotalsCollection(type: type, unit: unit, from: startDate, to: endDate)
    }

    private func fetchDailyTotalsOrNil(
        type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async -> [Date: Double]? {
        do {
            return try await fetchDailyTotals(type: type, unit: unit, from: startDate, to: endDate)
        } catch {
            Loggers.health.warning("healthkit.daily_totals_unavailable", metadata: [
                "type": type.rawValue, "error": error.localizedDescription
            ])
            return nil
        }
    }

    private func fetchStatisticsSum(
        type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async throws -> Double {
        guard startDate < endDate else { return 0 }

        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, any Error>) in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    Loggers.health.error("healthkit.sum_failed", metadata: [
                        "type": type.rawValue,
                        "error": String(describing: error),
                    ])
                    continuation.resume(throwing: Self.mapQueryError(error))
                    return
                }

                let value = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: value)
            }

            self.healthStore.execute(query)
        }
    }

    private func fetchDailyTotalsCollection(
        type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [Date: Double] {
        guard startDate < endDate else { return [:] }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let anchorDate = calendar.startOfDay(for: startDate)
        let interval = DateComponents(day: 1)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(type), predicate: predicate),
            options: [.cumulativeSum],
            anchorDate: anchorDate,
            intervalComponents: interval
        )
        let collection = try await descriptor.result(for: healthStore)

        var totals: [Date: Double] = [:]
        collection.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
            let day = self.calendar.startOfDay(for: statistics.startDate)
            totals[day] = statistics.sumQuantity()?.doubleValue(for: unit) ?? 0
        }
        return totals
    }
}
