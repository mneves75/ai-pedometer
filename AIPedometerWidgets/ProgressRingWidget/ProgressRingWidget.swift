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
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(
                        AngularGradient(colors: [.mint, .cyan], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text("\(data.todaySteps)")
                        .font(.headline.monospacedDigit())
                    Text(String(localized: "steps", comment: "Widget label for steps unit"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

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
        .padding()
    }
}

struct ProgressRingPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .stroke(.white.opacity(0.15), lineWidth: 10)
                .frame(width: 80, height: 80)

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

#Preview(as: .systemSmall) {
    ProgressRingWidget()
} timeline: {
    WidgetStepEntry(date: .now, data: WidgetDataLoader.placeholderData())
}
