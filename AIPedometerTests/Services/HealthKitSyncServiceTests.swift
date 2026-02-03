import Foundation
import SwiftData
import Testing

@testable import AIPedometer

// MARK: - SyncPolicy Tests

@Suite("SyncPolicy Constants Tests")
struct SyncPolicyTests {
    
    @Test("Cold start window is 30 days")
    func coldStartWindowIs30Days() {
        let expectedDays = 30.0
        let expectedInterval = expectedDays * 24 * 60 * 60
        
        #expect(SyncPolicy.coldStartWindow == expectedInterval)
    }
    
    @Test("Incremental overlap is 1 day")
    func incrementalOverlapIs1Day() {
        let expectedDays = 1.0
        let expectedInterval = expectedDays * 24 * 60 * 60
        
        #expect(SyncPolicy.incrementalOverlap == expectedInterval)
    }
    
    @Test("Foreground min interval is 6 hours")
    func foregroundMinIntervalIs6Hours() {
        let expectedHours = 6.0
        let expectedInterval = expectedHours * 60 * 60
        
        #expect(SyncPolicy.foregroundMinInterval == expectedInterval)
    }
    
    @Test("Background refresh interval is 12 hours")
    func backgroundRefreshIntervalIs12Hours() {
        let expectedHours = 12.0
        let expectedInterval = expectedHours * 60 * 60
        
        #expect(SyncPolicy.backgroundRefreshInterval == expectedInterval)
    }
    
    @Test("Pull to refresh window is 7 days")
    func pullToRefreshWindowIs7Days() {
        let expectedDays = 7.0
        let expectedInterval = expectedDays * 24 * 60 * 60
        
        #expect(SyncPolicy.pullToRefreshWindow == expectedInterval)
    }
    
    @Test("Stale data prune threshold is 30 days")
    func staleDataPruneThresholdIs30Days() {
        let expectedDays = 30.0
        let expectedInterval = expectedDays * 24 * 60 * 60
        
        #expect(SyncPolicy.staleDataPruneThreshold == expectedInterval)
    }
    
    @Test("AI context stale threshold is 1 hour")
    func aiContextStaleThresholdIs1Hour() {
        let expectedHours = 1.0
        let expectedInterval = expectedHours * 60 * 60
        
        #expect(SyncPolicy.aiContextStaleThreshold == expectedInterval)
    }
}

// MARK: - SyncStateKey Tests

@Suite("SyncStateKey Tests")
struct SyncStateKeyTests {
    
    @Test("Keys have correct raw values")
    func keysHaveCorrectRawValues() {
        #expect(SyncStateKey.lastSyncDate.rawValue == "aipedometer.sync.lastSyncDate")
        #expect(SyncStateKey.lastColdStartDate.rawValue == "aipedometer.sync.lastColdStartDate")
        #expect(SyncStateKey.syncVersion.rawValue == "aipedometer.sync.version")
    }
}

// MARK: - HealthKitSyncService Tests

@Suite("HealthKitSyncService Tests")
@MainActor
struct HealthKitSyncServiceTests {
    
    private func makeTestEnvironment(calendar: Calendar = .autoupdatingCurrent) -> (
        service: HealthKitSyncService,
        mockHealthKit: MockHealthKitService,
        userDefaults: UserDefaults,
        modelContext: ModelContext
    ) {
        let mockHealthKit = MockHealthKitService()
        let persistence = PersistenceController(inMemory: true)
        let modelContext = persistence.container.mainContext
        let goalService = GoalService(persistence: persistence)
        
        let suiteName = "HealthKitSyncServiceTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName) ?? .standard
        userDefaults.removePersistentDomain(forName: suiteName)
        
        let service = HealthKitSyncService(
            healthKitService: mockHealthKit,
            modelContext: modelContext,
            goalService: goalService,
            userDefaults: userDefaults,
            calendar: calendar
        )
        
        return (service, mockHealthKit, userDefaults, modelContext)
    }
    
