import Foundation
import Observation

enum LaunchConfiguration {
    private static let uiTestingArgument = "-ui-testing"
    private static let uiTestingEnvironmentKey = "UI_TESTING"

    static func isUITesting(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        isUITesting(
            arguments: arguments,
            environment: ProcessInfo.processInfo.environment
        )
    }

    static func isUITesting(
        arguments: [String],
        environment: [String: String]
    ) -> Bool {
        if arguments.contains(uiTestingArgument) {
            return true
        }
        if let envValue = environment[uiTestingEnvironmentKey] {
            let normalizedValue = envValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalizedValue == "1" || normalizedValue == "true"
        }
        return false
    }

    static func shouldResetState(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-reset-state")
    }

    static var isDemoModeSupported: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

// MARK: - Demo Mode

enum DemoModeKeys {
    static let useFakeData = "demo_mode_fake_data"
}

/// Manages demo mode settings for testing and showcasing the app.
///
/// Demo mode has one setting:
/// - `useFakeData`: When true, uses synthetic HealthKit data; when false, uses real user data
///
/// The default configuration (`useFakeData: false`) uses the user's actual health data.
@MainActor
@Observable
final class DemoModeStore {
    private let userDefaults: UserDefaults
    private let isDemoModeSupported: Bool
    private var storedUseFakeData: Bool
    @ObservationIgnored var onChange: (() -> Void)?

    /// When enabled, uses synthetic/fake HealthKit data instead of real user data.
    /// Useful for UI testing, screenshots, or when HealthKit is unavailable.
    /// Default is `false` to preserve user's real data in demo mode.
    var useFakeData: Bool {
        get { storedUseFakeData }
        set {
            guard isDemoModeSupported else { return }
            storedUseFakeData = newValue
            userDefaults.set(newValue, forKey: DemoModeKeys.useFakeData)
            Loggers.app.info("demo_mode.fake_data_updated", metadata: ["enabled": "\(newValue)"])
            onChange?()
        }
    }

    /// Convenience property: true when demo mode should use synthetic data.
    /// This is true when explicitly enabled OR during UI testing.
    var shouldUseFakeData: Bool {
        storedUseFakeData || LaunchConfiguration.isUITesting()
    }

    init(userDefaults: UserDefaults? = nil) {
        let resolvedDefaults = userDefaults
            ?? UserDefaults(suiteName: AppConstants.appGroupID)
            ?? .standard
        self.userDefaults = resolvedDefaults
        self.isDemoModeSupported = LaunchConfiguration.isDemoModeSupported
        self.storedUseFakeData = isDemoModeSupported
            ? resolvedDefaults.bool(forKey: DemoModeKeys.useFakeData)
            : false
    }
}
