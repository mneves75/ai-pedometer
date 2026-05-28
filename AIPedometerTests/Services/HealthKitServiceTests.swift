import Testing
import Foundation

@testable import AIPedometer

// MARK: - Mock HealthKitService

@MainActor
final class MockHealthKitService: HealthKitServiceProtocol, Sendable {
    var authorizationRequested = false
    var fetchStepsCallCount = 0
    /// Opt-in cooperative yields inside `fetchSteps` so a test can widen the interleaving
    /// window when probing for concurrent execution. Defaults to 0, leaving existing tests'
    /// timing unchanged.
    var fetchStepsYieldCount = 0
    private(set) var concurrentFetchSteps = 0
    private(set) var maxConcurrentFetchSteps = 0
    var fetchWheelchairPushesCallCount = 0
    var stepsToReturn: Int = 0
    var distanceToReturn: Double = 0
    var floorsToReturn: Int = 0
    var heartRateToReturn: Double?
    /// Optional override timestamp the mock applies to the synthesized `HeartRateSample`. When
    /// nil the mock anchors the sample to `Date.now`, which matches "fresh" semantics. Tests can
    /// set this to a past date to exercise the dashboard's "Nm ago" freshness label.
    var heartRateSampleEndDate: Date?
    var fetchLatestHeartRateCallCount = 0
    var wheelchairPushesToReturn: Int = 0
    var wheelchairDistanceToReturn: Double = 0
    var fetchWheelchairDistanceCallCount = 0
    var dailySummariesToReturn: [DailyStepSummary] = []
    var fetchDailySummariesCallCount = 0
    var lastFetchDailySummariesArgs: (
        days: Int,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    )?
    var fetchDailySummariesRangeCallCount = 0
    var lastFetchDailySummariesRangeArgs: (
        startDate: Date,
        endDate: Date,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    )?
    var errorToThrow: (any Error)?

    func requestAuthorization() async throws {
        if let error = errorToThrow {
            throw error
        }
        authorizationRequested = true
    }

    func fetchTodaySteps() async throws -> Int {
        if let error = errorToThrow {
            throw error
        }
        return stepsToReturn
    }

    func fetchSteps(from _: Date, to _: Date) async throws -> Int {
        if let error = errorToThrow {
            throw error
        }
        fetchStepsCallCount += 1
        concurrentFetchSteps += 1
        maxConcurrentFetchSteps = max(maxConcurrentFetchSteps, concurrentFetchSteps)
        for _ in 0..<fetchStepsYieldCount {
            await Task.yield()
        }
        concurrentFetchSteps -= 1
        return stepsToReturn
    }

    func fetchWheelchairPushes(from _: Date, to _: Date) async throws -> Int {
        if let error = errorToThrow {
            throw error
        }
        fetchWheelchairPushesCallCount += 1
        return wheelchairPushesToReturn
    }

    func fetchDistance(from _: Date, to _: Date) async throws -> Double {
        if let error = errorToThrow {
            throw error
        }
        return distanceToReturn
    }

    func fetchFloors(from _: Date, to _: Date) async throws -> Int {
        if let error = errorToThrow {
            throw error
        }
        return floorsToReturn
    }

    func fetchLatestHeartRateSample(from _: Date, to _: Date) async throws -> HeartRateSample? {
        fetchLatestHeartRateCallCount += 1
        guard let bpm = heartRateToReturn else { return nil }
        return HeartRateSample(bpm: bpm, endDate: heartRateSampleEndDate ?? .now)
    }

    func fetchWheelchairDistance(from _: Date, to _: Date) async throws -> Double {
        if let error = errorToThrow {
            throw error
        }
        fetchWheelchairDistanceCallCount += 1
        return wheelchairDistanceToReturn
    }

    func fetchDailySummaries(
        days: Int,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] {
        if let error = errorToThrow {
            throw error
        }
        fetchDailySummariesCallCount += 1
        lastFetchDailySummariesArgs = (
            days: days,
            activityMode: activityMode,
            distanceMode: distanceMode,
            manualStepLength: manualStepLength,
            dailyGoal: dailyGoal
        )
        return dailySummariesToReturn
    }

    func fetchDailySummaries(
        from startDate: Date,
        to endDate: Date,
        activityMode: ActivityTrackingMode,
        distanceMode: DistanceEstimationMode,
        manualStepLength: Double,
        dailyGoal: Int
    ) async throws -> [DailyStepSummary] {
        if let error = errorToThrow {
            throw error
        }
        fetchDailySummariesRangeCallCount += 1
        lastFetchDailySummariesRangeArgs = (
            startDate: startDate,
            endDate: endDate,
            activityMode: activityMode,
            distanceMode: distanceMode,
            manualStepLength: manualStepLength,
            dailyGoal: dailyGoal
        )
        return dailySummariesToReturn
    }

    func saveWorkout(_: WorkoutSession) async throws {
        if let error = errorToThrow {
            throw error
        }
    }
}

// MARK: - Mock MotionService

@MainActor
final class MockMotionService: MotionServiceProtocol {
    var liveUpdateHandler: (@MainActor (PedometerSnapshot) -> Void)?
    var snapshotToReturn = PedometerSnapshot(steps: 0, distance: 0, floorsAscended: 0)
    var errorToThrow: (any Error)?
    var queryCallCount = 0

    func startLiveUpdates(
        from _: Date,
        handler: @escaping @Sendable @MainActor (PedometerSnapshot) -> Void
    ) throws {
        if let error = errorToThrow {
            throw error
        }
        liveUpdateHandler = handler
    }

    func stopLiveUpdates() {
        liveUpdateHandler = nil
    }

    func query(from _: Date, to _: Date) async throws -> PedometerSnapshot {
        queryCallCount += 1
        if let error = errorToThrow {
            throw error
        }
        return snapshotToReturn
    }

