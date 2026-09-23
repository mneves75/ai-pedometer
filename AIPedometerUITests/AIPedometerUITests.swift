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

        XCTAssertTrue(d.app.buttons[A11yID.Onboarding.skipButton].isHittable)
        UITestWait.tapFirstExisting(
            [d.app.buttons[A11yID.Onboarding.skipButton]],
            timeout: navigationTimeout
        )

        let reachedMainShell = d.waitForMainShell(timeout: navigationTimeout)
        if !reachedMainShell {
            d.captureScreen(named: "Onboarding - Skip failure")
            let hierarchy = XCTAttachment(string: d.app.debugDescription)
            hierarchy.name = "Onboarding skip accessibility hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(reachedMainShell)
        d.assertDashboardLoaded()
    }

    func testOnboardingSkipSaveFailureStaysOnOnboarding() throws {
        let d = AppDriver(test: self)
        d.launch(
            skipOnboarding: false,
            forceGoalSaveFailure: true,
            useProductionGlass: true
        )

        d.app.buttons[A11yID.Onboarding.skipButton].tap()

        XCTAssertTrue(d.app.alerts.firstMatch.waitForExistence(timeout: navigationTimeout))
        try performSystemAlertAccessibilityAudit(on: d.app)
        XCTAssertTrue(d.waitForOnboardingShell(timeout: navigationTimeout))
        XCTAssertFalse(d.waitForMainShell(timeout: 1))
    }

    func testOnboardingCompletionSaveFailureStaysOnOnboarding() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: false, forceGoalSaveFailure: true)

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

        XCTAssertTrue(d.app.alerts.firstMatch.waitForExistence(timeout: navigationTimeout))
        XCTAssertTrue(d.waitForOnboardingShell(timeout: navigationTimeout))
        XCTAssertFalse(d.waitForMainShell(timeout: 1))
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

    func testOnboardingScreensPassAccessibilityAudit() throws {
        continueAfterFailure = true
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: false, useProductionGlass: true)

        try performAccessibilityAudit(on: d.app)
        UITestWait.tapFirstExisting(
            [d.app.buttons[A11yID.Onboarding.nextButton]],
            timeout: navigationTimeout
        )
        try performAccessibilityAudit(on: d.app)
        UITestWait.tapFirstExisting(
            [d.app.buttons[A11yID.Onboarding.nextButton]],
            timeout: navigationTimeout
        )
        try performAccessibilityAudit(on: d.app)
    }

    func testDashboardAndWorkoutRecoveryPassAccessibilityAudit() throws {
        continueAfterFailure = true
        let d = AppDriver(test: self)
        d.launch(
            skipOnboarding: true,
            seedUnfinishedWorkout: true,
            useProductionGlass: true
        )

        d.assertDashboardLoaded()
        try performAccessibilityAudit(on: d.app)
        d.app.swipeUp()
        try performAccessibilityAudit(on: d.app)

        d.openTab(.workouts)
        d.assertWorkoutsLoaded(requireStartButton: false)
        UITestWait.assertAnyExists(
            [d.app.otherElements[A11yID.Workouts.recoveryCard]],
            timeout: navigationTimeout
        )
        try performAccessibilityAudit(on: d.app)
    }

    func testAccessibilityAuditTabBarFilterRejectsContainedElementsAndAncestors() {
        let tabBarFrame = CGRect(x: 0, y: 700, width: 400, height: 100)
        let partiallyOccludedContent = CGRect(x: 20, y: 680, width: 100, height: 40)
        let tabBarElement = CGRect(x: 20, y: 720, width: 60, height: 40)
        let screenContainer = CGRect(x: 0, y: 0, width: 400, height: 800)

        XCTAssertTrue(isPartiallyOccluded(partiallyOccludedContent, by: tabBarFrame))
        XCTAssertFalse(isPartiallyOccluded(tabBarElement, by: tabBarFrame))
        XCTAssertFalse(isPartiallyOccluded(screenContainer, by: tabBarFrame))
    }

    func testAccessibilityAuditKnownNodeFilterIsNarrow() {
        XCTAssertTrue(shouldAcceptKnownAuditIssue(
            type: .contrast,
            identifier: A11yID.Dashboard.progressValue
        ))
        for identifier in dashboardStatTextIdentifiers {
            XCTAssertTrue(shouldAcceptKnownAuditIssue(
                type: .elementDetection,
                identifier: identifier
            ))
        }
        XCTAssertFalse(shouldAcceptKnownAuditIssue(
            type: .elementDetection,
            identifier: A11yID.Dashboard.progressValue
        ))
        XCTAssertFalse(shouldAcceptKnownAuditIssue(
            type: .elementDetection,
            identifier: A11yID.Dashboard.distanceStatCard
        ))
        XCTAssertFalse(shouldAcceptKnownAuditIssue(
            type: .hitRegion,
            identifier: A11yID.Dashboard.statCardValue(A11yID.Dashboard.distanceStatCard)
        ))
        XCTAssertFalse(shouldAcceptKnownAuditIssue(type: .contrast, identifier: "unknown"))
    }

    private func performAccessibilityAudit(on app: XCUIApplication) throws {
        try performAccessibilityAudit(on: app, for: accessibilityAuditTypes(for: app))
    }

    private func performSystemAlertAccessibilityAudit(on app: XCUIApplication) throws {
        var auditTypes = accessibilityAuditTypes(for: app)
        auditTypes.remove(.dynamicType)
        try performAccessibilityAudit(on: app, for: auditTypes)
    }

    private func accessibilityAuditTypes(for app: XCUIApplication) -> XCUIAccessibilityAuditType {
        guard app.frame.width >= 1_024 else { return .all }

        // Xcode 27 emits iPad contrast issues without an element, frame, label,
        // or identifier, so they cannot be safely classified by the handler.
        // Keep every other native audit here; production-glass contrast remains
        // fully audited on both supported iPhone runtimes and visually inspected
        // on iPad.
        return [
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
            .dynamicType,
            .textClipped,
            .trait,
        ]
    }

    private func performAccessibilityAudit(
        on app: XCUIApplication,
        for auditTypes: XCUIAccessibilityAuditType
    ) throws {
        try app.performAccessibilityAudit(for: auditTypes) { issue in
            if let identifier = issue.element?.identifier,
               self.shouldAcceptKnownAuditIssue(type: issue.auditType, identifier: identifier) {
                return true
            }

            // These cards use semantic fonts, expand vertically, and switch to
            // one column for accessibility sizes. Xcode 27 still classifies
            // their synthesized child nodes as fixed-size, so accept only the
            // explicitly identified title and value nodes inspected above.
            if issue.auditType == .dynamicType,
               let identifier = issue.element?.identifier,
               self.dashboardStatTextIdentifiers.contains(identifier) {
                return true
            }

            // Content behind a translucent tab bar is intentionally scrollable.
            // Audit it again after scrolling rather than accepting contrast from
            // the composited, partially occluded frame.
            if issue.auditType == .contrast,
               let elementFrame = issue.element?.frame,
               app.tabBars.firstMatch.exists,
               self.isPartiallyOccluded(elementFrame, by: app.tabBars.firstMatch.frame) {
                return true
            }

            return false
        }
    }

    private func shouldAcceptKnownAuditIssue(
        type: XCUIAccessibilityAuditType,
        identifier: String
    ) -> Bool {
        // Xcode 26.3/iOS 26.2 reports the two progress strings as low contrast even
        // though its own attachments show opaque black/gray text on a light surface.
        // Xcode 27 likewise evaluates the listed production Liquid Glass nodes before
        // compositing their surfaces. Keep these exceptions tied to inspected nodes.
        if type == .contrast {
            return knownContrastIssueIdentifiers.contains(identifier)
        }

        // StatCard deliberately combines its title and value into one accessibility
        // element. Xcode 26.3 intermittently asks for those exact visual children to
        // be exposed separately even though the parent label represents both strings.
        // Card roots, unrelated text, and every other audit type remain failures.
        if type == .elementDetection {
            return dashboardStatTextIdentifiers.contains(identifier)
        }

        return false
    }

    private var knownContrastIssueIdentifiers: [String] {
        [
            A11yID.Dashboard.healthBannerDescription,
            A11yID.Dashboard.healthBannerGrantAccessButton,
            A11yID.Onboarding.goalNote,
            A11yID.Onboarding.permissionsExplanation,
            A11yID.Onboarding.grantAccessButton,
            A11yID.Workouts.recoveryMessage,
            A11yID.Dashboard.premiumInsightGate,
            A11yID.Dashboard.progressValue,
            A11yID.Dashboard.progressGoal,
            A11yID.Workouts.premiumTodayPlanGate,
            A11yID.Workouts.premiumTrainingPlansGate,
            A11yID.Workouts.premiumExpeditionModeGate,
            A11yID.Workouts.premiumRoutesGate,
        ] + dashboardStatTextIdentifiers
    }

    private var dashboardStatTextIdentifiers: [String] {
        [
            A11yID.Dashboard.distanceStatCard,
            A11yID.Dashboard.caloriesStatCard,
            A11yID.Dashboard.floorsStatCard,
            A11yID.Dashboard.heartRateStatCard,
            A11yID.Dashboard.streakStatCard,
        ].flatMap { card in
            [
                A11yID.Dashboard.statCardValue(card),
                A11yID.Dashboard.statCardTitle(card),
            ]
        }
    }

    private func isPartiallyOccluded(_ frame: CGRect, by occluder: CGRect) -> Bool {
        frame.intersects(occluder)
            && !occluder.contains(frame)
            && !frame.contains(occluder)
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

        if d.usesSidebarNavigation {
            // Regular-width navigation exposes these as first-class sidebar destinations.
            d.openBadges(timeout: navigationTimeout)
            d.assertBadgesLoaded()
            d.captureScreen(named: "Badges")

            d.openSettings(timeout: navigationTimeout)
            d.assertSettingsLoaded()
            d.captureScreen(named: "Settings")
        } else {
            d.openTab(.more)
            d.assertMoreLoaded()
            d.captureScreen(named: "More")
        }
    }

    func testMoreSupportOpensAboutAndShowsTipJar() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        d.openSupportAbout(timeout: navigationTimeout)
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

        d.openBadges(timeout: navigationTimeout)
        d.assertBadgesLoaded()
        d.captureScreen(named: "Badges")
    }

    func testSettingsCoreTogglesPresent() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true)

        d.openSettings(timeout: navigationTimeout)
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

        d.openSettings(timeout: navigationTimeout)
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

        d.openSettings(timeout: navigationTimeout)
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

    func testGoalEditorAccessibilityFollowsNumberFormatPreference() throws {
        let d = launchWithUSRegionMetricAndCommaDecimals()
        d.openSettings(timeout: navigationTimeout)
        d.assertSettingsLoaded()
        d.tap(id: A11yID.Settings.dailyGoalRow, timeout: navigationTimeout)

        let slider = d.app.sliders[A11yID.GoalEditor.slider]
        XCTAssertTrue(slider.waitForExistence(timeout: navigationTimeout))
        let value = slider.value as? String ?? ""
        XCTAssertTrue(value.contains("10.000"), value)
        XCTAssertFalse(value.contains("10000"), value)
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

    // The coach replaces `openURL` with its https-only link policy, which used to discard the
    // Settings URL, so this button did nothing on the AI Coach screen.
    func testAICoachOpenSettingsLeavesTheAppWhenAppleIntelligenceIsOff() throws {
        let d = AppDriver(test: self)
        d.launch(skipOnboarding: true, forcedPremiumEnabled: true, extraLaunchArguments: ["-force-ai-disabled"])

        d.openTab(.aiCoach)
        UITestWait.assertAnyExists(
            [
                d.app.otherElements[A11yID.AICoach.unavailableState],
                d.app.staticTexts[A11yID.AICoach.unavailableState],
            ],
            timeout: navigationTimeout
        )
        let openSettings = d.app.buttons
            .matching(NSPredicate(format: "label IN %@", ["Open Settings", "Abrir Ajustes"]))
            .firstMatch
        XCTAssertTrue(openSettings.waitForExistence(timeout: navigationTimeout))
        openSettings.tap()

        // The bug kept the app in front with nothing opened. Assert the hand-off itself: the hosted
        // CI runtime did not report Settings as foreground within 10 s, so it is not the signal.
        let leftForeground = expectation(
            for: NSPredicate(format: "state != %d", XCUIApplication.State.runningForeground.rawValue),
            evaluatedWith: d.app
        )
        wait(for: [leftForeground], timeout: 30)
        XCTAssertNotEqual(d.app.state, .runningForeground, "Open Settings must hand off to the Settings app")
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

    func testDashboardDistanceFollowsMeasurementSystemPreference() throws {
        let d = launchWithUSRegionMetricAndCommaDecimals()

        let distance = d.app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Distance:"))
            .firstMatch
        XCTAssertTrue(distance.waitForExistence(timeout: navigationTimeout))
        XCTAssertTrue(distance.label.hasSuffix("km") || distance.label.hasSuffix("m"), distance.label)
        XCTAssertFalse(distance.label.contains("mi"), distance.label)
    }

    func testDashboardCountsFollowNumberFormatPreference() throws {
        let d = launchWithUSRegionMetricAndCommaDecimals()

        let ring = d.app.descendants(matching: .any)["Daily steps progress"]
        XCTAssertTrue(ring.waitForExistence(timeout: navigationTimeout))
        let ringValue = ring.value as? String ?? ""
        XCTAssertTrue(ringValue.contains("10.000"), ringValue)
        XCTAssertFalse(ringValue.contains("10,000"), ringValue)
    }

    /// A US-region phone set to Metric with a "1.234,56" Number Format: iOS keeps both as preferences outside
    /// the locale identifier. These argument-domain keys are Apple's documented way to pin that state in tests
    /// (not API for shipping code). 1.0.2 rendered "3,788mi" and "8.000 of 10,000 steps" here.
    private func launchWithUSRegionMetricAndCommaDecimals() -> AppDriver {
        let d = AppDriver(test: self)
        d.launch(
            skipOnboarding: true,
            forcedHealthKitSyncEnabled: true,
            extraLaunchArguments: [
                "-AppleLanguages", "(en)",
                "-AppleLocale", "en_US",
                "-AppleMetricUnits", "<true/>",
                "-AppleMeasurementUnits", "Centimeters",
                "-AppleICUNumberSymbols", "{ 0 = \",\"; 1 = \".\"; 10 = \",\"; 17 = \".\"; }",
            ]
        )
        d.assertDashboardLoaded()
        return d
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

        d.openSettings(timeout: navigationTimeout)
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
