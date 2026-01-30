#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(state: context.state, workoutType: context.attributes.workoutType)
                .activityBackgroundTint(Color.black.opacity(0.4))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.workoutType, systemImage: "figure.run")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(distanceText(context.state.distance))
                        .font(.callout.monospacedDigit().weight(.bold))
                        .foregroundStyle(.cyan)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("\(context.state.steps)")
                        .font(.title2.monospacedDigit().weight(.heavy))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 24) {
                        LiveStatView(value: "\(Int(context.state.calories))", label: LiveActivityUnits.calories, icon: "flame.fill", tint: .orange)
                        LiveStatView(value: distanceText(context.state.distance), label: LiveActivityUnits.distance, icon: "figure.walk", tint: .mint)
                    }
                    .padding(.top, 8)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                Text("\(context.state.steps)")
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "shoe.fill")
                    .foregroundStyle(.cyan)
            }
            .keylineTint(.cyan)
        }
    }

    private func distanceText(_ distance: Double) -> String {
        distance.formatted(.number.precision(.fractionLength(2)))
    }
}

struct LockScreenWorkoutView: View {
    let state: WorkoutActivityAttributes.ContentState
    let workoutType: String

    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(workoutType.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)

                Text("\(state.steps)")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)

                Text(LiveActivityUnits.steps)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.cyan)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                LiveStatView(value: distanceText(state.distance), label: LiveActivityUnits.distance, icon: "map.fill", tint: .mint)
                LiveStatView(value: "\(Int(state.calories))", label: LiveActivityUnits.calories, icon: "flame.fill", tint: .orange)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func distanceText(_ distance: Double) -> String {
        distance.formatted(.number.precision(.fractionLength(2)))
    }
}

private enum LiveActivityUnits {
    static var steps: String {
        String(localized: "steps", comment: "Live Activity steps unit").uppercased()
    }

    static var distance: String {
        String(localized: "km", comment: "Live Activity distance unit").uppercased()
    }

    static var calories: String {
        String(localized: "kcal", comment: "Live Activity calories unit").uppercased()
    }
}

struct LiveStatView: View {
    let value: String
    let label: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.white)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
#endif
