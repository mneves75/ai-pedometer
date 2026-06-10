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
            // Use the purpose-built one-shot query API. Unlike `startUpdates`, this fires the
            // handler exactly once with the historical totals between `startDate` and `endDate`
            // and tears itself down automatically — no manual `stopUpdates`/dedupe lock required.
            //
            // The handler MUST be built through the `nonisolated` helper below. `query` satisfies
            // a `@MainActor` protocol requirement, so an inline closure here would inherit MainActor
            // isolation. `CMPedometerHandler` is a plain ObjC block (NOT `@Sendable`), and CoreMotion
            // invokes it on its own background queue — a MainActor-isolated closure then trips
            // `swift_task_isCurrentExecutor` (EXC_BREAKPOINT) the moment it runs off-main. This was the
            // 0.88 launch crash. Mirror the `startLiveUpdates`/`makePedometerCallback` pattern.
            queryPedometer.queryPedometerData(
                from: startDate,
                to: endDate,
                withHandler: Self.makeQueryCallback(continuation: continuation)
            )
        }
    }

    nonisolated static func makeQueryCallback(
        continuation: CheckedContinuation<PedometerSnapshot, any Error>
    ) -> @Sendable (CMPedometerData?, (any Error)?) -> Void {
        { data, error in
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
