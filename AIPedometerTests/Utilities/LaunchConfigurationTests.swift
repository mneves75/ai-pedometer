import Foundation
import Testing

@testable import AIPedometer

struct LaunchConfigurationTests {
    @Test
    func detectsUITestingFlag() {
        let args = ["-ui-testing"]
        #expect(LaunchConfiguration.isUITesting(arguments: args, environment: [:]))
    }

    @Test
    func ignoresMissingFlag() {
        let args = ["-something-else"]
        #expect(!LaunchConfiguration.isUITesting(arguments: args, environment: [:]))
    }

    @Test
    func detectsUITestingEnvironmentFlag() {
        let args = ["-something-else"]
        let environment = ["UI_TESTING": "1"]
        #expect(LaunchConfiguration.isUITesting(arguments: args, environment: environment))
    }

    @Test
    func ignoresDisabledUITestingEnvironmentFlag() {
        let args = ["-something-else"]
        let environment = ["UI_TESTING": "0"]
        #expect(!LaunchConfiguration.isUITesting(arguments: args, environment: environment))
    }

    @Test
    func detectsResetStateFlag() {
        let args = ["-reset-state"]
        #expect(LaunchConfiguration.shouldResetState(arguments: args))
    }

    @Test
    func detectsForcedPremiumFlag() {
        let args = ["-force-premium-on"]
        #expect(LaunchConfiguration.forcedPremiumEnabled(arguments: args, environment: [:]) == true)
    }

    @Test
    func detectsForcedAIUnavailableOnlyInUITesting() {
        let arguments = ["-ui-testing", "-force-ai-unavailable"]

        #expect(LaunchConfiguration.isAIUnavailableForced(arguments: arguments, environment: [:]))
        #expect(!LaunchConfiguration.isAIUnavailableForced(
            arguments: ["-force-ai-unavailable"],
            environment: [:]
        ))
    }

    @Test
    func detectsUnfinishedWorkoutSeedOnlyInUITesting() {
        let arguments = ["-ui-testing", "-seed-unfinished-workout"]

        #expect(LaunchConfiguration.shouldSeedUnfinishedWorkout(arguments: arguments, environment: [:]))
        #expect(!LaunchConfiguration.shouldSeedUnfinishedWorkout(
            arguments: ["-seed-unfinished-workout"],
            environment: [:]
        ))
    }

    @Test
    func detectsForcedPremiumEnvironmentFlag() {
        let environment = ["PREMIUM_ENABLED": "false"]
        #expect(LaunchConfiguration.forcedPremiumEnabled(arguments: [], environment: environment) == false)
    }

    @Test
    func nonOverridableModeIgnoresTestLaunchInputs() {
        let arguments = [
            "-ui-testing",
            "-reset-state",
            "-skip-onboarding",
            "-force-healthkit-sync-off",
            "-force-premium-on",
            "-force-ai-unavailable",
            "-seed-unfinished-workout"
        ]
        let environment = [
            "UI_TESTING": "1",
            "XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration",
            "DEMO_DETERMINISTIC": "1",
            "PREMIUM_ENABLED": "true"
        ]

        #expect(!LaunchConfiguration.isUITesting(
            arguments: arguments,
            environment: environment,
            allowsOverrides: false
        ))
        #expect(!LaunchConfiguration.isRunningXCTest(
            environment: environment,
            allowsOverrides: false
        ))
        #expect(!LaunchConfiguration.isTesting(
            arguments: arguments,
            environment: environment,
            allowsOverrides: false
        ))
        #expect(!LaunchConfiguration.shouldResetState(
            arguments: arguments,
            allowsOverrides: false
        ))
        #expect(!LaunchConfiguration.shouldSkipOnboarding(
            arguments: arguments,
            allowsOverrides: false
        ))
        #expect(LaunchConfiguration.forcedHealthKitSyncEnabled(
            arguments: arguments,
            allowsOverrides: false
        ) == nil)
        #expect(LaunchConfiguration.forcedPremiumEnabled(
            arguments: arguments,
            environment: environment,
            allowsOverrides: false
        ) == nil)
        #expect(!LaunchConfiguration.isAIUnavailableForced(
            arguments: arguments,
            environment: environment,
            allowsOverrides: false
        ))
        #expect(!LaunchConfiguration.shouldSeedUnfinishedWorkout(
            arguments: arguments,
            environment: environment,
            allowsOverrides: false
        ))
        #expect(!LaunchConfiguration.isDeterministicDemoDataEnabled(
            arguments: arguments,
            environment: environment,
            allowsOverrides: false
        ))
    }
}
