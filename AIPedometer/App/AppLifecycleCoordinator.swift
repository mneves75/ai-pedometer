import SwiftUI

@MainActor
final class AppLifecycleCoordinator {
    private let isUITesting: () -> Bool
    private let isOnboardingCompleted: () -> Bool
    private let refreshHealthAuthorization: () -> Void
    private let refreshMotionAuthorization: () -> Void
    private let refreshAIAvailability: () -> Void
    private let refreshCoachSession: () -> Void
    private let clearInsightCacheIfNeeded: () -> Void
    private let refreshTodayData: () async -> Void
    private let refreshStreak: () async -> Void
    private let performForegroundRefresh: () async -> Void

    private var lastPhase: ScenePhase?

    init(
        isUITesting: @escaping () -> Bool,
        isOnboardingCompleted: @escaping () -> Bool,
        refreshHealthAuthorization: @escaping () -> Void,
        refreshMotionAuthorization: @escaping () -> Void,
        refreshAIAvailability: @escaping () -> Void,
        refreshCoachSession: @escaping () -> Void,
        clearInsightCacheIfNeeded: @escaping () -> Void,
        refreshTodayData: @escaping () async -> Void,
        refreshStreak: @escaping () async -> Void,
        performForegroundRefresh: @escaping () async -> Void
    ) {
        self.isUITesting = isUITesting
        self.isOnboardingCompleted = isOnboardingCompleted
        self.refreshHealthAuthorization = refreshHealthAuthorization
        self.refreshMotionAuthorization = refreshMotionAuthorization
        self.refreshAIAvailability = refreshAIAvailability
        self.refreshCoachSession = refreshCoachSession
        self.clearInsightCacheIfNeeded = clearInsightCacheIfNeeded
        self.refreshTodayData = refreshTodayData
        self.refreshStreak = refreshStreak
        self.performForegroundRefresh = performForegroundRefresh
    }

    func handle(scenePhase: ScenePhase) async {
        guard scenePhase != lastPhase else { return }
        lastPhase = scenePhase

        guard scenePhase == .active else { return }
        guard isOnboardingCompleted() else { return }
        guard !isUITesting() else { return }

        refreshHealthAuthorization()
        refreshMotionAuthorization()
        refreshAIAvailability()
        refreshCoachSession()
        clearInsightCacheIfNeeded()

        await refreshTodayData()
        await refreshStreak()
        await performForegroundRefresh()
    }
}
