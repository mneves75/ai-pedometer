import Foundation

enum GPXRouteParserError: Error, Equatable {
    case invalidDocument
    case noRoutePoints
}

enum GPXRouteParser {
    static func parse(
        data: Data,
        sourceFilename: String,
        now: Date = .now,
        id: UUID = UUID()
    ) throws -> ImportedRoute {
        let delegate = GPXParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw GPXRouteParserError.invalidDocument
        }

        let points = delegate.points
        guard points.count >= 2 else {
            throw GPXRouteParserError.noRoutePoints
        }

        let distanceMeters = routeDistance(points)
        let elevation = elevationChange(points)
        let fallbackName = sourceFilename.replacingOccurrences(of: ".gpx", with: "", options: .caseInsensitive)
        return ImportedRoute(
            id: id,
            name: delegate.routeName?.isEmpty == false ? delegate.routeName ?? fallbackName : fallbackName,
            sourceFilename: sourceFilename,
            importedAt: now,
            pointCount: points.count,
            waypointCount: delegate.waypointCount,
            distanceMeters: distanceMeters,
            elevationGainMeters: elevation.gain,
            elevationLossMeters: elevation.loss,
            estimatedDuration: estimatedDuration(distanceMeters: distanceMeters, elevationGainMeters: elevation.gain),
            previewPoints: previewPoints(from: points)
        )
    }

    private static func routeDistance(_ points: [RouteCoordinate]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { total, pair in
            total + distanceMeters(from: pair.0, to: pair.1)
        }
    }

    private static func elevationChange(_ points: [RouteCoordinate]) -> (gain: Double, loss: Double) {
        zip(points, points.dropFirst()).reduce(into: (gain: 0.0, loss: 0.0)) { totals, pair in
            guard let previous = pair.0.elevationMeters, let current = pair.1.elevationMeters else { return }
            let delta = current - previous
            if delta > 0 {
                totals.gain += delta
            } else {
                totals.loss += abs(delta)
            }
        }
    }

    private static func estimatedDuration(distanceMeters: Double, elevationGainMeters: Double) -> TimeInterval {
        let walkingSeconds = distanceMeters / 1.4
        let climbingPenaltySeconds = elevationGainMeters * 10
        return walkingSeconds + climbingPenaltySeconds
    }

    private static func previewPoints(from points: [RouteCoordinate], limit: Int = 160) -> [RouteCoordinate] {
        guard points.count > limit else { return points }
        let stride = Double(points.count - 1) / Double(limit - 1)
        return (0..<limit).map { index in
            points[min(Int((Double(index) * stride).rounded()), points.count - 1)]
        }
    }

    private static func distanceMeters(from start: RouteCoordinate, to end: RouteCoordinate) -> Double {
        let earthRadiusMeters = 6_371_000.0
        let startLatitude = start.latitude * .pi / 180
        let endLatitude = end.latitude * .pi / 180
        let deltaLatitude = (end.latitude - start.latitude) * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180

        let a = sin(deltaLatitude / 2) * sin(deltaLatitude / 2)
            + cos(startLatitude) * cos(endLatitude)
            * sin(deltaLongitude / 2) * sin(deltaLongitude / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMeters * c
    }
}

private final class GPXParserDelegate: NSObject, XMLParserDelegate {
    private struct MutablePoint {
        let latitude: Double
        let longitude: Double
        var elevationMeters: Double?
    }

    private var textBuffer = ""
    private var currentPoint: MutablePoint?
    private var waypointDepth = 0

    private(set) var routeName: String?
    private(set) var points: [RouteCoordinate] = []
    private(set) var waypointCount = 0

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        textBuffer = ""

        switch elementName {
        case "trkpt", "rtept":
            guard let latitude = Double(attributeDict["lat"] ?? ""),
                  let longitude = Double(attributeDict["lon"] ?? "") else {
                currentPoint = nil
                return
            }
            currentPoint = MutablePoint(latitude: latitude, longitude: longitude)
        case "wpt":
            waypointDepth += 1
            waypointCount += 1
        default:
            break
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "name" where routeName == nil && waypointDepth == 0:
            routeName = value
        case "ele":
            currentPoint?.elevationMeters = Double(value)
        case "trkpt", "rtept":
            if let currentPoint {
                points.append(RouteCoordinate(
                    latitude: currentPoint.latitude,
                    longitude: currentPoint.longitude,
                    elevationMeters: currentPoint.elevationMeters
                ))
            }
            currentPoint = nil
        case "wpt":
            waypointDepth = max(waypointDepth - 1, 0)
        default:
            break
        }

        textBuffer = ""
    }
}
