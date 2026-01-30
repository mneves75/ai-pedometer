import SwiftUI

struct AIInsightCard: View {
    let insight: DailyInsight?
    let isLoading: Bool
    let error: AIServiceError?
    var onRefresh: () -> Void
    var onRetry: () -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            header
            
            if let error {
                errorContent(error)
            } else if isLoading {
                loadingContent
            } else if let insight {
                insightContent(insight)
            } else {
                emptyContent
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.lg))
        .animation(DesignTokens.Animation.smooth, value: isExpanded)
        .animation(DesignTokens.Animation.smooth, value: isLoading)
    }
    
    private var header: some View {
        HStack {
            Label {
                Text(String(localized: "AI Insight", comment: "AI insight card header"))
                    .font(.headline)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            }
            
            Spacer()
            
            if insight != nil && !isLoading {
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
            
            Text(String(localized: "Generating insight...", comment: "AI insight loading state"))
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
            
            Button(action: onRetry) {
                Text(String(localized: "Try Again", comment: "Retry button"))
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .foregroundStyle(.secondary)
    }
    
    private func insightContent(_ insight: DailyInsight) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text(insight.greeting)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            highlightView(insight.highlight)
            
            if isExpanded {
                expandedContent(insight)
            }
            
            expandButton
        }
    }
    
    private func highlightView(_ highlight: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            
            Text(highlight)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private func expandedContent(_ insight: DailyInsight) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Divider()
            
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Label(String(localized: "Suggestion", comment: "AI suggestion section header"), systemImage: "lightbulb.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                
                Text(insight.suggestion)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Label(String(localized: "Keep Going", comment: "AI encouragement section header"), systemImage: "flame.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                
                Text(insight.encouragement)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
    
    private var expandButton: some View {
        Button {
            withAnimation(DesignTokens.Animation.smooth) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Text(isExpanded
                    ? String(localized: "Show Less", comment: "Collapse content button")
                    : String(localized: "Show More", comment: "Expand content button"))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }
    
    private var emptyContent: some View {
        Text(String(localized: "No insight available yet", comment: "AI insight empty state"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WeeklyTrendCard: View {
    let analysis: WeeklyTrendAnalysis?
    let isLoading: Bool
    let error: AIServiceError?
    var onRetry: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            header
            
            if let error {
                errorContent(error)
            } else if isLoading {
                loadingContent
            } else if let analysis {
                analysisContent(analysis)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.lg))
    }
    
    private var header: some View {
        HStack {
            Label {
                Text(String(localized: "Weekly Trend", comment: "Weekly trend card header"))
                    .font(.headline)
            } icon: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.blue)
            }
            
            Spacer()
        }
    }
    
    private var loadingContent: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            
            Text(String(localized: "Analyzing week...", comment: "Weekly trend loading state"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func errorContent(_ error: AIServiceError) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            Button(String(localized: "Try Again", comment: "Retry button"), action: onRetry)
                .font(.subheadline.weight(.medium))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private func analysisContent(_ analysis: WeeklyTrendAnalysis) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                trendIcon(for: analysis.trend)
                
                Text(analysis.summary)
                    .font(.subheadline)
            }
            
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(String(localized: "Observation", comment: "Weekly trend observation section"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Text(analysis.observation)
                    .font(.subheadline)
            }
            
            if !analysis.recommendation.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text(String(localized: "Recommendation", comment: "Weekly trend recommendation section"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.blue)
                    
                    Text(analysis.recommendation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func trendIcon(for trend: TrendDirection) -> some View {
        Group {
            switch trend {
            case .increasing:
                Image(systemName: "arrow.up.right.circle.fill")
                    .foregroundStyle(.green)
            case .decreasing:
                Image(systemName: "arrow.down.right.circle.fill")
                    .foregroundStyle(.orange)
            case .stable:
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .font(.title2)
    }
}

#Preview("With Insight") {
    AIInsightCard(
        insight: DailyInsight(
            greeting: "Great progress today!",
            highlight: "You've walked 8,500 steps - that's 85% of your goal!",
            suggestion: "A quick 15-minute walk would help you reach your goal.",
            encouragement: "You're building great habits. Keep it up!"
        ),
        isLoading: false,
        error: nil,
        onRefresh: {},
        onRetry: {}
    )
    .padding()
}

#Preview("Loading") {
    AIInsightCard(
        insight: nil,
        isLoading: true,
        error: nil,
        onRefresh: {},
        onRetry: {}
    )
    .padding()
}

#Preview("Error") {
    AIInsightCard(
        insight: nil,
        isLoading: false,
        error: .sessionNotConfigured,
        onRefresh: {},
        onRetry: {}
    )
    .padding()
}

#Preview("Weekly Trend") {
    WeeklyTrendCard(
        analysis: WeeklyTrendAnalysis(
            summary: "Your activity increased 12% compared to last week.",
            trend: .increasing,
            observation: "You're most active on Tuesdays and Thursdays.",
            recommendation: "Try to maintain this momentum through the weekend."
        ),
        isLoading: false,
        error: nil,
        onRetry: {}
    )
    .padding()
}
