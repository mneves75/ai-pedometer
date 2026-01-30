import Foundation
import Testing

@testable import AIPedometer

@Suite("HealthKitSyncSettings Tests")
struct HealthKitSyncSettingsTests {
    @Test("Defaults to enabled when key is missing")
    func defaultsToEnabledWhenMissing() {
        let suiteName = "HealthKitSyncSettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false), "Failed to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(HealthKitSyncSettings.isEnabled(userDefaults: defaults))
    }

    @Test("Returns false when disabled in UserDefaults")
    func returnsFalseWhenDisabled() {
        let suiteName = "HealthKitSyncSettingsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            #expect(Bool(false), "Failed to create UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: AppConstants.UserDefaultsKeys.healthKitSyncEnabled)
        #expect(!HealthKitSyncSettings.isEnabled(userDefaults: defaults))
    }
}
