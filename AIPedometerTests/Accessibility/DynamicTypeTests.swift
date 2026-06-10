import Testing

@testable import AIPedometer

@Suite("DynamicType Tests")
struct DynamicTypeTests {
    @Test("Base spacing accommodates accessibility")
    func designTokensSpacingScalesWithAccessibility() {
        #expect(DesignTokens.Spacing.md >= 16, "Base spacing should accommodate accessibility")
    }

    @Test("Corner radius does not exceed reasonable limit")
    func cornerRadiusDoesNotExceedReasonableLimit() {
        #expect(DesignTokens.CornerRadius.xxl <= 32, "Corner radius should not be excessive")
    }
}
