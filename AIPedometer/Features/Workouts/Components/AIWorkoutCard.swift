import SwiftUI

struct AIWorkoutCard: View {
    let recommendation: AIWorkoutRecommendation?
    let isLoading: Bool
    let error: AIServiceError?
    var onRefresh: () -> Void
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
            } else {
                emptyContent
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.lg))
        .animation(DesignTokens.Animation.smooth, value: isLoading)
    }
    
    private var header: some View {
        HStack {
            Label {
                Text(String(localized: "Today's Plan", comment: "AI workout card header"))
                    .font(.headline)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            }
            
            Spacer()
            
            if recommendation != nil && !isLoading {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var loadingContent: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            
            Text(String(localized: "Generating plan...", comment: "AI workout loading state"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }
    
    private func errorContent(_ error: AIServiceError) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Label {
                Text(error.localizedDescription)
                    .font(.subheadline)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            
            Button(action: onRefresh) {
                Text(String(localized: "Try Again", comment: "Retry button"))
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .foregroundStyle(.secondary)
    }
    
    private func recommendationContent(_ recommendation: AIWorkoutRecommendation) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            intentBadge(recommendation.intent)
            
            Text(recommendation.rationale)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            statsRow(recommendation)
            
            Button {
                HapticService.shared.confirm()
                onStartWorkout(recommendation)
            } label: {
                HStack {
                    Image(systemName: "figure.walk")
                    Text(String(localized: "Start This Workout", comment: "Start workout button"))
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(DesignTokens.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
        }
    }
    
    private func intentBadge(_ intent: WorkoutIntent) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: intentIcon(intent))
                .font(.title3)
                .foregroundStyle(intentColor(intent))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(intent.localizedTitle)
                    .font(.subheadline.weight(.semibold))
                Text(intent.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func statsRow(_ recommendation: AIWorkoutRecommendation) -> some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            statItem(
                icon: "figure.walk",
                value: recommendation.targetSteps.formatted(),
                label: String(localized: "steps", comment: "Steps unit")
            )
            
            statItem(
                icon: "clock",
                value: "\(recommendation.estimatedMinutes)",
                label: String(localized: "min", comment: "Minutes abbreviation")
            )
            
            statItem(
                icon: timeIcon(recommendation.suggestedTimeOfDay),
                value: recommendation.suggestedTimeOfDay.localizedTitle,
                label: String(localized: "best time", comment: "Best time label")
            )
            
            Spacer()
        }
        .padding(DesignTokens.Spacing.sm)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.sm))
    }
    
    private func statItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
    
    private var emptyContent: some View {
        Text(String(localized: "No workout plan available", comment: "Empty state"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
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
        case .maintain: return .blue
        case .build: return .orange
        case .explore: return .green
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
        isLoading: false,
        error: nil,
        onRefresh: {},
        onStartWorkout: { _ in }
    )
    .padding()
}

#Preview("Loading") {
    AIWorkoutCard(
        recommendation: nil,
        isLoading: true,
        error: nil,
        onRefresh: {},
        onStartWorkout: { _ in }
    )
    .padding()
}

#Preview("Error") {
    AIWorkoutCard(
        recommendation: nil,
        isLoading: false,
        error: .sessionNotConfigured,
        onRefresh: {},
        onStartWorkout: { _ in }
    )
    .padding()
}