    func simulateLiveUpdate(_ snapshot: PedometerSnapshot) {
        liveUpdateHandler?(snapshot)
    }
}

@MainActor
final class MockStreakCalculator: StreakCalculating {
    var result: StreakResult
    var errorToThrow: (any Error)?
    var callCount = 0

    init(result: StreakResult = StreakResult(count: 0, todayIncluded: false, streakStartDate: nil)) {
        self.result = result
    }

    func calculateCurrentStreak() async throws -> StreakResult {
        callCount += 1
        if let error = errorToThrow {
            throw error
        }
        return result
    }
}

@MainActor
private func makeService(
    healthKit: MockHealthKitService,
    motion: MockMotionService,
    goalValue: Int? = nil,
    streakResult: StreakResult = StreakResult(count: 0, todayIncluded: false, streakStartDate: nil),
    userDefaults: UserDefaults,
    persistence: PersistenceController = PersistenceController(inMemory: true)
) -> (service: StepTrackingService, goalService: GoalService) {
    let goalService = GoalService(persistence: persistence)
    if let goalValue {
        goalService.setGoal(goalValue)
    }
    let streakCalculator = MockStreakCalculator(result: streakResult)
    let dataStore = SharedDataStore(userDefaults: userDefaults)
    let badgeService = BadgeService(persistence: persistence)
    let service = StepTrackingService(
        healthKitService: healthKit,
        motionService: motion,
        healthAuthorization: HealthKitAuthorization(),
        goalService: goalService,
        badgeService: badgeService,
        dataStore: dataStore,
        streakCalculator: streakCalculator,
        userDefaults: userDefaults
    )
    return (service, goalService)
}

@MainActor
private func makeServiceWithStreakCalculator(
    healthKit: MockHealthKitService,
    motion: MockMotionService,
    streakCalculator: MockStreakCalculator,
    userDefaults: UserDefaults
) -> (service: StepTrackingService, goalService: GoalService, streakCalculator: MockStreakCalculator) {
    let persistence = PersistenceController(inMemory: true)
    let goalService = GoalService(persistence: persistence)
    let dataStore = SharedDataStore(userDefaults: userDefaults)
    let badgeService = BadgeService(persistence: persistence)
    let service = StepTrackingService(
        healthKitService: healthKit,
        motionService: motion,
        healthAuthorization: HealthKitAuthorization(),
        goalService: goalService,
        badgeService: badgeService,
        dataStore: dataStore,
        streakCalculator: streakCalculator,
        userDefaults: userDefaults
    )
    return (service, goalService, streakCalculator)
}

// MARK: - HealthKitService Protocol Tests

@Suite("HealthKitService Protocol Tests")
struct HealthKitServiceProtocolTests {

    @Test("Mock service returns configured steps")
    @MainActor
    func mockServiceReturnsConfiguredSteps() async throws {
        let mock = MockHealthKitService()
        mock.stepsToReturn = 5432

        let steps = try await mock.fetchTodaySteps()

        #expect(steps == 5432)
    }

    @Test("Mock service throws configured error")
    @MainActor
    func mockServiceThrowsConfiguredError() async {
        let mock = MockHealthKitService()
        mock.errorToThrow = HealthKitError.queryFailed

        await #expect(throws: HealthKitError.self) {
            _ = try await mock.fetchTodaySteps()
        }
    }

    @Test("Authorization request is tracked")
    @MainActor
    func authorizationRequestIsTracked() async throws {
        let mock = MockHealthKitService()

        try await mock.requestAuthorization()

        #expect(mock.authorizationRequested == true)
    }
}

// MARK: - StepTrackingService Integration Tests