    @Test("Needs cold start sync when never synced")
    func needsColdStartSyncWhenNeverSynced() {
        let (service, _, _, _) = makeTestEnvironment()
        
        #expect(service.needsColdStartSync() == true)
    }

    @Test("Sync checks disabled setting before scheduling")
    func syncSkipsWhenDisabled() async throws {
        let (service, _, userDefaults, _) = makeTestEnvironment()
        userDefaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)

        #expect(service.needsColdStartSync() == false)
        #expect(service.shouldPerformForegroundSync() == false)

        try await service.performColdStartSync()
        let lastSyncTimestamp = userDefaults.double(forKey: SyncStateKey.lastSyncDate.rawValue)
        #expect(lastSyncTimestamp == 0)
    }

    @Test("Sync requests HealthKit authorization before syncing")
    func syncRequestsAuthorizationBeforeSync() async throws {
        let (service, mockHealthKit, userDefaults, _) = makeTestEnvironment()
        userDefaults.set(Date.now.timeIntervalSince1970, forKey: SyncStateKey.lastSyncDate.rawValue)

        try await service.performIncrementalSync()

        #expect(mockHealthKit.authorizationRequested == true)
    }

    @Test("Sync uses historical goals when writing daily records")
    func syncUsesHistoricalGoalsForDailyRecords() async throws {
        let (service, mockHealthKit, userDefaults, modelContext) = makeTestEnvironment()
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let goal1End = calendar.date(byAdding: .second, value: -1, to: today) ?? today

        modelContext.insert(StepGoal(dailySteps: 8000, startDate: yesterday, endDate: goal1End))
        modelContext.insert(StepGoal(dailySteps: 10000, startDate: today))
        try modelContext.save()

        mockHealthKit.dailySummariesToReturn = [
            DailyStepSummary(
                date: yesterday,
                steps: 5000,
                distance: 1000,
                floors: 2,
                calories: Double(5000) * AppConstants.Metrics.caloriesPerStep,
                goal: 8000
            ),
            DailyStepSummary(
                date: today,
                steps: 7000,
                distance: 1400,
                floors: 3,
                calories: Double(7000) * AppConstants.Metrics.caloriesPerStep,
                goal: 10000
            )
        ]
        userDefaults.set(Date.now.timeIntervalSince1970, forKey: SyncStateKey.lastSyncDate.rawValue)

        try await service.performIncrementalSync()

        let descriptor = FetchDescriptor<DailyStepRecord>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        let records = try modelContext.fetch(descriptor)
        let goalsByDate = Dictionary(
            uniqueKeysWithValues: records.map { (calendar.startOfDay(for: $0.date), $0.goalSteps) }
        )

        #expect(goalsByDate[yesterday] == 8000)
        #expect(goalsByDate[today] == 10000)
    }

    @Test("Sync requests daily summaries using current activity settings")
    func syncUsesActivitySettingsForDailySummaries() async throws {
        let (service, mockHealthKit, userDefaults, _) = makeTestEnvironment()
        userDefaults.set(ActivityTrackingMode.wheelchairPushes.rawValue, forKey: AppConstants.UserDefaultsKeys.activityTrackingMode)
        userDefaults.set(DistanceEstimationMode.manual.rawValue, forKey: AppConstants.UserDefaultsKeys.distanceEstimationMode)
        userDefaults.set(0.85, forKey: AppConstants.UserDefaultsKeys.manualStepLengthMeters)
        userDefaults.set(Date.now.timeIntervalSince1970, forKey: SyncStateKey.lastSyncDate.rawValue)

        try await service.performIncrementalSync()

        let args = mockHealthKit.lastFetchDailySummariesRangeArgs
        #expect(args?.activityMode == .wheelchairPushes)
        #expect(args?.distanceMode == .manual)
        #expect(args?.manualStepLength == 0.85)
    }

    @Test("AI context snapshot counts goal hits using historical goals")
    func aiContextSnapshotUsesHistoricalGoals() async throws {
        let (service, _, _, modelContext) = makeTestEnvironment()
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let goal1End = calendar.date(byAdding: .second, value: -1, to: today) ?? today

        modelContext.insert(StepGoal(dailySteps: 8000, startDate: yesterday, endDate: goal1End))
        modelContext.insert(StepGoal(dailySteps: 12000, startDate: today))

        modelContext.insert(
            DailyStepRecord(
                date: yesterday,
                steps: 9000,
                distance: 1500,
                floorsAscended: 1,
                floorsDescended: 0,
                activeCalories: 250,
                goalSteps: 8000,
                source: .combined
            )
        )
        modelContext.insert(
            DailyStepRecord(
                date: today,
                steps: 11000,
                distance: 2000,
                floorsAscended: 2,
                floorsDescended: 0,
                activeCalories: 300,
                goalSteps: 12000,
                source: .combined
            )
        )
        try modelContext.save()

        try await service.updateAIContextSnapshot(referenceDate: today)

        let descriptor = FetchDescriptor<AIContextSnapshot>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        let snapshot = try modelContext.fetch(descriptor).first

        #expect(snapshot?.last7DaysGoalHitCount == 1)
        #expect(snapshot?.last7DaysSteps.count == 7)
        #expect(snapshot?.last7DaysSteps.suffix(2) == [9000, 11000])
    }

    @Test("AI context snapshot prefers the latest record when multiple records map to the same day")
    func aiContextSnapshotUsesLatestRecordForDay() async throws {
        let (service, _, _, modelContext) = makeTestEnvironment()
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let morning = calendar.date(byAdding: .hour, value: 3, to: today) ?? today
        let evening = calendar.date(byAdding: .hour, value: 18, to: today) ?? today

        let olderRecord = DailyStepRecord(
            date: morning,
            steps: 4000,
            distance: 1000,
            floorsAscended: 1,
            floorsDescended: 0,
            activeCalories: 200,
            goalSteps: 8000,
            source: .combined
        )
        olderRecord.updatedAt = morning

        let newerRecord = DailyStepRecord(
            date: evening,
            steps: 6500,
            distance: 1500,
            floorsAscended: 2,
            floorsDescended: 0,
            activeCalories: 250,
            goalSteps: 8000,
            source: .combined
        )
        newerRecord.updatedAt = evening

        modelContext.insert(olderRecord)
        modelContext.insert(newerRecord)
        try modelContext.save()

        try await service.updateAIContextSnapshot(referenceDate: today)

        let descriptor = FetchDescriptor<AIContextSnapshot>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        let snapshot = try modelContext.fetch(descriptor).first

        #expect(snapshot?.last7DaysSteps.last == 6500)
    }

    @Test("AI context snapshot averages full 7-day windows with zero-filled days")
    func aiContextSnapshotAveragesFullWeeksWithZeroFill() async throws {
        let (service, _, _, modelContext) = makeTestEnvironment()
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)

        // Week offset 1 (7-13 days ago): full data at 7000 steps/day.
        for offset in 7...13 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            modelContext.insert(
                DailyStepRecord(
                    date: date,
                    steps: 7000,
                    distance: 1500,
                    floorsAscended: 1,
                    floorsDescended: 0,
                    activeCalories: 250,
                    goalSteps: 10000,
                    source: .combined
                )
            )
        }

        // Week offset 0 (0-6 days ago): partial data on two days.
        if let dayMinus1 = calendar.date(byAdding: .day, value: -1, to: today) {
            modelContext.insert(
                DailyStepRecord(
                    date: dayMinus1,
                    steps: 7000,
                    distance: 1500,
                    floorsAscended: 1,
                    floorsDescended: 0,
                    activeCalories: 250,
                    goalSteps: 10000,
                    source: .combined
                )
            )
        }
        modelContext.insert(
            DailyStepRecord(
                date: today,
                steps: 5000,
                distance: 1200,
                floorsAscended: 1,
                floorsDescended: 0,
                activeCalories: 220,
                goalSteps: 10000,
                source: .combined
            )
        )

        try modelContext.save()

        try await service.updateAIContextSnapshot(referenceDate: today)

        let descriptor = FetchDescriptor<AIContextSnapshot>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        let snapshot = try modelContext.fetch(descriptor).first

        #expect(snapshot?.last4WeeksAverages.count == 4)
        #expect(snapshot?.last4WeeksAverages[0] == 0)
        #expect(snapshot?.last4WeeksAverages[1] == 0)
        #expect(snapshot?.last4WeeksAverages[2] == 7000)
        #expect(snapshot?.last4WeeksAverages[3] == 1714)
    }

    @Test("AI context snapshot ignores records older than 28 days")
    func aiContextSnapshotIgnoresOldRecords() async throws {
        let (service, _, _, modelContext) = makeTestEnvironment()
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let oldDate = calendar.date(byAdding: .day, value: -30, to: today) ?? today

        modelContext.insert(
            DailyStepRecord(
                date: oldDate,
                steps: 50000,
                distance: 10000,
                floorsAscended: 5,
                floorsDescended: 0,
                activeCalories: 500,
                goalSteps: 10000,
                source: .combined
            )
        )
        modelContext.insert(
            DailyStepRecord(
                date: today,
                steps: 5000,
                distance: 1000,
                floorsAscended: 1,
                floorsDescended: 0,
                activeCalories: 200,
                goalSteps: 10000,
                source: .combined
            )
        )
        try modelContext.save()

        try await service.updateAIContextSnapshot(referenceDate: today)

        let descriptor = FetchDescriptor<AIContextSnapshot>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        let snapshot = try modelContext.fetch(descriptor).first

        #expect(snapshot?.last7DaysSteps.suffix(1) == [5000])
        #expect(snapshot?.last4WeeksAverages.first == 0)
        #expect(snapshot?.last4WeeksAverages.last == 714)
    }

    @Test("AI context snapshot is stable across DST boundaries")
    func aiContextSnapshotHandlesDSTBoundaries() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .autoupdatingCurrent
        let referenceDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12)) ?? .now
        let (service, _, _, modelContext) = makeTestEnvironment(calendar: calendar)

        // Anchor on a DST transition week to ensure we rely on calendar-day math, not fixed 24h intervals.
        let endDate = calendar.startOfDay(for: referenceDate)
        var expectedSteps: [Int] = []

        for offset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: endDate) else { continue }
            let steps = 1000 + (6 - offset)
            expectedSteps.append(steps)
            modelContext.insert(
                DailyStepRecord(
                    date: date,
                    steps: steps,
                    distance: 1000,
                    floorsAscended: 1,
                    floorsDescended: 0,
                    activeCalories: 200,
                    goalSteps: 10000,
                    source: .combined
                )
            )
        }

        try modelContext.save()
        try await service.updateAIContextSnapshot(referenceDate: referenceDate)

        let descriptor = FetchDescriptor<AIContextSnapshot>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        let snapshot = try modelContext.fetch(descriptor).first

        #expect(snapshot?.last7DaysSteps.count == 7)
        #expect(snapshot?.last7DaysSteps == expectedSteps)
    }
    
    @Test("Should perform foreground sync when never synced")
    func shouldPerformForegroundSyncWhenNeverSynced() {
        let (service, _, _, _) = makeTestEnvironment()
        
        #expect(service.shouldPerformForegroundSync() == true)
    }
    
    @Test("Needs cold start sync when never synced")
    func needsColdStartSyncReturnsTrue() {
        let (service, _, _, _) = makeTestEnvironment()
        
        #expect(service.needsColdStartSync() == true)
    }
    
    @Test("Sync handles HealthKit errors gracefully")
    func syncHandlesHealthKitErrorsGracefully() async {
        let (service, mockHealthKit, _, _) = makeTestEnvironment()
        mockHealthKit.errorToThrow = HealthKitError.queryFailed
        
        await #expect(throws: HealthKitError.self) {
            try await service.performColdStartSync()
        }
    }

    @Test("Sync prunes only ended workouts without crashing on nil endTime")
    func syncPrunesOldEndedWorkoutsSafely() async throws {
        let (service, _, _, modelContext) = makeTestEnvironment()

        let oldEnd = Date.now.addingTimeInterval(-SyncPolicy.staleDataPruneThreshold - 3600)
        let ended = WorkoutSession(type: .outdoorWalk, startTime: oldEnd, endTime: oldEnd)
        let inProgress = WorkoutSession(type: .outdoorWalk, startTime: oldEnd, endTime: nil)

        modelContext.insert(ended)
        modelContext.insert(inProgress)
        try modelContext.save()

        try await service.performIncrementalSync()

        #expect(ended.deletedAt != nil)
        #expect(inProgress.deletedAt == nil)
    }
}

