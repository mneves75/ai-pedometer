import SwiftUI
import WidgetKit

struct StepCountWidget: Widget {
    let kind = "StepCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepTimelineProvider()) { entry in
            StepCountWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.localized("Steps Today", comment: "Widget display name for steps today widget"))
        .description(L10n.localized("Track your daily step progress.", comment: "Widget description for the steps today widget"))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StepCountWidgetView: View {
    let entry: WidgetStepEntry

    var body: some View {
        Group {
            if let data = entry.data {
                StepCountContentView(data: data)
            } else {
                StepCountPlaceholderView()
            }
        }
    }
}

struct StepCountContentView: View {
    let data: WidgetStepData

    private var clampedProgress: Double {
        ProgressClamp.unitInterval(data.goalProgress)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ContainerRelativeShape()
                    .fill(.ultraThinMaterial)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
                    HStack {
                        Label(L10n.localized("Steps", comment: "Widget label for steps"), systemImage: "figure.walk")
                            .font(DesignTokens.Typography.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)

                        Spacer()

                        Text("\(ProgressClamp.percent(data.goalProgress))%")
                            .font(DesignTokens.Typography.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.mint)
                    }

                    Text(data.todaySteps.formattedSteps)
                        .font(.system(size: geometry.size.height > 140 ? DesignTokens.FontSize.widgetLg : DesignTokens.FontSize.widgetSm, weight: .heavy, design: .rounded))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .monospacedDigit()

                    ProgressView(value: clampedProgress)
                        .tint(DesignTokens.Colors.mint)

                    HStack {
                        Label(L10n.localized("Streak", comment: "Widget label for streak"), systemImage: "flame.fill")
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)

                        Text(
                            Localization.format(
                                "%lld days",
                                comment: "Widget value for streak in days",
                                Int64(data.currentStreak)
                            )
                        )
                            .font(DesignTokens.Typography.caption2.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)

                        Spacer()

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
                }
                .padding(DesignTokens.Spacing.md)
            }
        }
    }

}

struct StepCountPlaceholderView: View {
    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
                Text(L10n.localized("Steps", comment: "Widget placeholder label for steps"))
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Text(8888.formattedSteps)
                    .font(.system(size: DesignTokens.FontSize.widgetMd, weight: .heavy, design: .rounded))

                ProgressView(value: 0.6)
                    .tint(DesignTokens.Colors.mint)

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
}

#Preview(as: .systemSmall) {
    StepCountWidget()
} timeline: {
    WidgetStepEntry(date: .now, data: WidgetDataLoader.placeholderData())
}
