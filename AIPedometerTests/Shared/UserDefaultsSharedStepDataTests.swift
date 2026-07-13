import Foundation
import Testing

@testable import AIPedometer

@Suite("UserDefaults SharedStepData Tests")
@MainActor
struct UserDefaultsSharedStepDataTests {
    @Test("Shared data coalescer keeps latest value and flushes within the bound")
    @MainActor
    func coalescerKeepsLatestValue() {
        let testDefaults = TestUserDefaults()
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var scheduledFlush: (@MainActor @Sendable () -> Void)?
        let store = SharedDataStore(
            userDefaults: testDefaults.defaults,
            coalescingInterval: 5,
            now: { now },
            scheduleFlush: { _, operation in scheduledFlush = operation }
        )
        let first = SharedStepData(todaySteps: 1_000, goalSteps: 10_000, goalProgress: 0.1, currentStreak: 2, lastUpdated: now, weeklySteps: [])
        store.update(first)
        now.addTimeInterval(1)
        let second = SharedStepData(todaySteps: 1_010, goalSteps: 10_000, goalProgress: 0.101, currentStreak: 2, lastUpdated: now, weeklySteps: [])
        store.update(second)
        now.addTimeInterval(1)
        let latest = SharedStepData(todaySteps: 1_020, goalSteps: 10_000, goalProgress: 0.102, currentStreak: 2, lastUpdated: now, weeklySteps: [])
        store.update(latest)

        #expect(store.persistedWriteCount == 1)
        #expect(store.coalescedUpdateCount == 2)
        #expect(testDefaults.defaults.sharedStepData?.todaySteps == 1_000)

        now.addTimeInterval(3)
        scheduledFlush?()
        #expect(store.persistedWriteCount == 2)
        #expect(testDefaults.defaults.sharedStepData?.todaySteps == 1_020)
    }

    @Test("Immediate persists invalidate obsolete coalescing timers")
    @MainActor
    func immediatePersistInvalidatesObsoleteTimer() {
        let testDefaults = TestUserDefaults()
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var scheduledFlushes: [@MainActor @Sendable () -> Void] = []
        let store = SharedDataStore(
            userDefaults: testDefaults.defaults,
            coalescingInterval: 5,
            now: { now },
            scheduleFlush: { _, operation in scheduledFlushes.append(operation) }
        )

        store.update(SharedStepData(todaySteps: 1_000, goalSteps: 10_000, goalProgress: 0.1, currentStreak: 2, lastUpdated: now, weeklySteps: []))
        now.addTimeInterval(1)
        store.update(SharedStepData(todaySteps: 1_010, goalSteps: 10_000, goalProgress: 0.101, currentStreak: 2, lastUpdated: now, weeklySteps: []))
        let obsoleteFlush = scheduledFlushes[0]

        now.addTimeInterval(1)
        store.update(SharedStepData(todaySteps: 1_011, goalSteps: 12_000, goalProgress: 0.084, currentStreak: 2, lastUpdated: now, weeklySteps: []))
        now.addTimeInterval(1)
        store.update(SharedStepData(todaySteps: 1_020, goalSteps: 12_000, goalProgress: 0.085, currentStreak: 2, lastUpdated: now, weeklySteps: []))

        #expect(scheduledFlushes.count == 2)
        obsoleteFlush()
        #expect(store.persistedWriteCount == 2)
        #expect(testDefaults.defaults.sharedStepData?.todaySteps == 1_011)

        scheduledFlushes[1]()
        #expect(store.persistedWriteCount == 3)
        #expect(testDefaults.defaults.sharedStepData?.todaySteps == 1_020)
    }

    @Test("Wall-clock rollback cannot extend the coalescing deadline")
    @MainActor
    func wallClockRollbackKeepsBoundedDelay() {
        let testDefaults = TestUserDefaults()
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var scheduledDelay: TimeInterval?
        let store = SharedDataStore(
            userDefaults: testDefaults.defaults,
            coalescingInterval: 5,
            now: { now },
            scheduleFlush: { delay, _ in scheduledDelay = delay }
        )

        store.update(SharedStepData(todaySteps: 1_000, goalSteps: 10_000, goalProgress: 0.1, currentStreak: 2, lastUpdated: now, weeklySteps: []))
        now.addTimeInterval(-3_600)
        store.update(SharedStepData(todaySteps: 1_010, goalSteps: 10_000, goalProgress: 0.101, currentStreak: 2, lastUpdated: now, weeklySteps: []))

        #expect(scheduledDelay == 5)
    }

