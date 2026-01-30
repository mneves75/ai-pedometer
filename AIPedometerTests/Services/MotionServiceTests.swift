import Testing

@testable import AIPedometer

struct MotionServiceTests {
    @Test
    func deliverSnapshotFromDetachedTaskInvokesHandler() async throws {
        let snapshot = PedometerSnapshot(steps: 1, distance: 0, floorsAscended: 0)
        let probe = MotionDeliveryProbe()

        let didCall = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    Task.detached {
                        MotionService.deliverSnapshot(snapshot) { delivered in
                            Task {
                                await probe.record(delivered)
                                continuation.resume()
                            }
                        }
                    }
                }
                return true
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(1))
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }

        #expect(didCall)
        #expect(await probe.wasCalled)
        #expect(await probe.lastSteps == 1)
    }
}

actor MotionDeliveryProbe {
    private(set) var wasCalled = false
    private(set) var lastSteps: Int = 0

    func record(_ snapshot: PedometerSnapshot) {
        wasCalled = true
        lastSteps = snapshot.steps
    }
}
