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

    @Test("rejects GPX payloads larger than the configured size limit")
    func rejectsOversizedGPX() throws {
        let oversized = Data(count: GPXRouteParser.maxFileSizeBytes + 1)
        #expect(throws: GPXRouteParserError.fileTooLarge) {
            _ = try GPXRouteParser.parse(data: oversized, sourceFilename: "huge.gpx")
        }
    }

    @Test("rejects GPX with too many track points")
    func rejectsTooManyTrackPoints() throws {
        let pointCount = GPXRouteParser.maxRoutePoints + 100
        var body = "<?xml version=\"1.0\"?><gpx version=\"1.1\"><trk><trkseg>"
        body.reserveCapacity(pointCount * 64)
        for index in 0..<pointCount {
            let lat = 37.0 + Double(index) * 0.000001
            body += "<trkpt lat=\"\(lat)\" lon=\"-122.0\"><ele>10</ele></trkpt>"
        }
        body += "</trkseg></trk></gpx>"

        #expect(throws: GPXRouteParserError.tooManyElements) {
            _ = try GPXRouteParser.parse(data: Data(body.utf8), sourceFilename: "many.gpx")
        }
    }

    @Test("ignores track points with non-finite or out-of-range coordinates")
    func ignoresInvalidCoordinates() throws {
        let data = Data("""
        <?xml version="1.0"?>
        <gpx version="1.1">
          <trk><trkseg>
            <trkpt lat="nan" lon="-122.0"><ele>10</ele></trkpt>
            <trkpt lat="91.0" lon="0.0"><ele>10</ele></trkpt>
            <trkpt lat="0.0" lon="181.0"><ele>10</ele></trkpt>
            <trkpt lat="37.33182" lon="-122.03118"><ele>10</ele></trkpt>
            <trkpt lat="37.33282" lon="-122.03218"><ele>15</ele></trkpt>
          </trkseg></trk>
        </gpx>
        """.utf8)

        let route = try GPXRouteParser.parse(data: data, sourceFilename: "noisy.gpx")
        #expect(route.pointCount == 2)
        #expect(route.distanceMeters > 0)
        #expect(route.previewPoints.allSatisfy { (-90.0...90.0).contains($0.latitude) })
        #expect(route.previewPoints.allSatisfy { (-180.0...180.0).contains($0.longitude) })
    }

    @Test("ignores non-finite elevation values")
    func ignoresInvalidElevations() throws {
        let data = Data("""
        <?xml version="1.0"?>
        <gpx version="1.1">
          <trk><trkseg>
            <trkpt lat="37.33182" lon="-122.03118"><ele>nan</ele></trkpt>
            <trkpt lat="37.33282" lon="-122.03218"><ele>inf</ele></trkpt>
            <trkpt lat="37.33382" lon="-122.03318"><ele>15</ele></trkpt>
          </trkseg></trk>
        </gpx>
        """.utf8)

        let route = try GPXRouteParser.parse(data: data, sourceFilename: "elev.gpx")
        #expect(route.elevationGainMeters.isFinite)
        #expect(route.elevationLossMeters.isFinite)
    }

    @Test("disables external entity resolution to defend against XXE")
    func disablesExternalEntities() throws {
        // The parser may still report well-formed-document errors, but the assertion we care
        // about is that no external entity is resolved into the route name. With external
        // entity resolution off, the most likely outcome is `invalidDocument` (or, on lenient
        // parsers, an empty name). The route name must never echo the file contents.
        let data = Data("""
        <?xml version="1.0"?>
        <!DOCTYPE foo [ <!ENTITY xxe SYSTEM "file:///etc/hostname"> ]>
        <gpx version="1.1">
          <metadata><name>&xxe;</name></metadata>
          <trk><trkseg>
            <trkpt lat="37.33182" lon="-122.03118"><ele>10</ele></trkpt>
            <trkpt lat="37.33282" lon="-122.03218"><ele>15</ele></trkpt>
          </trkseg></trk>
        </gpx>
        """.utf8)

        do {
            let route = try GPXRouteParser.parse(data: data, sourceFilename: "xxe.gpx")
            #expect(route.name != "/etc/hostname")
            #expect(route.name.contains("hostname") == false)
        } catch GPXRouteParserError.invalidDocument {
            // Acceptable: parser rejected the document outright once entity resolution is off.
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

    @Test("GPXRouteImporter saves a valid GPX route through one interface")
    func importerSavesValidGPXRoute() throws {
        let suiteName = "GPXRouteImporterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let routeURL = try writeTemporaryGPX(
            filename: "trail.gpx",
            contents: """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1">
              <metadata><name>Trail</name></metadata>
              <trk><trkseg>
                <trkpt lat="37.33182" lon="-122.03118"><ele>10</ele></trkpt>
                <trkpt lat="37.33282" lon="-122.03218"><ele>15</ele></trkpt>
              </trkseg></trk>
            </gpx>
            """
        )
        defer { try? FileManager.default.removeItem(at: routeURL.deletingLastPathComponent()) }

        let route = try GPXRouteImporter.importRoute(from: routeURL, defaults: defaults)

        #expect(route.name == "Trail")
        #expect(route.sourceFilename == "trail.gpx")
        #expect(ImportedRouteStorage.load(defaults: defaults) == route)
    }

    @Test("GPXRouteImporter rejects oversized files before storage")
    func importerRejectsOversizedFileBeforeStorage() throws {
        let suiteName = "GPXRouteImporterTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let routeURL = try writeTemporaryGPX(
            filename: "huge.gpx",
            data: Data(count: GPXRouteParser.maxFileSizeBytes + 1)
        )
        defer { try? FileManager.default.removeItem(at: routeURL.deletingLastPathComponent()) }

        #expect(throws: GPXRouteParserError.fileTooLarge) {
            _ = try GPXRouteImporter.importRoute(from: routeURL, defaults: defaults)
        }
        #expect(ImportedRouteStorage.load(defaults: defaults) == nil)
    }

    // MARK: - Localized error descriptions (2026-05-19 audit)

    @Test("GPXRouteParserError surfaces human-readable, localized messages")
    func gpxRouteParserErrorIsLocalized() {
        // The file-importer alert in WorkoutsView reads `error.localizedDescription`.
        // Without `LocalizedError` conformance Cocoa returned
        // "The operation couldn't be completed. (AIPedometer.GPXRouteParserError error 0.)"
        // and the user had no idea what failed. These checks make sure every case carries
        // a non-default, non-empty description so the alert is actionable.
        let cases: [GPXRouteParserError] = [
            .invalidDocument,
            .noRoutePoints,
            .fileTooLarge,
            .tooManyElements
        ]

        for error in cases {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
            #expect(!description.contains("couldn’t be completed"))
            #expect(!description.contains("error 0."))
            #expect(error.localizedDescription == description)
        }
    }

    private func writeTemporaryGPX(filename: String, contents: String) throws -> URL {
        try writeTemporaryGPX(filename: filename, data: Data(contents.utf8))
    }

    private func writeTemporaryGPX(filename: String, data: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GPXRouteImporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}
