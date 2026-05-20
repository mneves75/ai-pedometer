#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private var lastQueuedTransferAt: Date?
    private var lastReachableSendAt: Date?
    private var lastReachableSentSteps: Int?

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(stepData: SharedStepData) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.isPaired, session.isWatchAppInstalled else { return }
        let payload = WatchPayload(
            todaySteps: stepData.todaySteps,
            goalSteps: stepData.goalSteps,
            goalProgress: stepData.goalProgress,
            currentStreak: stepData.currentStreak,
            lastUpdated: stepData.lastUpdated,
            weeklySteps: stepData.weeklySteps
        )
        do {
            let encoded = try JSONEncoder().encode(payload)
            // Always update application context with the latest snapshot (overwrites previous).
            do {
                try session.updateApplicationContext([WatchPayload.transferKey: encoded])
            } catch {
                Loggers.sync.warning("watch.update_application_context_failed", metadata: [
                    "error": error.localizedDescription
                ])
            }

            let now = Date.now

            // If reachable, push the snapshot immediately for best UX — but throttle to avoid
            // saturating the WC channel during a brisk walk where CMPedometer fires several
            // updates per second. See implementation-notes.html#finding-watch-connectivity-throttle.
            if session.isReachable,
               Self.shouldSendReachableMessage(
                   lastSentAt: lastReachableSendAt,
                   lastSentSteps: lastReachableSentSteps,
                   newSteps: stepData.todaySteps,
                   now: now
               ) {
                session.sendMessage([WatchPayload.transferKey: encoded], replyHandler: nil) { error in
                    Loggers.sync.warning("watch.send_message_failed", metadata: [
                        "error": error.localizedDescription
                    ])
                }
                lastReachableSendAt = now
                lastReachableSentSteps = stepData.todaySteps
            }

            // Queue userInfo as a durability mechanism, but throttle to avoid an unbounded queue.
            let minInterval: TimeInterval = 10 * 60
            if lastQueuedTransferAt == nil || now.timeIntervalSince(lastQueuedTransferAt ?? .distantPast) >= minInterval {
                session.transferUserInfo([WatchPayload.transferKey: encoded])
                lastQueuedTransferAt = now
            }
        } catch {
            Loggers.sync.error("watch.payload_encode_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }

    /// Pure throttle decision for `WCSession.sendMessage`. Push immediately on first send;
    /// otherwise require either ≥`minInterval` elapsed or ≥`minDeltaSteps` step change.
    /// Extracted for testability — WatchConnectivity has no usable test seam.
    static func shouldSendReachableMessage(
        lastSentAt: Date?,
        lastSentSteps: Int?,
        newSteps: Int,
        now: Date,
        minInterval: TimeInterval = 5,
        minDeltaSteps: Int = 10
    ) -> Bool {
        guard let lastSentAt else { return true }
        if now.timeIntervalSince(lastSentAt) >= minInterval { return true }
        if let lastSentSteps, abs(newSteps - lastSentSteps) >= minDeltaSteps { return true }
        return false
    }

    private func resetReachableThrottle() {
        lastReachableSendAt = nil
        lastReachableSentSteps = nil
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.resetReachableThrottle()
        }
    }
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.resetReachableThrottle()
        }
        session.activate()
    }
}
#else
import Foundation

struct SharedStepData: Codable, Sendable {
    let todaySteps: Int
    let goalSteps: Int
    let goalProgress: Double
    let currentStreak: Int
    let lastUpdated: Date
    let weeklySteps: [Int]
}

@MainActor
final class WatchSyncService {
    static let shared = WatchSyncService()

    private init() {}

    func start() {}
    func send(stepData: SharedStepData) {}
}
#endif
