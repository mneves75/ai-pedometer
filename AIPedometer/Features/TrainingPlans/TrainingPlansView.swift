import SwiftUI
import SwiftData

struct TrainingPlansView: View {
    @AppStorage(AppConstants.UserDefaultsKeys.activityTrackingMode) private var activityModeRaw = ActivityTrackingMode.steps.rawValue
    @Environment(TrainingPlanService.self) private var planService
    @Environment(FoundationModelsService.self) private var aiService

    @Query(
        filter: #Predicate<TrainingPlanRecord> { $0.deletedAt == nil },
        sort: \TrainingPlanRecord.createdAt,
        order: .reverse
    ) private var plans: [TrainingPlanRecord]

    @State private var showingCreateSheet = false
    
    private var activityMode: ActivityTrackingMode {
        ActivityTrackingMode(rawValue: activityModeRaw) ?? .steps
    }

    var body: some View {
        ZStack {
            content
        }
        .uiTestMarker(A11yID.TrainingPlans.marker)
        .accessibilityIdentifier(A11yID.TrainingPlans.marker)
        .navigationTitle(L10n.localized("Training Plans", comment: "Training plans navigation title"))
        .toolbar {
            if aiService.availability.isAvailable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityIdentifier(A11yID.TrainingPlans.createButton)
                    .accessibilityLabel(L10n.localized("Create Plan", comment: "Accessibility label for create plan button"))
                }
            }
        }
        .sheet(isPresented: $showingCreateSheet) {
            CreatePlanSheet()
                .environment(planService)
        }
    }

    @ViewBuilder
    private var content: some View {
        if case .unavailable(let reason) = aiService.availability {
            unavailableView(reason: reason)
        } else if plans.isEmpty {
            emptyStateView
        } else {
            plansList
        }
    }

    private func unavailableView(reason: AIUnavailabilityReason) -> some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            AIUnavailableStateView(reason: reason)
            AIDisclaimerText()
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
    }

    private var emptyStateView: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            ContentUnavailableView {
                Label(L10n.localized("No Training Plans", comment: "Empty state title for training plans"), systemImage: "figure.walk.motion")
            } description: {
                Text(L10n.localized("Create your first AI-powered training plan to start your fitness journey.", comment: "Empty state description for training plans"))
            } actions: {
                Button {
                    showingCreateSheet = true
                } label: {
                    Text(L10n.localized("Create Plan", comment: "Empty state button to create plan"))
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(A11yID.TrainingPlans.createButton)
            }

            AIDisclaimerText()
                .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private var plansList: some View {
        List {
            Section {
                ForEach(plans) { plan in
                    NavigationLink {
                        PlanDetailView(plan: plan, unitName: activityMode.unitName)
                    } label: {
                        PlanRowView(plan: plan, unitName: activityMode.unitName)
                    }
                }
                .onDelete(perform: deletePlans)
            } footer: {
                AIDisclaimerText()
                    .padding(.vertical, DesignTokens.Spacing.xs)
            }
        }
    }

    private func deletePlans(at offsets: IndexSet) {
        for index in offsets {
            planService.deletePlan(plans[index])
        }
    }
}

struct PlanRowView: View {
    let plan: TrainingPlanRecord
    let unitName: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text(plan.name)
                    .font(DesignTokens.Typography.headline)

                Spacer()

                statusBadge
            }

            Text(plan.planDescription)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(2)

            HStack(spacing: DesignTokens.Spacing.md) {
                Label(
                    Localization.format(
                        "Week %lld",
                        comment: "Training plan current week label",
                        Int64(plan.currentWeek)
                    ),
                    systemImage: "calendar"
                )

                if let target = plan.currentWeekTarget {
                    Label(
                        Localization.format(
                            "%@ %@ per day",
                            comment: "Training plan daily target label with unit",
                            target.dailyStepTarget.formatted(),
                            unitName
                        ),
                        systemImage: "figure.walk"
                    )
                }
            }
            .font(DesignTokens.Typography.caption)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private var statusBadge: some View {
                Text(plan.planStatus.localizedName)
                    .font(DesignTokens.Typography.caption.weight(.medium))
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(statusColor.opacity(0.2), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch plan.planStatus {
        case .active: DesignTokens.Colors.success
        case .completed: DesignTokens.Colors.accent
        case .paused: DesignTokens.Colors.warning
        case .abandoned: .gray
        }
    }
}

struct PlanDetailView: View {
    @Environment(TrainingPlanService.self) private var planService
    @Environment(\.dismiss) private var dismiss

    let plan: TrainingPlanRecord
    let unitName: String

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text(plan.planDescription)
                        .font(DesignTokens.Typography.subheadline)

                ProgressView(value: plan.progressPercentage)
                        .tint(DesignTokens.Colors.accent)

                    HStack {
                        Text(
                            Localization.format(
                                "Started: %@",
                                comment: "Training plan start date label",
                                plan.startDate.formatted(date: .abbreviated, time: .omitted)
                            )
                        )
                        Spacer()
                        Text(
                            Localization.format(
                                "Week %lld of %lld",
                                comment: "Training plan week progress label",
                                Int64(plan.currentWeek),
                                Int64(plan.weeklyTargets.count)
                            )
                        )
                    }
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            Section(L10n.localized("Weekly Targets", comment: "Training plan weekly targets section header")) {
                ForEach(Array(plan.weeklyTargets.enumerated()), id: \.offset) { index, target in
                    WeeklyTargetRow(
                        week: index + 1,
                        target: target,
                        isCurrent: index + 1 == plan.currentWeek,
                        unitName: unitName
                    )
                }
            }

