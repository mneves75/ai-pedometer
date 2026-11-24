import SwiftUI

struct HistoryView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.healthKitSyncEnabled) private var healthKitSyncEnabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(StepTrackingService.self) private var trackingService
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var foundationModelsService
    @Environment(HealthKitAuthorization.self) private var healthAuthorization
    @State private var animateChart = false
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var weeklyAnalysis: WeeklyTrendAnalysis?
    @State private var isLoadingAnalysis = false
    @State private var loadGeneration = 0
    @State private var showHealthHelp = false
    @State private var selectedSummaryID: Date?

    private struct LoadTrigger: Hashable {
        let syncEnabled: Bool
        let activityModeRaw: String
        let aiAvailable: Bool
    }

    private var activityMode: ActivityTrackingMode {
        ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps
    }

    var body: some View {
        mainContent
            .sheet(isPresented: $showHealthHelp) {
                HealthAccessHelpSheet()
            }
            .uiTestMarker(A11yID.History.marker)
            .uiTestMarker(A11yID.History.todaySteps(trackingService.todaySteps))
            .uiTestMarker(A11yID.History.syncEnabled(healthKitSyncEnabled))
            .background {
                AmbientZenithBackground()
            }
            .navigationTitle(L10n.localized("History", comment: "History screen title"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                withAnimation(reduceMotion ? nil : DesignTokens.Animation.smooth.delay(0.1)) {
                    animateChart = true
                }
            }
            .task(id: LoadTrigger(
                syncEnabled: healthKitSyncEnabled,
                activityModeRaw: activityModeRaw,
                aiAvailable: foundationModelsService.availability.isAvailable
            )) {
                await loadData(forceRefreshAnalysis: false)
            }
            .refreshable {
                await loadData(forceRefreshAnalysis: true)
            }
    }

    private func loadData(forceRefreshAnalysis: Bool = false) async {
        loadGeneration &+= 1
        let generation = loadGeneration
        let isCurrent: @MainActor () -> Bool = { loadGeneration == generation }
        isLoading = true
        loadError = nil
        resetWeeklyAnalysis()
        guard healthKitSyncEnabled else {
            isLoading = false
            return
        }
        await HistoryAnalysisGate.load(
            isCurrent: isCurrent,
            refreshSummaries: {
                let result = await trackingService.refreshWeeklySummaries()
                if case .failure(let error) = result {
                    return error.localizedDescription
                }
                return nil
            },
            finishLoading: { error in
                isLoading = false
                loadError = error
            },
            shouldLoadAnalysis: { error in
                HistoryAnalysisGate.shouldLoadWeeklyAnalysis(
                    syncEnabled: healthKitSyncEnabled,
                    loadError: error,
                    summaries: trackingService.weeklySummaries
                )
            },
            loadAnalysis: {
                await loadWeeklyAnalysis(forceRefresh: forceRefreshAnalysis, isCurrent: isCurrent)
            }
        )
    }

    private func loadWeeklyAnalysis(forceRefresh: Bool, isCurrent: @escaping @MainActor () -> Bool) async {
        guard foundationModelsService.availability.isAvailable else { return }

        isLoadingAnalysis = true

        let analysis: WeeklyTrendAnalysis
        do {
            analysis = try await insightService.generateWeeklyAnalysis(forceRefresh: forceRefresh)
        } catch {
            analysis = weeklyAnalysisEmergencyFallback
            Loggers.ai.warning("ai.weekly_analysis_history_emergency_fallback", metadata: [
                "error": error.logDescription
            ])
        }

        guard isCurrent() else { return }
        weeklyAnalysis = analysis
        isLoadingAnalysis = false
    }

    private func resetWeeklyAnalysis() {
        weeklyAnalysis = nil
        isLoadingAnalysis = false
    }

    private var weeklyAnalysisEmergencyFallback: WeeklyTrendAnalysis {
        WeeklyTrendAnalysis(
            summary: L10n.localized(
                "No Activity Data",
                comment: "Weekly trend summary when no data is available"
            ),
            trend: .stable,
            observation: L10n.localized(
                "Start walking to see your activity history here. Make sure Health access is enabled in Settings.",
                comment: "Weekly trend observation when no data is available"
            ),
            recommendation: L10n.localized(
                "Enable HealthKit Sync in Settings to see your activity history.",
                comment: "Weekly trend recommendation when no data is available"
            )
        )
    }

    @ViewBuilder
    private var mainContent: some View {
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
            Text(L10n.localized("Loading history...", comment: "Loading indicator text"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        ContentUnavailableView {
            Label {
                Text(L10n.localized("Unable to Load History", comment: "Error state title"))
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(DesignTokens.Colors.warning)
            }
        } description: {
            Text(message)
        } actions: {
            Button(L10n.localized("Try Again", comment: "Retry button"), action: retryLoad)
                .glassSecondaryButton()
        }
    }

    private func retryLoad() {
        Task { await loadData() }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            L10n.localized("No Activity Data", comment: "Empty state title"),
            systemImage: "figure.walk",
            description: Text(L10n.localized("Start walking to see your activity history here. Make sure Health access is enabled in Settings.", comment: "Empty state description"))
        )
    }

    private var syncDisabledState: some View {
        ContentUnavailableView {
            Label {
                Text(L10n.localized("HealthKit Sync is Off", comment: "History empty state title when HealthKit sync disabled"))
                    .accessibilityIdentifier(A11yID.History.syncOffLabel)
            } icon: {
                Image(systemName: "heart.slash")
            }
        } description: {
            Text(L10n.localized("Enable HealthKit Sync in Settings to see your activity history.", comment: "History empty state description when HealthKit sync disabled"))
        }
        .accessibilityElement(children: .contain)
        .uiTestMarker(A11yID.History.syncOffView)
    }

    private var healthPermissionState: some View {
        ContentUnavailableView {
            Label(
                L10n.localized("Health Access Needed", comment: "History state title when HealthKit is not authorized"),
                systemImage: "heart.slash"
            )
        } description: {
            Text(permissionDescription)
        } actions: {
            Button(L10n.localized("Grant Access", comment: "Button to request Health access"), action: requestHealthAccess)
                .glassButton()
                .controlSize(.large)
        }
        .accessibilityElement(children: .contain)
        .uiTestMarker(A11yID.History.healthAccessNeededView)
    }

    private func requestHealthAccess() {
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

    private var shouldShowHealthTroubleshootingState: Bool {
        guard activityMode == .steps else { return false }
        guard trackingService.isUsingMotionFallback else { return false }
        guard trackingService.todaySteps > 0 else { return false }
        return trackingService.weeklySummaries.allSatisfy { $0.steps == 0 }
    }

    private var healthTroubleshootingState: some View {
        ContentUnavailableView {
            Label(
                L10n.localized("Health Access Needed", comment: "History troubleshooting title when Health data is missing"),
                systemImage: "heart.slash"
            )
        } description: {
            Text(
                L10n.localized(
                    "Your steps are available via Motion & Fitness, but Health history isn't loading. Enable Health access in Settings to show Apple Watch and history data.",
                    comment: "History troubleshooting description when using Motion fallback and HealthKit history is empty"
                )
            )
        } actions: {
            Button(L10n.localized("How to enable", comment: "Button to open Health access instructions")) {
                showHealthHelp = true
            }
            .glassButton()
            .controlSize(.large)
        }
        .accessibilityElement(children: .contain)
    }

    private var permissionDescription: String {
        switch healthAuthorization.status {
        case .shouldRequest:
            return L10n.localized("To show your history, we need permission to read your activity data from Health.", comment: "History permission description before requesting")
        case .requested:
            return L10n.localized("Health access was already requested. If data isn't showing, enable it in Settings.", comment: "History permission description after requesting")
        case .unavailable:
            return L10n.localized("Health data is not available on this device.", comment: "History permission description when HealthKit unavailable")
        }
    }

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                weeklySummaryCard
                dailyBreakdownCard
                aiTrendCard
            }
            .padding(.horizontal, DesignTokens.Spacing.mdPlus)
            .padding(.top, DesignTokens.Spacing.sm)
        }
        .tabBarAwareScrollContentBottomInset()
    }

    @ViewBuilder
    private var aiTrendCard: some View {
        if foundationModelsService.availability.isAvailable {
            WeeklyTrendCard(
                analysis: weeklyAnalysis,
                isLoading: isLoadingAnalysis,
                error: nil,
                onRetry: {
                    let generation = loadGeneration
                    Task {
                        await loadWeeklyAnalysis(forceRefresh: true, isCurrent: { loadGeneration == generation })
                    }
                }
            )
        } else if case .unavailable(let reason) = foundationModelsService.availability {
            AIAvailabilityBanner(reason: reason)
        }
    }

    private var weeklySummaryCard: some View {
        let summaries = trackingService.weeklySummaries
        let selectedSummary = summaries.first { $0.date == selectedSummaryID }
        let average = summaries.isEmpty ? 0 : summaries.reduce(0) { $0 + $1.steps } / summaries.count
        let goalMetCount = summaries.count(where: \.goalMet)
        let headlineValue = selectedSummary?.steps ?? average
        let headlineSubtitle = selectedSummary?.dateString
            ?? L10n.localized("Daily Average", comment: "History chart headline for 7-day daily average")

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(headlineSubtitle)
                        .font(DesignTokens.Typography.footnote.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)

                    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                        Text(headlineValue.formattedSteps)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        Text(activityMode.unitName)
                            .font(DesignTokens.Typography.subheadline)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }

                Spacer()

                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.success)
                        .accessibilityHidden(true)
                    Text("\(goalMetCount)/\(summaries.count)")
                        .font(DesignTokens.Typography.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                .padding(.horizontal, DesignTokens.Spacing.smPlus)
                .padding(.vertical, DesignTokens.Spacing.xsPlus)
                .background(DesignTokens.Colors.success.opacity(0.12), in: Capsule())
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Localization.format(
                        "%lld of %lld",
                        comment: "Days goal met out of total days",
                        Int64(goalMetCount),
                        Int64(summaries.count)
                    )
                )
            }

            barChart
        }
        .padding(DesignTokens.Spacing.mdPlus)
        .calmCard()
        .accessibilityElement(children: .contain)
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
        let goalReference = summaries.last?.goal ?? trackingService.currentGoal
        let maxSteps = max(summaries.maxStepsValue, goalReference, 1)
        let goalRatio = min(CGFloat(goalReference) / CGFloat(maxSteps), 1.0)

        return ZStack(alignment: .bottom) {
            if goalReference > 0 {
                GeometryReader { proxy in
                    let barAreaHeight = DesignTokens.Sizing.chartBarMaxHeight
                    let yOffset = max(0, barAreaHeight * (1 - goalRatio))
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: yOffset))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: yOffset))
                    }
                    .stroke(
                        DesignTokens.Colors.borderMuted,
                        style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                    )
                }
                .frame(height: DesignTokens.Sizing.chartBarMaxHeight)
                .padding(.bottom, 22)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.sm) {
                ForEach(summaries.enumerated(), id: \.element.id) { index, summary in
                    BarChartColumn(
                        summary: summary,
                        maxSteps: maxSteps,
                        activityMode: activityMode,
                        isSelected: selectedSummaryID == summary.date,
                        animate: animateChart,
                        delay: Double(index) * 0.04
                    ) {
                        HapticService.shared.selection()
                        withAnimation(reduceMotion ? nil : DesignTokens.Animation.snappy) {
                            selectedSummaryID = selectedSummaryID == summary.date ? nil : summary.date
                        }
                    }
                }
            }
        }
        .frame(minHeight: DesignTokens.Sizing.chartHeight)
    }

    private var dailyBreakdownCard: some View {
        let sorted = trackingService.weeklySummaries.sortedByDateDescending
        return VStack(spacing: DesignTokens.Spacing.none) {
            ForEach(sorted.enumerated(), id: \.element.id) { index, summary in
                HistoryRow(summary: summary, activityMode: activityMode)
                if index < sorted.count - 1 {
                    Divider()
                        .padding(.leading, DesignTokens.Spacing.mdPlus)
                }
            }
        }
        .calmCard()
    }
}

