import Foundation
import WidgetKit

struct WidgetStepData: Codable, Hashable, Sendable {
    let todaySteps: Int
    let goalSteps: Int
    let goalProgress: Double
    let currentStreak: Int
    let lastUpdated: Date
    let weeklySteps: [Int]

    var isStale: Bool {
        Date.now.timeIntervalSince(lastUpdated) > 3600
    }
}

enum WidgetConstants {
    static let appGroupID = "group.com.mneves.aipedometer"
    static let sharedStepDataKey = "sharedStepData"
    static let defaultDailyGoal = 10_000
}

struct WidgetStepEntry: TimelineEntry {
    let date: Date
    let data: WidgetStepData?
}

enum WidgetDataLoader {
    static func loadSharedData() -> WidgetStepData? {
        guard let defaults = UserDefaults(suiteName: WidgetConstants.appGroupID) else {
            return nil
        }
        guard let rawData = defaults.data(forKey: WidgetConstants.sharedStepDataKey) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(WidgetStepData.self, from: rawData)
        } catch {
            Loggers.widgets.error("widget.shared_data_decode_failed", metadata: [
                "error": error.localizedDescription
            ])
            return nil
        }
    }

    static func placeholderData() -> WidgetStepData {
        WidgetStepData(
            todaySteps: 6420,
            goalSteps: WidgetConstants.defaultDailyGoal,
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