            Section {
                if plan.planStatus == .active {
                    Button(L10n.localized("Pause Plan", comment: "Training plan pause button")) {
                        planService.pausePlan(plan)
                    }
                    .foregroundStyle(DesignTokens.Colors.warning)

                    Button(L10n.localized("Complete Plan", comment: "Training plan complete button")) {
                        planService.completePlan(plan)
                        dismiss()
                    }
                    .foregroundStyle(DesignTokens.Colors.success)
                } else if plan.planStatus == .paused {
                    Button(L10n.localized("Resume Plan", comment: "Training plan resume button")) {
                        planService.resumePlan(plan)
                    }
                    .foregroundStyle(DesignTokens.Colors.accent)
                }

                Button(L10n.localized("Delete Plan", comment: "Training plan delete button"), role: .destructive) {
                    planService.deletePlan(plan)
                    dismiss()
                }
            }

            Section {
                AIDisclaimerText()
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.large)
    }
}

struct WeeklyTargetRow: View {
    let week: Int
    let target: WeeklyTarget
    let isCurrent: Bool
    let unitName: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                HStack {
                    Text(
                        Localization.format(
                            "Week %lld",
                            comment: "Weekly target row week label",
                            Int64(week)
                        )
                    )
                        .font(DesignTokens.Typography.subheadline.weight(.medium))

                    if isCurrent {
                        Text(L10n.localized("CURRENT", comment: "Current week badge"))
                            .font(DesignTokens.Typography.caption2.weight(.bold))
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(DesignTokens.Colors.accentMuted, in: Capsule())
                            .foregroundStyle(DesignTokens.Colors.accent)
                    }
                }

                Text(target.focusTip)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("\(target.dailyStepTarget.formatted())")
                    .font(DesignTokens.Typography.headline.monospacedDigit())
                Text(
                    Localization.format(
                        "%@ per day",
                        comment: "Weekly target unit per day label",
                        unitName
                    )
                )
                    .font(DesignTokens.Typography.caption2)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .listRowBackground(isCurrent ? DesignTokens.Colors.accentSoft : nil)
    }
}

struct CreatePlanSheet: View {
    @Environment(TrainingPlanService.self) private var planService
    @Environment(\.dismiss) private var dismiss

    @State private var selectedGoal: TrainingGoalType = .reach10k
    @State private var selectedLevel: FitnessLevel = .beginner
    @State private var daysPerWeek: Int = 5
    @State private var isGenerating = false
    @State private var error: AIServiceError?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L10n.localized("Goal", comment: "Training plan goal picker label"), selection: $selectedGoal) {
                        ForEach(TrainingGoalType.allCases, id: \.self) { goal in
                            VStack(alignment: .leading) {
                                Text(goal.displayName)
                                Text(goal.description)
                                    .font(DesignTokens.Typography.caption)
                                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                            }
                            .tag(goal)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text(L10n.localized("What's your goal?", comment: "Training plan goal section header"))
                }

                Section {
                    Picker(L10n.localized("Fitness Level", comment: "Training plan fitness level picker label"), selection: $selectedLevel) {
                        ForEach(FitnessLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedLevel.description)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                } header: {
                    Text(L10n.localized("Your fitness level", comment: "Training plan fitness level section header"))
                }

                Section {
                    Stepper(
                        Localization.format(
                            "Days per week: %lld",
                            comment: "Training plan days per week stepper",
                            Int64(daysPerWeek)
                        ),
                        value: $daysPerWeek,
                        in: 3...7
                    )
                } header: {
                    Text(L10n.localized("Availability", comment: "Training plan availability section header"))
                }

                if let error {
                    Section {
                        Text(error.localizedDescription)
                            .foregroundStyle(DesignTokens.Colors.red)
                            .font(DesignTokens.Typography.subheadline)
                    }
                }

                Section {
                    AIDisclaimerText()
                }
            }
            .navigationTitle(L10n.localized("Create Plan", comment: "Create plan navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.localized("Cancel", comment: "Cancel button")) { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.localized("Create", comment: "Create button")) {
                        Task { await createPlan() }
                    }
                    .disabled(isGenerating)
                }
            }
            .overlay {
                if isGenerating {
                    ZStack {
                        DesignTokens.Colors.overlayDim
                            .ignoresSafeArea()

                        VStack(spacing: DesignTokens.Spacing.md) {
                            ProgressView()
                                .controlSize(.large)
                            Text(L10n.localized("Creating your personalized plan...", comment: "Training plan creation loading text"))
                                .font(DesignTokens.Typography.subheadline)
                        }
                        .padding(DesignTokens.Spacing.lg)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.lg))
                    }
                }
            }
        }
    }

    private func createPlan() async {
        isGenerating = true
        error = nil

        do {
            _ = try await planService.generatePlan(
                goal: selectedGoal,
                level: selectedLevel,
                daysPerWeek: daysPerWeek
            )
            dismiss()
        } catch {
            self.error = error
        }

        isGenerating = false
    }
}

#Preview {
    @MainActor in
    let demoModeStore = DemoModeStore()
    TrainingPlansView()
        .environment(demoModeStore)
        .environment(FoundationModelsService())
}
