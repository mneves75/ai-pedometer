import SwiftUI

struct HistoryView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.healthKitSyncEnabled) private var healthKitSyncEnabled = true
    @Environment(StepTrackingService.self) private var trackingService
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var foundationModelsService
    @Environment(HealthKitAuthorization.self) private var healthAuthorization
    @State private var animateChart = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var weeklyAnalysis: WeeklyTrendAnalysis?
    @State private var isLoadingAnalysis = false
    @State private var showHealthHelp = false

    private struct LoadTrigger: Hashable {
        let syncEnabled: Bool
        let activityModeRaw: String
    }

    private var activityMode: ActivityTrackingMode {
        ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            headerSection
            mainContent
        }
        .sheet(isPresented: $showHealthHelp) {
            HealthAccessHelpSheet()
        }
        .uiTestMarker(A11yID.History.marker)
        .uiTestMarker(A11yID.History.todaySteps(trackingService.todaySteps))
        .uiTestMarker(A11yID.History.syncEnabled(healthKitSyncEnabled))
        .background(DesignTokens.Colors.surfaceGrouped)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(DesignTokens.Animation.smooth.delay(0.1)) {
                animateChart = true
            }
        }
        .task(id: LoadTrigger(syncEnabled: healthKitSyncEnabled, activityModeRaw: activityModeRaw)) {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        loadError = nil
        resetWeeklyAnalysis()
        guard healthKitSyncEnabled else {
            isLoading = false
            return
        }
        let result = await trackingService.refreshWeeklySummaries()
        isLoading = false
        if case .failure(let error) = result {
            loadError = error.localizedDescription
        }

        if HistoryAnalysisGate.shouldLoadWeeklyAnalysis(
            syncEnabled: healthKitSyncEnabled,
            loadError: loadError,
            summaries: trackingService.weeklySummaries
        ) {
            await loadWeeklyAnalysis(forceRefresh: true)
        }
    }

    private func loadWeeklyAnalysis(forceRefresh: Bool = false) async {
        guard foundationModelsService.availability.isAvailable else { return }

        isLoadingAnalysis = true

        do {
            weeklyAnalysis = try await insightService.generateWeeklyAnalysis(forceRefresh: forceRefresh)
        } catch {
            weeklyAnalysis = weeklyAnalysisEmergencyFallback
            Loggers.ai.warning("ai.weekly_analysis_history_emergency_fallback", metadata: [
                "error": error.logDescription
            ])
        }

        isLoadingAnalysis = false
    }

    private func resetWeeklyAnalysis() {
        weeklyAnalysis = nil
        isLoadingAnalysis = false
    }

    private var weeklyAnalysisEmergencyFallback: WeeklyTrendAnalysis {
        WeeklyTrendAnalysis(
            summary: String(
                localized: "No Activity Data",
                comment: "Weekly trend summary when no data is available"
            ),
            trend: .stable,
            observation: String(
                localized: "Start walking to see your activity history here. Make sure Health access is enabled in Settings.",
                comment: "Weekly trend observation when no data is available"
            ),
            recommendation: String(
                localized: "Enable HealthKit Sync in Settings to see your activity history.",
                comment: "Weekly trend recommendation when no data is available"
            )
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        // Sync off is a deterministic state: don't show a spinner while we "load"
        // something we will never load.
        if !healthKitSyncEnabled {
            syncDisabledState
        } else if healthAuthorization.status == .shouldRequest {
            healthPermissionState
        } else if isLoading {
            loadingState
        } else if let error = loadError {
            errorState(message: error)
        } else if shouldShowHealthTroubleshootingState {
            healthTroubleshootingState
        } else if trackingService.weeklySummaries.isEmpty {
            emptyState
        } else {
            scrollContent
        }
    }

    private var loadingState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text(String(localized: "Loading history...", comment: "Loading indicator text"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: DesignTokens.FontSize.md))
                .foregroundStyle(DesignTokens.Colors.warning)
            Text(String(localized: "Unable to Load History", comment: "Error state title"))
                .font(DesignTokens.Typography.headline)
            Text(message)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await loadData() }
            } label: {
                Text(String(localized: "Try Again", comment: "Retry button"))
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "figure.walk")
                .font(.system(size: DesignTokens.FontSize.md))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(String(localized: "No Activity Data", comment: "Empty state title"))
                .font(DesignTokens.Typography.headline)
            Text(String(localized: "Start walking to see your activity history here. Make sure Health access is enabled in Settings.", comment: "Empty state description"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var syncDisabledState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "heart.slash")
                .font(.system(size: DesignTokens.FontSize.md))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(String(localized: "HealthKit Sync is Off", comment: "History empty state title when HealthKit sync disabled"))
                .font(DesignTokens.Typography.headline)
                .accessibilityIdentifier(A11yID.History.syncOffLabel)
            Text(String(localized: "Enable HealthKit Sync in Settings to see your activity history.", comment: "History empty state description when HealthKit sync disabled"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        // Do NOT set accessibilityIdentifier on the container: SwiftUI may apply it
        // to child text nodes, breaking per-element identifiers used by UI tests.
        .accessibilityElement(children: .contain)
        .uiTestMarker(A11yID.History.syncOffView)
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var healthPermissionState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "heart.slash")
                .font(.system(size: DesignTokens.FontSize.md))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(String(localized: "Health Access Needed", comment: "History state title when HealthKit is not authorized"))
                .font(DesignTokens.Typography.headline)
                .multilineTextAlignment(.center)
            Text(permissionDescription)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.lg)
            Button(String(localized: "Grant Access", comment: "Button to request Health access")) {
                Task {
                    do {
                        try await healthAuthorization.requestAuthorization()
                    } catch {
                        Loggers.health.warning("history.healthkit_request_failed", metadata: [
                            "error": error.localizedDescription
                        ])
                    }
                    await healthAuthorization.refreshStatus()
                    await loadData()
                }
            }
            .glassButton()
            .padding(.horizontal, DesignTokens.Spacing.lg)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .uiTestMarker(A11yID.History.healthAccessNeededView)
    }

    private var shouldShowHealthTroubleshootingState: Bool {
        // History depends on HealthKit (Apple Watch inclusive). If we are falling back to Motion for today,
        // and HealthKit summaries are entirely empty/zero, guide the user to Settings.
        guard activityMode == .steps else { return false }
        guard trackingService.isUsingMotionFallback else { return false }
        guard trackingService.todaySteps > 0 else { return false }
        return trackingService.weeklySummaries.allSatisfy { $0.steps == 0 }
    }

    private var healthTroubleshootingState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "heart.slash")
                .font(.system(size: DesignTokens.FontSize.md))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(String(localized: "Health Access Needed", comment: "History troubleshooting title when Health data is missing"))
                .font(DesignTokens.Typography.headline)
                .multilineTextAlignment(.center)
            Text(
                String(
                    localized: "Your steps are available via Motion & Fitness, but Health history isn't loading. Enable Health access in Settings to show Apple Watch and history data.",
                    comment: "History troubleshooting description when using Motion fallback and HealthKit history is empty"
                )
            )
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, DesignTokens.Spacing.lg)

            Button(String(localized: "How to enable", comment: "Button to open Health access instructions")) {
                showHealthHelp = true
            }
            .glassButton()
            .padding(.horizontal, DesignTokens.Spacing.lg)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }

    private var permissionDescription: String {
        switch healthAuthorization.status {
        case .shouldRequest:
            return String(localized: "To show your history, we need permission to read your activity data from Health.", comment: "History permission description before requesting")
        case .requested:
            return String(localized: "Health access was already requested. If data isn't showing, enable it in Settings.", comment: "History permission description after requesting")
        case .unavailable:
            return String(localized: "Health data is not available on this device.", comment: "History permission description when HealthKit unavailable")
        }
    }

    private var headerSection: some View {
        HStack {
            Text(String(localized: "History", comment: "History screen title"))
                .font(DesignTokens.Typography.largeTitle.bold())
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.md) {
                weeklySummaryCard
                aiTrendCard
                historyRows
            }
            .padding(.bottom, DesignTokens.Spacing.lg)
        }
    }

    @ViewBuilder
    private var aiTrendCard: some View {
        if foundationModelsService.availability.isAvailable {
            WeeklyTrendCard(
                analysis: weeklyAnalysis,
                isLoading: isLoadingAnalysis,
                error: nil,
                onRetry: {
                    Task { await loadWeeklyAnalysis(forceRefresh: true) }
                }
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    @ViewBuilder
    private var weeklySummaryCard: some View {
        if LaunchConfiguration.isUITesting() {
            weeklySummaryContent
                .padding(.horizontal, DesignTokens.Spacing.md)
        } else if #available(iOS 26, *) {
            GlassEffectContainer(spacing: DesignTokens.Spacing.sm) {
                weeklySummaryContent
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else {
            weeklySummaryContent
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private var weeklySummaryContent: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(String(localized: "Weekly Summary", comment: "History section header"))
                .font(DesignTokens.Typography.headline)

            barChart
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Localization.format(
                "Weekly %@ summary chart",
                comment: "Accessibility label for weekly summary chart, with unit name",
                activityMode.unitName
            )
        )
    }

    private var barChart: some View {
        let summaries = trackingService.weeklySummaries
        let maxSteps = summaries.maxStepsValue

        return HStack(alignment: .bottom, spacing: DesignTokens.Spacing.sm) {
            ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                BarChartColumn(
                    summary: summary,
                    maxSteps: maxSteps,
                    activityMode: activityMode,
                    animate: animateChart,
                    delay: Double(index) * 0.05
                )
            }
        }
        .frame(height: 150)
    }

    private var historyRows: some View {
        ForEach(trackingService.weeklySummaries.sortedByDateDescending) { summary in
            HistoryRow(summary: summary, activityMode: activityMode)
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }
}

struct BarChartColumn: View {
    let summary: DailyStepSummary
    let maxSteps: Int
    let activityMode: ActivityTrackingMode
    let animate: Bool
    let delay: Double

    private var heightRatio: CGFloat {
        CGFloat(summary.steps) / CGFloat(max(maxSteps, 1))
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Spacer()

            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs)
                .fill(
                    summary.goalMet
                        ? DesignTokens.Colors.accent.gradient
                        : DesignTokens.Colors.accentSoft.gradient
                )
                .frame(height: animate ? 120 * heightRatio : 0)
                .animation(
                    DesignTokens.Animation.springy.delay(delay),
                    value: animate
                )

            Text(summary.dayName)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.dayName): \(summary.steps.formattedSteps) \(activityMode.unitName), \(summary.goalMet ? String(localized: "goal met") : String(localized: "goal not met"))")
    }
}

struct HistoryRow: View {
    let summary: DailyStepSummary
    let activityMode: ActivityTrackingMode

    var body: some View {
        Button {
            HapticService.shared.selection()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(summary.dateString)
                        .font(DesignTokens.Typography.headline)
                    GoalStatusBadge(met: summary.goalMet)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xxs) {
                    Text(summary.steps.formattedSteps)
                        .font(DesignTokens.Typography.title3.bold().monospacedDigit())
                    Text(activityMode.unitName)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibleCard(
            label: "\(summary.dateString), \(summary.steps.formattedSteps) \(activityMode.unitName)",
            hint: summary.goalMet ? String(localized: "Goal achieved") : String(localized: "Goal not achieved")
        )
    }
}

struct GoalStatusBadge: View {
    let met: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(
                met
                    ? String(localized: "Goal Met", comment: "Badge label for when daily goal was met")
                    : String(localized: "Goal Not Met", comment: "Badge label for when daily goal was not met")
            )
        }
        .font(DesignTokens.Typography.caption.weight(.semibold))
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(
            met
                ? DesignTokens.Colors.success.opacity(0.15)
                : DesignTokens.Colors.warning.opacity(0.15),
            in: Capsule()
        )
        .foregroundStyle(met ? DesignTokens.Colors.success : DesignTokens.Colors.warning)
    }
}

