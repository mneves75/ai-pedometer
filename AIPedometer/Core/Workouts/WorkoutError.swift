import Foundation

enum WorkoutError: Error, Equatable, Sendable {
    case unableToStart
    case unableToSave
    case notAuthorized
}
