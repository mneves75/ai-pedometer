import Testing

@testable import AIPedometer

@MainActor
final class StartupCounter {
    var healthRefresh = 0
    var motionRefresh = 0
    var scheduleRefresh = 0
    var watchStart = 0
    var stepTrackingStart = 0
    var initialSync = 0
}

@Suite("AppStartupCoordinator")
@MainActor
struct AppStartupCoordinatorTests {
    @Test("Local startup does not wait for premium access resolution")
    func localStartupDoesNotWaitForPremiumResolution() async {
        let premiumStarted = AppStartupTestLatch()
        let releasePremium = AppStartupTestLatch()
        let localStartupCompleted = AppStartupTestLatch()
        var premiumCompleted = false

        let launch = Task { @MainActor in
            await AppLaunchSequence.start(
                preparePremiumAccess: {
                    premiumStarted.signal()
                    await releasePremium.wait()
                    premiumCompleted = true
                },
                startLocalServices: {
                    localStartupCompleted.signal()
                }
            )
        }

        await premiumStarted.wait()
        await localStartupCompleted.wait()

        #expect(premiumCompleted == false)

        releasePremium.signal()
        await launch.value

        #expect(premiumCompleted)
    }

    @Test("Cancelling launch cancels unresolved premium preparation")
    func cancelledLaunchCancelsPremiumPreparation() async {
        let premiumStarted = AppStartupTestLatch()
        let releasePremium = AppStartupTestLatch()
        let premiumCancelled = AppStartupTestLatch()

        let launch = Task { @MainActor in
            await AppLaunchSequence.start(
                preparePremiumAccess: {
                    await withTaskCancellationHandler {
                        premiumStarted.signal()
                        await releasePremium.wait()
                    } onCancel: {
                        Task { @MainActor in
                            premiumCancelled.signal()
                            releasePremium.signal()
                        }
                    }
                },
                startLocalServices: {}
            )
        }

        await premiumStarted.wait()
        launch.cancel()
        await premiumCancelled.wait()
        await launch.value

        #expect(launch.isCancelled)
    }

    @Test("Does not start when onboarding is incomplete")
    func doesNotStartWhenOnboardingIncomplete() async {
        let counter = StartupCounter()
        let coordinator = AppStartupCoordinator(
            isTesting: { false },
            refreshHealthAuthorization: { counter.healthRefresh += 1 },
            refreshMotionAuthorization: { counter.motionRefresh += 1 },
            scheduleAppRefresh: { counter.scheduleRefresh += 1 },
            startWatchSync: { counter.watchStart += 1 },
            startStepTracking: { counter.stepTrackingStart += 1 },
            performInitialSync: { counter.initialSync += 1 }
        )

        await coordinator.startIfNeeded(onboardingCompleted: false)

        #expect(counter.healthRefresh == 0)
        #expect(counter.motionRefresh == 0)
        #expect(counter.scheduleRefresh == 0)
        #expect(counter.watchStart == 0)
        #expect(counter.stepTrackingStart == 0)
        #expect(counter.initialSync == 0)
    }

    @Test("Does not start during UI testing")
    func doesNotStartDuringUITesting() async {
        let counter = StartupCounter()
        let coordinator = AppStartupCoordinator(
            isTesting: { true },
            refreshHealthAuthorization: { counter.healthRefresh += 1 },
            refreshMotionAuthorization: { counter.motionRefresh += 1 },
            scheduleAppRefresh: { counter.scheduleRefresh += 1 },
            startWatchSync: { counter.watchStart += 1 },
            startStepTracking: { counter.stepTrackingStart += 1 },
            performInitialSync: { counter.initialSync += 1 }
        )

        await coordinator.startIfNeeded(onboardingCompleted: true)

        #expect(counter.healthRefresh == 0)
        #expect(counter.motionRefresh == 0)
        #expect(counter.scheduleRefresh == 0)
        #expect(counter.watchStart == 0)
        #expect(counter.stepTrackingStart == 0)
        #expect(counter.initialSync == 0)
    }

