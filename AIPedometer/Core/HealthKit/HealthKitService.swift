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
        try await fetchMergedSum(
            type: .distanceWalkingRunning,
            unit: .meter(),
            from: startDate,
            to: endDate,
            errorLogEvent: "healthkit.distance_query_failed"
        )
    }

    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int {
        let floors = try await fetchMergedSum(
            type: .flightsClimbed,
            unit: .count(),
            from: startDate,
            to: endDate,
            errorLogEvent: "healthkit.floors_query_failed"
        )
        return Int(floors)
    }

    private func fetchCumulativeCount(type: HKQuantityTypeIdentifier, from startDate: Date, to endDate: Date) async throws -> Int {
        let total = try await fetchMergedSum(
            type: type,
            unit: .count(),
            from: startDate,
            to: endDate,
            errorLogEvent: "healthkit.query_failed"
        )
        return Int(total)
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
        let samples = try await fetchQuantitySamples(
            type: typeIdentifier,
            from: startDate,
            to: endDate,
            errorLogEvent: "healthkit.daily_sample_query_failed"
        )
        if samples.isEmpty { return [:] }

        let values = samples.map { sample in
            HealthKitSampleValue(
                start: sample.startDate,
                end: sample.endDate,
                value: sample.quantity.doubleValue(for: unit),
                sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                productType: sample.sourceRevision.productType,
                deviceModel: sample.device?.model,
                deviceName: sample.device?.name
            )
        }

        let calendar = calendar
        let result = await Task.detached {
            HealthKitSampleMerger.mergeDailyTotals(
                samples: values,
                calendar: calendar,
                from: startDate,
                to: endDate
            )
        }.value

        if result.daysWithMultipleSources > 0 {
            Loggers.health.info("healthkit.source_merge_applied_daily", metadata: [
                "type": typeIdentifier.rawValue,
                "days_with_multiple_sources": "\(result.daysWithMultipleSources)",
                "days_with_overlap": "\(result.daysWithOverlap)",
                "total_days": "\(result.totalDays)",
                "segments": "\(result.segmentCount)"
            ])
        }

        return result.totals
    }

    private func fetchMergedSum(
        type: HKQuantityTypeIdentifier,
        unit: HKUnit,
        from startDate: Date,
        to endDate: Date,
        errorLogEvent: String
    ) async throws -> Double {
        let samples = try await fetchQuantitySamples(
            type: type,
            from: startDate,
            to: endDate,
            errorLogEvent: errorLogEvent
        )
        if samples.isEmpty { return 0 }

        let values = samples.map { sample in
            HealthKitSampleValue(
                start: sample.startDate,
                end: sample.endDate,
                value: sample.quantity.doubleValue(for: unit),
                sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                productType: sample.sourceRevision.productType,
                deviceModel: sample.device?.model,
                deviceName: sample.device?.name
            )
        }

        let result = await Task.detached {
            HealthKitSampleMerger.mergeTotal(samples: values)
        }.value

        if result.mergedSources {
            Loggers.health.info("healthkit.source_merge_applied", metadata: [
                "type": type.rawValue,
                "source_count": "\(result.prioritiesPresent.count)",
                "overlap_seconds": "\(result.overlapSeconds)",
                "segments": "\(result.segmentCount)"
            ])
        }

        return result.total
    }

    private func fetchQuantitySamples(
        type: HKQuantityTypeIdentifier,
        from startDate: Date,
        to endDate: Date,
        errorLogEvent: String
    ) async throws -> [HKQuantitySample] {
        let quantityType = HKQuantityType(type)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    if Self.isNoDataError(error) {
                        continuation.resume(returning: [])
                        return
                    }
                    Loggers.health.error(errorLogEvent, metadata: [
                        "error": String(describing: error),
                        "type": type.rawValue
                    ])
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                let quantitySamples = samples as? [HKQuantitySample] ?? []
                continuation.resume(returning: quantitySamples)
            }
            healthStore.execute(query)
        }
    }
}
