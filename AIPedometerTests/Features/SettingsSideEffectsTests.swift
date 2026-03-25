import Testing

@testable import AIPedometer

@Suite("SettingsSideEffects")
@MainActor
struct SettingsSideEffectsTests {
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
}
