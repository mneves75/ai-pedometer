import Foundation

@MainActor
final class AppStartupCoordinator {
    private let isUITesting: () -> Bool
    private let refreshHealthAuthorization: () -> Void
    private let refreshMotionAuthorization: () -> Void
    private let registerBackgroundTasks: () -> Void
    private let scheduleAppRefresh: () -> Void
    private let startWatchSync: () -> Void
    private let startStepTracking: () async -> Void
    private let performInitialSync: () async -> Void

    private var didStart = false

    init(
        isUITesting: @escaping () -> Bool,
        refreshHealthAuthorization: @escaping () -> Void,
        refreshMotionAuthorization: @escaping () -> Void,
        registerBackgroundTasks: @escaping () -> Void,
        scheduleAppRefresh: @escaping () -> Void,
        startWatchSync: @escaping () -> Void,
        startStepTracking: @escaping () async -> Void,
        performInitialSync: @escaping () async -> Void
    ) {
        self.isUITesting = isUITesting
        self.refreshHealthAuthorization = refreshHealthAuthorization
        self.refreshMotionAuthorization = refreshMotionAuthorization
        self.registerBackgroundTasks = registerBackgroundTasks
        self.scheduleAppRefresh = scheduleAppRefresh
        self.startWatchSync = startWatchSync
        self.startStepTracking = startStepTracking
        self.performInitialSync = performInitialSync
    }

    func startIfNeeded(onboardingCompleted: Bool) async {
        guard onboardingCompleted else { return }
        guard !isUITesting() else { return }
        guard !didStart else { return }
        didStart = true

        refreshHealthAuthorization()
        refreshMotionAuthorization()
        registerBackgroundTasks()
        scheduleAppRefresh()
        startWatchSync()
        await startStepTracking()
        await performInitialSync()
    }
}
