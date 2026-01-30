import Foundation

struct ActivitySettings: Sendable, Equatable {
    let activityMode: ActivityTrackingMode
    let distanceMode: DistanceEstimationMode
    let manualStepLength: Double

    static func current(userDefaults: UserDefaults = .standard) -> ActivitySettings {
        let activityModeRaw = userDefaults.string(forKey: AppConstants.UserDefaultsKeys.activityTrackingMode)
            ?? ActivityTrackingMode.steps.rawValue
        let distanceModeRaw = userDefaults.string(forKey: AppConstants.UserDefaultsKeys.distanceEstimationMode)
            ?? DistanceEstimationMode.automatic.rawValue
        let storedStepLength = userDefaults.double(forKey: AppConstants.UserDefaultsKeys.manualStepLengthMeters)
        let resolvedStepLength = storedStepLength > 0 ? storedStepLength : AppConstants.Defaults.manualStepLengthMeters

        return ActivitySettings(
            activityMode: ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps,
            distanceMode: DistanceEstimationMode(rawValue: distanceModeRaw) ?? .automatic,
            manualStepLength: resolvedStepLength
        )
    }
}
