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
