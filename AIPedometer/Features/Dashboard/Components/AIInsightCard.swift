import SwiftUI

struct AIInsightCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let insight: DailyInsight?
    let isLoading: Bool
    let error: AIServiceError?
    var onRefresh: () -> Void
    var onRetry: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
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
        .padding(DesignTokens.Spacing.mdPlus)
        .calmCard()
        .motionAwareAnimation(DesignTokens.Animation.smooth, value: isExpanded)
        .motionAwareAnimation(DesignTokens.Animation.smooth, value: isLoading)
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "sparkles")
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.accent)
                .accessibilityHidden(true)

            Text(L10n.localized("AI Insight", comment: "AI insight card header"))
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Spacer()

            if insight != nil && !isLoading {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(DesignTokens.Typography.footnote.weight(.medium))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .frame(width: DesignTokens.IconSize.touchTarget, height: DesignTokens.IconSize.touchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.localized("Refresh AI insight", comment: "Accessibility label for AI insight refresh button"))
                .accessibilityHint(L10n.localized("Generates a new daily insight", comment: "Accessibility hint for AI insight refresh button"))
            }
        }
    }

    private var loadingContent: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ProgressView()
                .controlSize(.small)

            Text(L10n.localized("Generating insight...", comment: "AI insight loading state"))
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

            Button(L10n.localized("Try Again", comment: "Retry button"), action: onRetry)
                .glassSecondaryButton()
                .controlSize(.small)
        }
    }

    private func insightContent(_ insight: DailyInsight) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            Text(insight.highlight)
                .font(DesignTokens.Typography.callout.weight(.medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if isExpanded {
                expandedContent(insight)
            }

            expandButton
        }
    }

    private func expandedContent(_ insight: DailyInsight) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Divider()

            Text(insight.greeting)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "lightbulb.fill")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.accent)
                        .accessibilityHidden(true)
                    Text(L10n.localized("Suggestion", comment: "AI suggestion section header"))
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.accent)
                }

                Text(insight.suggestion)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "flame.fill")
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.orange)
                        .accessibilityHidden(true)
                    Text(L10n.localized("Keep Going", comment: "AI encouragement section header"))
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.orange)
                }

                Text(insight.encouragement)
                    .font(DesignTokens.Typography.subheadline)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }

            AIDisclaimerText()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var expandButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : DesignTokens.Animation.smooth) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Text(isExpanded
                    ? L10n.localized("Show Less", comment: "Collapse content button")
                    : L10n.localized("Show More", comment: "Expand content button"))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .accessibilityHidden(true)
            }
            .font(DesignTokens.Typography.caption.weight(.semibold))
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .buttonStyle(.plain)
    }

    private var emptyContent: some View {
        Text(L10n.localized("No insight available yet", comment: "AI insight empty state"))
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WeeklyTrendCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let analysis: WeeklyTrendAnalysis?
    let isLoading: Bool
    let error: AIServiceError?
    var onRetry: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            header

            if let error {
                errorContent(error)
            } else if isLoading {
                loadingContent
            } else if let analysis {
                analysisContent(analysis)
            } else {
                emptyWeeklyContent
            }
        }
        .padding(DesignTokens.Spacing.mdPlus)
        .calmCard()
        .motionAwareAnimation(DesignTokens.Animation.smooth, value: isExpanded)
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.accent)
                .accessibilityHidden(true)

            Text(L10n.localized("Weekly Trend", comment: "Weekly trend card header"))
                .font(DesignTokens.Typography.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            Spacer()
        }
    }

    private var loadingContent: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            ProgressView()
                .controlSize(.small)

            Text(L10n.localized("Analyzing week...", comment: "Weekly trend loading state"))
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorContent(_ error: AIServiceError) -> some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Text(error.localizedDescription)
                .font(DesignTokens.Typography.subheadline)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            Spacer()
            Button(L10n.localized("Try Again", comment: "Retry button"), action: onRetry)
                .glassSecondaryButton()
                .controlSize(.small)
        }
    }

    private func analysisContent(_ analysis: WeeklyTrendAnalysis) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                trendIcon(for: analysis.trend)
                    .accessibilityHidden(true)

                Text(analysis.summary)
                    .font(DesignTokens.Typography.callout.weight(.medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Divider()

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Text(L10n.localized("Observation", comment: "Weekly trend observation section"))
                            .font(DesignTokens.Typography.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)

                        Text(analysis.observation)
                            .font(DesignTokens.Typography.subheadline)
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }

                    if !analysis.recommendation.isEmpty {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text(L10n.localized("Recommendation", comment: "Weekly trend recommendation section"))
                                .font(DesignTokens.Typography.caption.weight(.semibold))
                                .foregroundStyle(DesignTokens.Colors.accent)

                            Text(analysis.recommendation)
                                .font(DesignTokens.Typography.subheadline)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                        }
                    }

                    AIDisclaimerText()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                withAnimation(reduceMotion ? nil : DesignTokens.Animation.smooth) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Text(isExpanded
                        ? L10n.localized("Show Less", comment: "Collapse content button")
                        : L10n.localized("Show More", comment: "Expand content button"))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .accessibilityHidden(true)
                }
                .font(DesignTokens.Typography.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyWeeklyContent: some View {
        Text(L10n.localized("No insight available yet", comment: "AI insight empty state"))
            .font(DesignTokens.Typography.subheadline)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendIcon(for trend: TrendDirection) -> some View {
        Group {
            switch trend {
            case .increasing:
                Image(systemName: "arrow.up.right.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.success)
            case .decreasing:
                Image(systemName: "arrow.down.right.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.warning)
            case .stable:
                Image(systemName: "arrow.right.circle.fill")
                    .foregroundStyle(DesignTokens.Colors.accent)
            }
        }
        .font(DesignTokens.Typography.title3)
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
    .padding(DesignTokens.Spacing.md)
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
    .padding(DesignTokens.Spacing.md)
}
