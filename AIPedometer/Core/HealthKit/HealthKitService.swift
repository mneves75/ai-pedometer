import Foundation
import HealthKit

/// A single heart-rate sample plus the timestamp it was recorded at. Exposing the timestamp
/// lets the UI display a freshness label ("12m ago") so a stale sample no longer reads as
/// "live" when the watch hasn't measured anything recently.
struct HeartRateSample: Sendable, Equatable {
    let bpm: Double
    let endDate: Date
}

struct HealthKitQuantityQuerySpec: @unchecked Sendable {
    let type: HKQuantityTypeIdentifier
    let unit: HKUnit
    let options: HKStatisticsOptions
    let predicateOptions: HKQueryOptions
}

@MainActor
protocol HealthKitServiceProtocol: Sendable {
    func requestAuthorization() async throws
    func fetchTodaySteps() async throws -> Int
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int
    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int
    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double
    /// Wheelchair-mode distance, mirroring `fetchDistance` but querying `distanceWheelchair`.
    /// Apple ships this as a first-class quantity type and the previous code hard-coded zero,
    /// which silently shipped a worse experience to wheelchair users.
    func fetchWheelchairDistance(from startDate: Date, to endDate: Date) async throws -> Double
    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int
    func fetchLatestHeartRateSample(from startDate: Date, to endDate: Date) async throws -> HeartRateSample?
    func fetchDailySummaries(days: Int, activityMode: ActivityTrackingMode, distanceMode: DistanceEstimationMode, manualStepLength: Double, dailyGoal: Int) async throws -> [DailyStepSummary]
    func fetchDailySummaries(from startDate: Date, to endDate: Date, activityMode: ActivityTrackingMode, distanceMode: DistanceEstimationMode, manualStepLength: Double, dailyGoal: Int) async throws -> [DailyStepSummary]
    func saveWorkout(_ session: WorkoutSession) async throws -> HealthKitWorkoutSaveOutcome
}

@MainActor
final class HealthKitService: HealthKitServiceProtocol, Sendable {
    typealias StatisticsSumExecutor = @MainActor (
        _ spec: HealthKitQuantityQuerySpec,
        _ startDate: Date,
        _ endDate: Date
    ) async throws -> Double?
    typealias DailyTotalsExecutor = @MainActor (
        _ spec: HealthKitQuantityQuerySpec,
        _ startDate: Date,
        _ endDate: Date
    ) async throws -> [Date: Double]
    typealias WorkoutLookupExecutor = @MainActor (_ externalIdentifier: String) async throws -> UUID?
    typealias WorkoutCreationExecutor = @MainActor (
        _ session: WorkoutSession,
        _ externalIdentifier: String
    ) async throws -> UUID

    private let healthStore: HKHealthStore
    private let calendar: Calendar
    private let authorization: HealthKitAuthorization
    private let statisticsSumExecutor: StatisticsSumExecutor?
    private let dailyTotalsExecutor: DailyTotalsExecutor?
    private let workoutLookupExecutor: WorkoutLookupExecutor?
    private let workoutCreationExecutor: WorkoutCreationExecutor?
    private var inFlightWorkoutExports: [UUID: Task<UUID, any Error>] = [:]

