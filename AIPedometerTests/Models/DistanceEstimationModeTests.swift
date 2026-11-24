import Foundation
import Testing

@testable import AIPedometer

struct DistanceEstimationModeTests {
    @Test
    func defaultsToAutomatic() {
        let mode = DistanceEstimationMode(rawValue: "automatic")
        #expect(mode == .automatic)
    }

    @Test
    func manualRawValue() {
        let mode = DistanceEstimationMode.manual
        #expect(mode.rawValue == "manual")
    }
}
