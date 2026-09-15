import Foundation

enum HistoryAnalysisGate {
    static func shouldLoadWeeklyAnalysis(
        syncEnabled: Bool,
        loadError: String?,
        summaries: [DailyStepSummary]
    ) -> Bool {
        guard syncEnabled else { return false }
        guard loadError == nil else { return false }
        return !summaries.isEmpty
    }

    /// Runs one History load. `.task(id:)`, pull-to-refresh and Try Again can overlap, so only the
    /// invocation that is still current may publish loading, error or analysis state.
    @MainActor
    static func load(
        isCurrent: @escaping @MainActor () -> Bool,
        refreshSummaries: @escaping @MainActor () async -> String?,
        finishLoading: @escaping @MainActor (_ loadError: String?) -> Void,
        shouldLoadAnalysis: @escaping @MainActor (_ loadError: String?) -> Bool,
        loadAnalysis: @escaping @MainActor () async -> Void
    ) async {
        let loadError = await refreshSummaries()
        // `refreshWeeklySummaries` reports success for a superseded generation, so a stale invocation would
        // otherwise hide the newer load's spinner and start analysis on data that is still loading.
        guard isCurrent() else { return }
        finishLoading(loadError)
        guard shouldLoadAnalysis(loadError) else { return }
        await loadAnalysis()
    }
}
