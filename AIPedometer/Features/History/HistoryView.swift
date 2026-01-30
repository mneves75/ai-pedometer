import SwiftUI

struct HistoryView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.healthKitSyncEnabled) private var healthKitSyncEnabled = true
    @Environment(StepTrackingService.self) private var trackingService
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var foundationModelsService
    @State private var animateChart = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var weeklyAnalysis: WeeklyTrendAnalysis?
    @State private var isLoadingAnalysis = false
    @State private var analysisError: AIServiceError?

    private struct LoadTrigger: Hashable {
        let syncEnabled: Bool
        let activityModeRaw: String
    }

    private struct AnalysisTrigger: Hashable {
        let summariesCount: Int
        let hasLoadError: Bool
        let aiAvailable: Bool
    }

    private var activityMode: ActivityTrackingMode {
        ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            mainContent
        }
        .background(Color(.systemGroupedBackground))
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            withAnimation(DesignTokens.Animation.smooth.delay(0.1)) {
                animateChart = true
            }
        }
        .task(id: LoadTrigger(syncEnabled: healthKitSyncEnabled, activityModeRaw: activityModeRaw)) {
            await loadData()
        }
        .task(id: AnalysisTrigger(
            summariesCount: trackingService.weeklySummaries.count,
            hasLoadError: loadError != nil,
            aiAvailable: foundationModelsService.availability.isAvailable
        )) {
            guard !isLoadingAnalysis, weeklyAnalysis == nil else { return }
            guard HistoryAnalysisGate.shouldLoadWeeklyAnalysis(
                syncEnabled: healthKitSyncEnabled,
                loadError: loadError,
                summaries: trackingService.weeklySummaries
            ) else {
                return
            }
            await loadWeeklyAnalysis()
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
            await loadWeeklyAnalysis()
        }
    }

    private func loadWeeklyAnalysis() async {
        guard foundationModelsService.availability.isAvailable else { return }

        isLoadingAnalysis = true
        analysisError = nil

        do {
            weeklyAnalysis = try await insightService.generateWeeklyAnalysis()
        } catch {
            analysisError = error
            Loggers.ai.warning("ai.weekly_analysis_load_failed", metadata: ["error": error.logDescription])
        }

        isLoadingAnalysis = false
    }

    private func resetWeeklyAnalysis() {
        weeklyAnalysis = nil
        analysisError = nil
        isLoadingAnalysis = false
    }

    @ViewBuilder
    private var mainContent: some View {
        if isLoading {
            loadingState
        } else if !healthKitSyncEnabled {
            syncDisabledState
        } else if let error = loadError {
            errorState(message: error)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text(String(localized: "Unable to Load History", comment: "Error state title"))
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "No Activity Data", comment: "Empty state title"))
                .font(.headline)
            Text(String(localized: "Start walking to see your activity history here. Make sure Health access is enabled in Settings.", comment: "Empty state description"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "HealthKit Sync is Off", comment: "History empty state title when HealthKit sync disabled"))
                .font(.headline)
            Text(String(localized: "Enable HealthKit Sync in Settings to see your activity history.", comment: "History empty state description when HealthKit sync disabled"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var headerSection: some View {
        HStack {
            Text(String(localized: "History", comment: "History screen title"))
                .font(.largeTitle.bold())
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
                error: analysisError,
                onRetry: {
                    Task { await loadWeeklyAnalysis() }
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
                .font(.headline)

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
                .fill(summary.goalMet ? Color.blue.gradient : Color.blue.opacity(0.3).gradient)
                .frame(height: animate ? 120 * heightRatio : 0)
                .animation(
                    DesignTokens.Animation.springy.delay(delay),
                    value: animate
                )

            Text(summary.dayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.dayName): \(summary.steps) \(activityMode.unitName), \(summary.goalMet ? String(localized: "goal met") : String(localized: "goal not met"))")
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
                        .font(.headline)
                    GoalStatusBadge(met: summary.goalMet)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xxs) {
                    Text("\(summary.steps)")
                        .font(.title3.bold().monospacedDigit())
                    Text(activityMode.unitName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibleCard(
            label: "\(summary.dateString), \(summary.steps) \(activityMode.unitName)",
            hint: summary.goalMet ? String(localized: "Goal achieved") : String(localized: "Goal not achieved")
        )
    }
}

struct GoalStatusBadge: View {
    let met: Bool

    var body: some View {
        Text(met ? String(localized: "Goal Met", comment: "Badge label for when daily goal was met") : String(localized: "Goal Not Met", comment: "Badge label for when daily goal was not met"))
            .font(.caption.weight(.medium))
            .foregroundStyle(met ? .green : .orange)
    }
}

#Preview {
    @MainActor in
    let demoModeStore = DemoModeStore()
    let healthKitService = HealthKitServiceFallback(demoModeStore: demoModeStore)
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
            goalService: goalService,
            badgeService: badgeService,
            dataStore: SharedDataStore(),
            streakCalculator: streakCalculator
        ))
        .environment(insightService)
        .environment(foundationModelsService)
        .environment(demoModeStore)
}

#Preview("HistoryRow - Steps") {
    HistoryRow(
        summary: DailyStepSummary(date: .now, steps: 8500, distance: 6000, floors: 5, calories: 300, goal: 10000),
        activityMode: .steps
    )
    .padding()
}

#Preview("HistoryRow - Wheelchair") {
    HistoryRow(
        summary: DailyStepSummary(date: .now, steps: 3200, distance: 2400, floors: 2, calories: 120, goal: 3000),
        activityMode: .wheelchairPushes
    )
    .padding()
}
