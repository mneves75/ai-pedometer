import SwiftUI

extension View {
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 20, interactive: Bool = false) -> some View {
        if LaunchConfiguration.isUITesting() {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else if #available(iOS 26, *) {
            if interactive {
                self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    func glassGroup(spacing: CGFloat = 12) -> some View {
        if LaunchConfiguration.isUITesting() {
            self
        } else if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing) {
                self
            }
        } else {
            self
        }
    }
}
