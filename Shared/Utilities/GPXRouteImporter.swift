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

        try rejectOversizedFile(at: url)

        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
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

    private static func rejectOversizedFile(at url: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? NSNumber else { return }

        if fileSize.int64Value > Int64(GPXRouteParser.maxFileSizeBytes) {
            throw GPXRouteParserError.fileTooLarge
        }
    }
}
