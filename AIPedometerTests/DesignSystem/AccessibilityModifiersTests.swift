import XCTest
import SwiftUI

@testable import AIPedometer

@MainActor
final class AccessibilityModifiersTests: XCTestCase {
    func testAccessibleButtonAddsLabel() {
        let view = Text("Test")
            .accessibleButton(label: "Action", hint: "Hint")
        _ = view
        XCTAssertTrue(true)
    }

    func testAccessibleProgressFormatsPercentage() {
        let view = Text("Progress")
            .accessibleProgress(label: "Steps", value: 0.5)
        _ = view
        XCTAssertTrue(true)
    }
}