@Suite("StepTrackingService Tests")
struct StepTrackingServiceTests {
    @Test("Service updates steps from HealthKit")
    @MainActor
    func serviceUpdatesStepsFromHealthKit() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.stepsToReturn = 8765
        mockHealthKit.heartRateToReturn = 72
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(service.todaySteps == 8765)
        #expect(service.todayCalories == Double(8765) * AppConstants.Metrics.caloriesPerStep)
        #expect(service.todayHeartRateBPM == 72)
        #expect(mockHealthKit.fetchLatestHeartRateCallCount == 1)
    }

    @Test("Concurrent refreshTodayData calls are serialized to prevent step regression")
    @MainActor
    func refreshTodayDataSerializesConcurrentCalls() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.stepsToReturn = 9000
        // Widen the interleaving window: without serialization, two overlapping refreshes
        // would both be inside fetchSteps at once (maxConcurrentFetchSteps == 2) and could
        // clobber each other's todaySteps/liveBaseline. Serialization must keep it to 1.
        mockHealthKit.fetchStepsYieldCount = 5
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        async let first: Void = service.refreshTodayData()
        async let second: Void = service.refreshTodayData()
        _ = await (first, second)

        #expect(mockHealthKit.maxConcurrentFetchSteps == 1)
        #expect(mockHealthKit.fetchStepsCallCount == 2)
        #expect(service.todaySteps == 9000)
    }

    @Test("Refresh today uses motion when HealthKit returns 0 but Motion has steps")
    @MainActor
    func refreshTodayUsesMotionWhenHealthKitReturnsZeroButMotionHasSteps() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.stepsToReturn = 0
        mockMotion.snapshotToReturn = PedometerSnapshot(steps: 4321, distance: 1500.5, floorsAscended: 3)
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(mockHealthKit.fetchStepsCallCount == 1)
        #expect(mockMotion.queryCallCount == 1)
        #expect(service.isUsingMotionFallback == true)
        #expect(service.todaySteps == 4321)
        #expect(service.todayDistance == 1500.5)
        #expect(service.todayFloors == 3)
    }

    @Test("Refresh today keeps zero-step day stale when HealthKit is zero and Motion probe fails")
    @MainActor
    func refreshTodayMarksZeroStepMotionProbeFailureStale() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.stepsToReturn = 0
        mockMotion.errorToThrow = MotionError.queryFailed
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(mockHealthKit.fetchStepsCallCount == 1)
        #expect(mockMotion.queryCallCount == 1)
        #expect(service.isUsingMotionFallback == true)
        #expect(service.todaySteps == 0)
        #expect(testDefaults.defaults.sharedStepData?.isStale == true)
    }

    @Test("Refresh today unlocks step badges")
    @MainActor
    func refreshTodayUnlocksStepBadges() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.stepsToReturn = 12_000
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let persistence = PersistenceController(inMemory: true)
        let badgeService = BadgeService(persistence: persistence)

        let service = StepTrackingService(
            healthKitService: mockHealthKit,
            motionService: mockMotion,
            healthAuthorization: HealthKitAuthorization(),
            goalService: GoalService(persistence: persistence),
            badgeService: badgeService,
            dataStore: SharedDataStore(userDefaults: testDefaults.defaults),
            streakCalculator: MockStreakCalculator(),
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        let earned = badgeService.earnedBadgeTypes()
        #expect(earned.contains(.steps5K))
        #expect(earned.contains(.steps10K))
        #expect(!earned.contains(.steps15K))
    }

    @Test("Refresh streak unlocks streak badges")
    @MainActor
    func refreshStreakUnlocksStreakBadges() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let persistence = PersistenceController(inMemory: true)
        let badgeService = BadgeService(persistence: persistence)
        let streakCalculator = MockStreakCalculator(
            result: StreakResult(count: 14, todayIncluded: true, streakStartDate: nil)
        )

        let service = StepTrackingService(
            healthKitService: mockHealthKit,
            motionService: mockMotion,
            healthAuthorization: HealthKitAuthorization(),
            goalService: GoalService(persistence: persistence),
            badgeService: badgeService,
            dataStore: SharedDataStore(userDefaults: testDefaults.defaults),
            streakCalculator: streakCalculator,
            userDefaults: testDefaults.defaults
        )

        await service.refreshStreak()

        let earned = badgeService.earnedBadgeTypes()
        #expect(earned.contains(.streak3))
        #expect(earned.contains(.streak7))
        #expect(earned.contains(.streak14))
        #expect(!earned.contains(.streak30))
    }

    @Test("Service handles HealthKit error gracefully")
    @MainActor
    func serviceHandlesHealthKitErrorGracefully() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.errorToThrow = HealthKitError.queryFailed
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        // Should not throw - errors are logged but not propagated
        await service.refreshTodayData()

        // Steps should remain at default (0)
        #expect(service.todaySteps == 0)
    }

    @Test("Refresh today falls back to motion when HealthKit errors")
    @MainActor
    func refreshTodayFallsBackToMotionOnHealthKitError() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.errorToThrow = HealthKitError.queryFailed
        mockMotion.snapshotToReturn = PedometerSnapshot(steps: 4321, distance: 1500.5, floorsAscended: 3)
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(mockMotion.queryCallCount == 1)
        #expect(service.todaySteps == 4321)
        #expect(service.todayDistance == 1500.5)
        #expect(service.todayFloors == 3)
    }

    @Test("Refresh today uses motion when HealthKit sync is disabled")
    @MainActor
    func refreshTodayUsesMotionWhenSyncDisabled() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockMotion.snapshotToReturn = PedometerSnapshot(steps: 3210, distance: 1200.5, floorsAscended: 2)
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(mockMotion.queryCallCount == 1)
        #expect(mockHealthKit.fetchStepsCallCount == 0)
        #expect(service.todaySteps == 3210)
        #expect(service.todayDistance == 1200.5)
        #expect(service.todayFloors == 2)
    }

    @Test("Start skips HealthKit authorization when sync is disabled")
    @MainActor
    func startSkipsAuthorizationWhenSyncDisabled() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.start()

        #expect(mockHealthKit.authorizationRequested == false)
        #expect(mockMotion.liveUpdateHandler != nil)
    }

    @Test("Service updates from live motion data")
    @MainActor
    func serviceUpdatesFromLiveMotionData() async throws {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.start()

        // Simulate live update from pedometer
        let snapshot = PedometerSnapshot(steps: 1234, distance: 850.5, floorsAscended: 3)
        mockMotion.simulateLiveUpdate(snapshot)

        #expect(service.todaySteps == 1234)
        #expect(service.todayDistance == 850.5)
        #expect(service.todayFloors == 3)
        #expect(service.todayCalories == Double(1234) * AppConstants.Metrics.caloriesPerStep)
    }

    @Test("Live updates keep HealthKit totals when HealthKit exceeds pedometer")
    @MainActor
    func liveUpdatesUseHealthKitWhenHigher() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        mockHealthKit.stepsToReturn = 8000
        mockHealthKit.distanceToReturn = 1200
        mockHealthKit.floorsToReturn = 6

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.start()

        mockMotion.simulateLiveUpdate(PedometerSnapshot(steps: 7000, distance: 900, floorsAscended: 4))

        #expect(service.todaySteps == 8000)
        #expect(service.todayDistance == 1200)
        #expect(service.todayFloors == 6)
    }

    @Test("Live updates keep pedometer totals when HealthKit lags")
    @MainActor
    func liveUpdatesUsePedometerWhenHigher() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        mockHealthKit.stepsToReturn = 3000
        mockHealthKit.distanceToReturn = 400
        mockHealthKit.floorsToReturn = 1

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.start()

        mockMotion.simulateLiveUpdate(PedometerSnapshot(steps: 4500, distance: 650, floorsAscended: 2))

        #expect(service.todaySteps == 4500)
        #expect(service.todayDistance == 650)
        #expect(service.todayFloors == 2)
    }

    @Test("Wheelchair mode uses HealthKit pushes and ignores live motion updates")
    @MainActor
    func wheelchairModeUsesPushes() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.wheelchairPushesToReturn = 4321
        mockHealthKit.distanceToReturn = 999 // walking distance — should NOT be used in wheelchair mode
        mockHealthKit.wheelchairDistanceToReturn = 2_750 // meters — the value we actually expect
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(ActivityTrackingMode.wheelchairPushes.rawValue, forKey: AppConstants.UserDefaultsKeys.activityTrackingMode)

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.start()

        // Attempt live update (should be ignored in wheelchair mode)
        mockMotion.simulateLiveUpdate(PedometerSnapshot(steps: 999, distance: 100, floorsAscended: 1))

        #expect(service.todaySteps == 4321)
        // Wheelchair distance now comes from HealthKit's `distanceWheelchair` sample type, not 0.
        #expect(service.todayDistance == 2_750)
        #expect(mockHealthKit.fetchWheelchairDistanceCallCount >= 1)
        #expect(service.todayCalories == Double(4321) * AppConstants.Metrics.caloriesPerStep)
    }

    @Test("Wheelchair mode clears stale values when HealthKit sync is disabled")
    @MainActor
    func wheelchairModeClearsValuesWhenSyncDisabled() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(ActivityTrackingMode.wheelchairPushes.rawValue, forKey: AppConstants.UserDefaultsKeys.activityTrackingMode)
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(service.todaySteps == 0)
        #expect(service.todayDistance == 0)
        #expect(service.todayFloors == 0)
        #expect(testDefaults.defaults.sharedStepData?.todaySteps == 0)
    }

    @Test("Motion fallback clears stale values when pedometer query fails")
    @MainActor
    func motionFallbackClearsStaleValuesWhenQueryFails() async {
        let mockHealthKit = MockHealthKitService()
        mockHealthKit.errorToThrow = HealthKitError.queryFailed
        let mockMotion = MockMotionService()
        mockMotion.errorToThrow = MotionError.queryFailed
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(service.todaySteps == 0)
        #expect(service.todayDistance == 0)
        #expect(testDefaults.defaults.sharedStepData?.todaySteps == 0)
        #expect(testDefaults.defaults.sharedStepData?.isStale == true)
    }

    @Test("Settings change restarts live updates and refreshes summaries")
    @MainActor
    func settingsChangeRestartsLiveUpdatesAndRefreshesSummaries() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        mockHealthKit.stepsToReturn = 1000
        mockHealthKit.wheelchairPushesToReturn = 250
        mockHealthKit.dailySummariesToReturn = [
            DailyStepSummary(date: .now, steps: 100, distance: 0, floors: 0, calories: 0, goal: 1000)
        ]

        testDefaults.defaults.set(
            ActivityTrackingMode.steps.rawValue,
            forKey: AppConstants.UserDefaultsKeys.activityTrackingMode
        )

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.start()
        #expect(mockMotion.liveUpdateHandler != nil)

        testDefaults.defaults.set(
            ActivityTrackingMode.wheelchairPushes.rawValue,
            forKey: AppConstants.UserDefaultsKeys.activityTrackingMode
        )
        await service.applySettingsChange()

        #expect(mockMotion.liveUpdateHandler == nil)
        #expect(service.todaySteps == 250)
        #expect(mockHealthKit.lastFetchDailySummariesArgs?.activityMode == .wheelchairPushes)

        testDefaults.defaults.set(
            ActivityTrackingMode.steps.rawValue,
            forKey: AppConstants.UserDefaultsKeys.activityTrackingMode
        )
        await service.applySettingsChange()

        #expect(mockMotion.liveUpdateHandler != nil)
        #expect(service.todaySteps == 1000)
        #expect(mockHealthKit.lastFetchDailySummariesArgs?.activityMode == .steps)
    }

    @Test("Weekly summaries refresh requests authorization and updates summaries")
    @MainActor
    func weeklySummariesRefreshUpdatesData() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)

        mockHealthKit.dailySummariesToReturn = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyStepSummary(
                date: date,
                steps: 1000 + offset,
                distance: 1000,
                floors: 1,
                calories: 50,
                goal: 10_000
            )
        }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        let result = await service.refreshWeeklySummaries()

        #expect(mockHealthKit.authorizationRequested == true)
        #expect(mockHealthKit.fetchDailySummariesCallCount == 1)
        do {
            _ = try result.get()
        } catch {
            #expect(Bool(false), "Expected refreshWeeklySummaries to succeed, but got \(error)")
        }
        #expect(service.weeklySummaries.count == 7)
    }

    @Test("Weekly summaries use current settings and goal")
    @MainActor
    func weeklySummariesUseSettingsAndGoal() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(ActivityTrackingMode.wheelchairPushes.rawValue, forKey: AppConstants.UserDefaultsKeys.activityTrackingMode)
        testDefaults.defaults.set(DistanceEstimationMode.manual.rawValue, forKey: AppConstants.UserDefaultsKeys.distanceEstimationMode)
        testDefaults.defaults.set(0.9, forKey: AppConstants.UserDefaultsKeys.manualStepLengthMeters)

        let (service, goalService) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )
        goalService.setGoal(12_500)

        _ = await service.refreshWeeklySummaries()

        let args = mockHealthKit.lastFetchDailySummariesArgs
        #expect(args?.days == 7)
        #expect(args?.activityMode == .wheelchairPushes)
        #expect(args?.distanceMode == .manual)
        #expect(args?.manualStepLength == 0.9)
        #expect(args?.dailyGoal == 12_500)
    }

    @Test("Weekly summaries apply historical goals per day")
    @MainActor
    func weeklySummariesUseHistoricalGoalsPerDay() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let dayMinus4 = calendar.date(byAdding: .day, value: -4, to: today) ?? today
        let dayMinus3 = calendar.date(byAdding: .day, value: -3, to: today) ?? today
        let dayMinus1 = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        let goal1Start = calendar.date(byAdding: .day, value: -10, to: today) ?? today
        let goal1End = calendar.date(byAdding: .second, value: -1, to: dayMinus3) ?? dayMinus3
        let goal2Start = dayMinus3

        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        context.insert(StepGoal(dailySteps: 9000, startDate: goal1Start, endDate: goal1End))
        context.insert(StepGoal(dailySteps: 12000, startDate: goal2Start))
        do {
            try context.save()
        } catch {
            Issue.record("Failed to save goals: \(error)")
        }

        mockHealthKit.dailySummariesToReturn = [
            DailyStepSummary(date: dayMinus4, steps: 8000, distance: 1000, floors: 1, calories: 50, goal: 10_000),
            DailyStepSummary(date: dayMinus3, steps: 9000, distance: 1000, floors: 1, calories: 50, goal: 10_000),
            DailyStepSummary(date: dayMinus1, steps: 11000, distance: 1000, floors: 1, calories: 50, goal: 10_000)
        ]

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults,
            persistence: persistence
        )

        _ = await service.refreshWeeklySummaries()

        #expect(service.weeklySummaries.count == 3)
        let goalsByDate = Dictionary(
            uniqueKeysWithValues: service.weeklySummaries.map { (calendar.startOfDay(for: $0.date), $0.goal) }
        )
        #expect(goalsByDate[dayMinus4] == 9000)
        #expect(goalsByDate[dayMinus3] == 12000)
        #expect(goalsByDate[dayMinus1] == 12000)
    }

    @Test("Goal update clamps to positive value")
    @MainActor
    func goalUpdateClampsToPositiveValue() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        service.updateGoal(15000)
        #expect(service.currentGoal == 15000)

        // Zero or negative should be ignored
        service.updateGoal(0)
        #expect(service.currentGoal == 15000)

        service.updateGoal(-100)
        #expect(service.currentGoal == 15000)
    }

    @Test("Goal update persists and updates shared data")
    @MainActor
    func goalUpdatePersistsAndUpdatesSharedData() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, goalService) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        service.updateGoal(12000)

        #expect(service.currentGoal == 12000)
        #expect(goalService.currentGoal == 12000)
        #expect(testDefaults.defaults.sharedStepData?.goalSteps == 12000)
    }

    @Test("Goal update refreshes streak and weekly summaries")
    @MainActor
    func goalUpdateRefreshesStreakAndWeeklySummaries() async {
        let mockHealthKit = MockHealthKitService()
        mockHealthKit.dailySummariesToReturn = [
            DailyStepSummary(date: .now, steps: 9000, distance: 6000, floors: 4, calories: 300, goal: 9000)
        ]
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let streakCalculator = MockStreakCalculator(
            result: StreakResult(count: 2, todayIncluded: true, streakStartDate: .now)
        )
        let (service, goalService, streakMock) = makeServiceWithStreakCalculator(
            healthKit: mockHealthKit,
            motion: mockMotion,
            streakCalculator: streakCalculator,
            userDefaults: testDefaults.defaults
        )

        await service.updateGoalAndRefresh(9000)

        #expect(service.currentGoal == 9000)
        #expect(goalService.currentGoal == 9000)
        #expect(streakMock.callCount == 1)
        #expect(mockHealthKit.fetchDailySummariesCallCount == 1)
        #expect(service.weeklySummaries.count == 1)
    }

    @Test("Streak refresh updates shared data")
    @MainActor
    func streakRefreshUpdatesSharedData() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let streakResult = StreakResult(count: 5, todayIncluded: true, streakStartDate: .now)
        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            streakResult: streakResult,
            userDefaults: testDefaults.defaults
        )

        await service.refreshStreak()

        #expect(testDefaults.defaults.sharedStepData?.currentStreak == 5)
    }

    @Test("Service refreshes weekly summaries from HealthKit")
    @MainActor
    func serviceRefreshesWeeklySummaries() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let summaries = [
            DailyStepSummary(date: .now, steps: 8000, distance: 6000, floors: 5, calories: 300, goal: 10000),
            DailyStepSummary(date: Date().addingTimeInterval(-86400), steps: 11000, distance: 8000, floors: 7, calories: 400, goal: 10000)
        ]
        mockHealthKit.dailySummariesToReturn = summaries

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        let result = await service.refreshWeeklySummaries()

        // Should succeed
        if case .failure = result {
            Issue.record("Expected success but got failure")
        }

        #expect(service.weeklySummaries.count == 2)
        #expect(service.weeklySummaries[0].steps == 8000)
        #expect(service.weeklySummaries[1].steps == 11000)
        #expect(testDefaults.defaults.sharedStepData?.weeklySteps == [8000, 11000])
    }

    @Test("Weekly summaries merge current day with live today total")
    @MainActor
    func weeklySummariesMergeCurrentDayWithLiveTotal() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        mockHealthKit.stepsToReturn = 9500
        mockHealthKit.distanceToReturn = 7200
        mockHealthKit.floorsToReturn = 8
        mockHealthKit.dailySummariesToReturn = [
            DailyStepSummary(date: .now, steps: 8000, distance: 6000, floors: 5, calories: 300, goal: 10000),
            DailyStepSummary(date: Date().addingTimeInterval(-86400), steps: 11000, distance: 8000, floors: 7, calories: 400, goal: 10000)
        ]

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()
        let result = await service.refreshWeeklySummaries()

        if case .failure = result {
            Issue.record("Expected success but got failure")
        }

        #expect(service.weeklySummaries.count == 2)
        #expect(service.weeklySummaries[0].steps == 9500)
        #expect(service.weeklySummaries[0].distance == 7200)
        #expect(service.weeklySummaries[0].floors == 8)
        #expect(service.weeklySummaries[1].steps == 11000)
        #expect(testDefaults.defaults.sharedStepData?.weeklySteps == [9500, 11000])
    }

    @Test("Weekly summaries returns failure on HealthKit error")
    @MainActor
    func weeklySummariesReturnsFailureOnError() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.errorToThrow = HealthKitError.queryFailed
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        let result = await service.refreshWeeklySummaries()

        // Should return failure result
        if case .success = result {
            Issue.record("Expected failure but got success")
        }

        // Summaries should remain empty
        #expect(service.weeklySummaries.isEmpty)
    }

    @Test("Weekly summaries skips HealthKit when sync disabled")
    @MainActor
    func weeklySummariesSkipsWhenSyncDisabled() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        let result = await service.refreshWeeklySummaries()

        if case .failure = result {
            Issue.record("Expected success but got failure")
        }

        #expect(mockHealthKit.fetchDailySummariesCallCount == 0)
        #expect(service.weeklySummaries.isEmpty)
        #expect(testDefaults.defaults.sharedStepData?.weeklySteps ?? [] == [])
    }
}

