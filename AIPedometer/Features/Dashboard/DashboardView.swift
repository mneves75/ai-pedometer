import SwiftUI

struct DashboardView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @Environment(StepTrackingService.self) private var trackingService
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var aiService

    @State private var animateProgress = false
    @State private var dailyInsight: DailyInsight?
    @State private var insightError: AIServiceError?

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
                aiInsightSection
                progressRingSection
                statsGridSection
            }
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(DesignTokens.Animation.smooth.delay(0.2)) {
                animateProgress = true
            }
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Dashboard", comment: "Dashboard screen title"))
                    .font(.largeTitle.bold())
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
                .font(.title)
                .symbolRenderingMode(.hierarchical)
        }
        .glassCard(cornerRadius: DesignTokens.CornerRadius.xxl, interactive: true)
        .accessibleButton(label: String(localized: "Profile", comment: "Accessibility label for profile button"), hint: String(localized: "Opens your profile settings", comment: "Accessibility hint for profile button"))
    }

    // MARK: - Progress Ring

    private var progressRingSection: some View {
        ZStack {
            progressRingBackground
            progressRingForeground
            progressRingContent
        }
        .frame(width: 250, height: 250)
        .padding(.vertical, DesignTokens.Spacing.md)
        .accessibleProgress(
            label: Localization.format(
                "Daily %@ progress",
                comment: "Accessibility label for daily progress, with unit name",
                activityMode.unitName
            ),
            value: progress
        )
    }

    private var progressRingBackground: some View {
        Circle()
            .stroke(lineWidth: 20)
            .foregroundStyle(.quaternary)
    }

    private var progressRingForeground: some View {
        Circle()
            .trim(from: 0, to: animateProgress ? progress : 0)
            .stroke(
                AngularGradient(
                    colors: [.blue, .purple, .blue],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: 20, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: .blue.opacity(0.3), radius: 10)
    }

    private var progressRingContent: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text("\(trackingService.todaySteps)")
                .font(.system(size: 48, weight: .bold, design: .rounded))
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                color: .blue
            )
            StatCard(
                icon: "flame.fill",
                title: String(localized: "Calories", comment: "Dashboard stat card title"),
                value: "\(trackingService.todayCalories.formattedCalories()) \(String(localized: "kcal", comment: "Calories unit"))",
                color: .orange
            )
            StatCard(
                icon: "figure.stairs",
                title: String(localized: "Floors", comment: "Dashboard stat card title"),
                value: "\(trackingService.todayFloors)",
                color: .green
            )
            StatCard(
                icon: "flame.circle",
                title: String(localized: "Streak", comment: "Dashboard stat card title for current streak"),
                value: Localization.format(
                    "%lld days",
                    comment: "The value of the stat card for the current streak.",
                    Int64(trackingService.currentStreak)
                ),
                color: .purple
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
                .font(.title2)
                .foregroundStyle(color)
                .applyIfNotUITesting { view in
                    view.symbolEffect(.pulse, options: .repeating.speed(0.5))
                }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(value)
                    .font(.title3.bold())
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
    let fmService = FoundationModelsService()
    let persistence = PersistenceController.shared
    let goalService = GoalService(persistence: persistence)
    let streakCalculator = StreakCalculator(stepAggregator: StepDataAggregator(), goalService: goalService)
    let badgeService = BadgeService(persistence: persistence)
    return DashboardView()
        .environment(StepTrackingService(
            healthKitService: healthKitService,
            motionService: MotionService(),
            goalService: goalService,
            badgeService: badgeService,
            dataStore: SharedDataStore(),
            streakCalculator: streakCalculator
        ))
        .environment(fmService)
        .environment(InsightService(
            foundationModelsService: fmService,
            healthKitService: healthKitService,
            goalService: goalService,
            dataStore: SharedDataStore()
        ))
        .environment(demoModeStore)
}
