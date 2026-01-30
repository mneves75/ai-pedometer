import Foundation

enum MotionError: Error {
    case notAvailable
    case authorizationDenied
    case queryFailed
    case noData
}