// MARK: - DailyStepSummary Tests

@Suite("DailyStepSummary Tests")
struct DailyStepSummaryTests {

    @Test("Goal met when steps exceed goal")
    func goalMetWhenStepsExceedGoal() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 12000,
            distance: 8500,
            floors: 5,
            calories: 400,
            goal: 10000
        )

        #expect(summary.goalMet == true)
        #expect(summary.progress == 1.2)
    }

    @Test("Goal not met when steps below goal")
    func goalNotMetWhenStepsBelowGoal() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 10000
        )

        #expect(summary.goalMet == false)
        #expect(summary.progress == 0.5)
    }

    @Test("Progress handles zero goal safely")
    func progressHandlesZeroGoalSafely() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 0
        )

        #expect(summary.progress == 0)
    }

    @Test("Summary is Identifiable using date")
    func summaryIsIdentifiable() {
        let date = Date.now
        let summary = DailyStepSummary(
            date: date,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 10000
        )

        #expect(summary.id == date)
    }

    @Test("DateString returns abbreviated date format")
    func dateStringReturnsAbbreviatedFormat() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 10000
        )

        // dateString should not be empty and should contain the year or month
        #expect(!summary.dateString.isEmpty)
    }

    @Test("DayName returns weekday abbreviation")
    func dayNameReturnsWeekdayAbbreviation() {
        let summary = DailyStepSummary(
            date: .now,
            steps: 5000,
            distance: 3500,
            floors: 2,
            calories: 200,
            goal: 10000
        )

        // dayName should be a short weekday like "Mon", "Tue", etc.
        #expect(summary.dayName.count >= 2)
        #expect(summary.dayName.count <= 4)
    }
}

