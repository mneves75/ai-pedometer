import SwiftUI
import Testing

@testable import AIPedometer

@MainActor
struct AppLifecycleCoordinatorTests {
    @Test("Active scene phase triggers refresh work once per transition")
    func activePhaseTriggersRefreshOncePerTransition() async {
        var healthAuthRefreshes = 0
        var motionAuthRefreshes = 0
        var aiAvailabilityRefreshes = 0
        var coachSessionRefreshes = 0
        var insightCacheChecks = 0
        var todayRefreshes = 0
        var streakRefreshes = 0
        var foregroundRefreshes = 0

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { true },
            refreshHealthAuthorization: { healthAuthRefreshes += 1 },
            refreshMotionAuthorization: { motionAuthRefreshes += 1 },
            refreshAIAvailability: { aiAvailabilityRefreshes += 1 },
            refreshCoachSession: { coachSessionRefreshes += 1 },
            clearInsightCacheIfNeeded: { insightCacheChecks += 1 },
            refreshTodayData: { todayRefreshes += 1 },
            refreshStreak: { streakRefreshes += 1 },
            performForegroundRefresh: { foregroundRefreshes += 1 }
        )

        await coordinator.handle(scenePhase: .active)

        #expect(healthAuthRefreshes == 1)
        #expect(motionAuthRefreshes == 1)
        #expect(aiAvailabilityRefreshes == 1)
        #expect(coachSessionRefreshes == 1)
        #expect(insightCacheChecks == 1)
        #expect(todayRefreshes == 1)
        #expect(streakRefreshes == 1)
        #expect(foregroundRefreshes == 1)

        await coordinator.handle(scenePhase: .active)

        #expect(healthAuthRefreshes == 1)
        #expect(motionAuthRefreshes == 1)
        #expect(aiAvailabilityRefreshes == 1)
        #expect(coachSessionRefreshes == 1)
        #expect(insightCacheChecks == 1)
        #expect(todayRefreshes == 1)
        #expect(streakRefreshes == 1)
        #expect(foregroundRefreshes == 1)

        await coordinator.handle(scenePhase: .inactive)
        await coordinator.handle(scenePhase: .active)