    init(
        healthStore: HKHealthStore = HKHealthStore(),
        calendar: Calendar = .autoupdatingCurrent,
        authorization: HealthKitAuthorization? = nil,
        statisticsSumExecutor: StatisticsSumExecutor? = nil,
        dailyTotalsExecutor: DailyTotalsExecutor? = nil,
        workoutLookupExecutor: WorkoutLookupExecutor? = nil,
        workoutCreationExecutor: WorkoutCreationExecutor? = nil
    ) {
        self.healthStore = healthStore
        self.calendar = calendar
        self.authorization = authorization ?? HealthKitAuthorization(healthStore: healthStore)
        self.statisticsSumExecutor = statisticsSumExecutor
        self.dailyTotalsExecutor = dailyTotalsExecutor
        self.workoutLookupExecutor = workoutLookupExecutor
        self.workoutCreationExecutor = workoutCreationExecutor
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

    func fetchWheelchairDistance(from startDate: Date, to endDate: Date) async throws -> Double {
        try await fetchSum(type: .distanceWheelchair, unit: .meter(), from: startDate, to: endDate)
    }

    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int {
        Int(try await fetchSum(type: .flightsClimbed, unit: .count(), from: startDate, to: endDate))
    }

    func fetchLatestHeartRateSample(from startDate: Date, to endDate: Date) async throws -> HeartRateSample? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return nil
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictEndDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: Self.mapQueryError(error))
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let unit = HKUnit.count().unitDivided(by: .minute())
                let bpm = sample.quantity.doubleValue(for: unit)
                continuation.resume(returning: HeartRateSample(bpm: bpm, endDate: sample.endDate))
            }
            healthStore.execute(query)
        }
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
        // Pick the distance quantity type that matches the activity. Wheelchair users get real
        // `distanceWheelchair` totals here instead of the previous hard-coded zero.
        let distanceType: HKQuantityTypeIdentifier = activityMode == .steps
            ? .distanceWalkingRunning
            : .distanceWheelchair

        async let activityTotals = fetchDailyTotals(type: activityType, unit: .count(), from: startDay, to: endDate)
        async let distanceTotals = fetchDailyTotalsOrNil(type: distanceType, unit: .meter(), from: startDay, to: endDate)
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
                    // The distance query failed entirely. For walking modes fall back to the
                    // manual step-length estimate; for wheelchair mode there is no analogous
                    // multiplier, so we surface zero rather than invent data.
                    dayDistance = activityMode == .steps
                        ? Double(activityCount) * manualStepLength
                        : 0
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

    /// Shared tail of `saveWorkout`: both the empty-samples and post-`add` paths must end
    /// collection and finish the builder identically; error-path fixes belong in one place.
    nonisolated private static func endCollectionAndFinish(
        builder: HKWorkoutBuilder,
        end: Date,
        continuation: CheckedContinuation<UUID, any Error>
    ) {
        builder.endCollection(withEnd: end) { _, endError in
            if let endError {
                Loggers.health.error("healthkit.workout_end_failed", metadata: ["error": String(describing: endError)])
                continuation.resume(throwing: endError)
                return
            }
            builder.finishWorkout { workout, finishError in
                if let finishError {
                    Loggers.health.error("healthkit.workout_finish_failed", metadata: ["error": String(describing: finishError)])
                    continuation.resume(throwing: finishError)
                    return
                }
                guard let workout else {
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                continuation.resume(returning: workout.uuid)
            }
        }
    }

    nonisolated private static func addSamplesAndFinish(
        _ samples: [HKQuantitySample],
        builder: HKWorkoutBuilder,
        end: Date,
        continuation: CheckedContinuation<UUID, any Error>
    ) {
        guard !samples.isEmpty else {
            endCollectionAndFinish(builder: builder, end: end, continuation: continuation)
            return
        }
        builder.add(samples) { success, error in
            if let error {
                Loggers.health.error("healthkit.workout_samples_add_failed", metadata: [
                    "error": String(describing: error)
                ])
                continuation.resume(throwing: error)
                return
            }
            guard success else {
                continuation.resume(throwing: HealthKitError.queryFailed)
                return
            }
            endCollectionAndFinish(builder: builder, end: end, continuation: continuation)
        }
    }

    private func existingWorkoutID(externalIdentifier: String) async throws -> UUID? {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyExternalUUID,
            allowedValues: [externalIdentifier]
        )
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: Self.mapQueryError(error))
                    return
                }
                continuation.resume(returning: (samples?.first as? HKWorkout)?.uuid)
            }
            healthStore.execute(query)
        }
    }

    func saveWorkout(_ session: WorkoutSession) async throws -> HealthKitWorkoutSaveOutcome {
        let exportIdentifier = session.stableHealthKitExportIdentifier
        if let inFlightExport = inFlightWorkoutExports[exportIdentifier] {
            let workoutID = try await inFlightExport.value
            session.healthKitWorkoutID = workoutID
            return .exported(workoutID)
        }

        let externalIdentifier = exportIdentifier.uuidString
        let export = Task { @MainActor [self] in
            try await exportWorkout(session, externalIdentifier: externalIdentifier)
        }
        inFlightWorkoutExports[exportIdentifier] = export
        defer { inFlightWorkoutExports.removeValue(forKey: exportIdentifier) }
        let workoutID = try await export.value
        session.healthKitWorkoutID = workoutID
        return .exported(workoutID)
    }

    private func exportWorkout(_ session: WorkoutSession, externalIdentifier: String) async throws -> UUID {
        let existingID = if let workoutLookupExecutor {
            try await workoutLookupExecutor(externalIdentifier)
        } else {
            try await existingWorkoutID(externalIdentifier: externalIdentifier)
        }
        if let existingID {
            return existingID
        }

        return if let workoutCreationExecutor {
            try await workoutCreationExecutor(session, externalIdentifier)
        } else {
            try await createWorkout(session, externalIdentifier: externalIdentifier)
        }
    }

    private func createWorkout(_ session: WorkoutSession, externalIdentifier: String) async throws -> UUID {
        let config = HKWorkoutConfiguration()
        config.activityType = session.type.healthKitType
        config.locationType = .unknown
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())
        let start = session.startTime
        let end = session.endTime ?? .now
        let samples = Self.makeWorkoutSamples(for: session, start: start, end: end)
        let workoutID = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UUID, any Error>) in
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

                builder.addMetadata([HKMetadataKeyExternalUUID: externalIdentifier]) { metadataSuccess, metadataError in
                    if let metadataError {
                        Loggers.health.error("healthkit.workout_metadata_add_failed", metadata: [
                            "error": String(describing: metadataError)
                        ])
                        continuation.resume(throwing: metadataError)
                        return
                    }
                    guard metadataSuccess else {
                        continuation.resume(throwing: HealthKitError.queryFailed)
                        return
                    }
                    Self.addSamplesAndFinish(
                        samples,
                        builder: builder,
                        end: end,
                        continuation: continuation
                    )
                }
            }
        }
        return workoutID
    }

    nonisolated static func makeWorkoutSamples(
        for session: WorkoutSession,
        start: Date,
        end: Date
    ) -> [HKQuantitySample] {
        guard start <= end else { return [] }

        var samples: [HKQuantitySample] = []

        if session.steps > 0 {
            let quantity = HKQuantity(unit: .count(), doubleValue: Double(session.steps))
            let sample = HKQuantitySample(
                type: .quantityType(forIdentifier: .stepCount)!,
                quantity: quantity,
                start: start,
                end: end
            )
            samples.append(sample)
        }

        if session.distance > 0 {
            let quantity = HKQuantity(unit: .meter(), doubleValue: session.distance)
            let sample = HKQuantitySample(
                type: .quantityType(forIdentifier: .distanceWalkingRunning)!,
                quantity: quantity,
                start: start,
                end: end
            )
            samples.append(sample)
        }

        if session.activeCalories > 0 {
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: session.activeCalories)
            let sample = HKQuantitySample(
                type: .quantityType(forIdentifier: .activeEnergyBurned)!,
                quantity: quantity,
                start: start,
                end: end
            )
            samples.append(sample)
        }

        return samples
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

        let spec = Self.statisticsQuerySpec(for: type, unit: unit)
        if let statisticsSumExecutor {
            return try await statisticsSumExecutor(spec, startDate, endDate) ?? 0
        }

        let quantityType = HKQuantityType(spec.type)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: spec.predicateOptions
        )

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, any Error>) in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: spec.options
            ) { _, statistics, error in
                if let error {
                    Loggers.health.error("healthkit.sum_failed", metadata: [
                        "type": type.rawValue,
                        "error": String(describing: error),
                    ])
                    continuation.resume(throwing: Self.mapQueryError(error))
                    return
                }

                let value = statistics?.sumQuantity()?.doubleValue(for: spec.unit) ?? 0
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

        let spec = Self.statisticsQuerySpec(for: type, unit: unit)
        if let dailyTotalsExecutor {
            return try await dailyTotalsExecutor(spec, startDate, endDate)
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: spec.predicateOptions
        )
        let anchorDate = calendar.startOfDay(for: startDate)
        let interval = DateComponents(day: 1)

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(spec.type), predicate: predicate),
            options: spec.options,
            anchorDate: anchorDate,
            intervalComponents: interval
        )
        let collection = try await descriptor.result(for: healthStore)

        var totals: [Date: Double] = [:]
        collection.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
            let day = self.calendar.startOfDay(for: statistics.startDate)
            totals[day] = statistics.sumQuantity()?.doubleValue(for: spec.unit) ?? 0
        }
        return totals
    }

    nonisolated static func statisticsQuerySpec(
        for type: HKQuantityTypeIdentifier,
        unit: HKUnit? = nil
    ) -> HealthKitQuantityQuerySpec {
        let resolvedUnit: HKUnit
        if let unit {
            resolvedUnit = unit
        } else {
            switch type {
            case .stepCount, .pushCount, .flightsClimbed:
                resolvedUnit = .count()
            case .distanceWalkingRunning, .distanceWheelchair:
                resolvedUnit = .meter()
            case .activeEnergyBurned:
                resolvedUnit = .kilocalorie()
            default:
                resolvedUnit = .count()
            }
        }
        return HealthKitQuantityQuerySpec(
            type: type,
            unit: resolvedUnit,
            options: .cumulativeSum,
            predicateOptions: .strictStartDate
        )
    }
}
