import SwiftUI
import WidgetKit

struct ProgressRingWidget: Widget {
    let kind = "ProgressRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepTimelineProvider()) { entry in
            ProgressRingWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.localized("Goal Ring", comment: "Widget display name for goal ring widget"))
        .description(L10n.localized("Your daily goal at a glance.", comment: "Widget description for goal ring widget"))
        .supportedFamilies([.systemSmall])
    }
}

struct ProgressRingWidgetView: View {
    let entry: WidgetStepEntry

    var body: some View {
        Group {
            if let data = entry.data {
                ProgressRingContent(data: data)
            } else {
                ProgressRingPlaceholder()
            }
        }
        .containerBackground(for: .widget) {
            DesignTokens.Colors.surface
        }
    }
}

struct ProgressRingContent: View {
    let data: SharedStepData
    private var clampedProgress: Double {
        ProgressClamp.unitInterval(data.goalProgress)
    }

    private var progressAccessibilityValue: String {
        data.activityMode.progressAccessibilityValue(
            count: data.todaySteps,
            goal: data.goalSteps,
            percent: Int((clampedProgress * 100).rounded())
        )
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.smPlus) {
            ZStack {
                Circle()
                    .stroke(DesignTokens.Colors.textQuaternary, lineWidth: 10)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        AngularGradient(colors: [DesignTokens.Colors.mint, DesignTokens.Colors.cyan], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()

                VStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(data.todaySteps.formattedSteps)
                        .font(DesignTokens.Typography.headline.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    Text(data.activityMode.unitName)
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            Text(
                Localization.format(
                    "Goal %@",
                    comment: "Widget label for daily goal",
                    data.goalSteps.formattedSteps
                )
            )
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(DesignTokens.Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.localized("Daily goal progress", comment: "Accessibility label for the goal ring widget"))
        .accessibilityValue(progressAccessibilityValue)
    }
}

struct ProgressRingPlaceholder: View {
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.smPlus) {
            Circle()
                .stroke(DesignTokens.Colors.textQuaternary, lineWidth: 10)
                .frame(width: 80, height: 80)

            Text(
                Localization.format(
                    "Goal %@",
                    comment: "Widget placeholder label for daily goal",
                    10_000.formattedSteps
                )
            )
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(DesignTokens.Spacing.md)
        .redacted(reason: .placeholder)
    }
}

#Preview(as: .systemSmall) {
    ProgressRingWidget()
} timeline: {
    WidgetStepEntry(date: .now, data: WidgetDataLoader.placeholderData())
}
