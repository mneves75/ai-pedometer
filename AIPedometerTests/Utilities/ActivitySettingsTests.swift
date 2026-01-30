import Foundation
import Testing

@testable import AIPedometer

@Suite("ActivitySettings Tests")
struct ActivitySettingsTests {
    @Test("Defaults use steps, automatic distance, and fallback step length")
    func defaultsUseFallbacks() {
        let suiteName = "ActivitySettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)

        let settings = ActivitySettings.current(userDefaults: defaults)

        #expect(settings.activityMode == .steps)
        #expect(settings.distanceMode == .automatic)
        #expect(settings.manualStepLength == AppConstants.Defaults.manualStepLengthMeters)
    }

    @Test("Reads stored activity preferences")
    func readsStoredPreferences() {
        let suiteName = "ActivitySettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(ActivityTrackingMode.wheelchairPushes.rawValue, forKey: AppConstants.UserDefaultsKeys.activityTrackingMode)
        defaults.set(DistanceEstimationMode.manual.rawValue, forKey: AppConstants.UserDefaultsKeys.distanceEstimationMode)
        defaults.set(0.9, forKey: AppConstants.UserDefaultsKeys.manualStepLengthMeters)

        let settings = ActivitySettings.current(userDefaults: defaults)

        #expect(settings.activityMode == .wheelchairPushes)
        #expect(settings.distanceMode == .manual)
        #expect(settings.manualStepLength == 0.9)
    }
}
