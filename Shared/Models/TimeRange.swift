import Foundation

enum TimeRange: String, CaseIterable, Sendable {
    case day
    case week
    case month
    case year

    var title: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }
}