// MARK: - AIContextSnapshot Prompt Tests

@Suite("AIContextSnapshot AI Prompt Tests")
struct AIContextSnapshotPromptTests {
    
    @Test("AI prompt context includes all sections when populated")
    func aiPromptContextIncludesAllSectionsWhenPopulated() {
        let snapshot = AIContextSnapshot(
            last7DaysSteps: [8000, 9000, 10000, 7500, 11000, 9500, 8500],
            last7DaysAverage: 9071,
            last7DaysGoalHitCount: 4,
            last4WeeksAverages: [8500, 8800, 9000, 9200],
            weekOverWeekTrend: "increasing",
            currentStreak: 5,
            longestStreak: 12,
            recentWorkoutCount: 3,
            lastWorkoutDate: Date.now,
            totalBadgesEarned: 7,
            currentDailyGoal: 10000
        )
        
        let prompt = snapshot.aiPromptContext
        
        #expect(prompt.contains("User Activity Summary"))
        // Check for goal value (locale-agnostic)
        #expect(prompt.contains("10") && prompt.contains("000") && prompt.contains("steps"))
        #expect(prompt.contains("Current streak: 5 days"))
        #expect(prompt.contains("Longest streak: 12 days"))
        #expect(prompt.contains("Total badges earned: 7"))
        #expect(prompt.contains("Last 7 Days"))
        // Check for average value presence
        #expect(prompt.contains("9") && prompt.contains("071"))
        #expect(prompt.contains("4 of 7"))
        #expect(prompt.contains("Weekly Trend"))
        #expect(prompt.contains("increasing"))
        #expect(prompt.contains("Workouts"))
        #expect(prompt.contains("3"))
    }
    
