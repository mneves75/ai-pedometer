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
}
