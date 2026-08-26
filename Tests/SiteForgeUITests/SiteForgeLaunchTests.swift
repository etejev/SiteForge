import AppKit
import XCTest

private enum LaunchLifecycleReadinessHandshake {
    /// All current window-presentation paths emit one of these phases after
    /// an AppKit window is usable. Keep this set in lockstep with
    /// `WorkspaceWindowPresentationOwner` so launch tests fail loudly when
    /// the diagnostic vocabulary changes instead of timing out opaquely.
    static let supportedPhaseFields: Set<Substring> = [
        "phase=window-became-usable",
        "phase=configuration-succeeded-constrained",
        "phase=configuration-succeeded-minimum",
        "phase=window-ready",
    ]

    static func reportsUsableWindow(in records: String) -> Bool {
        records.split(separator: "\n").contains { record in
            !supportedPhaseFields.isDisjoint(with: record.split(separator: ";"))
        }
    }
}

@MainActor
final class SiteForgeLaunchTests: XCTestCase {
    private static let applicationBundleIdentifier = "app.siteforge.SiteForge"
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
            return min(700, max(1, visibleHeight - (2 * safeScreenInset)))
        }
    }

    // SF-0201-002, SF-0201-008 — the UI harness recognizes every canonical
    // native-window readiness path and rejects merely similar phase names.
    func testLaunchLifecycleReadinessVocabularyIsExact() {
        for phase in LaunchLifecycleReadinessHandshake.supportedPhaseFields {
            XCTAssertTrue(LaunchLifecycleReadinessHandshake.reportsUsableWindow(
                in: "run=test;\(phase);windowCount=1;windows=visible=true"
            ), String(phase))
        }
        XCTAssertFalse(LaunchLifecycleReadinessHandshake.reportsUsableWindow(
            in: "run=test;phase=window-became-usable-later;windowCount=1;windows=visible=true"
        ))
        XCTAssertFalse(LaunchLifecycleReadinessHandshake.reportsUsableWindow(
            in: "run=test;phase=configuration-deferred;windowCount=1;windows=visible=false"
        ))
    }

    // SF-0406-001 through SF-0406-008
    func testInlinePlainTextEditingCommitCancelUndoRedoAndAccessibilityJourney() throws {
        let application = launchWorkspace(windowAlignment: .right)
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))

        // A blank document exposes a visible, named starting action. It
        // creates the same canonical plain-text node as the Insert menu and
        // avoids treating an arbitrary empty-canvas coordinate as content.
        application.buttons["canvas.empty.insert.text"].click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))

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
        XCTAssertTrue(
            application.descendants(matching: .any)["inspector.selection.summary"].waitForExistence(timeout: 3)
        )
        func beginSelectedTextEdit() {
            application.menuBars.menuBarItems["Selection"].click()
            let command = application.menuItems["Edit Selected Text"]
            XCTAssertTrue(command.waitForExistence(timeout: 2))
            XCTAssertTrue(command.isEnabled)
            command.click()
        }
        // Use the real Selection-menu command for the first edit. It shares
        // the typed text-edit registry with Return, VoiceOver, and canvas
        // pointer activation while keeping this journey independent of the
        // virtual child accessibility element's non-view mouse target.
        beginSelectedTextEdit()
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
        beginSelectedTextEdit()
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

        beginSelectedTextEdit()
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

        let afterPointerResize = try XCTUnwrap(geometry.value as? String)
        let xField = application.textFields["inspector.layout.x"]
        let yField = application.textFields["inspector.layout.y"]
        let widthField = application.textFields["inspector.layout.width"]
        let heightField = application.textFields["inspector.layout.height"]
        XCTAssertTrue(xField.waitForExistence(timeout: 5))
        XCTAssertTrue(yField.waitForExistence(timeout: 5))
        XCTAssertTrue(widthField.waitForExistence(timeout: 5))
        XCTAssertTrue(heightField.waitForExistence(timeout: 5))
        XCTAssertEqual(xField.label, "X geometry")
        XCTAssertTrue((xField.value as? String)?.contains("authored") == true)
        xField.click()
        xField.typeKey("a", modifierFlags: .command)
        xField.typeText("121")
        xField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValueToChange(geometry, from: afterPointerResize))
        let afterNumericMove = try XCTUnwrap(geometry.value as? String)
        yField.click()
        yField.typeKey("a", modifierFlags: .command)
        yField.typeText("122")
        yField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValueToChange(geometry, from: afterNumericMove))
        let afterNumericY = try XCTUnwrap(geometry.value as? String)
        widthField.click()
        widthField.typeKey("a", modifierFlags: .command)
        widthField.typeText("241")
        widthField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValueToChange(geometry, from: afterNumericY))
        let afterNumericWidth = try XCTUnwrap(geometry.value as? String)
        heightField.click()
        heightField.typeKey("a", modifierFlags: .command)
        heightField.typeText("161")
        heightField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValueToChange(geometry, from: afterNumericWidth))

        // Native focus loss commits a complete draft through the same typed
        // registry; no text-field draft becomes canonical while it is typed.
        let afterReturnCommit = try XCTUnwrap(geometry.value as? String)
        xField.click()
        xField.typeKey("a", modifierFlags: .command)
        xField.typeText("131")
        yField.click()
        XCTAssertTrue(waitForValueToChange(geometry, from: afterReturnCommit))
        // Retain an evidence frame after the real viewport has fitted the
        // selected canonical object; the attachment must show both fields and
        // their corresponding editor-only bounds rather than a clipped edge.
        let fit = application.buttons["canvas.zoom.fitCanvas"]
        XCTAssertTrue(fit.isHittable)
        fit.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-011 fixed geometry fields")

        let committedWidth = widthField.value as? String
        widthField.click()
        widthField.typeKey("a", modifierFlags: .command)
        widthField.typeText("0")
        widthField.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(widthField.value as? String, committedWidth)

        // Do not retain a coordinate rooted at the old resize-handle AX node:
        // successful numeric edits replace that editor-only node. Re-query the
        // current rendered object, whose stable identity is the production
        // source for the pointer-move gesture.
        let movedFrame = canvasObject(named: "Frame", in: application)
        XCTAssertTrue(movedFrame.waitForExistence(timeout: 3))
        let objectCenter = movedFrame.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
        let moveDestination = objectCenter.withOffset(.init(dx: 20, dy: -10))
        let beforePointerMove = try XCTUnwrap(geometry.value as? String)
        objectCenter.click(forDuration: 0.2, thenDragTo: moveDestination)
        XCTAssertTrue(waitForValueToChange(geometry, from: beforePointerMove))
        attachScreenshot(named: "SF-AUTHORING-006 pointer move")

        // The drag replaces its virtual canvas object. Re-establish selection
        // through the production Layers path before testing keyboard movement:
        // that is the stable semantic route, rather than an obsolete AX canvas
        // proxy or a destination coordinate that can lie outside the new frame.
        application.buttons["navigator.tab.layers"].click()
        let keyboardFrame = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"
        )).firstMatch
        XCTAssertTrue(keyboardFrame.waitForExistence(timeout: 3))
        keyboardFrame.click()
        // A selection click may preserve the user-selected Inspector tab. The
        // geometry assertion belongs to the actual Layout destination, rather
        // than relying on an incidental previous tab selection.
        let layoutTab = application.buttons["inspector.tab.layout"]
        XCTAssertTrue(waitForHittable(layoutTab, in: application))
        layoutTab.click()
        let preFocusGeometry = application.descendants(matching: .any)["inspector.transform.geometry"]
        XCTAssertTrue(preFocusGeometry.waitForExistence(timeout: 3))
        // Drive the shipping Selection-menu keyboard shortcut. It is a real
        // keyboard transform command but, unlike an AX click on a tiled canvas
        // proxy, it does not replace semantic Layers selection while routing
        // first responder through AppKit.
        let beforeKeyboard = try XCTUnwrap(preFocusGeometry.value as? String)
        application.typeKey(.rightArrow, modifierFlags: .control)
        XCTAssertTrue(waitForLiveElementValueToChange(
            in: application,
            identifier: "inspector.transform.geometry",
            from: beforeKeyboard
        ))
        let keyboardGeometry = application.descendants(matching: .any)["inspector.transform.geometry"]
        XCTAssertTrue(keyboardGeometry.waitForExistence(timeout: 3))

        let committed = try XCTUnwrap(keyboardGeometry.value as? String)
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValueToChange(keyboardGeometry, from: committed))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(keyboardGeometry, containing: committed))

        let beforeEscape = try XCTUnwrap(keyboardGeometry.value as? String)
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

    // SF-0508-001...006 — real native Design controls, not an accessibility-only mock.
    func testDesignInspectorSolidFillOpacityKeyboardUndoRedoJourney() throws {
        // The native opacity stepper is a genuine trailing Inspector control.
        // This explicitly named pointer journey uses the established right-edge
        // test placement so its real AppKit affordance remains visible on a
        // constrained hosted display; normal launches retain visible-frame
        // presentation.
        let application = launchWorkspace(windowAlignment: .right)
        let workspaceFrameBeforeColorPanel = application.windows.firstMatch.frame
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        application.buttons["toolbar.tool.frame"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.4, dy: 0.4)).click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        // The pointer tool intentionally supports repeated placement, but
        // screenshots for the Design Inspector must show committed authored
        // state rather than an active insertion preview.
        application.buttons["toolbar.tool.select"].click()
        application.buttons["inspector.tab.design"].click()
        let hex = application.textFields["inspector.design.fillHex"]
        let opacity = application.textFields["inspector.design.opacity"]
        let colorWell = application.colorWells["inspector.design.fillPicker"]
        let opacityStepper = application.steppers["inspector.design.opacityStepper"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5)); XCTAssertTrue(opacity.exists)
        XCTAssertTrue(colorWell.exists && colorWell.isEnabled)
        XCTAssertTrue(opacityStepper.exists && opacityStepper.isEnabled)
        XCTAssertEqual(opacityStepper.label, "Adjust opacity percent")
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 default fill and opacity")
        let designHierarchy = XCTAttachment(
            string: redactedAccessibilityHierarchy(for: application)
        )
        designHierarchy.name = "SF-AUTHORING-012 native Design controls accessibility hierarchy"
        designHierarchy.lifetime = .keepAlways
        add(designHierarchy)
        XCTAssertEqual(hex.label, "Solid fill hexadecimal RGBA")
        // This is SiteForge's production NSColorWell bridge. Drive the real
        // system Colors panel through its own visible slider; no model or
        // test-only mutation path participates in this interaction.
        let defaultHex = try XCTUnwrap(hex.value as? String)
        colorWell.click()
        let colorPanelHierarchy = XCTAttachment(
            string: redactedAccessibilityHierarchy(for: application)
        )
        colorPanelHierarchy.name = "SF-AUTHORING-012 native color panel accessibility hierarchy"
        colorPanelHierarchy.lifetime = .keepAlways
        add(colorPanelHierarchy)
        let nativeColorPanel = application.windows.matching(
            NSPredicate(format: "title == %@", "Colors")
        ).firstMatch
        XCTAssertTrue(nativeColorPanel.waitForExistence(timeout: 3))
        XCTAssertLessThan(
            nativeColorPanel.frame.width,
            workspaceFrameBeforeColorPanel.width,
            "The auxiliary NSColorPanel must not inherit workspace window sizing."
        )
        let workspaceWindow = application.windows.matching(
            NSPredicate(format: "title != %@", "Colors")
        ).firstMatch
        XCTAssertEqual(workspaceWindow.frame, workspaceFrameBeforeColorPanel)
        let nativeColorSlider = nativeColorPanel.sliders.firstMatch
        XCTAssertTrue(nativeColorSlider.exists && nativeColorSlider.isHittable)
        nativeColorSlider.coordinate(withNormalizedOffset: .init(dx: 0.72, dy: 0.5)).click()
        XCTAssertTrue(waitForValueToChange(hex, from: defaultHex))
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 native color well committed")
        let closeColorPanel = nativeColorPanel.buttons["_XCUI:CloseWindow"]
        XCTAssertTrue(closeColorPanel.exists && closeColorPanel.isEnabled)
        closeColorPanel.click()
        XCTAssertTrue(waitForNonexistence(nativeColorPanel, timeout: 2))
        application.activate()
        // Reopen and dismiss the actual system panel without a value change.
        // Cancelling a native picker session is history-neutral.
        let colorAfterNativeCommit = try XCTUnwrap(hex.value as? String)
        let undoBeforeColorCancellation = application.buttons["toolbar.undo"].value as? String
        colorWell.click()
        XCTAssertTrue(nativeColorPanel.waitForExistence(timeout: 3))
        nativeColorPanel.buttons["_XCUI:CloseWindow"].click()
        XCTAssertTrue(waitForNonexistence(nativeColorPanel, timeout: 2))
        application.activate()
        XCTAssertEqual(hex.value as? String, colorAfterNativeCommit)
        XCTAssertEqual(application.buttons["toolbar.undo"].value as? String, undoBeforeColorCancellation)
        hex.click()
        XCTAssertTrue(waitForKeyboardFocus(hex, in: application))

        // Drive the genuine visible NSStepper's two arrow affordances. Their
        // element-relative coordinates remain within the native control across
        // display placements, unlike an arbitrary screen coordinate.
        let opacityBeforeStepper = try XCTUnwrap(opacity.value as? String)
        XCTAssertTrue(waitForHittable(opacityStepper, in: application))
        opacityStepper.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.75)).click()
        XCTAssertTrue(waitForValueToChange(opacity, from: opacityBeforeStepper))
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 native opacity stepper decrement")
        let opacityAfterDecrement = try XCTUnwrap(opacity.value as? String)
        opacityStepper.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.25)).click()
        XCTAssertTrue(waitForValueToChange(opacity, from: opacityAfterDecrement))
        XCTAssertTrue(waitForValue(opacity, containing: "100 percent"))
        let undoAtOpacityMaximum = application.buttons["toolbar.undo"].value as? String
        opacityStepper.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.25)).click()
        XCTAssertTrue(waitForValue(opacity, containing: "100 percent"))
        XCTAssertEqual(application.buttons["toolbar.undo"].value as? String, undoAtOpacityMaximum)

        // Focus loss is a real Inspector boundary: a complete draft commits
        // exactly once when another visible native Inspector control becomes
        // first responder, while an invalid draft stays noncanonical and
        // reports validation rather than being coerced.
        hex.click(); hex.typeKey("a", modifierFlags: .command); hex.typeText("#203040FF")
        opacity.click()
        XCTAssertTrue(waitForValue(hex, containing: "#203040FF"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 valid focus loss")
        let opacityBeforeInvalidFocusLoss = opacity.value as? String
        hex.click(); hex.typeKey("a", modifierFlags: .command); hex.typeText("invalid")
        opacity.click()
        XCTAssertTrue(application.descendants(matching: .any)["inspector.design.validation"].waitForExistence(timeout: 3))
        XCTAssertEqual(opacity.value as? String, opacityBeforeInvalidFocusLoss)
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 invalid focus loss")
        hex.typeKey(.escape, modifierFlags: [])

        let prior = hex.value as? String
        hex.click(); hex.typeKey("a", modifierFlags: .command); hex.typeText("#20406080"); hex.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(hex, containing: "#20406080"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 authored fill")
        opacity.click(); opacity.typeKey("a", modifierFlags: .command); opacity.typeText("40"); opacity.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(opacity, containing: "40 percent"))
        hex.click(); hex.typeKey("a", modifierFlags: .command); hex.typeText("bad"); hex.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["inspector.design.validation"].waitForExistence(timeout: 5))
        hex.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue((hex.value as? String)?.contains("#20406080") == true)
        application.typeKey("z", modifierFlags: .command); application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(hex, containing: "#20406080"))
        XCTAssertNotEqual(prior, hex.value as? String)
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 cancel undo")
    }

    // SF-0506-001...006/008 — the real Design Inspector authors a border,
    // uniform corner radius, and one shadow through native controls.
    func testDesignInspectorBorderRadiusShadowUndoRedoAccessibilityJourney() throws {
        let application = launchWorkspace(windowAlignment: .right)
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        let insert = application.buttons["canvas.empty.insert.frame"]
        XCTAssertTrue(waitForHittable(insert, in: application)); insert.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-014 unstyled selection")
        application.buttons["inspector.tab.design"].click()
        let inspector = application.scrollViews["inspector.selection.scroll"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        func reveal(_ identifier: String) -> XCUIElement {
            let element = application.descendants(matching: .any)[identifier]
            for _ in 0..<12 where !element.isHittable { inspector.scroll(byDeltaX: 0, deltaY: -140) }
            return element
        }
        let borderToggle = reveal("inspector.design.borderToggle")
        XCTAssertTrue(borderToggle.isHittable); borderToggle.click()
        let borderWidth = reveal("inspector.design.borderWidth")
        XCTAssertTrue(borderWidth.isEnabled)
        borderWidth.click(); borderWidth.typeKey("a", modifierFlags: .command); borderWidth.typeText("4"); borderWidth.typeKey(.return, modifierFlags: [])
        let radiusToggle = reveal("inspector.design.cornerRadiusToggle")
        XCTAssertTrue(radiusToggle.isHittable); radiusToggle.click()
        let radius = reveal("inspector.design.cornerRadius")
        radius.click(); radius.typeKey("a", modifierFlags: .command); radius.typeText("18"); radius.typeKey(.return, modifierFlags: [])
        attachWindowScreenshot(application, named: "SF-AUTHORING-014 border radius")
        let shadowToggle = reveal("inspector.design.shadowToggle")
        XCTAssertTrue(shadowToggle.isHittable); shadowToggle.click()
        let shadow = reveal("inspector.design.shadowValues")
        shadow.click(); shadow.typeKey("a", modifierFlags: .command); shadow.typeText("2, 10, 20, 1"); shadow.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.design.announcement"], containing: "shadow committed"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-014 shadow")
        let beforeCancel = shadow.value as? String
        shadow.click(); shadow.typeKey("a", modifierFlags: .command); shadow.typeText("invalid"); shadow.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(shadow.value as? String, beforeCancel)
        application.typeKey("z", modifierFlags: .command)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue((canvas.value as? String)?.contains("rendered objects 1") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-014 undo redo")
    }

    // SF-0506-006/008 — the shipping Design controls remain readable and
    // scroll-reachable at the supported practical minimum; no hidden test
    // control substitutes for the native Inspector.
    func testDesignInspectorBoxAppearanceControlsRemainReachableAtPracticalMinimum() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWindowSize", "minimum",
        ])
        let shell = application.descendants(matching: .any)["workspace.shell"]
        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        XCTAssertEqual(shell.frame.width, 1_100, accuracy: 2)
        let insert = application.buttons["canvas.empty.insert.frame"]
        XCTAssertTrue(waitForHittable(insert, in: application)); insert.click()
        application.buttons["inspector.tab.design"].click()
        let inspector = application.scrollViews["inspector.selection.scroll"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        func reveal(_ identifier: String) -> XCUIElement {
            for _ in 0..<12 {
                let liveControl = application.descendants(matching: .any)[identifier]
                let controlFrame = liveControl.frame
                let viewportFrame = inspector.frame.insetBy(dx: 0, dy: 4)
                if liveControl.exists,
                   controlFrame.minY >= viewportFrame.minY,
                   controlFrame.maxY <= viewportFrame.maxY {
                    XCTAssertTrue(waitForHittable(liveControl, in: application), identifier)
                    return application.descendants(matching: .any)[identifier]
                }
                if controlFrame.maxY > viewportFrame.maxY {
                    inspector.scroll(byDeltaX: 0, deltaY: -120)
                } else if controlFrame.minY < viewportFrame.minY {
                    inspector.scroll(byDeltaX: 0, deltaY: 120)
                } else {
                    break
                }
            }
            return application.descendants(matching: .any)[identifier]
        }
        for identifier in [
            "inspector.design.borderToggle",
            "inspector.design.cornerRadiusToggle",
            "inspector.design.shadowToggle",
        ] {
            let control = reveal(identifier)
            XCTAssertTrue(control.isHittable, identifier)
            XCTAssertFalse(control.label.isEmpty, identifier)
        }
        attachWindowScreenshot(application, named: "SF-AUTHORING-014 practical minimum inspector")
    }

    // SF-0508-001 through SF-0508-006 — visible, keyboard/accessibility
    // discoverable v1 layer controls must drive the same canonical registry
    // as the established native colour and opacity controls.
    func testDesignInspectorOrderedFillLayersAccessibilityJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        application.buttons["canvas.empty.insert.frame"].click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["inspector.tab.design"].click()

        let layerList = application.descendants(matching: .any)["inspector.design.layers"]
        let addSolid = application.buttons["inspector.design.layers.addSolid"]
        let addGradient = application.buttons["inspector.design.layers.addGradient"]
        XCTAssertTrue(layerList.waitForExistence(timeout: 5))
        XCTAssertTrue(addSolid.isHittable && addGradient.isHittable)
        addGradient.click()
        let angle = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS %@", ".angle"))
            .firstMatch
        XCTAssertTrue(angle.waitForExistence(timeout: 5))
        XCTAssertEqual(angle.label, "Linear gradient angle")
        angle.click(); angle.typeKey("a", modifierFlags: .command); angle.typeText("90"); angle.typeKey(.return, modifierFlags: [])

        let gradientPrefix = angle.identifier.replacingOccurrences(of: ".angle", with: "")
        let stopColorWells = application.colorWells.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@ AND identifier ENDSWITH %@",
            "\(gradientPrefix).stop.", ".stop.", ".color"
        ))
        XCTAssertEqual(stopColorWells.count, 2)
        let inspectorScroll = application.descendants(matching: .any)["inspector.selection.scroll"]
        XCTAssertTrue(inspectorScroll.waitForExistence(timeout: 3))
        func reveal(_ element: XCUIElement) -> Bool {
            for _ in 0..<8 where !element.isHittable {
                let controlFrame = element.frame
                let viewportFrame = inspectorScroll.frame
                if controlFrame.maxY > viewportFrame.maxY {
                    inspectorScroll.scroll(byDeltaX: 0, deltaY: -100)
                } else if controlFrame.minY < viewportFrame.minY {
                    inspectorScroll.scroll(byDeltaX: 0, deltaY: 100)
                } else {
                    break
                }
            }
            return waitForHittable(element, in: application)
        }
        // A normal-height hosted display truthfully requires scrolling the
        // Design Inspector once a gradient exposes both stop editors. Prove
        // every real color well is reachable and pointer-operable through
        // that production scroll surface instead of assuming a tall display.
        let stopColorWellIdentifiers = stopColorWells.allElementsBoundByIndex.map(\.identifier)
        for identifier in stopColorWellIdentifiers {
            let stopColorWell = application.colorWells[identifier]
            XCTAssertTrue(reveal(stopColorWell))
        }
        let stopUpButtons = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "\(gradientPrefix).stop.", ".up"
        ))
        let stopDownButtons = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "\(gradientPrefix).stop.", ".down"
        ))
        XCTAssertEqual(stopUpButtons.count, 2)
        XCTAssertEqual(stopDownButtons.count, 2)
        XCTAssertFalse(stopUpButtons.element(boundBy: 0).isEnabled)
        XCTAssertTrue(stopDownButtons.element(boundBy: 0).isEnabled)
        let firstStopDown = stopDownButtons.element(boundBy: 0)
        XCTAssertTrue(reveal(firstStopDown))
        firstStopDown.click()

        let enabled = application.checkBoxes.matching(NSPredicate(format: "identifier CONTAINS %@", ".enabled"))
            .allElementsBoundByIndex.last ?? application.checkBoxes.firstMatch
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        XCTAssertTrue(enabled.isEnabled)
        XCTAssertTrue(reveal(enabled))
        enabled.click()
        let deleteIdentifier = angle.identifier.replacingOccurrences(of: ".angle", with: ".delete")
        for _ in 0..<8 {
            let liveDelete = application.buttons[deleteIdentifier]
            if liveDelete.isHittable { break }
            let controlFrame = liveDelete.frame
            let viewportFrame = inspectorScroll.frame
            if controlFrame.maxY > viewportFrame.maxY {
                inspectorScroll.scroll(byDeltaX: 0, deltaY: -100)
            } else if controlFrame.minY < viewportFrame.minY {
                inspectorScroll.scroll(byDeltaX: 0, deltaY: 100)
            } else {
                break
            }
        }
        let delete = application.buttons[deleteIdentifier]
        XCTAssertTrue(delete.exists && waitForHittable(delete, in: application))
        delete.click()
        XCTAssertTrue(waitForNonexistence(angle, timeout: 3))

        let solidColorWells = application.colorWells.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND NOT identifier CONTAINS %@ AND identifier ENDSWITH %@",
            "inspector.design.layers.", ".stop.", ".color"
        ))
        // Deleting the temporary gradient must retain the migrated default
        // solid layer. Adding another solid appends a distinct authored row;
        // it must not replace or hide the existing layer.
        XCTAssertEqual(solidColorWells.count, 1)
        XCTAssertTrue(reveal(addSolid))
        addSolid.click()
        XCTAssertEqual(solidColorWells.count, 2)
        let solidColorWellIdentifiers = solidColorWells.allElementsBoundByIndex.map(\.identifier)
        for identifier in solidColorWellIdentifiers {
            let solidColorWell = application.colorWells[identifier]
            XCTAssertTrue(reveal(solidColorWell))
        }
        attachWindowScreenshot(application, named: "SF-AUTHORING-013 ordered fill layers")
    }

    // SF-0508-001...006 — real Layers selection drives the same Design
    // registry for a mixed structural/Text subset; no fixture or model path
    // creates the selection.
    func testDesignInspectorMixedAndInapplicableSelectionJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        application.buttons["toolbar.tool.frame"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.35)).click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        // Insert Text as a page sibling. The bounded selection model only
        // permits additive selection within one active container; leaving the
        // Frame selected here would intentionally make Text its child.
        application.buttons["toolbar.tool.select"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.84, dy: 0.84)).click()
        let emptySelectionStatus = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(waitForValue(emptySelectionStatus, containing: "0 selected"))
        application.buttons["toolbar.tool.text"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.65, dy: 0.65)).click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 2"))

        application.buttons["navigator.tab.layers"].click()
        let frame = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"
        )).firstMatch
        let text = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text"
        )).firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 3)); XCTAssertTrue(text.exists)
        frame.click()
        XCUIElement.perform(withKeyModifiers: .shift) { text.click() }
        let multipleStatus = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(waitForValue(multipleStatus, containing: "2 selected; primary selection present"))
        XCTAssertTrue(frame.isSelected)
        XCTAssertTrue(text.isSelected)

        application.buttons["inspector.tab.design"].click()
        let hex = application.textFields["inspector.design.fillHex"]
        XCTAssertTrue(hex.isEnabled)
        hex.click(); hex.typeKey("a", modifierFlags: .command); hex.typeText("#112233FF"); hex.typeKey(.return, modifierFlags: [])
        let announcement = application.descendants(matching: .any)["inspector.design.announcement"]
        XCTAssertTrue(waitForValue(announcement, containing: "skipped 1 incompatible object"))
        XCTAssertEqual(multipleStatus.value as? String, "2 selected; primary selection present")
        XCTAssertTrue(frame.isSelected)
        XCTAssertTrue(text.isSelected)
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 mixed applicable fill")

        // The all-Text fill selection is truthfully unavailable. It keeps the
        // selection intact and exposes no enabled mutation control.
        text.click()
        XCTAssertFalse(hex.isEnabled)
        XCTAssertFalse(application.colorWells["inspector.design.fillPicker"].isEnabled)
        XCTAssertTrue((hex.value as? String)?.localizedCaseInsensitiveContains("Select a Frame") == true)
        // Operation feedback is scoped to the selection that produced it.
        // The previous mixed-edit success must not remain visible after Text
        // becomes the sole, inapplicable selection.
        XCTAssertTrue(waitForValue(announcement, containing: "updated for current selection"))
        XCTAssertFalse((announcement.value as? String)?.contains("skipped 1 incompatible") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 all-incompatible fill")
    }

    // SF-0508-001...008 — native Save, actual process close, and production
    // package reopen. Selection/draft state is intentionally re-established
    // through Layers because it is noncanonical editor convenience state.
    func testDesignInspectorNativeSaveCloseReopenPersistsFillAndOpacityJourney() throws {
        let fixture = legacyFixtureURL(named: "schema-v4-legacy-surface")
        let project = fixtureRoot.appendingPathComponent("design-inspector-native-save.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: fixture)
        XCTAssertTrue(waitForWorkspaceReady(application))
        // The historical schema-v4 member is deliberately geometry-less: it
        // exercises default resolution but must not be mistaken for a visible
        // authored object. Insert one real Frame through the public empty
        // canvas action, keeping the legacy member as unrelated package data
        // while this journey proves renderer adoption across Save/Close/Open.
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"))
        let insertFrame = application.buttons["canvas.empty.insert.frame"]
        XCTAssertTrue(waitForHittable(insertFrame, in: application))
        insertFrame.click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["navigator.tab.layers"].click()
        // Keep the immutable schema-v4 legacy member as unrelated package
        // evidence, then select the inserted geometry-bearing Frame through
        // the real Layers UI.
        let legacyFrame = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Legacy Surface Frame"
        )).firstMatch
        XCTAssertTrue(legacyFrame.waitForExistence(timeout: 5))
        let frame = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"
        )).firstMatch
        XCTAssertTrue(frame.waitForExistence(timeout: 5))
        frame.click()
        application.buttons["inspector.tab.design"].click()
        let hex = application.textFields["inspector.design.fillHex"]
        let opacity = application.textFields["inspector.design.opacity"]
        XCTAssertTrue(hex.waitForExistence(timeout: 5))
        hex.click(); hex.typeKey("a", modifierFlags: .command); hex.typeText("#315A7C99"); hex.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(hex, containing: "#315A7C99"))
        let designAnnouncement = application.descendants(matching: .any)["inspector.design.announcement"]
        XCTAssertTrue(waitForValue(designAnnouncement, containing: "Design solid-fill committed"))
        opacity.click(); opacity.typeKey("a", modifierFlags: .command); opacity.typeText("60"); opacity.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(opacity, containing: "60 percent"))
        XCTAssertTrue(waitForValue(designAnnouncement, containing: "Design opacity committed"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 native saved appearance")

        // Drive the visible native File command while the real opacity field
        // remains first responder. This proves the document command route is
        // independent of an AppKit inspector control owning keyboard focus.
        application.menuBars.menuBarItems["File"].click()
        let save = application.menuItems["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isEnabled)
        // Invoke the visible, enabled native menu item itself. This exercises
        // the production command target even while an AppKit Inspector field
        // owns first responder, without assuming keyboard routing through a
        // system menu-tracking loop.
        save.click()
        let saveStatus = application.descendants(matching: .any)["status.document"].firstMatch
        XCTAssertTrue(
            waitForLiveDocumentStatus(
                in: application,
                containing: "Saved",
                timeout: 5
            ),
            "Native Save must complete before the process is closed; live status: \(saveStatus.label)"
        )
        terminateAndWait(application)

        // Reopen with a separate empty recovery directory. The assertions
        // below must therefore read the package written by Save rather than
        // accidentally adopting the prior process's recovery artifact.
        let reopenRecoveryDirectory = fixtureRoot.appendingPathComponent("reopen-recovery", isDirectory: true)
        application = launchExistingIntegrationProject(project, recoveryDirectory: reopenRecoveryDirectory)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertFalse(application.descendants(matching: .any)["canvas.empty.state"].exists)
        let selectionStatus = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(waitForValue(selectionStatus, containing: "0 selected"))
        application.buttons["navigator.tab.layers"].click()
        let reopenedLegacyFrame = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Legacy Surface Frame"
        )).firstMatch
        XCTAssertTrue(reopenedLegacyFrame.waitForExistence(timeout: 5))
        let reopenedFrame = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"
        )).firstMatch
        XCTAssertTrue(reopenedFrame.waitForExistence(timeout: 5))
        reopenedFrame.click()
        application.buttons["inspector.tab.design"].click()
        let reopenedHex = application.textFields["inspector.design.fillHex"]
        let reopenedOpacity = application.textFields["inspector.design.opacity"]
        XCTAssertTrue(waitForValue(reopenedHex, containing: "#315A7C99"))
        XCTAssertTrue(waitForValue(reopenedOpacity, containing: "60 percent"))
        XCTAssertTrue(reopenedFrame.isSelected)
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 native reopened appearance")
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
        let emptySelectionStatus = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(emptySelectionStatus.label.contains("No selection"))
        XCTAssertTrue((emptySelectionStatus.value as? String)?.contains("0 selected") == true)
        attachScreenshot(named: "SF-AUTHORING-004 empty selection")

        layers[0].click()
        XCTAssertTrue((layers[0].value as? String)?.contains("Primary selection") == true)
        let singleStatus = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(singleStatus.label.contains("Fixture Layer 1"))
        XCTAssertTrue((singleStatus.value as? String)?.contains("1 selected; primary selection present") == true)
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
        XCTAssertTrue((layers[1].value as? String)?.contains("Primary selection") == true)
        XCTAssertFalse(
            (layers[2].value as? String)?.contains("Primary selection") == true,
            "The nonvisual structural Root must remain outside visible-object keyboard traversal"
        )
    }

    private var fixtureLease: ApplicationOwnedTestFixture!
    private var launchedApplications: [XCUIApplication] = []
    private var fixtureRoot: URL { fixtureLease.url }
    private var recoveryDirectory: URL {
        fixtureRoot.appendingPathComponent("recovery", isDirectory: true)
    }
    private var uiTestRunID = ""
    private var launchStateRecords: [String] = []
    private var lifecycleDiagnosticURL: URL {
        fixtureRoot.appendingPathComponent("launch-lifecycle.txt")
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Integration packages and recovery artifacts exercise descriptor-bound
        // application-owned I/O. Keep them in the same private temporary
        // container policy used by the package tests—not in a checkout whose
        // ancestor can be mediated by a File Provider.
        fixtureLease = try ApplicationOwnedTestFixture.create("ui")
        uiTestRunID = ProcessInfo.processInfo.environment["SITEFORGE_TEST_RUN_ID"]
            ?? UUID().uuidString.lowercased()
        launchStateRecords.removeAll(keepingCapacity: true)
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
        application.launchArguments += baseLaunchArguments()
        if let windowAlignment {
            application.launchArguments += ["-SiteForgeUITestWindowAlignment", windowAlignment.rawValue]
        }
        if let verticalAlignment {
            application.launchArguments += ["-SiteForgeUITestWindowVerticalAlignment", verticalAlignment.rawValue]
        }
        recordLaunchState("before-launch", application)
        application.launch()
        recordLaunchState("after-launch", application)
        application.activate()
        recordLaunchState("after-activate", application)

        XCTAssertTrue(waitForLaunchWindow(application))
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
        application.launchArguments += baseLaunchArguments() + [
            "-SiteForgeLaunchScenario", scenario,
        ]
        if reduceMotion {
            application.launchArguments += ["-SiteForgeReduceMotion", "YES"]
        }
        application.launchArguments += extraArguments
        recordLaunchState("before-launch", application)
        application.launch()
        recordLaunchState("after-launch", application)
        application.activate()
        recordLaunchState("after-activate", application)
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

    /// Every UI launch is a new test-owned application session. In
    /// particular, SwiftUI must not restore a previous zero-window scene,
    /// because that makes the real AppKit window absent rather than merely
    /// late in the accessibility hierarchy.
    private func baseLaunchArguments(recoveryDirectory overrideRecoveryDirectory: URL? = nil) -> [String] {
        [
            "-NSTreatUnknownArgumentsAsOpen", "NO",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleKeyboardUIMode", "3",
            "-SiteForgeUITestMode", "YES",
            "-SiteForgeUITestRunID", uiTestRunID,
            "-SiteForgeUITestDiagnosticPath", lifecycleDiagnosticURL.path,
            "-SiteForgeRecoveryDirectory", (overrideRecoveryDirectory ?? recoveryDirectory).path,
        ]
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

    private func assertElement(
        _ element: XCUIElement,
        isContainedIn container: XCUIElement,
        _ description: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(element.exists, description ?? element.identifier, file: file, line: line)
        XCTAssertTrue(container.exists, container.identifier, file: file, line: line)
        let permittedBounds = container.frame.insetBy(dx: -1, dy: -1)
        XCTAssertTrue(
            permittedBounds.contains(element.frame),
            "\(description ?? element.identifier) frame \(element.frame) is outside \(container.identifier) frame \(container.frame)",
            file: file,
            line: line
        )
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
        let lifecycle = XCTAttachment(string: launchLifecycleDiagnostics(for: application))
        lifecycle.name = "workspace-launch-lifecycle-diagnostics"
        lifecycle.lifetime = .keepAlways
        add(lifecycle)
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
        let application = XCUIApplication(bundleIdentifier: Self.applicationBundleIdentifier)
        launchedApplications.append(application)
        return application
    }

    private func waitForLaunchWindow(_ application: XCUIApplication) -> Bool {
        let window = application.windows.firstMatch
        let visible = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { [weak self] object, _ in
                    guard let self, let element = object as? XCUIElement, element.exists else {
                        return false
                    }
                    return self.hasNoAppLifecycleHandshake || self.appReportedVisibleWindow()
                },
                object: window
            )],
            timeout: 5
        ) == .completed
        if !visible { attachReadinessDiagnostics(for: application) }
        return visible
    }

    /// New app compositions provide this test-only acknowledgement only after
    /// a real AppKit window has become visible. Clean historical baselines do
    /// not contain the diagnostic owner, so their genuine AX window remains
    /// the compatibility handshake.
    private var hasNoAppLifecycleHandshake: Bool {
        !FileManager.default.fileExists(atPath: lifecycleDiagnosticURL.path)
    }

    private func appReportedVisibleWindow() -> Bool {
        guard let records = try? String(contentsOf: lifecycleDiagnosticURL, encoding: .utf8) else {
            return false
        }
        return LaunchLifecycleReadinessHandshake.reportsUsableWindow(in: records)
    }

    private func launchLifecycleDiagnostics(for application: XCUIApplication) -> String {
        let records = (try? String(contentsOf: lifecycleDiagnosticURL, encoding: .utf8)) ?? "<no app lifecycle record>"
        return """
        expectedBundle=\(Self.applicationBundleIdentifier)
        observedState=\(application.state.rawValue)
        xcuiApplicationStates:
        \(launchStateRecords.joined(separator: "\n"))
        lifecycleRecords:
        \(records)
        """
    }

    private func recordLaunchState(_ phase: String, _ application: XCUIApplication) {
        launchStateRecords.append("phase=\(phase);state=\(application.state.rawValue);bundle=\(Self.applicationBundleIdentifier)")
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
        application.launchArguments += baseLaunchArguments() + [
            "-SiteForgeIntegrationOpenProject", url.path,
            "-SiteForgeIntegrationPackageBase64", base64Fixture.path,
        ]
        if startMalformed { application.launchArguments.append("-SiteForgeIntegrationStartMalformed") }
        if let retryBase64Fixture {
            application.launchArguments += ["-SiteForgeIntegrationRetryBase64", retryBase64Fixture.path]
        }
        recordLaunchState("before-launch", application)
        application.launch()
        recordLaunchState("after-launch", application)
        application.activate()
        recordLaunchState("after-activate", application)
        XCTAssertTrue(application.windows.firstMatch.waitForExistence(timeout: 5))
        return application
    }

    /// Reopens already-created bytes through the production loader. This
    /// deliberately omits the fixture-writing argument so native Save bytes
    /// from the preceding app lifetime cannot be replaced by a test fixture.
    private func launchExistingIntegrationProject(
        _ url: URL,
        recoveryDirectory: URL? = nil
    ) -> XCUIApplication {
        continueAfterFailure = false
        let application = trackedApplication()
        application.launchArguments += baseLaunchArguments(recoveryDirectory: recoveryDirectory) + [
            "-SiteForgeIntegrationOpenProject", url.path,
        ]
        recordLaunchState("before-reopen", application)
        application.launch()
        recordLaunchState("after-reopen", application)
        application.activate()
        XCTAssertTrue(waitForWorkspaceReady(application))
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

    // SF-0201-002, SF-0201-006, SF-0201-008, SF-0401-006,
    // SF-0508-006, SF-1605-006 — the actual minimum workspace must not expose
    // clipped controls only through accessibility. Every named viewport action
    // and a deeply nested fill stop remains visibly contained and reachable.
    @MainActor
    func testMinimumWorkspaceContainsViewportAndScrollableFillInspectorControls() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWindowSize", "minimum",
        ])
        let shell = application.descendants(matching: .any)["workspace.shell"]
        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        if abs(shell.frame.width - 1_100) > 2 {
            attachReadinessDiagnostics(for: application)
        }
        XCTAssertEqual(shell.frame.width, 1_100, accuracy: 2)
        XCTAssertGreaterThanOrEqual(shell.frame.height, 700 - 2)

        // The minimum-layout contract is a real pointer contract, so restore
        // the launched application to the foreground immediately before
        // checking its trailing controls. Developer tooling may legitimately
        // become active while the launch/readiness diagnostics settle; an
        // occluding foreign window must not be misclassified as SiteForge
        // clipping its Inspector.
        application.activate()
        for identifier in ["navigator.tab.overflow", "inspector.tab.overflow"] {
            let overflow = application.descendants(matching: .any)[identifier]
            XCTAssertTrue(waitForHittable(overflow, in: application), identifier)
        }

        let canvasRegion = application.descendants(matching: .any)["shell.canvas"]
        let viewportControls = application.descendants(matching: .any)["canvas.viewport.controls"]
        XCTAssertTrue(viewportControls.exists)
        assertElement(viewportControls, isContainedIn: canvasRegion)

        for identifier in [
            "canvas.viewport.preset",
            "canvas.grid.toggle",
            "canvas.zoom.out",
            "canvas.zoom.in",
            "canvas.zoom.reset",
            "canvas.zoom.fitCanvas",
            "canvas.zoom.fit",
            "canvas.empty.insert.frame",
            "canvas.empty.insert.text",
        ] {
            let control = application.descendants(matching: .any)[identifier]
            XCTAssertTrue(waitForHittable(control, in: application), identifier)
            assertElement(control, isContainedIn: viewportControls, identifier)
        }

        application.buttons["canvas.empty.insert.frame"].click()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["inspector.tab.design"].click()

        let inspector = application.descendants(matching: .any)["shell.inspector"]
        let inspectorScroll = application.descendants(matching: .any)["inspector.selection.scroll"]
        XCTAssertTrue(inspectorScroll.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(inspector.frame.width, 280 - 2)
        assertElement(inspectorScroll, isContainedIn: inspector)

        let addGradient = application.buttons["inspector.design.layers.addGradient"]
        XCTAssertTrue(waitForHittable(addGradient, in: application))
        addGradient.click()
        let angle = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS %@", ".angle"))
            .firstMatch
        XCTAssertTrue(angle.waitForExistence(timeout: 5))
        let gradientPrefix = angle.identifier.replacingOccurrences(of: ".angle", with: "")
        let addStopIdentifier = "\(gradientPrefix).addStop"
        for _ in 0..<4 {
            let addStop = application.buttons[addStopIdentifier]
            for _ in 0..<8 where !addStop.isHittable {
                let controlFrame = addStop.frame
                let viewportFrame = inspectorScroll.frame
                if controlFrame.maxY > viewportFrame.maxY {
                    inspectorScroll.scroll(byDeltaX: 0, deltaY: -100)
                } else if controlFrame.minY < viewportFrame.minY {
                    inspectorScroll.scroll(byDeltaX: 0, deltaY: 100)
                } else {
                    break
                }
            }
            XCTAssertTrue(waitForHittable(addStop, in: application))
            addStop.click()
        }

        let removeStops = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "\(gradientPrefix).stop.", ".remove"
        ))
        XCTAssertEqual(removeStops.count, 6)
        let lastRemove = removeStops.element(boundBy: 5)
        for _ in 0..<8 {
            if lastRemove.isHittable { break }
            inspectorScroll.scroll(byDeltaX: 0, deltaY: -180)
        }
        XCTAssertTrue(waitForHittable(lastRemove, in: application))
        let lastStopPrefix = lastRemove.identifier.replacingOccurrences(of: ".remove", with: "")
        let lastRow = application.descendants(matching: .any)["\(lastStopPrefix).row"]
        XCTAssertTrue(lastRow.waitForExistence(timeout: 3))
        assertElement(lastRow, isContainedIn: inspectorScroll)
        for suffix in [".position", ".color", ".up", ".down", ".remove"] {
            let control = application.descendants(matching: .any)["\(lastStopPrefix)\(suffix)"]
            XCTAssertTrue(control.exists, suffix)
            assertElement(control, isContainedIn: lastRow, suffix)
        }
        attachWindowScreenshot(application, named: "minimum viewport and scrollable fill Inspector")
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
        for identifier in ["section", "stack", "grid"] {
            let item = application.buttons["navigator.elements.\(identifier)"]
            XCTAssertTrue(item.exists, identifier)
            XCTAssertTrue(item.isEnabled, identifier)
            XCTAssertTrue(item.label == identifier.capitalized)
        }
        for identifier in ["button", "link", "divider", "navbar", "footer"] {
            let item = application.buttons["navigator.elements.\(identifier)"]
            XCTAssertTrue(item.exists, identifier)
            XCTAssertFalse(item.isEnabled, identifier)
        }

        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        for (offset, name) in ["Section", "Stack", "Grid"].enumerated() {
            let item = application.buttons["navigator.elements.\(name.lowercased())"]
            item.click()
            XCTAssertTrue(waitForValue(canvas, containing: "rendered objects \(offset + 1)"), name)
            XCTAssertTrue(application.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch.waitForExistence(timeout: 3), name)
            XCTAssertTrue(application.buttons["toolbar.undo"].isEnabled)
            application.typeKey("z", modifierFlags: .command)
            XCTAssertTrue(application.buttons["toolbar.redo"].waitForExistence(timeout: 3))
            application.typeKey("z", modifierFlags: [.command, .shift])
        }

        frame.click()
        XCTAssertEqual(application.buttons["toolbar.tool.frame"].value as? String, "Selected")
        application.typeKey(.escape, modifierFlags: [])

        let assets = application.buttons["navigator.tab.assets"]
        XCTAssertTrue(waitForHittable(assets, in: application))
        assets.click()
        XCTAssertTrue(application.descendants(matching: .any)["navigator.assets.unavailable"].exists)

        // Components can be beyond the horizontally scrolled tab strip at
        // the practical minimum width. Use the real, always-visible native
        // overflow menu rather than assuming its direct tab is on screen.
        let navigatorOverflow = application.descendants(matching: .any)["navigator.tab.overflow"]
        XCTAssertTrue(waitForHittable(navigatorOverflow, in: application))
        navigatorOverflow.click()
        let componentsMenuItem = application.menuItems["Components"]
        XCTAssertTrue(componentsMenuItem.waitForExistence(timeout: 3))
        componentsMenuItem.click()
        XCTAssertTrue(application.descendants(matching: .any)["navigator.components.unavailable"].waitForExistence(timeout: 3))
    }

    // SF-0402-001 through SF-0402-008, SF-0407-001 through SF-0407-006
    // The virtual canvas accessibility object and the selected render object
    // are both derived from the adopted render plan. This fresh-process
    // journey retains one settled application-window image for every
    // supported authored kind, so enclosure by the editor-only outline is a
    // visual contract rather than an object-count-only assertion.
    @MainActor
    func testSupportedElementsShareSelectedRenderGeometryJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"))
        func assertSelection(_ kind: String, count: Int) {
            XCTAssertTrue(
                waitForLiveCanvasValue(
                    in: application,
                    containing: "rendered objects \(count)",
                    timeout: 5
                ),
                "\(kind): \(String(describing: liveCanvas(in: application).value))"
            )

            let object = canvasObject(named: kind == "Text" ? "Text object" : kind, in: application)
            XCTAssertTrue(object.waitForExistence(timeout: 3), kind)
            XCTAssertTrue(object.isSelected, "\(kind) must expose the same selected render identity")
            XCTAssertGreaterThan(object.frame.width, 0)
            XCTAssertGreaterThan(object.frame.height, 0)
            XCTAssertTrue(application.descendants(matching: .any)["inspector.selection.summary"].exists)
            attachWindowScreenshot(application, named: "SF-AUTHORING-012 geometry \(kind.lowercased()) selected")
        }
        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.section"].click()
        assertSelection("Section", count: 1)
        application.buttons["navigator.elements.stack"].click()
        assertSelection("Stack", count: 2)
        application.buttons["navigator.tab.layers"].click()
        let sectionLayer = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section"))
            .firstMatch
        XCTAssertTrue(sectionLayer.waitForExistence(timeout: 3))
        sectionLayer.click()
        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.grid"].click()
        assertSelection("Grid", count: 3)
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Frame at Center"].click()
        assertSelection("Frame", count: 4)
        application.buttons["navigator.tab.layers"].click()
        XCTAssertTrue(sectionLayer.waitForExistence(timeout: 3))
        sectionLayer.click()
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Text at Center"].click()
        assertSelection("Text", count: 5)
    }

    // SF-0501-001 through SF-0503-008 — visible catalog/menu operations
    // create canonical hierarchy, and the adopted renderer/selection surface
    // uses the same resolved parent-child geometry.
    @MainActor
    func testStructuralElementsNestThroughCatalogAndInsertMenuJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"))

        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.section"].click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        let section = canvasObject(named: "Section", in: application)
        XCTAssertTrue(section.waitForExistence(timeout: 3))
        XCTAssertTrue(application.descendants(matching: .any)["inspector.selection.summary"].waitForExistence(timeout: 3))

        // The selected Section is the validated parent for the Stack.
        application.buttons["navigator.elements.stack"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        let stack = canvasObject(named: "Stack", in: application)
        XCTAssertTrue(stack.waitForExistence(timeout: 3))

        application.menuBars.menuBarItems["Insert"].click()
        let frameCommand = application.menuItems["Insert Frame at Center"]
        XCTAssertTrue(frameCommand.waitForExistence(timeout: 2))
        XCTAssertTrue(frameCommand.isEnabled)
        frameCommand.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        let stackChild = canvasObject(named: "Frame", in: application)
        XCTAssertTrue(stackChild.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(stackChild.frame.minX, stack.frame.minX)
        XCTAssertGreaterThan(stackChild.frame.minY, stack.frame.minY)

        // Select the Section from the real Layers navigator, then create a
        // Grid below its Stack. The Grid is selected after commit, making the
        // two menu-inserted Frames its row-major children.
        application.buttons["navigator.tab.layers"].click()
        let sectionLayer = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section"))
            .firstMatch
        XCTAssertTrue(sectionLayer.waitForExistence(timeout: 3))
        sectionLayer.click()
        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.grid"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 4", timeout: 5))
        let grid = canvasObject(named: "Grid", in: application)
        XCTAssertTrue(grid.waitForExistence(timeout: 3))

        for expectedCount in [5, 6] {
            application.menuBars.menuBarItems["Insert"].click()
            application.menuItems["Insert Frame at Center"].click()
            XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects \(expectedCount)", timeout: 5))
        }
        // Canvas count is the live adopted render plan (not a catalogue
        // fixture); exact Stack/Grid child geometry is asserted at the shared
        // headless resolver boundary, where AX viewport clipping cannot hide
        // valid offscreen children.
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 6", timeout: 5))

        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 5", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 6", timeout: 5))
        attachScreenshot(named: "SF-AUTHORING-010 nested section stack grid")
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
        let application = launchWorkspace(windowAlignment: .right, verticalAlignment: .bottom)
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
        XCTAssertFalse((canvas.value as? String)?.contains("Zoom 100 percent") == true)
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

        application.buttons["canvas.zoom.reset"].click()
        XCTAssertTrue(waitForValue(canvas, containing: "Zoom 100 percent"))
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

    // SF-0401-001 through SF-0401-008 — editor-only world-grid orientation
    // remains behind the artboard and never changes the selected authored
    // render identity while viewport commands change.
    @MainActor
    func testWorldGridArtboardHierarchyVisualJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"))
        let grid = application.descendants(matching: .any)["canvas.grid.toggle"]
        XCTAssertTrue(waitForHittable(grid, in: application))
        XCTAssertTrue(grid.isSelected || (grid.value as? NSNumber)?.intValue == 1 || (grid.value as? String)?.contains("On") == true)

        application.buttons["canvas.empty.insert.frame"].click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.activeTool"], containing: "Select"))
        XCTAssertFalse(application.descendants(matching: .any)["status.insertion"].exists)
        let frame = canvasObject(named: "Frame", in: application)
        XCTAssertTrue(frame.waitForExistence(timeout: 3))
        let identity = frame.identifier
        let selectionPath = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(frame.isSelected)
        // New documents fit the real artboard with a visible surrounding
        // pasteboard/grid gutter instead of letting Desktop 1440 consume the
        // entire viewport at actual size.
        XCTAssertFalse((canvas.value as? String)?.contains("Zoom 100 percent") == true)
        attachWindowScreenshot(application, named: "SF-GRID desktop fitted")

        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        preset.click(); application.menuItems["Tablet"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Tablet"))
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        XCTAssertTrue(waitForLabel(application.descendants(matching: .any)["status.selectionPath"], containing: "Frame"))
        // Selection context is editor chrome, not authored content.  A
        // partially clipped Frame remains selected, but its readable badge
        // must be laid out wholly inside the visible Tablet artboard rather
        // than bleeding over the surrounding pasteboard.
        let tabletFrame = canvasObject(named: "Frame", in: application)
        XCTAssertTrue(tabletFrame.waitForExistence(timeout: 3))
        assertElement(
            tabletFrame,
            isContainedIn: canvas,
            "SF-0407-006 partially clipped Frame accessibility target"
        )
        let nodeIdentity = identity.replacingOccurrences(of: "canvas.object.", with: "")
        let selectionContext = application.descendants(matching: .any)["canvas.selection.context.\(nodeIdentity)"]
        XCTAssertTrue(selectionContext.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLabel(selectionContext, containing: "Frame"))
        // A badge may be repositioned leftward to stay inside the artboard;
        // the clipped Frame's right edge is the meaningful pasteboard edge.
        XCTAssertLessThanOrEqual(selectionContext.frame.maxX, tabletFrame.frame.maxX + 1)
        attachWindowScreenshot(application, named: "SF-GRID tablet fitted")
        preset.click(); application.menuItems["Mobile"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Mobile"))
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        XCTAssertTrue(waitForLabel(application.descendants(matching: .any)["status.selectionPath"], containing: "Frame"))
        let offArtboard = application.descendants(matching: .any)["status.selection.artboard"]
        XCTAssertTrue(offArtboard.waitForExistence(timeout: 3))
        // SwiftUI exposes a static status Label's spoken content as AXValue on
        // macOS. Assert that semantic value rather than the unrelated shell
        // selection-path value or an empty platform label.
        XCTAssertTrue(waitForValue(offArtboard, containing: "outside Mobile artboard"))
        XCTAssertTrue(application.buttons["canvas.selection.reveal"].isHittable)
        // The canonical selection remains but no normal object/selection
        // overlay is virtualized beyond the Mobile artboard clip.
        XCTAssertFalse(canvasObject(named: "Frame", in: application).exists)
        attachWindowScreenshot(application, named: "SF-GRID mobile fitted off-artboard")

        application.buttons["canvas.selection.reveal"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Desktop"))
        let revealedByAction = canvasObject(named: "Frame", in: application)
        XCTAssertTrue(revealedByAction.waitForExistence(timeout: 3))
        XCTAssertEqual(revealedByAction.identifier, identity)
        XCTAssertTrue(revealedByAction.isSelected)
        XCTAssertFalse(offArtboard.exists)
        attachWindowScreenshot(application, named: "SF-GRID reveal selection")

        application.menuBars.menuBarItems["View"].click()
        // Native menu commands are AXMenuItem instances whose visible title
        // is Grid (not the toolbar checkbox's accessibility identifier).
        // Opening View scopes the first visible match to this actual command.
        let menuGrid = application.menuItems["Grid"].firstMatch
        XCTAssertTrue(menuGrid.waitForExistence(timeout: 2)); menuGrid.click()
        XCTAssertFalse(grid.isSelected)
        attachWindowScreenshot(application, named: "SF-GRID off")
        grid.click(); XCTAssertTrue(grid.isSelected || (grid.value as? NSNumber)?.intValue == 1 || (grid.value as? String)?.contains("On") == true)
        application.buttons["canvas.zoom.in"].click()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.65)).scroll(byDeltaX: 80, deltaY: 0)
        // Virtual canvas AX objects remain bounded to the visible artboard;
        // a pan may correctly virtualize this offscreen frame. The canonical
        // selection identity must nevertheless remain in scene-local status.
        XCTAssertTrue(waitForLabel(selectionPath, containing: "Frame"))
        attachWindowScreenshot(application, named: "SF-GRID positive pan zoom")
        application.buttons["canvas.zoom.fit"].click()
        let revealedFrame = canvasObject(named: "Frame", in: application)
        XCTAssertTrue(revealedFrame.waitForExistence(timeout: 3))
        XCTAssertEqual(revealedFrame.identifier, identity); XCTAssertTrue(revealedFrame.isSelected)
        attachWindowScreenshot(application, named: "SF-GRID fit document")
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
        application.launchArguments += baseLaunchArguments() + [
            "-SiteForgeIntegrationRecoveryBase64", recoveryBytes.path,
            "-SiteForgeIntegrationRecoveryDestination", recovery.path,
        ]
        recordLaunchState("before-launch", application)
        application.launch()
        recordLaunchState("after-launch", application)
        application.activate()
        recordLaunchState("after-activate", application)
        let restore = application.buttons["launch.recovery.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 5))
        terminateAndWait(application)

        application = trackedApplication()
        application.launchArguments += baseLaunchArguments() + [
            "-SiteForgeIntegrationRecoveryBase64", recoveryBytes.path,
            "-SiteForgeIntegrationRecoveryDestination", recovery.path,
        ]
        recordLaunchState("before-launch", application)
        application.launch()
        recordLaunchState("after-launch", application)
        application.activate()
        recordLaunchState("after-activate", application)
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
        XCTAssertTrue(waitForLabel(
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

    private func waitForValue(
        _ element: XCUIElement,
        containing text: String,
        timeout: TimeInterval = 2
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String)?.contains(text) == true
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    /// Renderer adoption may replace the virtual canvas accessibility node.
    /// Query the live production node for an adopted render-plan assertion;
    /// retaining the original AX proxy would test a stale accessibility
    /// snapshot rather than the renderer's current canonical scene.
    private func waitForLiveCanvasValue(
        in application: XCUIApplication,
        containing text: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate { [weak application] _, _ in
            guard let application else { return false }
            let canvas = self.liveCanvas(in: application)
            return (canvas.value as? String)?.contains(text) == true
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: application)],
            timeout: timeout
        ) == .completed
    }

    private func liveCanvas(in application: XCUIApplication) -> XCUIElement {
        application.descendants(matching: .any)["canvas.interaction"].firstMatch
    }

    /// Save transitions can replace the status view's AX proxy. Query the live
    /// shipping status element so the assertion observes durable completion,
    /// not an obsolete pre-save accessibility snapshot.
    private func waitForLiveDocumentStatus(
        in application: XCUIApplication,
        containing text: String,
        timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate { [weak application] _, _ in
            guard let application else { return false }
            let status = application.descendants(matching: .any)["status.document"].firstMatch
            // SwiftUI may replace the status Label's AX proxy as lifecycle
            // state changes. Native macOS exposes the shipping label through
            // either AXLabel or AXValue depending on that replacement; both
            // are semantic status properties and must report the same Saved
            // lifecycle state.
            return status.label.contains(text) || (status.value as? String)?.contains(text) == true
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: application)],
            timeout: timeout
        ) == .completed
    }

    private func waitForLiveElementValueToChange(
        in application: XCUIApplication,
        identifier: String,
        from value: String,
        timeout: TimeInterval = 3
    ) -> Bool {
        let predicate = NSPredicate { [weak application] _, _ in
            guard let application else { return false }
            let element = application.descendants(matching: .any)[identifier].firstMatch
            return (element.value as? String) != value
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: application)],
            timeout: timeout
        ) == .completed
    }

    private func waitForLabel(
        _ element: XCUIElement,
        containing text: String,
        timeout: TimeInterval = 2
    ) -> Bool {
        let predicate = NSPredicate { object, _ in
            (object as? XCUIElement)?.label.contains(text) == true
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)],
            timeout: timeout
        ) == .completed
    }

    private func canvasObject(named name: String, in application: XCUIApplication) -> XCUIElement {
        application.descendants(matching: .any)
            .matching(NSPredicate(
                format: "label == %@ AND identifier BEGINSWITH %@",
                name,
                "canvas.object."
            ))
            .firstMatch
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
