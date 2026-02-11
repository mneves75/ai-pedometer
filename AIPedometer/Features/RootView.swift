import SwiftUI

struct RootView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.onboardingCompleted) private var onboardingCompleted = false

    var body: some View {
        let shouldBypassOnboarding = LaunchConfiguration.isTesting()
            && LaunchConfiguration.shouldSkipOnboarding()
        Group {
            if onboardingCompleted || shouldBypassOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .onChange(of: onboardingCompleted) { _, newValue in
            if LaunchConfiguration.isTesting() {
                Loggers.app.info("onboarding.completed_changed", metadata: ["value": "\(newValue)"])
            }
        }
    }
}
