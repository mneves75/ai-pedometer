import SwiftUI
import SwiftData
import MapKit
import UniformTypeIdentifiers

struct WorkoutsView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.expeditionModeEnabled) private var expeditionModeEnabled = false
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var aiService
    @Environment(TrainingPlanService.self) private var trainingPlanService
    @Environment(WorkoutSessionController.self) private var workoutController
    @Environment(PremiumAccessStore.self) private var premiumAccessStore

    // Bounded fetch: the carousel shows at most 6 completed sessions, but an unbounded
    // query would fetch and observe every workout ever recorded (soft-deleted rows are
    // never pruned), growing without limit for long-term users.
    @Query(WorkoutsView.recentCompletedWorkoutsDescriptor()) private var recentWorkouts: [WorkoutSession]

    private static func recentCompletedWorkoutsDescriptor(limit: Int = 6) -> FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    @State private var workoutRecommendation: AIWorkoutRecommendation?
    @State private var recommendationError: AIServiceError?
    @State private var isLoadingRecommendation = false
    @State private var hasLoadedRecommendation = false
    @State private var importedRoute: ImportedRoute? = GPXRouteImporter.loadImportedRoute()
    @State private var isImportingRoute = false
    @State private var routeImportError: RouteImportError?

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
                expeditionModeSection
                routeImportSection
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
        .fileImporter(
            isPresented: $isImportingRoute,
            allowedContentTypes: [Self.gpxContentType],
            allowsMultipleSelection: false
        ) { result in
            importRoute(from: result)
        }
        .alert(item: $routeImportError) { error in
            Alert(
                title: Text(L10n.localized("Could not import route", comment: "GPX import error alert title")),
                message: Text(error.message),
                dismissButton: .default(Text(L10n.localized("OK", comment: "Generic OK button")))
            )
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

    private static let gpxContentType = UTType(filenameExtension: "gpx") ?? .xml

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

    @ViewBuilder
    private var expeditionModeSection: some View {
        if premiumAccessStore.isResolvingAccess {
            PremiumAccessLoadingCard(
                title: L10n.localized("Expedition Mode", comment: "Expedition Mode card title")
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else if premiumAccessStore.canAccessAIFeatures {
            Toggle(isOn: $expeditionModeEnabled) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "battery.100.bolt")
                        .font(DesignTokens.Typography.title2)
                        .foregroundStyle(DesignTokens.Colors.green)
                        .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                        .background(DesignTokens.Colors.green.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(L10n.localized("Expedition Mode", comment: "Expedition Mode card title"))
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        Text(
                            L10n.localized(
                                "Use fewer live metric updates during long hikes and walks to reduce battery impact.",
                                comment: "Expedition Mode explanatory copy"
                            )
                        )
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
            }
            .toggleStyle(.switch)
            .padding(DesignTokens.Spacing.md)
            .glassCard()
            .accessibilityIdentifier(A11yID.Workouts.expeditionModeToggle)
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else {
            PremiumFeatureGateCard(
                title: L10n.localized("Expedition Mode", comment: "Expedition Mode card title"),
                message: L10n.localized(
                    "Premium is required to reduce live metric updates during long workouts.",
                    comment: "Premium gate copy for Expedition Mode"
                ),
                accessibilityIdentifier: A11yID.Workouts.premiumExpeditionModeGate
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
            .task { expeditionModeEnabled = false }
        }
    }

    @ViewBuilder
    private var routeImportSection: some View {
        if premiumAccessStore.isResolvingAccess {
            PremiumAccessLoadingCard(
                title: L10n.localized("Routes & GPX", comment: "Routes GPX card title")
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else if premiumAccessStore.canAccessAIFeatures {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "map.fill")
                        .font(DesignTokens.Typography.title2)
                        .foregroundStyle(DesignTokens.Colors.mint)
                        .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                        .background(DesignTokens.Colors.mint.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(L10n.localized("Routes & GPX", comment: "Routes GPX card title"))
                            .font(DesignTokens.Typography.headline)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        Text(
                            L10n.localized(
                                "Import a GPX route before a walk or hike to keep distance, elevation, and waypoints close at hand.",
                                comment: "Routes GPX explanatory copy"
                            )
                        )
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    }
                }
                .accessibilityIdentifier(A11yID.Workouts.routeImportCard)

                if let importedRoute {
                    ImportedRouteSummary(route: importedRoute) {
                        GPXRouteImporter.clearImportedRoute()
                        self.importedRoute = nil
                    }
                } else {
                    Text(L10n.localized("No route imported", comment: "Empty state for route import card"))
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    isImportingRoute = true
                } label: {
                    Label(
                        L10n.localized("Import GPX", comment: "Button to import a GPX route"),
                        systemImage: "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .glassButton()
                .accessibilityIdentifier(A11yID.Workouts.routeImportButton)
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard()
            .padding(.horizontal, DesignTokens.Spacing.md)
        } else {
            PremiumFeatureGateCard(
                title: L10n.localized("Routes & GPX", comment: "Routes GPX card title"),
                message: L10n.localized(
                    "Premium is required to import GPX routes and plan map-guided workouts.",
                    comment: "Premium gate copy for Routes GPX"
                ),
                accessibilityIdentifier: A11yID.Workouts.premiumRoutesGate
            )
            .padding(.horizontal, DesignTokens.Spacing.md)
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
                    .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
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
                .applyIfMotionEnabled { view in
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
                            .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
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

    private func importRoute(from result: Result<[URL], any Error>) {
        guard Self.canImportRoute(premiumEnabled: premiumAccessStore.canAccessAIFeatures) else {
            routeImportError = RouteImportError(
                message: L10n.localized(
                    "Premium is required to import GPX routes.",
                    comment: "Error shown when a GPX import is attempted without premium access"
                )
            )
            return
        }

        let url: URL
        do {
            guard let selected = try result.get().first else { return }
            url = selected
        } catch {
            routeImportError = RouteImportError(message: error.localizedDescription)
            return
        }

        // Parse off the main actor. A GPX file can be up to GPXRouteParser.maxFileSizeBytes
        // (5 MiB) and XML parsing plus coordinate decoding is CPU-bound; doing it inline in the
        // fileImporter callback hitched the dismissal animation on large routes. `ImportedRoute`
        // is Sendable, so the parsed value crosses back to the main actor safely.
        Task {
            do {
                let route = try await Task.detached(priority: .userInitiated) {
                    try GPXRouteImporter.importRoute(from: url)
                }.value
                importedRoute = route
            } catch {
                routeImportError = RouteImportError(message: error.localizedDescription)
            }
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
            return activePlan.currentWorkoutRecommendation
        }
        return workoutRecommendation
    }

    private var displayedRecommendationSummary: String? {
        if let activePlan {
            return activePlan.currentWorkoutRecommendationSummary
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

    static func recentCompletedWorkouts(
        from workouts: [WorkoutSession],
        limit: Int = 6
    ) -> [WorkoutSession] {
        Array(workouts.filter { $0.endTime != nil }.prefix(limit))
    }

    static func canImportRoute(premiumEnabled: Bool) -> Bool {
        premiumEnabled
    }
}

private struct RouteImportError: Identifiable {
    let id = UUID()
    let message: String
}

private struct ImportedRouteSummary: View {
    let route: ImportedRoute
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            RoutePreview(points: route.previewPoints)
                .frame(height: DesignTokens.Sizing.routePreviewHeight)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))

            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(route.name)
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(2)

                    Text(route.sourceFilename)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                        .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.localized("Remove Route", comment: "Button to remove imported route"))
                .accessibilityIdentifier(A11yID.Workouts.routeRemoveButton)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.sm) {
                routeStat(icon: "point.topleft.down.curvedto.point.bottomright.up", value: route.distanceMeters.formattedDistance(), label: L10n.localized("Distance", comment: "Workout metric title"))
                routeStat(icon: "clock", value: Formatters.durationString(seconds: route.estimatedDuration), label: L10n.localized("Estimated", comment: "Route estimate label"))
                routeStat(icon: "mountain.2.fill", value: Formatters.distanceString(meters: route.elevationGainMeters), label: L10n.localized("Elevation Gain", comment: "Route elevation gain label"))
                routeStat(icon: "mappin.and.ellipse", value: Localization.format("%d waypoints", comment: "Route waypoint count", route.waypointCount), label: L10n.localized("Waypoints", comment: "Route waypoint label"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func routeStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(width: DesignTokens.IconSize.sm)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(value)
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(label)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RoutePreview: View {
    let points: [RouteCoordinate]

    private var coordinates: [CLLocationCoordinate2D] {
        points.map { point in
            CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        coordinates.first
    }

    private var finishCoordinate: CLLocationCoordinate2D? {
        coordinates.last
    }

    private var cameraPosition: MapCameraPosition {
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 1, height: 1)
            rect = rect.union(pointRect)
        }

        guard !rect.isNull else {
            return .automatic
        }

        let horizontalPadding = max(rect.width * 0.2, 1_000)
        let verticalPadding = max(rect.height * 0.2, 1_000)
        return .rect(rect.insetBy(dx: -horizontalPadding, dy: -verticalPadding))
    }

    var body: some View {
        Map(initialPosition: cameraPosition) {
            if coordinates.count >= 2 {
                MapPolyline(coordinates: coordinates)
                    .stroke(DesignTokens.Colors.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            if let startCoordinate {
                Marker(L10n.localized("Start", comment: "Route preview start marker"), systemImage: "figure.walk", coordinate: startCoordinate)
                    .tint(DesignTokens.Colors.green)
            }

            if let finishCoordinate {
                Marker(L10n.localized("Finish", comment: "Route preview finish marker"), systemImage: "flag.checkered", coordinate: finishCoordinate)
                    .tint(DesignTokens.Colors.accent)
            }
        }
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .accessibilityLabel(L10n.localized("Route map preview", comment: "Accessibility label for imported route map preview"))
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
        .frame(width: DesignTokens.Sizing.workoutCardWidth)
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
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(formattedDate)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
                .minimumScaleFactor(0.7)
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
