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

    @Test
    func localizedNameIsNotEmpty() {
        for mode in DistanceEstimationMode.allCases {
            #expect(!mode.localizedName.isEmpty)
        }
    }

    @Test
    func localizedDescriptionIsNotEmpty() {
        for mode in DistanceEstimationMode.allCases {
            #expect(!mode.localizedDescription.isEmpty)
        }
    }

    @Test
    func isSendable() {
        let mode: any Sendable = DistanceEstimationMode.automatic
        #expect(mode as? DistanceEstimationMode == .automatic)
    }

    @Test
    func encodesAndDecodes() throws {
        let original = DistanceEstimationMode.manual
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DistanceEstimationMode.self, from: data)
        #expect(decoded == original)
    }
}
