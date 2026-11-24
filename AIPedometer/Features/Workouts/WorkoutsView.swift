import SwiftUI
import SwiftData
import MapKit
import UniformTypeIdentifiers

struct WorkoutsView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @AppStorage(AppConstants.UserDefaultsKeys.expeditionModeEnabled) private var expeditionModeEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(InsightService.self) private var insightService
    @Environment(FoundationModelsService.self) private var aiService
    @Environment(TrainingPlanService.self) private var trainingPlanService
    @Environment(WorkoutSessionController.self) private var workoutController

    @Query(WorkoutsView.recentCompletedWorkoutsDescriptor()) private var recentWorkouts: [WorkoutSession]

    private static func recentCompletedWorkoutsDescriptor(limit: Int = 6) -> FetchDescriptor<WorkoutSession> {
        var descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.deletedAt == nil && $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return descriptor
    }

    @State private var selectedWorkoutType: WorkoutType = .outdoorWalk
    @State private var workoutRecommendation: AIWorkoutRecommendation?
    @State private var recommendationError: AIServiceError?
    @State private var isLoadingRecommendation = false
    @State private var hasLoadedRecommendation = false
    @State private var recommendationRequestID = UUID()
    @State private var importedRoute: ImportedRoute?
    @State private var isImportingRoute = false
    @State private var routeImportError: RouteImportError?
    @State private var isHandlingRecovery = false
    @State private var isConfirmingRecoveryDiscard = false

    private var activityMode: ActivityTrackingMode {
        ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps
    }

    private struct RecommendationTrigger: Hashable {
        let aiAvailable: Bool
        let activePlanID: UUID?
        let activityMode: ActivityTrackingMode
    }

    private struct PresentedError {
        let title: String
        let message: String
    }

    private var presentedError: PresentedError? {
        if let routeImportError {
            return PresentedError(
                title: L10n.localized("Could not import route", comment: "GPX import error alert title"),
                message: routeImportError.message
            )
        }

        // ActiveWorkoutView owns workoutController.lastError while presented so the two views never race alerts.
        if !workoutController.isPresenting, let error = workoutController.lastError {
            return PresentedError(
                title: L10n.localized("Workout Error", comment: "Workout error alert title"),
                message: error.localizedDescription
            )
        }

        return nil
    }

    private var isPresentingError: Binding<Bool> {
        Binding(
            get: { presentedError != nil },
            set: { isPresented in
                if !isPresented {
                    clearPresentedError()
                }
            }
        )
    }

    private func clearPresentedError() {
        routeImportError = nil
        if !workoutController.isPresenting {
            workoutController.lastError = nil
        }
    }

    var body: some View {
        @Bindable var workoutController = workoutController
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.lg) {
                if workoutController.isActive {
                    activeWorkoutBanner
                }
                if workoutController.requiresWorkoutRecovery {
                    recoveryWorkoutSection
                } else {
                    startWorkoutHero
                }

                aiWorkoutSection
                toolsSection
                recentWorkoutsSection
            }
            .padding(.top, DesignTokens.Spacing.sm)
        }
        .tabBarAwareScrollContentBottomInset()
        .accessibilityIdentifier(A11yID.Workouts.scroll)
        .uiTestMarker(
            A11yID.Workouts.recentWorkoutsEmptyState,
            when: recentWorkouts.isEmpty
        )
        .uiTestMarker(
            A11yID.Workouts.recentWorkoutsCarousel,
            when: !recentWorkouts.isEmpty
        )
        .navigationTitle(L10n.localized("Workouts", comment: "Workouts screen title"))
        .navigationBarTitleDisplayMode(.large)
        .background {
            AmbientZenithBackground()
        }
        .sheet(isPresented: $workoutController.isPresenting) {
            NavigationStack {
                ActiveWorkoutView()
            }
            .presentationDetents([.large])
        }
        .fileImporter(
            isPresented: $isImportingRoute,
            allowedContentTypes: [Self.gpxContentType],
            allowsMultipleSelection: false
        ) { result in
            importRoute(from: result)
        }
        .alert(
            presentedError?.title ?? "",
            isPresented: isPresentingError,
            presenting: presentedError
        ) { _ in
            Button(L10n.localized("OK", comment: "Generic OK button"), role: .cancel) {
                clearPresentedError()
            }
        } message: { error in
            Text(error.message)
        }
        .confirmationDialog(
            L10n.localized("Discard Workout", comment: "Confirmation dialog title for discarding workout"),
            isPresented: $isConfirmingRecoveryDiscard,
            titleVisibility: .visible
        ) {
            Button(
                L10n.localized("Discard Workout", comment: "Discard recovered workout action"),
                role: .destructive
            ) {
                handleRecovery(discard: true)
            }
            .accessibilityIdentifier(A11yID.Workouts.confirmDiscardRecoveredWorkoutButton)
            Button(L10n.localized("Cancel", comment: "Cancel action"), role: .cancel) {}
        } message: {
            Text(L10n.localized(
                "This will remove the workout and discard progress.",
                comment: "Message explaining that discarding removes progress"
            ))
        }
        .task {
            if importedRoute == nil {
                importedRoute = GPXRouteImporter.loadImportedRoute()
            }
        }
        .task(id: RecommendationTrigger(
            aiAvailable: aiService.availability.isAvailable,
            activePlanID: activePlan?.id,
            activityMode: activityMode
        )) {
            guard !LaunchConfiguration.isUITesting() else { return }

            recommendationRequestID = UUID()
            isLoadingRecommendation = false
            workoutRecommendation = nil

            if activePlan != nil {
                hasLoadedRecommendation = true
                recommendationError = nil
                workoutRecommendation = nil
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

    /// Imported-route waypoint count. Interpolated so the catalog's plural variations apply.
    static func waypointCountText(_ count: Int, locale: Locale? = nil) -> String {
        L10n.localized("\(Int64(count)) waypoints", locale: locale, comment: "Route waypoint count")
    }

    // MARK: - Primary Hero Action (Above the Fold)

    private var startWorkoutHero: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.mdPlus) {
            ScrollView(.horizontal) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    ForEach(WorkoutType.allCases, id: \.self) { type in
                        let isSelected = selectedWorkoutType == type
                        Button {
                            HapticService.shared.selection()
                            withAnimation(reduceMotion ? nil : DesignTokens.Animation.snappy) {
                                selectedWorkoutType = type
                            }
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xsPlus) {
                                Image(systemName: type.icon)
                                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                                    .accessibilityHidden(true)
                                Text(type.displayName)
                                    .font(DesignTokens.Typography.subheadline.weight(isSelected ? .semibold : .medium))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? DesignTokens.Colors.accent : DesignTokens.Colors.textSecondary)
                            .padding(.horizontal, DesignTokens.Spacing.md)
                            .padding(.vertical, DesignTokens.Spacing.sm)
                            .frame(minHeight: DesignTokens.TouchTarget.minimum)
                            .glassCapsuleSurface(interactive: true, tinted: isSelected)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .glassContainer(spacing: DesignTokens.Spacing.sm)
                .padding(.horizontal, DesignTokens.Spacing.mdPlus)
                .padding(.vertical, DesignTokens.Spacing.xxs)
            }
            .scrollIndicators(.hidden)

            Button {
                HapticService.shared.confirm()
                startWorkout(type: selectedWorkoutType, targetSteps: nil)
            } label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: "play.fill")
                        .font(DesignTokens.Typography.headline)
                        .accessibilityHidden(true)
                    Text(L10n.localized("Start Workout", comment: "Button to begin a workout"))
                        .font(DesignTokens.Typography.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .glassButton()
            .controlSize(.large)
            .accessibilityIdentifier(A11yID.Workouts.startWorkoutButton)
            .accessibleButton(
                label: L10n.localized("Start Workout", comment: "Button to begin a workout"),
                hint: L10n.localized("Begins a new workout session", comment: "Accessibility hint for start workout button")
            )
            .padding(.horizontal, DesignTokens.Spacing.mdPlus)
        }
    }

    // MARK: - Active & Recovery Banners

    private var activeWorkoutBanner: some View {
        Button {
            HapticService.shared.tap()
            workoutController.isPresenting = true
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "figure.walk.motion")
                    .font(DesignTokens.Typography.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.success)
                    .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                    .background(DesignTokens.Colors.success.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)

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
                    .accessibilityHidden(true)
            }
            .padding(DesignTokens.Spacing.md)
            .glassCard(interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.Workouts.activeWorkoutBanner)
        .padding(.horizontal, DesignTokens.Spacing.mdPlus)
        .accessibleCard(
            label: L10n.localized("Active Workout", comment: "Accessibility label for active workout banner"),
            hint: L10n.localized("Resumes your current workout session", comment: "Accessibility hint for active workout banner")
        )
    }

    private var recoveryWorkoutSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .font(DesignTokens.Typography.title3.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .accessibilityHidden(true)

                Text(L10n.localized("Unfinished Workout", comment: "Title for a workout recovered after app interruption"))
                    .font(DesignTokens.Typography.headline)
            }

            Text(L10n.localized(
                "A previous workout ended unexpectedly. Finish it using the last saved checkpoint, or discard it before starting another workout.",
                comment: "Explanation for recovering an unfinished workout"
            ))
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .accessibilityIdentifier(A11yID.Workouts.recoveryMessage)

            VStack(spacing: DesignTokens.Spacing.sm) {
                Button {
                    handleRecovery(discard: false)
                } label: {
                    Text(L10n.localized(
                        "Finish Saved Workout",
                        comment: "Action that finishes an interrupted workout at its last saved checkpoint"
                    ))
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(DesignTokens.Colors.onAccent)
                .accessibilityIdentifier(A11yID.Workouts.finishRecoveredWorkoutButton)

                Button(role: .destructive) {
                    isConfirmingRecoveryDiscard = true
                } label: {
                    Text(L10n.localized("Discard Workout", comment: "Discard recovered workout action"))
                        .font(DesignTokens.Typography.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.Colors.red)
                .foregroundStyle(DesignTokens.Colors.onAccent)
                .accessibilityIdentifier(A11yID.Workouts.discardRecoveredWorkoutButton)
            }
            .controlSize(.large)
            .disabled(isHandlingRecovery)

            if isHandlingRecovery {
                ProgressView(
                    L10n.localized(
                        "Updating workout...",
                        comment: "Progress status while resolving an unfinished workout"
                    )
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DesignTokens.Spacing.mdPlus)
        .calmCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(A11yID.Workouts.recoveryCard)
        .padding(.horizontal, DesignTokens.Spacing.mdPlus)
    }

    // MARK: - AI Recommendation

    @ViewBuilder
    private var aiWorkoutSection: some View {
        if displayedRecommendation != nil || aiService.availability.isAvailable {
            AIWorkoutCard(
                recommendation: displayedRecommendation,
                summary: displayedRecommendationSummary,
                sourceTitle: activePlan?.name,
                isLoading: isLoadingRecommendation && activePlan == nil,
                hasLoadedRecommendation: hasLoadedRecommendation,
                error: activePlan == nil ? recommendationError : nil,
                canRefresh: activePlan == nil && aiService.availability.isAvailable,
                onRefresh: { Task { await loadWorkoutRecommendation(forceRefresh: true) } },
                unitName: activityMode.unitName,
                onStartWorkout: { recommendation in
                    startWorkout(type: selectedWorkoutType, targetSteps: recommendation.targetSteps)
                }
            )
            .padding(.horizontal, DesignTokens.Spacing.mdPlus)
        } else if case .unavailable(let reason) = aiService.availability {
            AIAvailabilityBanner(reason: reason)
                .padding(.horizontal, DesignTokens.Spacing.mdPlus)
        }
    }

    private func loadWorkoutRecommendation(forceRefresh: Bool = false) async {
        guard aiService.availability.isAvailable else { return }
        let requestID = UUID()
        recommendationRequestID = requestID
        let requestedMode = activityMode

        isLoadingRecommendation = true
        recommendationError = nil
        defer {
            if recommendationRequestID == requestID {
                isLoadingRecommendation = false
                hasLoadedRecommendation = true
            }
        }

        do {
            let recommendation = try await insightService.generateWorkoutRecommendation(forceRefresh: forceRefresh)
            guard !Task.isCancelled, recommendationRequestID == requestID,
                  activityMode == requestedMode, activePlan == nil,
                  aiService.availability.isAvailable else { return }
            workoutRecommendation = recommendation
            recommendationError = nil
        } catch {
            guard !Task.isCancelled, recommendationRequestID == requestID,
                  activityMode == requestedMode, activePlan == nil,
                  aiService.availability.isAvailable else { return }
            recommendationError = error
        }
    }

    // MARK: - Streamlined Tools (Training Plans, Routes & GPX, Expedition Mode)

    private var toolsSection: some View {
        VStack(spacing: DesignTokens.Spacing.smPlus) {
            trainingPlansCard
            routeImportCard
            expeditionModeRow
        }
        .padding(.horizontal, DesignTokens.Spacing.mdPlus)
    }

    private var trainingPlansCard: some View {
        NavigationLink {
            TrainingPlansView()
        } label: {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "calendar.badge.plus")
                    .font(DesignTokens.Typography.callout.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.accent)
                    .frame(width: DesignTokens.IconSize.lg, height: DesignTokens.IconSize.lg)
                    .background(DesignTokens.Colors.accentSoft, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(L10n.localized("AI Training Plans", comment: "Training plans card title"))
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)

                    if let activePlan {
                        Text(activePlan.name)
                            .font(DesignTokens.Typography.footnote)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(DesignTokens.Spacing.md)
            .calmCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(A11yID.Workouts.trainingPlansCard)
        .accessibleCard(
            label: L10n.localized("AI Training Plans", comment: "Training plans card title"),
            hint: L10n.localized("Opens AI-powered training plan creation", comment: "Accessibility hint")
        )
    }

    private var routeImportCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                Image(systemName: "map.fill")
                    .font(DesignTokens.Typography.callout.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.mint)
                    .frame(width: DesignTokens.IconSize.lg, height: DesignTokens.IconSize.lg)
                    .background(DesignTokens.Colors.mint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(L10n.localized("Routes & GPX", comment: "Routes GPX card title"))
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if importedRoute == nil {
                        Text(L10n.localized("No route imported", comment: "Empty state for route import card"))
                            .font(DesignTokens.Typography.footnote)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier(A11yID.Workouts.routeImportDescription)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(A11yID.Workouts.routeImportCard)

                Button {
                    isImportingRoute = true
                } label: {
                    Label(
                        L10n.localized("Import GPX", comment: "Button to import a GPX route"),
                        systemImage: "square.and.arrow.down"
                    )
                    .font(DesignTokens.Typography.footnote.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier(A11yID.Workouts.routeImportButtonLabel)
                }
                .glassSecondaryButton()
                .controlSize(.small)
                .layoutPriority(1)
                .accessibilityIdentifier(A11yID.Workouts.routeImportButton)
            }

            if let importedRoute {
                ImportedRouteSummary(route: importedRoute) {
                    GPXRouteImporter.clearImportedRoute()
                    self.importedRoute = nil
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .calmCard()
    }

    private var expeditionModeRow: some View {
        Toggle(isOn: $expeditionModeEnabled) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "battery.100.bolt")
                    .font(DesignTokens.Typography.callout.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.green)
                    .frame(width: DesignTokens.IconSize.lg, height: DesignTokens.IconSize.lg)
                    .background(DesignTokens.Colors.green.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(L10n.localized("Expedition Mode", comment: "Expedition Mode card title"))
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)

                    Text(L10n.localized("Battery saver", comment: "Short subtitle for Expedition Mode battery savings"))
                        .font(DesignTokens.Typography.footnote)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
        }
        .toggleStyle(.switch)
        .tint(DesignTokens.Colors.accent)
        .padding(DesignTokens.Spacing.md)
        .calmCard()
        .accessibilityIdentifier(A11yID.Workouts.expeditionModeToggle)
    }

    // MARK: - Recent Workouts

    private var recentWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            Text(L10n.localized("Recent Workouts", comment: "Workouts view section header"))
                .font(DesignTokens.Typography.headline)
                .padding(.horizontal, DesignTokens.Spacing.mdPlus)

            if recentWorkouts.isEmpty {
                emptyWorkoutsView
            } else {
                recentWorkoutsCarousel
            }
        }
    }

    private var emptyWorkoutsView: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "figure.walk")
                .font(DesignTokens.Typography.title3)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
                .frame(width: DesignTokens.IconSize.lg, height: DesignTokens.IconSize.lg)
                .background(DesignTokens.Colors.surfaceQuaternary, in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(L10n.localized("No workouts yet", comment: "Empty state title"))
                    .font(DesignTokens.Typography.subheadline.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(L10n.localized("Start your first workout to see it here", comment: "Empty state description"))
                    .font(DesignTokens.Typography.footnote)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .calmCard()
        .padding(.horizontal, DesignTokens.Spacing.mdPlus)
    }

    private var recentWorkoutsCarousel: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DesignTokens.Spacing.smPlus) {
                ForEach(recentWorkouts) { workout in
                    WorkoutCard(workout: workout)
                }
            }
            .glassContainer(spacing: DesignTokens.Spacing.smPlus)
            .padding(.horizontal, DesignTokens.Spacing.mdPlus)
        }
        .scrollIndicators(.hidden)
    }

    private func startWorkout(type: WorkoutType = .outdoorWalk, targetSteps: Int? = nil) {
        if workoutController.isActive {
            workoutController.isPresenting = true
            return
        }

        Task {
            await workoutController.startWorkout(type: type, targetSteps: targetSteps)
        }
    }

    private func handleRecovery(discard: Bool) {
        guard !isHandlingRecovery else { return }
        isHandlingRecovery = true
        Task {
            if discard {
                await workoutController.discardRecoverableWorkout()
            } else {
                await workoutController.finishRecoverableWorkout()
            }
            isHandlingRecovery = false
        }
    }

    private func importRoute(from result: Result<[URL], any Error>) {
        let url: URL
        do {
            guard let selected = try result.get().first else { return }
            url = selected
        } catch {
            routeImportError = RouteImportError(message: error.localizedDescription)
            return
        }

        Task {
            do {
                importedRoute = try await Self.importRouteOffMainActor(from: url)
            } catch {
                routeImportError = RouteImportError(message: error.localizedDescription)
            }
        }
    }

    @concurrent
    private nonisolated static func importRouteOffMainActor(from url: URL) async throws -> ImportedRoute {
        try GPXRouteImporter.importRoute(from: url)
    }

    private var activePlan: TrainingPlanRecord? {
        trainingPlanService.fetchActivePlans().first
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
}

