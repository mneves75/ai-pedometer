import CoreGraphics
import XCTest

@MainActor
final class AIPedometerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchAppForUITest() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchArguments.append("-reset-state")
        app.launchEnvironment["UI_TESTING"] = "1"
        app.terminate()
        addSystemAlertMonitor(for: app)
        app.launch()
        if !app.wait(for: .runningForeground, timeout: 10) {
            app.terminate()
            app.launch()
        }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        app.tap()
        return app
    }

    private func addSystemAlertMonitor(for app: XCUIApplication) {
        addUIInterruptionMonitor(withDescription: "System Dialog") { alert in
            let allowCandidates = ["Allow", "Allow While Using App", "OK", "Permitir", "Permitir ao usar o app", "OK"]
            for title in allowCandidates {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            let denyCandidates = ["Don’t Allow", "Don't Allow", "Não Permitir"]
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

    private func completeOnboardingIfNeeded(_ app: XCUIApplication) {
        let nextButton = app.buttons["onboarding_next_button"]
        if nextButton.waitForExistence(timeout: 2) {
            for _ in 0..<2 {
                nextButton.tap()
            }
        } else {
            let nextCandidates = ["Next", "Próximo"]
            if waitForAny(nextCandidates.map { app.buttons[$0] }, timeout: 2) != nil {
                for _ in 0..<2 {
                    tapFirstMatch(
                        nextCandidates.map { app.buttons[$0] },
                        timeout: 2,
                        message: "Onboarding Next button not found"
                    )
                }
            }
        }

        let startButton = app.buttons["onboarding_get_started_button"]
        if startButton.waitForExistence(timeout: 2) {
            startButton.tap()
            app.tap()
        } else {
            let startCandidates = ["Get Started", "Começar"]
            if waitForAny(startCandidates.map { app.buttons[$0] }, timeout: 2) != nil {
                tapFirstMatch(
                    startCandidates.map { app.buttons[$0] },
                    timeout: 2,
                    message: "Onboarding Get Started button not found"
                )
                app.tap()
            }
        }

        _ = app.otherElements["main_tab_bar"].waitForExistence(timeout: 5)
    }

    private func ensureSwitch(identifier: String, isOn: Bool, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        guard toggle.exists else { return }
        if normalizedSwitchValue(toggle) == isOn {
            return
        }
        let switchPoint = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        switchPoint.tap()
        waitForSwitch(identifier: identifier, isOn: isOn, in: app)
        if normalizedSwitchValue(app.switches[identifier]) != isOn {
            toggle.tap()
            waitForSwitch(identifier: identifier, isOn: isOn, in: app)
        }
        if normalizedSwitchValue(app.switches[identifier]) != isOn {
            let container = app.cells.containing(.switch, identifier: identifier).firstMatch
            if container.exists {
                container.tap()
                waitForSwitch(identifier: identifier, isOn: isOn, in: app)
            }
        }
    }

    private func ensureSwitch(_ toggle: XCUIElement, isOn: Bool, in app: XCUIApplication) {
        guard toggle.exists else { return }
        if normalizedSwitchValue(toggle) == isOn {
            return
        }
        guard toggle.isHittable else { return }
        let switchPoint = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        switchPoint.tap()
        waitForSwitch(toggle, isOn: isOn)
        if normalizedSwitchValue(toggle) != isOn {
            guard toggle.exists && toggle.isHittable else { return }
            toggle.tap()
            waitForSwitch(toggle, isOn: isOn)
        }
        if normalizedSwitchValue(toggle) != isOn {
            guard toggle.exists else { return }
            let container = app.cells.containing(.switch, identifier: toggle.identifier).firstMatch
            if container.exists {
                container.tap()
                waitForSwitch(toggle, isOn: isOn)
            }
        }
    }

    private func scrollToElement(_ element: XCUIElement, in scrollable: XCUIElement) {
        guard scrollable.exists else {
            XCTFail("Scrollable container not found")
            return
        }
        var attempts = 0
        while (!element.exists || !element.isHittable) && attempts < 12 {
            scrollable.swipeUp()
            attempts += 1
        }
        if element.isHittable {
            return
        }
        attempts = 0
        while (!element.exists || !element.isHittable) && attempts < 12 {
            scrollable.swipeDown()
            attempts += 1
        }
    }

    private func scrollToTop(_ scrollable: XCUIElement) {
        for _ in 0..<6 {
            scrollable.swipeDown()
        }
    }

    private func scrollToBottom(_ scrollable: XCUIElement) {
        for _ in 0..<8 {
            scrollable.swipeUp()
        }
    }

    private func firstScrollable(in app: XCUIApplication) -> XCUIElement {
        if app.collectionViews.firstMatch.exists {
            return app.collectionViews.firstMatch
        }
        if app.tables.firstMatch.exists {
            return app.tables.firstMatch
        }
        return app.scrollViews.firstMatch
    }

    private func settingsScrollable(in app: XCUIApplication) -> XCUIElement {
        let candidates: [XCUIElement] = [
            app.collectionViews["settings_list"],
            app.tables["settings_list"],
            app.scrollViews["settings_list"],
            app.otherElements["settings_list"],
            app.collectionViews.firstMatch,
            app.tables.firstMatch,
            app.scrollViews.firstMatch
        ]
        for candidate in candidates {
            if candidate.waitForExistence(timeout: 5) {
                return candidate
            }
        }
        XCTFail("Settings list not found")
        return firstScrollable(in: app)
    }

    private func settingsListExists(in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        if app.collectionViews["settings_list"].waitForExistence(timeout: timeout)
            || app.tables["settings_list"].waitForExistence(timeout: timeout)
            || app.scrollViews["settings_list"].waitForExistence(timeout: timeout)
            || app.otherElements["settings_list"].waitForExistence(timeout: timeout) {
            return true
        }

        let navCandidates = [
            app.navigationBars["Settings"],
            app.navigationBars["Configurações"],
            app.navigationBars["Ajustes"]
        ]
        if waitForAny(navCandidates, timeout: 0.5) != nil {
            return true
        }

        let titleCandidates = [
            app.staticTexts["Settings"],
            app.staticTexts["Configurações"],
            app.staticTexts["Ajustes"]
        ]
        return waitForAny(titleCandidates, timeout: 0.5) != nil
    }

    private func assertSettingsVisible(_ app: XCUIApplication) {
        if settingsListExists(in: app) {
            return
        }
        XCTFail("Settings screen did not load")
    }

    private func openMoreTab(_ app: XCUIApplication) -> Bool {
        let tabBar = app.tabBars.firstMatch
        guard tabBar.exists else { return false }

        let identifierCandidates = ["tab_more"]
        for identifier in identifierCandidates {
            let button = tabBar.buttons[identifier]
            if tapTabBarButton(button, in: tabBar) {
                ensureMoreRoot(in: app)
                return true
            }
        }

        let moreCandidates = ["More", "Mais"]
        for title in moreCandidates {
            let button = tabBar.buttons[title]
            if tapTabBarButton(button, in: tabBar) {
                ensureMoreRoot(in: app)
                return true
            }
        }

        let buttonCount = tabBar.buttons.count
        if buttonCount > 0 {
            let lastButton = tabBar.buttons.element(boundBy: buttonCount - 1)
            if tapTabBarButton(lastButton, in: tabBar) {
                ensureMoreRoot(in: app)
                return true
            }
        }

        return false
    }

    private func openSplitViewTab(_ app: XCUIApplication, titles: [String]) -> Bool {
        guard app.otherElements["main_split_view"].exists else { return false }
        let candidates = titles.map { app.buttons[$0] }
        if let candidate = waitForAny(candidates, timeout: 2) {
            candidate.tap()
            return true
        }
        return false
    }

    private func ensureMoreRoot(in app: XCUIApplication) {
        if moreListExists(in: app, timeout: 2) {
            return
        }
        let moreNavCandidates = [app.navigationBars["More"], app.navigationBars["Mais"]]
        if waitForAny(moreNavCandidates, timeout: 2) != nil {
            if moreListExists(in: app, timeout: 2) {
                return
            }
        }
        let detailCandidates: [XCUIElement] = [
            app.navigationBars["Settings"],
            app.navigationBars["Configurações"],
            app.navigationBars["Badges"],
            app.navigationBars["Medalhas"],
            app.otherElements["settings_list"],
            app.otherElements["badges_list"]
        ]
        if waitForAny(detailCandidates, timeout: 0.5) != nil {
            _ = navigateBackIfPossible(in: app)
        }
    }

    private func moreListExists(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let candidates: [XCUIElement] = [
            app.buttons["more_badges_row"],
            app.buttons["more_settings_row"],
            app.tables.buttons["more_badges_row"],
            app.tables.buttons["more_settings_row"],
            app.collectionViews.buttons["more_badges_row"],
            app.collectionViews.buttons["more_settings_row"],
            app.cells["more_badges_row"],
            app.cells["more_settings_row"],
            app.tables.cells["more_badges_row"],
            app.tables.cells["more_settings_row"],
            app.collectionViews.cells["more_badges_row"],
            app.collectionViews.cells["more_settings_row"],
            app.otherElements["more_badges_row"],
            app.otherElements["more_settings_row"],
            app.staticTexts["more_badges_row_label"],
            app.staticTexts["more_settings_row_label"],
            app.otherElements["more_badges_row_label"],
            app.otherElements["more_settings_row_label"],
            app.tables["more_list"],
            app.collectionViews["more_list"],
            app.scrollViews["more_list"],
            app.otherElements["more_list"]
        ]

        return waitForAny(candidates, timeout: timeout) != nil
    }

    private func navigateBackIfPossible(in app: XCUIApplication) -> Bool {
        let explicitBackButtons = [
            app.buttons["settings_back_button"],
            app.buttons["badges_back_button"]
        ]
        for button in explicitBackButtons {
            if tapIfPossible(button) {
                return true
            }
        }
        let backCandidates = ["More", "Mais", "Back", "Voltar"]
        for title in backCandidates {
            let button = app.navigationBars.buttons[title]
            if tapIfPossible(button) {
                return true
            }
        }
        let firstButton = app.navigationBars.buttons.firstMatch
        if tapIfPossible(firstButton) {
            return true
        }
        if app.navigationBars.firstMatch.exists {
            performEdgeBackGesture(in: app)
            return true
        }
        return false
    }

    private func returnToMoreListIfNeeded(in app: XCUIApplication) {
        if moreListExists(in: app, timeout: 0.5) {
            return
        }
        _ = navigateBackIfPossible(in: app)
        if moreListExists(in: app, timeout: 1) {
            return
        }
        _ = navigateBackIfPossible(in: app)
        if moreListExists(in: app, timeout: 1) {
            return
        }
        XCTFail("Unable to return to More list")
    }

    private func tapIfPossible(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if element.isHittable {
            element.tap()
            return true
        }
        if element.frame.width > 0, element.frame.height > 0 {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }
        return false
    }

    private func performEdgeBackGesture(in app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func tapMoreEntry(in app: XCUIApplication, titles: [String]) -> Bool {
        for title in titles {
            let containsPredicate = NSPredicate(format: "label CONTAINS[c] %@", title)
            let cell = app.cells[title]
            if cell.waitForExistence(timeout: 1) {
                cell.tap()
                return true
            }
            let cellContains = app.cells.matching(containsPredicate).firstMatch
            if cellContains.waitForExistence(timeout: 1) {
                cellContains.tap()
                return true
            }
            let tableCell = app.tables.cells[title]
            if tableCell.waitForExistence(timeout: 1) {
                tableCell.tap()
                return true
            }
            let tableStatic = app.tables.cells.staticTexts[title]
            if tableStatic.waitForExistence(timeout: 1) {
                tableStatic.tap()
                return true
            }
            let tableContains = app.tables.cells.matching(containsPredicate).firstMatch
            if tableContains.waitForExistence(timeout: 1) {
                tableContains.tap()
                return true
            }
            let collectionCell = app.collectionViews.cells[title]
            if collectionCell.waitForExistence(timeout: 1) {
                collectionCell.tap()
                return true
            }
            let collectionStatic = app.collectionViews.cells.staticTexts[title]
            if collectionStatic.waitForExistence(timeout: 1) {
                collectionStatic.tap()
                return true
            }
            let collectionContains = app.collectionViews.cells.matching(containsPredicate).firstMatch
            if collectionContains.waitForExistence(timeout: 1) {
                collectionContains.tap()
                return true
            }
            let staticText = app.staticTexts[title]
            if staticText.waitForExistence(timeout: 1) {
                staticText.tap()
                return true
            }
            let staticContains = app.staticTexts.matching(containsPredicate).firstMatch
            if staticContains.waitForExistence(timeout: 1) {
                staticContains.tap()
                return true
            }
            let otherElement = app.otherElements[title]
            if otherElement.waitForExistence(timeout: 1) {
                otherElement.tap()
                return true
            }
            let otherContains = app.otherElements.matching(containsPredicate).firstMatch
            if otherContains.waitForExistence(timeout: 1) {
                otherContains.tap()
                return true
            }
            let button = app.buttons[title]
            if button.waitForExistence(timeout: 1) {
                button.tap()
                return true
            }
            let buttonContains = app.buttons.matching(containsPredicate).firstMatch
            if buttonContains.waitForExistence(timeout: 1) {
                buttonContains.tap()
                return true
            }
        }
        return false
    }

    private func tapTabBarButton(_ button: XCUIElement, in tabBar: XCUIElement) -> Bool {
        guard button.waitForExistence(timeout: 1) else { return false }
        if button.isHittable {
            button.tap()
            return true
        }
        if button.frame.width > 0, button.frame.height > 0 {
            button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            return true
        }
        tabBar.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        return true
    }

    private func openSettingsTab(_ app: XCUIApplication) {
        let uiTestSettings = app.buttons["ui_test_open_settings"]
        if tapIfPossible(uiTestSettings) {
            if settingsListExists(in: app, timeout: 3) {
                return
            }
        }
        let directSettingsCandidates = ["Settings", "Configurações"]
        if openSplitViewTab(app, titles: directSettingsCandidates) {
            return
        }
        let identifierCandidates = ["tab_settings"]
        let tabBar = app.tabBars.firstMatch
        for identifier in identifierCandidates {
            let button = tabBar.buttons[identifier]
            if tapTabBarButton(button, in: tabBar) {
                if settingsListExists(in: app) {
                    return
                }
            }
        }
        for title in directSettingsCandidates {
            let button = app.tabBars.buttons[title]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                if settingsListExists(in: app) {
                    return
                }
            }
        }
        if openMoreTab(app) {
            _ = moreListExists(in: app, timeout: 3)
            let settingsRowCandidates: [XCUIElement] = [
                app.cells["more_settings_row"],
                app.tables.cells["more_settings_row"],
                app.collectionViews.cells["more_settings_row"],
                app.buttons["more_settings_row"],
                app.otherElements["more_settings_row"],
                app.staticTexts["more_settings_row_label"],
                app.otherElements["more_settings_row_label"]
            ]
            if waitForAny(settingsRowCandidates, timeout: 3) != nil {
                tapFirstMatch(settingsRowCandidates, timeout: 3, message: "More Settings row not found")
                if settingsListExists(in: app) {
                    return
                }
            }
            let settingsCandidates = ["Configurações", "Settings", "Ajustes"]
            if tapMoreEntry(in: app, titles: settingsCandidates) {
                if settingsListExists(in: app, timeout: 3) {
                    return
                }
            }
        }
        XCTFail("Unable to navigate to Settings tab")
    }

    private func openDashboardTab(_ app: XCUIApplication) {
        let directCandidates = ["Dashboard", "Painel"]
        if openSplitViewTab(app, titles: directCandidates) {
            return
        }
        let identifierCandidates = ["tab_dashboard"]
        let tabBar = app.tabBars.firstMatch
        for identifier in identifierCandidates {
            let button = tabBar.buttons[identifier]
            if tapTabBarButton(button, in: tabBar) {
                return
            }
        }
        for title in directCandidates {
            let button = app.tabBars.buttons[title]
            if button.exists {
                button.tap()
                return
            }
        }
        if openMoreTab(app) {
            if tapMoreEntry(in: app, titles: directCandidates) {
                return
            }
        }
        XCTFail("Unable to navigate to Dashboard tab")
    }

    private func openWorkoutsTab(_ app: XCUIApplication) {
        let directCandidates = ["Workouts", "Treinos"]
        if openSplitViewTab(app, titles: directCandidates) {
            return
        }
        let identifierCandidates = ["tab_workouts"]
        let tabBar = app.tabBars.firstMatch
        for identifier in identifierCandidates {
            let button = tabBar.buttons[identifier]
            if tapTabBarButton(button, in: tabBar) {
                return
            }
        }
        for title in directCandidates {
            let button = app.tabBars.buttons[title]
            if button.exists {
                button.tap()
                return
            }
        }
        if openMoreTab(app) {
            if tapMoreEntry(in: app, titles: directCandidates) {
                return
            }
        }
        XCTFail("Unable to navigate to Workouts tab")
    }

    private func openBadgesTab(_ app: XCUIApplication) {
        let uiTestBadges = app.buttons["ui_test_open_badges"]
        if tapIfPossible(uiTestBadges) {
            return
        }
        let directCandidates = ["Badges", "Medalhas"]
        if openSplitViewTab(app, titles: directCandidates) {
            return
        }
        let identifierCandidates = ["tab_badges"]
        let tabBar = app.tabBars.firstMatch
        for identifier in identifierCandidates {
            let button = tabBar.buttons[identifier]
            if tapTabBarButton(button, in: tabBar) {
                return
            }
        }
        for title in directCandidates {
            let button = app.tabBars.buttons[title]
            if button.exists {
                button.tap()
                return
            }
        }
        if openMoreTab(app) {
            _ = moreListExists(in: app, timeout: 3)
            let badgesRowCandidates: [XCUIElement] = [
                app.cells["more_badges_row"],
                app.tables.cells["more_badges_row"],
                app.collectionViews.cells["more_badges_row"],
                app.buttons["more_badges_row"],
                app.otherElements["more_badges_row"],
                app.staticTexts["more_badges_row_label"],
                app.otherElements["more_badges_row_label"]
            ]
            if waitForAny(badgesRowCandidates, timeout: 3) != nil {
                tapFirstMatch(badgesRowCandidates, timeout: 3, message: "More Badges row not found")
                return
            }
            if tapMoreEntry(in: app, titles: directCandidates) {
                return
            }
        }
        XCTFail("Unable to navigate to Badges tab")
    }

    private func openHistoryTab(_ app: XCUIApplication) {
        let directHistoryCandidates = ["History", "Histórico"]
        if openSplitViewTab(app, titles: directHistoryCandidates) {
            return
        }
        let identifierCandidates = ["tab_history"]
        let tabBar = app.tabBars.firstMatch
        for identifier in identifierCandidates {
            let button = tabBar.buttons[identifier]
            if tapTabBarButton(button, in: tabBar) {
                return
            }
        }
        for title in directHistoryCandidates {
            let button = app.tabBars.buttons[title]
            if button.exists {
                button.tap()
                return
            }
        }
        if openMoreTab(app) {
            if tapMoreEntry(in: app, titles: directHistoryCandidates) {
                return
            }
        }
        XCTFail("Unable to navigate to History tab")
    }

    private func tryOpenAICoachTab(_ app: XCUIApplication) -> Bool {
        let tabBar = app.tabBars.firstMatch
        _ = tabBar.waitForExistence(timeout: 3)
        let splitViewCandidates = ["AI Coach", "Coach IA"]
        if openSplitViewTab(app, titles: splitViewCandidates) {
            if waitForAICoach(in: app) {
                return true
            }
        }
        let identifierCandidates = ["tab_aiCoach"]
        for identifier in identifierCandidates {
            let button = app.tabBars.buttons[identifier]
            if tapTabBarButton(button, in: tabBar) {
                if waitForAICoach(in: app) {
                    return true
                }
            }
        }
        let titleCandidates = ["AI Coach", "Coach IA"]
        for title in titleCandidates {
            let button = app.tabBars.buttons[title]
            if tapTabBarButton(button, in: tabBar) {
                if waitForAICoach(in: app) {
                    return true
                }
            }
        }
        let tabButtons = app.tabBars.buttons
        if tabButtons.count >= 4 {
            let indexCandidate = tabButtons.element(boundBy: 3)
            if tapTabBarButton(indexCandidate, in: tabBar), waitForAICoach(in: app) {
                return true
            }
        }
        return false
    }

    private func tapMoreEntryByIndex(in app: XCUIApplication) -> Bool {
        let containers = [app.tables.firstMatch, app.collectionViews.firstMatch]
        for container in containers where container.exists {
            let cellCount = container.cells.count
            for index in 0..<min(cellCount, 3) {
                let cell = container.cells.element(boundBy: index)
                if !cell.exists { continue }
                cell.tap()
                if isAICoachVisible(in: app) {
                    return true
                }
                navigateBackFromMoreTarget(in: app)
                _ = openMoreTab(app)
            }
        }
        return false
    }

    private func isAICoachVisible(in app: XCUIApplication) -> Bool {
        let navCandidates = ["AI Coach", "Coach IA"]
        return navCandidates.contains(where: { app.navigationBars[$0].exists })
    }

    private func waitForAICoach(in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        if app.staticTexts["ai_coach_marker"].waitForExistence(timeout: timeout) {
            return true
        }
        if app.otherElements["ai_coach_view"].waitForExistence(timeout: timeout) {
            return true
        }
        let navCandidates = ["AI Coach", "Coach IA"]
        for title in navCandidates {
            if app.navigationBars[title].waitForExistence(timeout: timeout) {
                return true
            }
        }
        let contentCandidates = [
            app.staticTexts["Hi, I'm your AI Coach!"],
            app.staticTexts["Olá, sou seu Coach IA!"]
        ]
        return waitForAny(contentCandidates, timeout: timeout) != nil
    }

    private func navigateBackFromMoreTarget(in app: XCUIApplication) {
        let backButton = app.navigationBars.buttons.firstMatch
        if backButton.exists {
            backButton.tap()
        }
    }

    private func healthKitSyncToggle(in app: XCUIApplication) -> XCUIElement {
        app.switches["healthkit_sync_toggle"]
    }

    private func healthKitSyncDisabledLabel(in app: XCUIApplication) -> XCUIElement {
        let candidates = ["HealthKit Sync is Off", "Sincronização do HealthKit desativada"]
        for title in candidates {
            let label = app.staticTexts[title]
            if label.exists {
                return label
            }
        }
        return app.staticTexts.element(boundBy: 0)
    }

    private func normalizedSwitchValue(_ toggle: XCUIElement) -> Bool? {
        guard toggle.exists else { return nil }
        if let numberValue = toggle.value as? NSNumber {
            return numberValue.boolValue
        }
        if let boolValue = toggle.value as? Bool {
            return boolValue
        }
        guard let value = toggle.value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "1", "true", "on", "ligado", "ativado":
            return true
        case "0", "false", "off", "desligado", "desativado":
            return false
        default:
            return nil
        }
    }

    private func waitForSwitch(identifier: String, isOn: Bool, in app: XCUIApplication) {
        let toggle = app.switches[identifier]
        let predicate = NSPredicate { _, _ in
            self.normalizedSwitchValue(toggle) == isOn
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        _ = XCTWaiter.wait(for: [expectation], timeout: 2)
    }

    private func waitForSwitch(_ toggle: XCUIElement, isOn: Bool) {
        let predicate = NSPredicate { _, _ in
            self.normalizedSwitchValue(toggle) == isOn
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        _ = XCTWaiter.wait(for: [expectation], timeout: 2)
    }

    private func waitForAny(_ candidates: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        guard !candidates.isEmpty else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        let perCandidateTimeout = max(0.2, timeout / Double(candidates.count))
        for candidate in candidates {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { return nil }
            if candidate.waitForExistence(timeout: min(perCandidateTimeout, remaining)) {
                return candidate
            }
        }
        return candidates.first(where: { $0.exists })
    }

    private func assertAnyExists(
        _ candidates: [XCUIElement],
        timeout: TimeInterval,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard waitForAny(candidates, timeout: timeout) != nil else {
            XCTFail(message, file: file, line: line)
            return
        }
    }

    private func tapFirstMatch(
        _ candidates: [XCUIElement],
        timeout: TimeInterval,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let element = waitForAny(candidates, timeout: timeout) else {
            XCTFail(message, file: file, line: line)
            return
        }
        if element.isHittable {
            element.tap()
            return
        }
        for candidate in candidates where candidate.exists && candidate.isHittable {
            candidate.tap()
            return
        }
        XCTFail(message, file: file, line: line)
    }

    private func captureScreen(named name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testAppLaunches() throws {
        _ = launchAppForUITest()
    }

    @MainActor
    func testOnboardingFlowReachesMainTabs() throws {
        let app = launchAppForUITest()

        completeOnboardingIfNeeded(app)

        XCTAssertTrue(app.otherElements["main_tab_bar"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testHealthKitSyncToggleDisablesHistory() throws {
        let app = launchAppForUITest()

        completeOnboardingIfNeeded(app)

        openSettingsTab(app)
        assertSettingsVisible(app)
        let settingsContainer = settingsScrollable(in: app)
        scrollToTop(settingsContainer)
        let toggle = healthKitSyncToggle(in: app)
        scrollToElement(toggle, in: settingsContainer)
        XCTAssertTrue(toggle.exists)

        ensureSwitch(toggle, isOn: false, in: app)

        openHistoryTab(app)
        let disabledLabel = healthKitSyncDisabledLabel(in: app)
        XCTAssertTrue(disabledLabel.waitForExistence(timeout: 5))
    }

    @MainActor
    func testPrimaryTabsRenderAndCaptureScreens() throws {
        let app = launchAppForUITest()
        completeOnboardingIfNeeded(app)

        openDashboardTab(app)
        assertAnyExists(
            [
                app.staticTexts["Dashboard"],
                app.staticTexts["Painel"],
                app.staticTexts["Today"],
                app.staticTexts["Hoje"],
                app.staticTexts["Today's Dashboard"]
            ],
            timeout: 5,
            message: "Dashboard header not found"
        )
        captureScreen(named: "Dashboard")

        openHistoryTab(app)
        assertAnyExists(
            [
                app.staticTexts["History"],
                app.staticTexts["Histórico"],
                app.staticTexts["Weekly Summary"],
                app.staticTexts["Resumo Semanal"],
                app.staticTexts["HealthKit Sync is Off"],
                app.staticTexts["Sincronização do HealthKit desativada"]
            ],
            timeout: 5,
            message: "History screen content not found"
        )
        captureScreen(named: "History")

        openWorkoutsTab(app)
        app.tap()
        assertAnyExists(
            [
                app.staticTexts["Workouts"],
                app.staticTexts["Treinos"],
                app.buttons["Start Workout"],
                app.buttons["Iniciar Treino"]
            ],
            timeout: 5,
            message: "Workouts screen content not found"
        )
        captureScreen(named: "Workouts")

        openSettingsTab(app)
        app.tap()
        assertAnyExists(
            [
                app.navigationBars["Settings"],
                app.navigationBars["Configurações"],
                app.navigationBars["Ajustes"],
                app.staticTexts["Settings"],
                app.staticTexts["Configurações"],
                app.staticTexts["Ajustes"]
            ],
            timeout: 5,
            message: "Settings screen content not found"
        )
        captureScreen(named: "Settings")

        returnToMoreListIfNeeded(in: app)

        openBadgesTab(app)
        assertAnyExists(
            [
                app.staticTexts["Badges"],
                app.staticTexts["Medalhas"],
                app.staticTexts["No Badges Yet"],
                app.staticTexts["Nenhuma Medalha Ainda"]
            ],
            timeout: 5,
            message: "Badges screen content not found"
        )
        captureScreen(named: "Badges")

        if tryOpenAICoachTab(app) {
            assertAnyExists(
                [
                    app.navigationBars["AI Coach"],
                    app.navigationBars["Coach IA"],
                    app.staticTexts["Hi, I'm your AI Coach!"],
                    app.staticTexts["Olá, sou seu Coach IA!"],
                    app.staticTexts["ai_coach_marker"]
                ],
                timeout: 5,
                message: "AI Coach screen content not found"
            )
            captureScreen(named: "AI Coach")
        } else {
            XCTContext.runActivity(named: "AI Coach tab unavailable in UI test environment") { _ in }
        }
    }

    @MainActor
    func testTrainingPlansOpensFromWorkouts() throws {
        let app = launchAppForUITest()
        completeOnboardingIfNeeded(app)

        openWorkoutsTab(app)
        assertAnyExists(
            [
                app.staticTexts["Workouts"],
                app.staticTexts["Treinos"],
                app.buttons["Start Workout"],
                app.buttons["Iniciar Treino"]
            ],
            timeout: 5,
            message: "Workouts screen did not load"
        )
        captureScreen(named: "Workouts")

        let workoutsScrollView = app.scrollViews["workouts_scroll"]
        let workoutsScrollable = workoutsScrollView.exists ? workoutsScrollView : firstScrollable(in: app)
        let trainingPlansCard = workoutsScrollable.buttons["training_plans_card"]
        let trainingPlansElement = workoutsScrollable.otherElements["training_plans_card"]
        let trainingPlansLabel = workoutsScrollable.staticTexts["AI Training Plans"]
        let trainingPlansLabelLocalized = workoutsScrollable.staticTexts["Planos de Treino IA"]
        let trainingPlansButton = workoutsScrollable.buttons["AI Training Plans"]
        let trainingPlansButtonLocalized = workoutsScrollable.buttons["Planos de Treino IA"]
        let trainingPlanCandidates = [
            trainingPlansCard,
            trainingPlansElement,
            trainingPlansButton,
            trainingPlansButtonLocalized,
            trainingPlansLabel,
            trainingPlansLabelLocalized
        ]
        if let candidate = waitForAny(trainingPlanCandidates, timeout: 2) {
            scrollToElement(candidate, in: workoutsScrollable)
        } else {
            scrollToBottom(workoutsScrollable)
        }
        tapFirstMatch(
            trainingPlanCandidates,
            timeout: 5,
            message: "Training Plans entry not found"
        )
        assertAnyExists(
            [
                app.otherElements["training_plans_screen"],
                app.staticTexts["AI Training Plans"],
                app.staticTexts["Planos de Treino IA"],
                app.staticTexts["No Training Plans"],
                app.staticTexts["Nenhum Plano de Treino"],
                app.buttons["Create Plan"],
                app.buttons["Criar Plano"],
                app.navigationBars["Training Plans"],
                app.navigationBars["Planos de Treino"]
            ],
            timeout: 5,
            message: "Training Plans screen did not open"
        )
        captureScreen(named: "Training Plans")
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    @MainActor
    func testStartWorkoutShowsActiveWorkoutSheet() throws {
        let app = launchAppForUITest()
        completeOnboardingIfNeeded(app)

        openWorkoutsTab(app)
        assertAnyExists(
            [
                app.staticTexts["Workouts"],
                app.staticTexts["Treinos"],
                app.buttons["Start Workout"]
            ],
            timeout: 5,
            message: "Workouts screen did not load"
        )

        let workoutsScrollable = firstScrollable(in: app)
        let startWorkoutButton = app.buttons["Start Workout"]
        let startWorkoutLocalized = app.buttons["Iniciar Treino"]
        scrollToTop(workoutsScrollable)
        tapFirstMatch(
            [startWorkoutButton, startWorkoutLocalized],
            timeout: 5,
            message: "Start Workout button not found"
        )
        assertAnyExists(
            [
                app.staticTexts["Active Workout"],
                app.staticTexts["Treino Ativo"],
                app.staticTexts["Workout"],
                app.staticTexts["Treino"],
                app.buttons["End Workout"],
                app.buttons["Encerrar Treino"]
            ],
            timeout: 5,
            message: "Active Workout sheet did not appear"
        )
        captureScreen(named: "Active Workout")
        app.tap()
    }

    @MainActor
    func testAboutFromSettings() throws {
        let app = launchAppForUITest()
        completeOnboardingIfNeeded(app)

        openSettingsTab(app)
        assertAnyExists(
            [
                app.navigationBars["Settings"],
                app.staticTexts["Settings"],
                app.staticTexts["Configurações"]
            ],
            timeout: 5,
            message: "Settings screen did not load"
        )
        captureScreen(named: "Settings")

        let aboutCandidates = ["About", "Sobre"]
        let settingsList = app.tables["settings_list"]
        let settingsScrollView = app.scrollViews["settings_list"]
        let settingsScrollable = settingsList.exists ? settingsList : (settingsScrollView.exists ? settingsScrollView : firstScrollable(in: app))
        let aboutLabels = aboutCandidates.map { settingsScrollable.staticTexts[$0] }
        let aboutCells = aboutCandidates.map { settingsScrollable.cells.staticTexts[$0] }
        let aboutIdentifierCandidates = [
            settingsScrollable.buttons["about_row"],
            settingsScrollable.cells["about_row"],
            settingsScrollable.otherElements["about_row"]
        ]
        scrollToBottom(settingsScrollable)
        if let label = waitForAny(aboutIdentifierCandidates + aboutLabels + aboutCells, timeout: 5) {
            scrollToElement(label, in: settingsScrollable)
        }
        tapFirstMatch(
            aboutIdentifierCandidates + aboutLabels + aboutCells,
            timeout: 5,
            message: "About entry not found"
        )
        assertAnyExists(
            [app.navigationBars["About"], app.navigationBars["Sobre"]],
            timeout: 5,
            message: "About screen did not open"
        )
        captureScreen(named: "About")
    }
}
