#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

@MainActor
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private var lastQueuedTransferAt: Date?
    private var lastReachableSendAt: Date?
    private var lastReachableSentSteps: Int?
    private var lastContextUpdateAt: Date?
    private var lastContextSentSteps: Int?

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
            let now = Date.now

            // The context is a latest-wins snapshot, so it gets the same time/step-delta
            // throttle as `sendMessage` — without it, every CMPedometer tick (several per
            // second during a brisk walk) paid a JSON encode + plist serialization + XPC
            // hop to the WatchConnectivity daemon.
            let shouldUpdateContext = Self.shouldSendReachableMessage(
                lastSentAt: lastContextUpdateAt,
                lastSentSteps: lastContextSentSteps,
                newSteps: stepData.todaySteps,
                now: now
            )

            // If reachable, push the snapshot immediately for best UX — but throttle to avoid
            // saturating the WC channel during a brisk walk where CMPedometer fires several
            // updates per second. See implementation-notes.html#finding-watch-connectivity-throttle.
            let shouldSendMessage = session.isReachable && Self.shouldSendReachableMessage(
                lastSentAt: lastReachableSendAt,
                lastSentSteps: lastReachableSentSteps,
                newSteps: stepData.todaySteps,
                now: now
            )

            // Queue userInfo as a durability mechanism, but throttle to avoid an unbounded queue.
            let queueMinInterval: TimeInterval = 10 * 60
            let shouldQueueTransfer = lastQueuedTransferAt == nil
                || now.timeIntervalSince(lastQueuedTransferAt ?? .distantPast) >= queueMinInterval

            // Nothing due on any channel: skip the encode entirely (hot pedometer tick path).
            guard shouldUpdateContext || shouldSendMessage || shouldQueueTransfer else { return }

            let encoded = try JSONEncoder().encode(payload)
            Signposts.sync.event("WatchPayloadEncoded")
            if shouldUpdateContext {
                do {
                    try session.updateApplicationContext([WatchPayload.transferKey: encoded])
                    lastContextUpdateAt = now
                    lastContextSentSteps = stepData.todaySteps
                    Signposts.sync.event("WatchContextUpdated")
                } catch {
                    Loggers.sync.warning("watch.update_application_context_failed", metadata: [
                        "error": error.localizedDescription
                    ])
                }
            }

            if shouldSendMessage {
                // The errorHandler MUST come from the `nonisolated` helper below. `send` runs on
                // `@MainActor`, and `WCSession`'s errorHandler block is NOT `@Sendable`
                // (WCSession.h), so an inline closure would inherit MainActor isolation — and the
                // WatchConnectivity daemon invokes the errorHandler on its own background queue,
                // which would trip `swift_task_isCurrentExecutor` (EXC_BREAKPOINT) on a failed
                // send. Same crash class as `MotionService.query`.
                session.sendMessage(
                    [WatchPayload.transferKey: encoded],
                    replyHandler: nil,
                    errorHandler: Self.makeSendMessageErrorHandler()
                )
                lastReachableSendAt = now
                lastReachableSentSteps = stepData.todaySteps
                Signposts.sync.event("WatchMessageSent")
            }

            if shouldQueueTransfer {
                session.transferUserInfo([WatchPayload.transferKey: encoded])
                lastQueuedTransferAt = now
                Signposts.sync.event("WatchTransferQueued")
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

    /// Builds the `WCSession.sendMessage` errorHandler as a `@Sendable` (nonisolated) closure.
    /// WatchConnectivity invokes it on a background queue and the SDK block is not `@Sendable`,
    /// so it must not inherit this class's `@MainActor` isolation. `AppLogger` is `Sendable` with
    /// `nonisolated` methods, so logging from the background queue is safe.
    nonisolated static func makeSendMessageErrorHandler() -> @Sendable (any Error) -> Void {
        { error in
            Loggers.sync.warning("watch.send_message_failed", metadata: [
                "error": error.localizedDescription
            ])
        }
    }

    private func resetReachableThrottle() {
        lastReachableSendAt = nil
        lastReachableSentSteps = nil
        lastContextUpdateAt = nil
        lastContextSentSteps = nil
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
#endif
