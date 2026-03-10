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
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
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

            AIDisclaimerText()
                .padding(.top, DesignTokens.Spacing.xs)
        }
        .padding(DesignTokens.Spacing.md)
        .glassCard()
        .animation(DesignTokens.Animation.smooth, value: isLoading)
    }
    
    private var header: some View {
        HStack {
            Label {
                Text(L10n.localized("Today's Plan", comment: "AI workout card header"))
                    .font(DesignTokens.Typography.headline)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(DesignTokens.Colors.accent)
            }
            
            Spacer()
            
            if canRefresh && recommendation != nil && !isLoading {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.subheadline)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
                .frame(width: 44, height: 44)
                .buttonStyle(.plain)
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
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
    
    private func errorContent(_ error: AIServiceError) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Label {
                Text(error.localizedDescription)
                    .font(DesignTokens.Typography.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.orange)
            }
            
            Button(action: onRefresh) {
                Text(L10n.localized("Try Again", comment: "Retry button"))
                    .font(DesignTokens.Typography.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .foregroundStyle(DesignTokens.Colors.textSecondary)
    }
    
    private func recommendationContent(_ recommendation: AIWorkoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            intentBadge(recommendation.intent)

            if let sourceTitle {
                Text(sourceTitle)
                    .font(DesignTokens.Typography.caption.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            Text(summary ?? recommendation.intent.localizedDescription)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            
            statsRow(recommendation)
            
            Button {
                HapticService.shared.confirm()
                onStartWorkout(recommendation)
            } label: {
                HStack {
                    Image(systemName: "figure.walk")
                    Text(L10n.localized("Start This Workout", comment: "Start workout button"))
                }
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(DesignTokens.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignTokens.Colors.accent)
        }
    }
    
    private func intentBadge(_ intent: WorkoutIntent) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: intentIcon(intent))
                .font(DesignTokens.Typography.title3)
                .foregroundStyle(intentColor(intent))
            
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(intent.localizedTitle)
                    .font(DesignTokens.Typography.subheadline.weight(.semibold))
                Text(intent.localizedDescription)
                    .font(DesignTokens.Typography.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
    }
    
    private func statsRow(_ recommendation: AIWorkoutRecommendation) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            statItem(
                icon: "figure.walk",
                value: recommendation.targetSteps.formatted(),
                label: unitName
            )
            
            statItem(
                icon: "clock",
                value: "\(recommendation.estimatedMinutes)",
                label: L10n.localized("min", comment: "Minutes abbreviation")
            )
            
            statItem(
                icon: timeIcon(recommendation.suggestedTimeOfDay),
                value: recommendation.suggestedTimeOfDay.localizedTitle,
                label: L10n.localized("best time", comment: "Best time label")
            )
            
            Spacer()
        }
        .padding(DesignTokens.Spacing.sm)
        .background(DesignTokens.Colors.surfaceQuaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
    }
    
    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Text(value)
                .font(DesignTokens.Typography.caption.weight(.semibold))
            Text(label)
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textTertiary)
        }
    }
    
    private var emptyContent: some View {
        Label {
            Text(L10n.localized("No workout plan available", comment: "Empty state"))
                .font(DesignTokens.Typography.subheadline)
        } icon: {
            Image(systemName: "sparkles")
                .foregroundStyle(DesignTokens.Colors.accent)
        }
        .foregroundStyle(DesignTokens.Colors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func intentIcon(_ intent: WorkoutIntent) -> String {
        switch intent {
        case .maintain: return "equal.circle.fill"
        case .build: return "arrow.up.circle.fill"
        case .explore: return "map.circle.fill"
        case .recover: return "heart.circle.fill"
        }
    }
    
    private func intentColor(_ intent: WorkoutIntent) -> Color {
        switch intent {
        case .maintain: return DesignTokens.Colors.accent
        case .build: return DesignTokens.Colors.orange
        case .explore: return DesignTokens.Colors.green
        case .recover: return .pink
        }
    }
    
    private func timeIcon(_ time: TimeOfDay) -> String {
        switch time {
        case .morning: return "sunrise.fill"
        case .afternoon: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .anytime: return "clock.fill"
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

#Preview("Loading") {
    AIWorkoutCard(
        recommendation: nil,
        summary: nil,
        sourceTitle: nil,
        isLoading: true,
        hasLoadedRecommendation: false,
        error: nil,
        canRefresh: false,
        onRefresh: {},
        unitName: ActivityTrackingMode.steps.unitName,
        onStartWorkout: { _ in }
    )
    .padding(DesignTokens.Spacing.md)
}

#Preview("Error") {
    AIWorkoutCard(
        recommendation: nil,
        summary: nil,
        sourceTitle: nil,
        isLoading: false,
        hasLoadedRecommendation: true,
        error: .sessionNotConfigured,
        canRefresh: false,
        onRefresh: {},
        unitName: ActivityTrackingMode.steps.unitName,
        onStartWorkout: { _ in }
    )
    .padding(DesignTokens.Spacing.md)
}
