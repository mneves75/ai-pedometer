import Foundation
import Observation

#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
protocol StepTrackingServiceProtocol: AnyObject {
    func refreshTodayData() async
}

@Observable
@MainActor
final class StepTrackingService: StepTrackingServiceProtocol {
    private struct LiveStepBaseline: Sendable {
        let dayStart: Date
        let stepsOffset: Int
        let distanceOffset: Double
        let floorsOffset: Int
    }

    private struct LiveBaselineSeed: Sendable {
        let dayStart: Date
        let steps: Int
        let distance: Double
        let floors: Int
    }

    private let healthKitService: any HealthKitServiceProtocol
    private let motionService: any MotionServiceProtocol
    private let goalService: GoalService
    private let badgeService: BadgeService
    private let dataStore: SharedDataStore
    private let streakCalculator: any StreakCalculating
    private let userDefaults: UserDefaults
    @ObservationIgnored private let healthAuthorization: HealthKitAuthorization
    private let calculator = DailyStepCalculator()
    @ObservationIgnored private var activitySettings: ActivitySettings
    @ObservationIgnored private var liveBaseline: LiveStepBaseline?
    @ObservationIgnored private var pendingBaseline: LiveBaselineSeed?
    @ObservationIgnored private var lastLiveSnapshot: PedometerSnapshot?
    @ObservationIgnored private var liveSnapshotDayStart: Date?
    @ObservationIgnored private var lastWidgetReloadAt: Date?
    @ObservationIgnored private var lastWidgetReloadSteps: Int?

    private(set) var todaySteps: Int = 0
    private(set) var todayDistance: Double = 0
    private(set) var todayFloors: Int = 0
    private(set) var todayCalories: Double = 0
    private(set) var currentGoal: Int = AppConstants.defaultDailyGoal
    private(set) var currentStreak: Int = 0
    private(set) var lastUpdated: Date = .now
    private(set) var weeklySummaries: [DailyStepSummary] = []
    private(set) var isUsingMotionFallback: Bool = false

    init(
        healthKitService: any HealthKitServiceProtocol,
        motionService: any MotionServiceProtocol,
        healthAuthorization: HealthKitAuthorization,
        goalService: GoalService,
        badgeService: BadgeService,
        dataStore: SharedDataStore,
        streakCalculator: any StreakCalculating,
        userDefaults: UserDefaults = .standard
    ) {
        self.healthKitService = healthKitService
        self.motionService = motionService
        self.healthAuthorization = healthAuthorization
        self.goalService = goalService
        self.badgeService = badgeService
        self.dataStore = dataStore
        self.streakCalculator = streakCalculator
        self.userDefaults = userDefaults
        self.activitySettings = ActivitySettings.current(userDefaults: userDefaults)
        self.currentGoal = goalService.currentGoal
    }

    func start() async {
        refreshActivitySettings()
        if HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) {
            _ = await ensureHealthAuthorizationIfNeeded()
        } else {
            Loggers.sync.info("healthkit.authorization_skipped", metadata: ["reason": "sync_disabled"])
        }

        let startOfDay = calculator.startOfDay(for: .now)
        configureLiveUpdates(for: activitySettings.activityMode, startOfDay: startOfDay)

