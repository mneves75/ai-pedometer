import Foundation
import Testing

@testable import AIPedometer

@MainActor
struct FormattersTests {
    @Test
    func stepCountFormatterUsesDecimalStyle() {
        let result = Formatters.stepCountString(10_000)
        #expect(result.contains(",") || result.contains("."))
    }

    @Test
    func caloriesFormatterHasNoFractionDigits() {
        let result = Formatters.caloriesString(320.75)
        #expect(result == "321" || result == "320")
    }

    @Test
    func distanceFormatterUsesShortStyle() {
        let result = Formatters.distanceString(meters: 1_000)
        #expect(result.contains("km") || result.contains("m"))
    }

    @Test
    func durationFormatterProducesDigits() {
        let result = Formatters.durationString(seconds: 3660)
        #expect(!result.isEmpty)
        #expect(result.rangeOfCharacter(from: .decimalDigits) != nil)
    }

    @Test
    func durationFormatterHandlesZero() {
        let result = Formatters.durationString(seconds: 0)
        #expect(!result.isEmpty)
        #expect(result.contains("0"))
    }
}
