#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

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
            session.transferUserInfo([WatchPayload.transferKey: encoded])
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
