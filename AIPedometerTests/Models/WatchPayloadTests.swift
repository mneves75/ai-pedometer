import Foundation
import Testing

@testable import AIPedometer

struct WatchPayloadTests {
    private struct LegacyPayload: Encodable {
        let todaySteps: Int
        let goalSteps: Int
        let goalProgress: Double
        let currentStreak: Int
        let lastUpdated: Date
        let weeklySteps: [Int]
    }

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

    @Test("Reversed delivery cannot replace the newest accepted payload")
    func reversedDeliveryIsRejected() {
        let senderID = UUID()
        let newer = WatchPayload(
            senderID: senderID,
            revision: 2,
            todaySteps: 2_000,
            goalSteps: 10_000,
            goalProgress: 0.2,
            currentStreak: 2,
            lastUpdated: Date(timeIntervalSince1970: 150),
            weeklySteps: [],
            sentAt: Date(timeIntervalSince1970: 200)
        )
        let older = WatchPayload(
            senderID: senderID,
            revision: 1,
            todaySteps: 1_000,
            goalSteps: 10_000,
            goalProgress: 0.1,
            currentStreak: 1,
            lastUpdated: Date(timeIntervalSince1970: 100),
            weeklySteps: [],
            sentAt: Date(timeIntervalSince1970: 100)
        )

        var state = WatchPayloadAcceptanceState()
        let acceptedNewer = state.accept(newer)
        let acceptedOlder = state.accept(older)
        #expect(acceptedNewer)
        #expect(!acceptedOlder)
    }

    @Test("A new delivery remains acceptable when the phone clock moves backward")
    func clockRollbackDoesNotLockOutWatchUpdates() {
        let senderID = UUID()
        let previous = WatchPayload(
            senderID: senderID,
            revision: 1,
            todaySteps: 1_000,
            goalSteps: 10_000,
            goalProgress: 0.1,
            currentStreak: 1,
            lastUpdated: Date(timeIntervalSince1970: 200),
            weeklySteps: [],
            sentAt: Date(timeIntervalSince1970: 200)
        )
        let deliveredAfterClockRollback = WatchPayload(
            senderID: senderID,
            revision: 2,
            todaySteps: 1_100,
            goalSteps: 10_000,
            goalProgress: 0.11,
            currentStreak: 1,
            lastUpdated: Date(timeIntervalSince1970: 100),
            weeklySteps: [],
            sentAt: Date(timeIntervalSince1970: 100)
        )

        var state = WatchPayloadAcceptanceState()
        let acceptedPrevious = state.accept(previous)
        let acceptedAfterRollback = state.accept(deliveredAfterClockRollback)
        #expect(acceptedPrevious)
        #expect(acceptedAfterRollback)
    }

    @Test("Legacy payload without sentAt still decodes and orders by lastUpdated")
    func legacyPayloadStillDecodes() throws {
        let legacy = LegacyPayload(
            todaySteps: 1_234,
            goalSteps: 10_000,
            goalProgress: 0.1234,
            currentStreak: 4,
            lastUpdated: Date(timeIntervalSince1970: 300),
            weeklySteps: [1, 2, 3]
        )
        let decoded = try #require(WatchPayload.decode(from: JSONEncoder().encode(legacy)))

        #expect(decoded.todaySteps == 1_234)
        #expect(decoded.sentAt == nil)
        #expect(decoded.deliveryOrder == legacy.lastUpdated)
        var state = WatchPayloadAcceptanceState()
        let acceptedLegacy = state.accept(decoded)
        #expect(acceptedLegacy)
    }

