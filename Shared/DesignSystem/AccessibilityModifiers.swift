import SwiftUI

extension View {
    func accessibleButton(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }

    func accessibleProgress(label: String, value: Double, total: Double = 1.0, valueDescription: String? = nil) -> some View {
        let safeTotal = total.isFinite && total > 0 ? total : 1
        let ratio = ProgressClamp.unitInterval(value / safeTotal)
        let percentage = Int((ratio * 100).rounded())
        let percentageText = Localization.format(
            "%lld percent",
            comment: "A value that indicates the percentage of a task that has been completed.",
            Int64(percentage)
        )
        let accessibilityValue = if let valueDescription, !valueDescription.isEmpty {
            "\(valueDescription), \(percentageText)"
        } else {
            percentageText
        }
        return self
            .accessibilityLabel(label)
            .accessibilityValue(accessibilityValue)
    }

    func accessibleCard(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }

    func accessibleStatistic(title: String, value: String, accessibilityValue: String? = nil) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Localization.format(
                    "%@: %@",
                    comment: "A pair of text elements that together describe a single piece of data. The first element is a label that describes the data. The second element is the actual data itself.",
                    title,
                    accessibilityValue ?? value
                )
            )
    }
}

struct AIDisclaimerText: View {
    var body: some View {
        Text(L10n.localized(
            "AI guidance is general fitness information and not medical advice.",
            comment: "AI disclaimer shown across AI features"
        ))
        .font(DesignTokens.Typography.caption2)
        .foregroundStyle(DesignTokens.Colors.textTertiary)
    }
}
