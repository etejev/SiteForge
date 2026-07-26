import XCTest

@MainActor
final class SiteForgeLaunchTests: XCTestCase {
    private enum TestWindowAlignment: String {
        case left
        case right
    }

    private enum TestWindowGeometry {
        static let safeScreenInset: CGFloat = 16
    }

    // SF-0405-002 through SF-0405-007
    func testFrameTextInsertionCancellationUndoRedoAndSelectionJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        application.buttons["toolbar.tool.frame"].click()
        XCTAssertTrue(application.descendants(matching: .any)["status.insertion"].exists)
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.35)).click()
        XCTAssertTrue(application.buttons["toolbar.undo"].isEnabled)
        attachScreenshot(named: "SF-AUTHORING-005 inserted frame")

        application.buttons["toolbar.tool.text"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.55, dy: 0.50)).click()
        attachScreenshot(named: "SF-AUTHORING-005 inserted text")

        application.buttons["toolbar.tool.frame"].click()
        canvas.hover()
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.buttons["toolbar.undo"].isEnabled)
        attachScreenshot(named: "SF-AUTHORING-005 cancelled preview")

        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 3"))
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 2"))
        XCTAssertTrue(application.buttons["toolbar.redo"].isEnabled)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 3"))
        XCTAssertTrue(application.buttons["toolbar.undo"].isEnabled)

        application.buttons["navigator.tab.layers"].click()
        let layerQuery = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
        expectation(for: NSPredicate { _, _ in layerQuery.count >= 3 }, evaluatedWith: application)
        waitForExpectations(timeout: 5)
        let layers = layerQuery.allElementsBoundByAccessibilityElement
        XCTAssertGreaterThanOrEqual(layers.count, 3)
        XCTAssertEqual(Set(layers.map(\.identifier)).count, layers.count)
    }

    func testNativeCanvasRendererAdoptsAuthoredObjectsAndPreservesInput() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let rendered = NSPredicate { object, _ in
            // The renderer owns the active page only; the other blank-project page is not part of this scene.
            ((object as? XCUIElement)?.value as? String)?.contains("rendered objects 1") == true
        }
        expectation(for: rendered, evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(canvas.label, "Canvas viewport")
        canvas.click()
        XCTAssertTrue((canvas.value as? String)?.contains("interactions 1") == true)
    }

    // SF-0402-001 through SF-0402-008
    func testSelectionEmptySingleMultipleLayersKeyboardAndAccessibilityParity() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeSelectionFixture", "multiple",
        ])
        application.buttons["navigator.tab.layers"].click()
        let layers = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
            .allElementsBoundByAccessibilityElement
        XCTAssertEqual(layers.count, 3)
        XCTAssertEqual(Set(layers.map(\.identifier)).count, 3)
        XCTAssertTrue((application.descendants(matching: .any)["status.selectionPath"].value as? String)?.contains("No selection") == true)
        attachScreenshot(named: "SF-AUTHORING-004 empty selection")

        layers[0].click()
        XCTAssertTrue((layers[0].value as? String)?.contains("Primary selection") == true)
        XCTAssertTrue((application.descendants(matching: .any)["status.selectionPath"].label).contains("Fixture") == false)
        attachScreenshot(named: "SF-AUTHORING-004 single selection")

        XCUIElement.perform(withKeyModifiers: .shift) { layers[1].click() }
        XCTAssertTrue((layers[1].value as? String)?.contains("Primary selection") == true)
        let multipleStatus = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(multipleStatus.label.contains("2") || ((multipleStatus.value as? String)?.contains("2") == true))
        attachScreenshot(named: "SF-AUTHORING-004 multiple selection")

        application.typeKey(.escape, modifierFlags: [])
        let emptyStatus = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(emptyStatus.label.contains("No selection") || ((emptyStatus.value as? String)?.contains("No selection") == true))
        application.typeKey("]", modifierFlags: .command)
        XCTAssertTrue((layers[0].value as? String)?.contains("Primary selection") == true)
        application.typeKey("[", modifierFlags: .command)
        XCTAssertTrue((layers[2].value as? String)?.contains("Primary selection") == true)
    }

    private var fixtureLease: RepositoryTestFixture!
    private var launchedApplications: [XCUIApplication] = []
    private var fixtureRoot: URL { fixtureLease.url }
    private var recoveryDirectory: URL {
        fixtureRoot.appendingPathComponent("recovery", isDirectory: true)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // The launched Debug app owns creation; the UI runner's sandbox only reserves the path.
        fixtureLease = try RepositoryTestFixture.reserve("ui")
    }

    override func tearDownWithError() throws {
        for application in launchedApplications where application.state != .notRunning {
            application.terminate()
        }
        launchedApplications.removeAll()
        try super.tearDownWithError()
    }

    private func launchWorkspace(
        windowAlignment: TestWindowAlignment = .left
    ) -> XCUIApplication {
        continueAfterFailure = false
        let application = trackedApplication()
        application.launchArguments += [
            "-NSTreatUnknownArgumentsAsOpen", "NO",
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeUITestMode", "YES",
            "-SiteForgeUITestWindowAlignment", windowAlignment.rawValue,
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
        }
        application.activate()
        XCTAssertTrue(waitForWorkspaceReady(application))
        return application
    }

    private func launchScenario(
        _ scenario: String,
        reduceMotion: Bool = false,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        continueAfterFailure = false
        let application = trackedApplication()
        application.launchArguments += [
            "-NSTreatUnknownArgumentsAsOpen", "NO",
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeUITestMode", "YES",
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
        let state = application.descendants(matching: .any)["launch.experience"]
        if scenario == "workspace" {
            application.activate()
            XCTAssertTrue(waitForWorkspaceReady(application))
        } else {
            XCTAssertTrue(state.waitForExistence(timeout: 5))
            let stateIdentifier = switch scenario {
            case "welcome": "launch.newBlankProject"
            case "loadingIndeterminate": "launch.progress.indeterminate"
            case "loadingDeterminate": "launch.progress.determinate"
            case "loadingNonCancelable": "launch.nonCancelable"
            case "failure": "launch.retry"
            case "recovery": "launch.recovery.restore"
            default: "launch.experience"
            }
            XCTAssertTrue(
                application.descendants(matching: .any)[stateIdentifier].waitForExistence(timeout: 5),
                "Launch state \(scenario) did not become ready."
            )
        }
        return application
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) == true
    }

    private func waitForKeyboardFocus(
        _ element: XCUIElement,
        in application: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let focusedMatch = application.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ AND hasKeyboardFocus == true",
                element.identifier
            ))
            .firstMatch
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true"),
                object: focusedMatch
            )],
            timeout: timeout
        ) == .completed
        if !result {
            attachFocusDiagnostics(expected: element.identifier, application: application)
        }
        return result
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { object, _ in
                    guard let element = object as? XCUIElement else { return false }
                    return element.exists && element.isHittable
                },
                object: element
            )],
            timeout: timeout
        ) == .completed
    }

    private func waitForWorkspaceReady(
        _ application: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        application.activate()
        let window = application.windows.firstMatch
        let shell = application.descendants(matching: .any)["workspace.shell"]
        let ready = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return element.exists && element.label == "SiteForge workspace"
        }
        let result = window.waitForExistence(timeout: timeout)
            && XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: ready, object: shell)],
                timeout: timeout
            ) == .completed
        if !result {
            attachReadinessDiagnostics(for: application)
        }
        return result
    }

    private func attachReadinessDiagnostics(for application: XCUIApplication) {
        attachScreenshot(named: "workspace-readiness-failure")
        let hierarchy = XCTAttachment(string: redactedAccessibilityHierarchy(for: application))
        hierarchy.name = "workspace-readiness-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }

    private func attachFocusDiagnostics(
        expected identifier: String,
        application: XCUIApplication
    ) {
        let focused = application.descendants(matching: .any)
            .matching(NSPredicate(format: "hasKeyboardFocus == true"))
            .firstMatch
        let currentIdentifier: String
        if focused.exists, !focused.identifier.isEmpty {
            currentIdentifier = focused.identifier
        } else {
            currentIdentifier = "<unavailable>"
        }
        let details = """
        Expected accessibility identifier: \(identifier)
        Current focused accessibility identifier: \(currentIdentifier)

        \(redactedAccessibilityHierarchy(for: application))
        """
        let hierarchy = XCTAttachment(string: details)
        hierarchy.name = "focus-failure-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreenshot(named: "focus-failure-\(identifier)")
    }

    private func redactedAccessibilityHierarchy(for application: XCUIApplication) -> String {
        application.debugDescription
            .replacingOccurrences(
            of: #"(?:file://)?/(?:Users|private|var|Volumes)/[^\s,\]\)\}"]+"#,
            with: "<redacted-path>",
            options: .regularExpression
        )
            .replacingOccurrences(
                of: #"(label|value|title|placeholderValue): (?:'[^']*'|"[^"]*")"#,
                with: "$1: <redacted-content>",
                options: .regularExpression
            )
    }

    private func trackedApplication() -> XCUIApplication {
        let application = XCUIApplication()
        launchedApplications.append(application)
        return application
    }

    private func pageRows(in application: XCUIApplication) -> [XCUIElement] {
        application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.page."))
            .allElementsBoundByAccessibilityElement
    }

    private func pageRow(named name: String, in application: XCUIApplication) -> XCUIElement {
        application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
            "navigator.page.", name
        )).firstMatch
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launchIntegrationOpen(
        _ url: URL,
        base64Fixture: URL,
        startMalformed: Bool = false,
        retryBase64Fixture: URL? = nil
    ) -> XCUIApplication {
        continueAfterFailure = false
        let application = trackedApplication()
        application.launchArguments += [
            "-NSTreatUnknownArgumentsAsOpen", "NO",
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeUITestMode", "YES",
            "-SiteForgeRecoveryDirectory", recoveryDirectory.path,
            "-SiteForgeIntegrationOpenProject", url.path,
            "-SiteForgeIntegrationPackageBase64", base64Fixture.path,
        ]
        if startMalformed { application.launchArguments.append("-SiteForgeIntegrationStartMalformed") }
        if let retryBase64Fixture {
            application.launchArguments += ["-SiteForgeIntegrationRetryBase64", retryBase64Fixture.path]
        }
        application.launch()
        application.activate()
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 5))
        return application
    }

    private func legacyFixtureURL(named name: String) -> URL {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return repository.appendingPathComponent("Tests/Fixtures/Legacy/\(name).siteforge.b64")
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
        XCTAssertEqual(pageRows(in: application).count, 2)
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

    // SF-0201-006, SF-0201-008, SF-1902-008
    @MainActor
    func testWorkspaceReadinessDoesNotDependOnPreviewPointerVisibility() throws {
        let application = launchWorkspace()
        let workspace = application.descendants(matching: .any)["workspace.shell"]

        XCTAssertEqual(workspace.label, "SiteForge workspace")
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].exists)
        XCTAssertTrue(application.buttons["toolbar.preview"].exists)
    }

    // SF-0301-006, SF-0303-006, SF-0303-008
    @MainActor
    func testPagesNavigatorExposesApprovedOrderLabelsSelectionAndArrowNavigation() throws {
        let application = launchWorkspace()
        let home = pageRow(named: "Home", in: application)
        let notFound = pageRow(named: "Not Found", in: application)

        XCTAssertTrue(home.exists)
        XCTAssertTrue(notFound.exists)
        XCTAssertEqual(home.label, "Home, route /")
        XCTAssertEqual(notFound.label, "Not Found, route /404")
        XCTAssertLessThan(home.frame.minY, notFound.frame.minY)

        home.click()
        XCTAssertEqual(home.value as? String, "Home page; Selected")
        application.typeKey(.downArrow, modifierFlags: [])
        XCTAssertEqual(notFound.value as? String, "Not Found page; Selected")
        XCTAssertTrue(hasKeyboardFocus(notFound))
    }

    // SF-0202-006, SF-0202-008, SF-0303-006, SF-0303-008
    @MainActor
    func testPageRowIdentifiersAreTypedUniqueAndRoleIsSeparate() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWorkspaceFixture", "standard",
        ])
        let rows = pageRows(in: application)
        XCTAssertGreaterThanOrEqual(rows.count, 3)
        let identifiers = rows.map(\.identifier)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        let pattern = try NSRegularExpression(pattern: #"^navigator\.page\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#)
        for row in rows.prefix(12) {
            let range = NSRange(row.identifier.startIndex..., in: row.identifier)
            XCTAssertNotNil(pattern.firstMatch(in: row.identifier, range: range), row.identifier)
        }
        XCTAssertEqual(pageRow(named: "Home", in: application).value as? String, "Home page; Selected")
        XCTAssertTrue((pageRow(named: "Not Found", in: application).value as? String)?.hasPrefix("Not Found page;") == true)
        XCTAssertTrue(rows.contains { ($0.value as? String)?.hasPrefix("Standard page;") == true })
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

        application.typeKey("t", modifierFlags: [])
        XCTAssertTrue(application.staticTexts["Tool: Text"].waitForExistence(timeout: 2))

        let preview = application.buttons["toolbar.preview"]
        XCTAssertTrue(preview.exists)
        XCTAssertTrue(preview.isEnabled)
        XCTAssertEqual(preview.label, "Preview")
        application.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(application.descendants(matching: .any)["preview.placeholder"].waitForExistence(timeout: 2))
        application.buttons["preview.done"].click()
        XCTAssertTrue(hasKeyboardFocus(application.buttons["navigator.tab.pages"]))
    }

    // SF-0201-006, SF-0201-008, SF-0203-006, SF-1902-008
    @MainActor
    func testPreviewPointerUsesRightAlignedTestWindow() throws {
        let application = launchWorkspace(windowAlignment: .right)
        let preview = application.buttons["toolbar.preview"]

        XCTAssertTrue(waitForHittable(preview))
        preview.click()
        XCTAssertTrue(application.descendants(matching: .any)["preview.placeholder"].waitForExistence(timeout: 2))
    }

    // SF-0201-006, SF-0201-008, SF-0203-006, SF-0405-006, SF-0405-008
    @MainActor
    func testUndoRedoToolbarPointerUsesRightAlignedTestWindow() throws {
        let application = launchWorkspace(windowAlignment: .right)
        let canvas = application.descendants(matching: .any)["canvas.interaction"]
        application.typeKey("f", modifierFlags: [])
        XCTAssertTrue(application.staticTexts["Tool: Frame"].waitForExistence(timeout: 2))
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 2"))

        let undo = application.buttons["toolbar.undo"]
        let redo = application.buttons["toolbar.redo"]
        let screenWidth = XCUIScreen.main.screenshot().image.size.width
        XCTAssertTrue(waitForHittable(undo))
        XCTAssertGreaterThanOrEqual(undo.frame.minX, TestWindowGeometry.safeScreenInset)
        undo.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))

        XCTAssertTrue(waitForHittable(redo))
        XCTAssertLessThanOrEqual(
            redo.frame.maxX,
            screenWidth - TestWindowGeometry.safeScreenInset
        )
        redo.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 2"))
    }

    // SF-0201-006, SF-0602-006, SF-1902-006
    @MainActor
    func testKeyboardFocusTraversesWorkspaceForwardAndReverse() throws {
        let application = launchWorkspace()
        let pages = application.buttons["navigator.tab.pages"]
        let accessibility = application.buttons["inspector.tab.accessibility"]

        pages.click()
        XCTAssertTrue(waitForKeyboardFocus(pages, in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["navigator.tab.layers"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(pageRow(named: "Home", in: application), in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(pageRow(named: "Not Found", in: application), in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(
            application.descendants(matching: .any)["canvas.viewport.preset"],
            in: application
        ))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["canvas.zoom.out"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["canvas.zoom.in"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["canvas.zoom.reset"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["canvas.zoom.fit"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(
            application.descendants(matching: .any)["canvas.interaction"],
            in: application
        ))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["inspector.tab.layout"], in: application))

        accessibility.click()
        XCTAssertTrue(waitForKeyboardFocus(accessibility, in: application))
        application.typeKey("\t", modifierFlags: .shift)
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["inspector.tab.advanced"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(accessibility, in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(pages, in: application))

        let reverseTraversal: [XCUIElement] = [
            accessibility,
            application.buttons["inspector.tab.advanced"],
            application.buttons["inspector.tab.style"],
            application.buttons["inspector.tab.layout"],
            application.descendants(matching: .any)["canvas.interaction"],
            application.buttons["canvas.zoom.fit"],
            application.buttons["canvas.zoom.reset"],
            application.buttons["canvas.zoom.in"],
            application.buttons["canvas.zoom.out"],
            application.descendants(matching: .any)["canvas.viewport.preset"],
            pageRow(named: "Not Found", in: application),
            pageRow(named: "Home", in: application),
            application.buttons["navigator.tab.layers"],
            pages,
        ]
        for destination in reverseTraversal {
            application.typeKey("\t", modifierFlags: .shift)
            XCTAssertTrue(waitForKeyboardFocus(destination, in: application))
        }
    }

    // SF-0401-001, SF-0401-002, SF-0401-006, SF-0401-008
    @MainActor
    func testViewportCommandsAreKeyboardAndAccessibilityOperable() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"]
        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        XCTAssertTrue(canvas.exists)
        XCTAssertEqual(canvas.label, "Canvas viewport")
        XCTAssertTrue((canvas.value as? String)?.contains("Zoom 100 percent") == true)
        XCTAssertTrue(preset.exists)
        XCTAssertEqual(preset.label, "Viewport preset")
        XCTAssertEqual(preset.value as? String, "Desktop")

        preset.click()
        XCTAssertTrue(application.menuItems["Tablet"].waitForExistence(timeout: 2))
        application.menuItems["Tablet"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Tablet"))
        XCTAssertTrue(waitForKeyboardFocus(preset, in: application))
        application.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitForValue(preset, containing: "Mobile"))

        application.buttons["canvas.zoom.in"].click()
        XCTAssertTrue(waitForValue(canvas, containing: "Zoom 125 percent"))
        application.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(waitForValue(canvas, containing: "Zoom 100 percent"))

        let beforePan = try XCTUnwrap(canvas.value as? String)
        application.typeKey(.rightArrow, modifierFlags: .option)
        XCTAssertTrue(waitForValueToChange(canvas, from: beforePan))

        application.buttons["canvas.zoom.fit"].click()
        XCTAssertTrue((canvas.value as? String)?.contains("Zoom") == true)
        XCTAssertTrue(application.buttons["canvas.zoom.reset"].isHittable)
        XCTAssertTrue(application.descendants(matching: .any)["canvas.viewport.surface"].exists)
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
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 2))

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
        XCTAssertTrue(indeterminate.descendants(matching: .any)["launch.progress.indeterminate"].waitForExistence(timeout: 5))
        XCTAssertTrue(indeterminate.buttons["launch.cancel"].waitForExistence(timeout: 5))
        indeterminate.terminate()

        let determinate = launchScenario("loadingDeterminate")
        XCTAssertTrue(determinate.descendants(matching: .any)["launch.progress.determinate"].waitForExistence(timeout: 5))
        XCTAssertTrue(determinate.staticTexts["Restoring document history…"].waitForExistence(timeout: 5))
        determinate.terminate()

        let nonCancelable = launchScenario("loadingNonCancelable")
        XCTAssertTrue(nonCancelable.descendants(matching: .any)["launch.nonCancelable"].waitForExistence(timeout: 5))
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

    // SF-0201-004, SF-0201-006, SF-0301-004, SF-0301-006, SF-1602-008
    func testProductionLoaderOpensRealPackageAndRetriesMalformedBytesWithoutPreviewState() throws {
        let valid = legacyFixtureURL(named: "schema-v1-empty")
        let project = fixtureRoot.appendingPathComponent("Production-loader.siteforge")

        var application = launchIntegrationOpen(project, base64Fixture: valid)
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 5))
        XCTAssertTrue(pageRow(named: "Home", in: application).exists)
        application.terminate()

        application = launchIntegrationOpen(
            project,
            base64Fixture: valid,
            startMalformed: true,
            retryBase64Fixture: valid
        )
        let retry = application.buttons["launch.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        let failureMessage = application.staticTexts["launch.failure.message"]
        XCTAssertTrue(failureMessage.exists)
        XCTAssertFalse(failureMessage.label.contains("/Users/"))
        retry.click()
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 5))
    }

    // SF-0301-004, SF-0301-006, SF-0301-008, SF-1602-006
    func testProductionRecoveryDiscoverySupportsKeyboardRestoreAndDiscard() throws {
        let recoveryBytes = legacyFixtureURL(named: "schema-v1-rootless")
        let recovery = recoveryDirectory.appendingPathComponent(
            "11000000-0000-0000-0000-000000000002.siteforge-recovery"
        )
        var application = trackedApplication()
        application.launchArguments += [
            "-NSTreatUnknownArgumentsAsOpen", "NO",
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeUITestMode", "YES",
            "-SiteForgeRecoveryDirectory", recoveryDirectory.path,
            "-SiteForgeIntegrationRecoveryBase64", recoveryBytes.path,
            "-SiteForgeIntegrationRecoveryDestination", recovery.path,
        ]
        application.launch()
        application.activate()
        let restore = application.buttons["launch.recovery.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 5))
        application.terminate()

        application = trackedApplication()
        application.launchArguments += [
            "-NSTreatUnknownArgumentsAsOpen", "NO",
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeUITestMode", "YES",
            "-SiteForgeRecoveryDirectory", recoveryDirectory.path,
            "-SiteForgeIntegrationRecoveryBase64", recoveryBytes.path,
            "-SiteForgeIntegrationRecoveryDestination", recovery.path,
        ]
        application.launch()
        application.activate()
        let discard = application.buttons["launch.recovery.discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.click()
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 5))
    }

    // SF-0201-006, SF-0201-007, SF-1602-006
    @MainActor
    func testReduceMotionUsesStaticIndeterminateStatus() throws {
        let application = launchScenario("loadingIndeterminate", reduceMotion: true)
        let progress = application.descendants(matching: .any)["launch.progress.indeterminate"]
        XCTAssertTrue(progress.exists)
        XCTAssertEqual(progress.label, "Indeterminate progress, static")
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
        XCTAssertTrue((canvas.value as? String)?.contains("interactions 1") == true)

        application.buttons["navigator.tab.layers"].click()
        XCTAssertTrue(application.descendants(matching: .any)["navigator.layers.list"].exists)
        XCTAssertFalse(application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
            .allElementsBoundByAccessibilityElement.isEmpty)
        application.buttons["navigator.tab.pages"].click()
        XCTAssertTrue(application.descendants(matching: .any)["navigator.pages.list"].exists)
    }

    private func waitForValue(_ element: XCUIElement, containing text: String) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String)?.contains(text) == true
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 2
        ) == .completed
    }

    private func waitForValueToChange(_ element: XCUIElement, from value: String) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String) != value
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: 2
        ) == .completed
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
            XCTAssertTrue(waitForHittable(application.buttons["navigator.tab.pages"]))
            XCTAssertEqual(
                application.descendants(matching: .any)["workspace.shell"].label,
                "SiteForge workspace"
            )
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
            XCTAssertTrue(
                application.descendants(matching: .any)[expectedIdentifier].waitForExistence(timeout: 5),
                scenario
            )
            application.terminate()
        }
    }
}
