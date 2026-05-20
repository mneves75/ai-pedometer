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

    @Test("Cold-launch .active recovers once startup completes (2026-05-19 regression)")
    func coldLaunchActiveRecoversOnceStartupCompletes() async {
        // Repro for finding-lifecycle-startup-race: SwiftUI fires `.active` immediately on
        // cold launch. Previously the coordinator stamped `lastPhase = .active` before the
        // `isStartupComplete()` guard, swallowing the only `.active` event of the session.
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

        // Startup catches up — the very next .active call must now perform the work,
        // proving we didn't commit `lastPhase` while the guards were still failing.
        startupComplete = true
        await coordinator.handle(scenePhase: .active)
        #expect(calls == 8)
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