    @Test("AI prompt context handles empty data gracefully")
    func aiPromptContextHandlesEmptyDataGracefully() {
        let snapshot = AIContextSnapshot()
        
        let prompt = snapshot.aiPromptContext
        
        #expect(prompt.contains("User Activity Summary"))
        // Goal should appear in summary section
        #expect(prompt.contains("daily goal") && prompt.contains("10") && prompt.contains("000"))
        #expect(prompt.contains("Current streak: 0 days"))
        // Should NOT contain Last 7 Days or Weekly Trend sections when empty
        #expect(!prompt.contains("Last 7 Days:"))
        #expect(!prompt.contains("Weekly Trend:"))
        #expect(!prompt.contains("Workouts:"))
    }
    
    @Test("AI prompt context formats numbers")
    func aiPromptContextFormatsNumbers() {
        let snapshot = AIContextSnapshot(
            last7DaysSteps: [12345],
            last7DaysAverage: 12345,
            currentDailyGoal: 15000
        )
        
        let prompt = snapshot.aiPromptContext
        
        // Should contain the numeric values (formatter may vary by locale)
        #expect(prompt.contains("15") && prompt.contains("000"))
        #expect(prompt.contains("12") && prompt.contains("345"))
    }
}

// MARK: - AIContextSnapshot Model Tests

