import Foundation

enum SmartReminderAccessDecision: Equatable {
    case keep
    case disablePremium
    case disableUnavailableAI(AIUnavailabilityReason?)
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
