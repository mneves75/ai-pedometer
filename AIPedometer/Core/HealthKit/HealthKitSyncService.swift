import Foundation
import HealthKit
import Observation
import SwiftData

enum SyncPolicy {
    /// Initial full sync window (30 days)
    static let coldStartWindow: TimeInterval = 30 * 24 * 60 * 60
    
    /// Overlap period for incremental syncs to catch late-arriving samples
    static let incrementalOverlap: TimeInterval = 1 * 24 * 60 * 60
    
    /// Minimum interval between automatic foreground syncs
    static let foregroundMinInterval: TimeInterval = 6 * 60 * 60
    
    /// Target interval for background refresh tasks
    static let backgroundRefreshInterval: TimeInterval = 12 * 60 * 60
    
    /// Window for pull-to-refresh operations
    static let pullToRefreshWindow: TimeInterval = 7 * 24 * 60 * 60
    
    /// Threshold for pruning orphaned cache entries
    static let staleDataPruneThreshold: TimeInterval = 30 * 24 * 60 * 60
    
    /// Maximum age for considering AI context snapshot stale
    static let aiContextStaleThreshold: TimeInterval = 1 * 60 * 60
}

// MARK: - Sync State

/// Persisted sync state for deterministic behavior across app launches.
enum SyncStateKey: String {
    case lastSyncDate = "aipedometer.sync.lastSyncDate"
    case lastColdStartDate = "aipedometer.sync.lastColdStartDate"
    case syncVersion = "aipedometer.sync.version"
}

// MARK: - Protocol

@MainActor
protocol HealthKitSyncServiceProtocol: AnyObject {
    func performColdStartSync() async throws
    func performIncrementalSync() async throws
    func performPullToRefresh() async throws
    func updateAIContextSnapshot() async throws
    func shouldPerformForegroundSync() -> Bool
}

// MARK: - Implementation

@Observable
@MainActor
final class HealthKitSyncService: HealthKitSyncServiceProtocol {
    private let healthKitService: any HealthKitServiceProtocol
    private let modelContext: ModelContext
    private let userDefaults: UserDefaults
    private let calendar: Calendar
    private let goalService: GoalService
    
    /// Current sync version - increment when sync logic changes materially
    private static let currentSyncVersion = 1
    
    init(
        healthKitService: any HealthKitServiceProtocol,
        modelContext: ModelContext,
        goalService: GoalService,
        userDefaults: UserDefaults = .standard,
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.healthKitService = healthKitService
        self.modelContext = modelContext
        self.goalService = goalService
        self.userDefaults = userDefaults
        self.calendar = calendar
    }
    
    // MARK: - Cold Start Sync
    
    /// Performs initial full sync for new installs or after data reset.
    /// Fetches 30 days of historical data.
    func performColdStartSync() async throws {
        guard isSyncEnabled else {
            Loggers.sync.info("sync.cold_start_skipped", metadata: ["reason": "sync_disabled"])
            return
        }
        try await ensureAuthorization()
        Loggers.sync.info("sync.cold_start_begin")
        
        let now = Date.now
        let startDate = now.addingTimeInterval(-SyncPolicy.coldStartWindow)
        
        // Sync daily step records
        try await syncDailyRecords(from: startDate, to: now)
        
        // Sync workout sessions
        try await syncWorkouts(from: startDate, to: now)
        
        // Update AI context snapshot
        try await updateAIContextSnapshot()
        
        // Mark cold start complete
        userDefaults.set(now.timeIntervalSince1970, forKey: SyncStateKey.lastColdStartDate.rawValue)
        userDefaults.set(now.timeIntervalSince1970, forKey: SyncStateKey.lastSyncDate.rawValue)
        userDefaults.set(Self.currentSyncVersion, forKey: SyncStateKey.syncVersion.rawValue)
        
        Loggers.sync.info("sync.cold_start_complete", metadata: ["days": "30"])
    }
    
    // MARK: - Incremental Sync
    
    /// Performs incremental sync since last sync with 1-day overlap.
    /// Overlap catches late-arriving HealthKit samples.
    func performIncrementalSync() async throws {
        guard isSyncEnabled else {
            Loggers.sync.info("sync.incremental_skipped", metadata: ["reason": "sync_disabled"])
            return
        }
        try await ensureAuthorization()
        let now = Date.now
        let lastSync = lastSyncDate ?? now.addingTimeInterval(-SyncPolicy.coldStartWindow)
        let startDate = lastSync.addingTimeInterval(-SyncPolicy.incrementalOverlap)
        
        Loggers.sync.info("sync.incremental_begin", metadata: [
            "from": startDate.ISO8601Format(),
            "to": now.ISO8601Format()
        ])
        
        try await syncDailyRecords(from: startDate, to: now)
        try await syncWorkouts(from: startDate, to: now)
        try await updateAIContextSnapshot()
        
        userDefaults.set(now.timeIntervalSince1970, forKey: SyncStateKey.lastSyncDate.rawValue)
        
        Loggers.sync.info("sync.incremental_complete")
    }
    
