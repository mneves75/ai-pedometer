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
}