        await refreshTodayData()
        await refreshStreak()
    }

    func applySettingsChange() async {
        let previousSettings = activitySettings
        refreshActivitySettings()

        if activitySettings.activityMode != previousSettings.activityMode {
            let startOfDay = calculator.startOfDay(for: .now)
            configureLiveUpdates(for: activitySettings.activityMode, startOfDay: startOfDay)
        }

        await refreshTodayData()
        _ = await refreshWeeklySummaries()
        await refreshStreak()
    }

    func refreshTodayData() async {
        refreshActivitySettings()
        let startOfDay = calculator.startOfDay(for: .now)
        guard HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) else {
            isUsingMotionFallback = true
            await refreshTodayDataFromMotion(startOfDay: startOfDay)
            return
        }

        // HealthKit read access cannot be inferred reliably; always attempt queries.
        // If HealthKit is unavailable, fall back to Motion for steps.
        let healthAvailable = await ensureHealthAuthorizationIfNeeded()
        if !healthAvailable {
            isUsingMotionFallback = true
            if activitySettings.activityMode == .steps {
                await refreshTodayDataFromMotion(startOfDay: startOfDay)
            } else {
                todaySteps = 0
                todayDistance = 0
                todayFloors = 0
                todayCalories = 0
                lastUpdated = .now
                updateSharedData()
            }
            return
        }

        do {
            switch activitySettings.activityMode {
            case .steps:
                let hkSteps = try await healthKitService.fetchSteps(from: startOfDay, to: .now)

                // If HealthKit returns 0, attempt Motion as a heuristic: if Motion has steps,
                // HealthKit is likely missing read access and would otherwise show "0".
                if hkSteps == 0 {
                    if let motionSnapshot = try? await motionService.query(from: startOfDay, to: .now),
                       motionSnapshot.steps > 0 {
                        Loggers.health.info("healthkit.steps_zero_using_motion", metadata: [
                            "motionSteps": "\(motionSnapshot.steps)"
                        ])
                        isUsingMotionFallback = true
                        applyMotionSnapshot(motionSnapshot, startOfDay: startOfDay)
                        return
                    }
                }

                isUsingMotionFallback = false
                let distance = await resolveDistance(steps: hkSteps, start: startOfDay, end: .now)
                let floors = await resolveFloors(start: startOfDay, end: .now)
                todaySteps = hkSteps
                todayDistance = distance
                todayFloors = floors
                todayCalories = Double(hkSteps) * AppConstants.Metrics.caloriesPerStep
                lastUpdated = .now
                seedLiveBaseline(
                    startOfDay: startOfDay,
                    healthKitSteps: hkSteps,
                    healthKitDistance: distance,
                    healthKitFloors: floors
                )
                updateSharedData()
                evaluateBadges(steps: hkSteps, streak: nil)
                Loggers.tracking.info("steps.refresh_today", metadata: ["steps": "\(hkSteps)"])

            case .wheelchairPushes:
                isUsingMotionFallback = false
                let pushes = try await healthKitService.fetchWheelchairPushes(from: startOfDay, to: .now)
                let distance = await resolveDistance(steps: pushes, start: startOfDay, end: .now)
                let floors = await resolveFloors(start: startOfDay, end: .now)
                todaySteps = pushes
                todayDistance = distance
                todayFloors = floors
                todayCalories = Double(pushes) * AppConstants.Metrics.caloriesPerStep
                lastUpdated = .now
                liveBaseline = nil
                pendingBaseline = nil
                updateSharedData()
                evaluateBadges(steps: pushes, streak: nil)
                Loggers.tracking.info("pushes.refresh_today", metadata: ["pushes": "\(pushes)"])
            }
        } catch {
            Loggers.tracking.error("steps.refresh_failed", metadata: ["error": String(describing: error)])
            if activitySettings.activityMode == .steps {
                Loggers.motion.info("motion.refresh_fallback", metadata: [
                    "reason": "healthkit_error"
                ])
                isUsingMotionFallback = true
                await refreshTodayDataFromMotion(startOfDay: startOfDay)
            }
        }
    }

    func refreshStreak() async {
        do {
            let result = try await streakCalculator.calculateCurrentStreak()
            currentStreak = result.count
            updateSharedData()
            evaluateBadges(steps: nil, streak: result.count)
        } catch {
            Loggers.tracking.error("streak.refresh_failed", metadata: ["error": String(describing: error)])
        }
    }

    @discardableResult
    func refreshWeeklySummaries() async -> Result<Void, any Error> {
        guard HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) else {
            weeklySummaries = []
            updateSharedData()
            Loggers.sync.info("weekly.refresh_skipped", metadata: ["reason": "sync_disabled"])
            return .success(())
        }
        if !LaunchConfiguration.isUITesting() {
            let healthAvailable = await ensureHealthAuthorizationIfNeeded()
            guard healthAvailable else {
                weeklySummaries = []
                updateSharedData()
                Loggers.health.info("weekly.refresh_skipped", metadata: [
                    "reason": "healthkit_unavailable"
                ])
                return .failure(HealthKitError.notAvailable)
            }
        }

        let settings = ActivitySettings.current(userDefaults: userDefaults)

        // Fetch user's actual goal
        let effectiveGoal = goalService.currentGoal

        do {
            let summaries = try await healthKitService.fetchDailySummaries(
                days: 7,
                activityMode: settings.activityMode,
                distanceMode: settings.distanceMode,
                manualStepLength: settings.manualStepLength,
                dailyGoal: effectiveGoal
            )
            weeklySummaries = summaries.map { summary in
                let resolvedGoal = goalService.goal(for: summary.date) ?? effectiveGoal
                guard resolvedGoal != summary.goal else {
                    return summary
                }
                return DailyStepSummary(
                    date: summary.date,
                    steps: summary.steps,
                    distance: summary.distance,
                    floors: summary.floors,
                    calories: summary.calories,
                    goal: resolvedGoal
                )
            }
            updateSharedData()
            Loggers.tracking.info("weekly.refresh_success", metadata: ["count": "\(summaries.count)"])
            return .success(())
        } catch {
            Loggers.tracking.error("weekly.refresh_failed", metadata: ["error": String(describing: error)])
            return .failure(error)
        }
    }

    func updateGoal(_ goal: Int) {
        guard goal > 0 else { return }
        goalService.setGoal(goal)
        currentGoal = goal
        updateSharedData()
    }

    func updateGoalAndRefresh(_ goal: Int) async {
        guard goal > 0 else { return }
        updateGoal(goal)
        await refreshStreak()
        _ = await refreshWeeklySummaries()
    }

    /// Triggers the system prompt for Motion & Fitness permissions (if needed).
    /// This is used from onboarding/settings flows.
    func requestMotionAccessProbe() async {
        refreshActivitySettings()
        let startOfDay = calculator.startOfDay(for: .now)
        await refreshTodayDataFromMotion(startOfDay: startOfDay)
    }

    private func ensureHealthAuthorizationIfNeeded() async -> Bool {
        // Unit/UI tests use mock HealthKit services; avoid querying real authorization state,
        // but still exercise the "requestAuthorization" call so tests can verify integration.
        if LaunchConfiguration.isTesting() {
            do {
                try await healthKitService.requestAuthorization()
            } catch {
                Loggers.health.warning("healthkit.authorization_request_failed_in_tests", metadata: [
                    "error": error.localizedDescription
                ])
            }
            return true
        }

        await healthAuthorization.refreshStatus()
        switch healthAuthorization.status {
        case .unavailable:
            return false
        case .requested:
            return true
        case .shouldRequest:
            do {
                try await healthKitService.requestAuthorization()
            } catch {
                Loggers.health.warning("healthkit.authorization_request_failed", metadata: [
                    "error": error.localizedDescription
                ])
            }
            await healthAuthorization.refreshStatus()
            // Even if the user denies, HealthKit will not necessarily throw. Keep attempting queries.
            return healthAuthorization.status != .unavailable
        }
    }

    private func updateLiveData(from snapshot: PedometerSnapshot) {
        guard activitySettings.activityMode == .steps else { return }
        lastLiveSnapshot = snapshot
        seedPendingBaselineIfNeeded(using: snapshot)
        let baseline = currentBaseline()
        let steps = snapshot.steps + (baseline?.stepsOffset ?? 0)
        let distance = snapshot.distance + (baseline?.distanceOffset ?? 0)
        let floors = snapshot.floorsAscended + (baseline?.floorsOffset ?? 0)
        todaySteps = steps
        todayDistance = distance
        todayFloors = floors
        todayCalories = Double(steps) * AppConstants.Metrics.caloriesPerStep
        lastUpdated = .now
        updateSharedData()
    }

    private func refreshActivitySettings() {
        activitySettings = ActivitySettings.current(userDefaults: userDefaults)
    }

    private func configureLiveUpdates(for mode: ActivityTrackingMode, startOfDay: Date) {
        motionService.stopLiveUpdates()
        resetLiveState()

        guard mode == .steps else { return }

        liveSnapshotDayStart = startOfDay
        do {
            try motionService.startLiveUpdates(from: startOfDay) { [weak self] snapshot in
                guard let self else { return }
                self.updateLiveData(from: snapshot)
            }
        } catch {
            Loggers.motion.warning("motion.start_failed", metadata: ["error": String(describing: error)])
        }
    }

    private func resetLiveState() {
        liveBaseline = nil
        pendingBaseline = nil
        lastLiveSnapshot = nil
        liveSnapshotDayStart = nil
    }

    private func evaluateBadges(steps: Int?, streak: Int?) {
        var earnedTypes = badgeService.earnedBadgeTypes()
        
        if let steps {
            let stepBadges = BadgeDefinitions.all.filter {
                $0.type.category == .steps && steps >= $0.requiredValue
            }
            for badge in stepBadges {
                let unlocked = badgeService.unlock(
                    badge.type,
                    metadata: [
                        "steps": "\(steps)",
                        "required": "\(badge.requiredValue)"
                    ],
                    existingBadgeTypes: earnedTypes
                )
                if unlocked {
                    earnedTypes.insert(badge.type)
                }
            }
        }
        
        if let streak {
            let streakBadges = BadgeDefinitions.all.filter {
                $0.type.category == .streak && streak >= $0.requiredValue
            }
            for badge in streakBadges {
                let unlocked = badgeService.unlock(
                    badge.type,
                    metadata: [
                        "streak": "\(streak)",
                        "required": "\(badge.requiredValue)"
                    ],
                    existingBadgeTypes: earnedTypes
                )
                if unlocked {
                    earnedTypes.insert(badge.type)
                }
            }
        }
    }

    private func fetchTodayActivityCount(from startOfDay: Date) async throws -> Int {
        switch activitySettings.activityMode {
        case .steps:
            return try await healthKitService.fetchSteps(from: startOfDay, to: .now)
        case .wheelchairPushes:
            return try await healthKitService.fetchWheelchairPushes(from: startOfDay, to: .now)
        }
    }

    private func resolveDistance(steps: Int, start: Date, end: Date) async -> Double {
        switch activitySettings.distanceMode {
        case .manual:
            return Double(steps) * activitySettings.manualStepLength
        case .automatic:
            do {
                return try await healthKitService.fetchDistance(from: start, to: end)
            } catch {
                Loggers.health.warning("healthkit.distance_unavailable", metadata: [
                    "error": error.localizedDescription
                ])
                return Double(steps) * activitySettings.manualStepLength
            }
        }
    }

    private func resolveFloors(start: Date, end: Date) async -> Int {
        do {
            return try await healthKitService.fetchFloors(from: start, to: end)
        } catch {
            Loggers.health.warning("healthkit.floors_unavailable", metadata: [
                "error": error.localizedDescription
            ])
            return 0
        }
    }

    private func refreshTodayDataFromMotion(startOfDay: Date) async {
        guard activitySettings.activityMode == .steps else {
            Loggers.motion.info("motion.refresh_skipped", metadata: ["reason": "unsupported_mode"])
            return
        }
        do {
            let snapshot = try await motionService.query(from: startOfDay, to: .now)
            applyMotionSnapshot(snapshot, startOfDay: startOfDay)
        } catch {
            Loggers.motion.warning("motion.refresh_failed", metadata: ["error": String(describing: error)])
        }
    }

    private func applyMotionSnapshot(_ snapshot: PedometerSnapshot, startOfDay: Date) {
        let distance = resolveMotionDistance(snapshot: snapshot)
        todaySteps = snapshot.steps
        todayDistance = distance
        todayFloors = snapshot.floorsAscended
        todayCalories = Double(snapshot.steps) * AppConstants.Metrics.caloriesPerStep
        lastUpdated = .now
        seedMotionBaseline(snapshot: snapshot, startOfDay: startOfDay)
        updateSharedData()
        evaluateBadges(steps: snapshot.steps, streak: nil)
        Loggers.tracking.info("steps.refresh_today_motion", metadata: ["steps": "\(snapshot.steps)"])
    }

    private func resolveMotionDistance(snapshot: PedometerSnapshot) -> Double {
        switch activitySettings.distanceMode {
        case .manual:
            return Double(snapshot.steps) * activitySettings.manualStepLength
        case .automatic:
            if snapshot.distance > 0 {
                return snapshot.distance
            }
            return Double(snapshot.steps) * activitySettings.manualStepLength
        }
    }

    private func seedMotionBaseline(snapshot: PedometerSnapshot, startOfDay: Date) {
        lastLiveSnapshot = snapshot
        liveSnapshotDayStart = startOfDay
        liveBaseline = LiveStepBaseline(
            dayStart: startOfDay,
            stepsOffset: 0,
            distanceOffset: 0,
            floorsOffset: 0
        )
        pendingBaseline = nil
    }

    private func updateSharedData() {
        let shared = SharedStepData(
            todaySteps: todaySteps,
            goalSteps: currentGoal,
            goalProgress: Double(todaySteps) / Double(max(currentGoal, 1)),
            currentStreak: currentStreak,
            lastUpdated: lastUpdated,
            weeklySteps: weeklySummaries.map(\.steps)
        )
        dataStore.update(shared)
        WatchSyncService.shared.send(stepData: shared)

        // Widgets should reflect new data, but StepTrackingService can update very frequently.
        // Throttle reloads to avoid spamming WidgetKit (and to reduce battery impact).
        reloadWidgetsIfNeeded(steps: todaySteps)
    }

    private func reloadWidgetsIfNeeded(steps: Int) {
        #if canImport(WidgetKit)
        let now = Date.now
        let minInterval: TimeInterval = 5 * 60
        let minDeltaSteps = 200

        if let last = lastWidgetReloadAt, now.timeIntervalSince(last) < minInterval {
            return
        }
        if let lastSteps = lastWidgetReloadSteps, abs(steps - lastSteps) < minDeltaSteps {
            return
        }

        lastWidgetReloadAt = now
        lastWidgetReloadSteps = steps

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.stepCount)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.progressRing)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.weeklyChart)
        #endif
    }

    private func currentBaseline() -> LiveStepBaseline? {
        guard let baseline = liveBaseline else { return nil }
        guard !calculator.didCrossMidnight(previousDate: baseline.dayStart, currentDate: .now) else {
            liveBaseline = nil
            return nil
        }
        return baseline
    }

    private func seedLiveBaseline(
        startOfDay: Date,
        healthKitSteps: Int,
        healthKitDistance: Double,
        healthKitFloors: Int
    ) {
        // Keep live updates at max(HealthKit, CMPedometer) to avoid double-counting Apple Watch steps.
        guard activitySettings.activityMode == .steps else {
            liveBaseline = nil
            pendingBaseline = nil
            return
        }
        if let snapshot = lastLiveSnapshot,
           let snapshotDayStart = liveSnapshotDayStart,
           !calculator.didCrossMidnight(previousDate: snapshotDayStart, currentDate: startOfDay) {
            liveBaseline = LiveStepBaseline(
                dayStart: startOfDay,
                stepsOffset: max(healthKitSteps - snapshot.steps, 0),
                distanceOffset: max(healthKitDistance - snapshot.distance, 0),
                floorsOffset: max(healthKitFloors - snapshot.floorsAscended, 0)
            )
            pendingBaseline = nil
        } else {
            pendingBaseline = LiveBaselineSeed(
                dayStart: startOfDay,
                steps: healthKitSteps,
                distance: healthKitDistance,
                floors: healthKitFloors
            )
            liveBaseline = nil
        }
    }

    private func seedPendingBaselineIfNeeded(using snapshot: PedometerSnapshot) {
        guard let pendingBaseline else { return }
        guard !calculator.didCrossMidnight(previousDate: pendingBaseline.dayStart, currentDate: .now) else {
            self.pendingBaseline = nil
            return
        }
        liveBaseline = LiveStepBaseline(
            dayStart: pendingBaseline.dayStart,
            stepsOffset: max(pendingBaseline.steps - snapshot.steps, 0),
            distanceOffset: max(pendingBaseline.distance - snapshot.distance, 0),
            floorsOffset: max(pendingBaseline.floors - snapshot.floorsAscended, 0)
        )
        self.pendingBaseline = nil
    }
}
