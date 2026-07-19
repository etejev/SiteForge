import XCTest

@MainActor
final class SiteForgeLaunchTests: XCTestCase {
    private func launchWorkspace() -> XCUIApplication {
        continueAfterFailure = false
        let application = XCUIApplication()
        application.launchArguments += ["-AppleKeyboardUIMode", "3"]
        application.launch()
        application.activate()

        if !application.windows.firstMatch.waitForExistence(timeout: 2) {
            application.typeKey("n", modifierFlags: .command)
        }
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 5))
        let newProject = application.buttons["launch.newBlankProject"]
        if newProject.waitForExistence(timeout: 2) {
            newProject.click()
            XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 2))
        }
        return application
    }

    private func launchScenario(_ scenario: String, reduceMotion: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let application = XCUIApplication()
        application.launchArguments += [
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeLaunchScenario", scenario,
        ]
        if reduceMotion {
            application.launchArguments += ["-SiteForgeReduceMotion", "YES"]
        }
        application.launch()
        application.activate()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 5))
        return application
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
    }

    // SF-0201-002, SF-0201-004, SF-0201-008
    @MainActor
    func testApplicationLaunchesCompleteNativeShellAtPracticalMinimumSize() throws {
        let application = launchWorkspace()
        let window = application.windows.firstMatch
        XCTAssertFalse(window.title.isEmpty)
        XCTAssertGreaterThanOrEqual(window.frame.width, 1_100)
        XCTAssertGreaterThanOrEqual(window.frame.height, 700)

        for identifier in ["shell.navigator", "shell.canvas", "shell.inspector", "shell.status"] {
            XCTAssertTrue(application.descendants(matching: .any)[identifier].exists, identifier)
        }

        XCTAssertTrue(application.buttons["navigator.tab.pages"].exists)
        XCTAssertTrue(application.buttons["navigator.tab.layers"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["navigator.pages.list"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["navigator.page.home"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["navigator.page.notFound"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["canvas.viewport.controls"].exists)
        XCTAssertTrue(application.buttons["inspector.tab.layout"].exists)
        XCTAssertTrue(application.buttons["inspector.tab.style"].exists)
        XCTAssertTrue(application.buttons["inspector.tab.advanced"].exists)
        XCTAssertTrue(application.buttons["inspector.tab.accessibility"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["status.zoom"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["status.breakpoint"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["status.diagnostics"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["status.document"].exists)
    }

    // SF-0301-006, SF-0303-006, SF-0303-008
    @MainActor
    func testPagesNavigatorExposesApprovedOrderLabelsSelectionAndArrowNavigation() throws {
        let application = launchWorkspace()
        let home = application.descendants(matching: .any)["navigator.page.home"]
        let notFound = application.descendants(matching: .any)["navigator.page.notFound"]

        XCTAssertTrue(home.exists)
        XCTAssertTrue(notFound.exists)
        XCTAssertEqual(home.label, "Home, route /")
        XCTAssertEqual(notFound.label, "Not Found, route /404")
        XCTAssertLessThan(home.frame.minY, notFound.frame.minY)

        home.click()
        XCTAssertEqual(home.value as? String, "Selected")
        application.typeKey(.downArrow, modifierFlags: [])
        XCTAssertEqual(notFound.value as? String, "Selected")
        XCTAssertTrue(hasKeyboardFocus(notFound))
    }

    // SF-0201-006, SF-0203-006, SF-0203-008
    @MainActor
    func testToolbarCommandsExposeSelectedDisabledAndPreviewStates() throws {
        let application = launchWorkspace()
        for tool in ["select", "frame", "text", "image", "component"] {
            XCTAssertTrue(application.buttons["toolbar.tool.\(tool)"].exists, tool)
        }

        XCTAssertEqual(application.buttons["toolbar.tool.select"].value as? String, "Selected")
        XCTAssertFalse(application.buttons["toolbar.undo"].isEnabled)
        XCTAssertFalse(application.buttons["toolbar.redo"].isEnabled)

        application.buttons["toolbar.tool.frame"].click()
        XCTAssertTrue(application.staticTexts["Tool: Frame"].waitForExistence(timeout: 2))

        application.buttons["toolbar.preview"].click()
        XCTAssertTrue(application.descendants(matching: .any)["preview.placeholder"].waitForExistence(timeout: 2))
        application.buttons["preview.done"].click()
    }

    // SF-0201-006, SF-0602-006, SF-1902-006
    @MainActor
    func testKeyboardFocusMovesThroughNavigatorBeforeViewportControls() throws {
        let application = launchWorkspace()
        let pages = application.buttons["navigator.tab.pages"]
        let layers = application.buttons["navigator.tab.layers"]
        let viewport = application.descendants(matching: .any)["canvas.viewport.preset"]

        pages.click()
        XCTAssertTrue(hasKeyboardFocus(pages))

        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(hasKeyboardFocus(layers))

        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(hasKeyboardFocus(viewport))
    }

    // SF-0301-006, SF-0306-006, SF-1504-006
    @MainActor
    func testDocumentCommandsAndStatusAreKeyboardAndAccessibilityAvailable() throws {
        let application = launchWorkspace()
        application.menuBars.menuBarItems["File"].click()
        for command in ["New", "Open…", "Save", "Save As…", "Revert to Saved"] {
            XCTAssertTrue(application.menuItems[command].exists, command)
        }
        XCTAssertTrue(application.menuItems["New"].isEnabled)
        XCTAssertTrue(application.menuItems["Open…"].isEnabled)
        XCTAssertTrue(application.menuItems["Save"].isEnabled)
        application.typeKey(.escape, modifierFlags: [])

        let status = application.descendants(matching: .any)["status.document"]
        XCTAssertTrue(status.exists)
    }

    // SF-0201-006, SF-0301-002, SF-1602-006
    @MainActor
    func testInitialLaunchOffersKeyboardFocusedNativeProjectActions() throws {
        let application = launchScenario("welcome")
        let newProject = application.buttons["launch.newBlankProject"]
        let openProject = application.buttons["launch.openProject"]
        XCTAssertTrue(newProject.exists)
        XCTAssertTrue(openProject.exists)
        XCTAssertTrue(newProject.isHittable)
        XCTAssertTrue(openProject.isHittable)
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 2))
    }

    // SF-0201-004, SF-0301-004, SF-1602-004
    @MainActor
    func testDeterminateIndeterminateAndNonCancelableLoadingSurfaces() throws {
        let indeterminate = launchScenario("loadingIndeterminate")
        XCTAssertTrue(indeterminate.descendants(matching: .any)["launch.progress.indeterminate"].exists)
        XCTAssertTrue(indeterminate.buttons["launch.cancel"].exists)
        indeterminate.terminate()

        let determinate = launchScenario("loadingDeterminate")
        XCTAssertTrue(determinate.descendants(matching: .any)["launch.progress.determinate"].exists)
        XCTAssertTrue(determinate.staticTexts["Restoring document history…"].exists)
        determinate.terminate()

        let nonCancelable = launchScenario("loadingNonCancelable")
        XCTAssertTrue(nonCancelable.descendants(matching: .any)["launch.nonCancelable"].exists)
        XCTAssertFalse(nonCancelable.buttons["launch.cancel"].exists)
    }

    // SF-0301-004, SF-0301-006, SF-0301-008
    @MainActor
    func testFailureAndRecoveryExposeSpecificFullyKeyboardOperableActions() throws {
        let failure = launchScenario("failure")
        XCTAssertTrue(failure.buttons["launch.retry"].exists)
        XCTAssertTrue(failure.buttons["launch.chooseAnother"].exists)
        XCTAssertTrue(failure.buttons["launch.retry"].isHittable)
        failure.terminate()

        let recovery = launchScenario("recovery")
        for identifier in ["launch.recovery.inspect", "launch.recovery.discard", "launch.recovery.restore"] {
            XCTAssertTrue(recovery.buttons[identifier].exists, identifier)
        }
        XCTAssertTrue(recovery.buttons["launch.recovery.restore"].isHittable)
        recovery.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(recovery.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 2))
    }

    // SF-0201-006, SF-0201-007, SF-1602-006
    @MainActor
    func testReduceMotionUsesStaticIndeterminateStatus() throws {
        let application = launchScenario("loadingIndeterminate", reduceMotion: true)
        XCTAssertFalse(application.descendants(matching: .any)["launch.progress.indeterminate"].exists)
        XCTAssertTrue(application.staticTexts["Opening project…"].exists)
    }
}
