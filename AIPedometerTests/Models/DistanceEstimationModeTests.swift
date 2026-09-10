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

    @Test
    func allCasesContainsBothModes() {
        let cases = DistanceEstimationMode.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.automatic))
        #expect(cases.contains(.manual))
    }
}
