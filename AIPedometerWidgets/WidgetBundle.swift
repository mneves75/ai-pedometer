import SwiftUI
import WidgetKit

@main
struct AIPedometerWidgetBundle: WidgetBundle {
    var body: some Widget {
        StepCountWidget()
        ProgressRingWidget()
        WeeklyChartWidget()
        WorkoutLiveActivityWidget()
    }
}
