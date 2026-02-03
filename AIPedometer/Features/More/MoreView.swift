import SwiftUI

struct MoreView: View {
    @State private var showBadges = false
    @State private var showSettings = false

    var body: some View {
        List {
            Button {
                showBadges = true
            } label: {
                Label(String(localized: "Badges", comment: "More list entry for badges"), systemImage: "medal.fill")
                    .accessibilityIdentifier("more_badges_row_label")
            }
            .accessibilityIdentifier("more_badges_row")
            .accessibilityLabel(String(localized: "Badges", comment: "Accessibility label for badges entry"))
            .buttonStyle(.plain)

            Button {
                showSettings = true
            } label: {
                Label(String(localized: "Settings", comment: "More list entry for settings"), systemImage: "gearshape.fill")
                    .accessibilityIdentifier("more_settings_row_label")
            }
            .accessibilityIdentifier("more_settings_row")
            .accessibilityLabel(String(localized: "Settings", comment: "Accessibility label for settings entry"))
            .buttonStyle(.plain)
        }
        .accessibilityIdentifier("more_list")
        .navigationTitle(String(localized: "More", comment: "Title for more tab"))
        .navigationDestination(isPresented: $showBadges) {
            BadgesView()
        }
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

#Preview {
    MoreView()
}
