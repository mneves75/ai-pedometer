import SwiftUI

@MainActor
final class AppLifecycleCoordinator {
    private struct ActiveRefresh {
        let id: Int
        let task: Task<Void, Never>
    }

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

    private var currentPhase: ScenePhase?
    private var sceneGeneration = 0
    private var lastPhase: ScenePhase?
    private var nextActiveRefreshID = 0
    private var activeRefresh: ActiveRefresh?

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
        if scenePhase != currentPhase {
            currentPhase = scenePhase
            sceneGeneration += 1
        }
        let generation = sceneGeneration

        guard scenePhase != lastPhase else { return }

        // Non-active transitions can be recorded immediately — they have no follow-up work
        // that we might want to retry later.
        guard scenePhase == .active else {
            flushSharedData()
            lastPhase = scenePhase
            if let activeRefresh {
                activeRefresh.task.cancel()
                await waitForActiveRefresh(activeRefresh)
            }
            return
        }

        // For `.active`, do NOT commit `lastPhase` until we’ve cleared every guard. If a cold
        // launch fires `.active` before startup finished, we previously recorded it as “seen”
        // and then never re-ran the foreground work once startup caught up. Now the next call
        // (after startup completes) can re-enter and actually refresh.
        guard isOnboardingCompleted() else { return }
        guard !isTesting() else { return }
        guard isStartupComplete() else { return }

        while let activeRefresh {
            await waitForActiveRefresh(activeRefresh)
            guard isCurrentActive(generation: generation) else { return }
            guard lastPhase != .active else { return }
        }

        nextActiveRefreshID += 1
        let refreshID = nextActiveRefreshID
        let refreshTask = Task { @MainActor in
            await performActiveRefresh(generation: generation)
        }
        let activeRefresh = ActiveRefresh(id: refreshID, task: refreshTask)
        self.activeRefresh = activeRefresh
        await withTaskCancellationHandler {
            await waitForActiveRefresh(activeRefresh)
        } onCancel: {
            refreshTask.cancel()
        }
    }

    /// Entry point for lifecycle work that was deferred while local startup was incomplete.
    ///
    /// The app calls this after startup finishes because SwiftUI does not emit another scene-phase
    /// change when the scene remained active throughout launch.
    func handleStartupCompletion(scenePhase initialPhase: ScenePhase) async {
        // The SwiftUI task may have captured an older Environment value before startup awaited.
        // Prefer the latest phase observed by this coordinator and use the supplied value only
        // when no scene transition has reached us yet.
        await handle(scenePhase: currentPhase ?? initialPhase)
    }

    private func performActiveRefresh(generation: Int) async {
        await refreshHealthAuthorization()
        guard isCurrentActive(generation: generation) else { return }
        refreshMotionAuthorization()
        refreshAIAvailability()
        refreshCoachSession()
        clearInsightCacheIfNeeded()
        guard isCurrentActive(generation: generation) else { return }

        await refreshTodayData()
        guard isCurrentActive(generation: generation) else { return }
        await refreshStreak()
        guard isCurrentActive(generation: generation) else { return }
        await performForegroundRefresh()
        guard isCurrentActive(generation: generation) else { return }

        lastPhase = .active
    }

    private func waitForActiveRefresh(_ refresh: ActiveRefresh) async {
        await refresh.task.value

        if activeRefresh?.id == refresh.id {
            activeRefresh = nil
        }
    }

    private func isCurrentActive(generation: Int) -> Bool {
        !Task.isCancelled && currentPhase == .active && sceneGeneration == generation
    }
}
