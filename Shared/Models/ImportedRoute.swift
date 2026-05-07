import Foundation

struct RouteCoordinate: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    let elevationMeters: Double?
}

struct ImportedRoute: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let sourceFilename: String
    let importedAt: Date
    let pointCount: Int
    let waypointCount: Int
    let distanceMeters: Double
    let elevationGainMeters: Double
    let elevationLossMeters: Double
    let estimatedDuration: TimeInterval
    let previewPoints: [RouteCoordinate]
}
