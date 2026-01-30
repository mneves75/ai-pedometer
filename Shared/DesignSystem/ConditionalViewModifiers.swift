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
}