private struct RouteImportError: Identifiable {
    let id = UUID()
    let message: String
}

private struct ImportedRouteSummary: View {
    let route: ImportedRoute
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            RoutePreview(segments: route.previewSegments)
                .frame(height: DesignTokens.Sizing.routePreviewHeight)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md, style: .continuous))

            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(route.name)
                        .font(DesignTokens.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)

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
                routeStat(icon: "mountain.2.fill", value: Formatters.elevationString(meters: route.elevationGainMeters), label: L10n.localized("Elevation Gain", comment: "Route elevation gain label"))
                routeStat(icon: "mappin.and.ellipse", value: WorkoutsView.waypointCountText(route.waypointCount), label: L10n.localized("Waypoints", comment: "Route waypoint label"))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func routeStat(icon: String, value: String, label: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(DesignTokens.Colors.accent)
                .frame(width: DesignTokens.IconSize.sm)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(value)
                    .font(DesignTokens.Typography.subheadline.weight(.semibold).monospacedDigit())
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
        .accessibleStatistic(title: label, value: value)
    }
}

struct RoutePreview: View {
    let segments: [[RouteCoordinate]]

    private var coordinateSegments: [[CLLocationCoordinate2D]] {
        segments.map { segment in
            segment.map { point in
                CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            }
        }
    }

