import SwiftUI
import WidgetKit

struct WeeklyChartWidget: Widget {
    let kind = "WeeklyChartWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepTimelineProvider()) { entry in
            WeeklyChartWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Weekly Steps", comment: "Widget display name and header for weekly steps summary"))
        .description(String(localized: "Your recent step trend.", comment: "Widget description for weekly steps widget"))
        .supportedFamilies([.systemMedium])
    }
}

struct WeeklyChartWidgetView: View {
    let entry: WidgetStepEntry

    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)

            if let data = entry.data {
                WeeklyChartContent(data: data)
            } else {
                WeeklyChartPlaceholder()
            }
        }
    }
}

struct WeeklyChartContent: View {
    let data: WidgetStepData

    private var maxSteps: Int {
        max(data.weeklySteps.max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            HStack {
                Text(String(localized: "Weekly Steps", comment: "Widget header for weekly steps summary"))
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                Text(data.todaySteps.formattedSteps)
                    .font(DesignTokens.Typography.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }

            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xsPlus) {
                ForEach(Array(data.weeklySteps.enumerated()), id: \.offset) { index, value in
                    Capsule()
                        .fill(index == data.weeklySteps.count - 1 ? DesignTokens.Colors.mint : DesignTokens.Colors.mint.opacity(0.4))
                        .frame(width: 10, height: max(8, CGFloat(value) / CGFloat(maxSteps) * 70))
                }
            }
            .frame(maxWidth: .infinity, alignment: .bottom)

            Text(
                Localization.format(
                    "Streak %lld days",
                    comment: "Widget label for streak in days",
                    Int64(data.currentStreak)
                )
            )
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
        }
        .padding(DesignTokens.Spacing.md)
    }
}

struct WeeklyChartPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.smPlus) {
            Text(String(localized: "Weekly Steps", comment: "Widget header for weekly steps summary"))
                .font(DesignTokens.Typography.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)

            HStack(alignment: .bottom, spacing: DesignTokens.Spacing.xsPlus) {
                ForEach(0..<7, id: \.self) { _ in
                    Capsule()
                        .fill(DesignTokens.Colors.mint.opacity(0.4))
                        .frame(width: 10, height: 40)
                }
            }

            Text(
                Localization.format(
                    "Streak %lld days",
                    comment: "Widget placeholder label for streak in days",
                    Int64(10)
                )
            )
                .font(DesignTokens.Typography.caption2)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
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
