import Testing

@testable import AIPedometer

@MainActor
final class StartupCounter {
    var healthRefresh = 0
    var motionRefresh = 0
    var registerBackground = 0
    var scheduleRefresh = 0
    var watchStart = 0
    var stepTrackingStart = 0
    var initialSync = 0
}

@Suite("AppStartupCoordinator")
@MainActor
struct AppStartupCoordinatorTests {
    @Test("Does not start when onboarding is incomplete")
    func doesNotStartWhenOnboardingIncomplete() async {
        let counter = StartupCounter()
        let coordinator = AppStartupCoordinator(
            isTesting: { false },
            refreshHealthAuthorization: { counter.healthRefresh += 1 },
            refreshMotionAuthorization: { counter.motionRefresh += 1 },
            registerBackgroundTasks: { counter.registerBackground += 1 },
            scheduleAppRefresh: { counter.scheduleRefresh += 1 },
            startWatchSync: { counter.watchStart += 1 },
            startStepTracking: { counter.stepTrackingStart += 1 },
            performInitialSync: { counter.initialSync += 1 }
        )

        await coordinator.startIfNeeded(onboardingCompleted: false)

        #expect(counter.healthRefresh == 0)
        #expect(counter.motionRefresh == 0)
        #expect(counter.registerBackground == 0)
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
            registerBackgroundTasks: { counter.registerBackground += 1 },
            scheduleAppRefresh: { counter.scheduleRefresh += 1 },
            startWatchSync: { counter.watchStart += 1 },
            startStepTracking: { counter.stepTrackingStart += 1 },
            performInitialSync: { counter.initialSync += 1 }
        )

        await coordinator.startIfNeeded(onboardingCompleted: true)

        #expect(counter.healthRefresh == 0)
        #expect(counter.motionRefresh == 0)
        #expect(counter.registerBackground == 0)
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
            registerBackgroundTasks: { counter.registerBackground += 1 },
            scheduleAppRefresh: { counter.scheduleRefresh += 1 },
            startWatchSync: { counter.watchStart += 1 },
            startStepTracking: { counter.stepTrackingStart += 1 },
            performInitialSync: { counter.initialSync += 1 }
        )

        await coordinator.startIfNeeded(onboardingCompleted: true)
        await coordinator.startIfNeeded(onboardingCompleted: true)

        #expect(counter.healthRefresh == 1)
        #expect(counter.motionRefresh == 1)
        #expect(counter.registerBackground == 1)
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
            registerBackgroundTasks: { counter.registerBackground += 1 },
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
        #expect(counter.registerBackground == 1)
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
            registerBackgroundTasks: { counter.registerBackground += 1 },
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
        #expect(counter.registerBackground == 1)
        #expect(counter.scheduleRefresh == 1)
        #expect(counter.watchStart == 1)
        #expect(counter.stepTrackingStart == 1)
        #expect(counter.initialSync == 1)
    }
}
