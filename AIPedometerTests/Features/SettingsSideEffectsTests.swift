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
            }
        )

        #expect(didSave)
        #expect(persistedGoal == 12_000)
        await refreshStarted.wait()
        #expect(refreshFinished == false)
        releaseRefresh.signal()
        await Task.yield()
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
            aiAvailability: .available
        )

        #expect(decision == .disablePremium)
    }

    @Test("Smart reminders are disabled when AI is unavailable")
    func smartRemindersDisableWhenAIUnavailable() {
        let decision = SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: true,
            premiumEnabled: true,
            aiAvailability: .unavailable(reason: .appleIntelligenceNotEnabled)
        )

        #expect(decision == .disableUnavailableAI(.appleIntelligenceNotEnabled))
    }

    @Test("Smart reminders stay enabled when access is valid")
    func smartRemindersStayEnabledWhenAccessValid() {
        let decision = SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: true,
            premiumEnabled: true,
            aiAvailability: .available
        )

        #expect(decision == .keep)
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
