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

@Suite("SharedStepData render normalization")
struct SharedStepDataRenderNormalizationTests {
    private func makeData(lastUpdated: Date) -> SharedStepData {
        SharedStepData(
            todaySteps: 12_340,
            goalSteps: 10_000,
            goalProgress: 1.234,
            currentStreak: 7,
            lastUpdated: lastUpdated,
            weeklySteps: [5400, 6100, 7200, 8300, 9100, 10_200, 12_340]
        )
    }

    /// 2023-11-14 00:00:00 UTC. Fixtures are offset from an explicit start-of-day so that "same day"
    /// cases cannot silently cross midnight.
    private static let dayStart = Date(timeIntervalSince1970: 1_699_920_000)

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    @Test("A payload from an earlier day is not presented as today's progress")
    func previousDayPayloadIsResetForToday() {
        // Regression: widgets re-read the app-group payload on their own 30-minute timeline. With no
        // overnight write — background refresh is not guaranteed — yesterday's 12,340 steps and completed
        // goal ring were rendered as today's, congratulating the user for steps they had not taken.
        let calendar = utcCalendar
        let lastNight = Self.dayStart.addingTimeInterval(22 * 3600)
        let nextMorning = Self.dayStart.addingTimeInterval(32 * 3600)
        #expect(!calendar.isDate(lastNight, inSameDayAs: nextMorning))

        let normalized = makeData(lastUpdated: lastNight)
            .normalizedForRendering(at: nextMorning, calendar: calendar)

        #expect(normalized.todaySteps == 0)
        #expect(normalized.goalProgress == 0)
        // The goal and streak are not day-scoped, so they survive and the ring keeps a target.
        #expect(normalized.goalSteps == 10_000)
        #expect(normalized.currentStreak == 7)
    }

    @Test("Activity mode survives a shared data round trip")
    func activityModeSurvivesRoundTrip() throws {
        // Widgets labelled wheelchair pushes as steps because the app-group payload dropped the mode.
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(makeData(lastUpdated: Self.dayStart))) as? [String: Any]
        )
        object["activityMode"] = "wheelchairPushes"
        let decoded = try JSONDecoder().decode(SharedStepData.self, from: JSONSerialization.data(withJSONObject: object))

        let reencoded = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any]
        )
        #expect(reencoded["activityMode"] as? String == "wheelchairPushes")
    }

    @Test("Legacy shared data without activity mode decodes as steps; pushes mode round trips")
    func activityModeDecoding() throws {
        var legacy = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(makeData(lastUpdated: Self.dayStart))) as? [String: Any]
        )
        legacy.removeValue(forKey: "activityMode")
        let decodedLegacy = try JSONDecoder().decode(SharedStepData.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(decodedLegacy.activityMode == .steps)

        let pushes = SharedStepData(
            todaySteps: 800,
            goalSteps: 1_500,
            goalProgress: 0.53,
            currentStreak: 2,
            lastUpdated: Self.dayStart,
            weeklySteps: [800],
            activityMode: .wheelchairPushes
        )
        let decoded = try JSONDecoder().decode(SharedStepData.self, from: JSONEncoder().encode(pushes))
        #expect(decoded.activityMode == .wheelchairPushes)
        // Day normalization must not silently fall back to steps.
        let nextDay = Self.dayStart.addingTimeInterval(30 * 3600)
        #expect(decoded.normalizedForRendering(at: nextDay, calendar: utcCalendar).activityMode == .wheelchairPushes)
    }

    @Test("Widget snapshot shows sample data only in the gallery when nothing is stored")
    func widgetSnapshotUsesSampleOnlyForPreview() {
        let now = Self.dayStart.addingTimeInterval(9 * 3600)

        let preview = SharedStepData.widgetSnapshotData(stored: nil, isPreview: true, at: now, calendar: utcCalendar)
        let live = SharedStepData.widgetSnapshotData(stored: nil, isPreview: false, at: now, calendar: utcCalendar)

        #expect(preview?.todaySteps == SharedStepData.widgetGallerySample().todaySteps)
        #expect(live == nil)
    }

    @Test("Widget snapshot normalizes stored data from a previous day")
    func widgetSnapshotNormalizesStoredData() {
        // Regression: `getSnapshot` returned the stored payload as-is, presenting yesterday's total as today's.
        let lastNight = Self.dayStart.addingTimeInterval(22 * 3600)
        let nextMorning = Self.dayStart.addingTimeInterval(32 * 3600)

        for isPreview in [false, true] {
            let snapshot = SharedStepData.widgetSnapshotData(
                stored: makeData(lastUpdated: lastNight),
                isPreview: isPreview,
                at: nextMorning,
                calendar: utcCalendar
            )
            #expect(snapshot?.todaySteps == 0)
            #expect(snapshot?.goalProgress == 0)
            #expect(snapshot?.currentStreak == 7)
        }
    }

    @Test("Same-day data is left untouched even when it is over an hour old")
    func sameDayPayloadSurvivesEvenWhenOld() {
        // Narrower than `isStale` on purpose: an hour-old payload is still today's best-known progress,
        // and zeroing it would erase real steps for anyone whose app simply has not refreshed recently.
        let calendar = utcCalendar
        let morning = Self.dayStart.addingTimeInterval(8 * 3600)
        let sameDayLater = Self.dayStart.addingTimeInterval(11 * 3600)
        #expect(calendar.isDate(morning, inSameDayAs: sameDayLater))
        #expect(makeData(lastUpdated: morning).isStale(referenceDate: sameDayLater, calendar: calendar))

        let normalized = makeData(lastUpdated: morning)
            .normalizedForRendering(at: sameDayLater, calendar: calendar)

        #expect(normalized.todaySteps == 12_340)
        #expect(normalized.goalProgress == 1.234)
    }

    @Test("Switching activity mode reaches widgets and the watch without the coalescing delay")
    func activityModeChangePersistsImmediately() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previous = SharedStepData(
            todaySteps: 1_000, goalSteps: 5_000, goalProgress: 0.2, currentStreak: 3,
            lastUpdated: now, weeklySteps: [1_000], activityMode: .steps
        )
        let next = SharedStepData(
            todaySteps: 1_000, goalSteps: 5_000, goalProgress: 0.2, currentStreak: 3,
            lastUpdated: now, weeklySteps: [1_000], activityMode: .wheelchairPushes
        )

        #expect(SharedStepDataWritePolicy.shouldPersistImmediately(
            previous: previous, next: next, lastPersistedAt: now, now: now, maximumStaleness: 5
        ))
        #expect(!SharedStepDataWritePolicy.shouldPersistImmediately(
            previous: previous, next: previous, lastPersistedAt: now, now: now, maximumStaleness: 5
        ))
    }
}
