import SwiftUI
import SwiftData

struct WorkoutsView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var aiService
    @Environment(WorkoutSessionController.self) private var workoutController
    @Namespace private var workoutNamespace

    @Query(
        filter: #Predicate<WorkoutSession> { $0.deletedAt == nil },
        sort: \WorkoutSession.startTime,
        order: .reverse
    ) private var recentWorkouts: [WorkoutSession]

    @State private var workoutRecommendation: AIWorkoutRecommendation?
    @State private var recommendationError: AIServiceError?
    @State private var isLoadingRecommendation = false
    
    private var activityMode: ActivityTrackingMode {
        ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps
    }

    private struct RecommendationTrigger: Hashable {
        let aiAvailable: Bool
    }

    var body: some View {
        @Bindable var workoutController = workoutController
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                headerSection
                if workoutController.isActive {
                    activeWorkoutBanner
                }
                aiWorkoutSection
                startWorkoutSection
                trainingPlansSection
                recentWorkoutsSection
            }
        }
        .tabBarAwareScrollContentBottomInset()
        .accessibilityIdentifier(A11yID.Workouts.scroll)
        .toolbar(.hidden, for: .navigationBar)
        .background(DesignTokens.Colors.surfaceGrouped)
        .sheet(isPresented: $workoutController.isPresenting) {
            ActiveWorkoutView()
                .presentationDetents([.large])
        }
        .task(id: RecommendationTrigger(aiAvailable: aiService.availability.isAvailable)) {
            guard !LaunchConfiguration.isUITesting() else { return }
            await loadWorkoutRecommendation()
        }
    }

    @ViewBuilder
    private var aiWorkoutSection: some View {
        if aiService.availability.isAvailable {
            AIWorkoutCard(
                recommendation: workoutRecommendation,
                isLoading: isLoadingRecommendation,
                error: recommendationError,
                onRefresh: { Task { await loadWorkoutRecommendation(forceRefresh: true) } },
                unitName: activityMode.unitName,
                onStartWorkout: { recommendation in
                    startWorkout(targetSteps: recommendation.targetSteps)
                }
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private func loadWorkoutRecommendation(forceRefresh: Bool = false) async {
        guard aiService.availability.isAvailable else { return }
        guard !isLoadingRecommendation else { return }

        isLoadingRecommendation = true
        recommendationError = nil
        defer { isLoadingRecommendation = false }

        do {
            workoutRecommendation = try await insightService.generateWorkoutRecommendation(forceRefresh: forceRefresh)
        } catch {
            recommendationError = error
        }
    }

    private var headerSection: some View {
        HStack {
            Text(L10n.localized("Workouts", comment: "Workouts screen title"))
                .font(DesignTokens.Typography.largeTitle.bold())
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private var activeWorkoutBanner: some View {
        Button {
            HapticService.shared.tap()
            workoutController.isPresenting = true
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "figure.walk.motion")
                    .font(DesignTokens.Typography.title2)
                    .foregroundStyle(DesignTokens.Colors.success)
                    .frame(width: 44, height: 44)
                    .background(DesignTokens.Colors.success.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(L10n.localized("Active Workout", comment: "Banner title for an active workout"))
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Text(L10n.localized("Tap to resume", comment: "Banner subtitle for resuming an active workout"))
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.Workouts.activeWorkoutBanner)
        .padding(.horizontal, DesignTokens.Spacing.md)
        .accessibleCard(
            label: L10n.localized("Active Workout", comment: "Accessibility label for active workout banner"),
            hint: L10n.localized("Resumes your current workout session", comment: "Accessibility hint for active workout banner")
        )
    }

    private var startWorkoutSection: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: DesignTokens.FontSize.xxl))
                .foregroundStyle(DesignTokens.Colors.accent.gradient)
                .applyIfNotUITesting { view in
                    view.symbolEffect(.breathe.pulse.byLayer)
                }

            Text(L10n.localized("Ready to start?", comment: "Workouts view prompt"))
                .font(DesignTokens.Typography.title2.bold())

            Button {
                HapticService.shared.confirm()
                startWorkout(targetSteps: nil)
            } label: {
                Text(L10n.localized("Start Workout", comment: "Button to begin a workout"))
                    .font(DesignTokens.Typography.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(DesignTokens.Spacing.md)
            }
            .glassButton()
            .accessibilityIdentifier(A11yID.Workouts.startWorkoutButton)
            .padding(.horizontal, DesignTokens.Spacing.xl)
            .accessibleButton(
                label: L10n.localized("Start Workout", comment: "Button to begin a workout"),
                hint: L10n.localized("Begins a new workout session", comment: "Accessibility hint for start workout button")
            )
        }
        .padding(.vertical, DesignTokens.Spacing.lg)
    }

    // MARK: - Training Plans Section

    private var trainingPlansSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(L10n.localized("Training Plans", comment: "Section header for training plans"))
                .font(DesignTokens.Typography.headline)
                .padding(.horizontal, DesignTokens.Spacing.md)

            NavigationLink {
                TrainingPlansView()
            } label: {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "calendar.badge.plus")
                        .font(DesignTokens.Typography.title2)
                        .foregroundStyle(DesignTokens.Colors.accent)
                        .frame(width: 44, height: 44)
                        .background(DesignTokens.Colors.accentSoft, in: Circle())

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(L10n.localized("AI Training Plans", comment: "Training plans card title"))
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        Text(L10n.localized("Get personalized plans powered by AI", comment: "Training plans card subtitle"))
                            .font(DesignTokens.Typography.subheadline)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(DesignTokens.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                }
                .padding(DesignTokens.Spacing.md)
                .glassCard(interactive: true)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DesignTokens.Spacing.md)
            .accessibilityIdentifier(A11yID.Workouts.trainingPlansCard)
            .accessibleCard(
                label: L10n.localized("AI Training Plans", comment: "Training plans card title"),
                hint: L10n.localized("Opens AI-powered training plan creation", comment: "Accessibility hint")
            )
        }
    }

    // MARK: - Recent Workouts Section

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(L10n.localized("Recent Workouts", comment: "Workouts view section header"))
                .font(DesignTokens.Typography.headline)
                .padding(.horizontal, DesignTokens.Spacing.md)

            if recentWorkouts.isEmpty {
                emptyWorkoutsView
            } else {
                recentWorkoutsCarousel
            }
        }
    }

    private var emptyWorkoutsView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "figure.walk")
                .font(.system(size: DesignTokens.FontSize.xs))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(L10n.localized("No workouts yet", comment: "Empty state title"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Text(L10n.localized("Start your first workout to see it here", comment: "Empty state description"))
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.xl)
        .glassCard()
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    @ViewBuilder
    private var recentWorkoutsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if LaunchConfiguration.isUITesting() {
                workoutCardsRow
                    .padding(.horizontal, DesignTokens.Spacing.md)
            } else if #available(iOS 26, *) {
                GlassEffectContainer(spacing: DesignTokens.Spacing.md) {
                    workoutCardsRow
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
            } else {
                workoutCardsRow
                    .padding(.horizontal, DesignTokens.Spacing.md)
            }
        }
    }

    private var workoutCardsRow: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ForEach(recentWorkouts.prefix(5)) { workout in
                WorkoutCard(workout: workout)
            }
        }
    }

    private func startWorkout(targetSteps: Int? = nil) {
        if workoutController.isActive {
            workoutController.isPresenting = true
            return
        }

        Task {
            await workoutController.startWorkout(type: .outdoorWalk, targetSteps: targetSteps)
        }
    }
}

