import SwiftUI

struct OnboardingView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.onboardingCompleted) private var onboardingCompleted = false
    @Environment(StepTrackingService.self) private var trackingService
    @State private var currentPage = 0
    @State private var dailyGoal: Double = Double(AppConstants.defaultDailyGoal)

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            TabView(selection: $currentPage) {
                welcomePage
                    .tag(0)

                goalPage
                    .tag(1)

                permissionsPage
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .accessibilityIdentifier("onboarding_pages")

            VStack {
                Spacer()

                Button(action: handleNext) {
                    Text(currentPage == 2 ? String(localized: "Get Started", comment: "Final onboarding button") : String(localized: "Next", comment: "Onboarding navigation button"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
                .accessibilityIdentifier(primaryButtonIdentifier)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.xxl)
                .accessibleButton(
                    label: currentPage == 2 ? String(localized: "Get Started", comment: "Final onboarding button") : String(localized: "Next", comment: "Onboarding navigation button"),
                    hint: currentPage == 2 ? String(localized: "Finishes onboarding", comment: "Accessibility hint for Get Started button") : String(localized: "Moves to the next step", comment: "Accessibility hint for Next button in onboarding")
                )
            }
        }
    }
    
    private var welcomePage: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "figure.walk")
                .font(.system(size: 80))
                .foregroundColor(.blue)
                .padding(DesignTokens.Spacing.md)
                .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)

            Text(String(localized: "Welcome to AI Pedometer", comment: "Onboarding welcome title"))
                .font(.largeTitle)
                .bold()
                .multilineTextAlignment(.center)

            Text(String(localized: "Track your steps with the power of AI.", comment: "Onboarding welcome subtitle"))
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .padding(DesignTokens.Spacing.md)
    }
    
    private var goalPage: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Text(String(localized: "Set Your Daily Goal", comment: "Onboarding page title for goal setting"))
                .font(.title)
                .bold()

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(
                    Localization.format(
                        "%lld steps",
                        comment: "Step count with unit",
                        Int64(dailyGoal)
                    )
                )
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.blue)

                Slider(value: $dailyGoal, in: 1000...20000, step: 500)
                    .tint(.blue)
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)

            Text(String(localized: "You can change this later in settings.", comment: "Onboarding note about goal settings"))
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(DesignTokens.Spacing.md)
    }

    private var permissionsPage: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text(String(localized: "Permissions", comment: "Onboarding permissions page title"))
                .font(.title)
                .bold()

            Text(String(localized: "We need access to your motion data to count steps.", comment: "Onboarding permissions explanation"))
                .multilineTextAlignment(.center)
                .padding(DesignTokens.Spacing.md)
                .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)
        }
        .padding(DesignTokens.Spacing.md)
    }

    private var primaryButtonIdentifier: String {
        currentPage == 2 ? "onboarding_get_started_button" : "onboarding_next_button"
    }
    
    private func handleNext() {
        HapticService.shared.tap()
        if currentPage < 2 {
            withAnimation(DesignTokens.Animation.snappy) {
                currentPage += 1
            }
        } else {
            Task {
                await trackingService.updateGoalAndRefresh(Int(dailyGoal))
            }
            withAnimation(DesignTokens.Animation.smooth) {
                onboardingCompleted = true
            }
        }
    }
}

#Preview {
    let persistence = PersistenceController.shared
    let goalService = GoalService(persistence: persistence)
    let streakCalculator = StreakCalculator(stepAggregator: StepDataAggregator(), goalService: goalService)
    let badgeService = BadgeService(persistence: persistence)
    return OnboardingView()
        .environment(StepTrackingService(
            healthKitService: HealthKitService(),
            motionService: MotionService(),
            goalService: goalService,
            badgeService: badgeService,
            dataStore: SharedDataStore(),
            streakCalculator: streakCalculator
        ))
}
