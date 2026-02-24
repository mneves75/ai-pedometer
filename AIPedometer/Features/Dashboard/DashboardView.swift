import SwiftUI

struct DashboardView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.healthKitSyncEnabled) private var healthKitSyncEnabled = true
    @Environment(StepTrackingService.self) private var trackingService
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var aiService
    @Environment(HealthKitAuthorization.self) private var healthAuthorization

    @State private var animateProgress = false
    @State private var dailyInsight: DailyInsight?
    @State private var insightError: AIServiceError?
    @State private var showHealthHelp = false

    private let progressRingSize: CGFloat = DesignTokens.Sizing.progressRing
    private let progressRingLineWidth: CGFloat = DesignTokens.Sizing.progressRingLineWidth

    private struct LoadTrigger: Hashable {
        let activityModeRaw: String
    }

    private struct InsightTrigger: Hashable {
        let activityModeRaw: String
        let aiAvailable: Bool
    }

    private var activityMode: ActivityTrackingMode {
        ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps
    }

    private var progress: Double {
        let goal = max(trackingService.currentGoal, 1)
        return min(Double(trackingService.todaySteps) / Double(goal), 1.0)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                headerSection
                healthPermissionBanner
                aiInsightSection
                progressRingSection
                statsGridSection
            }
        }
        .tabBarAwareScrollContentBottomInset()
        .accessibilityIdentifier(A11yID.Dashboard.view)
        .background(DesignTokens.Colors.surfaceGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(DesignTokens.Animation.smooth.delay(0.2)) {
                animateProgress = true
            }
        }
        .sheet(isPresented: $showHealthHelp) {
            HealthAccessHelpSheet()
        }
        .task(id: LoadTrigger(activityModeRaw: activityModeRaw)) {
            await trackingService.refreshTodayData()
        }
        .task(id: InsightTrigger(
            activityModeRaw: activityModeRaw,
            aiAvailable: aiService.availability.isAvailable
        )) {
            await loadDailyInsight()
        }
    }

    @ViewBuilder
    private var healthPermissionBanner: some View {
        if healthKitSyncEnabled && (healthAuthorization.status == .shouldRequest || trackingService.isUsingMotionFallback) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "heart.slash")
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text(String(localized: "Health Access Needed", comment: "Dashboard banner title when HealthKit is not authorized"))
                        .font(DesignTokens.Typography.headline)
                    Spacer()
                }

                Text(bannerDescription)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    if healthAuthorization.status == .shouldRequest {
                        Button(String(localized: "Grant Access", comment: "Button to request Health access")) {
                            Task {
                                do {
                                    try await healthAuthorization.requestAuthorization()
                                } catch {
                                    Loggers.health.warning("dashboard.healthkit_request_failed", metadata: [
                                        "error": error.localizedDescription
                                    ])
                                }
                                await healthAuthorization.refreshStatus()
                                await trackingService.refreshTodayData()
                            }
                        }
                        .glassButton()
                    } else {
                        Button(String(localized: "How to enable", comment: "Button to open Health access instructions")) {
                            showHealthHelp = true
                        }
                        .glassButton()
                    }

                    Spacer()
                }
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard(cornerRadius: DesignTokens.CornerRadius.xl, interactive: false)
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private var bannerDescription: String {
        if trackingService.isUsingMotionFallback {
            return String(
                localized: "We're using Motion & Fitness data. Enable Health access to include Apple Watch steps and improve history.",
                comment: "Dashboard banner description when falling back to Motion due to missing HealthKit read access"
            )
        }
        return String(localized: "Enable Health access to improve history and insights.", comment: "Dashboard banner description when HealthKit not authorized")
    }

    // MARK: - AI Insight

    @ViewBuilder
    private var aiInsightSection: some View {
        if aiService.availability.isAvailable {
            AIInsightCard(
                insight: dailyInsight,
                isLoading: insightService.isGeneratingDailyInsight,
                error: insightError,
                onRefresh: { Task { await loadDailyInsight(forceRefresh: true) } },
                onRetry: { Task { await loadDailyInsight() } }
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else if case .unavailable(let reason) = aiService.availability {
            AIAvailabilityBanner(reason: reason)
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private func loadDailyInsight(forceRefresh: Bool = false) async {
        guard aiService.availability.isAvailable else { return }

        insightError = nil
        do {
            dailyInsight = try await insightService.generateDailyInsight(forceRefresh: forceRefresh)
        } catch {
            insightError = error
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(String(localized: "Today", comment: "Dashboard header label for current day"))
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Text(String(localized: "Dashboard", comment: "Dashboard screen title"))
                    .font(DesignTokens.Typography.largeTitle.bold())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Today's Dashboard", comment: "Accessibility label for dashboard header"))

            Spacer()

            profileButton
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private var profileButton: some View {
        NavigationLink {
            SettingsView()
        } label: {
            Image(systemName: "person.circle.fill")
                .font(DesignTokens.Typography.title)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 44, height: 44)
        }
        .glassCard(cornerRadius: DesignTokens.CornerRadius.xxl, interactive: true)
        .accessibilityIdentifier("profile_button")
        .accessibleButton(label: String(localized: "Profile", comment: "Accessibility label for profile button"), hint: String(localized: "Opens your profile settings", comment: "Accessibility hint for profile button"))
    }

    // MARK: - Progress Ring

    private var progressRingSection: some View {
        ZStack {
            progressRingBackground
            progressRingForeground
            progressRingContent
        }
        .frame(width: progressRingSize, height: progressRingSize)
        .padding(.vertical, DesignTokens.Spacing.md)
        .accessibleProgress(
            label: Localization.format(
                "Daily %@ progress",
                comment: "Accessibility label for daily progress, with unit name",
                activityMode.unitName
            ),
            value: progress
        )
        .uiTestMarker(A11yID.Dashboard.steps(trackingService.todaySteps))
        .uiTestMarker(A11yID.Dashboard.goal(trackingService.currentGoal))
    }

    private var progressRingBackground: some View {
        Circle()
            .stroke(lineWidth: progressRingLineWidth)
            .foregroundStyle(DesignTokens.Colors.textQuaternary)
    }

    private var progressRingForeground: some View {
        Circle()
            .trim(from: 0, to: animateProgress ? progress : 0)
            .stroke(
                AngularGradient(
                    colors: [
                        DesignTokens.Colors.accent,
                        DesignTokens.Colors.accentMuted,
                        DesignTokens.Colors.accent
                    ],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: progressRingLineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: DesignTokens.Colors.accent.opacity(0.3), radius: 10)
    }

    private var progressRingContent: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(trackingService.todaySteps.formattedSteps)
                .font(.system(size: DesignTokens.FontSize.md, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(
                Localization.format(
                    "of %@ %@",
                    comment: "Label for progress ring showing goal and unit",
                    trackingService.currentGoal.formatted(),
                    activityMode.unitName
                )
            )
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Stats Grid

    @ViewBuilder
    private var statsGridSection: some View {
        if LaunchConfiguration.isUITesting() {
            statsGrid
                .padding(.horizontal, DesignTokens.Spacing.md)
        } else if #available(iOS 26, *) {
            GlassEffectContainer(spacing: DesignTokens.Spacing.md) {
                statsGrid
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else {
            statsGrid
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: DesignTokens.Spacing.md
        ) {
            StatCard(
                icon: activityMode.iconName,
                title: String(localized: "Distance"),
                value: trackingService.todayDistance.formattedDistance(),
                color: DesignTokens.Colors.accent
            )
            StatCard(
                icon: "flame.fill",
                title: String(localized: "Calories", comment: "Dashboard stat card title"),
                value: "\(trackingService.todayCalories.formattedCalories()) \(String(localized: "kcal", comment: "Calories unit"))",
                color: DesignTokens.Colors.orange
            )
            StatCard(
                icon: "figure.stairs",
                title: String(localized: "Floors", comment: "Dashboard stat card title"),
                value: "\(trackingService.todayFloors)",
                color: DesignTokens.Colors.green
            )
            StatCard(
                icon: "flame.circle",
                title: String(localized: "Streak", comment: "Dashboard stat card title for current streak"),
                value: Localization.format(
                    "%lld days",
                    comment: "The value of the stat card for the current streak.",
                    Int64(trackingService.currentStreak)
                ),
                color: DesignTokens.Colors.accent
            )
        }
    }

}

// MARK: - Stat Card

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.title2)
                .foregroundStyle(color)
                .applyIfNotUITesting { view in
                    view.symbolEffect(.pulse, options: .repeating.speed(0.5))
                }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(value)
                    .font(DesignTokens.Typography.title3.bold())
                    .monospacedDigit()
                Text(title)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .glassCard()
        .accessibleStatistic(title: title, value: value)
    }
}

#Preview {
    @MainActor in
    let demoModeStore = DemoModeStore()
    let healthKitService = HealthKitServiceFallback(demoModeStore: demoModeStore)
    let healthAuthorization = HealthKitAuthorization()
    let fmService = FoundationModelsService()
    let persistence = PersistenceController.shared
    let goalService = GoalService(persistence: persistence)
    let streakCalculator = StreakCalculator(stepAggregator: StepDataAggregator(), goalService: goalService)
    let badgeService = BadgeService(persistence: persistence)
    return DashboardView()
        .environment(StepTrackingService(
            healthKitService: healthKitService,
            motionService: MotionService(),
            healthAuthorization: healthAuthorization,
            goalService: goalService,
            badgeService: badgeService,
            dataStore: SharedDataStore(),
            streakCalculator: streakCalculator
        ))
        .environment(healthAuthorization)
        .environment(fmService)
        .environment(InsightService(
            foundationModelsService: fmService,
            healthKitService: healthKitService,
            goalService: goalService,
            dataStore: SharedDataStore()
        ))
        .environment(demoModeStore)
}