#Preview {
    @MainActor in
    let demoModeStore = DemoModeStore()
    let healthKitService = HealthKitServiceFallback(demoModeStore: demoModeStore)
    let healthAuthorization = HealthKitAuthorization()
    let persistence = PersistenceController.shared
    let goalService = GoalService(persistence: persistence)
    let streakCalculator = StreakCalculator(stepAggregator: StepDataAggregator(), goalService: goalService)
    let badgeService = BadgeService(persistence: persistence)
    let foundationModelsService = FoundationModelsService()
    let insightService = InsightService(
        foundationModelsService: foundationModelsService,
        healthKitService: healthKitService,
        goalService: goalService,
        dataStore: SharedDataStore()
    )
    HistoryView()
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
        .environment(insightService)
        .environment(foundationModelsService)
        .environment(demoModeStore)
}

#Preview("HistoryRow - Steps") {
    HistoryRow(
        summary: DailyStepSummary(date: .now, steps: 8500, distance: 6000, floors: 5, calories: 300, goal: 10000),
        activityMode: .steps
    )
    .padding(DesignTokens.Spacing.md)
}

#Preview("HistoryRow - Wheelchair") {
    HistoryRow(
        summary: DailyStepSummary(date: .now, steps: 3200, distance: 2400, floors: 2, calories: 120, goal: 3000),
        activityMode: .wheelchairPushes
    )
    .padding(DesignTokens.Spacing.md)
}
