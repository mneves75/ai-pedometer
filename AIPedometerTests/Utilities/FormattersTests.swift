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

    // Exact strings assume the simulator's region is not the injected one: a legacy formatter applies the
    // device's Number Format override to a locale whose identifier matches the current locale.
    @Test(arguments: [
        (meters: 0.0, expected: "0 m"),
        (meters: 500.0, expected: "500 m"),
        (meters: 999.4, expected: "999 m"),
        (meters: 999.5, expected: "1 km"),
        (meters: 999.6, expected: "1 km"),
        (meters: 1_234.0, expected: "1,23 km"),
        (meters: 42_195.0, expected: "42,2 km"),
    ])
    func metricDistanceSwitchesToKilometersAfterRounding(meters: Double, expected: String) {
        #expect(normalized(Formatters.distanceString(meters: meters, locale: Locale(identifier: "de_DE"))) == expected)
    }

    @Test
    func imperialRegionsUseMilesFeetAndInches() {
        let britain = Locale(identifier: "en_GB")
        #expect(normalized(Formatters.distanceString(meters: 5_000, locale: britain)) == "3.11mi")
        #expect(normalized(Formatters.elevationString(meters: 30, locale: britain)) == "98′")
        #expect(normalized(Formatters.stepLengthString(meters: 0.75, locale: britain)) == "29.5″")

        let unitedStates = Locale(identifier: "en_US")
        #expect(Formatters.distanceString(meters: 5_000, locale: unitedStates).hasSuffix("mi"))
        #expect(Formatters.elevationString(meters: 30, locale: unitedStates).hasSuffix("′"))
        #expect(Formatters.stepLengthString(meters: 0.75, locale: unitedStates).hasSuffix("″"))
    }

    @Test
    func metricMeasurementSystemWinsOverAUnitedStatesRegion() {
        let locale = Locale(identifier: "en_US@measure=metric")
        #expect(normalized(Formatters.distanceString(meters: 5_000, locale: locale)) == "5km")
        #expect(normalized(Formatters.elevationString(meters: 30, locale: locale)) == "30m")
        #expect(normalized(Formatters.stepLengthString(meters: 0.75, locale: locale)) == "75cm")
    }

    @Test
    func unitFollowsTheUsageNotOneSystemWideChoice() {
        let canada = Locale(identifier: "en_CA")
        #expect(Formatters.distanceString(meters: 5_000, locale: canada).hasSuffix("km"))
        #expect(Formatters.stepLengthString(meters: 0.75, locale: canada).hasSuffix("″"))
    }

    private func normalized(_ string: String) -> String {
        string.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ")
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

    // iOS keeps Settings > Measurement System as a preference outside the locale identifier: a US-region
    // phone set to Metric reports `en_US` with a metric `measurementSystem`, and `MeasurementFormatter`'s
    // natural scale still picked yards and miles from the identifier. On a simulator configured that way
    // this failed with "3,107mi"; on a default simulator it checks that the unit matches the region.
    @Test
    func distanceFollowsTheDeviceMeasurementPreference() {
        let preferredUnit = UnitLength(forLocale: .autoupdatingCurrent, usage: .road)
        let result = Formatters.distanceString(meters: 5_000)
        #expect(result.hasSuffix(preferredUnit.symbol), "\(result) should be in \(preferredUnit.symbol)")
    }

    // Settings > Number Format is honored by `NumberFormatter` but not by `FormatStyle`, so the ring read
    // "8.000 of 10,000 steps" when counts mixed `formattedSteps` and `.formatted()`.
    @Test
    func progressAccessibilityValueFormatsCountsLikeTheVisibleRing() {
        let value = ActivityTrackingMode.steps.progressAccessibilityValue(count: 12_345, goal: 10_000, percent: 100)
        #expect(value.contains(Formatters.stepCountString(12_345)), "\(value)")
        #expect(value.contains(Formatters.stepCountString(10_000)), "\(value)")
    }
}
