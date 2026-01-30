import Foundation

enum HealthKitSyncSettings {
    static func isEnabled(userDefaults: UserDefaults = .standard) -> Bool {
        if userDefaults.object(forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled) == nil {
            return true
        }
        return userDefaults.bool(forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
    }
}
