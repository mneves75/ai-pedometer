import Testing

@testable import AIPedometer

struct MotionServiceTests {
    @Test
    @MainActor
    func deliverSnapshotFromDetachedTaskInvokesHandler() async throws {
        let snapshot = PedometerSnapshot(steps: 1, distance: 0, floorsAscended: 0)
        let probe = MotionDeliveryProbe()

        Task.detached {
            MotionService.deliverSnapshot(snapshot) { delivered in
                probe.record(delivered)
            }
        }

        let didCall = await waitForDelivery(probe: probe, timeout: .seconds(1))

        #expect(didCall)
        #expect(probe.wasCalled)
        #expect(probe.lastSteps == 1)
    }

    // Regression guard for the 0.88 launch crash (EXC_BREAKPOINT in
    // MotionService.query → swift_task_isCurrentExecutor). `query` is a `@MainActor`
    // protocol witness, but `CMPedometerHandler` is a non-`@Sendable` ObjC block that
    // CoreMotion invokes on a background queue. `makeQueryCallback` returns a
    // `@Sendable` (nonisolated) closure, so resuming the continuation off-main must NOT
    // trip the main-executor assertion. Driving it from a detached task mimics CoreMotion.
    @Test
    func queryCallbackResumesErrorOffMainWithoutIsolationTrap() async throws {
        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PedometerSnapshot, any Error>) in
                let callback = MotionService.makeQueryCallback(continuation: continuation)
                Task.detached {
                    callback(nil, MotionError.queryFailed)
                }
            }
            Issue.record("Expected MotionError.queryFailed to be thrown")
        } catch MotionError.queryFailed {
            // Expected: callback ran off-main and resumed without a main-executor trap.
        } catch {
            Issue.record("Expected MotionError.queryFailed, got \(error)")
        }
    }

    @Test
    func queryCallbackResumesNoDataOffMain() async throws {
        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PedometerSnapshot, any Error>) in
                let callback = MotionService.makeQueryCallback(continuation: continuation)
                Task.detached {
                    callback(nil, nil)
                }
            }
            Issue.record("Expected MotionError.noData to be thrown")
        } catch MotionError.noData {
            // Expected.
        } catch {
            Issue.record("Expected MotionError.noData, got \(error)")
        }
    }
}

@MainActor
final class MotionDeliveryProbe {
    private(set) var wasCalled = false
    private(set) var lastSteps: Int = 0

    func record(_ snapshot: PedometerSnapshot) {
        wasCalled = true
        lastSteps = snapshot.steps
    }
}

@MainActor
private func waitForDelivery(probe: MotionDeliveryProbe, timeout: Duration) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while !probe.wasCalled && clock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }

    return probe.wasCalled
}
