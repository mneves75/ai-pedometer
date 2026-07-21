import Foundation
import Observation

#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
protocol StepTrackingServiceProtocol: AnyObject {
    func refreshTodayData() async
    func flushSharedData()
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
    private let calculator: DailyStepCalculator
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let sendToWatch: @MainActor (SharedStepData) -> Void
    @ObservationIgnored private var activitySettings: ActivitySettings
    @ObservationIgnored private var liveBaseline: LiveStepBaseline?
    @ObservationIgnored private var pendingBaseline: LiveBaselineSeed?
    @ObservationIgnored private var lastLiveSnapshot: PedometerSnapshot?
    @ObservationIgnored private var liveSnapshotDayStart: Date?
    @ObservationIgnored private var lastWidgetReloadAt: Date?
    @ObservationIgnored private var lastWidgetReloadSteps: Int?
    @ObservationIgnored private var refreshChain: Task<Void, Never>?
    @ObservationIgnored private var liveStreamGeneration = 0
    @ObservationIgnored private var streakRefreshGeneration = 0
    @ObservationIgnored private var weeklyRefreshGeneration = 0

    private(set) var todaySteps: Int = 0
    private(set) var todayDistance: Double = 0
    private(set) var todayFloors: Int = 0
    private(set) var todayCalories: Double = 0
    private(set) var todayHeartRateSample: HeartRateSample?