// MARK: - Workout Card

struct WorkoutCard: View {
    let workout: WorkoutSession

    var body: some View {
        Button {
            HapticService.shared.tap()
        } label: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                iconBadge
                workoutInfo
            }
            .padding(DesignTokens.Spacing.md)
            .frame(width: 160)
            .glassCard(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibleCard(label: "\(workout.type.displayName), \(formattedDuration), \(formattedDate)")
    }

    private var iconBadge: some View {
        HStack {
            Image(systemName: workout.type.icon)
                .font(DesignTokens.Typography.title2)
                .foregroundStyle(DesignTokens.Colors.inverseText)
                .padding(DesignTokens.Spacing.sm)
                .background(workout.type.color.gradient, in: Circle())
            Spacer()
        }
    }

    private var workoutInfo: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(workout.type.displayName)
                .font(DesignTokens.Typography.headline)
            Text(formattedDuration)
                .font(DesignTokens.Typography.subheadline.bold())
            Text(formattedDate)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

    private var formattedDuration: String {
        guard let endTime = workout.endTime else {
            return L10n.localized("In Progress", comment: "Workout status")
        }
        let duration = endTime.timeIntervalSince(workout.startTime)
        return Formatters.durationString(seconds: duration)
    }

    private var formattedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(workout.startTime) {
            return L10n.localized("Today", comment: "Date label for today")
        } else if calendar.isDateInYesterday(workout.startTime) {
            return L10n.localized("Yesterday", comment: "Date label for yesterday")
        } else {
            return workout.startTime.formatted(date: .abbreviated, time: .omitted)
        }
    }
}

// MARK: - WorkoutType Extension

extension WorkoutType {
    var color: Color {
        switch self {
        case .outdoorWalk, .indoorWalk: return DesignTokens.Colors.accent
        case .outdoorRun, .indoorRun: return DesignTokens.Colors.orange
        case .hike: return DesignTokens.Colors.green
        }
    }
}

#Preview {
    @MainActor in
    let persistence = PersistenceController(inMemory: true)
    let demoModeStore = DemoModeStore()
    let healthKitService = HealthKitServiceFallback(demoModeStore: demoModeStore)
    let goalService = GoalService(persistence: persistence)
    let dataStore = SharedDataStore()
    let foundationModelsService = FoundationModelsService()
    let insightService = InsightService(
        foundationModelsService: foundationModelsService,
        healthKitService: healthKitService,
        goalService: goalService,
        dataStore: dataStore
    )
    let workoutController = WorkoutSessionController(
        modelContext: persistence.container.mainContext,
        healthKitService: healthKitService,
        metricsSource: MotionLiveMetricsSource(motionService: MotionService()),
        liveActivityManager: NoopLiveActivityManager()
    )
    WorkoutsView()
        .modelContainer(persistence.container)
        .environment(demoModeStore)
        .environment(foundationModelsService)
        .environment(insightService)
        .environment(workoutController)
}
