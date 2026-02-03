import Testing
import Foundation
@testable import AIPedometer

@Suite("HealthKitSampleMerger Tests")
struct HealthKitSampleMergerTests {
    @Test("Overlapping samples prefer Apple Watch priority")
    func prefersWatchOnOverlap() {
        let watch = makeSample(start: 0, end: 10, value: 100, productType: "Watch6,1")
        let phone = makeSample(start: 0, end: 10, value: 50, productType: "iPhone16,2")

        let result = HealthKitSampleMerger.mergeTotal(samples: [watch, phone])

        #expect(result.total == 100)
        #expect(result.mergedSources == true)
        #expect(result.overlapSeconds > 0)
    }

    @Test("Non-overlapping lower priority samples are included")
    func includesNonOverlappingLowerPriority() {
        let watch = makeSample(start: 0, end: 5, value: 50, productType: "Watch6,1")
        let phone = makeSample(start: 5, end: 10, value: 50, productType: "iPhone16,2")

        let result = HealthKitSampleMerger.mergeTotal(samples: [watch, phone])

        #expect(result.total == 100)
        #expect(result.overlapSeconds == 0)
    }

    @Test("Partial overlap keeps lower priority portions")
    func partialOverlapKeepsPhoneRemainder() {
        let watch = makeSample(start: 0, end: 5, value: 50, productType: "Watch6,1")
        let phone = makeSample(start: 0, end: 10, value: 100, productType: "iPhone16,2")

        let result = HealthKitSampleMerger.mergeTotal(samples: [watch, phone])

        #expect(result.total == 100)
        #expect(result.overlapSeconds == 5)
    }

    @Test("Daily totals split samples that cross midnight")
    func dailyTotalsSplitAcrossDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let dayStart = Date(timeIntervalSinceReferenceDate: 0)
        let sample = makeSample(
            start: 23 * 3600,
            end: 25 * 3600,
            value: 120,
            productType: "iPhone16,2",
            base: dayStart
        )

        let result = HealthKitSampleMerger.mergeDailyTotals(
            samples: [sample],
            calendar: calendar,
            from: dayStart,
            to: dayStart.addingTimeInterval(25 * 3600)
        )

        let firstDayTotal = result.totals[dayStart] ?? -1
        let secondDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let secondDayTotal = result.totals[secondDayStart] ?? -1

        #expect(firstDayTotal == 60)
        #expect(secondDayTotal == 60)
    }

    private func makeSample(
        start: TimeInterval,
        end: TimeInterval,
        value: Double,
        productType: String,
        base: Date = Date(timeIntervalSinceReferenceDate: 0)
    ) -> HealthKitSampleValue {
        HealthKitSampleValue(
            start: base.addingTimeInterval(start),
            end: base.addingTimeInterval(end),
            value: value,
            sourceBundleIdentifier: "com.apple.health",
            productType: productType,
            deviceModel: nil,
            deviceName: nil
        )
    }
}
