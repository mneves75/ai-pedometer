import SwiftUI

extension View {
    @ViewBuilder
    func applyIfNotUITesting<Content: View>(
        _ transform: (Self) -> Content
    ) -> some View {
        if LaunchConfiguration.isUITesting() {
            self
        } else {
            transform(self)
        }
    }

    /// Adds a stable accessibility marker only when UI testing.
    ///
    /// SwiftUI containers (e.g. `VStack`, `ScrollView`) don't always surface `accessibilityIdentifier`
    /// reliably in the accessibility tree. This creates a tiny element that UI tests can assert on.
    @ViewBuilder
    func uiTestMarker(_ identifier: String) -> some View {
        if LaunchConfiguration.isUITesting() {
            overlay(alignment: .topLeading) {
                UITestMarkerView(identifier: identifier)
                    .allowsHitTesting(false)
            }
        } else {
            self
        }
    }
}

private struct UITestMarkerView: View {
    let identifier: String

    var body: some View {
        // Keep it discoverable for XCUITest without affecting layout.
        Text(identifier)
            .font(DesignTokens.Typography.caption2)
            .opacity(0.01)
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(identifier)
    }
}
