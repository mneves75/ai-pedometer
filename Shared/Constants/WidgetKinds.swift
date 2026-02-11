import Foundation

// Widget kind identifiers used by WidgetKit and by the iOS app to trigger reloads.
// Keep these stable; changing them will break WidgetCenter reload targeting.
enum WidgetKinds {
    static let stepCount = "StepCountWidget"
    static let progressRing = "ProgressRingWidget"
    static let weeklyChart = "WeeklyChartWidget"
}