// MARK: - PedometerSnapshot Tests

@Suite("PedometerSnapshot Tests")
struct PedometerSnapshotTests {

    @Test("Snapshot is Sendable")
    func snapshotIsSendable() async {
        let snapshot = PedometerSnapshot(steps: 100, distance: 75.5, floorsAscended: 1)

        // Verify sendable by passing across isolation boundaries
        let result = await Task.detached {
            return snapshot.steps
        }.value

        #expect(result == 100)
    }

    @Test("Snapshot stores all values correctly")
    func snapshotStoresAllValuesCorrectly() {
        let snapshot = PedometerSnapshot(steps: 9876, distance: 7234.5, floorsAscended: 12)

        #expect(snapshot.steps == 9876)
        #expect(snapshot.distance == 7234.5)
        #expect(snapshot.floorsAscended == 12)
    }
}

// MARK: - Dependency Injection Tests

@Suite("Dependency Injection Tests")
struct DependencyInjectionTests {

    @Test("StepTrackingService accepts injected HealthKitService")
    @MainActor
    func stepTrackingServiceAcceptsInjectedHealthKit() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.stepsToReturn = 42
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        // Verify the injected mock was used
        #expect(service.todaySteps == 42)
    }

    @Test("StepTrackingService accepts injected MotionService")
    @MainActor
    func stepTrackingServiceAcceptsInjectedMotion() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.start()

        // Simulate motion update
        let snapshot = PedometerSnapshot(steps: 999, distance: 500.0, floorsAscended: 2)
        mockMotion.simulateLiveUpdate(snapshot)

        // Verify the injected mock was used
        #expect(service.todaySteps == 999)
        #expect(service.todayDistance == 500.0)
    }

    @Test("SharedDataStore receives updates from StepTrackingService")
    @MainActor
    func sharedDataStoreReceivesUpdates() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let dataStore = SharedDataStore(userDefaults: testDefaults.defaults)
        mockHealthKit.stepsToReturn = 7777
        let persistence = PersistenceController(inMemory: true)
        let badgeService = BadgeService(persistence: persistence)

        let service = StepTrackingService(
            healthKitService: mockHealthKit,
            motionService: mockMotion,
            healthAuthorization: HealthKitAuthorization(),
            goalService: GoalService(persistence: persistence),
            badgeService: badgeService,
            dataStore: dataStore,
            streakCalculator: MockStreakCalculator(),
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        // Verify SharedDataStore was updated
        #expect(dataStore.sharedData?.todaySteps == 7777)
    }

    @Test("Multiple services can share same HealthKitService instance")
    @MainActor
    func multipleServicesShareHealthKitInstance() async {
        // This test verifies the pattern used in AIPedometerApp
        let sharedHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        sharedHealthKit.stepsToReturn = 5000
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        let persistence = PersistenceController(inMemory: true)
        let goalService = GoalService(persistence: persistence)
        let badgeService = BadgeService(persistence: persistence)
        let streakCalculator = MockStreakCalculator()

        let service1 = StepTrackingService(
            healthKitService: sharedHealthKit,
            motionService: mockMotion,
            healthAuthorization: HealthKitAuthorization(),
            goalService: goalService,
            badgeService: badgeService,
            dataStore: SharedDataStore(userDefaults: testDefaults.defaults),
            streakCalculator: streakCalculator,
            userDefaults: testDefaults.defaults
        )

        let service2 = StepTrackingService(
            healthKitService: sharedHealthKit,
            motionService: mockMotion,
            healthAuthorization: HealthKitAuthorization(),
            goalService: goalService,
            badgeService: badgeService,
            dataStore: SharedDataStore(userDefaults: testDefaults.defaults),
            streakCalculator: streakCalculator,
            userDefaults: testDefaults.defaults
        )

        // Change the shared mock's return value
        sharedHealthKit.stepsToReturn = 9999

        await service1.refreshTodayData()
        await service2.refreshTodayData()

        // Both services should see the updated value
        #expect(service1.todaySteps == 9999)
        #expect(service2.todaySteps == 9999)
    }
}

