import SwiftUI

// MARK: - Motion tokens

extension DesignTokens.Animation {
    /// Slow ambient cycle used by breathing/glow effects.
    static let breathDuration: Double = 2.6

    /// Celebration spring used when a goal is reached.
    static var celebration: SwiftUI.Animation {
        .spring(response: 0.45, dampingFraction: 0.55)
    }

    /// Per-item delay used by staggered entrances.
    static let staggerStep: Double = 0.06
}

// MARK: - Breathing glow

/// A soft, slowly pulsing glow around the content.
///
/// Identity-stable under Reduce Motion: the phase animator stays installed and
/// the glow amplitude collapses to a constant, so toggling the system setting
/// never resets descendant state.
private struct BreathingGlowModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let color: Color
    let isActive: Bool

    private var animatesGlow: Bool {
        isActive && !reduceMotion && !LaunchConfiguration.isUITesting()
    }

    func body(content: Content) -> some View {
        content
            .phaseAnimator([false, true]) { view, phase in
                view.shadow(
                    color: color.opacity(glowOpacity(expanded: phase)),
                    radius: glowRadius(expanded: phase)
                )
            } animation: { _ in
                animatesGlow ? .easeInOut(duration: DesignTokens.Animation.breathDuration) : nil
            }
    }

    private func glowOpacity(expanded: Bool) -> Double {
        guard isActive else { return 0 }
        guard animatesGlow else { return 0.25 }
        return expanded ? 0.45 : 0.18
    }

    private func glowRadius(expanded: Bool) -> CGFloat {
        guard isActive else { return 0 }
        guard animatesGlow else { return DesignTokens.Spacing.smPlus }
        return expanded ? DesignTokens.Spacing.mdPlus : DesignTokens.Spacing.sm
    }
}

// MARK: - Goal celebration

/// A short scale "pop" played when `trigger` flips to `true`.
///
/// Pair with `.sensoryFeedback(.success, trigger:)` at the call site for haptics.
private struct GoalCelebrationModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let trigger: Bool

    func body(content: Content) -> some View {
        content
            .phaseAnimator([false, true], trigger: trigger) { view, burst in
                view.scaleEffect(scale(burst: burst))
            } animation: { _ in
                reduceMotion ? nil : DesignTokens.Animation.celebration
            }
    }

    private func scale(burst: Bool) -> CGFloat {
        guard trigger, !reduceMotion, !LaunchConfiguration.isUITesting() else { return 1 }
        return burst ? 1.05 : 1
    }
}

// MARK: - Scroll-driven entrance

/// Standard scroll-edge treatment: content gently fades and recedes as it
/// leaves the visible area. Under Reduce Motion only opacity is applied.
private struct ScrollFadeModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let reduceMotion = self.reduceMotion
        return content.scrollTransition(.interactive) { view, phase in
            view
                .opacity(phase.isIdentity ? 1 : 0.35)
                .scaleEffect(phase.isIdentity || reduceMotion ? 1 : 0.94)
                .offset(y: phase.isIdentity || reduceMotion ? 0 : phase.value * DesignTokens.Spacing.smPlus)
        }
    }
}

// MARK: - Staggered reveal

/// Entrance used for grids/lists on first appearance: items rise and fade in,
/// one after another. Under Reduce Motion items simply appear.
private struct StaggeredRevealModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let index: Int
    let isRevealed: Bool

    private var animates: Bool {
        !reduceMotion && !LaunchConfiguration.isUITesting()
    }

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed || !animates ? 1 : 0)
            .offset(y: isRevealed || !animates ? 0 : DesignTokens.Spacing.md)
            .animation(
                animates
                    ? DesignTokens.Animation.springy.delay(Double(index) * DesignTokens.Animation.staggerStep)
                    : nil,
                value: isRevealed
            )
    }
}

// MARK: - View extensions

extension View {
    /// Soft pulsing glow behind the content while `isActive` is true.
    func breathingGlow(_ color: Color, isActive: Bool = true) -> some View {
        modifier(BreathingGlowModifier(color: color, isActive: isActive))
    }

    /// One-shot celebratory scale pop when `trigger` becomes true.
    func goalCelebration(trigger: Bool) -> some View {
        modifier(GoalCelebrationModifier(trigger: trigger))
    }

    /// Standard scroll-edge fade/scale treatment for cards in scroll views.
    func scrollFadeIn() -> some View {
        modifier(ScrollFadeModifier())
    }

    /// Staggered rise-and-fade entrance; drive `isRevealed` from `onAppear`.
    func staggeredReveal(index: Int, isRevealed: Bool) -> some View {
        modifier(StaggeredRevealModifier(index: index, isRevealed: isRevealed))
    }
}
