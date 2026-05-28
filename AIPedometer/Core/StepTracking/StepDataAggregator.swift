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

actor StepDataAggregator: StepHistoryProviding {
    private let healthStore: HKHealthStore
    private let calendar: Calendar

    init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .autoupdatingCurrent) {
        self.healthStore = healthStore
        self.calendar = calendar
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        let stepType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error {
                    Loggers.health.error("healthkit.aggregate_failed", metadata: ["error": String(describing: error)])
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                let steps = statistics?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(steps))
            }
            healthStore.execute(query)
        }
    }

    func fetchDailySteps(from startDate: Date, to endDate: Date) async throws -> [Date: Int] {
        guard startDate < endDate else { return [:] }

        let stepType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let anchorDate = calendar.startOfDay(for: startDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: [.cumulativeSum],
            anchorDate: anchorDate,
            intervalComponents: DateComponents(day: 1)
        )

        let collection = try await descriptor.result(for: healthStore)
        // Bind the calendar to a local `let` so the (non-isolated) enumeration block captures no
        // actor-isolated state — capturing `self` here trips Swift 6 "sending 'totals'" isolation checks.
        let bucketCalendar = calendar
        var totals: [Date: Int] = [:]
        collection.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
            let day = bucketCalendar.startOfDay(for: statistics.startDate)
            let steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
            totals[day] = Int(steps)
        }
        return totals
    }

    func fetchStepsBySource(from startDate: Date, to endDate: Date) async throws -> [HKSource: Int] {
        let stepType = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum, .separateBySource]
            ) { _, statistics, error in
                if let error {
                    Loggers.health.error("healthkit.aggregate_by_source_failed", metadata: ["error": String(describing: error)])
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                var result: [HKSource: Int] = [:]
                if let sources = statistics?.sources {
                    for source in sources {
                        if let quantity = statistics?.sumQuantity(for: source) {
                            result[source] = Int(quantity.doubleValue(for: .count()))
                        }
                    }
                }
                continuation.resume(returning: result)
            }
            healthStore.execute(query)
        }
    }
}
