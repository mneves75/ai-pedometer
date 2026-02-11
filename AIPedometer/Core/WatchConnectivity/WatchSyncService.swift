#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private var lastQueuedTransferAt: Date?

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

            // If reachable, push the snapshot immediately for best UX.
            if session.isReachable {
                session.sendMessage([WatchPayload.transferKey: encoded], replyHandler: nil) { error in
                    Loggers.sync.warning("watch.send_message_failed", metadata: [
                        "error": error.localizedDescription
                    ])
                }
            }

            // Queue userInfo as a durability mechanism, but throttle to avoid an unbounded queue.
            let now = Date.now
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

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
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
