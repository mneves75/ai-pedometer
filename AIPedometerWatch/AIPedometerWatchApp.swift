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

    /// Estimated from an average step length, which means nothing for wheelchair pushes.
    private var distanceText: String? {
        guard syncClient.payload.activityMode == .steps else { return nil }
        let meters = Double(syncClient.payload.todaySteps) * AppConstants.Metrics.averageStepLengthMeters
        return meters.formattedDistance()
    }

    var body: some View {
        StepSummaryWatchView(
            steps: syncClient.payload.todaySteps,
            goal: syncClient.payload.goalSteps,
            streak: syncClient.payload.currentStreak,
            activityMode: syncClient.payload.activityMode,
            distanceText: distanceText
        )
    }
}
#endif
