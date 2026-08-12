import AppKit
import XCTest

@MainActor
final class SiteForgeLaunchTests: XCTestCase {
    private enum TestWindowAlignment: String {
        case left
        case right
    }

    private enum TestWindowVerticalAlignment: String {
        case top
        case bottom
    }

    private enum TestWindowGeometry {
        static let safeScreenInset: CGFloat = 16

        static var minimumExpectedHeight: CGFloat {
            guard let visibleHeight = NSScreen.main?.visibleFrame.height else {
                return 700
            }
            return min(700, max(1, visibleHeight - safeScreenInset))
        }
    }

    // SF-0406-001 through SF-0406-008
    func testInlinePlainTextEditingCommitCancelUndoRedoAndAccessibilityJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        application.buttons["toolbar.tool.text"].click()
        let textPoint = canvas.coordinate(withNormalizedOffset: .init(dx: 0.55, dy: 0.50))
        textPoint.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(application.buttons["toolbar.tool.select"].value as? String, "Selected")

        func textObject() -> XCUIElement {
            application.descendants(matching: .any)
                .matching(NSPredicate(
                    format: "label == %@ AND identifier BEGINSWITH %@",
                    "Text object",
                    "canvas.object."
                ))
                .firstMatch
        }
        XCTAssertTrue(textObject().waitForExistence(timeout: 5))
        func editPoint() -> XCUICoordinate {
            canvas.coordinate(withNormalizedOffset: .init(dx: 0.67, dy: 0.52))
        }
        editPoint().doubleClick()
        var editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.label, "Inline plain-text editor")
        XCTAssertTrue(waitForKeyboardFocus(editor, in: application))
        for _ in 0..<4 {
            editor.typeKey(.delete, modifierFlags: [])
        }
        editor.typeText("Edited")
        XCTAssertEqual(editor.value as? String, "Edited")
        editor.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(editor.value as? String, "Edited\n")
        editor.typeText("Line")
        XCTAssertEqual(application.buttons["toolbar.tool.select"].value as? String, "Selected")
        XCTAssertEqual(editor.value as? String, "Edited\nLine")
        XCTAssertTrue(waitForValue(
            application.descendants(matching: .any)["status.textEditing"],
            containing: "11 bytes"
        ))
        editor.typeKey(.leftArrow, modifierFlags: [.shift])
        attachWindowScreenshot(application, named: "SF-AUTHORING-008 inline text draft")
        editor.typeKey(.rightArrow, modifierFlags: [])
        editor.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(waitForNonexistence(editor))
        XCTAssertTrue(
            waitForValue(application.buttons["toolbar.undo"], containing: "Set Property"),
            String(describing: application.descendants(matching: .any)["status.textEditing"].value)
        )
        XCTAssertTrue(
            waitForEnabled(application.buttons["toolbar.undo"]),
            String(describing: application.descendants(matching: .any)[
                "workspace.focus.diagnostics"
            ].value)
        )
        attachWindowScreenshot(application, named: "SF-AUTHORING-008 committed plain text")

        application.typeKey("z", modifierFlags: .command)
        let undoneTextObject = textObject()
        XCTAssertTrue(undoneTextObject.waitForExistence(timeout: 5))
        application.typeKey(.return, modifierFlags: [])
        editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Text")
        editor.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(editor))

        application.typeKey("z", modifierFlags: [.command, .shift])
        let redoneTextObject = textObject()
        XCTAssertTrue(redoneTextObject.waitForExistence(timeout: 5))
        editPoint().doubleClick()
        editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Edited\nLine")
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Cancelled")
        editor.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(editor))
        XCTAssertTrue(
            application.descendants(matching: .any)["status.textEditing"]
                .waitForExistence(timeout: 2)
        )

        editPoint().doubleClick()
        editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Edited\nLine")
        editor.typeKey("a", modifierFlags: .command)
        editor.typeKey("c", modifierFlags: .command)
        editor.typeKey("x", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "")
        editor.typeKey("v", modifierFlags: .command)
        XCTAssertEqual(editor.value as? String, "Edited\nLine")
        editor.typeKey(.escape, modifierFlags: [])
        attachWindowScreenshot(application, named: "SF-AUTHORING-008 cancelled text restored")
    }

    // SF-0405-002 through SF-0405-007
    func testFrameTextInsertionCancellationUndoRedoAndSelectionJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        application.buttons["toolbar.tool.frame"].click()
        XCTAssertTrue(application.descendants(matching: .any)["status.insertion"].exists)
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.35)).click()
        XCTAssertTrue(waitForEnabled(application.buttons["toolbar.undo"]))
        attachScreenshot(named: "SF-AUTHORING-005 inserted frame")

        application.buttons["toolbar.tool.text"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.55, dy: 0.50)).click()
        attachScreenshot(named: "SF-AUTHORING-005 inserted text")

        application.buttons["toolbar.tool.frame"].click()
        canvas.hover()
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.buttons["toolbar.undo"].isEnabled)
        attachScreenshot(named: "SF-AUTHORING-005 cancelled preview")

        XCTAssertTrue(
            waitForValue(canvas, containing: "rendered objects 2"),
            "Unexpected canvas state after frame/text insertion: \(String(describing: canvas.value))"
        )
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        XCTAssertTrue(application.buttons["toolbar.redo"].isEnabled)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 2"))
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

    // SF-0408-001 through SF-0408-008 — local navigator drag command parity.
    func testLayersContextualReorderShowsAccessiblePreviewAndUndoRedo() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        application.buttons["toolbar.tool.frame"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.30, dy: 0.35)).click()
        application.buttons["toolbar.tool.frame"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.60, dy: 0.50)).click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 2"))

        application.buttons["navigator.tab.layers"].click()
        let layers = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
        expectation(for: NSPredicate { _, _ in layers.count >= 3 }, evaluatedWith: application)
        waitForExpectations(timeout: 5)
        let frames = layers.matching(NSPredicate(format: "label == %@", "Frame"))
            .allElementsBoundByAccessibilityElement
        XCTAssertEqual(frames.count, 2)
        frames[1].click()
        XCTAssertTrue((frames[1].value as? String)?.contains("Primary selection") == true)
        frames[0].rightClick()
        let moveBefore = application.menuItems["Move Before"]
        XCTAssertTrue(moveBefore.waitForExistence(timeout: 3))
        XCTAssertTrue(moveBefore.isEnabled)
        moveBefore.click()
        XCTAssertTrue(waitForValue(application.buttons["toolbar.undo"], containing: "Move Node"))
        attachScreenshot(named: "SF-AUTHORING-009 local Layers reorder")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForEnabled(application.buttons["toolbar.redo"]))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForEnabled(application.buttons["toolbar.undo"]))
    }

    // SF-0403-001 through SF-0403-008
    func testGeometryTransformPointerKeyboardNumericUndoRedoAndAccessibilityJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        application.buttons["toolbar.tool.frame"].click()
        let insertion = canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.35))
        insertion.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["toolbar.tool.select"].click()

        let geometry = application.descendants(matching: .any)["inspector.transform.geometry"]
        XCTAssertTrue(geometry.waitForExistence(timeout: 5))
        XCTAssertEqual(geometry.label, "Selection geometry")
        let initial = try XCTUnwrap(geometry.value as? String)

        let rightHandle = application.buttons["canvas.transform.handle.right"]
        XCTAssertTrue(rightHandle.waitForExistence(timeout: 5))
        XCTAssertEqual(rightHandle.label, "right resize handle")
        let rightHandleCenter = rightHandle.coordinate(
            withNormalizedOffset: .init(dx: 0.5, dy: 0.5)
        )
        let resizeDestination = rightHandleCenter.withOffset(.init(dx: 20, dy: 0))
        rightHandleCenter.click(forDuration: 0.2, thenDragTo: resizeDestination)
        let transformStatus = application.descendants(matching: .any)["status.transform"]
        XCTAssertTrue(
            waitForValueToChange(geometry, from: initial),
            "transform status: \(transformStatus.label); canvas: \(String(describing: canvas.value))"
        )
        attachScreenshot(named: "SF-AUTHORING-006 pointer resize")

        let moveButton = application.buttons["inspector.transform.moveRight"]
        let resizeButton = application.buttons["inspector.transform.increaseWidth"]
        XCTAssertTrue(moveButton.exists)
        XCTAssertTrue(resizeButton.exists)
        let afterPointerResize = try XCTUnwrap(geometry.value as? String)
        moveButton.click()
        XCTAssertTrue(waitForValueToChange(geometry, from: afterPointerResize))
        let afterNumericMove = try XCTUnwrap(geometry.value as? String)
        resizeButton.click()
        XCTAssertTrue(waitForValueToChange(geometry, from: afterNumericMove))
        attachScreenshot(named: "SF-AUTHORING-006 numeric move and resize")

        let objectCenter = resizeDestination.withOffset(.init(dx: -130, dy: 0))
        let moveDestination = objectCenter.withOffset(.init(dx: 20, dy: -10))
        let beforePointerMove = try XCTUnwrap(geometry.value as? String)
        objectCenter.click(forDuration: 0.2, thenDragTo: moveDestination)
        XCTAssertTrue(waitForValueToChange(geometry, from: beforePointerMove))
        attachScreenshot(named: "SF-AUTHORING-006 pointer move")

        moveDestination.click()
        let beforeKeyboard = try XCTUnwrap(geometry.value as? String)
        // A large keyboard step deliberately exits the snapping hysteresis envelope.
        application.typeKey(.rightArrow, modifierFlags: .shift)
        XCTAssertTrue(waitForValueToChange(geometry, from: beforeKeyboard))

        let committed = try XCTUnwrap(geometry.value as? String)
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValueToChange(geometry, from: committed))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(geometry, containing: committed))

        let beforeEscape = try XCTUnwrap(geometry.value as? String)
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["inspector.empty"].exists)
        XCTAssertTrue(waitForKeyboardFocus(canvas, in: application))
        application.buttons["navigator.tab.layers"].click()
        XCTAssertTrue(application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
            .firstMatch.exists)
        XCTAssertFalse(beforeEscape.isEmpty)
        attachScreenshot(named: "SF-AUTHORING-006 cancelled selection scope")
        XCTAssertTrue(application.buttons["toolbar.undo"].isEnabled)
    }

    // SF-0404-001 through SF-0404-008
    func testSnappingRulersAuthoredGuidesSuppressionAndAccessibilityJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertTrue(application.descendants(matching: .any)["canvas.ruler.horizontal"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["canvas.ruler.vertical"].exists)

        application.buttons["toolbar.tool.frame"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.40, dy: 0.40)).click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["toolbar.tool.select"].click()

        let addHorizontal = application.buttons["inspector.guide.addHorizontal"]
        XCTAssertTrue(addHorizontal.waitForExistence(timeout: 5))
        XCTAssertEqual(addHorizontal.label, "Add horizontal guide")
        addHorizontal.click()
        let summary = application.descendants(matching: .any)["inspector.guide.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("Horizontal") || (summary.value as? String)?.contains("Horizontal") == true)
        let guide = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.guide."))
            .firstMatch
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        XCTAssertTrue(guide.label.contains("Horizontal authored guide"))
        attachWindowScreenshot(
            application,
            named: "SF-AUTHORING-007 rulers and authored guide"
        )

        let move = application.buttons["inspector.guide.move"]
        XCTAssertTrue(move.exists)
        let originalPosition = try XCTUnwrap(guide.value as? String)
        let originalPoints = try XCTUnwrap(Double(
            originalPosition.replacingOccurrences(of: " points", with: "")
        ))
        move.click()
        XCTAssertTrue(waitForValueToChange(guide, from: originalPosition))
        XCTAssertEqual(
            guide.value as? String,
            String(format: "%.1f points", originalPoints + 1)
        )

        let suppress = application.checkBoxes["inspector.snapping.suppress"]
        XCTAssertTrue(suppress.exists)
        suppress.click()
        XCTAssertTrue(application.descendants(matching: .any)["status.snapping"].waitForExistence(timeout: 2))
        attachWindowScreenshot(application, named: "SF-AUTHORING-007 snapping suppressed")
        suppress.click()

        application.buttons["inspector.guide.remove"].click()
        XCTAssertFalse(guide.exists)
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            application.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.guide."))
                .firstMatch.waitForExistence(timeout: 2)
        )
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertFalse(guide.exists)
    }

    func testNativeCanvasRendererAdoptsAuthoredObjectsAndPreservesInput() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let rendered = NSPredicate { object, _ in
            // Structural blank-project roots are intentionally nonvisual; the
            // active page begins with zero authored render objects.
            ((object as? XCUIElement)?.value as? String)?.contains("rendered objects 0") == true
        }
        expectation(for: rendered, evaluatedWith: canvas)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(canvas.label, "Canvas viewport")
        let emptyState = application.descendants(matching: .any)["canvas.empty.state"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["canvas.empty.insert.frame"].isHittable)
        XCTAssertTrue(application.buttons["canvas.empty.insert.text"].isHittable)
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

    private var fixtureLease: ApplicationOwnedTestFixture!
    private var launchedApplications: [XCUIApplication] = []
    private var fixtureRoot: URL { fixtureLease.url }
    private var recoveryDirectory: URL {
        fixtureRoot.appendingPathComponent("recovery", isDirectory: true)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Integration packages and recovery artifacts exercise descriptor-bound
        // application-owned I/O. Keep them in the same private temporary
        // container policy used by the package tests—not in a checkout whose
        // ancestor can be mediated by a File Provider.
        fixtureLease = try ApplicationOwnedTestFixture.create("ui")
    }

    override func tearDownWithError() throws {
        for application in launchedApplications where application.state != .notRunning {
            application.terminate()
        }
        launchedApplications.removeAll()
        try fixtureLease?.cleanup()
        fixtureLease = nil
        try super.tearDownWithError()
    }

    private func launchWorkspace(
        windowAlignment: TestWindowAlignment? = nil,
        verticalAlignment: TestWindowVerticalAlignment? = nil
    ) -> XCUIApplication {
        continueAfterFailure = false
        let application = trackedApplication()
        application.launchArguments += [
            "-NSTreatUnknownArgumentsAsOpen", "NO",
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeUITestMode", "YES",
            "-SiteForgeRecoveryDirectory", recoveryDirectory.path,
        ]
        if let windowAlignment {
            application.launchArguments += ["-SiteForgeUITestWindowAlignment", windowAlignment.rawValue]
        }
        if let verticalAlignment {
            application.launchArguments += ["-SiteForgeUITestWindowVerticalAlignment", verticalAlignment.rawValue]
        }
        application.launch()
        application.activate()

        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 5))
        let newProject = application.buttons["launch.newBlankProject"]
        guard newProject.waitForExistence(timeout: 2) else {
            attachReadinessDiagnostics(for: application)
            XCTFail("Welcome action did not become available before workspace creation.")
            return application
        }
        newProject.click()
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
            let stateIsReady = application.descendants(matching: .any)[stateIdentifier]
                .waitForExistence(timeout: 5)
            if !stateIsReady {
                attachReadinessDiagnostics(for: application)
            }
            XCTAssertTrue(stateIsReady, "Launch state \(scenario) did not become ready.")
        }
        return application
    }

    /// XCTest may report termination before the prior process relinquishes its
    /// accessibility server connection. A bounded predicate keeps one test's
    /// launch scenario from becoming the next scenario's foreground window.
    private func terminateAndWait(
        _ application: XCUIApplication,
        timeout: TimeInterval = 5
    ) {
        guard application.state != .notRunning else { return }
        application.terminate()
        let stopped = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { object, _ in
                    (object as? XCUIApplication)?.state == .notRunning
                },
                object: application
            )],
            timeout: timeout
        ) == .completed
        XCTAssertTrue(stopped, "The prior SiteForge UI-test process did not terminate cleanly.")
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

    private func waitForHittable(
        _ element: XCUIElement,
        in application: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let result = waitForHittable(element, timeout: timeout)
        if !result {
            attachPointerDiagnostics(control: element, application: application)
        }
        return result
    }

    private func waitForNonexistence(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: element
            )],
            timeout: timeout
        ) == .completed
    }

    private func waitForEnabled(
        _ element: XCUIElement,
        timeout: TimeInterval = 5
    ) -> Bool {
        XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == true AND enabled == true"),
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
        let nativeDiagnostics = application.descendants(matching: .any)[
            "workspace.focus.diagnostics"
        ]
        let nativeFocusSnapshot: String
        if nativeDiagnostics.exists, let value = nativeDiagnostics.value as? String {
            nativeFocusSnapshot = value
        } else {
            nativeFocusSnapshot = "<unavailable>"
        }
        let details = """
        Expected accessibility identifier: \(identifier)
        Current focused accessibility identifier: \(currentIdentifier)
        Native focus snapshot: \(nativeFocusSnapshot)

        \(redactedAccessibilityHierarchy(for: application))
        """
        let hierarchy = XCTAttachment(string: details)
        hierarchy.name = "focus-failure-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreenshot(named: "focus-failure-\(identifier)")
    }

    private func attachPointerDiagnostics(
        control: XCUIElement,
        application: XCUIApplication
    ) {
        let window = application.windows.firstMatch
        let screenSize = XCUIScreen.main.screenshot().image.size
        let history = ["toolbar.undo", "toolbar.redo"].map { identifier in
            let command = application.buttons[identifier]
            let exists = command.exists
            let value = exists ? ((command.value as? String) ?? "unavailable") : "unavailable"
            return "\(identifier){exists=\(exists);enabled=\(exists && command.isEnabled);operation=\(value)}"
        }.joined(separator: ";")
        let textStatus = application.descendants(matching: .any)["status.textEditing"]
        let focusStatus = application.descendants(matching: .any)["workspace.focus.diagnostics"]
        let controlExists = control.exists
        let windowExists = window.exists
        let details = """
        control=\(control.identifier)
        state={exists=\(controlExists);enabled=\(controlExists && control.isEnabled);hittable=\(controlExists && control.isHittable);focused=\(controlExists && hasKeyboardFocus(control))}
        controlFrame=\(controlExists ? sanitizedFrame(control.frame) : "unavailable")
        visibleScreen={x=0.0;y=0.0;width=\(screenSize.width);height=\(screenSize.height)}
        window={identifier=\(windowExists ? window.identifier : "unavailable");frame=\(windowExists ? sanitizedFrame(window.frame) : "unavailable")}
        history=\(history)
        textPhase=\(textStatus.exists ? ((textStatus.value as? String) ?? "unavailable") : "unavailable")
        responder=\(focusStatus.exists ? ((focusStatus.value as? String) ?? "unavailable") : "unavailable")
        """
        let attachment = XCTAttachment(string: details)
        attachment.name = "pointer-failure-\(control.identifier)"
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)
        attachScreenshot(named: "pointer-failure-\(control.identifier)")
    }

    private func sanitizedFrame(_ frame: CGRect) -> String {
        String(
            format: "{x=%.1f;y=%.1f;width=%.1f;height=%.1f}",
            frame.minX,
            frame.minY,
            frame.width,
            frame.height
        )
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

    private func attachWindowScreenshot(_ application: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: application.windows.firstMatch.screenshot())
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
        XCTAssertGreaterThanOrEqual(
            window.frame.height,
            TestWindowGeometry.minimumExpectedHeight
        )

        for identifier in ["shell.navigator", "shell.canvas", "shell.inspector", "shell.status"] {
            XCTAssertTrue(application.descendants(matching: .any)[identifier].exists, identifier)
        }

        XCTAssertTrue(application.buttons["navigator.tab.pages"].exists)
        XCTAssertTrue(application.buttons["navigator.tab.layers"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["navigator.pages.list"].exists)
        XCTAssertEqual(pageRows(in: application).count, 2)
        XCTAssertTrue(application.descendants(matching: .any)["canvas.viewport.controls"].exists)
        for tab in ["design", "layout", "content", "interactions", "accessibility"] {
            XCTAssertTrue(application.buttons["inspector.tab.\(tab)"].exists, tab)
        }
        XCTAssertTrue(application.descendants(matching: .any)["status.zoom"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["status.breakpoint"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["status.diagnostics"].exists)
        XCTAssertTrue(application.descendants(matching: .any)["status.document"].exists)
    }

    // SF-0201-002, SF-0201-006, SF-0201-008
    @MainActor
    func testProductNavigatorProvidesTruthfulElementsAssetsAndComponentsDestinations() throws {
        let application = launchWorkspace()

        let elements = application.buttons["navigator.tab.elements"]
        XCTAssertTrue(waitForHittable(elements, in: application))
        elements.click()
        XCTAssertTrue(application.descendants(matching: .any)["navigator.elements.catalog"].exists)

        let frame = application.buttons["navigator.elements.frame"]
        let text = application.buttons["navigator.elements.text"]
        XCTAssertTrue(frame.isEnabled)
        XCTAssertTrue(text.isEnabled)
        XCTAssertEqual(frame.label, "Frame")
        XCTAssertEqual(text.label, "Text")
        for identifier in ["section", "stack", "grid", "button", "link", "divider", "navbar", "footer"] {
            let item = application.buttons["navigator.elements.\(identifier)"]
            XCTAssertTrue(item.exists, identifier)
            XCTAssertFalse(item.isEnabled, identifier)
        }

        frame.click()
        XCTAssertEqual(application.buttons["toolbar.tool.frame"].value as? String, "Selected")
        application.typeKey(.escape, modifierFlags: [])

        let assets = application.buttons["navigator.tab.assets"]
        XCTAssertTrue(waitForHittable(assets, in: application))
        assets.click()
        XCTAssertTrue(application.descendants(matching: .any)["navigator.assets.unavailable"].exists)

        let components = application.buttons["navigator.tab.components"]
        XCTAssertTrue(waitForHittable(components, in: application))
        components.click()
        XCTAssertTrue(application.descendants(matching: .any)["navigator.components.unavailable"].exists)
    }

    // SF-0201-002, SF-0201-006, SF-0201-008, SF-1505-006 through SF-1505-008
    @MainActor
    func testInspectorProvidesTruthfulUnavailableContentAndInteractionsDestinations() throws {
        let application = launchWorkspace(windowAlignment: .right)
        let design = application.buttons["inspector.tab.design"]
        let layout = application.buttons["inspector.tab.layout"]
        let content = application.buttons["inspector.tab.content"]
        let interactions = application.buttons["inspector.tab.interactions"]
        let accessibility = application.buttons["inspector.tab.accessibility"]

        for (tab, identifier) in [
            (design, "design"),
            (layout, "layout"),
            (accessibility, "accessibility"),
        ] {
            XCTAssertTrue(waitForHittable(tab, in: application))
            tab.click()
            attachScreenshot(named: "SF-PRODUCT-UI-003 inspector \(identifier)")
        }

        XCTAssertTrue(waitForHittable(content, in: application))
        XCTAssertEqual(content.label, "Content")
        XCTAssertTrue(content.isEnabled)
        content.click()
        let contentUnavailable = application.descendants(matching: .any)["inspector.content.unavailable"]
        XCTAssertTrue(contentUnavailable.waitForExistence(timeout: 5))
        XCTAssertTrue(contentUnavailable.label.localizedCaseInsensitiveContains("Content unavailable"))
        XCTAssertTrue(contentUnavailable.label.localizedCaseInsensitiveContains("not available yet"))
        XCTAssertTrue(application.descendants(matching: .button)["inspector.transform.moveRight"].exists == false)
        attachScreenshot(named: "SF-PRODUCT-UI-003 inspector content unavailable")

        XCTAssertTrue(waitForHittable(interactions, in: application))
        XCTAssertEqual(interactions.label, "Interactions")
        interactions.click()
        let interactionsUnavailable = application.descendants(matching: .any)["inspector.interactions.unavailable"]
        XCTAssertTrue(interactionsUnavailable.waitForExistence(timeout: 5))
        XCTAssertTrue(interactionsUnavailable.label.localizedCaseInsensitiveContains("Interactions unavailable"))
        XCTAssertTrue(interactionsUnavailable.label.localizedCaseInsensitiveContains("not available yet"))
        attachScreenshot(named: "SF-PRODUCT-UI-003 inspector interactions unavailable")
    }

    // SF-0203-006, SF-0405-004, SF-0405-006, SF-1505-006
    @MainActor
    func testInsertedFrameHasVisibleAuthoredSurfaceAndSeparateSelectionContext() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        application.buttons["toolbar.tool.frame"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.46, dy: 0.46)).click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))

        let frame = application.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Frame"))
            .firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 5))
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].waitForExistence(timeout: 5))
        attachScreenshot(named: "SF-PRODUCT-UI-003 selected frame surface and context")

        let undo = application.buttons["toolbar.undo"]
        XCTAssertTrue(waitForHittable(undo, in: application))
        undo.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"))
        let redo = application.buttons["toolbar.redo"]
        XCTAssertTrue(waitForHittable(redo, in: application))
        redo.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
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

        XCTAssertTrue(waitForHittable(preview, in: application))
        preview.click()
        XCTAssertTrue(application.descendants(matching: .any)["preview.placeholder"].waitForExistence(timeout: 2))
    }

    // SF-0201-006, SF-0201-008, SF-0406-006, SF-1902-008
    @MainActor
    func testInlineTextStatusCommitAndCancelUseBottomAlignedPointerWindow() throws {
        let application = launchWorkspace(verticalAlignment: .bottom)
        let canvas = application.descendants(matching: .any)["canvas.interaction"]
        let textTool = application.buttons["toolbar.tool.text"]
        XCTAssertTrue(waitForHittable(textTool, in: application))
        textTool.click()
        XCTAssertTrue(waitForHittable(canvas, in: application))
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.55, dy: 0.50)).click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["toolbar.tool.select"].click()

        func openSelectedTextEditor() {
            application.menuBars.menuBarItems["Selection"].click()
            let edit = application.menuItems["Edit Selected Text"]
            XCTAssertTrue(edit.waitForExistence(timeout: 2))
            XCTAssertTrue(edit.isEnabled)
            edit.click()
        }
        openSelectedTextEditor()
        var editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Pointer commit")

        let commit = application.buttons["textEditing.commit"]
        let cancel = application.buttons["textEditing.cancel"]
        let screenHeight = XCUIScreen.main.screenshot().image.size.height
        XCTAssertTrue(waitForHittable(commit, in: application))
        XCTAssertLessThanOrEqual(
            commit.frame.maxY,
            screenHeight - TestWindowGeometry.safeScreenInset
        )
        commit.click()
        XCTAssertTrue(waitForNonexistence(editor))
        XCTAssertTrue(waitForValue(application.buttons["toolbar.undo"], containing: "Set Property"))

        openSelectedTextEditor()
        editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Pointer cancel")
        XCTAssertTrue(waitForHittable(cancel, in: application))
        XCTAssertLessThanOrEqual(
            cancel.frame.maxY,
            screenHeight - TestWindowGeometry.safeScreenInset
        )
        cancel.click()
        XCTAssertTrue(waitForNonexistence(editor))

        openSelectedTextEditor()
        editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "Pointer commit")
        editor.typeKey(.escape, modifierFlags: [])
    }

    // SF-0201-006, SF-0201-008, SF-0203-006, SF-0405-006, SF-0405-008
    @MainActor
    func testUndoRedoToolbarPointerUsesRightAlignedTestWindow() throws {
        let application = launchWorkspace(windowAlignment: .right)
        let canvas = application.descendants(matching: .any)["canvas.interaction"]
        application.typeKey("f", modifierFlags: [])
        XCTAssertTrue(application.staticTexts["Tool: Frame"].waitForExistence(timeout: 2))
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))

        let undo = application.buttons["toolbar.undo"]
        let redo = application.buttons["toolbar.redo"]
        let screenWidth = XCUIScreen.main.screenshot().image.size.width
        XCTAssertTrue(waitForHittable(undo, in: application))
        XCTAssertGreaterThanOrEqual(undo.frame.minX, TestWindowGeometry.safeScreenInset)
        undo.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"))

        XCTAssertTrue(waitForHittable(redo, in: application))
        XCTAssertLessThanOrEqual(
            redo.frame.maxX,
            screenWidth - TestWindowGeometry.safeScreenInset
        )
        redo.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
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
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["navigator.tab.elements"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["navigator.tab.assets"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["navigator.tab.components"], in: application))
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
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["canvas.zoom.fitCanvas"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["canvas.zoom.fit"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(
            application.descendants(matching: .any)["canvas.interaction"],
            in: application
        ))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["inspector.tab.design"], in: application))

        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["inspector.tab.layout"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["inspector.tab.content"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["inspector.tab.interactions"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(accessibility, in: application))
        application.typeKey("\t", modifierFlags: .shift)
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["inspector.tab.interactions"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(accessibility, in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(pages, in: application))

        let reverseTraversal: [XCUIElement] = [
            accessibility,
            application.buttons["inspector.tab.interactions"],
            application.buttons["inspector.tab.content"],
            application.buttons["inspector.tab.layout"],
            application.buttons["inspector.tab.design"],
            application.descendants(matching: .any)["canvas.interaction"],
            application.buttons["canvas.zoom.fit"],
            application.buttons["canvas.zoom.fitCanvas"],
            application.buttons["canvas.zoom.reset"],
            application.buttons["canvas.zoom.in"],
            application.buttons["canvas.zoom.out"],
            application.descendants(matching: .any)["canvas.viewport.preset"],
            pageRow(named: "Not Found", in: application),
            pageRow(named: "Home", in: application),
            application.buttons["navigator.tab.components"],
            application.buttons["navigator.tab.assets"],
            application.buttons["navigator.tab.elements"],
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

        let fitCanvas = application.buttons["canvas.zoom.fitCanvas"]
        XCTAssertTrue(fitCanvas.isHittable)
        let beforeFitCanvas = try XCTUnwrap(canvas.value as? String)
        fitCanvas.click()
        XCTAssertTrue(waitForValueToChange(canvas, from: beforeFitCanvas))

        let beforePan = try XCTUnwrap(canvas.value as? String)
        application.typeKey(.rightArrow, modifierFlags: .option)
        XCTAssertTrue(waitForValueToChange(canvas, from: beforePan))

        let fitDocument = application.buttons["canvas.zoom.fit"]
        XCTAssertTrue(fitDocument.isHittable)
        let beforeFitDocument = try XCTUnwrap(canvas.value as? String)
        fitDocument.click()
        XCTAssertTrue(waitForValueToChange(canvas, from: beforeFitDocument))
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
        // Scene command routing is established as the workspace adopts its
        // document. Assert the real enabled state through a bounded predicate
        // rather than sampling a transient menu snapshot.
        XCTAssertTrue(waitForEnabled(application.menuItems["New"]))
        XCTAssertTrue(waitForEnabled(application.menuItems["Open…"]))
        XCTAssertTrue(waitForEnabled(application.menuItems["Save"]))
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
        terminateAndWait(indeterminate)

        let determinate = launchScenario("loadingDeterminate")
        XCTAssertTrue(determinate.descendants(matching: .any)["launch.progress.determinate"].waitForExistence(timeout: 5))
        XCTAssertTrue(determinate.staticTexts["Restoring document history…"].waitForExistence(timeout: 5))
        terminateAndWait(determinate)

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
        terminateAndWait(failure)

        let recovery = launchScenario("recovery")
        for identifier in ["launch.recovery.inspect", "launch.recovery.discard", "launch.recovery.restore"] {
            XCTAssertTrue(recovery.buttons[identifier].exists, identifier)
        }
        XCTAssertTrue(
            waitForHittable(
                recovery.buttons["launch.recovery.restore"],
                in: recovery
            ),
            "Restore must become a genuinely interactable default recovery action."
        )
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
        terminateAndWait(application)

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
            // The immutable package's project ID is deliberately distinct
            // from its document ID. Recovery ownership binds the filename to
            // the project ID from the package manifest.
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
        terminateAndWait(application)

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
        XCTAssertTrue(application.descendants(matching: .any)["navigator.empty"].exists)
        XCTAssertTrue(application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
            .allElementsBoundByAccessibilityElement.isEmpty)

        // A blank project has only a structural root, which must not be
        // fabricated into a visual/Layer object. Use the real named empty
        // action before requiring canonical content and its adopted layer.
        application.buttons["navigator.tab.pages"].click()
        let insertFrame = application.buttons["canvas.empty.insert.frame"]
        XCTAssertTrue(waitForHittable(insertFrame, in: application))
        insertFrame.click()
        XCTAssertTrue(waitForValue(
            application.descendants(matching: .any)["canvas.interaction"].firstMatch,
            containing: "rendered objects 1"
        ))
        XCTAssertTrue(waitForValue(
            application.descendants(matching: .any)["status.selectionPath"],
            containing: "Frame"
        ))

        application.buttons["navigator.tab.layers"].click()
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

    private func waitForLabelToChange(_ element: XCUIElement, from value: String) -> Bool {
        let predicate = NSPredicate { object, _ in
            (object as? XCUIElement)?.label != value
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
            terminateAndWait(application)
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
        XCTAssertGreaterThanOrEqual(
            window.frame.height,
            TestWindowGeometry.minimumExpectedHeight
        )
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
            terminateAndWait(application)
        }
    }
}
