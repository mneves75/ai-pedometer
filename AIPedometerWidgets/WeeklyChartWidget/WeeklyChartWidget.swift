import SwiftUI
import WidgetKit

struct WeeklyChartWidget: Widget {
    let kind = "WeeklyChartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepTimelineProvider()) { entry in
            WeeklyChartWidgetView(entry: entry)
        }
        .configurationDisplayName(L10n.localized("Weekly Steps", comment: "Widget display name and header for weekly steps summary"))
        .description(L10n.localized("Your recent step trend.", comment: "Widget description for weekly steps widget"))
        .supportedFamilies([.systemMedium])
    }
}

struct WeeklyChartWidgetView: View {
    let entry: WidgetStepEntry

    var body: some View {
        Group {
            if let data = entry.data {
                WeeklyChartContent(data: data)
            } else {
                WeeklyChartPlaceholder()
            }
        }
        .containerBackground(for: .widget) {
            DesignTokens.Colors.surface
        }
    }
}

struct WeeklyChartContent: View {
    let data: SharedStepData

    private var maxSteps: Int {
        max(data.weeklySteps.max() ?? 1, 1)
    }

    private var weeklyTotal: Int {
        data.weeklySteps.reduce(0, +)
    }

    private var headerTitle: String {
        switch data.activityMode {
        case .steps: L10n.localized("Weekly Steps", comment: "Widget header for weekly steps summary")
        case .wheelchairPushes: L10n.localized("Weekly Pushes", comment: "Widget header for weekly wheelchair pushes summary")
        }
    }

    private var accessibilityTitle: String {
        switch data.activityMode {
        case .steps: L10n.localized("Weekly steps", comment: "Accessibility label for weekly steps widget")
        case .wheelchairPushes: L10n.localized("Weekly pushes", comment: "Accessibility label for weekly wheelchair pushes widget")
        }
    }

    private var accessibilitySummary: String {
        switch data.activityMode {
        case .steps:
            Localization.format(
                "%@ steps today, %@ steps this week, streak of %@",
                comment: "Accessibility value for weekly steps widget; the last argument is a pluralized day count",
                data.todaySteps.formattedSteps,
                weeklyTotal.formattedSteps,
                Localization.streakDays(data.currentStreak)
            )
        case .wheelchairPushes:
            Localization.format(
                "%@ pushes today, %@ pushes this week, streak of %@",
                comment: "Accessibility value for weekly wheelchair pushes widget; the last argument is a pluralized day count",
                data.todaySteps.formattedSteps,
                weeklyTotal.formattedSteps,
                Localization.streakDays(data.currentStreak)
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            HStack {
                Text(headerTitle)
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(data.todaySteps.formattedSteps)
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xsPlus) {
                ForEach(Array(data.weeklySteps.enumerated()), id: \.offset) { index, value in
                    Capsule()
                        .fill(index == data.weeklySteps.count - 1 ? DesignTokens.Colors.mint : DesignTokens.Colors.mint.opacity(0.4))
                        .frame(width: 10, height: max(8, CGFloat(value) / CGFloat(maxSteps) * 70))
                        .widgetAccentable()
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottom)

            Text(
                Localization.format(
                    "Streak: %@",
                    comment: "Widget label for streak length; the argument is a pluralized day count such as \"1 day\"",
                    Localization.streakDays(data.currentStreak)
                )
            )
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(DesignTokens.Spacing.md)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilitySummary)
    }
}

struct WeeklyChartPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            Text(L10n.localized("Weekly Steps", comment: "Widget header for weekly steps summary"))
                .font(DesignTokens.Typography.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xsPlus) {
                ForEach(0..<7, id: \.self) { _ in
                    Capsule()
                        .fill(DesignTokens.Colors.mint.opacity(0.4))
                        .frame(width: 10, height: 40)
                }
            }

            Text(
                Localization.format(
                    "Streak: %@",
                    comment: "Widget label for streak length; the argument is a pluralized day count such as \"1 day\"",
                    Localization.streakDays(10)
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

#Preview(as: .systemMedium) {
    WeeklyChartWidget()
} timeline: {
    WidgetStepEntry(date: .now, data: WidgetDataLoader.placeholderData())
}
