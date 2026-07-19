import XCTest

@MainActor
final class SiteForgeLaunchTests: XCTestCase {
    private lazy var recoveryDirectory: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".siteforge-test-fixtures/ui-\(UUID())", isDirectory: true)
    }()

    private func launchWorkspace() -> XCUIApplication {
        continueAfterFailure = false
        let application = XCUIApplication()
        application.launchArguments += [
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeRecoveryDirectory", recoveryDirectory.path,
        ]
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

    private func launchScenario(
        _ scenario: String,
        reduceMotion: Bool = false,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        continueAfterFailure = false
        let application = XCUIApplication()
        application.launchArguments += [
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeLaunchScenario", scenario,
            "-SiteForgeRecoveryDirectory", recoveryDirectory.path,
        ]
        if reduceMotion {
            application.launchArguments += ["-SiteForgeReduceMotion", "YES"]
        }
        application.launchArguments += extraArguments
        application.launch()
        application.activate()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 5))
        return application
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    // SF-0203-006, SF-0301-006, SF-0306-006, SF-1902-006
    @MainActor
    func testUnsavedTransitionDecisionIsNativeKeyboardAndAccessibilityOperable() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeStartModified", "YES",
        ])

        application.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(application.buttons["documentTransition.discard"].waitForExistence(timeout: 2))
        for identifier in ["documentTransition.save", "documentTransition.discard", "documentTransition.cancel"] {
            XCTAssertTrue(application.buttons[identifier].exists, identifier)
            XCTAssertTrue(application.buttons[identifier].isHittable, identifier)
        }

        application.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(application.buttons["documentTransition.discard"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].exists)

        application.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(application.buttons["documentTransition.discard"].waitForExistence(timeout: 2))
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.buttons["Cancel"].waitForExistence(timeout: 2))
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].exists)

        application.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(application.buttons["documentTransition.discard"].waitForExistence(timeout: 2))
        application.buttons["documentTransition.discard"].click()
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 2))
        XCTAssertFalse(application.windows.firstMatch.title.contains("Edited"))
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

    // SF-0201-003, SF-0201-006, SF-1505-006, SF-1605-006
    @MainActor
    func testWorkspaceChromeUsesNativeMaterialWithoutInterceptingCanvasInput() throws {
        let application = launchScenario("workspace")
        for identifier in ["shell.navigator", "shell.inspector", "canvas.viewport.controls", "shell.status"] {
            let surface = application.descendants(matching: .any)[identifier]
            XCTAssertTrue(surface.exists, identifier)
        }
        attachScreenshot(named: "workspace-default-native-material")

        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.exists)
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertEqual(canvas.value as? String, "Interactions: 1")

        application.buttons["navigator.tab.layers"].click()
        XCTAssertTrue(application.descendants(matching: .any)["navigator.empty"].exists)
        application.buttons["navigator.tab.pages"].click()
        XCTAssertTrue(application.descendants(matching: .any)["navigator.pages.list"].exists)
    }

    // SF-0201-003, SF-0201-006, SF-0201-008
    @MainActor
    func testOpaqueHighContrastDarkAndInactiveMaterialStatesRemainOperable() throws {
        let variants: [(String, [String])] = [
            ("light", ["-SiteForgeAppearance", "light"]),
            ("dark", ["-SiteForgeAppearance", "dark"]),
            ("reduce-transparency", ["-SiteForgeReduceTransparency", "YES"]),
            ("increased-contrast", ["-SiteForgeIncreaseContrast", "YES"]),
            ("inactive", ["-SiteForgeWindowInactive", "YES"]),
        ]
        for (name, arguments) in variants {
            let application = launchScenario("workspace", extraArguments: arguments)
            XCTAssertTrue(application.descendants(matching: .any)["shell.navigator"].exists)
            XCTAssertTrue(application.buttons["navigator.tab.pages"].isHittable)
            XCTAssertTrue(application.buttons["toolbar.preview"].isHittable)
            application.typeKey("\t", modifierFlags: [])
            XCTAssertTrue(application.descendants(matching: .any)["workspace.shell"].exists)
            attachScreenshot(named: "workspace-\(name)")
            application.terminate()
        }
    }

    // SF-0201-002, SF-0201-007, SF-1505-007, SF-1605-007
    @MainActor
    func testLargeFixtureScrollsAndRetainsMinimumLayoutResponsiveness() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWorkspaceFixture", "large",
            "-SiteForgeWindowSize", "minimum",
        ])
        let window = application.windows.firstMatch
        XCTAssertGreaterThanOrEqual(window.frame.width, 1_100)
        XCTAssertGreaterThanOrEqual(window.frame.height, 700)
        let pageList = application.descendants(matching: .any)["navigator.pages.list"]
        XCTAssertTrue(pageList.exists)
        pageList.scroll(byDeltaX: 0, deltaY: 600)
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["shell.inspector"].exists)
        XCTAssertTrue(application.buttons["toolbar.tool.select"].isHittable)
        attachScreenshot(named: "workspace-large-minimum")
    }

    // SF-0201-008, SF-1505-008, SF-1605-008
    @MainActor
    func testLaunchAndLoadingStatesRegressUnderOpaqueMaterialFallback() throws {
        for scenario in ["welcome", "loadingIndeterminate", "loadingDeterminate", "loadingNonCancelable", "failure", "recovery"] {
            let application = launchScenario(scenario, extraArguments: [
                "-SiteForgeReduceTransparency", "YES",
            ])
            XCTAssertTrue(application.descendants(matching: .any)["launch.experience"].exists, scenario)
            let expectedIdentifier = switch scenario {
            case "welcome": "launch.newBlankProject"
            case "loadingIndeterminate": "launch.progress.indeterminate"
            case "loadingDeterminate": "launch.progress.determinate"
            case "loadingNonCancelable": "launch.nonCancelable"
            case "failure": "launch.retry"
            default: "launch.recovery.restore"
            }
            XCTAssertTrue(application.descendants(matching: .any)[expectedIdentifier].exists, scenario)
            application.terminate()
        }
    }
}
