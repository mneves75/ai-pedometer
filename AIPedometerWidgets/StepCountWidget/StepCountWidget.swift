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
        .containerBackground(for: .widget) {
            DesignTokens.Colors.surface
        }
    }
}

struct StepCountContentView: View {
    let data: SharedStepData

    private var clampedProgress: Double {
        ProgressClamp.unitInterval(data.goalProgress)
    }

    private var countLabel: String {
        switch data.activityMode {
        case .steps:
            L10n.localized("Steps", comment: "Widget label for steps")
        case .wheelchairPushes:
            // No capitalized catalog entry exists for pushes; the localized unit name is capitalized instead.
            data.activityMode.unitName.localizedCapitalized
        }
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
                HStack {
                    Label(countLabel, systemImage: data.activityMode.iconName)
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    Text("\(ProgressClamp.percent(data.goalProgress))%")
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.mint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Text(data.todaySteps.formattedSteps)
                    .font(.system(size: geometry.size.height > 140 ? DesignTokens.FontSize.widgetLg : DesignTokens.FontSize.widgetSm, weight: .heavy, design: .rounded))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .widgetAccentable()

                ProgressView(value: clampedProgress)
                    .tint(DesignTokens.Colors.mint)
                    .widgetAccentable()

                HStack {
                    Label(L10n.localized("Streak", comment: "Widget label for streak"), systemImage: "flame.fill")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(Localization.streakDays(data.currentStreak))
                        .font(DesignTokens.Typography.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Spacer()

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
            }
            .padding(DesignTokens.Spacing.md)
        }
    }

}

struct StepCountPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            Text(L10n.localized("Steps", comment: "Widget placeholder label for steps"))
                .font(DesignTokens.Typography.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(8888.formattedSteps)
                .font(.system(size: DesignTokens.FontSize.widgetMd, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            ProgressView(value: 0.6)
                .tint(DesignTokens.Colors.mint)

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
    StepCountWidget()
} timeline: {
    WidgetStepEntry(date: .now, data: WidgetDataLoader.placeholderData())
}