    // MARK: - Pull to Refresh
    
    /// User-initiated refresh covering last 7 days.
    func performPullToRefresh() async throws {
        guard isSyncEnabled else {
            Loggers.sync.info("sync.pull_to_refresh_skipped", metadata: ["reason": "sync_disabled"])
            return
        }
        try await ensureAuthorization()
        let now = Date.now
        let startDate = now.addingTimeInterval(-SyncPolicy.pullToRefreshWindow)
        
        Loggers.sync.info("sync.pull_to_refresh_begin")
        
        try await syncDailyRecords(from: startDate, to: now)
        try await syncWorkouts(from: startDate, to: now)
        try await updateAIContextSnapshot()
        
        userDefaults.set(now.timeIntervalSince1970, forKey: SyncStateKey.lastSyncDate.rawValue)
        
        Loggers.sync.info("sync.pull_to_refresh_complete")
    }
    
    // MARK: - Foreground Sync Check
    
    /// Returns true if enough time has passed since last sync.
    func shouldPerformForegroundSync() -> Bool {
        guard isSyncEnabled else { return false }
        guard let lastSync = lastSyncDate else { return true }
        let elapsed = Date.now.timeIntervalSince(lastSync)
        return elapsed >= SyncPolicy.foregroundMinInterval
    }
    
    /// Returns true if cold start sync is needed.
    func needsColdStartSync() -> Bool {
        guard isSyncEnabled else { return false }
        let storedVersion = userDefaults.integer(forKey: SyncStateKey.syncVersion.rawValue)
        if storedVersion < Self.currentSyncVersion { return true }
        
        let lastColdStart = userDefaults.double(forKey: SyncStateKey.lastColdStartDate.rawValue)
        return lastColdStart == 0
    }
    
    // MARK: - AI Context Snapshot
    
    /// Rebuilds the AI context snapshot from current cache state.
    func updateAIContextSnapshot() async throws {
        try await updateAIContextSnapshot(referenceDate: Date.now)
    }

    /// Rebuilds the AI context snapshot anchored to a fixed reference date (for deterministic tests).
    func updateAIContextSnapshot(referenceDate: Date) async throws {
        let now = referenceDate
        let currentGoal = goalService.currentGoal
        
        // Fetch or create snapshot
        let descriptor = FetchDescriptor<AIContextSnapshot>(
            sortBy: [SortDescriptor(\.lastUpdated, order: .reverse)]
        )
        let existing = try modelContext.fetch(descriptor).first
        let snapshot = existing ?? AIContextSnapshot()
        
        // Update last 7 days
        let recentRecords = try fetchRecentRecords(referenceDate: now, days: 28)
        let last7DaysSnapshot = buildLast7DaysSnapshot(
            referenceDate: now,
            recordsByDate: recentRecords,
            fallbackGoal: currentGoal
        )
        snapshot.last7DaysSteps = last7DaysSnapshot.steps
        snapshot.last7DaysAverage = last7DaysSnapshot.steps.isEmpty
            ? 0
            : last7DaysSnapshot.steps.reduce(0, +) / last7DaysSnapshot.steps.count
        snapshot.last7DaysGoalHitCount = last7DaysSnapshot.goalHitCount
        
        // Update last 4 weeks
        let last4Weeks = buildLast4WeeksAverages(referenceDate: now, recordsByDate: recentRecords)
        snapshot.last4WeeksAverages = last4Weeks
        snapshot.weekOverWeekTrend = calculateTrend(from: last4Weeks)
        
        // Update streaks
        let streakInfo = try fetchStreakInfo()
        snapshot.currentStreak = streakInfo.current
        snapshot.longestStreak = streakInfo.longest
        
        // Update workout info
        let workoutInfo = try fetchRecentWorkoutInfo()
        snapshot.recentWorkoutCount = workoutInfo.count
        snapshot.lastWorkoutDate = workoutInfo.lastDate
        
        // Update badges
        snapshot.totalBadgesEarned = try fetchEarnedBadgeCount()
        
        // Update goal
        snapshot.currentDailyGoal = currentGoal
        
        // Update metadata
        snapshot.snapshotDate = now
        snapshot.lastUpdated = now
        
        if existing == nil {
            modelContext.insert(snapshot)
        }
        
        try modelContext.save()
        
        Loggers.sync.info("sync.ai_context_updated", metadata: [
            "avg7d": "\(snapshot.last7DaysAverage)",
            "streak": "\(snapshot.currentStreak)",
            "trend": snapshot.weekOverWeekTrend
        ])
    }
    
