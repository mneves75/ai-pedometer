import Foundation

enum SmartReminderAccessDecision: Equatable {
    case keep
    case disableUnavailableAI(AIUnavailabilityReason?)
}

/// What to do with a smart reminder whose delivery was suspended without the user asking.
enum SuspendedSmartReminderAction: Equatable, Sendable {
    case none
    /// The preference is off: drop the suspension marker.
    case clear
    /// Reschedule the reminder, then drop the marker once it is scheduled.
    case resume
}

enum SmartReminderSchedulingResult: Equatable {
    case scheduled
    case stale
    case authorizationDenied
    case scheduleFailed
}

enum SettingsSideEffects {
    /// Rescheduling needs the on-device model to generate the reminder, so an unavailable or still
    /// loading model leaves the marker in place for a later attempt.
    static func suspendedSmartReminderAction(
        isSuspended: Bool,
        isEnabled: Bool,
        aiAvailability: AIModelAvailability
    ) -> SuspendedSmartReminderAction {
        guard isSuspended else { return .none }
        guard isEnabled else { return .clear }
        return aiAvailability.isAvailable ? .resume : .none
    }

    @MainActor
    static func persistGoalAndScheduleRefresh(
        goal: Int,
        persistGoal: @MainActor (Int) -> Bool,
        refreshAfterSave: @escaping @MainActor () async -> Void
    ) -> Bool {
        guard persistGoal(goal) else { return false }
        Task { @MainActor in
            await refreshAfterSave()
        }
        return true
    }

    static func smartReminderAccessDecision(
        isEnabled: Bool,
        aiAvailability: AIModelAvailability
    ) -> SmartReminderAccessDecision {
        guard isEnabled else { return .keep }
        if case .unavailable(let reason) = aiAvailability {
            return .disableUnavailableAI(reason)
        }

        return .keep
    }

    @MainActor
    static func scheduleSmartReminderIfCurrent(
        isCurrent: @escaping @MainActor () -> Bool,
        isEnabled: @escaping @MainActor () -> Bool,
        aiAvailability: @escaping @MainActor () -> AIModelAvailability,
        ensureAuthorization: @escaping @MainActor () async -> Bool,
        scheduleReminder: @escaping @MainActor () async -> Bool,
        cancelReminders: @escaping @MainActor () -> Void
    ) async -> SmartReminderSchedulingResult {
        let isEligible: @MainActor () -> Bool = {
            isEnabled() && aiAvailability().isAvailable
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
