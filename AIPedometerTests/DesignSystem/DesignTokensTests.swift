import XCTest
import SwiftUI

@testable import AIPedometer

final class DesignTokensTests: XCTestCase {
    func testSpacingScaleIsAscending() {
        XCTAssertLessThan(DesignTokens.Spacing.xxs, DesignTokens.Spacing.xs)
        XCTAssertLessThan(DesignTokens.Spacing.xs, DesignTokens.Spacing.sm)
        XCTAssertLessThan(DesignTokens.Spacing.sm, DesignTokens.Spacing.md)
        XCTAssertLessThan(DesignTokens.Spacing.md, DesignTokens.Spacing.lg)
        XCTAssertLessThan(DesignTokens.Spacing.lg, DesignTokens.Spacing.xl)
        XCTAssertLessThan(DesignTokens.Spacing.xl, DesignTokens.Spacing.xxl)
    }

    func testCornerRadiusScaleIsAscending() {
        XCTAssertLessThan(DesignTokens.CornerRadius.xs, DesignTokens.CornerRadius.sm)
        XCTAssertLessThan(DesignTokens.CornerRadius.sm, DesignTokens.CornerRadius.md)
        XCTAssertLessThan(DesignTokens.CornerRadius.md, DesignTokens.CornerRadius.lg)
        XCTAssertLessThan(DesignTokens.CornerRadius.lg, DesignTokens.CornerRadius.xl)
        XCTAssertLessThan(DesignTokens.CornerRadius.xl, DesignTokens.CornerRadius.xxl)
    }

    func testAnimationDurationsWithinLiquidGlassRange() {
        XCTAssertGreaterThanOrEqual(DesignTokens.Animation.defaultDuration, 0.2)
        XCTAssertLessThanOrEqual(DesignTokens.Animation.defaultDuration, 0.35)
        XCTAssertGreaterThanOrEqual(DesignTokens.Animation.shortDuration, 0.2)
        XCTAssertLessThanOrEqual(DesignTokens.Animation.shortDuration, 0.35)
        XCTAssertGreaterThanOrEqual(DesignTokens.Animation.longDuration, 0.2)
        XCTAssertLessThanOrEqual(DesignTokens.Animation.longDuration, 0.35)
    }

    func testTouchTargetMeetsMinimum() {
        XCTAssertGreaterThanOrEqual(DesignTokens.TouchTarget.minimum, 44)
    }
}
