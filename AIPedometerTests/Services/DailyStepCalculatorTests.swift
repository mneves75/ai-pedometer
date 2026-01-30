import Foundation
import Testing

@testable import AIPedometer

struct DailyStepCalculatorTests {
    @Test
    func startOfDayReturnsMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        let calculator = DailyStepCalculator(calendar: calendar)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let start = calculator.startOfDay(for: date)
        let components = calendar.dateComponents([.hour, .minute, .second], from: start)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test
    func dailyRangesCountMatchesDays() {
        let calendar = Calendar(identifier: .gregorian)
        let calculator = DailyStepCalculator(calendar: calendar)
        let ranges = calculator.dailyRanges(days: 7, endingOn: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(ranges.count == 7)
    }

    @Test
    func endOfDayIsNextMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        let calculator = DailyStepCalculator(calendar: calendar)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let end = calculator.endOfDay(for: date)
        let components = calendar.dateComponents([.hour, .minute, .second], from: end)
        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test
    func dailyRangesAreChronological() {
        let calendar = Calendar(identifier: .gregorian)
        let calculator = DailyStepCalculator(calendar: calendar)
        let ranges = calculator.dailyRanges(days: 3, endingOn: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(ranges[0].start < ranges[1].start)
        #expect(ranges[1].start < ranges[2].start)
    }

    @Test
    func didCrossMidnightDetectsDayChange() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let calculator = DailyStepCalculator(calendar: calendar)

        let before = Date(timeIntervalSince1970: 1_700_000_000)
        let after = Date(timeIntervalSince1970: 1_700_100_000)

        #expect(calculator.didCrossMidnight(previousDate: before, currentDate: after))
    }

    @Test
    func didCrossMidnightReturnsFalseForSameDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let calculator = DailyStepCalculator(calendar: calendar)

        let time1 = Date(timeIntervalSince1970: 1_700_000_000)
        let time2 = Date(timeIntervalSince1970: 1_700_000_100)

        #expect(!calculator.didCrossMidnight(previousDate: time1, currentDate: time2))
    }

    @Test
    func dailyRangesHandlesZeroDays() {
        let calendar = Calendar(identifier: .gregorian)
        let calculator = DailyStepCalculator(calendar: calendar)
        let ranges = calculator.dailyRanges(days: 0, endingOn: .now)
        #expect(ranges.isEmpty)
    }

    @Test
    func dailyRangesHandlesSingleDay() {
        let calendar = Calendar(identifier: .gregorian)
        let calculator = DailyStepCalculator(calendar: calendar)
        let ranges = calculator.dailyRanges(days: 1, endingOn: .now)
        #expect(ranges.count == 1)
    }

    @Test
    func eachRangeSpansExactly24Hours() {
        let calendar = Calendar(identifier: .gregorian)
        let calculator = DailyStepCalculator(calendar: calendar)
        let ranges = calculator.dailyRanges(days: 5, endingOn: Date(timeIntervalSince1970: 1_700_000_000))
        for range in ranges {
            let interval = range.end.timeIntervalSince(range.start)
            #expect(abs(interval - 86400) < 1)
        }
    }
}
