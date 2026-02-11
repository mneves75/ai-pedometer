import XCTest
import CoreGraphics

@MainActor
final class AppDriver {
    enum MainTab: String {
        case dashboard
        case history
        case workouts
        case aiCoach
        case more
    }

    private unowned let test: XCTestCase
    let app: XCUIApplication

    init(test: XCTestCase, app: XCUIApplication = XCUIApplication()) {
        self.test = test
        self.app = app
    }

    func launch(skipOnboarding: Bool = true, forcedHealthKitSyncEnabled: Bool? = nil) {
        app.launchArguments.append(contentsOf: [
            "-ui-testing",
            "-reset-state",
        ])
        if skipOnboarding {
            app.launchArguments.append("-skip-onboarding")
        }
        if let forcedHealthKitSyncEnabled {
            app.launchArguments.append(forcedHealthKitSyncEnabled ? "-force-healthkit-sync-on" : "-force-healthkit-sync-off")
        }

        app.launchEnvironment["UI_TESTING"] = "1"
        // Mantem o demo deterministico estavel (CI/simulador).
        app.launchEnvironment["DEMO_DETERMINISTIC"] = "1"

        installSystemAlertMonitor()

        for attempt in 0..<2 {
            if attempt > 0 { app.terminate() }
            app.launch()
            _ = app.wait(for: .runningForeground, timeout: 12)
            app.activate()

            if skipOnboarding {
                if waitForMainShell(timeout: 8) { return }
            } else {
                if waitForOnboardingShell(timeout: 8) { return }
            }
        }

        // Last attempt: assert we reached the expected shell to make failures actionable.
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 12))
        if skipOnboarding {
            XCTAssertTrue(waitForMainShell(timeout: 12))
        } else {
            XCTAssertTrue(waitForOnboardingShell(timeout: 12))
        }
    }

    func waitForOnboardingShell(timeout: TimeInterval) -> Bool {
        // We don't rely on localized strings. Buttons are stable IDs in the app.
        let candidates: [XCUIElement] = [
            app.buttons["onboarding_next_button"],
            app.buttons["onboarding_get_started_button"],
        ]
        return UITestWait.firstExisting(candidates, timeout: timeout) != nil
    }

    func waitForMainShell(timeout: TimeInterval) -> Bool {
        let candidates: [XCUIElement] = [
            app.otherElements[A11yID.mainTabBar],
            app.otherElements[A11yID.mainSplitView],
        ]
        return UITestWait.firstExisting(candidates, timeout: timeout) != nil
    }

    func openTab(_ tab: MainTab) {
        let id = A11yID.tab(tab.rawValue)
        let expected = expectedMarkers(for: tab)

        for _ in 0..<3 {
            tap(id: id, timeout: 6)
            if UITestWait.firstExisting(expected, timeout: 2) != nil { return }
            app.activate()
        }

        UITestWait.assertAnyExists(expected, timeout: 2)
    }

    func tap(id: String, timeout: TimeInterval) {
        func candidates() -> [XCUIElement] {
            [
                app.buttons[id],
                app.cells[id],
                app.otherElements[id],
                app.staticTexts[id],
            ]
        }

        for attempt in 0..<3 {
            guard let el = UITestWait.firstExisting(candidates(), timeout: timeout) else {
                if attempt < 2 {
                    app.activate()
                    continue
                }
                XCTFail("Elemento nao encontrado para tap: \(id)")
                return
            }

            // Prefer coordinate taps from the app root to avoid stale-element flakes after interruption handling.
            if tapUsingAppCoordinatesIfPossible(element: el) {
                return
            }

            if el.isHittable {
                el.tap()
                return
            }

            if attempt < 2 {
                app.activate()
            }
        }

        XCTFail("Falha ao tocar no elemento '\(id)' apos retries.")
    }

    /// Scrolls until an element with the given identifier exists (best-effort).
    ///
    /// SwiftUI `List` is backed by `UITableView` and offscreen rows may not exist
    /// until scrolled into view.
    func scrollTo(id: String, maxSwipes: Int = 10) {
        func elementExists() -> Bool {
            let candidates: [XCUIElement] = [
                app.buttons[id],
                app.cells[id],
                app.otherElements[id],
                app.staticTexts[id],
                app.switches[id],
                app.sliders[id],
            ]
            return candidates.contains(where: { $0.exists })
        }

        if elementExists() { return }

        let scrollContainer: XCUIElement = {
            if app.tables.firstMatch.exists { return app.tables.firstMatch }
            if app.scrollViews.firstMatch.exists { return app.scrollViews.firstMatch }
            return app
        }()

        for _ in 0..<maxSwipes {
            scrollContainer.swipeUp()
            if elementExists() { return }
        }

        XCTFail("Nao foi possivel encontrar o elemento '\(id)' apos \(maxSwipes) swipes.")
    }

    func waitForMarker(prefix: String, timeout: TimeInterval) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)

        let candidates: [XCUIElement] = [
            app.otherElements.matching(predicate).firstMatch,
            app.staticTexts.matching(predicate).firstMatch,
        ]

        for candidate in candidates {
            if candidate.waitForExistence(timeout: timeout) {
                return candidate
            }
        }

        XCTFail("Nao foi possivel encontrar marker com prefixo '\(prefix)' em \(timeout)s.")
        return candidates.first!
    }

    func setSwitch(id: String, isOn desiredOn: Bool, timeout: TimeInterval) {
        let sw = app.switches[id]
        XCTAssertTrue(sw.waitForExistence(timeout: timeout))

        func normalized(_ value: Any?) -> String? {
            if let s = value as? String { return s }
            if let n = value as? NSNumber { return n.stringValue }
            return nil
        }

        let desired = desiredOn ? "1" : "0"
        for _ in 0..<3 {
            if normalized(sw.value) == desired { return }
            sw.tap()
        }

        XCTAssertEqual(normalized(sw.value), desired, "Switch '\(id)' nao atingiu estado esperado.")
    }

    func captureScreen(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name

        // E2E precisa de evidencias visuais (Carmack-level review).
        // Mantemos os screenshots mesmo em sucesso e exportamos via `xcresulttool`.
        attachment.lifetime = .keepAlways

        test.add(attachment)
    }

    // MARK: - Assertions

    func assertDashboardLoaded() {
        UITestWait.assertAnyExists(
            [
                app.otherElements[A11yID.Dashboard.view],
                app.scrollViews[A11yID.Dashboard.view],
            ],
            timeout: 8
        )
    }

    func assertHistoryLoaded() {
        UITestWait.assertAnyExists(
            [
                app.otherElements[A11yID.History.marker],
                app.staticTexts[A11yID.History.marker],
            ],
            timeout: 8
        )
    }

    func assertWorkoutsLoaded() {
        UITestWait.assertAnyExists(
            [
                app.scrollViews[A11yID.Workouts.scroll],
                app.otherElements[A11yID.Workouts.scroll],
                app.buttons[A11yID.Workouts.startWorkoutButton],
            ],
            timeout: 8
        )
    }

    func assertTrainingPlansLoaded() {
        UITestWait.assertAnyExists(
            [
                app.otherElements[A11yID.TrainingPlans.marker],
                app.staticTexts[A11yID.TrainingPlans.marker],
                app.scrollViews[A11yID.TrainingPlans.marker],
                app.tables[A11yID.TrainingPlans.marker],
                app.collectionViews[A11yID.TrainingPlans.marker],
                app.buttons[A11yID.TrainingPlans.createButton],
            ],
            timeout: 10
        )
    }

    func assertBadgesLoaded() {
        UITestWait.assertAnyExists(
            [
                app.otherElements[A11yID.Badges.marker],
                app.staticTexts[A11yID.Badges.marker],
                app.scrollViews[A11yID.Badges.marker],
            ],
            timeout: 10
        )
    }

    func assertAboutLoaded() {
        UITestWait.assertAnyExists(
            [
                app.scrollViews[A11yID.About.view],
                app.otherElements[A11yID.About.view],
            ],
            timeout: 8
        )
    }

    func assertMoreLoaded() {
        UITestWait.assertAnyExists(
            [
                // Marker sempre presente em modo UI testing.
                app.otherElements[A11yID.More.marker],
                app.staticTexts[A11yID.More.marker],

                // Fallbacks: SwiftUI List/NavigationLink nem sempre expõe o identifier do row/cell.
                // Os identifiers do Label costumam ser muito mais estáveis.
                app.staticTexts[A11yID.More.settingsRowLabel],
                app.otherElements[A11yID.More.settingsRowLabel],
                app.staticTexts[A11yID.More.supportRowLabel],
                app.otherElements[A11yID.More.supportRowLabel],
                app.staticTexts[A11yID.More.badgesRowLabel],
                app.otherElements[A11yID.More.badgesRowLabel],
            ],
            timeout: 8
        )
    }

    func assertSettingsLoaded() {
        UITestWait.assertAnyExists(
            [
                // Marker sempre presente em modo UI testing.
                app.otherElements[A11yID.Settings.marker],
                app.staticTexts[A11yID.Settings.marker],

                // Fallback: o List nem sempre expõe identifier de forma estável.
                app.tables[A11yID.Settings.list],
                app.otherElements[A11yID.Settings.list],
                app.otherElements[A11yID.Settings.dailyGoalRow],
            ],
            timeout: 8
        )
    }

    // MARK: - Private

    private func expectedMarkers(for tab: MainTab) -> [XCUIElement] {
        switch tab {
        case .dashboard:
            return [
                app.otherElements[A11yID.Dashboard.view],
                app.scrollViews[A11yID.Dashboard.view],
            ]
        case .history:
            return [
                app.otherElements[A11yID.History.marker],
                app.staticTexts[A11yID.History.marker],
            ]
        case .workouts:
            return [
                app.scrollViews[A11yID.Workouts.scroll],
                app.otherElements[A11yID.Workouts.scroll],
                app.buttons[A11yID.Workouts.startWorkoutButton],
            ]
        case .aiCoach:
            return [
                app.otherElements[A11yID.AICoach.view],
                app.otherElements[A11yID.AICoach.marker],
                app.staticTexts[A11yID.AICoach.marker],
            ]
        case .more:
            return [
                app.otherElements[A11yID.More.marker],
                app.staticTexts[A11yID.More.marker],
                app.staticTexts[A11yID.More.settingsRowLabel],
                app.otherElements[A11yID.More.settingsRowLabel],
            ]
        }
    }

    private func tapUsingAppCoordinatesIfPossible(element: XCUIElement) -> Bool {
        guard element.exists else { return false }

        let appFrame = app.frame
        let frame = element.frame
        guard appFrame.width > 0, appFrame.height > 0 else { return false }
        guard !frame.isEmpty else { return false }

        let midX = frame.midX
        let midY = frame.midY
        guard midX.isFinite, midY.isFinite else { return false }

        let normalized = CGVector(
            dx: (midX - appFrame.minX) / appFrame.width,
            dy: (midY - appFrame.minY) / appFrame.height
        )
        guard normalized.dx >= 0, normalized.dx <= 1, normalized.dy >= 0, normalized.dy <= 1 else {
            return false
        }

        app.coordinate(withNormalizedOffset: normalized).tap()
        return true
    }

    private func installSystemAlertMonitor() {
        test.addUIInterruptionMonitor(withDescription: "System Dialog") { alert in
            let allowCandidates = [
                "Allow",
                "Allow While Using App",
                "OK",
                "Permitir",
                "Permitir ao usar o app",
                "OK",
            ]
            for title in allowCandidates {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }

            let denyCandidates = ["Don’t Allow", "Don't Allow", "Nao Permitir", "Não Permitir"]
            for title in denyCandidates {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }

            return false
        }
    }
}
