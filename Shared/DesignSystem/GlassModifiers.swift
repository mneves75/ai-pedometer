import SwiftUI

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    init(cornerRadius: CGFloat = DesignTokens.CornerRadius.lg, interactive: Bool = false) {
        self.cornerRadius = cornerRadius
        self.interactive = interactive
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if LaunchConfiguration.isUITesting() && !LaunchConfiguration.shouldUseProductionGlass() {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else if #available(iOS 26, *) {
            if interactive {
                content
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

struct GlassButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if LaunchConfiguration.isUITesting() && !LaunchConfiguration.shouldUseProductionGlass() {
            content
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
        } else if #available(iOS 26, *) {
            content
                .buttonStyle(.glassProminent)
                .foregroundStyle(.black)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .foregroundStyle(.black)
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = DesignTokens.CornerRadius.lg, interactive: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    func glassButton() -> some View {
        modifier(GlassButtonModifier())
    }

    @ViewBuilder
    func glassContainer(spacing: CGFloat = DesignTokens.Spacing.md) -> some View {
        if LaunchConfiguration.isUITesting() && !LaunchConfiguration.shouldUseProductionGlass() {
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