    @Test("A retired phone installation cannot overwrite its replacement")
    func retiredSenderCannotReturn() {
        let oldSenderID = UUID()
        let newSenderID = UUID()
        let oldDeliveryDate = Date(timeIntervalSince1970: 100)
        let replacementDeliveryDate = Date(timeIntervalSince1970: 200)
        let oldPayload = WatchPayload(
            senderID: oldSenderID,
            revision: 10,
            todaySteps: 1_000,
            goalSteps: 10_000,
            goalProgress: 0.1,
            currentStreak: 1,
            lastUpdated: oldDeliveryDate,
            weeklySteps: [],
            sentAt: oldDeliveryDate
        )
        let replacementPayload = WatchPayload(
            senderID: newSenderID,
            revision: 1,
            todaySteps: 1_100,
            goalSteps: 10_000,
            goalProgress: 0.11,
            currentStreak: 1,
            lastUpdated: replacementDeliveryDate,
            weeklySteps: [],
            sentAt: replacementDeliveryDate
        )

        var state = WatchPayloadAcceptanceState()
        let acceptedOld = state.accept(oldPayload)
        let acceptedReplacement = state.accept(replacementPayload)
        let acceptedRetired = state.accept(oldPayload)
        #expect(acceptedOld)
        #expect(acceptedReplacement)
        #expect(!acceptedRetired)
    }

    @Test("An older queued sender cannot displace the current phone after watch state reset")
    func olderUnknownSenderCannotDisplaceCurrentPhone() {
        let currentPayload = WatchPayload(
            senderID: UUID(),
            revision: 1,
            todaySteps: 2_000,
            goalSteps: 10_000,
            goalProgress: 0.2,
            currentStreak: 2,
            lastUpdated: Date(timeIntervalSince1970: 200),
            weeklySteps: [],
            sentAt: Date(timeIntervalSince1970: 200)
        )
        let olderQueuedPayload = WatchPayload(
            senderID: UUID(),
            revision: 100,
            todaySteps: 1_000,
            goalSteps: 10_000,
            goalProgress: 0.1,
            currentStreak: 1,
            lastUpdated: Date(timeIntervalSince1970: 100),
            weeklySteps: [],
            sentAt: Date(timeIntervalSince1970: 100)
        )

        var state = WatchPayloadAcceptanceState()
        let acceptedCurrent = state.accept(currentPayload)
        let acceptedOlderSender = state.accept(olderQueuedPayload)
        #expect(acceptedCurrent)
        #expect(!acceptedOlderSender)
    }
}

// MARK: - WatchSyncService throttle (2026-05-19 audit)

#if canImport(WatchConnectivity)
@Suite("WatchSyncService throttle")
@MainActor
struct WatchSyncServiceThrottleTests {
    @Test("First reachable message is always sent")
    func firstReachableMessageIsAlwaysSent() {
        let shouldSend = WatchSyncService.shouldSendReachableMessage(
            lastSentAt: nil,
            lastSentSteps: nil,
            newSteps: 100,
            now: Date(timeIntervalSince1970: 0)
        )
        #expect(shouldSend == true)
    }

    @Test("Tight CMPedometer bursts inside the 5s window get coalesced")
    func tightBurstsGetCoalesced() {
        let last = Date(timeIntervalSince1970: 100)
        let now = last.addingTimeInterval(1)
        let shouldSend = WatchSyncService.shouldSendReachableMessage(
            lastSentAt: last,
            lastSentSteps: 1000,
            newSteps: 1003,
            now: now
        )
        #expect(shouldSend == false)
    }

    @Test("Big step deltas inside the window still bust the throttle")
    func bigDeltasBustTheThrottle() {
        let last = Date(timeIntervalSince1970: 100)
        let now = last.addingTimeInterval(1)
        let shouldSend = WatchSyncService.shouldSendReachableMessage(
            lastSentAt: last,
            lastSentSteps: 1000,
            newSteps: 1020,
            now: now
        )
        #expect(shouldSend == true)
    }

    @Test("After 5 seconds we re-send even without a meaningful step delta")
    func releasesAfterFiveSeconds() {
        let last = Date(timeIntervalSince1970: 100)
        let now = last.addingTimeInterval(6)
        let shouldSend = WatchSyncService.shouldSendReachableMessage(
            lastSentAt: last,
            lastSentSteps: 1000,
            newSteps: 1001,
            now: now
        )
        #expect(shouldSend == true)
    }
}
#endif
