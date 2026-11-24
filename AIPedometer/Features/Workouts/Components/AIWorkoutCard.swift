import SwiftUI

struct AIWorkoutCard: View {
    let recommendation: AIWorkoutRecommendation?
    let summary: String?
    let sourceTitle: String?
    let isLoading: Bool
    let hasLoadedRecommendation: Bool
    let error: AIServiceError?
    let canRefresh: Bool
    var onRefresh: () -> Void
    let unitName: String
    var onStartWorkout: (AIWorkoutRecommendation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            header

            if let error {
                errorContent(error)
            } else if isLoading {
                loadingContent
            } else if let recommendation {
                recommendationContent(recommendation)
            } else if !hasLoadedRecommendation {
                loadingContent
            } else {
                emptyContent
            }
        }
        .padding(DesignTokens.Spacing.mdPlus)
        .calmCard()
        .motionAwareAnimation(DesignTokens.Animation.smooth, value: isLoading)
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.accent)
                .accessibilityHidden(true)

            Text(L10n.localized("Today's Plan", comment: "AI workout card header"))
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Spacer()

            if canRefresh && recommendation != nil && !isLoading {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.footnote.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.localized("Refresh workout plan", comment: "Accessibility label for AI workout refresh button"))
                .accessibilityHint(L10n.localized("Generates a new workout recommendation", comment: "Accessibility hint for AI workout refresh button"))
            }
        }
    }

    private var loadingContent: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ProgressView()
                .controlSize(.small)

            Text(L10n.localized("Generating plan...", comment: "AI workout loading state"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private func errorContent(_ error: AIServiceError) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.Colors.warning)
                .accessibilityHidden(true)

            Text(error.localizedDescription)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Spacer()

            Button(L10n.localized("Try Again", comment: "Retry button"), action: onRefresh)
                .glassSecondaryButton()
                .controlSize(.small)
        }
    }

    private func recommendationContent(_ recommendation: AIWorkoutRecommendation) -> some View {
        let resolvedSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detailCopy = resolvedSummary.flatMap { $0.isEmpty ? nil : $0 }
            ?? recommendation.intent.localizedDescription

        return VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.smPlus) {
                Image(systemName: intentIcon(recommendation.intent))
                    .font(DesignTokens.Typography.title3)
                    .foregroundStyle(intentColor(recommendation.intent))
                    .frame(width: DesignTokens.IconSize.lg, height: DesignTokens.IconSize.lg)
                    .background(intentColor(recommendation.intent).opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(sourceTitle ?? recommendation.intent.localizedTitle)
                        .font(DesignTokens.Typography.headline)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)

                    Text(detailCopy)
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            statsRow(recommendation)

            Button {
                HapticService.shared.confirm()
                onStartWorkout(recommendation)
            } label: {
                HStack(spacing: DesignTokens.Spacing.xsPlus) {
                    Image(systemName: "figure.walk")
                        .accessibilityHidden(true)
                    Text(L10n.localized("Start This Workout", comment: "Start workout button"))
                }
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .glassSecondaryButton()
            .controlSize(.large)

            AIDisclaimerText()
        }
    }

    private func statsRow(_ recommendation: AIWorkoutRecommendation) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            statItem(
                icon: "figure.walk",
                value: recommendation.targetSteps.formattedSteps,
                label: unitName
            )
            statItem(
                icon: "clock",
                value: Formatters.stepCountString(recommendation.estimatedMinutes),
                label: L10n.localized("min", comment: "Minutes abbreviation")
            )
            statItem(
                icon: timeIcon(recommendation.suggestedTimeOfDay),
                value: recommendation.suggestedTimeOfDay.localizedTitle,
                label: L10n.localized("best time", comment: "Best time label")
            )
        }
        .padding(.vertical, DesignTokens.Spacing.smPlus)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceQuaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.md, style: .continuous))
    }

    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.accent)
                .accessibilityHidden(true)
            Text(value)
                .font(DesignTokens.Typography.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    private var emptyContent: some View {
        Text(L10n.localized("No workout plan available", comment: "Empty state"))
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func intentIcon(_ intent: WorkoutIntent) -> String {
        switch intent {
        case .maintain: "equal.circle.fill"
        case .build: "arrow.up.circle.fill"
        case .explore: "map.circle.fill"
        case .recover: "heart.circle.fill"
        }
    }

    private func intentColor(_ intent: WorkoutIntent) -> Color {
        switch intent {
        case .maintain: DesignTokens.Colors.accent
        case .build: DesignTokens.Colors.orange
        case .explore: DesignTokens.Colors.green
        case .recover: DesignTokens.Colors.pink
        }
    }

    private func timeIcon(_ time: TimeOfDay) -> String {
        switch time {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "sunset.fill"
        case .anytime: "clock.fill"
        }
    }
}

#Preview("With Recommendation") {
    AIWorkoutCard(
        recommendation: AIWorkoutRecommendation(
            intent: .build,
            difficulty: 3,
            rationale: "You're at 65% of your goal. A 30-minute walk would help you crush today's target!",
            targetSteps: 4500,
            estimatedMinutes: 30,
            suggestedTimeOfDay: .afternoon
        ),
        summary: "Keep your strongest routine and prioritize consistency.",
        sourceTitle: "Reach 10,000 Steps Daily",
        isLoading: false,
        hasLoadedRecommendation: true,
        error: nil,
        canRefresh: true,
        onRefresh: {},
        unitName: ActivityTrackingMode.steps.unitName,
        onStartWorkout: { _ in }
    )
    .padding(DesignTokens.Spacing.md)
}
