import SwiftUI
import SwiftData

struct WorkoutsView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var aiService
    @Environment(TrainingPlanService.self) private var trainingPlanService
    @Environment(WorkoutSessionController.self) private var workoutController
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    @Query(
        filter: #Predicate<WorkoutSession> { $0.deletedAt == nil },
        sort: \WorkoutSession.startTime,
        order: .reverse
    ) private var recentWorkouts: [WorkoutSession]

    @State private var workoutRecommendation: AIWorkoutRecommendation?
    @State private var recommendationError: AIServiceError?
    @State private var isLoadingRecommendation = false
    @State private var hasLoadedRecommendation = false

    private var activityMode: ActivityTrackingMode {
        ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps
    }

    private struct RecommendationTrigger: Hashable {
        let aiAvailable: Bool
        let premiumEnabled: Bool
        let premiumResolving: Bool
        let activePlanID: UUID?
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
        .task(id: RecommendationTrigger(
            aiAvailable: aiService.availability.isAvailable,
            premiumEnabled: premiumAccessStore.canAccessAIFeatures,
            premiumResolving: premiumAccessStore.isResolvingAccess,
            activePlanID: activePlan?.id
        )) {
            guard !LaunchConfiguration.isUITesting() else { return }

            if activePlan != nil {
                hasLoadedRecommendation = true
                recommendationError = nil
                workoutRecommendation = nil
                return
            }

            guard premiumAccessStore.canAccessAIFeatures else {
                workoutRecommendation = nil
                recommendationError = nil
                hasLoadedRecommendation = false
                return
            }

            guard aiService.availability.isAvailable else {
                workoutRecommendation = nil
                recommendationError = nil
                hasLoadedRecommendation = false
                return
            }

            await loadWorkoutRecommendation()
        }
    }

    @ViewBuilder
    private var aiWorkoutSection: some View {
        if let displayedRecommendation {
            AIWorkoutCard(
                recommendation: displayedRecommendation,
                summary: displayedRecommendationSummary,
                sourceTitle: activePlan?.name,
                isLoading: isLoadingRecommendation && activePlan == nil,
                hasLoadedRecommendation: hasLoadedRecommendation,
                error: activePlan == nil ? recommendationError : nil,
                canRefresh: activePlan == nil && premiumAccessStore.canAccessAIFeatures && aiService.availability.isAvailable,
                onRefresh: { Task { await loadWorkoutRecommendation(forceRefresh: true) } },
                unitName: activityMode.unitName,
                onStartWorkout: { recommendation in
                    startWorkout(targetSteps: recommendation.targetSteps)
                }
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else if premiumAccessStore.isResolvingAccess {
            PremiumAccessLoadingCard(
                title: L10n.localized("Today's Plan", comment: "AI workout card header")
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else if premiumAccessStore.canAccessAIFeatures {
            if case .unavailable(let reason) = aiService.availability {
                AIAvailabilityBanner(reason: reason)
                    .padding(.horizontal, DesignTokens.Spacing.md)
            }
        } else {
            PremiumFeatureGateCard(
                title: L10n.localized("Today's Plan", comment: "AI workout card header"),
                message: L10n.localized(
                    "Premium is required to generate new AI insights, coaching, plans, and smart reminders.",
                    comment: "Premium gate copy for AI features"
                ),
                accessibilityIdentifier: A11yID.Workouts.premiumTodayPlanGate
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private func loadWorkoutRecommendation(forceRefresh: Bool = false) async {
        guard aiService.availability.isAvailable else { return }
        guard premiumAccessStore.canAccessAIFeatures else { return }
        guard !isLoadingRecommendation else { return }

        isLoadingRecommendation = true
        recommendationError = nil
        defer {
            isLoadingRecommendation = false
            hasLoadedRecommendation = true
        }

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

    private var trainingPlansSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(L10n.localized("Training Plans", comment: "Section header for training plans"))
                .font(DesignTokens.Typography.headline)
                .padding(.horizontal, DesignTokens.Spacing.md)

            if premiumAccessStore.isResolvingAccess && !hasSavedPlans {
                PremiumAccessLoadingCard(
                    title: L10n.localized("AI Training Plans", comment: "Training plans card title")
                )
            } else if !premiumAccessStore.canAccessAIFeatures && !hasSavedPlans {
                PremiumFeatureGateCard(
                    title: L10n.localized("AI Training Plans", comment: "Training plans card title"),
                    message: L10n.localized(
                        "Premium is required to generate new AI insights, coaching, plans, and smart reminders.",
                        comment: "Premium gate copy for AI features"
                    ),
                    accessibilityIdentifier: A11yID.Workouts.premiumTrainingPlansGate
                )
            } else {
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

                            Text(trainingPlansSubtitle)
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
                .accessibilityIdentifier(A11yID.Workouts.trainingPlansCard)
                .accessibleCard(
                    label: L10n.localized("AI Training Plans", comment: "Training plans card title"),
                    hint: L10n.localized("Opens AI-powered training plan creation", comment: "Accessibility hint")
                )
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(L10n.localized("Recent Workouts", comment: "Workouts view section header"))
                .font(DesignTokens.Typography.headline)
                .padding(.horizontal, DesignTokens.Spacing.md)

            if completedRecentWorkouts.isEmpty {
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
        .accessibilityIdentifier(A11yID.Workouts.recentWorkoutsEmptyState)
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
            ForEach(completedRecentWorkouts) { workout in
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

    private var activePlan: TrainingPlanRecord? {
        trainingPlanService.fetchActivePlans().first
    }

    private var hasSavedPlans: Bool {
        !trainingPlanService.fetchAllPlans().isEmpty
    }

    private var displayedRecommendation: AIWorkoutRecommendation? {
        if let activePlan {
            return recommendation(for: activePlan)
        }
        return workoutRecommendation
    }

    private var displayedRecommendationSummary: String? {
        if let activePlan {
            return activePlan.currentWeekTarget?.focusTip ?? activePlan.planDescription
        }
        return workoutRecommendation.map { $0.intent.localizedDescription }
    }

    private var completedRecentWorkouts: [WorkoutSession] {
        Self.recentCompletedWorkouts(from: recentWorkouts)
    }

    private var trainingPlansSubtitle: String {
        if let activePlan {
            return activePlan.planDescription
        }
        return L10n.localized("Get personalized plans powered by AI", comment: "Training plans card subtitle")
    }

    private func recommendation(for plan: TrainingPlanRecord) -> AIWorkoutRecommendation? {
        guard let target = plan.currentWeekTarget else { return nil }

        return AIWorkoutRecommendation(
            intent: intent(for: plan),
            difficulty: difficulty(for: target.dailyStepTarget),
            rationale: plan.planDescription,
            targetSteps: target.dailyStepTarget,
            estimatedMinutes: max(Int(Double(target.dailyStepTarget) / 110.0), 15),
            suggestedTimeOfDay: .anytime
        )
    }

    private func intent(for plan: TrainingPlanRecord) -> WorkoutIntent {
        switch TrainingGoalType(rawValue: plan.primaryGoal) {
        case .startWalking, .improveConsistency:
            return .maintain
        case .buildEndurance, .reach10k:
            return .build
        case .weightManagement:
            return .explore
        case .none:
            return .maintain
        }
    }

    private func difficulty(for targetSteps: Int) -> Int {
        switch targetSteps {
        case ..<3_500: return 1
        case ..<6_000: return 2
        case ..<9_000: return 3
        case ..<12_000: return 4
        default: return 5
        }
    }

    static func recentCompletedWorkouts(
        from workouts: [WorkoutSession],
        limit: Int = 6
    ) -> [WorkoutSession] {
        Array(workouts.filter { $0.endTime != nil }.prefix(limit))
    }
}

struct WorkoutCard: View {
    let workout: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            iconBadge
            workoutInfo
            statsRow
        }
        .padding(DesignTokens.Spacing.md)
        .frame(width: 190)
        .glassCard()
        .accessibleCard(label: "\(workout.type.displayName), \(formattedDate), \(formattedDuration)")
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
            Text(formattedDate)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
    }

    private var statsRow: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            statValue(icon: "figure.walk", value: workout.steps.formattedSteps)
            statValue(icon: "clock", value: formattedDuration)
            statValue(icon: "location", value: workout.distance.formattedDistance())
        }
        .font(DesignTokens.Typography.caption.weight(.medium))
        .foregroundStyle(DesignTokens.Colors.textSecondary)
    }

    private func statValue(icon: String, value: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: icon)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
    let trainingPlanService = TrainingPlanService(
        foundationModelsService: foundationModelsService,
        healthKitService: healthKitService,
        goalService: goalService,
        modelContext: persistence.container.mainContext
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
        .environment(trainingPlanService)
        .environment(workoutController)
        .environment(PremiumAccessStore(forcedPremiumEnabled: true, isTesting: true))
}
