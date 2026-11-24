import SwiftUI

@MainActor
enum HeartRateDisplayFormatter {
    static let freshnessThreshold: TimeInterval = 5 * 60
    static let freshnessRefreshInterval: TimeInterval = 60

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .numeric
        formatter.locale = .autoupdatingCurrent
        return formatter
    }()

    static func visualText(sample: HeartRateSample?, now: Date = .now) -> String {
        guard let sample else {
            return L10n.localized("No Data", comment: "Dashboard stat fallback when a metric has no value")
        }
        let bpm = "\(HealthCount.clamped(sample.bpm.rounded())) \(L10n.localized("bpm", comment: "Heart rate unit"))"
        let age = now.timeIntervalSince(sample.endDate)
        guard age >= freshnessThreshold else { return bpm }
        let ageText = localizedAgeText(for: sample.endDate, relativeTo: now)
        return "\(bpm) · \(ageText)"
    }

    static func accessibilityText(sample: HeartRateSample?, now: Date = .now) -> String {
        guard let sample else {
            return L10n.localized("No Data", comment: "Dashboard stat fallback when a metric has no value")
        }
        let bpm = Localization.format(
            "%lld beats per minute",
            comment: "Accessibility value for heart rate",
            Int64(HealthCount.clamped(sample.bpm.rounded()))
        )
        let age = now.timeIntervalSince(sample.endDate)
        guard age >= freshnessThreshold else { return bpm }
        let ageText = localizedAgeText(for: sample.endDate, relativeTo: now)
        return "\(bpm), \(ageText)"
    }

    private static func localizedAgeText(for date: Date, relativeTo now: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: now)
    }
}

