import Foundation

extension Double {
    @MainActor
    func formattedDistance() -> String {
        Formatters.distanceString(meters: self)
    }

    @MainActor
    func formattedCalories() -> String {
        Formatters.caloriesString(self)
    }
}
