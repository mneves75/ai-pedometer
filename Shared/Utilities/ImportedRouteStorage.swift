import Foundation

enum ImportedRouteStorage {
    static func load(
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.importedGPXRoute
    ) -> ImportedRoute? {
        guard let data = defaults.data(forKey: key),
              let route = try? JSONDecoder().decode(ImportedRoute.self, from: data) else { return nil }
        // Builds before the name bound stored `<name>` at full length; apply it on the way out too.
        let boundedName = GPXRouteParser.boundedRouteName(route.name)
        guard boundedName.count != route.name.count else { return route }
        return ImportedRoute(
            id: route.id,
            name: boundedName,
            sourceFilename: route.sourceFilename,
            importedAt: route.importedAt,
            pointCount: route.pointCount,
            waypointCount: route.waypointCount,
            distanceMeters: route.distanceMeters,
            elevationGainMeters: route.elevationGainMeters,
            elevationLossMeters: route.elevationLossMeters,
            estimatedDuration: route.estimatedDuration,
            previewPoints: route.previewPoints
        )
    }

    static func save(
        _ route: ImportedRoute,
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.importedGPXRoute
    ) throws {
        let data = try JSONEncoder().encode(route)
        defaults.set(data, forKey: key)
    }

    static func clear(
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.importedGPXRoute
    ) {
        defaults.removeObject(forKey: key)
    }
}
