import SwiftUI
import SwiftData
import UIKit

struct TrainingPlansView: View {
    @Environment(TrainingPlanService.self) private var planService
    @Environment(FoundationModelsService.self) private var aiService
    @Environment(\.openURL) private var openURL

    @Query(
        filter: #Predicate<TrainingPlanRecord> { $0.deletedAt == nil },
        sort: \TrainingPlanRecord.createdAt,
        order: .reverse
    ) private var plans: [TrainingPlanRecord]

    @State private var showingCreateSheet = false

    var body: some View {
        ZStack {
            content
        }
        .accessibilityIdentifier("training_plans_screen")
        .navigationTitle(String(localized: "Training Plans", comment: "Training plans navigation title"))
        .toolbar {
            if aiService.availability.isAvailable {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
        ContentUnavailableView {
            Label(String(localized: "AI Features Unavailable", comment: "AI unavailable title"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(reason.userFacingMessage)
        } actions: {
            if reason.hasAction {
                Button(reason.actionTitle) {
                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(settingsURL)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(String(localized: "No Training Plans", comment: "Empty state title for training plans"), systemImage: "figure.walk.motion")
        } description: {
            Text(String(localized: "Create your first AI-powered training plan to start your fitness journey.", comment: "Empty state description for training plans"))
        } actions: {
            Button {
                showingCreateSheet = true
            } label: {
                Text(String(localized: "Create Plan", comment: "Empty state button to create plan"))
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var plansList: some View {
        List {
            ForEach(plans) { plan in
                NavigationLink {
                    PlanDetailView(plan: plan)
                } label: {
                    PlanRowView(plan: plan)
                }
            }
            .onDelete(perform: deletePlans)
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

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack {
                Text(plan.name)
                    .font(.headline)

                Spacer()

                statusBadge
            }

            Text(plan.planDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                            "%@ steps/day",
                            comment: "Training plan daily target label",
                            target.dailyStepTarget.formatted()
                        ),
                        systemImage: "figure.walk"
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private var statusBadge: some View {
                Text(plan.planStatus.localizedName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, DesignTokens.Spacing.sm)
                    .padding(.vertical, DesignTokens.Spacing.xxs)
                    .background(statusColor.opacity(0.2), in: Capsule())
            .foregroundStyle(statusColor)
    }

    private var statusColor: Color {
        switch plan.planStatus {
        case .active: .green
        case .completed: .blue
        case .paused: .orange
        case .abandoned: .gray
        }
    }
}

struct PlanDetailView: View {
    @Environment(TrainingPlanService.self) private var planService
    @Environment(\.dismiss) private var dismiss

    let plan: TrainingPlanRecord

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Text(plan.planDescription)
                        .font(.subheadline)

                    ProgressView(value: plan.progressPercentage)
                        .tint(.blue)

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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "Weekly Targets", comment: "Training plan weekly targets section header")) {
                ForEach(Array(plan.weeklyTargets.enumerated()), id: \.offset) { index, target in
                    WeeklyTargetRow(
                        week: index + 1,
                        target: target,
                        isCurrent: index + 1 == plan.currentWeek
                    )
                }
            }

            Section {
                if plan.planStatus == .active {
                    Button(String(localized: "Pause Plan", comment: "Training plan pause button")) {
                        planService.pausePlan(plan)
                    }
                    .foregroundStyle(.orange)

                    Button(String(localized: "Complete Plan", comment: "Training plan complete button")) {
                        planService.completePlan(plan)
                        dismiss()
                    }
                    .foregroundStyle(.green)
                } else if plan.planStatus == .paused {
                    Button(String(localized: "Resume Plan", comment: "Training plan resume button")) {
                        planService.resumePlan(plan)
                    }
                    .foregroundStyle(.blue)
                }

                Button(String(localized: "Delete Plan", comment: "Training plan delete button"), role: .destructive) {
                    planService.deletePlan(plan)
                    dismiss()
                }
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
                        .font(.subheadline.weight(.medium))

                    if isCurrent {
                        Text(String(localized: "CURRENT", comment: "Current week badge"))
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, DesignTokens.Spacing.xs)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }

                Text(target.focusTip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing) {
                Text("\(target.dailyStepTarget.formatted())")
                    .font(.headline.monospacedDigit())
                Text(String(localized: "steps/day", comment: "Weekly target steps per day unit"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
        .listRowBackground(isCurrent ? Color.blue.opacity(0.1) : nil)
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
                    Picker(String(localized: "Goal", comment: "Training plan goal picker label"), selection: $selectedGoal) {
                        ForEach(TrainingGoalType.allCases, id: \.self) { goal in
                            VStack(alignment: .leading) {
                                Text(goal.displayName)
                                Text(goal.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(goal)
                        }
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text(String(localized: "What's your goal?", comment: "Training plan goal section header"))
                }

                Section {
                    Picker(String(localized: "Fitness Level", comment: "Training plan fitness level picker label"), selection: $selectedLevel) {
                        ForEach(FitnessLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedLevel.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(String(localized: "Your fitness level", comment: "Training plan fitness level section header"))
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
                    Text(String(localized: "Availability", comment: "Training plan availability section header"))
                }

                if let error {
                    Section {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(String(localized: "Create Plan", comment: "Create plan navigation title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Cancel button")) { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create", comment: "Create button")) {
                        Task { await createPlan() }
                    }
                    .disabled(isGenerating)
                }
            }
            .overlay {
                if isGenerating {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()

                        VStack(spacing: DesignTokens.Spacing.md) {
                            ProgressView()
                                .controlSize(.large)
                            Text(String(localized: "Creating your personalized plan...", comment: "Training plan creation loading text"))
                                .font(.subheadline)
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
