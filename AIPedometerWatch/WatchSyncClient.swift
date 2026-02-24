import Foundation
import Observation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

#if canImport(WatchConnectivity)
@Observable
@MainActor
final class WatchSyncClient: NSObject, WCSessionDelegate {
    private(set) var payload: WatchPayload = .placeholder

    override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handlePayload(from: userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handlePayload(from: applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handlePayload(from: message)
    }

    private nonisolated func handlePayload(from dictionary: [String: Any]) {
        guard let data = dictionary[WatchPayload.transferKey] as? Data,
              let decoded = WatchPayload.decode(from: data) else { return }
        Task { @MainActor in
            payload = decoded
            Loggers.sync.info("watch.payload_received", metadata: [
                "steps": "\(decoded.todaySteps)",
                "goal": "\(decoded.goalSteps)",
                "streak": "\(decoded.currentStreak)"
            ])
        }
    }
}
#else
@Observable
@MainActor
final class WatchSyncClient: NSObject {
    private(set) var payload: WatchPayload = .placeholder
}
#endif
