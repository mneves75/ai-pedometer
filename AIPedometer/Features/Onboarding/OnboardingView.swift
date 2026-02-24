import SwiftUI
import UIKit

struct OnboardingView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.onboardingCompleted) private var onboardingCompleted = false
    @Environment(StepTrackingService.self) private var trackingService
    @Environment(HealthKitAuthorization.self) private var healthAuthorization
    @Environment(MotionAuthorization.self) private var motionAuthorization
    @State private var currentPage = 0
    @State private var dailyGoal: Double = Double(AppConstants.defaultDailyGoal)
    @State private var isRequestingPermissions = false

    var body: some View {
        ZStack {
            DesignTokens.Colors.surfaceGrouped.ignoresSafeArea()

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
            .overlay(alignment: .topTrailing) {
                if currentPage < 2 {
                    skipButton
                }
            }

            VStack {
                Spacer()

                Button(action: handleNext) {
                    Text(currentPage == 2 ? L10n.localized("Get Started", comment: "Final onboarding button") : L10n.localized("Next", comment: "Onboarding navigation button"))
                        .font(DesignTokens.Typography.headline)
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
                .accessibilityIdentifier(primaryButtonIdentifier)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.bottom, DesignTokens.Spacing.xxl)
                .accessibleButton(
                    label: currentPage == 2 ? L10n.localized("Get Started", comment: "Final onboarding button") : L10n.localized("Next", comment: "Onboarding navigation button"),
                    hint: currentPage == 2 ? L10n.localized("Finishes onboarding", comment: "Accessibility hint for Get Started button") : L10n.localized("Moves to the next step", comment: "Accessibility hint for Next button in onboarding")
                )
            }
        }
    }
    
    private var welcomePage: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "figure.walk")
                .font(.system(size: DesignTokens.FontSize.xxl))
                .foregroundStyle(DesignTokens.Colors.accent)
                .padding(DesignTokens.Spacing.md)
                .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)

            Text(L10n.localized("Welcome to AI Pedometer", comment: "Onboarding welcome title"))
                .font(DesignTokens.Typography.largeTitle)
                .bold()
                .multilineTextAlignment(.center)

            Text(L10n.localized("Track your steps with the power of AI.", comment: "Onboarding welcome subtitle"))
                .font(DesignTokens.Typography.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.md)
    }
    
    private var goalPage: some View {
        VStack(spacing: DesignTokens.Spacing.xl) {
            Text(L10n.localized("Set Your Daily Goal", comment: "Onboarding page title for goal setting"))
                .font(DesignTokens.Typography.title)
                .bold()

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(
                    Localization.format(
                        "%lld steps",
                        comment: "Step count with unit",
                        Int64(dailyGoal)
                    )
                )
                    .font(.system(size: DesignTokens.FontSize.md, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.accent)

                Slider(value: $dailyGoal, in: 1000...20000, step: 500)
                    .tint(DesignTokens.Colors.accent)
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)

            Text(L10n.localized("You can change this later in settings.", comment: "Onboarding note about goal settings"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.md)
    }

    private var permissionsPage: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: DesignTokens.FontSize.lg))
                .foregroundStyle(DesignTokens.Colors.accent)

            Text(L10n.localized("Permissions", comment: "Onboarding permissions page title"))
                .font(DesignTokens.Typography.title)
                .bold()

            Text(L10n.localized("We need access to your motion and Health data to count steps.", comment: "Onboarding permissions explanation"))
                .multilineTextAlignment(.center)
                .padding(DesignTokens.Spacing.md)
                .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)

            VStack(spacing: DesignTokens.Spacing.sm) {
                permissionStatusRow(
                    title: L10n.localized("Health", comment: "Permission label for Apple Health access"),
                    status: healthAuthorization.status
                )
                permissionStatusRow(
                    title: L10n.localized("Motion & Fitness", comment: "Permission label for Motion & Fitness access"),
                    status: motionAuthorization.status
                )
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)

            VStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    Task { await requestPermissionsIfNeeded() }
                } label: {
                    Text(
                        isRequestingPermissions
                            ? L10n.localized("Requesting Access...", comment: "Onboarding permissions button while requesting access")
                            : L10n.localized("Grant Access", comment: "Onboarding permissions button to request access")
                    )
                    .font(DesignTokens.Typography.headline)
                    .frame(maxWidth: .infinity)
                }
                .glassButton()
                .disabled(isRequestingPermissions)

                if healthAuthorization.status == .requested || motionAuthorization.status == .denied {
                    Button(L10n.localized("Open Settings", comment: "Button to open system settings")) {
                        openSystemSettings()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
    }

    private var primaryButtonIdentifier: String {
        currentPage == 2 ? "onboarding_get_started_button" : "onboarding_next_button"
    }

    private var skipButton: some View {
        Button(L10n.localized("Skip", comment: "Onboarding skip button")) {
            HapticService.shared.tap()
            completeOnboarding()
        }
        .font(DesignTokens.Typography.footnote.weight(.semibold))
        .foregroundStyle(DesignTokens.Colors.textSecondary)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.md)
        .accessibilityIdentifier("onboarding_skip_button")
        .accessibleButton(label: L10n.localized("Skip", comment: "Onboarding skip button"))
    }
    
    private func handleNext() {
        HapticService.shared.tap()
        if currentPage < 2 {
            withAnimation(DesignTokens.Animation.snappy) {
                currentPage += 1
            }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        if LaunchConfiguration.isUITesting() {
            trackingService.updateGoal(Int(dailyGoal))
            onboardingCompleted = true
            UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.onboardingCompleted)
            Loggers.app.info("onboarding.completed_set", metadata: ["value": "true"])
        } else {
            Task {
                await requestPermissionsIfNeeded()
                await trackingService.updateGoalAndRefresh(Int(dailyGoal))
            }
            withAnimation(DesignTokens.Animation.smooth) {
                onboardingCompleted = true
            }
        }
    }

    private func requestPermissionsIfNeeded() async {
        guard !LaunchConfiguration.isTesting() else { return }
        guard !isRequestingPermissions else { return }
        isRequestingPermissions = true
        defer { isRequestingPermissions = false }

        await healthAuthorization.refreshStatus()
        motionAuthorization.refreshStatus()

        if healthAuthorization.status == .shouldRequest {
            do {
                try await healthAuthorization.requestAuthorization()
            } catch {
                // If denied, the correct next step is Settings.
                Loggers.health.warning("onboarding.healthkit_request_failed", metadata: [
                    "error": error.localizedDescription
                ])
            }
        }

        if motionAuthorization.status == .notDetermined {
            await trackingService.requestMotionAccessProbe()
        }

        await healthAuthorization.refreshStatus()
        motionAuthorization.refreshStatus()
    }

    private func permissionStatusRow(title: String, status: HealthKitAccessStatus) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: statusSymbol(for: status))
                .foregroundStyle(statusColor(for: status))
            Text(title)
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
            Spacer()
            Text(statusLabel(for: status))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(statusLabel(for: status))")
    }

    private func permissionStatusRow(title: String, status: MotionAuthStatus) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: statusSymbol(for: status))
                .foregroundStyle(statusColor(for: status))
            Text(title)
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
            Spacer()
            Text(statusLabel(for: status))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(statusLabel(for: status))")
    }

    private func statusSymbol(for status: HealthKitAccessStatus) -> String {
        switch status {
        case .requested: "checkmark.circle.fill"
        case .shouldRequest: "questionmark.circle"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for status: HealthKitAccessStatus) -> Color {
        switch status {
        case .requested: DesignTokens.Colors.success
        case .shouldRequest: DesignTokens.Colors.textSecondary
        case .unavailable: DesignTokens.Colors.warning
        }
    }

    private func statusLabel(for status: HealthKitAccessStatus) -> String {
        switch status {
        case .requested:
            L10n.localized("Requested", comment: "Permissions status: authorization already requested")
        case .shouldRequest:
            L10n.localized("Not Requested", comment: "Permissions status: not requested yet")
        case .unavailable:
            L10n.localized("Unavailable", comment: "Permissions status: unavailable on this device")
        }
    }

    private func statusSymbol(for status: MotionAuthStatus) -> String {
        switch status {
        case .authorized: "checkmark.circle.fill"
        case .notDetermined: "questionmark.circle"
        case .denied: "xmark.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private func statusColor(for status: MotionAuthStatus) -> Color {
        switch status {
        case .authorized: DesignTokens.Colors.success
        case .notDetermined: DesignTokens.Colors.textSecondary
        case .denied: DesignTokens.Colors.warning
        case .unavailable: DesignTokens.Colors.warning
        }
    }

    private func statusLabel(for status: MotionAuthStatus) -> String {
        switch status {
        case .authorized:
            L10n.localized("Granted", comment: "Permissions status: granted")
        case .notDetermined:
            L10n.localized("Not Requested", comment: "Permissions status: not requested yet")
        case .denied:
            L10n.localized("Denied", comment: "Permissions status: denied")
        case .unavailable:
            L10n.localized("Unavailable", comment: "Permissions status: unavailable on this device")
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    let persistence = PersistenceController.shared
    let goalService = GoalService(persistence: persistence)
    let streakCalculator = StreakCalculator(stepAggregator: StepDataAggregator(), goalService: goalService)
    let badgeService = BadgeService(persistence: persistence)
    let healthAuthorization = HealthKitAuthorization()
    let motionAuthorization = MotionAuthorization()
    return OnboardingView()
        .environment(StepTrackingService(
            healthKitService: HealthKitService(),
            motionService: MotionService(),
            healthAuthorization: healthAuthorization,
            goalService: goalService,
            badgeService: badgeService,
            dataStore: SharedDataStore(),
            streakCalculator: streakCalculator
        ))
        .environment(healthAuthorization)
        .environment(motionAuthorization)
}
