import Foundation

enum HealthKitError: Error, LocalizedError, Sendable {
    case notAvailable
    case authorizationFailed
    case queryFailed
    case noData

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return String(localized: "Health data is not available on this device.", comment: "HealthKit not available error")
        case .authorizationFailed:
            return String(localized: "Health access is not authorized. Please enable Health in Settings.", comment: "HealthKit authorization error")
        case .queryFailed:
            return String(localized: "We couldn't load your health data. Please try again.", comment: "HealthKit query error")
        case .noData:
            return String(localized: "No health data available yet. Start moving to build your history.", comment: "HealthKit no data error")
        }
    }
}