@Suite("AIContextSnapshot Model Tests")
struct AIContextSnapshotModelTests {
    
    @Test("Default initialization has correct values")
    func defaultInitializationHasCorrectValues() {
        let snapshot = AIContextSnapshot()
        
        #expect(snapshot.last7DaysSteps.isEmpty)
        #expect(snapshot.last7DaysAverage == 0)
        #expect(snapshot.last7DaysGoalHitCount == 0)
        #expect(snapshot.last4WeeksAverages.isEmpty)
        #expect(snapshot.weekOverWeekTrend == "stable")
        #expect(snapshot.currentStreak == 0)
        #expect(snapshot.longestStreak == 0)
        #expect(snapshot.recentWorkoutCount == 0)
        #expect(snapshot.lastWorkoutDate == nil)
        #expect(snapshot.totalBadgesEarned == 0)
        #expect(snapshot.currentDailyGoal == 10000)
        #expect(snapshot.deletedAt == nil)
    }
    
    @Test("Custom initialization sets all values")
    func customInitializationSetsAllValues() {
        let testDate = Date.now
        let snapshot = AIContextSnapshot(
            last7DaysSteps: [1, 2, 3, 4, 5, 6, 7],
            last7DaysAverage: 4,
            last7DaysGoalHitCount: 3,
            last4WeeksAverages: [100, 200, 300, 400],
            weekOverWeekTrend: "decreasing",
            currentStreak: 10,
            longestStreak: 20,
            recentWorkoutCount: 5,
            lastWorkoutDate: testDate,
            totalBadgesEarned: 15,
            currentDailyGoal: 8000
        )
        
        #expect(snapshot.last7DaysSteps == [1, 2, 3, 4, 5, 6, 7])
        #expect(snapshot.last7DaysAverage == 4)
        #expect(snapshot.last7DaysGoalHitCount == 3)
        #expect(snapshot.last4WeeksAverages == [100, 200, 300, 400])
        #expect(snapshot.weekOverWeekTrend == "decreasing")
        #expect(snapshot.currentStreak == 10)
        #expect(snapshot.longestStreak == 20)
        #expect(snapshot.recentWorkoutCount == 5)
        #expect(snapshot.lastWorkoutDate == testDate)
        #expect(snapshot.totalBadgesEarned == 15)
        #expect(snapshot.currentDailyGoal == 8000)
    }
    
