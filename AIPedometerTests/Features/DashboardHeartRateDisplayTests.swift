import Foundation
import Testing

@testable import AIPedometer

@MainActor
@Suite("Dashboard heart-rate display")
struct DashboardHeartRateDisplayTests {
    @Test("Stale visual text shows freshness while accessibility text avoids punctuation artifacts")
    func staleHeartRateAccessibilityAvoidsMiddleDot() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let sample = HeartRateSample(bpm: 72, endDate: now.addingTimeInterval(-45 * 60))

        let visual = HeartRateDisplayFormatter.visualText(sample: sample, now: now)
        let accessibility = HeartRateDisplayFormatter.accessibilityText(sample: sample, now: now)

        #expect(visual.contains("·"))
        #expect(accessibility.contains("beats per minute") || accessibility.contains("batimentos por minuto"))
        #expect(!accessibility.contains("·"))
    }

    @Test("Freshness timeline crosses the stale threshold within one minute")
    func freshnessTimelineCrossesThresholdWithinOneMinute() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let sample = HeartRateSample(
            bpm: 72,
            endDate: now.addingTimeInterval(-HeartRateDisplayFormatter.freshnessThreshold + 30)
        )

        let beforeRefresh = HeartRateDisplayFormatter.visualText(sample: sample, now: now)
        let afterRefresh = HeartRateDisplayFormatter.visualText(
            sample: sample,
            now: now.addingTimeInterval(HeartRateDisplayFormatter.freshnessRefreshInterval)
        )

        #expect(HeartRateDisplayFormatter.freshnessRefreshInterval == 60)
        #expect(!beforeRefresh.contains("·"))
        #expect(afterRefresh.contains("·"))
    }
}