    private var coordinates: [CLLocationCoordinate2D] {
        coordinateSegments.flatMap { $0 }
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
        let lineSegments = coordinateSegments.filter { $0.count >= 2 }
        Map(position: .constant(cameraPosition)) {
            ForEach(lineSegments.indices, id: \.self) { index in
                MapPolyline(coordinates: lineSegments[index])
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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            HStack {
                Image(systemName: workout.type.icon)
                    .font(DesignTokens.Typography.callout.weight(.semibold))
                    .foregroundStyle(workout.type.color)
                    .frame(width: DesignTokens.IconSize.lg, height: DesignTokens.IconSize.lg)
                    .background(workout.type.color.opacity(0.15), in: Circle())
                    .accessibilityHidden(true)

                Spacer()

                Text(formattedDate)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
            }

            Text(workout.type.displayName)
                .font(DesignTokens.Typography.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            HStack(spacing: DesignTokens.Spacing.sm) {
                statValue(icon: "figure.walk", value: workout.steps.formattedSteps)
                statValue(icon: "clock", value: formattedDuration)
                statValue(icon: "location", value: workout.distance.formattedDistance())
            }
            .font(DesignTokens.Typography.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(width: DesignTokens.Sizing.workoutCardWidth)
        .calmCard()
        .accessibleCard(
            label: "\(workout.type.displayName), \(formattedDate), \(formattedDuration), \(workout.steps.formattedSteps) \(L10n.localized("Steps", comment: "Workout metric title")), \(workout.distance.formattedDistance())"
        )
    }

    private func statValue(icon: String, value: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
        case .outdoorWalk, .indoorWalk: DesignTokens.Colors.accent
        case .outdoorRun, .indoorRun: DesignTokens.Colors.orange
        case .hike: DesignTokens.Colors.green
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
    NavigationStack {
        WorkoutsView()
    }
    .modelContainer(persistence.container)
    .environment(demoModeStore)
    .environment(foundationModelsService)
    .environment(insightService)
    .environment(trainingPlanService)
    .environment(workoutController)
}