    @Test("Snapshot can be persisted to SwiftData")
    @MainActor
    func snapshotCanBePersistedToSwiftData() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        
        let snapshot = AIContextSnapshot(
            last7DaysSteps: [5000, 6000, 7000, 8000, 9000, 10000, 11000],
            last7DaysAverage: 8000,
            currentStreak: 7
        )
        
        context.insert(snapshot)
        try context.save()
        
        let descriptor = FetchDescriptor<AIContextSnapshot>()
        let fetched = try context.fetch(descriptor)
        
        #expect(fetched.count == 1)
        #expect(fetched.first?.last7DaysSteps == [5000, 6000, 7000, 8000, 9000, 10000, 11000])
        #expect(fetched.first?.last7DaysAverage == 8000)
        #expect(fetched.first?.currentStreak == 7)
    }
    
    @Test("Snapshot supports soft delete pattern")
    @MainActor
    func snapshotSupportsSoftDeletePattern() throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.mainContext
        
        let snapshot = AIContextSnapshot()
        context.insert(snapshot)
        try context.save()
        
        // Soft delete
        snapshot.deletedAt = Date.now
        try context.save()
        
        // Should still exist in database
        let allDescriptor = FetchDescriptor<AIContextSnapshot>()
        let allSnapshots = try context.fetch(allDescriptor)
        #expect(allSnapshots.count == 1)
        
        // But filtered query excludes it
        let activeDescriptor = FetchDescriptor<AIContextSnapshot>(
            predicate: #Predicate { $0.deletedAt == nil }
        )
        let activeSnapshots = try context.fetch(activeDescriptor)
        #expect(activeSnapshots.isEmpty)
    }
}
