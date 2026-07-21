import Foundation
import XCTest

@MainActor
final class AIPedometerUITests: XCTestCase {
    private let navigationTimeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunches() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)
        d.assertDashboardLoaded()
    }

    func testOnboardingFlowReachesMainTabs() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: false)

        // Flow: Welcome -> Goal -> Permissions -> Get Started.
        UITestWait.tapFirstExisting(
            [d.app.buttons[A11yID.Onboarding.nextButton]],
            timeout: navigationTimeout
        )
        UITestWait.tapFirstExisting(
            [d.app.buttons[A11yID.Onboarding.nextButton]],
            timeout: navigationTimeout
        )
        UITestWait.tapFirstExisting(
            [d.app.buttons[A11yID.Onboarding.getStartedButton]],
            timeout: navigationTimeout
        )

        XCTAssertTrue(d.waitForMainShell(timeout: navigationTimeout))
        d.assertDashboardLoaded()
    }

    func testOnboardingSkipReachesMainTabsWithoutPermissionStep() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: false)

        UITestWait.tapFirstExisting(
            [d.app.buttons[A11yID.Onboarding.skipButton]],
            timeout: navigationTimeout
        )

        XCTAssertTrue(d.waitForMainShell(timeout: navigationTimeout))
        d.assertDashboardLoaded()
    }

    func testOnboardingCapturesScreens() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: false)
        d.captureScreen(named: "Onboarding - Welcome")
        UITestWait.tapFirstExisting([d.app.buttons[A11yID.Onboarding.nextButton]], timeout: navigationTimeout)
        let goalSlider = d.app.descendants(matching: .any)[A11yID.Onboarding.goalSlider]
        XCTAssertTrue(goalSlider.waitForExistence(timeout: navigationTimeout))
        let expectedGoalLabels = try localizedStringCatalogValues(for: "Daily step goal")
        XCTAssertTrue(
            expectedGoalLabels.contains(goalSlider.label),
            "Unexpected onboarding goal slider label: \(goalSlider.label)"
        )
        d.captureScreen(named: "Onboarding - Goal")
        UITestWait.tapFirstExisting([d.app.buttons[A11yID.Onboarding.nextButton]], timeout: navigationTimeout)
        d.captureScreen(named: "Onboarding - Permissions")
    }

    func testHealthKitSyncToggleDisablesHistory() throws {
        let d = AppDriver(test: self)
        // Force a deterministically disabled state. UI automation of SwiftUI toggles in List can be flaky.
        d.launch(skipOnboarding: true, forcedHealthKitSyncEnabled: false)

        d.openTab(.history)
        d.assertHistoryLoaded()
        // Confirma que a HistoryView leu o valor atualizado do AppStorage.
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.History.syncEnabled(false)],
                d.app.staticTexts[A11yID.History.syncEnabled(false)],
            ],
            timeout: navigationTimeout
        )
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.History.syncOffView],
                d.app.staticTexts[A11yID.History.syncOffView],
                d.app.staticTexts[A11yID.History.syncOffLabel],
            ],
            timeout: navigationTimeout
        )
        d.captureScreen(named: "History - Sync Off")
    }

    func testPrimaryTabsRenderAndCaptureScreens() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        // Dashboard
        d.openTab(.dashboard)
        d.assertDashboardLoaded()
        d.captureScreen(named: "Dashboard")

        // Extract step marker from dashboard and validate history uses the same value.
        let dashboardStepsMarker = d.waitForMarker(prefix: "dashboard_steps_", timeout: navigationTimeout)
        let stepsId = dashboardStepsMarker.identifier
        let stepsRaw = stepsId.replacingOccurrences(of: "dashboard_steps_", with: "")
        let steps = Int(stepsRaw) ?? -1
        XCTAssertGreaterThan(steps, -1)

        // History
        d.openTab(.history)
        d.assertHistoryLoaded()
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.History.todaySteps(steps)],
                d.app.staticTexts[A11yID.History.todaySteps(steps)],
            ],
            timeout: navigationTimeout
        )
        d.captureScreen(named: "History")

        // Workouts
        d.openTab(.workouts)
        d.assertWorkoutsLoaded()
        d.captureScreen(named: "Workouts")

        // AI Coach
        d.openTab(.aiCoach)
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.AICoach.view],
                d.app.otherElements[A11yID.AICoach.marker],
                d.app.staticTexts[A11yID.AICoach.marker],
            ],
            timeout: navigationTimeout
        )
        d.captureScreen(named: "AI Coach")

        // More
        d.openTab(.more)
        d.assertMoreLoaded()
        d.captureScreen(named: "More")
    }

    func testMoreSupportOpensAboutAndShowsTipJar() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        d.openTab(.more)
        d.assertMoreLoaded()
        d.tap(id: A11yID.More.supportRowLabel, timeout: navigationTimeout)
        d.assertAboutLoaded()
        UITestWait.assertAnyExists(
            [d.app.buttons[A11yID.About.tipJarCoffeeButton]],
            timeout: navigationTimeout
        )
        d.captureScreen(named: "About - Tip Jar")
    }

    func testBadgesOpensFromMore() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        d.openTab(.more)
        d.assertMoreLoaded()
        d.tap(id: A11yID.More.badgesRowLabel, timeout: navigationTimeout)
        d.assertBadgesLoaded()
        d.captureScreen(named: "Badges")
    }

    func testSettingsCoreTogglesPresent() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        d.openTab(.more)
        d.assertMoreLoaded()
        d.tap(id: A11yID.More.settingsRowLabel, timeout: navigationTimeout)
        d.assertSettingsLoaded()

        UITestWait.assertAnyExists(
            [
                d.app.buttons[A11yID.Settings.dailyGoalRow],
                d.app.cells[A11yID.Settings.dailyGoalRow],
                d.app.otherElements[A11yID.Settings.dailyGoalRow],
                d.app.staticTexts[A11yID.Settings.dailyGoalRow],
            ],
            timeout: navigationTimeout
        )

        d.scrollTo(id: A11yID.Settings.healthKitSyncToggle)
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Settings.healthKitSyncToggle],
                d.app.switches[A11yID.Settings.healthKitSyncToggle],
            ],
            timeout: navigationTimeout
        )
    }

    func testHealthAccessHelpOpensFromSettings() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        d.openTab(.more)
        d.assertMoreLoaded()
        d.tap(id: A11yID.More.settingsRowLabel, timeout: navigationTimeout)
        d.assertSettingsLoaded()

        d.scrollTo(id: A11yID.Settings.healthAccessRow)
        d.tap(id: A11yID.Settings.healthAccessRow, timeout: navigationTimeout)

        UITestWait.assertAnyExists(
            [
                d.app.scrollViews[A11yID.HealthAccessHelp.view],
                d.app.otherElements[A11yID.HealthAccessHelp.view],
            ],
            timeout: navigationTimeout
        )
        d.captureScreen(named: "Health Access Help")
        UITestWait.tapFirstExisting(
            [d.app.buttons[A11yID.HealthAccessHelp.doneButton]],
            timeout: navigationTimeout
        )
    }

    func testGoalEditorUpdatesDashboardMarkers() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        d.openTab(.more)
        d.assertMoreLoaded()
        d.tap(id: A11yID.More.settingsRowLabel, timeout: navigationTimeout)
        d.assertSettingsLoaded()

        d.tap(id: A11yID.Settings.dailyGoalRow, timeout: navigationTimeout)

        // Slider exists in the goal editor sheet.
        let slider = d.app.sliders[A11yID.GoalEditor.slider]
        XCTAssertTrue(slider.waitForExistence(timeout: navigationTimeout))

        // Nudge the slider and save.
        slider.adjust(toNormalizedSliderPosition: 0.65)
        UITestWait.tapFirstExisting([d.app.buttons[A11yID.GoalEditor.saveButton]], timeout: navigationTimeout)

        d.openTab(.dashboard)
        d.assertDashboardLoaded()

        _ = d.waitForMarker(prefix: "dashboard_goal_", timeout: navigationTimeout)
    }

    func testTrainingPlansOpensFromWorkouts() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true, forcedPremiumEnabled: true)

        d.openTab(.workouts)
        d.assertWorkoutsLoaded()
        // Prefer tapping the actual button (NavigationLink) for reliability.
        d.tap(id: A11yID.Workouts.trainingPlansCard, timeout: navigationTimeout)
        d.assertTrainingPlansLoaded()
        d.captureScreen(named: "Training Plans")
    }

    func testStartAndFinishWorkoutUpdatesRecentList() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        d.openTab(.workouts)
        d.assertWorkoutsLoaded()
        UITestWait.tapFirstExisting([d.app.buttons[A11yID.Workouts.startWorkoutButton]], timeout: navigationTimeout)
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.ActiveWorkout.view],
                d.app.buttons[A11yID.ActiveWorkout.endButton],
            ],
            timeout: navigationTimeout
        )
        d.captureScreen(named: "Active Workout")

        d.tap(id: A11yID.ActiveWorkout.endButton, timeout: navigationTimeout)
        d.tap(id: A11yID.ActiveWorkout.confirmEndButton, timeout: navigationTimeout)
        XCTAssertTrue(
            d.app.buttons[A11yID.ActiveWorkout.endButton].waitForNonExistence(timeout: navigationTimeout),
            "Active workout sheet should dismiss after finishing"
        )
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Workouts.recentWorkoutsCarousel],
                d.app.staticTexts[A11yID.Workouts.recentWorkoutsCarousel],
            ],
            timeout: navigationTimeout
        )
        XCTAssertFalse(d.app.descendants(matching: .any)[A11yID.Workouts.recentWorkoutsEmptyState].exists)
    }

    func testRecoveredWorkoutCanBeFinished() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true, seedUnfinishedWorkout: true)

        d.openTab(.workouts)
        d.assertWorkoutsLoaded(requireStartButton: false)
        UITestWait.assertAnyExists(
            [d.app.otherElements[A11yID.Workouts.recoveryCard]],
            timeout: navigationTimeout
        )
        d.tap(id: A11yID.Workouts.finishRecoveredWorkoutButton, timeout: navigationTimeout)
        XCTAssertTrue(
            d.app.otherElements[A11yID.Workouts.recoveryCard].waitForNonExistence(timeout: navigationTimeout)
        )
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Workouts.recentWorkoutsCarousel],
                d.app.staticTexts[A11yID.Workouts.recentWorkoutsCarousel],
            ],
            timeout: navigationTimeout
        )
    }

    func testRecoveredWorkoutCanBeDiscarded() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true, seedUnfinishedWorkout: true)

        d.openTab(.workouts)
        d.assertWorkoutsLoaded(requireStartButton: false)
        d.tap(id: A11yID.Workouts.discardRecoveredWorkoutButton, timeout: navigationTimeout)
        d.tap(id: A11yID.Workouts.confirmDiscardRecoveredWorkoutButton, timeout: navigationTimeout)
        XCTAssertTrue(
            d.app.otherElements[A11yID.Workouts.recoveryCard].waitForNonExistence(timeout: navigationTimeout)
        )
        d.assertWorkoutsLoaded()
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Workouts.recentWorkoutsEmptyState],
                d.app.staticTexts[A11yID.Workouts.recentWorkoutsEmptyState],
            ],
            timeout: navigationTimeout
        )
    }

    func testAICoachShowsUnavailableStateAndNoInputWhenForced() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true, forcedPremiumEnabled: true, forceAIUnavailable: true)

        d.openTab(.aiCoach)
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.AICoach.unavailableState],
                d.app.staticTexts[A11yID.AICoach.unavailableState],
            ],
            timeout: navigationTimeout
        )
        XCTAssertFalse(d.app.textFields[A11yID.AICoach.input].exists)
        XCTAssertFalse(d.app.buttons[A11yID.AICoach.sendButton].exists)
    }

    func testDashboardShowsAIUnavailableBannerWhenForced() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true, forcedPremiumEnabled: true, forceAIUnavailable: true)

        d.assertDashboardLoaded()
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.AIAvailability.banner],
                d.app.staticTexts[A11yID.AIAvailability.banner],
            ],
            timeout: navigationTimeout
        )
    }

    func testWorkoutsShowPremiumGatesWhenPremiumIsForcedOff() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true, forcedPremiumEnabled: false)

        d.openTab(.workouts)
        d.assertWorkoutsLoaded()

        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Workouts.premiumTodayPlanGate],
                d.app.staticTexts[A11yID.Workouts.premiumTodayPlanGate],
            ],
            timeout: navigationTimeout
        )
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Workouts.premiumTrainingPlansGate],
                d.app.staticTexts[A11yID.Workouts.premiumTrainingPlansGate],
            ],
            timeout: navigationTimeout
        )
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Workouts.premiumExpeditionModeGate],
                d.app.staticTexts[A11yID.Workouts.premiumExpeditionModeGate],
            ],
            timeout: navigationTimeout
        )
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Workouts.premiumRoutesGate],
                d.app.staticTexts[A11yID.Workouts.premiumRoutesGate],
            ],
            timeout: navigationTimeout
        )
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Workouts.recentWorkoutsEmptyState],
                d.app.staticTexts[A11yID.Workouts.recentWorkoutsEmptyState],
            ],
            timeout: navigationTimeout
        )
    }

    func testWorkoutsShowsRouteImportWhenPremiumIsForcedOn() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true, forcedPremiumEnabled: true)

        d.openTab(.workouts)
        d.assertWorkoutsLoaded()

        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.Workouts.routeImportCard],
                d.app.staticTexts[A11yID.Workouts.routeImportCard],
            ],
            timeout: navigationTimeout
        )
        UITestWait.assertAnyExists(
            [
                d.app.buttons[A11yID.Workouts.routeImportButton],
                d.app.otherElements[A11yID.Workouts.routeImportButton],
            ],
            timeout: navigationTimeout
        )
    }

    func testAboutFromSettings() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        d.openTab(.more)
        d.assertMoreLoaded()
        d.tap(id: A11yID.More.settingsRowLabel, timeout: navigationTimeout)
        d.assertSettingsLoaded()

        d.scrollTo(id: A11yID.Settings.aboutRow)
        d.tap(id: A11yID.Settings.aboutRow, timeout: navigationTimeout)
        d.assertAboutLoaded()
    }
}

private enum StringCatalogLookupError: Error {
    case malformedCatalog
    case missingKey(String)
}

private func localizedStringCatalogValues(for key: String, filePath: String = #filePath) throws -> Set<String> {
    let testFile = URL(fileURLWithPath: filePath)
    let repoRoot = testFile
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let catalogURL = repoRoot
        .appendingPathComponent("Shared")
        .appendingPathComponent("Resources")
        .appendingPathComponent("Localizable.xcstrings")

    let data = try Data(contentsOf: catalogURL)
    guard
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let strings = json["strings"] as? [String: Any],
        let entry = strings[key] as? [String: Any],
        let localizations = entry["localizations"] as? [String: Any]
    else {
        throw StringCatalogLookupError.missingKey(key)
    }

    let values = localizations.values.compactMap { localeEntry -> String? in
        guard
            let localeEntry = localeEntry as? [String: Any],
            let stringUnit = localeEntry["stringUnit"] as? [String: Any],
            let value = stringUnit["value"] as? String,
            !value.isEmpty
        else {
            return nil
        }
        return value
    }

    guard !values.isEmpty else {
        throw StringCatalogLookupError.malformedCatalog
    }

    return Set(values)
}
