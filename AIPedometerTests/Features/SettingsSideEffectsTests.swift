import Foundation
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

    @Test("Available AI schedules a smart reminder without a purchase")
    func availableAISchedulesReminderWithoutPurchase() async {
        var scheduled = false
        let result = await SettingsSideEffects.scheduleSmartReminderIfCurrent(
            isCurrent: { true },
            isEnabled: { true },
            aiAvailability: { .available },
            ensureAuthorization: { true },
            scheduleReminder: { scheduled = true; return true },
            cancelReminders: { scheduled = false }
        )
        #expect(result == .scheduled)
        #expect(scheduled)
        #expect(SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: true,
            aiAvailability: .available
        ) == .keep)
    }

    @Test("Unavailable AI blocks smart reminder scheduling")
    func unavailableAIBlocksReminder() async {
        var scheduleCalls = 0
        let result = await SettingsSideEffects.scheduleSmartReminderIfCurrent(
            isCurrent: { true },
            isEnabled: { true },
            aiAvailability: { .unavailable(reason: .modelNotReady) },
            ensureAuthorization: { true },
            scheduleReminder: { scheduleCalls += 1; return true },
            cancelReminders: {}
        )
        #expect(result == .stale)
        #expect(scheduleCalls == 0)
        #expect(SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: true,
            aiAvailability: .unavailable(reason: .modelNotReady)
        ) == .disableUnavailableAI(.modelNotReady))
        #expect(SettingsSideEffects.smartReminderAccessDecision(
            isEnabled: false,
            aiAvailability: .unavailable(reason: .modelNotReady)
        ) == .keep)
    }

    @Test("Smart reminder authorization cannot schedule after preference or AI eligibility changes", arguments: [false, true])
    func smartReminderAuthorizationCannotScheduleAfterEligibilityChanges(aiBecomesUnavailable: Bool) async {
        var isEnabled = true
        var aiAvailability = AIModelAvailability.available
        var scheduleCallCount = 0
        let authorizationStarted = SettingsAsyncTestLatch()
        let resumeAuthorization = SettingsAsyncTestLatch()

        let update = Task {
            await SettingsSideEffects.scheduleSmartReminderIfCurrent(
                isCurrent: { true },
                isEnabled: { isEnabled },
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
        if aiBecomesUnavailable {
            aiAvailability = .unavailable(reason: .appleIntelligenceNotEnabled)
        } else {
            isEnabled = false
        }
        resumeAuthorization.signal()

        #expect(await update.value == .stale)
        #expect(scheduleCallCount == 0)
    }

    @Test(
        "A suspended reminder resumes once AI can generate it, or its marker is cleared if the user turned it off",
        arguments: [
            (false, true, AIModelAvailability.available, SuspendedSmartReminderAction.none),
            (true, false, AIModelAvailability.available, SuspendedSmartReminderAction.clear),
            (true, true, AIModelAvailability.available, SuspendedSmartReminderAction.resume),
            (true, true, AIModelAvailability.checking, SuspendedSmartReminderAction.none),
            (true, true, AIModelAvailability.unavailable(reason: .modelNotReady), SuspendedSmartReminderAction.none),
        ]
    )
    func suspendedReminderAction(
        isSuspended: Bool,
        isEnabled: Bool,
        availability: AIModelAvailability,
        expected: SuspendedSmartReminderAction
    ) {
        #expect(SettingsSideEffects.suspendedSmartReminderAction(
            isSuspended: isSuspended,
            isEnabled: isEnabled,
            aiAvailability: availability
        ) == expected)
    }
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
