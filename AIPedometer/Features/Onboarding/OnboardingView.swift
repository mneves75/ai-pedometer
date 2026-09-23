import SwiftUI

enum OnboardingGoalPersistenceAction: Equatable {
    case complete
    case showSaveError

    init(didPersistGoal: Bool) {
        self = didPersistGoal ? .complete : .showSaveError
    }
}

/// One-tap daily goals on the goal page. They sit on the slider's grid, so choosing one and then
/// dragging lands on the same values.
enum OnboardingGoalPreset {
    static let sliderRange: ClosedRange<Double> = 1_000...20_000
    static let sliderStep: Double = 500
    static let values = [5_000, 7_500, 10_000, 12_500]
}

struct OnboardingView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.onboardingCompleted) private var onboardingCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(StepTrackingService.self) private var trackingService
    @Environment(HealthKitAuthorization.self) private var healthAuthorization
    @Environment(MotionAuthorization.self) private var motionAuthorization
    @State private var currentPage = 0
    @State private var dailyGoal: Double = Double(AppConstants.defaultDailyGoal)
    @State private var isRequestingPermissions = false
    @State private var showGoalSaveError = false
    @ScaledMetric(relativeTo: .largeTitle) private var goalValueFontSize = DesignTokens.FontSize.md

    private static let pageCount = 3
    private var isLastPage: Bool { currentPage == Self.pageCount - 1 }

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
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier("onboarding_pages")
            .overlay(alignment: .topTrailing) {
                // The Apple Health page is a pre-permission screen: its only action opens the system
                // alert (HIG, Privacy > Pre-alert screens), so it offers no way around it.
                if !isLastPage {
                    skipButton
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .alert(
            L10n.localized(
                "Unable to save goal. Please try again.",
                comment: "Goal editor save failure alert title"
            ),
            isPresented: $showGoalSaveError
        ) {
            Button(L10n.localized("OK", comment: "Dismiss alert button"), role: .cancel) {}
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        onboardingScrollPage {
            Image(systemName: "figure.walk")
                .font(.system(size: DesignTokens.FontSize.xl))
                .foregroundStyle(DesignTokens.Colors.accent)
                .padding(DesignTokens.Spacing.sm)
                .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)
                .breathingGlow(DesignTokens.Colors.accent)
                .applyIfMotionEnabled { view in
                    view.symbolEffect(.bounce, options: .repeating.speed(0.4))
                }
                .accessibilityHidden(true)

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(L10n.localized("Welcome to AI Pedometer", comment: "Onboarding welcome title"))
                    .font(DesignTokens.Typography.largeTitle)
                    .bold()
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.localized(
                    "Steps, workouts and an AI coach that runs on your device.",
                    comment: "Onboarding welcome subtitle"
                ))
                .font(DesignTokens.Typography.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                OnboardingFeatureRow(
                    symbol: "sparkles",
                    title: L10n.localized("AI on your device", comment: "Onboarding feature title"),
                    detail: L10n.localized(
                        "Insights, coaching and plans from Apple Intelligence on supported devices, without a cloud AI service.",
                        comment: "Onboarding feature detail for on-device AI"
                    )
                )
                OnboardingFeatureRow(
                    symbol: "lock.shield.fill",
                    title: L10n.localized("Private by design", comment: "Onboarding feature title"),
                    detail: L10n.localized(
                        "No account and no ads. The app never sends your health data to us or to third parties.",
                        comment: "Onboarding feature detail for privacy"
                    )
                )
                OnboardingFeatureRow(
                    symbol: "applewatch",
                    title: L10n.localized("iPhone, Apple Watch and widgets", comment: "Onboarding feature title"),
                    detail: L10n.localized(
                        "Your progress on your wrist and on your Home Screen.",
                        comment: "Onboarding feature detail for watch and widgets"
                    )
                )
                OnboardingFeatureRow(
                    symbol: "checkmark.seal.fill",
                    title: L10n.localized("Everything included", comment: "Onboarding feature title"),
                    detail: L10n.localized(
                        "Every feature comes with the app. No subscription.",
                        comment: "Onboarding feature detail for the one-time purchase"
                    )
                )
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)
        }
    }

    private var goalPage: some View {
        onboardingScrollPage(spacing: DesignTokens.Spacing.xl) {
            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(L10n.localized("Set Your Daily Goal", comment: "Onboarding page title for goal setting"))
                    .font(DesignTokens.Typography.title)
                    .bold()
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.localized(
                    "Pick a goal you can reach on most days.",
                    comment: "Onboarding goal page subtitle"
                ))
                .font(DesignTokens.Typography.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            VStack(spacing: DesignTokens.Spacing.md) {
                Text(
                    Localization.format(
                        "%@ steps",
                        comment: "Step count with unit",
                        Int(dailyGoal).formattedSteps
                    )
                )
                    .font(.system(size: goalValueFontSize, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.numericText(value: dailyGoal))
                    .animation(reduceMotion ? nil : DesignTokens.Animation.snappy, value: dailyGoal)
                    .accessibilityHidden(true)

                goalPresets

                Slider(
                    value: $dailyGoal,
                    in: OnboardingGoalPreset.sliderRange,
                    step: OnboardingGoalPreset.sliderStep
                )
                    .tint(DesignTokens.Colors.accent)
                    .accessibilityIdentifier(A11yID.Onboarding.goalSlider)
                    .accessibilityLabel(L10n.localized("Daily step goal", comment: "Accessibility label for daily step goal slider"))
                    .accessibilityValue(
                        Localization.format(
                            "%@ steps",
                            comment: "Step count with unit",
                            Int(dailyGoal).formattedSteps
                        )
                    )
                    .accessibilityHint(L10n.localized("You can change this later in settings.", comment: "Onboarding note about goal settings"))
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)

            Text(L10n.localized("You can change this later in settings.", comment: "Onboarding note about goal settings"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier(A11yID.Onboarding.goalNote)
        }
    }

    private var goalPresets: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.xs) { goalPresetButtons }
            VStack(spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) { goalPresetButtons(OnboardingGoalPreset.values.prefix(2)) }
                HStack(spacing: DesignTokens.Spacing.xs) { goalPresetButtons(OnboardingGoalPreset.values.suffix(2)) }
            }
        }
    }

    private var goalPresetButtons: some View {
        goalPresetButtons(OnboardingGoalPreset.values[...])
    }

    private func goalPresetButtons(_ values: ArraySlice<Int>) -> some View {
        ForEach(values, id: \.self) { value in
            let isSelected = Int(dailyGoal) == value
            Button {
                HapticService.shared.tap()
                dailyGoal = Double(value)
            } label: {
                Text(value.formattedSteps)
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: DesignTokens.TouchTarget.minimum)
            }
            .buttonStyle(.bordered)
            .tint(isSelected ? DesignTokens.Colors.accent : DesignTokens.Colors.textSecondary)
            .accessibilityIdentifier(A11yID.Onboarding.goalPreset(value))
            .accessibilityLabel(Localization.format("%@ steps", comment: "Step count with unit", value.formattedSteps))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private var permissionsPage: some View {
        onboardingScrollPage {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: DesignTokens.FontSize.lg))
                .foregroundStyle(DesignTokens.Colors.accent)
                .accessibilityHidden(true)

            VStack(spacing: DesignTokens.Spacing.sm) {
                Text(L10n.localized("Connect Apple Health", comment: "Onboarding permissions page title"))
                    .font(DesignTokens.Typography.title)
                    .bold()
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(L10n.localized(
                    "AI Pedometer counts your steps with Apple Health and your device's motion sensor. iOS asks for each one next.",
                    comment: "Onboarding permissions explanation"
                ))
                .multilineTextAlignment(.center)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .accessibilityIdentifier(A11yID.Onboarding.permissionsExplanation)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                OnboardingFeatureRow(
                    symbol: "heart.fill",
                    title: L10n.localized("Health", comment: "Permission label for Apple Health access"),
                    detail: L10n.localized(
                        "Reads steps, distance, floors, heart rate and workouts, and saves the workouts you record.",
                        comment: "Onboarding explanation of the Health permission"
                    )
                )
                OnboardingFeatureRow(
                    symbol: "figure.walk.motion",
                    title: L10n.localized("Motion & Fitness", comment: "Permission label for Motion & Fitness access"),
                    detail: L10n.localized(
                        "Counts steps live between Health updates.",
                        comment: "Onboarding explanation of the Motion & Fitness permission"
                    )
                )
                OnboardingFeatureRow(
                    symbol: "lock.fill",
                    title: L10n.localized("Stays with you", comment: "Onboarding privacy row title"),
                    detail: L10n.localized(
                        "The app never sends your health data to us or to third parties. You can change access anytime in Settings.",
                        comment: "Onboarding privacy row detail"
                    )
                )
            }
            .padding(DesignTokens.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(cornerRadius: DesignTokens.CornerRadius.xl)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(0..<Self.pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? DesignTokens.Colors.accent : DesignTokens.Colors.textQuaternary)
                        .frame(width: index == currentPage ? 20 : 8, height: 8)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pageIndicatorAccessibilityLabel)
            .accessibilityAddTraits(.isStaticText)

            Button(action: handleNext) {
                Text(primaryButtonTitle)
                    .font(DesignTokens.Typography.headline)
                    .frame(maxWidth: .infinity)
            }
            .glassButton()
            .accessibilityIdentifier(primaryButtonIdentifier)
            .disabled(isLastPage && isRequestingPermissions)
            .accessibleButton(
                label: primaryButtonTitle,
                hint: isLastPage
                    ? L10n.localized(
                        "Asks iOS for Health and motion access, then opens the app",
                        comment: "Accessibility hint for the last onboarding button"
                    )
                    : L10n.localized("Moves to the next step", comment: "Accessibility hint for Next button in onboarding")
            )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.sm)
        .padding(.bottom, DesignTokens.Spacing.md)
        .background(.bar)
        .accessibilityElement(children: .contain)
    }

    private func onboardingScrollPage<Content: View>(
        spacing: CGFloat = DesignTokens.Spacing.lg,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ScrollView {
            VStack(spacing: spacing) {
                content()
            }
            .frame(maxWidth: .infinity)
            .padding(DesignTokens.Spacing.md)
            .padding(.top, DesignTokens.Spacing.xl)
            .padding(.bottom, DesignTokens.Sizing.onboardingPageBottomInset)
        }
        .scrollIndicators(.hidden)
    }

    /// The last page's single button opens the system permission alerts, so it reads "Continue",
    /// not "Allow" (HIG, Privacy > Pre-alert screens).
    private var primaryButtonTitle: String {
        if isLastPage && isRequestingPermissions {
            return L10n.localized("Requesting Access...", comment: "Onboarding permissions button while requesting access")
        }

        return isLastPage
            ? L10n.localized("Continue", comment: "Last onboarding button; opens the system permission alerts")
            : L10n.localized("Next", comment: "Onboarding navigation button")
    }

    private var primaryButtonIdentifier: String {
        isLastPage ? "onboarding_get_started_button" : "onboarding_next_button"
    }

    private var pageIndicatorAccessibilityLabel: String {
        Localization.format(
            "Step %lld of %lld",
            comment: "Accessibility label for onboarding page indicator",
            Int64(currentPage + 1),
            Int64(Self.pageCount)
        )
    }

    private var skipButton: some View {
        Button {
            HapticService.shared.tap()
            skipOnboarding()
        } label: {
            Text(L10n.localized("Skip", comment: "Onboarding skip button"))
                .frame(minWidth: DesignTokens.TouchTarget.minimum, minHeight: DesignTokens.TouchTarget.minimum)
                .contentShape(Rectangle())
        }
        .font(DesignTokens.Typography.footnote.weight(.semibold))
        .foregroundStyle(DesignTokens.Colors.textSecondary)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.top, DesignTokens.Spacing.md)
        .accessibilityIdentifier("onboarding_skip_button")
        .accessibleButton(label: L10n.localized("Skip", comment: "Onboarding skip button"))
    }

    // MARK: - Actions

    private func handleNext() {
        HapticService.shared.tap()
        if !isLastPage {
            withAnimation(reduceMotion ? nil : DesignTokens.Animation.snappy) {
                currentPage += 1
            }
        } else {
            Task { await completeOnboarding() }
        }
    }

    private func skipOnboarding() {
        let didPersistGoal = trackingService.updateGoal(Int(dailyGoal))
        guard handleGoalPersistence(didPersistGoal) else { return }
        withAnimation(reduceMotion ? nil : DesignTokens.Animation.smooth) {
            onboardingCompleted = true
        }
        UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.onboardingCompleted)
        Loggers.app.info("onboarding.skipped")
    }

    private func completeOnboarding() async {
        let isUITesting = LaunchConfiguration.isUITesting()
        let didPersistGoal: Bool
        if isUITesting {
            didPersistGoal = trackingService.updateGoal(Int(dailyGoal))
        } else {
            await requestPermissionsIfNeeded()
            didPersistGoal = await trackingService.updateGoalAndRefresh(Int(dailyGoal))
        }

        guard handleGoalPersistence(didPersistGoal) else { return }
        if isUITesting {
            onboardingCompleted = true
            UserDefaults.standard.set(true, forKey: AppConstants.UserDefaultsKeys.onboardingCompleted)
            Loggers.app.info("onboarding.completed_set", metadata: ["value": "true"])
        } else {
            withAnimation(reduceMotion ? nil : DesignTokens.Animation.smooth) {
                onboardingCompleted = true
            }
        }
    }

    private func handleGoalPersistence(_ didPersistGoal: Bool) -> Bool {
        guard OnboardingGoalPersistenceAction(didPersistGoal: didPersistGoal) == .complete else {
            HapticService.shared.error()
            showGoalSaveError = true
            return false
        }
        return true
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
                // A denial is not an error for onboarding: the Dashboard offers Health access again.
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
}

/// An icon, a title and one sentence, read by VoiceOver as a single element.
private struct OnboardingFeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: symbol)
                .font(DesignTokens.Typography.title3)
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(minWidth: DesignTokens.FontSize.md)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(title)
                    .font(DesignTokens.Typography.headline)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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