struct DashboardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.healthKitSyncEnabled) private var healthKitSyncEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(StepTrackingService.self) private var trackingService
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var aiService
    @Environment(HealthKitAuthorization.self) private var healthAuthorization

    @State private var animateProgress = false
    @State private var dailyInsight: DailyInsight?
    @State private var insightError: AIServiceError?
    @State private var insightRequestID = UUID()
    @State private var showHealthHelp = false
    @ScaledMetric(relativeTo: .largeTitle) private var progressValueFontSize = DesignTokens.FontSize.md

    // Hidden easter egg: tapping the ring's center triggers a local confetti burst
    // (automatically suppressed under Reduce Motion).
    @State private var secretTapCount = 0
    @State private var celebrateSecret = false
    private static let secretTapThreshold = 7

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

    private var goalReached: Bool {
        progress >= 1
    }

    /// Quarter-goal bucket (0...4) used to fire a light haptic at 25/50/75%.
    static func milestoneBucket(progress: Double) -> Int {
        guard progress > 0 else { return 0 }
        return min(Int(progress * 4), 4)
    }

    private func registerSecretTap() {
        secretTapCount += 1
        guard secretTapCount >= Self.secretTapThreshold else { return }
        secretTapCount = 0
        HapticService.shared.success()
        withAnimation(reduceMotion ? nil : DesignTokens.Animation.smooth) {
            celebrateSecret = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2.4))
            withAnimation(reduceMotion ? nil : DesignTokens.Animation.smooth) {
                celebrateSecret = false
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                heroSection
                statsGridSection
                healthPermissionBanner
                aiInsightSection
            }
            .padding(.horizontal, DesignTokens.Spacing.mdPlus)
            .padding(.top, DesignTokens.Spacing.sm)
        }
        .overlay {
            if celebrateSecret {
                ConfettiView()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .tabBarAwareScrollContentBottomInset()
        .accessibilityIdentifier(A11yID.Dashboard.view)
        .uiTestMarker(
            A11yID.AIAvailability.banner,
            when: !aiService.availability.isAvailable
        )
        .background {
            AmbientZenithBackground()
        }
        .navigationTitle(L10n.localized("Today", comment: "Dashboard header label for current day"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                profileButton
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : DesignTokens.Animation.smooth.delay(0.1)) {
                animateProgress = true
            }
        }
        .sensoryFeedback(.success, trigger: goalReached) { _, newValue in newValue }
        .sensoryFeedback(trigger: Self.milestoneBucket(progress: progress)) { oldValue, newValue in
            (newValue > oldValue && newValue < 4) ? .impact(weight: .light) : nil
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

    // MARK: - Toolbar

    private var profileButton: some View {
        NavigationLink {
            SettingsView()
        } label: {
            Image(systemName: "person.circle.fill")
                .symbolRenderingMode(.hierarchical)
        }
        .accessibilityIdentifier("profile_button")
        .accessibleButton(
            label: L10n.localized("Profile", comment: "Accessibility label for profile button"),
            hint: L10n.localized("Opens your profile settings", comment: "Accessibility hint for profile button")
        )
    }

    // MARK: - Hero (Unobstructed First-Viewport Focus)

    private var heroSection: some View {
        VStack(spacing: DesignTokens.Spacing.mdPlus) {
            progressRingSection
            streakPill
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private var progressRingSection: some View {
        ZStack {
            progressRingBackground
            progressRingForeground
            progressRingTip
            progressRingContent
                .contentShape(Circle())
                .onTapGesture {
                    registerSecretTap()
                }
        }
        .frame(width: progressRingSize, height: progressRingSize)
        .goalCelebration(trigger: goalReached)
        .accessibilityElement(children: .combine)
        .accessibleProgress(
            label: Localization.format(
                "Daily %@ progress",
                comment: "Accessibility label for daily progress, with unit name",
                activityMode.unitName
            ),
            value: progress,
            valueDescription: Localization.format(
                "%@ of %@ %@",
                comment: "Accessibility value for daily progress with current and goal counts",
                trackingService.todaySteps.formattedSteps,
                trackingService.currentGoal.formattedSteps,
                activityMode.unitName
            )
        )
        .uiTestMarker(A11yID.Dashboard.steps(trackingService.todaySteps))
        .uiTestMarker(A11yID.Dashboard.goal(trackingService.currentGoal))
    }

    private var progressRingBackground: some View {
        Circle()
            .stroke(lineWidth: progressRingLineWidth)
            .foregroundStyle(DesignTokens.Colors.borderMuted.opacity(0.45))
    }

    private var progressRingForeground: some View {
        Circle()
            .trim(from: 0, to: animateProgress ? progress : 0)
            .stroke(
                AngularGradient(
                    colors: [
                        DesignTokens.Colors.mint,
                        DesignTokens.Colors.cyan,
                        DesignTokens.Colors.accent,
                        DesignTokens.Colors.mint
                    ],
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                style: StrokeStyle(lineWidth: progressRingLineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .breathingGlow(DesignTokens.Colors.accent, isActive: animateProgress && progress > 0)
    }

    private var progressRingTip: some View {
        let radius = (progressRingSize - progressRingLineWidth) / 2
        let angle = Angle.degrees((animateProgress ? progress : 0) * 360 - 90)
        return Circle()
            .fill(DesignTokens.Colors.inverseText)
            .frame(width: progressRingLineWidth * 0.65, height: progressRingLineWidth * 0.65)
            .overlay {
                Circle()
                    .fill(DesignTokens.Colors.accent)
                    .frame(width: progressRingLineWidth * 0.32, height: progressRingLineWidth * 0.32)
            }
            .shadow(color: DesignTokens.Colors.accent.opacity(0.45), radius: DesignTokens.Spacing.xsPlus)
            .offset(x: radius * cos(angle.radians), y: radius * sin(angle.radians))
            .opacity(progress > 0 ? 1 : 0)
            .animation(reduceMotion ? nil : DesignTokens.Animation.smooth, value: animateProgress)
    }

    private var progressRingContent: some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(trackingService.todaySteps.formattedSteps)
                .font(.system(size: progressValueFontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityIdentifier(A11yID.Dashboard.progressValue)
                .contentTransition(.numericText())

            Text(
                Localization.format(
                    "of %@ %@",
                    comment: "Label for progress ring showing goal and unit",
                    trackingService.currentGoal.formattedSteps,
                    activityMode.unitName
                )
            )
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
            .accessibilityIdentifier(A11yID.Dashboard.progressGoal)

            Text("\(ProgressClamp.percent(progress))%")
                .font(DesignTokens.Typography.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .accessibilityHidden(true)
        }
    }

    /// Anchors the streak directly under the hero ring so the metrics grid stays a clean 2x2 with zero orphan card.
    private var streakPill: some View {
        let title = L10n.localized("Streak", comment: "Dashboard stat card title for current streak")
        let value = Localization.streakDays(trackingService.currentStreak)

        return HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "flame.fill")
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.orange)
                .accessibilityHidden(true)

            Text(title)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .accessibilityIdentifier(A11yID.Dashboard.statCardTitle(A11yID.Dashboard.streakStatCard))

            Circle()
                .fill(DesignTokens.Colors.textSecondary)
                .frame(width: 3, height: 3)
                .accessibilityHidden(true)

            Text(value)
                .font(DesignTokens.Typography.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .contentTransition(.numericText())
                .accessibilityIdentifier(A11yID.Dashboard.statCardValue(A11yID.Dashboard.streakStatCard))
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .glassCapsuleSurface(interactive: false)
        .accessibleStatistic(title: title, value: value)
        .accessibilityIdentifier(A11yID.Dashboard.streakStatCard)
    }

    // MARK: - Balanced 2x2 Metrics Grid

    private var statItems: [StatItem] {
        [
            StatItem(
                icon: activityMode.iconName,
                title: L10n.localized("Distance"),
                value: .text(trackingService.todayDistance.formattedDistance(), accessibilityValue: nil),
                color: DesignTokens.Colors.accent,
                accessibilityIdentifier: A11yID.Dashboard.distanceStatCard
            ),
            StatItem(
                icon: "flame.fill",
                title: L10n.localized("Calories", comment: "Dashboard stat card title"),
                value: .text(
                    "\(trackingService.todayCalories.formattedCalories()) \(L10n.localized("kcal", comment: "Calories unit"))",
                    accessibilityValue: nil
                ),
                color: DesignTokens.Colors.orange,
                accessibilityIdentifier: A11yID.Dashboard.caloriesStatCard
            ),
            StatItem(
                icon: "figure.stairs",
                title: L10n.localized("Floors", comment: "Dashboard stat card title"),
                value: .text(Formatters.stepCountString(trackingService.todayFloors), accessibilityValue: nil),
                color: DesignTokens.Colors.mint,
                accessibilityIdentifier: A11yID.Dashboard.floorsStatCard
            ),
            StatItem(
                icon: "heart.fill",
                title: L10n.localized("Heart Rate", comment: "Dashboard stat card title"),
                value: .heartRate(trackingService.todayHeartRateSample),
                color: DesignTokens.Colors.red,
                accessibilityIdentifier: A11yID.Dashboard.heartRateStatCard
            )
        ]
    }

    private var statsGridSection: some View {
        LazyVGrid(
            columns: dynamicTypeSize.isAccessibilitySize
                ? [GridItem(.flexible())]
                : [GridItem(.flexible(), spacing: DesignTokens.Spacing.smPlus), GridItem(.flexible(), spacing: DesignTokens.Spacing.smPlus)],
            spacing: DesignTokens.Spacing.smPlus
        ) {
            ForEach(statItems) { item in
                statCard(for: item)
            }
        }
    }

    @ViewBuilder
    private func statCard(for item: StatItem) -> some View {
        switch item.value {
        case .text(let value, let accessibilityValue):
            StatCard(
                icon: item.icon,
                title: item.title,
                value: value,
                color: item.color,
                accessibilityValue: accessibilityValue,
                accessibilityIdentifier: item.accessibilityIdentifier
            )
        case .heartRate(let sample):
            TimelineView(.periodic(from: .now, by: HeartRateDisplayFormatter.freshnessRefreshInterval)) { context in
                StatCard(
                    icon: item.icon,
                    title: item.title,
                    value: HeartRateDisplayFormatter.visualText(sample: sample, now: context.date),
                    color: item.color,
                    accessibilityValue: HeartRateDisplayFormatter.accessibilityText(sample: sample, now: context.date),
                    accessibilityIdentifier: item.accessibilityIdentifier
                )
            }
        }
    }

    // MARK: - Secondary Banners (Never Above Hero Focus)

    @ViewBuilder
    private var healthPermissionBanner: some View {
        if healthKitSyncEnabled && (healthAuthorization.status == .shouldRequest || trackingService.isUsingMotionFallback) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "heart.slash")
                        .font(DesignTokens.Typography.callout.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.accent)
                        .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
                        .background(DesignTokens.Colors.accentSoft, in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(L10n.localized("Health Access Needed", comment: "Dashboard banner title when HealthKit is not authorized"))
                            .font(DesignTokens.Typography.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        Text(bannerDescription)
                            .font(DesignTokens.Typography.footnote)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(A11yID.Dashboard.healthBannerDescription)
                    }
                }

                if healthAuthorization.status == .shouldRequest {
                    Button(L10n.localized("Grant Access", comment: "Button to request Health access")) {
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
                    .controlSize(.regular)
                    .accessibilityIdentifier(A11yID.Dashboard.healthBannerGrantAccessButton)
                } else {
                    Button(L10n.localized("How to enable", comment: "Button to open Health access instructions")) {
                        showHealthHelp = true
                    }
                    .glassSecondaryButton()
                    .controlSize(.regular)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DesignTokens.Spacing.mdPlus)
            .calmCard()
        }
    }

    private var bannerDescription: String {
        if trackingService.isUsingMotionFallback {
            return L10n.localized(
                "We're using Motion & Fitness data. Enable Health access to include Apple Watch steps and improve history.",
                comment: "Dashboard banner description when falling back to Motion due to missing HealthKit read access"
            )
        }
        return L10n.localized("Enable Health access to improve history and insights.", comment: "Dashboard banner description when HealthKit not authorized")
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
        } else if case .unavailable(let reason) = aiService.availability {
            AIAvailabilityBanner(reason: reason)
        }
    }

    private func loadDailyInsight(forceRefresh: Bool = false) async {
        let requestID = UUID()
        insightRequestID = requestID
        let requestedMode = activityMode
        guard aiService.availability.isAvailable else { return }

        insightError = nil
        do {
            let insight = try await insightService.generateDailyInsight(forceRefresh: forceRefresh)
            guard !Task.isCancelled, insightRequestID == requestID,
                  activityMode == requestedMode, aiService.availability.isAvailable else { return }
            dailyInsight = insight
            insightError = nil
        } catch {
            guard !Task.isCancelled, insightRequestID == requestID,
                  activityMode == requestedMode, aiService.availability.isAvailable else { return }
            insightError = error
        }
    }
}

// MARK: - Stat Item

private struct StatItem: Identifiable {
    enum Value {
        case text(String, accessibilityValue: String?)
        case heartRate(HeartRateSample?)
    }

    let icon: String
    let title: String
    let value: Value
    let color: Color
    let accessibilityIdentifier: String

    var id: String { title }
}

// MARK: - Stat Card

struct StatCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let icon: String
    let title: String
    let value: String
    let color: Color
    var accessibilityValue: String? = nil
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.callout.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
                .background(color.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(value)
                    .font(DesignTokens.Typography.title3.bold())
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(A11yID.Dashboard.statCardValue(accessibilityIdentifier))
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : DesignTokens.Animation.smooth, value: value)

                Text(title)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(A11yID.Dashboard.statCardTitle(accessibilityIdentifier))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .calmCard()
        .accessibleStatistic(title: title, value: value, accessibilityValue: accessibilityValue)
        .accessibilityIdentifier(accessibilityIdentifier)
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
    return NavigationStack {
        DashboardView()
    }
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