        #expect(healthAuthRefreshes == 2)
        #expect(motionAuthRefreshes == 2)
        #expect(aiAvailabilityRefreshes == 2)
        #expect(coachSessionRefreshes == 2)
        #expect(insightCacheChecks == 2)
        #expect(todayRefreshes == 2)
        #expect(streakRefreshes == 2)
        #expect(foregroundRefreshes == 2)
    }

    @Test("Lifecycle refreshes skip when onboarding is incomplete")
    func lifecycleSkipsWhenOnboardingIncomplete() async {
        var calls = 0

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { false },
            isStartupComplete: { true },
            refreshHealthAuthorization: { calls += 1 },
            refreshMotionAuthorization: { calls += 1 },
            refreshAIAvailability: { calls += 1 },
            refreshCoachSession: { calls += 1 },
            clearInsightCacheIfNeeded: { calls += 1 },
            refreshTodayData: { calls += 1 },
            refreshStreak: { calls += 1 },
            performForegroundRefresh: { calls += 1 }
        )

        await coordinator.handle(scenePhase: .active)

        #expect(calls == 0)
    }

    @Test("Lifecycle refreshes skip during UI testing")
    func lifecycleSkipsDuringUITesting() async {
        var calls = 0

        let coordinator = AppLifecycleCoordinator(
            isTesting: { true },
            isOnboardingCompleted: { true },
            isStartupComplete: { true },
            refreshHealthAuthorization: { calls += 1 },
            refreshMotionAuthorization: { calls += 1 },
            refreshAIAvailability: { calls += 1 },
            refreshCoachSession: { calls += 1 },
            clearInsightCacheIfNeeded: { calls += 1 },
            refreshTodayData: { calls += 1 },
            refreshStreak: { calls += 1 },
            performForegroundRefresh: { calls += 1 }
        )

        await coordinator.handle(scenePhase: .active)

        #expect(calls == 0)
    }

    @Test("Lifecycle refreshes skip until startup is complete")
    func lifecycleSkipsUntilStartupCompletes() async {
        var calls = 0

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { false },
            refreshHealthAuthorization: { calls += 1 },
            refreshMotionAuthorization: { calls += 1 },
            refreshAIAvailability: { calls += 1 },
            refreshCoachSession: { calls += 1 },
            clearInsightCacheIfNeeded: { calls += 1 },
            refreshTodayData: { calls += 1 },
            refreshStreak: { calls += 1 },
            performForegroundRefresh: { calls += 1 }
        )

        await coordinator.handle(scenePhase: .active)

        #expect(calls == 0)
    }

    @Test("Cold-launch .active is retried explicitly when startup completes")
    func coldLaunchActiveRecoversOnceStartupCompletes() async {
        // SwiftUI fires `.active` immediately on cold launch but does not emit it again merely
        // because startup completed. The post-startup entry point must own that retry.
        var calls = 0
        var startupComplete = false

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { startupComplete },
            refreshHealthAuthorization: { calls += 1 },
            refreshMotionAuthorization: { calls += 1 },
            refreshAIAvailability: { calls += 1 },
            refreshCoachSession: { calls += 1 },
            clearInsightCacheIfNeeded: { calls += 1 },
            refreshTodayData: { calls += 1 },
            refreshStreak: { calls += 1 },
            performForegroundRefresh: { calls += 1 }
        )

        await coordinator.handle(scenePhase: .active)
        #expect(calls == 0)

        startupComplete = true
        await coordinator.handleStartupCompletion(scenePhase: .active)
        #expect(calls == 8)
    }

    @Test("Startup completion does not replace a newer background phase")
    func startupCompletionPreservesNewerBackgroundPhase() async {
        var calls = 0
        var startupComplete = false

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { startupComplete },
            refreshHealthAuthorization: { calls += 1 },
            refreshMotionAuthorization: { calls += 1 },
            refreshAIAvailability: { calls += 1 },
            refreshCoachSession: { calls += 1 },
            clearInsightCacheIfNeeded: { calls += 1 },
            refreshTodayData: { calls += 1 },
            refreshStreak: { calls += 1 },
            performForegroundRefresh: { calls += 1 }
        )

        await coordinator.handle(scenePhase: .active)
        await coordinator.handle(scenePhase: .background)
        startupComplete = true

        // The completion callback may still hold the phase captured before its await.
        await coordinator.handleStartupCompletion(scenePhase: .active)

        #expect(calls == 0)
    }

    @Test("Startup completion retries a newer active phase")
    func startupCompletionRetriesNewerActivePhase() async {
        var calls = 0
        var startupComplete = false

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { startupComplete },
            refreshHealthAuthorization: { calls += 1 },
            refreshMotionAuthorization: { calls += 1 },
            refreshAIAvailability: { calls += 1 },
            refreshCoachSession: { calls += 1 },
            clearInsightCacheIfNeeded: { calls += 1 },
            refreshTodayData: { calls += 1 },
            refreshStreak: { calls += 1 },
            performForegroundRefresh: { calls += 1 }
        )

        await coordinator.handle(scenePhase: .inactive)
        await coordinator.handle(scenePhase: .active)
        startupComplete = true

        // The completion callback may still hold the phase captured before its await.
        await coordinator.handleStartupCompletion(scenePhase: .inactive)

        #expect(calls == 8)
    }

    @Test("Startup completion seeds the initial phase when no transition was observed")
    func startupCompletionSeedsInitialPhase() async {
        var calls = 0

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { true },
            refreshHealthAuthorization: { calls += 1 },
            refreshMotionAuthorization: { calls += 1 },
            refreshAIAvailability: { calls += 1 },
            refreshCoachSession: { calls += 1 },
            clearInsightCacheIfNeeded: { calls += 1 },
            refreshTodayData: { calls += 1 },
            refreshStreak: { calls += 1 },
            performForegroundRefresh: { calls += 1 }
        )

        await coordinator.handleStartupCompletion(scenePhase: .active)

        #expect(calls == 8)
    }

    @Test("Post-startup retry does not duplicate active work already in flight")
    func postStartupRetryDoesNotDuplicateActiveWork() async {
        let activeRefreshStarted = AppLifecycleTestLatch()
        let releaseActiveRefresh = AppLifecycleTestLatch()
        let startupRetryStarted = AppLifecycleTestLatch()
        var healthAuthRefreshes = 0
        var foregroundRefreshes = 0

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { true },
            refreshHealthAuthorization: {
                healthAuthRefreshes += 1
                activeRefreshStarted.signal()
                await releaseActiveRefresh.wait()
            },
            refreshMotionAuthorization: {},
            refreshAIAvailability: {},
            refreshCoachSession: {},
            clearInsightCacheIfNeeded: {},
            refreshTodayData: {},
            refreshStreak: {},
            performForegroundRefresh: { foregroundRefreshes += 1 }
        )

        let sceneTransition = Task { @MainActor in
            await coordinator.handle(scenePhase: .active)
        }
        await activeRefreshStarted.wait()

        let startupCompletion = Task { @MainActor in
            startupRetryStarted.signal()
            await coordinator.handleStartupCompletion(scenePhase: .active)
        }
        await startupRetryStarted.wait()

        #expect(healthAuthRefreshes == 1)
        releaseActiveRefresh.signal()

        await sceneTransition.value
        await startupCompletion.value

        #expect(healthAuthRefreshes == 1)
        #expect(foregroundRefreshes == 1)
    }

    @Test("Cancelling a duplicate waiter preserves the owning active refresh")
    func cancellingDuplicateWaiterPreservesActiveRefresh() async {
        let activeRefreshStarted = AppLifecycleTestLatch()
        let releaseActiveRefresh = AppLifecycleTestLatch()
        let duplicateStarted = AppLifecycleTestLatch()
        var foregroundRefreshes = 0

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { true },
            refreshHealthAuthorization: {
                activeRefreshStarted.signal()
                await releaseActiveRefresh.wait()
            },
            refreshMotionAuthorization: {},
            refreshAIAvailability: {},
            refreshCoachSession: {},
            clearInsightCacheIfNeeded: {},
            refreshTodayData: {},
            refreshStreak: {},
            performForegroundRefresh: { foregroundRefreshes += 1 }
        )

        let owner = Task { await coordinator.handle(scenePhase: .active) }
        await activeRefreshStarted.wait()
        let duplicate = Task {
            duplicateStarted.signal()
            await coordinator.handleStartupCompletion(scenePhase: .active)
        }
        await duplicateStarted.wait()
        duplicate.cancel()
        releaseActiveRefresh.signal()
        await owner.value
        await duplicate.value

        #expect(foregroundRefreshes == 1)
    }

    @Test("Background and reactivation invalidate stale active refresh without losing the latest")
    func backgroundTransitionInvalidatesInFlightActiveRefresh() async {
        let activeRefreshStarted = AppLifecycleTestLatch()
        let releaseActiveRefresh = AppLifecycleTestLatch()
        let backgroundTransitionStarted = AppLifecycleTestLatch()
        let latestActiveTransitionStarted = AppLifecycleTestLatch()
        var healthAuthRefreshes = 0
        var todayRefreshes = 0
        var foregroundRefreshes = 0
        var sharedDataFlushes = 0

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { true },
            refreshHealthAuthorization: {
                healthAuthRefreshes += 1
                activeRefreshStarted.signal()
                await releaseActiveRefresh.waitIgnoringCancellation()
            },
            refreshMotionAuthorization: {},
            refreshAIAvailability: {},
            refreshCoachSession: {},
            clearInsightCacheIfNeeded: {},
            refreshTodayData: { todayRefreshes += 1 },
            refreshStreak: {},
            performForegroundRefresh: { foregroundRefreshes += 1 },
            flushSharedData: { sharedDataFlushes += 1 }
        )

        let staleActiveRefresh = Task { @MainActor in
            await coordinator.handle(scenePhase: .active)
        }
        await activeRefreshStarted.wait()

        let backgroundTransition = Task { @MainActor in
            backgroundTransitionStarted.signal()
            await coordinator.handle(scenePhase: .background)
        }
        await backgroundTransitionStarted.wait()

        let latestActiveTransition = Task { @MainActor in
            latestActiveTransitionStarted.signal()
            await coordinator.handle(scenePhase: .active)
        }
        await latestActiveTransitionStarted.wait()

        #expect(sharedDataFlushes == 1)
        #expect(todayRefreshes == 0)
        #expect(foregroundRefreshes == 0)

        releaseActiveRefresh.signal()
        await staleActiveRefresh.value
        await backgroundTransition.value
        await latestActiveTransition.value

        #expect(healthAuthRefreshes == 2)
        #expect(todayRefreshes == 1)
        #expect(foregroundRefreshes == 1)
    }

    @Test("Cancelled active refresh is retried on the next active call")
    func cancelledActiveRefreshRetries() async {
        var healthAuthRefreshes = 0
        var todayRefreshes = 0
        var foregroundRefreshes = 0
        var cancelTask: (() -> Void)?

        let coordinator = AppLifecycleCoordinator(
            isTesting: { false },
            isOnboardingCompleted: { true },
            isStartupComplete: { true },
            refreshHealthAuthorization: { healthAuthRefreshes += 1 },
            refreshMotionAuthorization: {},
            refreshAIAvailability: {},
            refreshCoachSession: {},
            clearInsightCacheIfNeeded: {},
            refreshTodayData: {
                todayRefreshes += 1
                cancelTask?()
            },
            refreshStreak: {},
            performForegroundRefresh: { foregroundRefreshes += 1 }
        )

        let firstAttempt = Task { @MainActor in
            await coordinator.handle(scenePhase: .active)
        }
        cancelTask = { firstAttempt.cancel() }
        await firstAttempt.value

        #expect(healthAuthRefreshes == 1)
        #expect(todayRefreshes == 1)
        #expect(foregroundRefreshes == 0)

        cancelTask = nil
        await coordinator.handle(scenePhase: .active)

        #expect(healthAuthRefreshes == 2)
        #expect(todayRefreshes == 2)
        #expect(foregroundRefreshes == 1)
    }
}

@MainActor
private final class AppLifecycleTestLatch {
    private var isSignaled = false

    func wait(timeout: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !isSignaled {
            if Task.isCancelled { return }
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for an app-lifecycle test rendezvous")
                signal()
                return
            }
            await Task.yield()
        }
    }

    func waitIgnoringCancellation(timeout: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !isSignaled {
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for an app-lifecycle test rendezvous")
                signal()
                return
            }
            await Task.yield()
        }
    }

    func signal() {
        guard !isSignaled else { return }
        isSignaled = true
    }
}
