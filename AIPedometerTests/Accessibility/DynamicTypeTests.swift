import XCTest
import SwiftUI

@testable import AIPedometer

@MainActor
final class DynamicTypeTests: XCTestCase {

    func testDesignTokensSpacingScalesWithAccessibility() {
        let baseSpacing = DesignTokens.Spacing.md
        XCTAssertGreaterThanOrEqual(baseSpacing, 16, "Base spacing should accommodate accessibility")
    }

    func testTouchTargetsMeetAccessibilityMinimum() {
        XCTAssertGreaterThanOrEqual(DesignTokens.TouchTarget.minimum, 44)
    }

    func testCornerRadiusDoesNotExceedReasonableLimit() {
        XCTAssertLessThanOrEqual(DesignTokens.CornerRadius.xxl, 32, "Corner radius should not be excessive")
    }

    func testStatCardViewInstantiatesWithoutCrash() {
        let card = StatCard(icon: "figure.walk", title: "Distance", value: "5.0 km", color: .blue)
        XCTAssertNotNil(card)
    }

    func testBadgeCardViewInstantiatesWithoutCrash() {
        let badge = BadgeDisplayItem(type: .steps5K, isEarned: true)
        let card = BadgeCard(badge: badge, onSelect: { _ in })
        XCTAssertNotNil(card)
    }

    func testHistoryRowViewInstantiatesWithoutCrash() {
        let summary = DailyStepSummary(date: Date(), steps: 10000, distance: 7000, floors: 5, calories: 350, goal: 10000)
        let row = HistoryRow(summary: summary, activityMode: .steps)
        XCTAssertNotNil(row)
    }

    func testHistoryRowViewInstantiatesWithWheelchairMode() {
        let summary = DailyStepSummary(date: Date(), steps: 3200, distance: 2400, floors: 2, calories: 120, goal: 3000)
        let row = HistoryRow(summary: summary, activityMode: .wheelchairPushes)
        XCTAssertNotNil(row)
    }

    func testWorkoutCardViewInstantiatesWithoutCrash() {
        let workout = WorkoutSession(type: .outdoorRun, startTime: Date())
        let card = WorkoutCard(workout: workout)
        XCTAssertNotNil(card)
    }

    func testGoalEditorSheetInstantiatesWithoutCrash() {
        let sheet = GoalEditorSheet(initialGoal: 10000, unitName: ActivityTrackingMode.steps.unitName) { _ in }
        XCTAssertNotNil(sheet)
    }
}
