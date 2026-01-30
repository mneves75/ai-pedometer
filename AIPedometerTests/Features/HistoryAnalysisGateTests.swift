import Testing
import Foundation

@testable import AIPedometer

@Suite("HistoryAnalysisGate Tests")
struct HistoryAnalysisGateTests {
    private let summaries = [
        DailyStepSummary(
            date: Date.now,
            steps: 1200,
            distance: 800,
            floors: 1,
            calories: 50,
            goal: 10_000
        )
    ]

    @Test("Skips analysis when sync is disabled")
    func skipsWhenSyncDisabled() {
        let shouldLoad = HistoryAnalysisGate.shouldLoadWeeklyAnalysis(
            syncEnabled: false,
            loadError: nil,
            summaries: summaries
        )
        #expect(!shouldLoad)
    }

    @Test("Skips analysis when load error exists")
    func skipsWhenLoadErrorExists() {
        let shouldLoad = HistoryAnalysisGate.shouldLoadWeeklyAnalysis(
            syncEnabled: true,
            loadError: "Error",
            summaries: summaries
        )
        #expect(!shouldLoad)
    }

    @Test("Skips analysis when summaries are empty")
    func skipsWhenSummariesEmpty() {
        let shouldLoad = HistoryAnalysisGate.shouldLoadWeeklyAnalysis(
            syncEnabled: true,
            loadError: nil,
            summaries: []
        )
        #expect(!shouldLoad)
    }

    @Test("Loads analysis when sync enabled, no error, and summaries exist")
    func loadsWhenDataAvailable() {
        let shouldLoad = HistoryAnalysisGate.shouldLoadWeeklyAnalysis(
            syncEnabled: true,
            loadError: nil,
            summaries: summaries
        )
        #expect(shouldLoad)
    }
}
