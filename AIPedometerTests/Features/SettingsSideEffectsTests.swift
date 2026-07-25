import Testing

@testable import AIPedometer

@Suite("SettingsSideEffects")
@MainActor
struct SettingsSideEffectsTests {
    @Test("Goal persistence returns before its follow-up refresh finishes")
    func goalPersistenceDoesNotAwaitRefresh() async {
        var persistedGoal: Int?
        var refreshFinished = false
        let refreshStarted = SettingsAsyncTestLatch()
        let releaseRefresh = SettingsAsyncTestLatch()
        // Wait on an explicit completion signal rather than a bare `Task.yield()`. A single yield only
        // guarantees this task suspends once, not that the released refresh task runs to completion, so
        // the old form failed under full-suite load while passing in isolation.
        let refreshCompleted = SettingsAsyncTestLatch()

        let didSave = SettingsSideEffects.persistGoalAndScheduleRefresh(
            goal: 12_000,
            persistGoal: { goal in
                persistedGoal = goal
                return true
            },
            refreshAfterSave: {
                refreshStarted.signal()
                await releaseRefresh.wait()
                refreshFinished = true
                refreshCompleted.signal()
            }
        )

        #expect(didSave)
        #expect(persistedGoal == 12_000)
        await refreshStarted.wait()
        // The contract under test: persistence returned before the refresh finished.
        #expect(refreshFinished == false)
        releaseRefresh.signal()
        await refreshCompleted.wait()
        #expect(refreshFinished)
    }

    @Test("HealthKit sync change refreshes today data even when disabling sync")
    func healthKitSyncChangeRefreshesTodayDataWhenDisabling() async {
        var refreshedToday = 0
        var refreshedWeekly = 0
        var refreshedAuthorization = 0
        var pullToRefreshCalls = 0
        var coldStartCalls = 0
        var capturedErrors: [String] = []

        await SettingsSideEffects.applyHealthKitSyncChange(
            enabled: false,
            refreshTodayData: { refreshedToday += 1 },
            refreshWeeklySummaries: { refreshedWeekly += 1 },
            refreshAuthorization: { refreshedAuthorization += 1 },
            needsColdStartSync: { false },
            performColdStartSync: { coldStartCalls += 1 },
            performPullToRefresh: { pullToRefreshCalls += 1 },
            onError: { capturedErrors.append($0) }
        )

        #expect(refreshedToday == 1)
        #expect(refreshedWeekly == 1)
        #expect(refreshedAuthorization == 1)
        #expect(pullToRefreshCalls == 0)
        #expect(coldStartCalls == 0)
        #expect(capturedErrors.isEmpty)
    }

    @Test("HealthKit sync change refreshes current data after enabling sync")
    func healthKitSyncChangeRefreshesDataWhenEnabling() async {
        var refreshedToday = 0
        var refreshedWeekly = 0
        var refreshedAuthorization = 0
        var pullToRefreshCalls = 0

        await SettingsSideEffects.applyHealthKitSyncChange(
            enabled: true,
            refreshTodayData: { refreshedToday += 1 },
            refreshWeeklySummaries: { refreshedWeekly += 1 },
            refreshAuthorization: { refreshedAuthorization += 1 },
            needsColdStartSync: { false },
            performColdStartSync: {},
            performPullToRefresh: { pullToRefreshCalls += 1 },
            onError: { _ in }
        )

        #expect(pullToRefreshCalls == 1)
        #expect(refreshedToday == 1)
        #expect(refreshedWeekly == 1)
        #expect(refreshedAuthorization == 1)
    }

    @Test("Smart reminders are disabled when premium is unavailable")
    func smartRemindersDisableWhenPremiumUnavailable() {
        let decision = SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: true,
            premiumEnabled: false,
            aiAvailability: .available,
            hasAuthoritativeAccess: true
        )