    @Test("Starts only once after onboarding completes")
    func startsOnlyOnce() async {
        let counter = StartupCounter()
        let coordinator = AppStartupCoordinator(
            isTesting: { false },
            refreshHealthAuthorization: { counter.healthRefresh += 1 },
            refreshMotionAuthorization: { counter.motionRefresh += 1 },
            scheduleAppRefresh: { counter.scheduleRefresh += 1 },
            startWatchSync: { counter.watchStart += 1 },
            startStepTracking: { counter.stepTrackingStart += 1 },
            performInitialSync: { counter.initialSync += 1 }
        )

        await coordinator.startIfNeeded(onboardingCompleted: true)
        await coordinator.startIfNeeded(onboardingCompleted: true)

        #expect(counter.healthRefresh == 1)
        #expect(counter.motionRefresh == 1)
        #expect(counter.scheduleRefresh == 1)
        #expect(counter.watchStart == 1)
        #expect(counter.stepTrackingStart == 1)
        #expect(counter.initialSync == 1)
        #expect(coordinator.hasCompletedStartup)
    }

    @Test("Cancelled startup retries on next invocation (2026-05-19 regression)")
    func cancelledStartupRetriesOnNextInvocation() async {
        // Repro for finding-startup-cancellation: if the calling Task is cancelled mid-flight,
        // `didStart` previously latched at `true` while `hasCompletedStartup` stayed false,
        // leaving the app permanently half-initialized. The fix resets `didStart` when the
        // task ends with `Task.isCancelled == true`.
        let counter = StartupCounter()

        // First closure that fires during startup will cancel the surrounding Task,
        // simulating SwiftUI tearing down the `.task` modifier mid-startup.
        var cancelTask: (() -> Void)?
        let coordinator = AppStartupCoordinator(
            isTesting: { false },
            refreshHealthAuthorization: { counter.healthRefresh += 1 },
            refreshMotionAuthorization: {
                counter.motionRefresh += 1
                cancelTask?()
            },
            scheduleAppRefresh: { counter.scheduleRefresh += 1 },
            startWatchSync: { counter.watchStart += 1 },
            startStepTracking: { counter.stepTrackingStart += 1 },
            performInitialSync: { counter.initialSync += 1 }
        )

        let firstAttempt = Task { @MainActor in
            await coordinator.startIfNeeded(onboardingCompleted: true)
        }
        cancelTask = { firstAttempt.cancel() }
        await firstAttempt.value

        #expect(coordinator.hasCompletedStartup == false)

        // Wipe the cancel hook so the retry actually finishes.
        cancelTask = nil
        await coordinator.startIfNeeded(onboardingCompleted: true)

        #expect(coordinator.hasCompletedStartup)
        // Cancellation stops before later side effects, so retrying does not double-register
        // background/watch/workout work from a half-cancelled first pass.
        #expect(counter.healthRefresh == 2)
        #expect(counter.motionRefresh == 2)
        #expect(counter.scheduleRefresh == 1)
        #expect(counter.watchStart == 1)
        #expect(counter.stepTrackingStart == 1)
        #expect(counter.initialSync == 1)
    }

    @Test("Late cancellation after final startup step does not re-run side effects")
    func lateCancellationDoesNotRerunCompletedStartup() async {
        // Once `performInitialSync` has returned, startup side effects have all run. A SwiftUI
        // task cancellation arriving at that point should not reset `didStart` and restart
        // background/watch/pedometer work on the next attachment.
        let counter = StartupCounter()
        var cancelTask: (() -> Void)?
        let coordinator = AppStartupCoordinator(
            isTesting: { false },
            refreshHealthAuthorization: { counter.healthRefresh += 1 },
            refreshMotionAuthorization: { counter.motionRefresh += 1 },
            scheduleAppRefresh: { counter.scheduleRefresh += 1 },
            startWatchSync: { counter.watchStart += 1 },
            startStepTracking: { counter.stepTrackingStart += 1 },
            performInitialSync: {
                counter.initialSync += 1
                cancelTask?()
            }
        )

        let firstAttempt = Task { @MainActor in
            await coordinator.startIfNeeded(onboardingCompleted: true)
        }
        cancelTask = { firstAttempt.cancel() }
        await firstAttempt.value

        #expect(coordinator.hasCompletedStartup)

        cancelTask = nil
        await coordinator.startIfNeeded(onboardingCompleted: true)

        #expect(counter.healthRefresh == 1)
        #expect(counter.motionRefresh == 1)
        #expect(counter.scheduleRefresh == 1)
        #expect(counter.watchStart == 1)
        #expect(counter.stepTrackingStart == 1)
        #expect(counter.initialSync == 1)
    }
}

@MainActor
private final class AppStartupTestLatch {
    private var isSignaled = false

    func wait(timeout: Duration = .seconds(5)) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while !isSignaled {
            if Task.isCancelled { return }
            guard clock.now < deadline else {
                Issue.record("Timed out waiting for an app-startup test rendezvous")
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
