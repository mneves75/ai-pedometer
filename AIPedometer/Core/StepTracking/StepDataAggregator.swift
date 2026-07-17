import HealthKit

/// Read seam for the historical step data that streak calculation needs.
///
/// Extracted as a protocol so `StreakCalculator` can be unit-tested without a live `HKHealthStore`
/// and so the daily-window query can be swapped for a fake that counts calls (guarding the
/// "one bucketed query, not one query per day" performance contract).
protocol StepHistoryProviding: Sendable {
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int
    /// Daily step totals bucketed by start-of-day, fetched in a single
    /// `HKStatisticsCollectionQuery` instead of one `HKStatisticsQuery` per day.
    /// Keys are start-of-day dates; days with no samples are omitted (callers treat them as 0).
    func fetchDailySteps(from startDate: Date, to endDate: Date) async throws -> [Date: Int]
}

struct StepStatisticsQueryDescriptor: Sendable {
    let startDate: Date
    let endDate: Date
    let predicateOptions: HKQueryOptions
    let statisticsOptions: HKStatisticsOptions
    let anchorDate: Date?
    let intervalComponents: DateComponents?
}

struct StepStatisticsBucket: Sendable {
    let startDate: Date
    let steps: Double?
}

struct StepSourceStatistics: Sendable {
    let source: HKSource
    let steps: Double
}

protocol StepStatisticsQueryExecuting: Sendable {
    func cumulativeSteps(for descriptor: StepStatisticsQueryDescriptor) async throws -> Double?
    func dailySteps(for descriptor: StepStatisticsQueryDescriptor) async throws -> [StepStatisticsBucket]
    func stepsBySource(for descriptor: StepStatisticsQueryDescriptor) async throws -> [StepSourceStatistics]
}

private actor HealthKitStepStatisticsQueryExecutor: StepStatisticsQueryExecuting {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    func cumulativeSteps(for descriptor: StepStatisticsQueryDescriptor) async throws -> Double? {
        let predicate = samplePredicate(for: descriptor)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: predicate,
                options: descriptor.statisticsOptions
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(
                    returning: statistics?.sumQuantity()?.doubleValue(for: .count())
                )
            }
            healthStore.execute(query)
        }
    }

    func dailySteps(for descriptor: StepStatisticsQueryDescriptor) async throws -> [StepStatisticsBucket] {
        guard let anchorDate = descriptor.anchorDate,
              let intervalComponents = descriptor.intervalComponents else {
            throw HealthKitError.queryFailed
        }
        let queryDescriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(
                type: HKQuantityType(.stepCount),
                predicate: samplePredicate(for: descriptor)
            ),
            options: descriptor.statisticsOptions,
            anchorDate: anchorDate,
            intervalComponents: intervalComponents
        )
        let collection = try await queryDescriptor.result(for: healthStore)
        var buckets: [StepStatisticsBucket] = []
        collection.enumerateStatistics(from: descriptor.startDate, to: descriptor.endDate) { statistics, _ in
            buckets.append(
                StepStatisticsBucket(
                    startDate: statistics.startDate,
                    steps: statistics.sumQuantity()?.doubleValue(for: .count())
                )
            )
        }
        return buckets
    }

    func stepsBySource(for descriptor: StepStatisticsQueryDescriptor) async throws -> [StepSourceStatistics] {
        let predicate = samplePredicate(for: descriptor)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: predicate,
                options: descriptor.statisticsOptions
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let values = statistics?.sources?.compactMap { source -> StepSourceStatistics? in
                    guard let quantity = statistics?.sumQuantity(for: source) else { return nil }
                    return StepSourceStatistics(
                        source: source,
                        steps: quantity.doubleValue(for: .count())
                    )
                } ?? []
                continuation.resume(returning: values)
            }
            healthStore.execute(query)
        }
    }

    private func samplePredicate(for descriptor: StepStatisticsQueryDescriptor) -> NSPredicate {
        HKQuery.predicateForSamples(
            withStart: descriptor.startDate,
            end: descriptor.endDate,
            options: descriptor.predicateOptions
        )
    }
}

actor StepDataAggregator: StepHistoryProviding {
    private let executor: any StepStatisticsQueryExecuting
    private let calendar: Calendar

    init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .autoupdatingCurrent) {
        self.executor = HealthKitStepStatisticsQueryExecutor(healthStore: healthStore)
        self.calendar = calendar
    }

    init(executor: any StepStatisticsQueryExecuting, calendar: Calendar = .autoupdatingCurrent) {
        self.executor = executor
        self.calendar = calendar
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        let descriptor = descriptor(
            from: startDate,
            to: endDate,
            statisticsOptions: [.cumulativeSum]
        )
        do {
            let steps = try await executor.cumulativeSteps(for: descriptor) ?? 0
            return Int(steps)
        } catch {
            Loggers.health.error("healthkit.aggregate_failed", metadata: ["error": String(describing: error)])
            throw HealthKitError.queryFailed
        }
    }

    func fetchDailySteps(from startDate: Date, to endDate: Date) async throws -> [Date: Int] {
        guard startDate < endDate else { return [:] }

        let anchorDate = calendar.startOfDay(for: startDate)
        let descriptor = descriptor(
            from: startDate,
            to: endDate,
            statisticsOptions: [.cumulativeSum],
            anchorDate: anchorDate,
            intervalComponents: DateComponents(day: 1)
        )

        let buckets = try await executor.dailySteps(for: descriptor)
        // Bind the calendar to a local `let` so the (non-isolated) enumeration block captures no
        // actor-isolated state — capturing `self` here trips Swift 6 "sending 'totals'" isolation checks.
        let bucketCalendar = calendar
        var totals: [Date: Int] = [:]
        for bucket in buckets {
            let day = bucketCalendar.startOfDay(for: bucket.startDate)
            let steps = bucket.steps ?? 0
            totals[day] = Int(steps)
        }
        return totals
    }

    func fetchStepsBySource(from startDate: Date, to endDate: Date) async throws -> [HKSource: Int] {
        let descriptor = descriptor(
            from: startDate,
            to: endDate,
            statisticsOptions: [.cumulativeSum, .separateBySource]
        )
        do {
            let sourceStatistics = try await executor.stepsBySource(for: descriptor)
            var result: [HKSource: Int] = [:]
            for statistics in sourceStatistics {
                result[statistics.source] = Int(statistics.steps)
            }
            return result
        } catch {
            Loggers.health.error(
                "healthkit.aggregate_by_source_failed",
                metadata: ["error": String(describing: error)]
            )
            throw HealthKitError.queryFailed
        }
    }

    private func descriptor(
        from startDate: Date,
        to endDate: Date,
        statisticsOptions: HKStatisticsOptions,
        anchorDate: Date? = nil,
        intervalComponents: DateComponents? = nil
    ) -> StepStatisticsQueryDescriptor {
        StepStatisticsQueryDescriptor(
            startDate: startDate,
            endDate: endDate,
            predicateOptions: .strictStartDate,
            statisticsOptions: statisticsOptions,
            anchorDate: anchorDate,
            intervalComponents: intervalComponents
        )
    }
}
