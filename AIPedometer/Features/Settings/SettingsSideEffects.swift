import Foundation

enum SmartReminderAccessDecision: Equatable {
    case keep
    case disablePremium
    case disableUnavailableAI(AIUnavailabilityReason?)
}

enum SmartReminderSchedulingResult: Equatable {
    case scheduled
    case stale
    case authorizationDenied
    case scheduleFailed
}

enum SettingsSideEffects {
    static func smartReminderAccessDecision(
        isEnabled: Bool,
        premiumEnabled: Bool,
        aiAvailability: AIModelAvailability
    ) -> SmartReminderAccessDecision {
        guard isEnabled else { return .keep }
        guard premiumEnabled else { return .disablePremium }

        if case .unavailable(let reason) = aiAvailability {
            return .disableUnavailableAI(reason)
        }

        return .keep
    }

    @MainActor
    static func scheduleSmartReminderIfCurrent(
        isCurrent: @escaping @MainActor () -> Bool,
        isEnabled: @escaping @MainActor () -> Bool,
        premiumEnabled: @escaping @MainActor () -> Bool,
        aiAvailability: @escaping @MainActor () -> AIModelAvailability,
        ensureAuthorization: @escaping @MainActor () async -> Bool,
        scheduleReminder: @escaping @MainActor () async -> Bool,
        cancelReminders: @escaping @MainActor () -> Void
    ) async -> SmartReminderSchedulingResult {
        let isEligible: @MainActor () -> Bool = {
            isEnabled() && premiumEnabled() && aiAvailability().isAvailable
        }

        guard isCurrent(), isEligible() else {
            return .stale
        }
        guard await ensureAuthorization() else {
            return .authorizationDenied
        }
        guard isCurrent(), isEligible() else {
            return .stale
        }

        let didSchedule = await scheduleReminder()
        guard isEligible() else {
            if didSchedule {
                cancelReminders()
            }
            return .stale
        }
        guard isCurrent() else {
            return .stale
        }
        return didSchedule ? .scheduled : .scheduleFailed
    }

    @MainActor
    static func applyHealthKitSyncChange(
        enabled: Bool,
        refreshTodayData: @escaping @MainActor () async -> Void,
        refreshWeeklySummaries: @escaping @MainActor () async -> Void,
        refreshAuthorization: @escaping @MainActor () async -> Void,
        needsColdStartSync: @escaping @MainActor () -> Bool,
        performColdStartSync: @escaping @MainActor () async throws -> Void,
        performPullToRefresh: @escaping @MainActor () async throws -> Void,
        onError: @escaping @MainActor (String) -> Void
    ) async {
        if enabled {
            do {
                if needsColdStartSync() {
                    try await performColdStartSync()
                } else {
                    try await performPullToRefresh()
                }
            } catch {
                onError(error.localizedDescription)
            }
        }

        await refreshTodayData()
        await refreshWeeklySummaries()
        await refreshAuthorization()
    }
}
