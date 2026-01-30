import CoreMotion
import Observation

enum MotionAuthStatus: String, Sendable {
    case notDetermined
    case authorized
    case denied
    case unavailable
}

@Observable
@MainActor
final class MotionAuthorization {
    var status: MotionAuthStatus = .notDetermined

    static var isAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    func refreshStatus() {
        guard Self.isAvailable else {
            status = .unavailable
            return
        }
        switch CMPedometer.authorizationStatus() {
        case .notDetermined:
            status = .notDetermined
        case .authorized:
            status = .authorized
        case .denied, .restricted:
            status = .denied
        @unknown default:
            status = .notDetermined
        }
    }
}
