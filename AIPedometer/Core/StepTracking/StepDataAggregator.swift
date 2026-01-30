import HealthKit

actor StepDataAggregator {
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
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
