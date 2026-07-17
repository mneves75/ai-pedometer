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

    @Test("Throws when HealthKit is unavailable and fake data is disabled")
    func throwsWhenUnavailableWithoutFakeData() async throws {
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

        await #expect(throws: HealthKitError.self) {
            try await service.requestAuthorization()
        }

        await #expect(throws: HealthKitError.self) {
            _ = try await service.fetchTodaySteps()
        }

        await #expect(throws: HealthKitError.self) {
            _ = try await service.fetchDailySummaries(
                days: 7,
                activityMode: .steps,
                distanceMode: .automatic,
                manualStepLength: AppConstants.Defaults.manualStepLengthMeters,
                dailyGoal: 10_000
            )
        }
    }

    @Test("No data still returns empty summaries")
    func noDataStillReturnsEmptySummaries() async throws {
        let (store, defaults, cleanup) = makeDemoStore(useFakeData: false)
        defer { cleanup() }

        let failing = FailingHealthKitService(
            authorizationError: nil,
            queryError: HealthKitError.noData
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

    @Test("Query failures propagate without fake data")
    func queryFailuresPropagateWithoutFakeData() async throws {
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

        await #expect(throws: HealthKitError.self) {
            _ = try await service.fetchTodaySteps()
        }
    }

    @Test("fetchLatestHeartRateSample forwards to primary instead of falling back to nil")
    func fetchLatestHeartRateForwardsToPrimary() async throws {
        let (store, defaults, cleanup) = makeDemoStore(useFakeData: false)
        defer { cleanup() }

        let primary = MutableHealthKitService()
        primary.heartRateToReturn = 88
        let service = HealthKitServiceFallback(
            primary: primary,
            demoModeStore: store,
            calendar: Calendar(identifier: .gregorian),
            isHealthDataAvailable: { true },
            userDefaults: defaults
        )

        try await service.requestAuthorization()
        let sample = try await service.fetchLatestHeartRateSample(from: Date.now.addingTimeInterval(-3600), to: .now)
        #expect(sample?.bpm == 88)
    }

    @Test("fetchLatestHeartRateSample uses demo data when fake-data mode is on")
    func fetchLatestHeartRateUsesFakeDataWhenEnabled() async throws {
        let (store, defaults, cleanup) = makeDemoStore(useFakeData: true)
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
        let sample = try await service.fetchLatestHeartRateSample(from: Date.now.addingTimeInterval(-3600), to: .now)
        #expect(sample != nil)
    }

    @Test("fetchLatestHeartRateSample returns nil when sync is disabled")
    func fetchLatestHeartRateRespectsSyncDisabled() async throws {
        let suiteName = "HealthKitServiceFallbackTests-sync-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)

        let store = DemoModeStore(userDefaults: defaults)
        let primary = MutableHealthKitService()
        primary.heartRateToReturn = 99
        let service = HealthKitServiceFallback(
            primary: primary,
            demoModeStore: store,
            calendar: Calendar(identifier: .gregorian),
            isHealthDataAvailable: { true },
            userDefaults: defaults
        )

        let sample = try await service.fetchLatestHeartRateSample(from: Date.now.addingTimeInterval(-3600), to: .now)
        #expect(sample == nil)
    }

    @Test("Authorization denial does not permanently latch empty reads after recovery")
    func authorizationDenialCanRecoverWithoutRelaunch() async throws {
        let (store, defaults, cleanup) = makeDemoStore(useFakeData: false)
        defer { cleanup() }

        let primary = MutableHealthKitService()
        primary.authorizationError = HealthKitError.authorizationFailed
        let service = HealthKitServiceFallback(
            primary: primary,
            demoModeStore: store,
            calendar: Calendar(identifier: .gregorian),
            isHealthDataAvailable: { true },
            userDefaults: defaults
        )

        await #expect(throws: HealthKitError.self) {
            try await service.requestAuthorization()
        }

        await #expect(throws: HealthKitError.self) {
            _ = try await service.fetchTodaySteps()
        }

        primary.authorizationError = nil
        primary.stepsToReturn = 4321

        try await service.requestAuthorization()
        let recoveredSteps = try await service.fetchTodaySteps()
        #expect(recoveredSteps == 4321)
    }

    @Test("Workout save is deferred while HealthKit sync is disabled")
    func workoutSaveIsDeferredWhenSyncIsDisabled() async throws {
        let suiteName = "HealthKitServiceFallbackTests-workout-sync-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
        let store = DemoModeStore(userDefaults: defaults)
        let service = HealthKitServiceFallback(
            primary: MutableHealthKitService(),
            demoModeStore: store,
            calendar: Calendar(identifier: .gregorian),
            isHealthDataAvailable: { true },
            userDefaults: defaults
        )

        let outcome = try await service.saveWorkout(
            WorkoutSession(type: .outdoorWalk, startTime: .now, endTime: .now)
        )

        #expect(outcome == .deferred)
    }

    @Test("Demo workout save is explicitly not required")
    func demoWorkoutSaveIsNotRequired() async throws {
        let (store, defaults, cleanup) = makeDemoStore(useFakeData: true)
        defer { cleanup() }
        let service = HealthKitServiceFallback(
            primary: MutableHealthKitService(),
            demoModeStore: store,
            calendar: Calendar(identifier: .gregorian),
            isHealthDataAvailable: { true },
            userDefaults: defaults
        )

        let outcome = try await service.saveWorkout(
            WorkoutSession(type: .outdoorWalk, startTime: .now, endTime: .now)
        )

        #expect(outcome == .notRequired)
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

    func fetchLatestHeartRateSample(from startDate: Date, to endDate: Date) async throws -> HeartRateSample? {
        throw queryError
    }

    func fetchWheelchairDistance(from startDate: Date, to endDate: Date) async throws -> Double {
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

    func fetchDailySummaries(
        from startDate: Date,
        to endDate: Date,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] {
        throw queryError
    }

    func saveWorkout(_ session: WorkoutSession) async throws -> HealthKitWorkoutSaveOutcome {
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
    func fetchWheelchairDistance(from startDate: Date, to endDate: Date) async throws -> Double { 0 }
    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int { 0 }
    func fetchLatestHeartRateSample(from startDate: Date, to endDate: Date) async throws -> HeartRateSample? { nil }
    func fetchDailySummaries(
        days: Int,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] { [] }
    func fetchDailySummaries(
        from startDate: Date,
        to endDate: Date,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] { [] }
    func saveWorkout(_ session: WorkoutSession) async throws -> HealthKitWorkoutSaveOutcome { .notRequired }
}

@MainActor
private final class MutableHealthKitService: HealthKitServiceProtocol {
    var authorizationError: (any Error)?
    var stepsToReturn = 0
    var heartRateToReturn: Double?
    var dailySummariesToReturn: [DailyStepSummary] = []

    func requestAuthorization() async throws {
        if let authorizationError {
            throw authorizationError
        }
    }

    func fetchTodaySteps() async throws -> Int { stepsToReturn }
    func fetchSteps(from startDate: Date, to endDate: Date) async throws -> Int { stepsToReturn }
    func fetchWheelchairPushes(from startDate: Date, to endDate: Date) async throws -> Int { 0 }
    func fetchDistance(from startDate: Date, to endDate: Date) async throws -> Double { 0 }
    func fetchWheelchairDistance(from startDate: Date, to endDate: Date) async throws -> Double { 0 }
    func fetchFloors(from startDate: Date, to endDate: Date) async throws -> Int { 0 }
    func fetchLatestHeartRateSample(from startDate: Date, to endDate: Date) async throws -> HeartRateSample? {
        guard let bpm = heartRateToReturn else { return nil }
        return HeartRateSample(bpm: bpm, endDate: .now)
    }
    func fetchDailySummaries(days: Int, activityMode: ActivityTrackingMode, distanceMode: DistanceEstimationMode, manualStepLength: Double, dailyGoal: Int) async throws -> [DailyStepSummary] { dailySummariesToReturn }
    func fetchDailySummaries(from startDate: Date, to endDate: Date, activityMode: ActivityTrackingMode, distanceMode: DistanceEstimationMode, manualStepLength: Double, dailyGoal: Int) async throws -> [DailyStepSummary] { dailySummariesToReturn }
    func saveWorkout(_ session: WorkoutSession) async throws -> HealthKitWorkoutSaveOutcome { .notRequired }
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
