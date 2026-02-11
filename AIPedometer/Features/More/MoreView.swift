import SwiftUI

struct MoreView: View {
    var body: some View {
        List {
            NavigationLink {
                BadgesView()
            } label: {
                Label(String(localized: "Badges", comment: "More list entry for badges"), systemImage: "medal.fill")
                    .accessibilityIdentifier(A11yID.More.badgesRowLabel)
            }
            .accessibilityIdentifier(A11yID.More.badgesRow)
            .accessibilityLabel(String(localized: "Badges", comment: "Accessibility label for badges entry"))

            NavigationLink {
                AboutView()
            } label: {
                Label(String(localized: "Support AI Pedometer", comment: "More list entry for support"), systemImage: "cup.and.saucer.fill")
                    .accessibilityIdentifier(A11yID.More.supportRowLabel)
            }
            .accessibilityIdentifier(A11yID.More.supportRow)
            .accessibilityLabel(String(localized: "Support AI Pedometer", comment: "Accessibility label for support entry"))

            NavigationLink {
                SettingsView()
            } label: {
                Label(String(localized: "Settings", comment: "More list entry for settings"), systemImage: "gearshape.fill")
                    .accessibilityIdentifier(A11yID.More.settingsRowLabel)
            }
            .accessibilityIdentifier(A11yID.More.settingsRow)
            .accessibilityLabel(String(localized: "Settings", comment: "Accessibility label for settings entry"))
        }
        .accessibilityIdentifier(A11yID.More.list)
        .uiTestMarker(A11yID.More.marker)
        .navigationTitle(String(localized: "More", comment: "Title for more tab"))
    }
}

#Preview {
    MoreView()
}
