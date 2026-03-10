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
    func detectsForcedPremiumEnvironmentFlag() {
        let environment = ["PREMIUM_ENABLED": "false"]
        #expect(LaunchConfiguration.forcedPremiumEnabled(arguments: [], environment: environment) == false)
    }
}
