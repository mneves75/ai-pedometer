import SwiftUI
import WidgetKit

struct ProgressRingWidget: Widget {
    let kind = "ProgressRingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepTimelineProvider()) { entry in
            ProgressRingWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Goal Ring", comment: "Widget display name for goal ring widget"))
        .description(String(localized: "Your daily goal at a glance.", comment: "Widget description for goal ring widget"))
        .supportedFamilies([.systemSmall])
    }
}

struct ProgressRingWidgetView: View {
    let entry: WidgetStepEntry

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)

            if let data = entry.data {
                ProgressRingContent(data: data)
            } else {
                ProgressRingPlaceholder()
            }
        }
    }
}

struct ProgressRingContent: View {
    let data: WidgetStepData
    private var clampedProgress: Double {
        ProgressClamp.unitInterval(data.goalProgress)
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.smPlus) {
            ZStack {
                Circle()
                    .stroke(DesignTokens.Colors.inverseStroke, lineWidth: 10)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        AngularGradient(colors: [DesignTokens.Colors.mint, DesignTokens.Colors.cyan], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(data.todaySteps.formattedSteps)
                        .font(DesignTokens.Typography.headline.monospacedDigit())
                    Text(String(localized: "steps", comment: "Widget label for steps unit"))
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }

            Text(
                Localization.format(
                    "Goal %lld",
                    comment: "Widget label for daily goal",
                    Int64(data.goalSteps)
                )
            )
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.md)
    }
}

struct ProgressRingPlaceholder: View {
    var body: some View {
        VStack(spacing: DesignTokens.Spacing.smPlus) {
            Circle()
                .stroke(DesignTokens.Colors.inverseStroke, lineWidth: 10)
                .frame(width: 80, height: 80)

            Text(
                Localization.format(
                    "Goal %lld",
                    comment: "Widget placeholder label for daily goal",
                    Int64(10_000)
                )
            )
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
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
