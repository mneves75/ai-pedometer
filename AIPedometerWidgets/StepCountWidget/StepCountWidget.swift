import SwiftUI
import WidgetKit

struct StepCountWidget: Widget {
    let kind = "StepCountWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StepTimelineProvider()) { entry in
            StepCountWidgetView(entry: entry)
        }
        .configurationDisplayName(String(localized: "Steps Today", comment: "Widget display name for steps today widget"))
        .description(String(localized: "Track your daily step progress.", comment: "Widget description for the steps today widget"))
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

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(String(localized: "Steps", comment: "Widget label for steps"), systemImage: "figure.walk")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(ProgressClamp.percent(data.goalProgress))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.mint)
                    }

                    Text("\(data.todaySteps)")
                        .font(.system(size: geometry.size.height > 140 ? 36 : 30, weight: .heavy, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()

                    ProgressView(value: clampedProgress)
                        .tint(.mint)

                    HStack {
                        Label(String(localized: "Streak", comment: "Widget label for streak"), systemImage: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(
                            Localization.format(
                                "%lld days",
                                comment: "Widget value for streak in days",
                                Int64(data.currentStreak)
                            )
                        )
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(
                            Localization.format(
                                "Goal %lld",
                                comment: "Widget label for daily goal",
                                Int64(data.goalSteps)
                            )
                        )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
        }
    }

}

struct StepCountPlaceholderView: View {
    var body: some View {
        ZStack {
            ContainerRelativeShape()
                .fill(.ultraThinMaterial)
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Steps", comment: "Widget placeholder label for steps"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("8,888")
                    .font(.system(size: 32, weight: .heavy, design: .rounded))

                ProgressView(value: 0.6)
                    .tint(.mint)

                Text(
                    Localization.format(
                        "Goal %lld",
                        comment: "Widget placeholder label for daily goal",
                        Int64(10_000)
                    )
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .redacted(reason: .placeholder)
        }
    }
}

#Preview(as: .systemSmall) {
    StepCountWidget()
} timeline: {
    WidgetStepEntry(date: .now, data: WidgetDataLoader.placeholderData())
}
