import Foundation
import Testing

@testable import AIPedometer

struct WatchPayloadTests {
    @Test
    func encodeAndDecodeRoundTrip() throws {
        let original = WatchPayload(
            todaySteps: 8_500,
            goalSteps: 10_000,
            goalProgress: 0.85,
            currentStreak: 7,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000),
            weeklySteps: [5_000, 6_000, 7_000, 8_000, 9_000, 10_000, 8_500]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoded = WatchPayload.decode(from: data)

        #expect(decoded != nil)
        #expect(decoded?.todaySteps == 8_500)
        #expect(decoded?.goalSteps == 10_000)
        #expect(decoded?.goalProgress == 0.85)
        #expect(decoded?.currentStreak == 7)
        #expect(decoded?.weeklySteps.count == 7)
    }

    @Test
    func decodeFromNilReturnsNil() {
        let result = WatchPayload.decode(from: nil)
        #expect(result == nil)
    }

    @Test
    func decodeFromInvalidDataReturnsNil() {
        let invalidData = "not json".data(using: .utf8)
        let result = WatchPayload.decode(from: invalidData)
        #expect(result == nil)
    }

    @Test
    func placeholderHasExpectedDefaults() {
        let placeholder = WatchPayload.placeholder
        #expect(placeholder.todaySteps == 0)
        #expect(placeholder.goalSteps == 10_000)
        #expect(placeholder.goalProgress == 0)
        #expect(placeholder.currentStreak == 0)
        #expect(placeholder.weeklySteps.isEmpty)
    }

    @Test
    func transferKeyIsStable() {
        #expect(WatchPayload.transferKey == "payload")
    }

    @Test
    func handlesEmptyWeeklySteps() throws {
        let payload = WatchPayload(
            todaySteps: 1000,
            goalSteps: 10_000,
            goalProgress: 0.1,
            currentStreak: 0,
            lastUpdated: .now,
            weeklySteps: []
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = WatchPayload.decode(from: data)
        #expect(decoded?.weeklySteps.isEmpty == true)
    }

    @Test
    func handlesLargeStepCounts() throws {
        let payload = WatchPayload(
            todaySteps: 100_000,
            goalSteps: 50_000,
            goalProgress: 2.0,
            currentStreak: 365,
            lastUpdated: .now,
            weeklySteps: Array(repeating: 15_000, count: 7)
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = WatchPayload.decode(from: data)
        #expect(decoded?.todaySteps == 100_000)
        #expect(decoded?.goalProgress == 2.0)
    }
}
