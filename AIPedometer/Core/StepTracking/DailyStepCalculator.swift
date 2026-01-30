import Foundation

struct DailyStepCalculator {
    private let calendar: Calendar

    init(calendar: Calendar = .autoupdatingCurrent) {
        self.calendar = calendar
    }

    func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    func endOfDay(for date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startOfDay(for: date)) ?? date
    }

    func dailyRanges(days: Int, endingOn endDate: Date = .now) -> [(start: Date, end: Date)] {
        var ranges: [(Date, Date)] = []
        for offset in 0..<days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: endDate) else { continue }
            let start = startOfDay(for: date)
            let end = endOfDay(for: date)
            ranges.append((start, end))
        }
        return ranges.reversed()
    }

    func didCrossMidnight(previousDate: Date, currentDate: Date) -> Bool {
        !calendar.isDate(previousDate, inSameDayAs: currentDate)
    }
}
