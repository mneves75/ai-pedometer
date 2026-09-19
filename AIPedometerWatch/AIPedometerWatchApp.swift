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
    private func distanceText(for payload: WatchPayload) -> String? {
        guard payload.activityMode == .steps else { return nil }
        let meters = Double(payload.todaySteps) * AppConstants.Metrics.averageStepLengthMeters
        return meters.formattedDistance()
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let payload = syncClient.payload.normalizedForRendering(at: context.date)
            StepSummaryWatchView(
                steps: payload.todaySteps,
                goal: payload.goalSteps,
                streak: payload.currentStreak,
                activityMode: payload.activityMode,
                distanceText: distanceText(for: payload)
            )
        }
    }
}
#endif
