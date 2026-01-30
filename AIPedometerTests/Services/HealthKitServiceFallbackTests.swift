import Foundation
import Testing

@testable import AIPedometer

@MainActor
struct HealthKitServiceFallbackTests {
    @Test("Uses fake data when useFakeData is enabled")
    func usesFakeDataWhenEnabled() async throws {
        let (store, defaults, cleanup) = makeDemoStore(useFakeData: true)
        defer { cleanup() }

        let failing = FailingHealthKitService(
            authorizationError: HealthKitError.authorizationFailed,
            queryError: HealthKitError.queryFailed
        )

        let service = HealthKitServiceFallback(
            primary: failing,
            demoModeStore: store,
            calendar: Calendar(identifier: .gregorian),
            isHealthDataAvailable: { true },
            userDefaults: defaults
        )

        try await service.requestAuthorization()

        let summaries = try await service.fetchDailySummaries(
            days: 7,
            activityMode: .steps,
            distanceMode: .automatic,
            manualStepLength: AppConstants.Defaults.manualStepLengthMeters,
            dailyGoal: 10_000
        )

        #expect(summaries.count == 7)
        #expect(summaries.allSatisfy { $0.steps > 0 })
    }

    @Test("Returns empty data gracefully when HealthKit unavailable and fake data off")
    func returnsEmptyDataWhenUnavailable() async throws {
        let (store, defaults, cleanup) = makeDemoStore(useFakeData: false)
        defer { cleanup() }

        let failing = FailingHealthKitService(
            authorizationError: HealthKitError.authorizationFailed,
            queryError: HealthKitError.queryFailed
        )

        let service = HealthKitServiceFallback(
            primary: failing,
            demoModeStore: store,
            calendar: Calendar(identifier: .gregorian),
            isHealthDataAvailable: { false },
            userDefaults: defaults
        )

        try await service.requestAuthorization()
        
        let steps = try await service.fetchTodaySteps()
        #expect(steps == 0)
        
        let summaries = try await service.fetchDailySummaries(
            days: 7,
            activityMode: .steps,
            distanceMode: .automatic,
            manualStepLength: AppConstants.Defaults.manualStepLengthMeters,
            dailyGoal: 10_000
        )
        #expect(summaries.isEmpty)
    }

    @Test("Uses real HealthKit when fake data disabled and HealthKit available")
    func usesRealHealthKitWhenAvailable() async throws {
        let (store, defaults, cleanup) = makeDemoStore(useFakeData: false)
        defer { cleanup() }

        let spy = SpyHealthKitService()
        let service = HealthKitServiceFallback(
            primary: spy,
            demoModeStore: store,
            calendar: Calendar(identifier: .gregorian),
            isHealthDataAvailable: { true },
            userDefaults: defaults
        )

        try await service.requestAuthorization()
        #expect(spy.authorizationCalls == 1)
        
        _ = try await service.fetchTodaySteps()
        #expect(spy.fetchTodayStepsCalls == 1)
    }

    @Test("Gracefully handles query failures without fake data")
    func handlesQueryFailuresGracefully() async throws {
        let (store, defaults, cleanup) = makeDemoStore(useFakeData: false)
        defer { cleanup() }

        let failing = FailingHealthKitService(
            authorizationError: nil,
            queryError: HealthKitError.queryFailed
        )

        let service = HealthKitServiceFallback(
            primary: failing,
            demoModeStore: store,
            calendar: Calendar(identifier: .gregorian),
            isHealthDataAvailable: { true },
            userDefaults: defaults
        )

        try await service.requestAuthorization()
        
        let steps = try await service.fetchTodaySteps()
        #expect(steps == 0)
    }
}

@MainActor
private final class FailingHealthKitService: HealthKitServiceProtocol {
    private let authorizationError: (any Error)?
    private let queryError: any Error

    init(authorizationError: (any Error)?, queryError: any Error) {
        self.authorizationError = authorizationError
        self.queryError = queryError
    }

    func requestAuthorization() async throws {
        if let authorizationError {
            throw authorizationError
        }
    }

    func fetchTodaySteps() async throws -> Int {
        throw queryError
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int {
        throw queryError
    }

    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int {
        throw queryError
    }

    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double {
        throw queryError
    }

    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int {
        throw queryError
    }

    func fetchDailySummaries(
        days: Int,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] {
        throw queryError
    }

    func saveWorkout(_ session: WorkoutSession) async throws {
        throw queryError
    }
}

@MainActor
private final class SpyHealthKitService: HealthKitServiceProtocol {
    private(set) var authorizationCalls = 0
    private(set) var fetchTodayStepsCalls = 0

    func requestAuthorization() async throws {
        authorizationCalls += 1
    }

    func fetchTodaySteps() async throws -> Int {
        fetchTodayStepsCalls += 1
        return 0
    }

    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int { 0 }
    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int { 0 }
    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double { 0 }
    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int { 0 }
    func fetchDailySummaries(
        days: Int,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] { [] }
    func saveWorkout(_ session: WorkoutSession) async throws {}
}

@MainActor
private func makeDemoStore(useFakeData: Bool = false) -> (DemoModeStore, UserDefaults, () -> Void) {
    let suiteName = "HealthKitServiceFallbackTests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.removePersistentDomain(forName: suiteName)
    let store = DemoModeStore(userDefaults: defaults)
    store.useFakeData = useFakeData
    return (store, defaults, { defaults.removePersistentDomain(forName: suiteName) })
}
