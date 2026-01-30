import Foundation
import Testing

@testable import AIPedometer

struct ActivityTrackingModeTests {
    @Test
    func defaultsToSteps() {
        let mode = ActivityTrackingMode(rawValue: "steps")
        #expect(mode == .steps)
    }

    @Test
    func wheelchairPushesRawValue() {
        let mode = ActivityTrackingMode.wheelchairPushes
        #expect(mode.rawValue == "wheelchairPushes")
    }

    @Test
    func allCasesContainsBothModes() {
        let cases = ActivityTrackingMode.allCases
        #expect(cases.count == 2)
        #expect(cases.contains(.steps))
        #expect(cases.contains(.wheelchairPushes))
    }

    @Test
    func stepsIconIsWalk() {
        #expect(ActivityTrackingMode.steps.iconName == "figure.walk")
    }

    @Test
    func wheelchairIconIsRoll() {
        #expect(ActivityTrackingMode.wheelchairPushes.iconName == "figure.roll")
    }

    @Test
    func unitNamesAreNonEmpty() {
        #expect(!ActivityTrackingMode.steps.unitName.isEmpty)
        #expect(!ActivityTrackingMode.wheelchairPushes.unitName.isEmpty)
    }

    @Test
    func unitNamesAreDistinct() {
        let stepsUnit = ActivityTrackingMode.steps.unitName
        let wheelchairUnit = ActivityTrackingMode.wheelchairPushes.unitName
        #expect(stepsUnit != wheelchairUnit)
    }

    @Test
    func localizedNameIsNotEmpty() {
        for mode in ActivityTrackingMode.allCases {
            #expect(!mode.localizedName.isEmpty)
        }
    }

    @Test
    func localizedDescriptionIsNotEmpty() {
        for mode in ActivityTrackingMode.allCases {
            #expect(!mode.localizedDescription.isEmpty)
        }
    }

    @Test
    func isSendable() {
        let mode: any Sendable = ActivityTrackingMode.steps
        #expect(mode as? ActivityTrackingMode == .steps)
    }

    @Test
    func encodesAndDecodes() throws {
        let original = ActivityTrackingMode.wheelchairPushes
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ActivityTrackingMode.self, from: data)
        #expect(decoded == original)
    }
}
