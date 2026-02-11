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
    }
}
