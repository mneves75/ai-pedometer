import SwiftUI
import SwiftData
import HealthKit
import UIKit

@main
@MainActor
struct AIPedometerApp: App {
    @AppStorage(AppConstants.UserDefaultsKeys.onboardingCompleted) private var onboardingCompleted = false
    @State private var healthAuthorization: HealthKitAuthorization
    @State private var motionAuthorization: MotionAuthorization
    @State private var sharedDataStore: SharedDataStore
    @State private var stepTrackingService: StepTrackingService
    @State private var foundationModelsService: FoundationModelsService
    @State private var insightService: InsightService
    @State private var coachService: CoachService
    @State private var trainingPlanService: TrainingPlanService
    @State private var badgeService: BadgeService
    @State private var healthKitSyncService: HealthKitSyncService
    @State private var demoModeStore: DemoModeStore
    @State private var workoutSessionController: WorkoutSessionController
    @State private var notificationService: NotificationService
    @State private var smartNotificationService: SmartNotificationService
    @State private var tipJarStore: TipJarStore
    @State private var startupCoordinator: AppStartupCoordinator
    @State private var lifecycleCoordinator: AppLifecycleCoordinator
    private let persistence = PersistenceController.shared
    private let backgroundService: BackgroundTaskService
    private let metricKitService = MetricKitService.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if LaunchConfiguration.isTesting() && LaunchConfiguration.shouldResetState() {
            Self.resetStateForUITesting()
        }
        if LaunchConfiguration.isTesting() && LaunchConfiguration.shouldSkipOnboarding() {
            onboardingCompleted = true
            UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.onboardingCompleted)
        }
        if LaunchConfiguration.isTesting(), let forced = LaunchConfiguration.forcedHealthKitSyncEnabled() {
            // Keep UI tests deterministic: allow forcing the sync setting without relying on flakey toggle interactions.
            UserDefaults.standard.set(forced, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
            if let suiteDefaults = UserDefaults(suiteName: AppConstants.appGroupID) {
                suiteDefaults.set(forced, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
            }
        }
        if LaunchConfiguration.isTesting() {
            Loggers.app.info(
                "ui_testing.arguments",
                metadata: ["args": ProcessInfo.processInfo.arguments.joined(separator: " ")]
            )
            UIView.setAnimationsEnabled(false)
        }
        // Create shared dependencies once - single source of truth
        let sharedHealthStore = HKHealthStore()
        let healthAuth = HealthKitAuthorization(healthStore: sharedHealthStore)
        let motionAuth = MotionAuthorization()
        let motionService = MotionService()
        let dataStore = SharedDataStore()
        let goalService = GoalService(persistence: PersistenceController.shared)
        let streakCalculator = StreakCalculator(stepAggregator: StepDataAggregator(), goalService: goalService)
        let fmService = FoundationModelsService()
        let modelContext = PersistenceController.shared.container.mainContext
        let demoStore = DemoModeStore()
        let primaryHealthKitService = HealthKitService(
            healthStore: sharedHealthStore,
            authorization: healthAuth
        )
        let healthKitService = HealthKitServiceFallback(
            primary: primaryHealthKitService,
            demoModeStore: demoStore
        )
        let workoutMetricsSource: any WorkoutLiveMetricsSource
        let liveActivityManager: any LiveActivityManaging
        if LaunchConfiguration.isUITesting() {
            workoutMetricsSource = DemoLiveMetricsSource()
            liveActivityManager = NoopLiveActivityManager()
        } else {
            workoutMetricsSource = MotionLiveMetricsSource(motionService: MotionService())
            liveActivityManager = LiveActivityManager()
        }

        let badges = BadgeService(persistence: PersistenceController.shared)
        badges.configure(with: fmService)

        // Create StepTrackingService with shared dependencies
        let trackingService = StepTrackingService(
            healthKitService: healthKitService,
            motionService: motionService,
            healthAuthorization: healthAuth,
            goalService: goalService,
            badgeService: badges,
            dataStore: dataStore,
            streakCalculator: streakCalculator
        )

        let syncService = HealthKitSyncService(
            healthKitService: healthKitService,
            modelContext: modelContext,
            goalService: goalService
        )

        // Initialize all @State properties
        _healthAuthorization = State(initialValue: healthAuth)
        _motionAuthorization = State(initialValue: motionAuth)
        _sharedDataStore = State(initialValue: dataStore)
        _stepTrackingService = State(initialValue: trackingService)
        _healthKitSyncService = State(initialValue: syncService)
        let insightService = InsightService(
            foundationModelsService: fmService,
            healthKitService: healthKitService,
            goalService: goalService,
            dataStore: dataStore
        )
        let coachService = CoachService(
            foundationModelsService: fmService,
            healthKitService: healthKitService,
            goalService: goalService
        )

        _foundationModelsService = State(initialValue: fmService)
        _insightService = State(initialValue: insightService)
        _coachService = State(initialValue: coachService)
        _trainingPlanService = State(initialValue: TrainingPlanService(
            foundationModelsService: fmService,
            healthKitService: healthKitService,
            goalService: goalService,
            modelContext: modelContext
        ))
        _workoutSessionController = State(initialValue: WorkoutSessionController(
            modelContext: modelContext,
            healthKitService: healthKitService,
            metricsSource: workoutMetricsSource,
            liveActivityManager: liveActivityManager
        ))
        _demoModeStore = State(initialValue: demoStore)
        _notificationService = State(initialValue: NotificationService())
        _smartNotificationService = State(initialValue: SmartNotificationService(
            foundationModelsService: fmService,
            healthKitService: healthKitService,
            goalService: goalService
        ))
        _tipJarStore = State(initialValue: TipJarStore())

        _badgeService = State(initialValue: badges)

        let backgroundTaskService = BackgroundTaskService(stepTrackingService: trackingService)
        backgroundService = backgroundTaskService

        _startupCoordinator = State(initialValue: AppStartupCoordinator(
            isTesting: { LaunchConfiguration.isTesting() },
            refreshHealthAuthorization: { Task { await healthAuth.refreshStatus() } },
            refreshMotionAuthorization: { motionAuth.refreshStatus() },
            registerBackgroundTasks: { backgroundTaskService.registerTasks() },
            scheduleAppRefresh: { backgroundTaskService.scheduleAppRefresh() },
            startWatchSync: { WatchSyncService.shared.start() },
            startStepTracking: { await trackingService.start() },
            performInitialSync: { [syncService] in
                do {
                    if syncService.needsColdStartSync() {
                        try await syncService.performColdStartSync()
                    } else if syncService.shouldPerformForegroundSync() {
                        try await syncService.performIncrementalSync()
                    }
                } catch {
                    Loggers.sync.error("sync.initial_sync_failed", metadata: ["error": error.localizedDescription])
                }
            }
        ))

        _lifecycleCoordinator = State(initialValue: AppLifecycleCoordinator(
            isTesting: { LaunchConfiguration.isTesting() },
            isOnboardingCompleted: {
                UserDefaults.standard.bool(forKey: AppConstants.UserDefaultsKeys.onboardingCompleted)
            },
            refreshHealthAuthorization: { Task { await healthAuth.refreshStatus() } },
            refreshMotionAuthorization: { motionAuth.refreshStatus() },
            refreshAIAvailability: { fmService.refreshAvailability() },
            refreshCoachSession: { coachService.refreshSession() },
            clearInsightCacheIfNeeded: { insightService.checkDayRolloverAndClearCache() },
            refreshTodayData: { await trackingService.refreshTodayData() },
            refreshStreak: { await trackingService.refreshStreak() },
            performForegroundRefresh: { [syncService, trackingService] in
                guard syncService.shouldPerformForegroundSync() else { return }
                do {
                    try await syncService.performIncrementalSync()
                } catch {
                    Loggers.sync.error("sync.foreground_refresh_failed", metadata: [
                        "error": error.localizedDescription
                    ])
                }
                _ = await trackingService.refreshWeeklySummaries()
            }
        ))
    }

    private static func resetStateForUITesting() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        if let suiteDefaults = UserDefaults(suiteName: AppConstants.appGroupID) {
            suiteDefaults.removePersistentDomain(forName: AppConstants.appGroupID)
        }
        PersistenceController.resetStore()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(healthAuthorization)
                .environment(motionAuthorization)
                .environment(stepTrackingService)
                .environment(sharedDataStore)
                .environment(foundationModelsService)
                .environment(insightService)
                .environment(coachService)
                .environment(trainingPlanService)
                .environment(workoutSessionController)
                .environment(badgeService)
                .environment(healthKitSyncService)
                .environment(demoModeStore)
                .environment(notificationService)
                .environment(smartNotificationService)
                .environment(tipJarStore)
                .modelContainer(persistence.container)
                .task {
                    await startupCoordinator.startIfNeeded(onboardingCompleted: onboardingCompleted)
                }
                .onChange(of: onboardingCompleted) { _, _ in
                    Task { @MainActor in
                        await startupCoordinator.startIfNeeded(onboardingCompleted: onboardingCompleted)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    Task { @MainActor in
                        await lifecycleCoordinator.handle(scenePhase: newPhase)
                    }
                }
        }
    }
}
