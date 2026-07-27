import Foundation

enum GPXRouteImporter {
    static func loadImportedRoute(
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.importedGPXRoute
    ) -> ImportedRoute? {
        ImportedRouteStorage.load(defaults: defaults, key: key)
    }

    static func importRoute(
        from url: URL,
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.importedGPXRoute
    ) throws -> ImportedRoute {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try readBoundedFile(at: url)
        let route = try GPXRouteParser.parse(data: data, sourceFilename: url.lastPathComponent)
        try ImportedRouteStorage.save(route, defaults: defaults, key: key)
        return route
    }

    static func clearImportedRoute(
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.importedGPXRoute
    ) {
        ImportedRouteStorage.clear(defaults: defaults, key: key)
    }

    /// Reads at most `maxFileSizeBytes + 1` bytes, then rejects if the cap was exceeded.
    ///
    /// A pre-flight `stat` alone is not a bound: the file lives in a user-chosen document provider that
    /// can grow or swap it between the size check and the read, and when the `.size` attribute is missing
    /// there is no bound at all. Reading through a bounded `FileHandle` makes the cap apply to what we
    /// actually materialize, so an oversized file cannot cause memory pressure before the parser sees it.
    private static func readBoundedFile(at url: URL) throws -> Data {
        let limit = GPXRouteParser.maxFileSizeBytes
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw GPXRouteParserError.invalidDocument
        }
        defer { try? handle.close() }

        let data: Data?
        do {
            data = try handle.read(upToCount: limit + 1)
        } catch {
            throw GPXRouteParserError.invalidDocument
        }

        guard let data else { return Data() }
        if data.count > limit {
            throw GPXRouteParserError.fileTooLarge
        }
        return data
    }
}
