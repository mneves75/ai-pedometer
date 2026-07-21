import SwiftUI

extension View {
    @ViewBuilder
    func tabBarAwareScrollContentBottomInset(_ spacing: CGFloat = DesignTokens.Spacing.lg) -> some View {
#if os(iOS)
        self.safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: spacing)
                .accessibilityHidden(true)
        }
#else
        self.padding(.bottom, spacing)
#endif
    }
}
