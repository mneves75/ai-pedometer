import SwiftUI

struct GlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool

    init(cornerRadius: CGFloat = DesignTokens.CornerRadius.xl, interactive: Bool = false) {
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

/// Calm, elevated content surface for dense or scannable data cards.
/// Reserving Liquid Glass for interactive controls, floating chrome, and focal accents
/// keeps content crisp and effortless to scan under iOS 26+ HIG.
struct CalmSurfaceCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    init(cornerRadius: CGFloat = DesignTokens.CornerRadius.xl) {
        self.cornerRadius = cornerRadius
    }

    func body(content: Content) -> some View {
        content
            .background(
                DesignTokens.Colors.surfaceElevated,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(DesignTokens.Colors.borderMuted.opacity(0.45), lineWidth: 0.75)
            }
    }
}

struct GlassButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if LaunchConfiguration.isUITesting() && !LaunchConfiguration.shouldUseProductionGlass() {
            content
                .buttonStyle(.borderedProminent)
                .foregroundStyle(DesignTokens.Colors.onAccent)
        } else if #available(iOS 26, *) {
            content
                .buttonStyle(.glassProminent)
                .foregroundStyle(DesignTokens.Colors.onAccent)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .foregroundStyle(DesignTokens.Colors.onAccent)
        }
    }
}

struct GlassSecondaryButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if LaunchConfiguration.isUITesting() && !LaunchConfiguration.shouldUseProductionGlass() {
            content
                .buttonStyle(.bordered)
                .tint(DesignTokens.Colors.textPrimary)
        } else if #available(iOS 26, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.bordered)
                .tint(DesignTokens.Colors.textPrimary)
        }
    }
}

/// Subtle top-zenith ambient wash that gives Liquid Glass surfaces gentle depth and light to refract
/// without reducing text contrast in Light or Dark Mode.
struct AmbientZenithBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var tint: Color = DesignTokens.Colors.accent

    var body: some View {
        ZStack(alignment: .top) {
            DesignTokens.Colors.surfaceGrouped
                .ignoresSafeArea()

            RadialGradient(
                colors: [
                    tint.opacity(colorScheme == .dark ? 0.10 : 0.06),
                    tint.opacity(colorScheme == .dark ? 0.03 : 0.015),
                    Color.clear
                ],
                center: .top,
                startRadius: 12,
                endRadius: 220
            )
            .frame(height: 220)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = DesignTokens.CornerRadius.xl, interactive: Bool = false) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, interactive: interactive))
    }

    func calmCard(cornerRadius: CGFloat = DesignTokens.CornerRadius.xl) -> some View {
        modifier(CalmSurfaceCardModifier(cornerRadius: cornerRadius))
    }

    func glassButton() -> some View {
        modifier(GlassButtonModifier())
    }

    func glassSecondaryButton() -> some View {
        modifier(GlassSecondaryButtonModifier())
    }

    @ViewBuilder
    func glassCapsuleSurface(interactive: Bool = true, tinted: Bool = false) -> some View {
        if LaunchConfiguration.isUITesting() && !LaunchConfiguration.shouldUseProductionGlass() {
            self.background(
                tinted ? AnyShapeStyle(DesignTokens.Colors.accentSoft) : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
        } else if #available(iOS 26, *) {
            if tinted && interactive {
                self.glassEffect(.regular.tint(DesignTokens.Colors.accent.opacity(0.22)).interactive(), in: .capsule)
            } else if tinted {
                self.glassEffect(.regular.tint(DesignTokens.Colors.accent.opacity(0.22)), in: .capsule)
            } else if interactive {
                self.glassEffect(.regular.interactive(), in: .capsule)
            } else {
                self.glassEffect(.regular, in: .capsule)
            }
        } else {
            self.background(
                tinted ? AnyShapeStyle(DesignTokens.Colors.accentSoft) : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
        }
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
