import Foundation
import Observation

enum LaunchConfiguration {
    private static let uiTestingArgument = "-ui-testing"
    private static let skipOnboardingArgument = "-skip-onboarding"
    private static let forceHealthKitSyncOffArgument = "-force-healthkit-sync-off"
    private static let forceHealthKitSyncOnArgument = "-force-healthkit-sync-on"
    private static let uiTestingEnvironmentKey = "UI_TESTING"
    private static let demoDeterministicEnvironmentKey = "DEMO_DETERMINISTIC"

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

    static func isRunningXCTest(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        // XCTest sets at least one of these when running unit tests.
        if environment["XCTestConfigurationFilePath"] != nil { return true }
        if environment["XCTestBundlePath"] != nil { return true }
        if environment["XCTestSessionIdentifier"] != nil { return true }
        return false
    }

    static func isTesting(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        isUITesting(arguments: arguments) || isRunningXCTest()
    }

    static func shouldResetState(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains("-reset-state")
    }

    static func shouldSkipOnboarding(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        arguments.contains(skipOnboardingArgument)
    }

    static func forcedHealthKitSyncEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool? {
        if arguments.contains(forceHealthKitSyncOffArgument) { return false }
        if arguments.contains(forceHealthKitSyncOnArgument) { return true }
        return nil
    }

    static var isDemoModeSupported: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    static func isDeterministicDemoDataEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        // Deterministic demo data is primarily for UI tests/snapshots, not unit tests.
        // It can be forced on/off via env for debugging.
        if let value = environment[demoDeterministicEnvironmentKey] {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "0" || normalized == "false" { return false }
            if normalized == "1" || normalized == "true" { return true }
        }
        return isUITesting()
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
    /// This is true when explicitly enabled OR during UI tests.
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
