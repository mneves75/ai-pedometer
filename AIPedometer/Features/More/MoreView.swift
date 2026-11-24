import SwiftUI

struct MoreView: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    BadgesView()
                } label: {
                    MoreMenuRow(
                        title: L10n.localized("Badges", comment: "More list entry for badges"),
                        symbol: "medal.fill",
                        tint: DesignTokens.Colors.orange
                    )
                    .accessibilityIdentifier(A11yID.More.badgesRowLabel)
                }
                .accessibilityIdentifier(A11yID.More.badgesRow)
                .accessibilityLabel(L10n.localized("Badges", comment: "Accessibility label for badges entry"))

                NavigationLink {
                    AboutView()
                } label: {
                    MoreMenuRow(
                        title: L10n.localized("Support AI Pedometer", comment: "More list entry for support"),
                        symbol: "cup.and.saucer.fill",
                        tint: DesignTokens.Colors.brown
                    )
                    .accessibilityIdentifier(A11yID.More.supportRowLabel)
                }
                .accessibilityIdentifier(A11yID.More.supportRow)
                .accessibilityLabel(L10n.localized("Support AI Pedometer", comment: "Accessibility label for support entry"))

                NavigationLink {
                    SettingsView()
                } label: {
                    MoreMenuRow(
                        title: L10n.localized("Settings", comment: "More list entry for settings"),
                        symbol: "gearshape.fill",
                        tint: DesignTokens.Colors.accent
                    )
                    .accessibilityIdentifier(A11yID.More.settingsRowLabel)
                }
                .accessibilityIdentifier(A11yID.More.settingsRow)
                .accessibilityLabel(L10n.localized("Settings", comment: "Accessibility label for settings entry"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AmbientZenithBackground())
        .accessibilityIdentifier(A11yID.More.list)
        .uiTestMarker(A11yID.More.marker)
        .navigationTitle(L10n.localized("More", comment: "Title for more tab"))
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct MoreMenuRow: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(
                    tint.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.xs, style: .continuous)
                )
                .accessibilityHidden(true)

            Text(title)
                .font(DesignTokens.Typography.body.weight(.medium))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
        }
        .padding(.vertical, DesignTokens.Spacing.xxs)
    }
}

#Preview {
    MoreView()
}
