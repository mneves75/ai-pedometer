import Foundation

enum DistanceEstimationMode: String, Codable, CaseIterable, Sendable {
    case automatic
    case manual

    var localizedName: String {
        switch self {
        case .automatic:
            String(localized: "Automatic", comment: "Distance estimation mode: automatic from HealthKit")
        case .manual:
            String(localized: "Manual", comment: "Distance estimation mode: manual step length")
        }
    }

    var localizedDescription: String {
        switch self {
        case .automatic:
            String(localized: "Automatically estimate distance traveled. This is typically more accurate than using a fixed step length.", comment: "Automatic distance mode description")
        case .manual:
            String(localized: "Use a fixed step length to calculate distance", comment: "Manual distance mode description")
        }
    }
}