struct BarChartColumn: View {
    let summary: DailyStepSummary
    let maxSteps: Int
    let activityMode: ActivityTrackingMode
    var isSelected: Bool = false
    let animate: Bool
    let delay: Double
    var onSelect: (() -> Void)? = nil

    private var heightRatio: CGFloat {
        CGFloat(summary.steps) / CGFloat(max(maxSteps, 1))
    }

    private var barFill: LinearGradient {
        if summary.goalMet {
            LinearGradient(
                colors: [DesignTokens.Colors.accent, DesignTokens.Colors.mint],
                startPoint: .bottom,
                endPoint: .top
            )
        } else {
            LinearGradient(
                colors: [DesignTokens.Colors.accentSoft, DesignTokens.Colors.accentMuted],
                startPoint: .bottom,
                endPoint: .top
            )
        }
    }

    var body: some View {
        let minBarHeight: CGFloat = summary.steps > 0 ? 6 : 3
        let barHeight = animate
            ? max(DesignTokens.Sizing.chartBarMaxHeight * heightRatio, minBarHeight)
            : minBarHeight

        Button {
            onSelect?()
        } label: {
            VStack(spacing: DesignTokens.Spacing.xsPlus) {
                Spacer(minLength: 0)

                Capsule()
                    .fill(barFill)
                    .frame(maxWidth: 26)
                    .frame(height: barHeight)
                    .opacity(isSelected ? 1 : 0.92)
                    .overlay {
                        if isSelected {
                            Capsule()
                                .strokeBorder(DesignTokens.Colors.textPrimary.opacity(0.45), lineWidth: 1.5)
                        }
                    }
                    .motionAwareAnimation(
                        DesignTokens.Animation.springy.delay(delay),
                        value: animate
                    )

                Text(summary.dayName)
                    .font(DesignTokens.Typography.caption2.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("\(summary.dayName): \(summary.steps.formattedSteps) \(activityMode.unitName), \(summary.goalMet ? L10n.localized("goal met") : L10n.localized("goal not met"))")
    }
}

struct HistoryRow: View {
    let summary: DailyStepSummary
    let activityMode: ActivityTrackingMode

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            GoalStatusIndicator(met: summary.goalMet)

            Text(summary.dateString)
                .font(DesignTokens.Typography.body.weight(.medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xxs) {
                Text(summary.steps.formattedSteps)
                    .font(DesignTokens.Typography.headline.monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .contentTransition(.numericText())
                Text(activityMode.unitName)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.mdPlus)
        .padding(.vertical, DesignTokens.Spacing.md)
        .accessibleCard(
            label: "\(summary.dateString), \(summary.steps.formattedSteps) \(activityMode.unitName)",
            hint: summary.goalMet ? L10n.localized("Goal achieved") : L10n.localized("Goal not achieved")
        )
    }
}

/// Quiet, accessible goal status dot/check. Hides the SF Symbol from VoiceOver so
/// `xmark.circle.fill` never leaks as "Close"/"Fechar"; the row's card hint speaks the status.
struct GoalStatusIndicator: View {
    let met: Bool

    var body: some View {
        Image(systemName: met ? "checkmark.circle.fill" : "circle")
            .font(DesignTokens.Typography.callout.weight(.semibold))
            .foregroundStyle(met ? DesignTokens.Colors.success : DesignTokens.Colors.borderMuted)
            .accessibilityHidden(true)
    }
}

/// Retained for previews and callers that render the explicit capsule status badge, with the
/// decorative icon hidden from VoiceOver so it never reads as "Close"/"Fechar".
struct GoalStatusBadge: View {
    let met: Bool

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .accessibilityHidden(true)
            Text(
                met
                    ? L10n.localized("Goal Met", comment: "Badge label for when daily goal was met")
                    : L10n.localized("Goal Not Met", comment: "Badge label for when daily goal was not met")
            )
        }
        .font(DesignTokens.Typography.caption.weight(.semibold))
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .background(
            met
                ? DesignTokens.Colors.success.opacity(0.15)
                : DesignTokens.Colors.surfaceQuaternary,
            in: Capsule()
        )
        .foregroundStyle(met ? DesignTokens.Colors.success : DesignTokens.Colors.textSecondary)
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
    NavigationStack {
        HistoryView()
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
    .environment(insightService)
    .environment(foundationModelsService)
    .environment(demoModeStore)
}
