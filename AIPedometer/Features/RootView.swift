import SwiftUI

struct RootView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.onboardingCompleted) private var onboardingCompleted = false

    var body: some View {
        if onboardingCompleted {
            MainTabView()
        } else {
            OnboardingView()
        }
    }
}