    // MARK: - Private Helpers
    
    private var lastSyncDate: Date? {
        let timestamp = userDefaults.double(forKey: SyncStateKey.lastSyncDate.rawValue)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    private var isSyncEnabled: Bool {
        HealthKitSyncSettings.isEnabled(userDefaults: userDefaults)
    }

    private func ensureAuthorization() async throws {
        do {
            try await healthKitService.requestAuthorization()
        } catch {
            Loggers.health.warning("healthkit.authorization_failed_for_sync", metadata: [
                "error": error.localizedDescription
            ])
            throw error
        }
    }
    
    private func syncDailyRecords(from startDate: Date, to endDate: Date) async throws {
        let currentGoal = goalService.currentGoal
        let settings = ActivitySettings.current(userDefaults: userDefaults)

        let summaries = try await healthKitService.fetchDailySummaries(
            from: startDate,
            to: endDate,
            activityMode: settings.activityMode,
            distanceMode: settings.distanceMode,
            manualStepLength: settings.manualStepLength,
            dailyGoal: currentGoal
        )

        for summary in summaries {
            let goalForDay = goalService.goal(for: summary.date) ?? currentGoal
            let calories = Double(summary.steps) * AppConstants.Metrics.caloriesPerStep

            try upsertDailyRecord(
                date: summary.date,
                steps: summary.steps,
                distance: summary.distance,
                floors: summary.floors,
                calories: calories,
                goal: goalForDay
            )
        }

        try modelContext.save()
    }
    
    private func upsertDailyRecord(
        date: Date,
        steps: Int,
        distance: Double,
        floors: Int,
        calories: Double,
        goal: Int
    ) throws {
        let normalizedDate = calendar.startOfDay(for: date)
        
        // Try to find existing record
        let predicate = #Predicate<DailyStepRecord> { record in
            record.date == normalizedDate && record.deletedAt == nil
        }
        let descriptor = FetchDescriptor<DailyStepRecord>(predicate: predicate)
        
        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing - HealthKit always wins
            existing.steps = steps
            existing.distance = distance
            existing.floorsAscended = floors
            existing.activeCalories = calories
            existing.goalSteps = goal
            existing.updatedAt = Date.now
        } else {
            // Create new
            let record = DailyStepRecord(
                date: normalizedDate,
                steps: steps,
                distance: distance,
                floorsAscended: floors,
                floorsDescended: 0,
                activeCalories: calories,
                goalSteps: goal,
                source: .combined
            )
            modelContext.insert(record)
        }
    }
    
    private func syncWorkouts(from startDate: Date, to endDate: Date) async throws {
        // Note: WorkoutSession records are created when user starts workouts in-app.
        // This method syncs any HealthKit-originated workouts we may have missed.
        // For now, we just ensure existing records have updated metadata.
        // Full HKWorkout query would require additional HealthKit permissions.
        
        // Mark records older than prune threshold as potentially stale
        let pruneThreshold = Date.now.addingTimeInterval(-SyncPolicy.staleDataPruneThreshold)
        let predicate = #Predicate<WorkoutSession> { session in
            session.deletedAt == nil && session.endTime != nil
        }
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: predicate)
        
        let endedWorkouts = try modelContext.fetch(descriptor)
        for workout in endedWorkouts {
            guard let endTime = workout.endTime, endTime < pruneThreshold else { continue }
            // Mark as soft-deleted if very old and not synced back
            if workout.healthKitWorkoutID == nil {
                workout.deletedAt = Date.now
            }
        }
        
        try modelContext.save()
    }
    
    private func fetchRecentRecords(referenceDate: Date, days: Int) throws -> [Date: DailyStepRecord] {
        let endDate = calendar.startOfDay(for: referenceDate)
        guard days > 0 else { return [:] }
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: endDate) ?? endDate
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        let predicate = #Predicate<DailyStepRecord> { record in
            record.date >= startDate &&
            record.date < endExclusive &&
            record.deletedAt == nil
        }
        let descriptor = FetchDescriptor<DailyStepRecord>(predicate: predicate)
        let records = try modelContext.fetch(descriptor)
        var recordsByDate: [Date: DailyStepRecord] = [:]
        var duplicateCount = 0
        for record in records {
            let normalizedDate = calendar.startOfDay(for: record.date)
            if let existing = recordsByDate[normalizedDate] {
                duplicateCount += 1
                if record.updatedAt > existing.updatedAt {
                    recordsByDate[normalizedDate] = record
                }
            } else {
                recordsByDate[normalizedDate] = record
            }
        }
        if duplicateCount > 0 {
            Loggers.sync.warning("sync.daily_records_duplicate_dates", metadata: [
                "duplicates": "\(duplicateCount)",
                "range_start": "\(startDate)",
                "range_end": "\(endExclusive)"
            ])
        }
        return recordsByDate
    }

    private func buildLast7DaysSnapshot(
        referenceDate: Date,
        recordsByDate: [Date: DailyStepRecord],
        fallbackGoal: Int
    ) -> (steps: [Int], goalHitCount: Int) {
        let endDate = calendar.startOfDay(for: referenceDate)
        var steps: [Int] = []
        var goalHitCount = 0

        for offset in (0..<7).reversed() {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: endDate) else { continue }
            let normalizedDate = calendar.startOfDay(for: date)
            let record = recordsByDate[normalizedDate]
            let daySteps = record?.steps ?? 0
            let dayGoal = record?.goalSteps ?? goalService.goal(for: normalizedDate) ?? fallbackGoal

            steps.append(daySteps)
            if daySteps >= dayGoal {
                goalHitCount += 1
            }
        }

        return (steps: steps, goalHitCount: goalHitCount)
    }
    
    private func buildLast4WeeksAverages(
        referenceDate: Date,
        recordsByDate: [Date: DailyStepRecord]
    ) -> [Int] {
        let endDate = calendar.startOfDay(for: referenceDate)
        var weeklyAverages: [Int] = []

        for weekOffset in (0..<4).reversed() {
            guard let weekStart = calendar.date(byAdding: .day, value: -(weekOffset * 7 + 6), to: endDate),
                  let weekEnd = calendar.date(byAdding: .day, value: -(weekOffset * 7), to: endDate) else {
                continue
            }

            var total = 0
            var dayCursor = calendar.startOfDay(for: weekStart)
            let normalizedEnd = calendar.startOfDay(for: weekEnd)

            while dayCursor <= normalizedEnd {
                total += recordsByDate[dayCursor]?.steps ?? 0
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayCursor) else { break }
                dayCursor = nextDay
            }

            weeklyAverages.append(total / 7)
        }

        return weeklyAverages
    }
    
    private func calculateTrend(from weeklyAverages: [Int]) -> String {
        guard weeklyAverages.count >= 2 else { return "stable" }
        
        let recent = weeklyAverages.suffix(2)
        guard let lastWeek = recent.first, let thisWeek = recent.last else { return "stable" }
        
        let threshold = 0.1 // 10% change threshold
        let change = lastWeek > 0 ? Double(thisWeek - lastWeek) / Double(lastWeek) : 0
        
        if change > threshold {
            return "increasing"
        } else if change < -threshold {
            return "decreasing"
        } else {
            return "stable"
        }
    }
    
    private func fetchStreakInfo() throws -> (current: Int, longest: Int) {
        let predicate = #Predicate<Streak> { streak in
            streak.deletedAt == nil
        }
        let descriptor = FetchDescriptor<Streak>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.currentCount, order: .reverse)]
        )
        
        let streaks = try modelContext.fetch(descriptor)
        
        let current = streaks.first(where: { $0.isActive })?.currentCount ?? 0
        let longest = streaks.max(by: { $0.currentCount < $1.currentCount })?.currentCount ?? 0
        
        return (current, max(current, longest))
    }
    
    private func fetchRecentWorkoutInfo() throws -> (count: Int, lastDate: Date?) {
        let thirtyDaysAgo = Date.now.addingTimeInterval(-30 * 24 * 60 * 60)
        
        let predicate = #Predicate<WorkoutSession> { session in
            session.deletedAt == nil && session.startTime >= thirtyDaysAgo
        }
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        
        let workouts = try modelContext.fetch(descriptor)
        return (workouts.count, workouts.first?.startTime)
    }
    
    private func fetchEarnedBadgeCount() throws -> Int {
        let predicate = #Predicate<EarnedBadge> { badge in
            badge.deletedAt == nil
        }
        let descriptor = FetchDescriptor<EarnedBadge>(predicate: predicate)
        
        return try modelContext.fetchCount(descriptor)
    }
}
