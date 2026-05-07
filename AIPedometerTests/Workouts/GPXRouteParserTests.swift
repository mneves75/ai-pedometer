import Foundation
import Testing

@testable import AIPedometer

struct GPXRouteParserTests {
    @Test
    func parsesTrackPointsWaypointsAndElevation() throws {
        let data = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="AIPedometerTests">
          <metadata><name>Hill Loop</name></metadata>
          <wpt lat="37.33182" lon="-122.03118"><name>Trailhead</name></wpt>
          <trk>
            <name>Track name should not replace metadata</name>
            <trkseg>
              <trkpt lat="37.33182" lon="-122.03118"><ele>10</ele></trkpt>
              <trkpt lat="37.33282" lon="-122.03218"><ele>25</ele></trkpt>
              <trkpt lat="37.33382" lon="-122.03318"><ele>18</ele></trkpt>
            </trkseg>
          </trk>
        </gpx>
        """.utf8)

        let route = try GPXRouteParser.parse(
            data: data,
            sourceFilename: "hill-loop.gpx",
            now: Date(timeIntervalSince1970: 1_000),
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )

        #expect(route.name == "Hill Loop")
        #expect(route.sourceFilename == "hill-loop.gpx")
        #expect(route.pointCount == 3)
        #expect(route.waypointCount == 1)
        #expect(route.elevationGainMeters == 15)
        #expect(route.elevationLossMeters == 7)
        #expect(route.distanceMeters > 250)
        #expect(route.estimatedDuration > 0)
        #expect(route.previewPoints.count == 3)
    }

    @Test
    func rejectsGPXWithoutRoutePoints() throws {
        let data = Data("""
        <gpx version="1.1"><wpt lat="37.33182" lon="-122.03118" /></gpx>
        """.utf8)

        #expect(throws: GPXRouteParserError.noRoutePoints) {
            _ = try GPXRouteParser.parse(data: data, sourceFilename: "empty.gpx")
        }
    }

    @Test
    func savesLoadsAndClearsImportedRoute() throws {
        let suiteName = "ImportedRouteStorageTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let route = ImportedRoute(
            id: UUID(),
            name: "Saved Route",
            sourceFilename: "saved.gpx",
            importedAt: Date(timeIntervalSince1970: 2_000),
            pointCount: 2,
            waypointCount: 0,
            distanceMeters: 500,
            elevationGainMeters: 5,
            elevationLossMeters: 2,
            estimatedDuration: 360,
            previewPoints: [
                RouteCoordinate(latitude: 1, longitude: 1, elevationMeters: 1),
                RouteCoordinate(latitude: 2, longitude: 2, elevationMeters: 2)
            ]
        )

        try ImportedRouteStorage.save(route, defaults: defaults)
        #expect(ImportedRouteStorage.load(defaults: defaults) == route)

        ImportedRouteStorage.clear(defaults: defaults)
        #expect(ImportedRouteStorage.load(defaults: defaults) == nil)
    }
}
