import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(WorkoutSessionController.self) private var workoutController
    @State private var showEndConfirmation = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        @Bindable var workoutController = workoutController
        VStack(spacing: DesignTokens.Spacing.lg) {
            statusHeader

            metricsSection

            if let targetSteps = workoutController.metrics?.targetSteps {
                targetProgressSection(targetSteps: targetSteps)
            }

            Spacer()

            actionButtons
        }
        .accessibilityIdentifier(A11yID.ActiveWorkout.view)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.Colors.surfaceGrouped)
        .navigationTitle(statusTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showDiscardConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(String(localized: "Discard Workout", comment: "Discard workout toolbar action"))
            }
        }
        .confirmationDialog(
            String(localized: "End Workout", comment: "Confirmation dialog title for ending workout"),
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "End Workout", comment: "Confirm ending workout"), role: .destructive) {
                Task { await workoutController.finishWorkout() }
            }
        } message: {
            Text(String(localized: "Ending will save the workout to your history.", comment: "Message explaining that ending saves the workout"))
        }
        .confirmationDialog(
            String(localized: "Discard Workout", comment: "Confirmation dialog title for discarding workout"),
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Discard Workout", comment: "Confirm discarding workout"), role: .destructive) {
                workoutController.discardWorkout()
            }
        } message: {
            Text(String(localized: "This will remove the workout and discard progress.", comment: "Message explaining that discarding removes progress"))
        }
        .alert(item: $workoutController.lastError) { error in
            Alert(
                title: Text(String(localized: "Workout Error", comment: "Workout error alert title")),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text(String(localized: "OK", comment: "Dismiss alert button")))
            )
        }
    }

    private var statusHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(workoutTypeTitle)
                    .font(DesignTokens.Typography.title2.bold())
            }

            Spacer()

            statusBadge
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
    }

    private var metricsSection: some View {
        let metrics = workoutController.metrics
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.md) {
            metricCard(
                title: String(localized: "Steps", comment: "Workout metric title"),
                value: metrics?.steps.formattedSteps ?? "0",
                icon: "figure.walk",
                tint: DesignTokens.Colors.green
            )
            metricCard(
                title: String(localized: "Distance", comment: "Workout metric title"),
                value: metrics?.distance.formattedDistance() ?? 0.formattedDistance(),
                icon: "map",
                tint: DesignTokens.Colors.blue
            )
            metricCard(
                title: String(localized: "Calories", comment: "Workout metric title"),
                value: metrics?.calories.formattedCalories() ?? "0",
                icon: "flame",
                tint: DesignTokens.Colors.orange
            )
            metricCard(
                title: String(localized: "Elapsed", comment: "Workout metric title"),
                value: elapsedText,
                icon: "clock",
                tint: DesignTokens.Colors.purple
            )
        }
    }

    private func targetProgressSection(targetSteps: Int) -> some View {
        let progress = workoutController.metrics?.targetProgress ?? 0
        let currentSteps = workoutController.metrics?.steps ?? 0

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text(String(localized: "Target", comment: "Workout target label"))
                    .font(DesignTokens.Typography.headline)
                Spacer()
                Text("\(currentSteps.formattedSteps)/\(targetSteps.formattedSteps)")
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
            }

            ProgressView(value: progress)
                .tint(DesignTokens.Colors.accent)
                .accessibleProgress(
                    label: String(localized: "Target progress", comment: "Accessibility label for target progress"),
                    value: progress
                )
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
    }

    private var actionButtons: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button(action: togglePause) {
                Label(pauseButtonTitle, systemImage: pauseButtonIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showEndConfirmation = true
            } label: {
                Text(String(localized: "End Workout", comment: "Button to end workout"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(A11yID.ActiveWorkout.endButton)
        }
        .controlSize(.large)
        .tint(DesignTokens.Colors.accent)
    }

    private func metricCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(DesignTokens.Typography.title3)
            Text(value)
                .font(DesignTokens.Typography.title3.bold())
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .glassCard()
        .accessibleStatistic(title: title, value: value)
    }

    private func togglePause() {
        switch workoutController.state {
        case .active:
            workoutController.pauseWorkout()
        case .paused:
            workoutController.resumeWorkout()
        default:
            break
        }
    }

    private var statusTitle: String {
        switch workoutController.state {
        case .paused:
            return String(localized: "Workout Paused", comment: "Title when workout is paused")
        default:
            return String(localized: "Active Workout", comment: "Title when workout is active")
        }
    }

    private var statusSubtitle: String {
        switch workoutController.state {
        case .paused:
            return String(localized: "Paused", comment: "Workout status subtitle")
        default:
            return String(localized: "In Progress", comment: "Workout status subtitle")
        }
    }

    private var statusTint: Color {
        switch workoutController.state {
        case .paused:
            return DesignTokens.Colors.warning
        default:
            return DesignTokens.Colors.success
        }
    }

    private var statusBadge: some View {
        Text(statusSubtitle.uppercased())
            .font(DesignTokens.Typography.caption.weight(.bold))
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xxs)
            .background(statusTint.opacity(0.15), in: Capsule())
            .foregroundStyle(statusTint)
    }

    private var workoutTypeTitle: String {
        workoutController.workoutType?.displayName ?? String(localized: "Workout", comment: "Fallback workout title")
    }

    private var pauseButtonTitle: String {
        switch workoutController.state {
        case .paused:
            String(localized: "Resume Workout", comment: "Resume workout button title")
        default:
            String(localized: "Pause Workout", comment: "Pause workout button title")
        }
    }

    private var pauseButtonIcon: String {
        switch workoutController.state {
        case .paused:
            return "play.fill"
        default:
            return "pause.fill"
        }
    }

    private var elapsedText: String {
        let formatter = Self.elapsedFormatter
        return formatter.string(from: workoutController.elapsedTime) ?? "0:00"
    }

    private static let elapsedFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}

#Preview("Active Workout") {
    @MainActor in
    let demoStore = DemoModeStore()
    let modelContext = PersistenceController(inMemory: true).container.mainContext
    let metricsSource = MotionLiveMetricsSource(motionService: MotionService())
    let controller = WorkoutSessionController(
        modelContext: modelContext,
        healthKitService: HealthKitServiceFallback(demoModeStore: demoStore),
        metricsSource: metricsSource,
        liveActivityManager: NoopLiveActivityManager()
    )

    ActiveWorkoutView()
        .environment(controller)
}
