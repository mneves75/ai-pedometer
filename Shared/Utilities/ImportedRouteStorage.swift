import Foundation

enum ImportedRouteStorage {
    static func load(
        defaults: UserDefaults = .standard,
        key: String = AppConstants.UserDefaultsKeys.importedGPXRoute
    ) -> ImportedRoute? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ImportedRoute.self, from: data)
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
