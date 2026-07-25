import Foundation

enum SmartReminderAccessDecision: Equatable {
    case keep
    case disablePremium
    case disableUnavailableAI(AIUnavailabilityReason?)
}

/// Background enforcement of Premium access for already-scheduled smart reminders.
///
/// Deliberately never persists the user's `smartRemindersEnabled` preference off: losing access
/// suspends delivery, and regaining it resumes delivery, so a resubscribing user does not have to
/// rediscover the setting. Settings keeps its own interactive path, where the change is visible and
/// explained to the user.
enum SmartReminderAccessAction: Equatable {
    case none
    /// Cancel the pending repeating request but leave the user's preference intact.
    case suspend
    /// Re-schedule a previously suspended reminder now that access is back.
    case resume
}

enum SmartReminderSchedulingResult: Equatable {
    case scheduled
    case stale
    case authorizationDenied
    case scheduleFailed
}

enum SettingsSideEffects {
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
        premiumEnabled: Bool,
        aiAvailability: AIModelAvailability,
        hasAuthoritativeAccess: Bool
    ) -> SmartReminderAccessDecision {
        guard isEnabled else { return .keep }
        // `premiumEnabled` is false both when the user is not entitled and when entitlement could not be
        // determined — still resolving, or the last fetch/verification failed, as on an offline launch.
        // Defer until the answer is authoritative; acting on the unknown case cancels reminders for
        // paying subscribers. See `PremiumAccessStore.hasAuthoritativeAccessState`.
        guard hasAuthoritativeAccess else { return .keep }
        guard premiumEnabled else { return .disablePremium }

        if case .unavailable(let reason) = aiAvailability {
            return .disableUnavailableAI(reason)
        }

        return .keep
    }

    /// Decides whether background access enforcement should suspend or resume smart reminders.
    ///
    /// Acts only on authoritative entitlement state. While access is unknown — still resolving, or the
    /// last fetch/verification failed, as happens on an offline launch — this returns `.none`, because
    /// "cannot determine entitlement" is value-identical to "not entitled" and acting on it cancels
    /// reminders for paying subscribers.
    ///
    /// Scoped to Premium only. On-device AI availability is transient (assets can still be downloading)
    /// and an already-scheduled reminder carries pre-generated content, so AI availability does not
    /// suspend delivery; it only gates re-scheduling, which needs the model to generate fresh content.
    static func smartReminderAccessAction(
        isEnabled: Bool,
        isSuspended: Bool,
        hasAuthoritativeAccess: Bool,
        premiumEnabled: Bool,
        aiAvailability: AIModelAvailability
    ) -> SmartReminderAccessAction {
        guard isEnabled else { return .none }
        guard hasAuthoritativeAccess else { return .none }

        guard premiumEnabled else {
            return isSuspended ? .none : .suspend
        }
        guard isSuspended else { return .none }
        return aiAvailability.isAvailable ? .resume : .none
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
