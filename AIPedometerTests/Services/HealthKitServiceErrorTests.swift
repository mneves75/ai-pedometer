import Foundation
import HealthKit
import Testing

@testable import AIPedometer

private enum StepStatisticsExecutorTestError: Error {
    case expected
}

private actor StepStatisticsExecutorProbe: StepStatisticsQueryExecuting {
    private var cumulativeResult: Result<Double?, any Error> = .success(nil)
    private var dailyResult: Result<[StepStatisticsBucket], any Error> = .success([])
    private var sourceResult: Result<[StepSourceStatistics], any Error> = .success([])
    private(set) var cumulativeDescriptors: [StepStatisticsQueryDescriptor] = []
    private(set) var dailyDescriptors: [StepStatisticsQueryDescriptor] = []
    private(set) var sourceDescriptors: [StepStatisticsQueryDescriptor] = []

    func setCumulativeResult(_ result: Result<Double?, any Error>) {
        cumulativeResult = result
    }

    func setDailyResult(_ result: Result<[StepStatisticsBucket], any Error>) {
        dailyResult = result
    }

    func setSourceResult(_ result: Result<[StepSourceStatistics], any Error>) {
        sourceResult = result
    }

    func cumulativeSteps(for descriptor: StepStatisticsQueryDescriptor) async throws -> Double? {
        cumulativeDescriptors.append(descriptor)
        return try cumulativeResult.get()
    }

    func dailySteps(for descriptor: StepStatisticsQueryDescriptor) async throws -> [StepStatisticsBucket] {
        dailyDescriptors.append(descriptor)
        return try dailyResult.get()
    }

    func stepsBySource(for descriptor: StepStatisticsQueryDescriptor) async throws -> [StepSourceStatistics] {
        sourceDescriptors.append(descriptor)
        return try sourceResult.get()
    }
}

@MainActor
struct HealthKitServiceErrorTests {
    @Test("Detects HealthKit no-data error")
    func detectsNoDataError() {
        let error = NSError(domain: HKErrorDomain, code: HKError.Code.errorNoData.rawValue)
        #expect(HealthKitService.isNoDataError(error))
    }

    @Test("Does not flag other HealthKit errors as no-data")
    func ignoresNonNoDataErrors() {
        let error = NSError(domain: HKErrorDomain, code: HKError.Code.errorAuthorizationDenied.rawValue)
        #expect(!HealthKitService.isNoDataError(error))
    }

    @Test("Does not flag non-HealthKit errors")
    func ignoresNonHealthKitErrors() {
        let error = NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue)
        #expect(!HealthKitService.isNoDataError(error))
    }
}

@Suite("StepDataAggregator query construction and mapping")
struct StepDataAggregatorTests {
    @Test("Daily query uses strict-start predicate semantics and the injected calendar anchor")
    func dailyDescriptorUsesStrictStartAndCalendarAnchor() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let start = try #require(ISO8601DateFormatter().date(from: "2026-07-17T14:15:00Z"))
        let end = try #require(ISO8601DateFormatter().date(from: "2026-07-19T14:15:00Z"))
        let executor = StepStatisticsExecutorProbe()
        let aggregator = StepDataAggregator(executor: executor, calendar: calendar)

        let result = try await aggregator.fetchDailySteps(from: start, to: end)

