import Foundation

@MainActor
final class AppStartupCoordinator {
    private let isTesting: () -> Bool
    private let refreshHealthAuthorization: () async -> Void
    private let refreshMotionAuthorization: () -> Void
    private let scheduleAppRefresh: () -> Void
    private let startWatchSync: () -> Void
    private let startStepTracking: () async -> Void
    private let performInitialSync: () async -> Void

    private var didStart = false
    private(set) var hasCompletedStartup = false

    init(
        isTesting: @escaping () -> Bool,
        refreshHealthAuthorization: @escaping () async -> Void,
        refreshMotionAuthorization: @escaping () -> Void,
        scheduleAppRefresh: @escaping () -> Void,
        startWatchSync: @escaping () -> Void,
        startStepTracking: @escaping () async -> Void,
        performInitialSync: @escaping () async -> Void
    ) {
        self.isTesting = isTesting
        self.refreshHealthAuthorization = refreshHealthAuthorization
        self.refreshMotionAuthorization = refreshMotionAuthorization
        self.scheduleAppRefresh = scheduleAppRefresh
        self.startWatchSync = startWatchSync
        self.startStepTracking = startStepTracking
        self.performInitialSync = performInitialSync
    }

    func startIfNeeded(onboardingCompleted: Bool) async {
        guard onboardingCompleted else { return }
        guard !isTesting() else { return }
        guard !didStart else { return }
        didStart = true

        await refreshHealthAuthorization()
        guard !Task.isCancelled else {
            didStart = false
            return
        }
        refreshMotionAuthorization()
        guard !Task.isCancelled else {
            didStart = false
            return
        }
        scheduleAppRefresh()
        guard !Task.isCancelled else {
            didStart = false
            return
        }
        startWatchSync()
        guard !Task.isCancelled else {
            didStart = false
            return
        }
        await startStepTracking()
        guard !Task.isCancelled else {
            didStart = false
            return
        }
        await performInitialSync()

        // After the final awaited step returns, every startup side effect has already run.
        // Treat late cancellation as complete so a SwiftUI task teardown cannot re-run
        // watch/background/pedometer startup on the next view attachment.
        hasCompletedStartup = true
    }
}
