import Foundation

struct DailyStepSummary: Sendable, Identifiable {
    var id: Date { date }

    let date: Date
    let steps: Int
    let distance: Double
    let floors: Int
    let calories: Double
    let goal: Int

    var goalMet: Bool {
        steps >= goal
    }

    var progress: Double {
        guard goal > 0 else { return 0 }
        return Double(steps) / Double(goal)
    }

    var dateString: String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    var dayName: String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }
}

extension Array where Element == DailyStepSummary {
    var maxStepsValue: Int {
        Swift.max(map(\.steps).max() ?? 0, 1)
    }

    var sortedByDateDescending: [DailyStepSummary] {
        sorted { $0.date > $1.date }
    }
}
