import SwiftUI

struct MoreView: View {
    var body: some View {
        List {
            NavigationLink {
                BadgesView()
            } label: {
                Label(String(localized: "Badges", comment: "More list entry for badges"), systemImage: "medal.fill")
                    .accessibilityIdentifier("more_badges_row_label")
            }
            .accessibilityIdentifier("more_badges_row")
            .accessibilityElement(children: .combine)

            NavigationLink {
                SettingsView()
            } label: {
                Label(String(localized: "Settings", comment: "More list entry for settings"), systemImage: "gearshape.fill")
                    .accessibilityIdentifier("more_settings_row_label")
            }
            .accessibilityIdentifier("more_settings_row")
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("more_list")
        .navigationTitle(String(localized: "More", comment: "Title for more tab"))
    }
}

#Preview {
    MoreView()
}
