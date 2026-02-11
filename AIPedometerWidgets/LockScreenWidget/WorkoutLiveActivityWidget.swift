#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenWorkoutView(state: context.state, workoutType: context.attributes.workoutType)
                .activityBackgroundTint(DesignTokens.Colors.overlayDark)
                .activitySystemActionForegroundColor(DesignTokens.Colors.inverseText)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.attributes.workoutType, systemImage: "figure.run")
                        .font(DesignTokens.Typography.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(distanceText(context.state.distance))
                        .font(DesignTokens.Typography.callout.monospacedDigit().weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.cyan)
                }

                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.steps.formattedSteps)
                        .font(DesignTokens.Typography.title2.monospacedDigit().weight(.heavy))
                        .foregroundStyle(DesignTokens.Colors.inverseText)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: DesignTokens.Spacing.lg) {
                        LiveStatView(value: "\(Int(context.state.calories))", label: LiveActivityUnits.calories, icon: "flame.fill", tint: DesignTokens.Colors.orange)
                        LiveStatView(value: distanceText(context.state.distance), label: LiveActivityUnits.distance, icon: "figure.walk", tint: DesignTokens.Colors.mint)
                    }
                    .padding(.top, DesignTokens.Spacing.sm)
                }
            } compactLeading: {
                Image(systemName: "figure.run")
                    .foregroundStyle(DesignTokens.Colors.cyan)
            } compactTrailing: {
                Text(context.state.steps.formattedSteps)
                    .font(DesignTokens.Typography.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.inverseText)
            } minimal: {
                Image(systemName: "shoe.fill")
                    .foregroundStyle(DesignTokens.Colors.cyan)
            }
            .keylineTint(DesignTokens.Colors.cyan)
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
        HStack(spacing: DesignTokens.Spacing.mdPlus) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(workoutType.uppercased())
                    .font(DesignTokens.Typography.caption.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Text(state.steps.formattedSteps)
                    .font(.system(size: DesignTokens.FontSize.xs, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Colors.inverseText)

                Text(LiveActivityUnits.steps)
                    .font(DesignTokens.Typography.caption2.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.cyan)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: DesignTokens.Spacing.sm) {
                LiveStatView(value: distanceText(state.distance), label: LiveActivityUnits.distance, icon: "map.fill", tint: DesignTokens.Colors.mint)
                LiveStatView(value: "\(Int(state.calories))", label: LiveActivityUnits.calories, icon: "flame.fill", tint: DesignTokens.Colors.orange)
            }
        }
        .padding(DesignTokens.Spacing.lg)
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
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(value)
                    .font(DesignTokens.Typography.headline.monospacedDigit())
                    .foregroundStyle(DesignTokens.Colors.inverseText)
                Text(label)
                    .font(DesignTokens.Typography.caption2.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
    }
}
#endif
