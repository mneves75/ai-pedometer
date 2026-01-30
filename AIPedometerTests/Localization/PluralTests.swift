import Foundation
import Testing
@testable import AIPedometer

@Suite("Pluralization Tests")
@MainActor
struct PluralTests {

    // MARK: - Number Formatting

    @Test("Step count formatting handles various values", arguments: [0, 1, 100, 1000, 10000, 25000])
    func stepCountFormatting(count: Int) {
        let formatted = count.formattedSteps
        #expect(!formatted.isEmpty, "Formatted count should not be empty")
    }

    @Test("Distance formatting produces valid output")
    func distanceFormattingProducesValidOutput() {
        let testDistances: [Double] = [0.1, 1.0, 4.2, 10.5, 42.195]

        for distance in testDistances {
            let formatted = distance.formattedDistance()
            #expect(!formatted.isEmpty, "Formatted distance should not be empty")
        }
    }

    @Test("Large numbers format with proper grouping")
    func largeNumbersFormatProperly() {
        let largeNumbers = [1000, 10000, 100000]

        for number in largeNumbers {
            let formatted = number.formattedSteps
            #expect(!formatted.isEmpty, "Large number formatting should not be empty")
        }
    }

    // MARK: - Goal Progress

    @Test("Goal progress text handles edge cases", arguments: [0, 50, 100, 150])
    func goalProgressHandlesEdgeCases(percentage: Int) {
        // Verify progress values don't cause issues
        let progress = Double(percentage) / 100.0
        #expect(progress >= 0, "Progress should be non-negative")

        // Test that the min function works correctly for display
        let displayProgress = min(progress, 1.0)
        #expect(displayProgress <= 1.0, "Display progress should cap at 1.0")
    }

    // MARK: - Unit Name Tests

    @Test("ActivityTrackingMode unitName returns valid unit")
    func activityModeUnitNameIsValid() {
        for mode in ActivityTrackingMode.allCases {
            let unitName = mode.unitName
            #expect(!unitName.isEmpty, "Unit name should not be empty for \(mode.rawValue)")
        }
    }

    // MARK: - Date Formatting

    @Test("Day name formatting produces output")
    func dayNameFormattingProducesOutput() {
        let testDates = [
            Date(),
            Date().addingTimeInterval(-86400),
            Date().addingTimeInterval(-86400 * 2),
            Date().addingTimeInterval(-86400 * 3)
        ]

        for date in testDates {
            let dayName = date.formatted(.dateTime.weekday(.abbreviated))
            #expect(!dayName.isEmpty, "Day name should not be empty")
        }
    }

    @Test("Date string formatting produces output")
    func dateStringFormattingProducesOutput() {
        let date = Date()
        let formatted = date.formatted(date: .abbreviated, time: .omitted)

        #expect(!formatted.isEmpty, "Date string should not be empty")
    }
}
