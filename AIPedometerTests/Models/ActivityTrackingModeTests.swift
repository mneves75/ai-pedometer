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
    func stepsIconIsWalk() {
        #expect(ActivityTrackingMode.steps.iconName == "figure.walk")
    }

    @Test
    func wheelchairIconIsRoll() {
        #expect(ActivityTrackingMode.wheelchairPushes.iconName == "figure.roll")
    }

    @Test
    func unitNamesAreDistinct() {
        let stepsUnit = ActivityTrackingMode.steps.unitName
        let wheelchairUnit = ActivityTrackingMode.wheelchairPushes.unitName
        #expect(stepsUnit != wheelchairUnit)
    }
}
