import Foundation

extension Date {
    func startOfDay(using calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.startOfDay(for: self)
    }

    func endOfDay(using calendar: Calendar = .autoupdatingCurrent) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startOfDay(using: calendar)) ?? self
    }
}