        #expect(result.isEmpty)
        let descriptor = try #require(await executor.dailyDescriptors.last)
        #expect(descriptor.startDate == start)
        #expect(descriptor.endDate == end)
        #expect(descriptor.predicateOptions == .strictStartDate)
        #expect(descriptor.statisticsOptions == [.cumulativeSum])
        #expect(descriptor.anchorDate == calendar.startOfDay(for: start))
        #expect(descriptor.intervalComponents == DateComponents(day: 1))
    }

    @Test("Empty cumulative statistics map to zero")
    func emptyCumulativeStatisticsMapToZero() async throws {
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 200)
        let executor = StepStatisticsExecutorProbe()
        let aggregator = StepDataAggregator(executor: executor)

        let steps = try await aggregator.fetchSteps(from: start, to: end)

        #expect(steps == 0)
        let descriptor = try #require(await executor.cumulativeDescriptors.last)
        #expect(descriptor.predicateOptions == .strictStartDate)
        #expect(descriptor.statisticsOptions == [.cumulativeSum])
    }

    // Any app with HealthKit write access contributes to these sums; `Int(_: Double)` traps on
    // non-finite values and on anything at or beyond 2^63.
    @Test(
        "Out-of-range HealthKit sums are clamped instead of trapping",
        arguments: [
            (1e19, Int(HealthCount.maximum)),
            (Double.infinity, 0),
            (Double.nan, 0),
            (-1, 0),
            (1_234.7, 1_234)
        ]
    )
    func outOfRangeCumulativeSumsAreClamped(raw: Double, expected: Int) async throws {
        let executor = StepStatisticsExecutorProbe()
        await executor.setCumulativeResult(.success(raw))
        await executor.setDailyResult(.success([StepStatisticsBucket(startDate: Date(timeIntervalSince1970: 150), steps: raw)]))
        let aggregator = StepDataAggregator(executor: executor)
        let start = Date(timeIntervalSince1970: 100)
        let end = Date(timeIntervalSince1970: 200)

        #expect(try await aggregator.fetchSteps(from: start, to: end) == expected)
        #expect(try await aggregator.fetchDailySteps(from: start, to: end).values.first == expected)
    }

    @Test("Cumulative executor failures retain the public queryFailed contract")
    func cumulativeFailureMapsToQueryFailed() async {
        let executor = StepStatisticsExecutorProbe()
        await executor.setCumulativeResult(.failure(StepStatisticsExecutorTestError.expected))
        let aggregator = StepDataAggregator(executor: executor)

        do {
            _ = try await aggregator.fetchSteps(
                from: Date(timeIntervalSince1970: 100),
                to: Date(timeIntervalSince1970: 200)
            )
            Issue.record("Expected HealthKitError.queryFailed")
        } catch let error as HealthKitError {
            guard case .queryFailed = error else {
                Issue.record("Expected HealthKitError.queryFailed, got \(error)")
                return
            }
        } catch {
            Issue.record("Expected HealthKitError.queryFailed, got \(error)")
        }
    }

    @Test("Daily buckets use the injected timezone rather than UTC boundaries")
    func dailyBucketsUseInjectedTimezone() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let beforeLocalMidnight = try #require(
            ISO8601DateFormatter().date(from: "2026-07-18T02:30:00Z")
        )
        let afterLocalMidnight = try #require(
            ISO8601DateFormatter().date(from: "2026-07-18T03:30:00Z")
        )
        let executor = StepStatisticsExecutorProbe()
        await executor.setDailyResult(.success([
            StepStatisticsBucket(startDate: beforeLocalMidnight, steps: 120.9),
            StepStatisticsBucket(startDate: afterLocalMidnight, steps: 340.1),
        ]))
        let aggregator = StepDataAggregator(executor: executor, calendar: calendar)

        let totals = try await aggregator.fetchDailySteps(
            from: beforeLocalMidnight,
            to: afterLocalMidnight.addingTimeInterval(60)
        )

        #expect(totals == [
            calendar.startOfDay(for: beforeLocalMidnight): 120,
            calendar.startOfDay(for: afterLocalMidnight): 340,
        ])
    }

    @Test("Daily executor errors propagate without touching HealthKit")
    func dailyExecutorErrorPropagates() async {
        let executor = StepStatisticsExecutorProbe()
        await executor.setDailyResult(.failure(StepStatisticsExecutorTestError.expected))
        let aggregator = StepDataAggregator(executor: executor)

        do {
            _ = try await aggregator.fetchDailySteps(
                from: Date(timeIntervalSince1970: 100),
                to: Date(timeIntervalSince1970: 200)
            )
            Issue.record("Expected the executor error")
        } catch StepStatisticsExecutorTestError.expected {
            // Expected characterization of the existing async descriptor behavior.
        } catch {
            Issue.record("Expected StepStatisticsExecutorTestError.expected, got \(error)")
        }
    }

    @Test("Per-source statistics map fractional HealthKit quantities to integer steps")
    func sourceAggregationMapsConcreteValues() async throws {
        let source = HKSource.default()
        let executor = StepStatisticsExecutorProbe()
        await executor.setSourceResult(.success([
            StepSourceStatistics(source: source, steps: 987.9)
        ]))
        let aggregator = StepDataAggregator(executor: executor)

        let result = try await aggregator.fetchStepsBySource(
            from: Date(timeIntervalSince1970: 100),
            to: Date(timeIntervalSince1970: 200)
        )

        #expect(result == [source: 987])
        let descriptor = try #require(await executor.sourceDescriptors.last)
        #expect(descriptor.predicateOptions == .strictStartDate)
        #expect(descriptor.statisticsOptions == [.cumulativeSum, .separateBySource])
    }
}
