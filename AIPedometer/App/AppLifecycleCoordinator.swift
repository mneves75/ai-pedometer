import SwiftUI

@MainActor
final class AppLifecycleCoordinator {
    private let isTesting: () -> Bool
    private let isOnboardingCompleted: () -> Bool
    private let isStartupComplete: () -> Bool
    private let refreshHealthAuthorization: () async -> Void
    private let refreshMotionAuthorization: () -> Void
    private let refreshAIAvailability: () -> Void
    private let refreshCoachSession: () -> Void
    private let clearInsightCacheIfNeeded: () -> Void
    private let refreshTodayData: () async -> Void
    private let refreshStreak: () async -> Void
    private let performForegroundRefresh: () async -> Void
    private let flushSharedData: () -> Void

    private var lastPhase: ScenePhase?

    init(
        isTesting: @escaping () -> Bool,
        isOnboardingCompleted: @escaping () -> Bool,
        isStartupComplete: @escaping () -> Bool,
        refreshHealthAuthorization: @escaping () async -> Void,
        refreshMotionAuthorization: @escaping () -> Void,
        refreshAIAvailability: @escaping () -> Void,
        refreshCoachSession: @escaping () -> Void,
        clearInsightCacheIfNeeded: @escaping () -> Void,
        refreshTodayData: @escaping () async -> Void,
        refreshStreak: @escaping () async -> Void,
        performForegroundRefresh: @escaping () async -> Void,
        flushSharedData: @escaping () -> Void = {}
    ) {
        self.isTesting = isTesting
        self.isOnboardingCompleted = isOnboardingCompleted
        self.isStartupComplete = isStartupComplete
        self.refreshHealthAuthorization = refreshHealthAuthorization
        self.refreshMotionAuthorization = refreshMotionAuthorization
        self.refreshAIAvailability = refreshAIAvailability
        self.refreshCoachSession = refreshCoachSession
        self.clearInsightCacheIfNeeded = clearInsightCacheIfNeeded
        self.refreshTodayData = refreshTodayData
        self.refreshStreak = refreshStreak
        self.performForegroundRefresh = performForegroundRefresh
        self.flushSharedData = flushSharedData
    }

    func handle(scenePhase: ScenePhase) async {
        guard scenePhase != lastPhase else { return }

        // Non-active transitions can be recorded immediately — they have no follow-up work
        // that we might want to retry later.
        guard scenePhase == .active else {
            flushSharedData()
            lastPhase = scenePhase
            return
        }

        // For `.active`, do NOT commit `lastPhase` until we’ve cleared every guard. If a cold
        // launch fires `.active` before startup finished, we previously recorded it as “seen”
        // and then never re-ran the foreground work once startup caught up. Now the next call
        // (after startup completes) can re-enter and actually refresh.
        guard isOnboardingCompleted() else { return }
        guard !isTesting() else { return }
        guard isStartupComplete() else { return }

        await refreshHealthAuthorization()
        guard !Task.isCancelled else { return }
        refreshMotionAuthorization()
        refreshAIAvailability()
        refreshCoachSession()
        clearInsightCacheIfNeeded()
        guard !Task.isCancelled else { return }

        await refreshTodayData()
        guard !Task.isCancelled else { return }
        await refreshStreak()
        guard !Task.isCancelled else { return }
        await performForegroundRefresh()
        guard !Task.isCancelled else { return }

        lastPhase = scenePhase
    }
}
