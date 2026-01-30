#if os(watchOS)
import SwiftUI

@main
struct AIPedometerWatchApp: App {
    @State private var syncClient = WatchSyncClient()

    var body: some Scene {
        WindowGroup {
            WatchRootView(syncClient: syncClient)
        }
    }
}

struct WatchRootView: View {
    let syncClient: WatchSyncClient

    private var distanceMeters: Double {
        Double(syncClient.payload.todaySteps) * AppConstants.Metrics.averageStepLengthMeters
    }

    private var distanceText: String {
        distanceMeters.formattedDistance()
    }

    var body: some View {
        StepSummaryWatchView(
            steps: syncClient.payload.todaySteps,
            goal: syncClient.payload.goalSteps,
            streak: syncClient.payload.currentStreak,
            distanceText: distanceText
        )
    }
}
#endif
