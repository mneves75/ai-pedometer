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

    /// Adjusts a stored payload for the moment it will actually be rendered.
    /// The rule itself lives on `SharedStepData` so it is covered by the app's unit tests.
    static func presentableData(_ data: SharedStepData?, at renderDate: Date) -> SharedStepData? {
        data?.normalizedForRendering(at: renderDate)
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
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        let data = WidgetDataLoader.loadSharedData()

        var entries = [WidgetStepEntry(date: now, data: WidgetDataLoader.presentableData(data, at: now))]

        // Second entry at the next midnight. Background refresh is not guaranteed — iOS routinely declines
        // it for low-engagement apps — so without a day-boundary entry the widget can keep presenting the
        // previous day's totals until something else wakes it.
        if let midnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) {
            entries.append(
                WidgetStepEntry(date: midnight, data: WidgetDataLoader.presentableData(data, at: midnight))
            )
        }

        let nextUpdate = calendar.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: entries, policy: .after(nextUpdate)))
    }
}
