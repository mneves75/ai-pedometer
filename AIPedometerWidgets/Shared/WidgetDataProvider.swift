import Foundation
import WidgetKit

struct WidgetStepEntry: TimelineEntry {
    let date: Date
    let data: SharedStepData?
}

enum WidgetDataLoader {
    static func loadSharedData() -> SharedStepData? {
        SharedStepDataPersistence.load(
            from: UserDefaults(suiteName: AppConstants.appGroupID)
        )
    }

    static func placeholderData() -> SharedStepData {
        SharedStepData(
            todaySteps: 6420,
            goalSteps: AppConstants.defaultDailyGoal,
            goalProgress: 0.642,
            currentStreak: 12,
            lastUpdated: .now,
            weeklySteps: [5400, 6100, 7200, 8300, 9100, 10200, 6420]
        )
    }
}

struct StepTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetStepEntry {
        WidgetStepEntry(date: .now, data: WidgetDataLoader.placeholderData())
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetStepEntry) -> Void) {
        let data = WidgetDataLoader.loadSharedData() ?? WidgetDataLoader.placeholderData()
        completion(WidgetStepEntry(date: .now, data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetStepEntry>) -> Void) {
        let data = WidgetDataLoader.loadSharedData()
        let entry = WidgetStepEntry(date: .now, data: data)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}
