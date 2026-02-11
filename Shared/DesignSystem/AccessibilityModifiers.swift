import SwiftUI

extension View {
    func accessibleButton(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
            .accessibilityAddTraits(.isButton)
    }

    func accessibleProgress(label: String, value: Double, total: Double = 1.0) -> some View {
        let safeTotal = total > 0 ? total : 1
        let rawPercentage = (value / safeTotal) * 100
        let percentage = max(0, min(Int(rawPercentage.rounded()), 100))
        return self
            .accessibilityLabel(label)
            .accessibilityValue(
                Localization.format(
                    "%lld percent",
                    comment: "A value that indicates the percentage of a task that has been completed.",
                    Int64(percentage)
                )
            )
    }

    func accessibleCard(label: String, hint: String? = nil) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint ?? "")
    }

    func accessibleStatistic(title: String, value: String) -> some View {
        self
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Localization.format(
                    "%@: %@",
                    comment: "A pair of text elements that together describe a single piece of data. The first element is a label that describes the data. The second element is the actual data itself.",
                    title,
                    value
                )
            )
    }
}

struct AIDisclaimerText: View {
    var body: some View {
        Text(String(
            localized: "AI guidance is general fitness information and not medical advice.",
            comment: "AI disclaimer shown across AI features"
        ))
            .font(DesignTokens.Typography.caption2)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
    }
}
