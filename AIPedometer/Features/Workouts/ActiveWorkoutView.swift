import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(WorkoutSessionController.self) private var workoutController
    @State private var showEndConfirmation = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        @Bindable var workoutController = workoutController
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                heroCockpit
                metricsStrip

                if let targetSteps = workoutController.metrics?.targetSteps {
                    targetProgressSection(targetSteps: targetSteps)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.mdPlus)
            .padding(.top, DesignTokens.Spacing.lg)
            .padding(.bottom, DesignTokens.Spacing.xl)
        }
        .accessibilityIdentifier(A11yID.ActiveWorkout.view)
        .background {
            AmbientZenithBackground(tint: statusTint)
        }
        .safeAreaInset(edge: .bottom) {
            actionButtons
                .padding(.horizontal, DesignTokens.Spacing.mdPlus)
                .padding(.top, DesignTokens.Spacing.sm)
                .padding(.bottom, DesignTokens.Spacing.md)
        }
        .navigationTitle(workoutTypeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDiscardConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel(L10n.localized("Discard Workout", comment: "Discard workout toolbar action"))
            }
        }
        .confirmationDialog(
            L10n.localized("End Workout", comment: "Confirmation dialog title for ending workout"),
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.localized("End Workout", comment: "Confirm ending workout"), role: .destructive) {
                Task { await workoutController.finishWorkout() }
            }
            .accessibilityIdentifier(A11yID.ActiveWorkout.confirmEndButton)
        } message: {
            Text(L10n.localized("Ending will save the workout to your history.", comment: "Message explaining that ending saves the workout"))
        }
        .confirmationDialog(
            L10n.localized("Discard Workout", comment: "Confirmation dialog title for discarding workout"),
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.localized("Discard Workout", comment: "Confirm discarding workout"), role: .destructive) {
                Task { await workoutController.discardWorkout() }
            }
        } message: {
            Text(L10n.localized("This will remove the workout and discard progress.", comment: "Message explaining that discarding removes progress"))
        }
        .alert(item: $workoutController.lastError) { error in
            Alert(
                title: Text(L10n.localized("Workout Error", comment: "Workout error alert title")),
                message: Text(error.localizedDescription),
                dismissButton: .default(Text(L10n.localized("OK", comment: "Dismiss alert button")))
            )
        }
    }

    // MARK: - Hero Live Cockpit

    private var heroCockpit: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            statusBadge

            VStack(spacing: DesignTokens.Spacing.xs) {
                Text(elapsedText)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .contentTransition(.numericText())

                Text(L10n.localized("Elapsed", comment: "Workout metric title"))
                    .font(DesignTokens.Typography.footnote.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .accessibleStatistic(
                title: L10n.localized("Elapsed", comment: "Workout metric title"),
                value: elapsedText
            )

            VStack(spacing: DesignTokens.Spacing.xxs) {
                Text(workoutController.metrics?.steps.formattedSteps ?? "0")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.accent)
                    .contentTransition(.numericText())

                Text(L10n.localized("Steps", comment: "Workout metric title"))
                    .font(DesignTokens.Typography.footnote.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .accessibleStatistic(
                title: L10n.localized("Steps", comment: "Workout metric title"),
                value: workoutController.metrics?.steps.formattedSteps ?? "0"
            )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    private var metricsStrip: some View {
        let metrics = workoutController.metrics
        return HStack(spacing: DesignTokens.Spacing.smPlus) {
            metricTile(
                title: L10n.localized("Distance", comment: "Workout metric title"),
                value: metrics?.distance.formattedDistance() ?? 0.formattedDistance(),
                icon: "map.fill",
                tint: DesignTokens.Colors.blue
            )
            metricTile(
                title: L10n.localized("Calories", comment: "Workout metric title"),
                value: "\(metrics?.calories.formattedCalories() ?? "0") \(L10n.localized("kcal", comment: "Calories unit"))",
                icon: "flame.fill",
                tint: DesignTokens.Colors.orange
            )
        }
    }

    private func metricTile(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: DesignTokens.IconSize.md, height: DesignTokens.IconSize.md)
                .background(tint.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(value)
                    .font(DesignTokens.Typography.title3.bold().monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .contentTransition(.numericText())

                Text(title)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignTokens.Spacing.md)
        .calmCard()
        .accessibleStatistic(title: title, value: value)
    }

    private func targetProgressSection(targetSteps: Int) -> some View {
        let progress = workoutController.metrics?.targetProgress ?? 0
        let currentSteps = workoutController.metrics?.steps ?? 0

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                Text(L10n.localized("Target", comment: "Workout target label"))
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Text("\(currentSteps.formattedSteps) / \(targetSteps.formattedSteps)")
                    .font(DesignTokens.Typography.subheadline.weight(.semibold).monospacedDigit())
            }

            ProgressView(value: progress)
                .tint(DesignTokens.Colors.accent)
                .accessibleProgress(
                    label: L10n.localized("Target progress", comment: "Accessibility label for target progress"),
                    value: progress
                )
        }
        .padding(DesignTokens.Spacing.mdPlus)
        .calmCard()
    }

    // MARK: - Floating Liquid Glass Action Controls

    private var actionButtons: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button(action: togglePause) {
                Label(pauseButtonTitle, systemImage: pauseButtonIcon)
                    .font(DesignTokens.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .glassSecondaryButton()

            Button {
                showEndConfirmation = true
            } label: {
                Text(L10n.localized("End Workout", comment: "Button to end workout"))
                    .font(DesignTokens.Typography.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .glassButton()
            .accessibilityIdentifier(A11yID.ActiveWorkout.endButton)
        }
        .controlSize(.large)
        .glassContainer(spacing: DesignTokens.Spacing.md)
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

    private var statusSubtitle: String {
        switch workoutController.state {
        case .paused:
            L10n.localized("Paused", comment: "Workout status subtitle")
        default:
            L10n.localized("In Progress", comment: "Workout status subtitle")
        }
    }

    private var statusTint: Color {
        switch workoutController.state {
        case .paused:
            DesignTokens.Colors.warning
        default:
            DesignTokens.Colors.success
        }
    }

    private var statusBadge: some View {
        HStack(spacing: DesignTokens.Spacing.xsPlus) {
            Circle()
                .fill(statusTint)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(statusSubtitle)
                .font(DesignTokens.Typography.footnote.weight(.semibold))
                .foregroundStyle(statusTint)
        }
        .padding(.horizontal, DesignTokens.Spacing.smPlus)
        .padding(.vertical, DesignTokens.Spacing.xsPlus)
        .background(statusTint.opacity(0.14), in: Capsule())
    }

    private var workoutTypeTitle: String {
        workoutController.workoutType?.displayName ?? L10n.localized("Workout", comment: "Fallback workout title")
    }

    private var pauseButtonTitle: String {
        switch workoutController.state {
        case .paused:
            L10n.localized("Resume Workout", comment: "Resume workout button title")
        default:
            L10n.localized("Pause Workout", comment: "Pause workout button title")
        }
    }

    private var pauseButtonIcon: String {
        switch workoutController.state {
        case .paused:
            "play.fill"
        default:
            "pause.fill"
        }
    }

    private var elapsedText: String {
        Self.elapsedFormatter.string(from: workoutController.elapsedTime) ?? "00:00:00"
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

    NavigationStack {
        ActiveWorkoutView()
    }
    .environment(controller)
}
