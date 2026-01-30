import Foundation

extension Int {
    @MainActor
    var formattedSteps: String {
        Formatters.stepCountString(self)
    }
}
