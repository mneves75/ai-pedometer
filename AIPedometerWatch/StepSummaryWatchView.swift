#if os(watchOS)
import SwiftUI

struct StepSummaryWatchView: View {
    let steps: Int
    let goal: Int
    let streak: Int
    let distanceText: String

    private var progress: Double {
        goal > 0 ? min(Double(steps) / Double(goal), 1.0) : 0
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.smPlus) {
            ZStack {
                Circle()
                    .stroke(DesignTokens.Colors.inverseStroke, lineWidth: 10)

                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [DesignTokens.Colors.mint, DesignTokens.Colors.cyan], center: .center),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: DesignTokens.Spacing.xxs) {
                    Text(steps.formattedSteps)
                        .font(DesignTokens.Typography.title2Rounded)
                        .fontWeight(.bold)
                        .monospacedDigit()
                    Text(String(localized: "steps", comment: "Watch steps unit"))
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .frame(height: 110)

            HStack {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Label(String(localized: "Distance", comment: "Watch distance label"), systemImage: "figure.walk")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text(distanceText)
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xxs) {
                    Label(String(localized: "Streak", comment: "Watch streak label"), systemImage: "flame.fill")
                        .font(DesignTokens.Typography.caption2)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                    Text(
                        Localization.format(
                            "%lld days",
                            comment: "Watch streak value in days",
                            Int64(streak)
                        )
                    )
                        .font(DesignTokens.Typography.caption.weight(.semibold))
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
    }
}

#Preview {
    StepSummaryWatchView(steps: 6540, goal: 10_000, streak: 12, distanceText: "4.2 km")
}
#endif
