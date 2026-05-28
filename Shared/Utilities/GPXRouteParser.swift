import Foundation

enum GPXRouteParserError: LocalizedError, Equatable {
    case invalidDocument
    case noRoutePoints
    case fileTooLarge
    case tooManyElements

    /// Convenience used in `WorkoutsView`'s file-importer alert. Keeps the GPX
    /// failure modes localized — without this `LocalizedError` conformance the
    /// system used to surface the meaningless
    /// "The operation couldn't be completed. (AIPedometer.GPXRouteParserError error 0.)".
    var errorDescription: String? {
        switch self {
        case .invalidDocument:
            return L10n.localized(
                "The GPX file isn’t valid. Try exporting it again from your route tool.",
                comment: "GPX import error: malformed XML/GPX document"
            )
        case .noRoutePoints:
            return L10n.localized(
                "We couldn’t find any track or route points in this file.",
                comment: "GPX import error: parse succeeded but no track/route points present"
            )
        case .fileTooLarge:
            return L10n.localized(
                "This GPX file is over the 5 MB import limit. Try a shorter route or simplify the track.",
                comment: "GPX import error: file exceeds the parser size cap"
            )
        case .tooManyElements:
            return L10n.localized(
                "This GPX has too many track points or waypoints for offline import.",
                comment: "GPX import error: file exceeds the parser element caps"
            )
        }
    }
}

enum GPXRouteParser {
    /// Hard cap on GPX file size accepted by the importer. Anything larger is rejected
    /// before we hand bytes to `XMLParser` to avoid memory pressure from hostile input.
    static let maxFileSizeBytes = 5 * 1024 * 1024 // 5 MiB
    /// Cap on track/route points to defend against degenerate inputs that would blow up
    /// distance/elevation math, MapKit preview rendering, and storage size.
    static let maxRoutePoints = 50_000
    /// Cap on waypoint elements parsed; matches `maxRoutePoints` order of magnitude.
    static let maxWaypoints = 5_000
    /// Cap on characters accumulated for a single element's text node. `shouldResolveExternalEntities`
    /// already blocks XXE, but Foundation still expands *internal* DTD entities — a small file with
    /// nested entity definitions ("billion laughs") could otherwise balloon one element's text in
    /// memory. Legitimate GPX text nodes (names, elevations, coordinates) are tiny, so this bound is
    /// far above any real value while keeping hostile expansion in check.
    static let maxElementTextCharacters = 1_000_000

    static func parse(
        data: Data,
        sourceFilename: String,
        now: Date = .now,
        id: UUID = UUID()
    ) throws -> ImportedRoute {
        guard data.count <= maxFileSizeBytes else {
            throw GPXRouteParserError.fileTooLarge
        }

        let delegate = GPXParserDelegate(
            maxRoutePoints: maxRoutePoints,
            maxWaypoints: maxWaypoints,
            maxElementTextCharacters: maxElementTextCharacters
        )
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        // Defense in depth: disable XML external entity resolution and DTD lookup so that a
        // hostile GPX cannot trigger network requests or local file reads via XXE.
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false

        guard parser.parse() else {
            if delegate.aborted {
                throw GPXRouteParserError.tooManyElements
            }
            throw GPXRouteParserError.invalidDocument
        }

        if delegate.aborted {
            throw GPXRouteParserError.tooManyElements
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

    private let maxRoutePoints: Int
    private let maxWaypoints: Int
    private let maxElementTextCharacters: Int

    private var textBuffer = ""
    private var currentPoint: MutablePoint?
    private var waypointDepth = 0

    private(set) var routeName: String?
    private(set) var points: [RouteCoordinate] = []
    private(set) var waypointCount = 0
    private(set) var aborted = false

    init(maxRoutePoints: Int, maxWaypoints: Int, maxElementTextCharacters: Int) {
        self.maxRoutePoints = maxRoutePoints
        self.maxWaypoints = maxWaypoints
        self.maxElementTextCharacters = maxElementTextCharacters
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        textBuffer = ""
        if aborted { return }

        switch elementName {
        case "trkpt", "rtept":
            guard let latitude = Self.parseCoordinate(attributeDict["lat"], range: -90...90),
                  let longitude = Self.parseCoordinate(attributeDict["lon"], range: -180...180) else {
                currentPoint = nil
                return
            }
            currentPoint = MutablePoint(latitude: latitude, longitude: longitude)
        case "wpt":
            waypointDepth += 1
            if waypointCount >= maxWaypoints {
                aborted = true
                parser.abortParsing()
                return
            }
            waypointCount += 1
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if aborted { return }
        // Bound text accumulation so internal-entity expansion cannot balloon a single element in
        // memory. Tripping the cap is treated like the element caps: abort and surface `.tooManyElements`.
        guard textBuffer.count + string.count <= maxElementTextCharacters else {
            aborted = true
            parser.abortParsing()
            return
        }
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?
    ) {
        if aborted { return }
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "name" where routeName == nil && waypointDepth == 0:
            routeName = value
        case "ele":
            if let elevation = Double(value), elevation.isFinite {
                currentPoint?.elevationMeters = elevation
            }
        case "trkpt", "rtept":
            if let currentPoint {
                if points.count >= maxRoutePoints {
                    aborted = true
                    parser.abortParsing()
                    self.currentPoint = nil
                    textBuffer = ""
                    return
                }
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

    private static func parseCoordinate(_ raw: String?, range: ClosedRange<Double>) -> Double? {
        guard let raw, let value = Double(raw), value.isFinite, range.contains(value) else { return nil }
        return value
    }
}
