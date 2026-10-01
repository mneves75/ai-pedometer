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
    /// Optional for routes persisted before segment boundaries were retained.
    private(set) var previewSegmentLengths: [Int]? = nil

    var previewSegments: [[RouteCoordinate]] {
        guard let lengths = previewSegmentLengths else {
            return previewPoints.isEmpty ? [] : [previewPoints]
        }
        var offset = 0
        var segments: [[RouteCoordinate]] = []
        for length in lengths {
            guard length > 0, length <= previewPoints.count - offset else {
                return previewPoints.isEmpty ? [] : [previewPoints]
            }
            segments.append(Array(previewPoints[offset..<(offset + length)]))
            offset += length
        }
        return offset == previewPoints.count ? segments : [previewPoints]
    }
}
