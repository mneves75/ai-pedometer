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
        ScrollView {
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(L10n.localized("steps", comment: "Watch steps unit"))
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
                .frame(height: 110)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.localized("Daily goal progress", comment: "Accessibility label for watch daily progress ring"))
                .accessibilityValue(
                    Localization.format(
                        "%@ steps of %@ goal, %lld percent",
                        comment: "Accessibility value for watch daily progress ring",
                        steps.formatted(),
                        goal.formatted(),
                        Int64((progress * 100).rounded())
                    )
                )

                HStack {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Label(L10n.localized("Distance", comment: "Watch distance label"), systemImage: "figure.walk")
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(distanceText)
                            .font(DesignTokens.Typography.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .combine)

                    Spacer(minLength: DesignTokens.Spacing.sm)

                    VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xxs) {
                        Label(L10n.localized("Streak", comment: "Watch streak label"), systemImage: "flame.fill")
                            .font(DesignTokens.Typography.caption2)
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(
                            Localization.format(
                                "%lld days",
                                comment: "Watch streak value in days",
                                Int64(streak)
                            )
                        )
                            .font(DesignTokens.Typography.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
    }
}

#Preview {
    StepSummaryWatchView(steps: 6540, goal: 10_000, streak: 12, distanceText: "4.2 km")
}
#endif
