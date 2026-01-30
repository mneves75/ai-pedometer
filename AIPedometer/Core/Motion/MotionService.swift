import Foundation
import CoreMotion

@MainActor
protocol MotionServiceProtocol {
    func startLiveUpdates(from date: Date, handler: @escaping @Sendable @MainActor (PedometerSnapshot) -> Void) throws
    func stopLiveUpdates()
    func query(from startDate: Date, to endDate: Date) async throws -> PedometerSnapshot
}

struct PedometerSnapshot: Sendable {
    let steps: Int
    let distance: Double
    let floorsAscended: Int
}

final class MotionService: MotionServiceProtocol {
    private let pedometer = CMPedometer()

    func startLiveUpdates(from date: Date, handler: @escaping @Sendable @MainActor (PedometerSnapshot) -> Void) throws {
        guard CMPedometer.isStepCountingAvailable() else {
            throw MotionError.notAvailable
        }
        let callback = Self.makePedometerCallback(handler: handler)
        pedometer.startUpdates(from: date, withHandler: callback)
    }

    func stopLiveUpdates() {
        pedometer.stopUpdates()
    }

    func query(from startDate: Date, to endDate: Date) async throws -> PedometerSnapshot {
        guard CMPedometer.isStepCountingAvailable() else {
            throw MotionError.notAvailable
        }
        let queryPedometer = CMPedometer()
        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var didResume = false
            queryPedometer.startUpdates(from: startDate) { data, error in
                lock.lock()
                let shouldResume = !didResume
                didResume = true
                lock.unlock()
                guard shouldResume else {
                    Loggers.motion.warning("motion.query_duplicate_callback")
                    return
                }
                defer { queryPedometer.stopUpdates() }
                if let error {
                    Loggers.motion.error("motion.query_failed", metadata: ["error": String(describing: error)])
                    continuation.resume(throwing: MotionError.queryFailed)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: MotionError.noData)
                    return
                }
                let snapshot = PedometerSnapshot(
                    steps: data.numberOfSteps.intValue,
                    distance: data.distance?.doubleValue ?? 0,
                    floorsAscended: data.floorsAscended?.intValue ?? 0
                )
                continuation.resume(returning: snapshot)
            }
        }
    }

    nonisolated static func deliverSnapshot(
        _ snapshot: PedometerSnapshot,
        handler: @escaping @Sendable @MainActor (PedometerSnapshot) -> Void
    ) {
        Task { @MainActor in
            handler(snapshot)
        }
    }

    nonisolated private static func makePedometerCallback(
        handler: @escaping @Sendable @MainActor (PedometerSnapshot) -> Void
    ) -> @Sendable (CMPedometerData?, (any Error)?) -> Void {
        { data, error in
            guard let data, error == nil else { return }
            let snapshot = PedometerSnapshot(
                steps: data.numberOfSteps.intValue,
                distance: data.distance?.doubleValue ?? 0,
                floorsAscended: data.floorsAscended?.intValue ?? 0
            )
            deliverSnapshot(snapshot, handler: handler)
        }
    }
}
