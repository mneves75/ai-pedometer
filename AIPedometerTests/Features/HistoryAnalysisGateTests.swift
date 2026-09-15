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

@Suite("History load ownership")
@MainActor
struct HistoryLoadOwnershipTests {
    @Test("An older load cannot hide loading or start analysis while a newer load runs")
    func olderLoadDoesNotPublishOverNewerLoad() async {
        var generation = 0
        var isLoading = false
        var analysisLoads = 0
        let firstRefreshStarted = HistoryAsyncTestLatch()
        let releaseFirstRefresh = HistoryAsyncTestLatch()
        let secondRefreshStarted = HistoryAsyncTestLatch()
        let releaseSecondRefresh = HistoryAsyncTestLatch()

        // Mirrors `HistoryView.loadData`: bump the generation and show loading, then run the load.
        func startLoad(started: HistoryAsyncTestLatch, release: HistoryAsyncTestLatch) -> Task<Void, Never> {
            generation += 1
            let ownGeneration = generation
            isLoading = true
            return Task {
                await HistoryAnalysisGate.load(
                    isCurrent: { generation == ownGeneration },
                    refreshSummaries: {
                        started.signal()
                        await release.wait()
                        return nil
                    },
                    finishLoading: { _ in isLoading = false },
                    shouldLoadAnalysis: { _ in true },
                    loadAnalysis: { analysisLoads += 1 }
                )
            }
        }

        let first = startLoad(started: firstRefreshStarted, release: releaseFirstRefresh)
        await firstRefreshStarted.wait()
        let second = startLoad(started: secondRefreshStarted, release: releaseSecondRefresh)
        await secondRefreshStarted.wait()

        releaseFirstRefresh.signal()
        await first.value

        #expect(isLoading)
        #expect(analysisLoads == 0)

        releaseSecondRefresh.signal()
        await second.value

        #expect(!isLoading)
        #expect(analysisLoads == 1)
    }
}

@MainActor
private final class HistoryAsyncTestLatch {
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