    /// Convenience for callers that only want the BPM value (e.g. AI prompts). Kept as a
    /// computed property so the `Observable` macro still observes through the underlying
    /// `todayHeartRateSample` storage.
    var todayHeartRateBPM: Double? {
        todayHeartRateSample?.bpm
    }
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
        userDefaults: UserDefaults = .standard,
        calculator: DailyStepCalculator = DailyStepCalculator(),
        now: @escaping @MainActor () -> Date = { .now },
        sendToWatch: @escaping @MainActor (SharedStepData) -> Void = { WatchSyncService.shared.send(stepData: $0) }
    ) {
        self.healthKitService = healthKitService
        self.motionService = motionService
        self.healthAuthorization = healthAuthorization
        self.goalService = goalService
        self.badgeService = badgeService
        self.dataStore = dataStore
        self.streakCalculator = streakCalculator
        self.userDefaults = userDefaults
        self.calculator = calculator
        self.now = now
        self.sendToWatch = sendToWatch
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

        let startOfDay = calculator.startOfDay(for: now())
        configureLiveUpdates(for: activitySettings.activityMode, startOfDay: startOfDay)

        await refreshTodayData()
        await refreshStreak()
    }

    func applySettingsChange() async {
        let previousSettings = activitySettings
        refreshActivitySettings()

        if activitySettings.activityMode != previousSettings.activityMode {
            let startOfDay = calculator.startOfDay(for: now())
            configureLiveUpdates(for: activitySettings.activityMode, startOfDay: startOfDay)
        }

        await refreshTodayData()
        _ = await refreshWeeklySummaries()
        await refreshStreak()
    }

    func refreshTodayData() async {
        // Serialize overlapping refreshes. This method is `async` with many `await`
        // suspension points, and several independent callers (app foreground, background
        // refresh, pull-to-refresh, settings changes) can invoke it concurrently. Without
        // serialization two interleaved runs can overwrite `todaySteps`/`liveBaseline` with an
        // older-but-stale HealthKit read, making the displayed count visibly regress and
        // corrupting the live baseline until the next clean refresh. Chaining each run after
        // the previous one guarantees every invocation's body executes atomically, in order.
        let previous = refreshChain
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard !Task.isCancelled else { return }
            await self?.performRefreshTodayData()
        }
        refreshChain = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performRefreshTodayData() async {
        guard !Task.isCancelled else { return }
        refreshActivitySettings()
        let currentDate = now()
        let startOfDay = calculator.startOfDay(for: currentDate)
        guard HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) else {
            isUsingMotionFallback = true
            if activitySettings.activityMode == .steps {
                await refreshTodayDataFromMotion(startOfDay: startOfDay)
            } else {
                clearCurrentActivityData(markStale: true)
            }
            return
        }

        // HealthKit read access cannot be inferred reliably; always attempt queries.
        // If HealthKit is unavailable, fall back to Motion for steps.
        let healthAvailable = await ensureHealthAuthorizationIfNeeded()
        guard !Task.isCancelled else { return }
        if !healthAvailable {
            isUsingMotionFallback = true
            if activitySettings.activityMode == .steps {
                await refreshTodayDataFromMotion(startOfDay: startOfDay)
            } else {
                todaySteps = 0
                todayDistance = 0
                todayFloors = 0
                todayCalories = 0
                // HealthKit is unavailable for every read type, so the latest heart-rate value
                // can no longer be trusted. Clear it explicitly here (the steps path clears it
                // implicitly by failing earlier).
                todayHeartRateSample = nil
                lastUpdated = currentDate
                updateSharedData()
            }
            return
        }

        do {
            switch activitySettings.activityMode {
            case .steps:
                let hkSteps = try await healthKitService.fetchSteps(from: startOfDay, to: currentDate)
                guard !Task.isCancelled else { return }

                // If HealthKit returns 0, attempt Motion as a heuristic: if Motion has steps,
                // HealthKit is likely missing read access and would otherwise show "0".
                if hkSteps == 0 {
                    do {
                        let motionSnapshot = try await motionService.query(from: startOfDay, to: currentDate)
                        guard !Task.isCancelled else { return }
                        if motionSnapshot.steps > 0 {
                            Loggers.health.info("healthkit.steps_zero_using_motion", metadata: [
                                "motionSteps": "\(motionSnapshot.steps)"
                            ])
                            isUsingMotionFallback = true
                            // HR is independent of step samples. Always attempt a fresh fetch so we
                            // honor the latest BPM (or fade to "No Data" when there is no recent sample).
                            let sample = await resolveLatestHeartRate(start: startOfDay, end: currentDate)
                            guard !Task.isCancelled else { return }
                            let attempt = HeartRateRefreshAttempt(attempted: true, sample: sample)
                            applyMotionSnapshot(
                                motionSnapshot,
                                startOfDay: startOfDay,
                                heartRate: attempt
                            )
                            return
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        Loggers.health.info("healthkit.steps_zero_using_motion", metadata: [
                            "motionError": String(describing: error)
                        ])
                        isUsingMotionFallback = true
                        let sample = await resolveLatestHeartRate(start: startOfDay, end: currentDate)
                        guard !Task.isCancelled else { return }
                        let attempt = HeartRateRefreshAttempt(attempted: true, sample: sample)
                        clearCurrentActivityData(markStale: true, heartRate: attempt)
                        return
                    }
                }

                isUsingMotionFallback = false
                async let distanceResult = resolveDistance(steps: hkSteps, start: startOfDay, end: currentDate)
                async let floorsResult = resolveFloors(start: startOfDay, end: currentDate)
                async let heartRateResult = resolveLatestHeartRate(start: startOfDay, end: currentDate)
                let (distance, floors, heartRate) = await (distanceResult, floorsResult, heartRateResult)
                guard !Task.isCancelled else { return }
                todaySteps = hkSteps
                todayDistance = distance
                todayFloors = floors
                todayCalories = Double(hkSteps) * AppConstants.Metrics.caloriesPerStep
                todayHeartRateSample = heartRate
                lastUpdated = currentDate
                seedLiveBaseline(
                    startOfDay: startOfDay,
                    healthKitSteps: hkSteps,
                    healthKitDistance: distance,
                    healthKitFloors: floors
                )
                updateSharedData()
                evaluateBadges(steps: hkSteps, streak: nil, distance: distance)
                Loggers.tracking.info("steps.refresh_today", metadata: ["steps": "\(hkSteps)"])

            case .wheelchairPushes:
                isUsingMotionFallback = false
                let pushes = try await healthKitService.fetchWheelchairPushes(from: startOfDay, to: currentDate)
                guard !Task.isCancelled else { return }
                async let distanceResult = resolveDistance(steps: pushes, start: startOfDay, end: currentDate)
                async let floorsResult = resolveFloors(start: startOfDay, end: currentDate)
                async let heartRateResult = resolveLatestHeartRate(start: startOfDay, end: currentDate)
                let (distance, floors, heartRate) = await (distanceResult, floorsResult, heartRateResult)
                guard !Task.isCancelled else { return }
                todaySteps = pushes
                todayDistance = distance
                todayFloors = floors
                todayCalories = Double(pushes) * AppConstants.Metrics.caloriesPerStep
                todayHeartRateSample = heartRate
                lastUpdated = currentDate
                liveBaseline = nil
                pendingBaseline = nil
                updateSharedData()
                evaluateBadges(steps: pushes, streak: nil, distance: distance)
                Loggers.tracking.info("pushes.refresh_today", metadata: ["pushes": "\(pushes)"])
            }
        } catch {
            guard !Task.isCancelled else { return }
            Loggers.tracking.error("steps.refresh_failed", metadata: ["error": String(describing: error)])
            if activitySettings.activityMode == .steps {
                Loggers.motion.info("motion.refresh_fallback", metadata: [
                    "reason": "healthkit_error"
                ])
                isUsingMotionFallback = true
                await refreshTodayDataFromMotion(startOfDay: startOfDay)
            } else {
                clearCurrentActivityData(markStale: true)
            }
        }
    }

    func refreshStreak() async {
        streakRefreshGeneration += 1
        let generation = streakRefreshGeneration
        do {
            let result = try await streakCalculator.calculateCurrentStreak()
            guard generation == streakRefreshGeneration else { return }
            currentStreak = result.count
            updateSharedData()
            evaluateBadges(steps: nil, streak: result.count)
        } catch {
            guard generation == streakRefreshGeneration else { return }
            Loggers.tracking.error("streak.refresh_failed", metadata: ["error": String(describing: error)])
        }
    }

    @discardableResult
    func refreshWeeklySummaries() async -> Result<Void, any Error> {
        weeklyRefreshGeneration += 1
        let generation = weeklyRefreshGeneration
        guard HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) else {
            weeklySummaries = []
            updateSharedData()
            Loggers.sync.info("weekly.refresh_skipped", metadata: ["reason": "sync_disabled"])
            return .success(())
        }
        if !LaunchConfiguration.isUITesting() {
            let healthAvailable = await ensureHealthAuthorizationIfNeeded()
            guard generation == weeklyRefreshGeneration else { return .success(()) }
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
            guard generation == weeklyRefreshGeneration else { return .success(()) }
            weeklySummaries = summaries.map { summary in
                let resolvedGoal = goalService.goal(for: summary.date) ?? effectiveGoal
                let mergedSummary = mergeCurrentDaySummaryIfNeeded(summary, activityMode: settings.activityMode)
                guard resolvedGoal != summary.goal else {
                    return mergedSummary
                }
                return DailyStepSummary(
                    date: mergedSummary.date,
                    steps: mergedSummary.steps,
                    distance: mergedSummary.distance,
                    floors: mergedSummary.floors,
                    calories: mergedSummary.calories,
                    goal: resolvedGoal
                )
            }
            updateSharedData()
            Loggers.tracking.info("weekly.refresh_success", metadata: ["count": "\(summaries.count)"])
            return .success(())
        } catch {
            guard generation == weeklyRefreshGeneration else { return .success(()) }
            Loggers.tracking.error("weekly.refresh_failed", metadata: ["error": String(describing: error)])
            return .failure(error)
        }
    }

    @discardableResult
    func updateGoal(_ goal: Int) -> Bool {
        guard goal > 0 else { return false }
        guard goalService.setGoal(goal) else { return false }
        currentGoal = goal
        updateSharedData()
        return true
    }

    @discardableResult
    func updateGoalAndRefresh(_ goal: Int) async -> Bool {
        guard updateGoal(goal) else { return false }
        await refreshStreak()
        _ = await refreshWeeklySummaries()
        return true
    }

    /// Triggers the system prompt for Motion & Fitness permissions (if needed).
    /// This is used from onboarding/settings flows.
    func requestMotionAccessProbe() async {
        refreshActivitySettings()
        let startOfDay = calculator.startOfDay(for: now())
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

    private func updateLiveData(from snapshot: PedometerSnapshot, generation: Int) {
        guard generation == liveStreamGeneration else { return }
        guard activitySettings.activityMode == .steps else { return }
        let currentDate = now()
        let currentDayStart = calculator.startOfDay(for: currentDate)
        if let liveSnapshotDayStart,
           calculator.didCrossMidnight(previousDate: liveSnapshotDayStart, currentDate: currentDate) {
            resetTodayForRollover(at: currentDate)
            configureLiveUpdates(for: .steps, startOfDay: currentDayStart)
            return
        }
        lastLiveSnapshot = snapshot
        seedPendingBaselineIfNeeded(using: snapshot, currentDate: currentDate)
        let baseline = currentBaseline(currentDate: currentDate)
        let steps = snapshot.steps + (baseline?.stepsOffset ?? 0)
        let distance = snapshot.distance + (baseline?.distanceOffset ?? 0)
        let floors = snapshot.floorsAscended + (baseline?.floorsOffset ?? 0)
        todaySteps = steps
        todayDistance = distance
        todayFloors = floors
        todayCalories = Double(steps) * AppConstants.Metrics.caloriesPerStep
        lastUpdated = currentDate
        updateSharedData()
    }

    private func refreshActivitySettings() {
        activitySettings = ActivitySettings.current(userDefaults: userDefaults)
    }

    private func configureLiveUpdates(for mode: ActivityTrackingMode, startOfDay: Date) {
        liveStreamGeneration &+= 1
        let generation = liveStreamGeneration
        motionService.stopLiveUpdates()
        resetLiveState()

        guard mode == .steps else { return }

        liveSnapshotDayStart = startOfDay
        do {
            try motionService.startLiveUpdates(from: startOfDay) { [weak self] snapshot in
                guard let self else { return }
                self.updateLiveData(from: snapshot, generation: generation)
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

    private func resetTodayForRollover(at date: Date) {
        todaySteps = 0
        todayDistance = 0
        todayFloors = 0
        todayCalories = 0
        todayHeartRateSample = nil
        lastUpdated = date
        updateSharedData()
    }

    private func evaluateBadges(steps: Int?, streak: Int?, distance: Double? = nil) {
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

        if let distance {
            // `distance` is the day's walking/running distance in meters, matched against the
            // meter thresholds in BadgeDefinitions. Negative/NaN distances can't clear any
            // threshold, so `Int(...)` is guarded to avoid trapping on non-finite input.
            let distanceMeters = distance.isFinite ? Int(distance) : 0
            let distanceBadges = BadgeDefinitions.all.filter {
                $0.type.category == .distance && distanceMeters >= $0.requiredValue
            }
            for badge in distanceBadges {
                let unlocked = badgeService.unlock(
                    badge.type,
                    metadata: [
                        "distance": "\(distanceMeters)",
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

    private func resolveDistance(steps: Int, start: Date, end: Date) async -> Double {
        switch activitySettings.distanceMode {
        case .manual:
            return Double(steps) * activitySettings.manualStepLength
        case .automatic:
            do {
                switch activitySettings.activityMode {
                case .steps:
                    return try await healthKitService.fetchDistance(from: start, to: end)
                case .wheelchairPushes:
                    // Surface the real `distanceWheelchair` sample. Previous behavior hardcoded
                    // zero and silently shipped a worse UX to wheelchair users.
                    return try await healthKitService.fetchWheelchairDistance(from: start, to: end)
                }
            } catch {
                Loggers.health.warning("healthkit.distance_unavailable", metadata: [
                    "error": error.localizedDescription,
                    "mode": activitySettings.activityMode.rawValue
                ])
                // Walking mode has a meaningful manual fallback (steps × stride length); wheelchair
                // mode has no analogous multiplier, so we return 0 rather than invent a number.
                return activitySettings.activityMode == .steps
                    ? Double(steps) * activitySettings.manualStepLength
                    : 0
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

    private func resolveLatestHeartRate(start: Date, end: Date) async -> HeartRateSample? {
        do {
            return try await healthKitService.fetchLatestHeartRateSample(from: start, to: end)
        } catch {
            Loggers.health.warning("healthkit.heart_rate_unavailable", metadata: [
                "error": error.localizedDescription
            ])
            return nil
        }
    }

    private struct HeartRateRefreshAttempt {
        let attempted: Bool
        let sample: HeartRateSample?
    }

    private func refreshTodayDataFromMotion(startOfDay: Date) async {
        guard !Task.isCancelled else { return }
        guard activitySettings.activityMode == .steps else {
            Loggers.motion.info("motion.refresh_skipped", metadata: ["reason": "unsupported_mode"])
            clearCurrentActivityData(markStale: true)
            return
        }
        // Heart-rate samples are independent of the step path. When sync is enabled we explicitly
        // re-query HealthKit so a transient step-query failure never wipes a real Apple Watch BPM,
        // and so the display naturally fades to "No Data" when there is no recent sample. Sync
        // disabled means we must not query HealthKit, so clear any previously cached BPM.
        let heartRateAttempt: HeartRateRefreshAttempt
        if HealthKitSyncSettings.isEnabled(userDefaults: userDefaults) {
            let sample = await resolveLatestHeartRate(start: startOfDay, end: now())
            guard !Task.isCancelled else { return }
            heartRateAttempt = HeartRateRefreshAttempt(attempted: true, sample: sample)
        } else {
            heartRateAttempt = HeartRateRefreshAttempt(attempted: true, sample: nil)
        }
        do {
            let snapshot = try await motionService.query(from: startOfDay, to: now())
            guard !Task.isCancelled else { return }
            applyMotionSnapshot(snapshot, startOfDay: startOfDay, heartRate: heartRateAttempt)
        } catch {
            guard !Task.isCancelled else { return }
            Loggers.motion.warning("motion.refresh_failed", metadata: ["error": String(describing: error)])
            clearCurrentActivityData(markStale: true, heartRate: heartRateAttempt)
        }
    }

    private func applyMotionSnapshot(
        _ snapshot: PedometerSnapshot,
        startOfDay: Date,
        heartRate: HeartRateRefreshAttempt = HeartRateRefreshAttempt(attempted: false, sample: nil)
    ) {
        let distance = resolveMotionDistance(snapshot: snapshot)
        todaySteps = snapshot.steps
        todayDistance = distance
        todayFloors = snapshot.floorsAscended
        todayCalories = Double(snapshot.steps) * AppConstants.Metrics.caloriesPerStep
        // Only mutate HR when we actually queried for it. That keeps a known-good sample on screen
        // through transient step-query failures, while still flipping to "No Data" the moment a
        // refresh attempt comes back empty (the Apple Watch app's behavior).
        // See implementation-notes.html#finding-heart-rate-clobber.
        if heartRate.attempted {
            todayHeartRateSample = heartRate.sample
        }
        lastUpdated = now()
        seedMotionBaseline(snapshot: snapshot, startOfDay: startOfDay)
        updateSharedData()
        evaluateBadges(steps: snapshot.steps, streak: nil, distance: distance)
        Loggers.tracking.info("steps.refresh_today_motion", metadata: ["steps": "\(snapshot.steps)"])
    }

    private func clearCurrentActivityData(
        markStale: Bool,
        heartRate: HeartRateRefreshAttempt = HeartRateRefreshAttempt(attempted: true, sample: nil)
    ) {
        todaySteps = 0
        todayDistance = 0
        todayFloors = 0
        todayCalories = 0
        if heartRate.attempted {
            todayHeartRateSample = heartRate.sample
        }
        lastUpdated = markStale ? .distantPast : now()
        resetLiveState()
        updateSharedData()
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
        sendToWatch(shared)

        // Widgets should reflect new data, but StepTrackingService can update very frequently.
        // Throttle reloads to avoid spamming WidgetKit (and to reduce battery impact).
        reloadWidgetsIfNeeded(steps: todaySteps)
    }

    func flushSharedData() {
        dataStore.flush()
    }

    private func reloadWidgetsIfNeeded(steps: Int) {
        #if canImport(WidgetKit)
        let now = now()
        guard Self.shouldReloadWidgets(
            lastReloadAt: lastWidgetReloadAt,
            lastReloadSteps: lastWidgetReloadSteps,
            newSteps: steps,
            now: now
        ) else {
            return
        }

        // WidgetKit may service the reload immediately, so make the latest payload durable first.
        dataStore.flush()
        lastWidgetReloadAt = now
        lastWidgetReloadSteps = steps

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.stepCount)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.progressRing)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKinds.weeklyChart)
        Signposts.sync.event("WidgetTimelinesReloaded")
        #endif
    }

    /// Pure decision for the widget-reload throttle. Exposed at module scope so it can be
    /// tested without standing up `WidgetCenter`.
    ///
    /// Rules (in order):
    /// 1. Never reloaded yet → reload.
    /// 2. Day changed since the last push → reload (defeats the post-midnight blackout where
    ///    `0 - yesterdaysTotal < 0` and the delta guard suppresses the reload, leaving the
    ///    home-screen widget stuck on yesterday's count for up to 5 minutes).
    /// 3. Within 5-minute throttle AND step delta &lt; 200 → skip.
    /// 4. Otherwise → reload.
    static func shouldReloadWidgets(
        lastReloadAt: Date?,
        lastReloadSteps: Int?,
        newSteps: Int,
        now: Date,
        calendar: Calendar = .autoupdatingCurrent,
        minInterval: TimeInterval = 5 * 60,
        minDeltaSteps: Int = 200
    ) -> Bool {
        guard let last = lastReloadAt else { return true }

        if !calendar.isDate(last, inSameDayAs: now) {
            return true
        }

        if now.timeIntervalSince(last) < minInterval {
            if let lastSteps = lastReloadSteps, abs(newSteps - lastSteps) < minDeltaSteps {
                return false
            }
        }

        return true
    }

    private func mergeCurrentDaySummaryIfNeeded(
        _ summary: DailyStepSummary,
        activityMode: ActivityTrackingMode
    ) -> DailyStepSummary {
        guard activityMode == .steps else { return summary }
        // Use the service's `calculator` (same calendar instance as every other day-boundary
        // decision here) instead of a one-off `Calendar.current`, so the current-day merge stays
        // consistent with `seedLiveBaseline`/`currentBaseline` and is exercisable under a fixed
        // test calendar.
        guard !calculator.didCrossMidnight(previousDate: summary.date, currentDate: now()) else {
            return summary
        }

        let mergedSteps = max(summary.steps, todaySteps)
        guard mergedSteps != summary.steps else { return summary }

        let mergedDistance = max(summary.distance, todayDistance)
        let mergedFloors = max(summary.floors, todayFloors)
        return DailyStepSummary(
            date: summary.date,
            steps: mergedSteps,
            distance: mergedDistance,
            floors: mergedFloors,
            calories: Double(mergedSteps) * AppConstants.Metrics.caloriesPerStep,
            goal: summary.goal
        )
    }

    private func currentBaseline(currentDate: Date) -> LiveStepBaseline? {
        guard let baseline = liveBaseline else { return nil }
        guard !calculator.didCrossMidnight(previousDate: baseline.dayStart, currentDate: currentDate) else {
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

    private func seedPendingBaselineIfNeeded(using snapshot: PedometerSnapshot, currentDate: Date) {
        guard let pendingBaseline else { return }
        guard !calculator.didCrossMidnight(previousDate: pendingBaseline.dayStart, currentDate: currentDate) else {
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