    @Test("Goal changes bypass shared data coalescing")
    @MainActor
    func goalChangesFlushImmediately() {
        let testDefaults = TestUserDefaults()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let store = SharedDataStore(userDefaults: testDefaults.defaults, coalescingInterval: 5, now: { now })
        store.update(SharedStepData(todaySteps: 1_000, goalSteps: 10_000, goalProgress: 0.1, currentStreak: 0, lastUpdated: now, weeklySteps: []))
        store.update(SharedStepData(todaySteps: 1_001, goalSteps: 12_000, goalProgress: 0.08, currentStreak: 0, lastUpdated: now, weeklySteps: []))

        #expect(store.persistedWriteCount == 2)
        #expect(testDefaults.defaults.sharedStepData?.goalSteps == 12_000)
    }

    @Test("App-written shared step data loads through the widget persistence contract")
    func appWrittenSharedStepDataLoadsThroughCanonicalPersistence() {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        let expected = SharedStepData(
            todaySteps: 5400,
            goalSteps: 10000,
            goalProgress: 0.54,
            currentStreak: 3,
            lastUpdated: Date(timeIntervalSince1970: 1_735_000_000),
            weeklySteps: [5000, 6000, 7000, 8000, 9000, 10000, 11000]
        )

        testDefaults.defaults.sharedStepData = expected
        let actual = SharedStepDataPersistence.load(from: testDefaults.defaults)

        #expect(actual?.todaySteps == expected.todaySteps)
        #expect(actual?.goalSteps == expected.goalSteps)
        #expect(actual?.goalProgress == expected.goalProgress)
        #expect(actual?.currentStreak == expected.currentStreak)
        #expect(actual?.lastUpdated == expected.lastUpdated)
        #expect(actual?.weeklySteps == expected.weeklySteps)
    }

    @Test("Shared step data loader returns nil when the store is unavailable or empty")
    func sharedStepDataLoaderReturnsNilWhenMissing() {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        #expect(SharedStepDataPersistence.load(from: nil) == nil)
        #expect(SharedStepDataPersistence.load(from: testDefaults.defaults) == nil)
    }

    @Test("Shared step data clears when set to nil")
    func sharedStepDataClearsWhenNil() {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        testDefaults.defaults.sharedStepData = SharedStepData(
            todaySteps: 1200,
            goalSteps: 8000,
            goalProgress: 0.15,
            currentStreak: 1,
            lastUpdated: Date(timeIntervalSince1970: 1_735_000_100),
            weeklySteps: [1200]
        )
        testDefaults.defaults.sharedStepData = nil

        #expect(testDefaults.defaults.sharedStepData == nil)
        #expect(testDefaults.defaults.data(forKey: AppConstants.UserDefaultsKeys.sharedStepData) == nil)
    }

    @Test("Shared step data loader purges corrupt payloads")
    func sharedStepDataLoaderPurgesCorruptPayloads() {
        let testDefaults = TestUserDefaults()
        defer { testDefaults.reset() }

        testDefaults.defaults.set(Data("invalid".utf8), forKey: AppConstants.UserDefaultsKeys.sharedStepData)

        #expect(SharedStepDataPersistence.load(from: testDefaults.defaults) == nil)
        #expect(testDefaults.defaults.data(forKey: AppConstants.UserDefaultsKeys.sharedStepData) == nil)
    }

    @Test("Shared step data treats future timestamps as stale")
    func sharedStepDataTreatsFutureTimestampAsStale() {
        let futureData = SharedStepData(
            todaySteps: 1200,
            goalSteps: 8000,
            goalProgress: 0.15,
            currentStreak: 1,
            lastUpdated: Date.now.addingTimeInterval(300),
            weeklySteps: [1200]
        )

        #expect(futureData.isStale)
    }

    @Test("Shared step data is stale after calendar-day rollover even within one hour")
    func sharedStepDataIsStaleAfterDayRollover() {
        let calendar = Calendar(identifier: .gregorian)
        let lastUpdated = Date(timeIntervalSince1970: 1_735_430_400) // 2024-12-31 23:00:00 UTC
        let referenceDate = lastUpdated.addingTimeInterval(30 * 60)
        let nextDayReference = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        let data = SharedStepData(
            todaySteps: 9000,
            goalSteps: 10000,
            goalProgress: 0.9,
            currentStreak: 4,
            lastUpdated: lastUpdated,
            weeklySteps: [8000, 9000]
        )

        #expect(data.isStale(referenceDate: nextDayReference, calendar: calendar))
    }
}
