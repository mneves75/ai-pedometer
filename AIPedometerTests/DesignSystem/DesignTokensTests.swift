import SwiftUI
import Testing

@testable import AIPedometer

@Suite("DesignTokens Tests")
struct DesignTokensTests {
    private static let spacingScale: [(name: String, value: CGFloat)] = [
        ("xxs", DesignTokens.Spacing.xxs),
        ("xs", DesignTokens.Spacing.xs),
        ("sm", DesignTokens.Spacing.sm),
        ("md", DesignTokens.Spacing.md),
        ("lg", DesignTokens.Spacing.lg),
        ("xl", DesignTokens.Spacing.xl),
        ("xxl", DesignTokens.Spacing.xxl),
    ]

    private static let cornerRadiusScale: [(name: String, value: CGFloat)] = [
        ("xs", DesignTokens.CornerRadius.xs),
        ("sm", DesignTokens.CornerRadius.sm),
        ("md", DesignTokens.CornerRadius.md),
        ("lg", DesignTokens.CornerRadius.lg),
        ("xl", DesignTokens.CornerRadius.xl),
        ("xxl", DesignTokens.CornerRadius.xxl),
    ]

    private static let animationDurations: [(name: String, value: Double)] = [
        ("defaultDuration", DesignTokens.Animation.defaultDuration),
        ("shortDuration", DesignTokens.Animation.shortDuration),
        ("longDuration", DesignTokens.Animation.longDuration),
    ]

    @Test("Spacing scale is ascending", arguments: zip(spacingScale, spacingScale.dropFirst()))
    func spacingScaleIsAscending(smaller: (name: String, value: CGFloat), larger: (name: String, value: CGFloat)) {
        #expect(smaller.value < larger.value)
    }

    @Test("Corner radius scale is ascending", arguments: zip(cornerRadiusScale, cornerRadiusScale.dropFirst()))
    func cornerRadiusScaleIsAscending(smaller: (name: String, value: CGFloat), larger: (name: String, value: CGFloat)) {
        #expect(smaller.value < larger.value)
    }

    @Test("Animation durations within Liquid Glass range", arguments: animationDurations)
    func animationDurationsWithinLiquidGlassRange(duration: (name: String, value: Double)) {
        #expect(duration.value >= 0.2)
        #expect(duration.value <= 0.35)
    }

    @Test("Touch target meets minimum")
    func touchTargetMeetsMinimum() {
        #expect(DesignTokens.TouchTarget.minimum >= 44)
    }
}