        #expect(decision == .disablePremium)
    }

    @Test("Smart reminders are disabled when AI is unavailable")
    func smartRemindersDisableWhenAIUnavailable() {
        let decision = SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: true,
            premiumEnabled: true,
            aiAvailability: .unavailable(reason: .appleIntelligenceNotEnabled),
            hasAuthoritativeAccess: true
        )

        #expect(decision == .disableUnavailableAI(.appleIntelligenceNotEnabled))
    }

    @Test("Smart reminders stay enabled when access is valid")
    func smartRemindersStayEnabledWhenAccessValid() {
        let decision = SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: true,
            premiumEnabled: true,
            aiAvailability: .available,
            hasAuthoritativeAccess: true
        )

        #expect(decision == .keep)
    }

    @Test("Background enforcement never acts while entitlement state is unknown")
    func accessActionDefersWhileEntitlementUnknown() {
        // The defect that broke two earlier attempts: `canAccessAIFeatures == false` is value-identical
        // for "not entitled" and "could not determine". An offline launch reaches `.unavailable` with
        // no customer info, so acting here cancels a paying subscriber's reminders.
        let action = SettingsSideEffects.smartReminderAccessAction(
            isEnabled: true,
            isSuspended: false,
            hasAuthoritativeAccess: false,
            premiumEnabled: false,
            aiAvailability: .available
        )

        #expect(action == .none)
    }

    @Test("Background enforcement suspends delivery once revocation is authoritative")
    func accessActionSuspendsOnAuthoritativeRevocation() {
        let action = SettingsSideEffects.smartReminderAccessAction(
            isEnabled: true,
            isSuspended: false,
            hasAuthoritativeAccess: true,
            premiumEnabled: false,
            aiAvailability: .available
        )

        #expect(action == .suspend)
    }

    @Test("Background enforcement does not suspend twice")
    func accessActionDoesNotSuspendTwice() {
        let action = SettingsSideEffects.smartReminderAccessAction(
            isEnabled: true,
            isSuspended: true,
            hasAuthoritativeAccess: true,
            premiumEnabled: false,
            aiAvailability: .available
        )

        #expect(action == .none)
    }

    @Test("Background enforcement resumes delivery when premium returns")
    func accessActionResumesWhenPremiumReturns() {
        let action = SettingsSideEffects.smartReminderAccessAction(
            isEnabled: true,
            isSuspended: true,
            hasAuthoritativeAccess: true,
            premiumEnabled: true,
            aiAvailability: .available
        )

        #expect(action == .resume)
    }

    @Test("Resume waits for on-device AI because rescheduling regenerates content")
    func accessActionWaitsForAIBeforeResuming() {
        let action = SettingsSideEffects.smartReminderAccessAction(
            isEnabled: true,
            isSuspended: true,
            hasAuthoritativeAccess: true,
            premiumEnabled: true,
            aiAvailability: .unavailable(reason: .modelNotReady)
        )

        #expect(action == .none)
    }

    @Test("Transient AI unavailability never suspends an already-scheduled reminder")
    func accessActionIgnoresAIAvailabilityWhenEntitled() {
        // The reminder carries pre-generated content, so a model that is still downloading is not a
        // reason to stop delivering it.
        let action = SettingsSideEffects.smartReminderAccessAction(
            isEnabled: true,
            isSuspended: false,
            hasAuthoritativeAccess: true,
            premiumEnabled: true,
            aiAvailability: .unavailable(reason: .modelNotReady)
        )

        #expect(action == .none)
    }

    @Test("Background enforcement ignores reminders the user turned off")
    func accessActionIgnoresDisabledReminders() {
        let action = SettingsSideEffects.smartReminderAccessAction(
            isEnabled: false,
            isSuspended: true,
            hasAuthoritativeAccess: true,
            premiumEnabled: true,
            aiAvailability: .available
        )

        #expect(action == .none)
    }

    @Test("Settings does not disable reminders while entitlement state is unknown")
    func smartRemindersSurviveUnresolvedPremiumAccess() {
        // Regression: `premiumEnabled` is false both when RevenueCat is still resolving and when the
        // fetch failed (offline launch). Treating either as revocation cancels a paying user's reminders
        // and, before this guard, erased the setting the moment they opened Settings.
        let decision = SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: true,
            premiumEnabled: false,
            aiAvailability: .available,
            hasAuthoritativeAccess: false
        )

        #expect(decision == .keep)
    }

    @Test("Settings still disables reminders once revocation is authoritative")
    func smartRemindersDisableOnAuthoritativeRevocation() {
        let decision = SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: true,
            premiumEnabled: false,
            aiAvailability: .available,
            hasAuthoritativeAccess: true
        )

        #expect(decision == .disablePremium)
    }


    @Test(
        "Smart reminder authorization cannot schedule after eligibility revocation",
        arguments: SmartReminderRevocation.allCases
    )
    func smartReminderAuthorizationCannotScheduleAfterRevocation(
        _ revocation: SmartReminderRevocation
    ) async {
        var isEnabled = true
        var premiumEnabled = true
        var aiAvailability = AIModelAvailability.available
        var scheduleCallCount = 0
        let authorizationStarted = SettingsAsyncTestLatch()
        let resumeAuthorization = SettingsAsyncTestLatch()

        let update = Task {
            await SettingsSideEffects.scheduleSmartReminderIfCurrent(
                isCurrent: { true },
                isEnabled: { isEnabled },
                premiumEnabled: { premiumEnabled },
                aiAvailability: { aiAvailability },
                ensureAuthorization: {
                    authorizationStarted.signal()
                    await resumeAuthorization.wait()
                    return true
                },
                scheduleReminder: {
                    scheduleCallCount += 1
                    return true
                },
                cancelReminders: {}
            )
        }

        await authorizationStarted.wait()
        switch revocation {
        case .toggle:
            isEnabled = false
        case .premium:
            premiumEnabled = false
        case .ai:
            aiAvailability = .unavailable(reason: .appleIntelligenceNotEnabled)
        }
        resumeAuthorization.signal()

        let result = await update.value

        #expect(result == .stale)
        #expect(scheduleCallCount == 0)
    }
}

enum SmartReminderRevocation: CaseIterable, Sendable {
    case toggle
    case premium
    case ai
}

@MainActor
private final class SettingsAsyncTestLatch {
    private var isSignaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isSignaled else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        guard !isSignaled else { return }
        isSignaled = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }
}
