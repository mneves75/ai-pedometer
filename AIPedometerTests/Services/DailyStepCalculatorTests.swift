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
    func endOfDayIsNextDayStart() throws {
        let calendar = Calendar(identifier: .gregorian)
        let calculator = DailyStepCalculator(calendar: calendar)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let start = calculator.startOfDay(for: date)
        let end = calculator.endOfDay(for: date)
        let expectedNextDay = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        #expect(end > date)
        #expect(end == calendar.startOfDay(for: expectedNextDay))
    }

    @Test("Midnight spring-forward DST keeps contiguous day boundaries without a 1-hour gap")
    func midnightDSTKeepsContiguousBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Santiago"))
        let calculator = DailyStepCalculator(calendar: calendar)

        // America/Santiago springs forward at 00:00 -> 01:00 on 2026-09-06.
        let sept5Noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12)))
        let sept6Noon = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 12)))

        let sept5End = calculator.endOfDay(for: sept5Noon)
        let sept6Start = calculator.startOfDay(for: sept6Noon)
        #expect(sept5End == sept6Start)
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