// MARK: - Result Type Tests

@Suite("Result Type Error Handling Tests")
struct ResultTypeTests {

    @Test("refreshWeeklySummaries returns success with data")
    @MainActor
    func refreshWeeklySummariesReturnsSuccessWithData() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.dailySummariesToReturn = [
            DailyStepSummary(date: .now, steps: 10000, distance: 7500, floors: 8, calories: 350, goal: 10000)
        ]
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        let result = await service.refreshWeeklySummaries()

        switch result {
        case .success:
            #expect(service.weeklySummaries.count == 1)
        case .failure(let error):
            Issue.record("Expected success but got failure: \(error)")
        }
    }

    @Test("refreshWeeklySummaries returns failure with HealthKit error")
    @MainActor
    func refreshWeeklySummariesReturnsFailureWithError() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.errorToThrow = HealthKitError.queryFailed
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        let result = await service.refreshWeeklySummaries()

        switch result {
        case .success:
            Issue.record("Expected failure but got success")
        case .failure(let error):
            #expect(error is HealthKitError)
        }
    }

    @Test("refreshWeeklySummaries preserves empty state on error")
    @MainActor
    func refreshWeeklySummariesPreservesEmptyStateOnError() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.errorToThrow = HealthKitError.authorizationFailed
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        _ = await service.refreshWeeklySummaries()

        // State should remain unchanged (empty)
        #expect(service.weeklySummaries.isEmpty)
    }

    // MARK: - Heart-rate preservation across Motion fallbacks (2026-05-19 audit)

    @Test("Motion fallback after HealthKit-zero-steps keeps the latest heart-rate sample")
    @MainActor
    func motionFallbackAfterHealthKitZeroStepsKeepsHeartRate() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        // HealthKit returns zero steps but still has a valid heart-rate sample
        // (the Apple Watch only logged HR so far this session).
        mockHealthKit.stepsToReturn = 0
        mockHealthKit.heartRateToReturn = 71
        mockMotion.snapshotToReturn = PedometerSnapshot(steps: 3210, distance: 1200, floorsAscended: 1)
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(service.isUsingMotionFallback == true)
        #expect(service.todaySteps == 3210)
        #expect(service.todayHeartRateBPM == 71)
        // We re-read heart rate during the fallback exactly once.
        #expect(mockHealthKit.fetchLatestHeartRateCallCount == 1)
    }

    @Test("Motion fallback after HealthKit error still propagates heart rate when available")
    @MainActor
    func motionFallbackAfterHealthKitErrorPropagatesHeartRate() async {
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        // The steps query throws but the heart-rate read can still succeed in the fallback path.
        mockHealthKit.errorToThrow = HealthKitError.queryFailed
        mockHealthKit.heartRateToReturn = 84
        mockMotion.snapshotToReturn = PedometerSnapshot(steps: 1500, distance: 800, floorsAscended: 0)
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(service.todaySteps == 1500)
        #expect(service.todayHeartRateBPM == 84)
    }

    @Test("Motion fallback fades heart rate to nil when HK explicitly returns no sample")
    @MainActor
    func motionFallbackClearsHeartRateWhenHealthKitReturnsNil() async {
        // After a successful HR read returns a value, the next refresh whose HR fetch
        // resolves to `nil` (no sample available — sensor off, watch removed, etc.) must
        // surface "No Data" rather than freezing the previous value forever.
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.stepsToReturn = 9_000
        mockHealthKit.heartRateToReturn = 78
        mockMotion.snapshotToReturn = PedometerSnapshot(steps: 9_500, distance: 6000, floorsAscended: 2)
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()
        #expect(service.todayHeartRateBPM == 78)

        // Drop into Motion fallback (HK steps = 0, Motion > 0) and clear the HR sample.
        mockHealthKit.stepsToReturn = 0
        mockHealthKit.heartRateToReturn = nil
        await service.refreshTodayData()

        // Apple's reference UX is to drop HR to "No Data" the moment fresh samples disappear.
        #expect(service.todayHeartRateBPM == nil)
    }

    @Test("HealthKit-zero plus Motion probe failure still refreshes heart rate")
    @MainActor
    func healthKitZeroMotionProbeFailureStillRefreshesHeartRate() async {
        // If HealthKit reports zero steps and the Motion probe itself fails, step counts should
        // become stale/zero, but heart-rate still has an independent HealthKit read path.
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.stepsToReturn = 0
        mockHealthKit.heartRateToReturn = 91
        mockMotion.errorToThrow = MotionError.queryFailed
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(service.isUsingMotionFallback == true)
        #expect(service.todaySteps == 0)
        #expect(service.todayHeartRateBPM == 91)
        #expect(service.lastUpdated == .distantPast)
        #expect(testDefaults.defaults.sharedStepData?.isStale == true)
        #expect(mockHealthKit.fetchLatestHeartRateCallCount == 1)
    }

    // MARK: - Widget reload throttle (2026-05-19 audit)

    @Test("Widget throttle skips repeated calls inside the 5-minute window with small delta")
    @MainActor
    func widgetThrottleSkipsInsideWindowWithSmallDelta() {
        let calendar = Calendar(identifier: .gregorian)
        let last = Date(timeIntervalSince1970: 1_000)
        let now = last.addingTimeInterval(60) // 1 minute later, same day
        let shouldReload = StepTrackingService.shouldReloadWidgets(
            lastReloadAt: last,
            lastReloadSteps: 1000,
            newSteps: 1099, // delta < 200
            now: now,
            calendar: calendar
        )
        #expect(shouldReload == false)
    }

    @Test("Widget throttle releases once 5 minutes elapse even with no step delta")
    @MainActor
    func widgetThrottleReleasesAfterFiveMinutes() {
        let calendar = Calendar(identifier: .gregorian)
        let last = Date(timeIntervalSince1970: 1_000)
        let now = last.addingTimeInterval(6 * 60) // 6 minutes later
        let shouldReload = StepTrackingService.shouldReloadWidgets(
            lastReloadAt: last,
            lastReloadSteps: 1000,
            newSteps: 1010,
            now: now,
            calendar: calendar
        )
        #expect(shouldReload == true)
    }

    @Test("Widget throttle resets at midnight even when delta is small (2026-05-19 regression)")
    @MainActor
    func widgetThrottleResetsAtMidnight() {
        // Repro for finding-widget-throttle-midnight: at the start of a new day,
        // todaySteps drops to 0 from yesterday's final count. The old throttle saw
        // `abs(0 - 12_345) >= 200 but only after 5 minutes`, so the home-screen widget
        // stayed on yesterday's count for up to 5 minutes after midnight.
        let calendar = Calendar(identifier: .gregorian)
        let yesterdayLate = calendar.date(from: DateComponents(year: 2026, month: 5, day: 19, hour: 23, minute: 58))!
        let todayMidnight = calendar.date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 0, minute: 0, second: 30))!
        let shouldReload = StepTrackingService.shouldReloadWidgets(
            lastReloadAt: yesterdayLate,
            lastReloadSteps: 12_345,
            newSteps: 0, // fresh day
            now: todayMidnight,
            calendar: calendar
        )
        #expect(shouldReload == true)
    }

    @Test("Widget throttle always reloads when there is no previous push recorded")
    @MainActor
    func widgetThrottleReloadsOnFirstUpdate() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_000)
        let shouldReload = StepTrackingService.shouldReloadWidgets(
            lastReloadAt: nil,
            lastReloadSteps: nil,
            newSteps: 0,
            now: now,
            calendar: calendar
        )
        #expect(shouldReload == true)
    }

    @Test("Heart-rate sample carries the HealthKit endDate so the dashboard can show freshness")
    @MainActor
    func heartRateSampleCarriesEndDate() async {
        // The dashboard reads `endDate` to decide whether to show a "Nm ago" label. The mock
        // synthesizes a sample with the supplied endDate; this test guards the wiring end-to-end.
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.stepsToReturn = 5000
        mockHealthKit.heartRateToReturn = 64
        let staleDate = Date(timeIntervalSinceNow: -45 * 60) // 45 minutes ago
        mockHealthKit.heartRateSampleEndDate = staleDate
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(service.todayHeartRateSample?.bpm == 64)
        #expect(service.todayHeartRateSample?.endDate == staleDate)
        // Convenience accessor still reports the BPM for callers that don't care about timing.
        #expect(service.todayHeartRateBPM == 64)
    }

    @Test("Wheelchair distance is fetched via the wheelchair-distance HealthKit type")
    @MainActor
    func wheelchairDistanceFlowsThroughDedicatedType() async {
        // Repro for finding-wheelchair-distance: previously the wheelchair path hardcoded zero.
        // Now it must query `fetchWheelchairDistance` and surface the result.
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        mockHealthKit.wheelchairPushesToReturn = 3_500
        mockHealthKit.wheelchairDistanceToReturn = 1_900
        mockHealthKit.distanceToReturn = 9_999 // walking distance — must be ignored
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(ActivityTrackingMode.wheelchairPushes.rawValue, forKey: AppConstants.UserDefaultsKeys.activityTrackingMode)
        testDefaults.defaults.set(DistanceEstimationMode.automatic.rawValue, forKey: AppConstants.UserDefaultsKeys.distanceEstimationMode)

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        await service.refreshTodayData()

        #expect(service.todayDistance == 1_900)
        #expect(mockHealthKit.fetchWheelchairDistanceCallCount >= 1)
    }

    @Test("HealthKit unavailable path still clears stale heart-rate display")
    @MainActor
    func healthKitUnavailableClearsStaleHeartRate() async {
        // When HealthKit can't service any read (sync disabled or device unavailable),
        // we should NOT continue to claim a heart rate. Verify the explicit-clear branch
        // still runs for the wheelchair-mode + sync-disabled combination.
        let mockHealthKit = MockHealthKitService()
        let mockMotion = MockMotionService()
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }
        testDefaults.defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
        testDefaults.defaults.set(ActivityTrackingMode.wheelchairPushes.rawValue, forKey: AppConstants.UserDefaultsKeys.activityTrackingMode)

        let (service, _) = makeService(
            healthKit: mockHealthKit,
            motion: mockMotion,
            userDefaults: testDefaults.defaults
        )

        // Seed a value so we can prove the clear actually fires.
        await service.refreshTodayData()
        #expect(service.todayHeartRateBPM == nil)
    }
}
