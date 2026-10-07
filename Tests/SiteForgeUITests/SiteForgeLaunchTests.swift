import AppKit
import ImageIO
import UniformTypeIdentifiers
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

private enum PointerWindowPlacement {
    @MainActor
    static func moveWindowHorizontally(by delta: CGFloat, in application: XCUIApplication) {
        let start = application.toolbars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let point = start.screenPoint
        // Coordinates track their referenced element. Anchor the destination
        // to the stationary menu bar, not the window being dragged.
        let anchor = application.menuBars.firstMatch.coordinate(withNormalizedOffset: .zero)
        let origin = anchor.screenPoint
        let destination = anchor.withOffset(CGVector(dx: point.x + delta - origin.x, dy: point.y - origin.y))
        start.click(forDuration: 0.1, thenDragTo: destination)
    }

    // Align the *live target* to the usable display. The production window may
    // intentionally exceed a narrow display, so window-edge alignment alone
    // cannot guarantee a control in its obscured strip becomes hittable.
    static func horizontalTranslation(window: CGRect, target: CGRect, visible: CGRect) -> CGFloat {
        _ = window // Width is preserved by the native title-bar drag.
        if target.minX < visible.minX { return visible.minX - target.minX }
        if target.maxX > visible.maxX { return visible.maxX - target.maxX }
        return 0
    }
}

@MainActor
final class SiteForgeLaunchTests: XCTestCase {
    // SF-0206-002/004/006 — real native application preference-group reset.
    func testApplicationSettingsGroupResetCancelRestoreAndRelaunchJourney() {
        let application = launchWorkspace()
        let grid = application.descendants(matching: .any)["canvas.grid.toggle"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        application.typeKey(",", modifierFlags: .command)
        @MainActor func tab(_ name: String) {
            let button = application.toolbars.buttons[name]
            XCTAssertTrue(button.waitForExistence(timeout: 5), application.debugDescription)
            button.click()
        }
        @MainActor func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: application.windows.firstMatch.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        @MainActor func isOn(_ element: XCUIElement) -> Bool {
            element.isSelected || (element.value as? NSNumber)?.intValue == 1
                || (element.value as? String)?.contains("On") == true
        }

        tab("Appearance")
        let originalAppearance = ["Follow macOS", "Light", "Dark"].first {
            (application.radioButtons[$0].value as? NSNumber)?.intValue == 1
        } ?? "Follow macOS"
        let originalAppearanceDefault = (application.staticTexts["settings.appearance.provenance"].value as? String)?
            .contains("Default") == true
        if originalAppearance != "Dark" { application.radioButtons["Dark"].click() }
        if application.buttons["settings.appearance.apply"].isEnabled {
            application.buttons["settings.appearance.apply"].click()
        }
        tab("Canvas")
        let canvasSetting = application.checkBoxes["settings.canvas.gridDefault"]
        XCTAssertTrue(canvasSetting.waitForExistence(timeout: 5))
        let originalCanvas = isOn(canvasSetting)
        let originalCanvasDefault = (application.staticTexts["settings.canvas.provenance"].value as? String)?
            .contains("Default") == true
        if isOn(canvasSetting) { canvasSetting.click() }
        if application.buttons["settings.canvas.apply"].isEnabled {
            application.buttons["settings.canvas.apply"].click()
        }

        tab("Reset")
        capture("SF-AUTHORING-065 application defaults before reset")
        let stage = application.buttons["settings.group.stage"]
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        stage.click()
        XCTAssertTrue(application.buttons["settings.group.confirm"].isEnabled)
        capture("SF-AUTHORING-065 pending confirmation")
        application.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        XCTAssertTrue((application.staticTexts["settings.group.status"].value as? String)?.contains("cancelled") == true)
        stage.click()
        tab("Canvas")
        tab("Reset")
        XCTAssertFalse(application.buttons["settings.group.confirm"].exists)
        XCTAssertTrue((application.staticTexts["settings.group.status"].value as? String)?.contains("cancelled") == true)
        stage.click()
        application.buttons["settings.group.confirm"].click()
        XCTAssertTrue((application.staticTexts["settings.group.status"].value as? String)?.contains("reset") == true)
        capture("SF-AUTHORING-065 application defaults reset")
        tab("Appearance")
        XCTAssertEqual((application.radioButtons["Follow macOS"].value as? NSNumber)?.intValue, 1)
        tab("Canvas")
        XCTAssertTrue(isOn(application.checkBoxes["settings.canvas.gridDefault"]))
        tab("Reset")
        application.buttons["settings.group.restore"].click()
        XCTAssertTrue((application.staticTexts["settings.group.status"].value as? String)?.contains("restored") == true)
        capture("SF-AUTHORING-065 previous defaults restored")
        tab("Appearance")
        XCTAssertEqual((application.radioButtons["Dark"].value as? NSNumber)?.intValue, 1)
        tab("Canvas")
        XCTAssertFalse(isOn(application.checkBoxes["settings.canvas.gridDefault"]))

        tab("Reset")
        stage.click()
        application.buttons["settings.group.confirm"].click()
        application.terminate()
        application.launch(); application.activate()
        XCTAssertTrue(waitForLaunchWindow(application))
        XCTAssertTrue(application.buttons["launch.newBlankProject"].waitForExistence(timeout: 5))
        application.buttons["launch.newBlankProject"].click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        XCTAssertTrue(isOn(application.descendants(matching: .any)["canvas.grid.toggle"]))
        application.typeKey(",", modifierFlags: .command)
        tab("Appearance")
        XCTAssertEqual((application.radioButtons["Follow macOS"].value as? NSNumber)?.intValue, 1)
        tab("Canvas")
        XCTAssertTrue(isOn(application.checkBoxes["settings.canvas.gridDefault"]))
        capture("SF-AUTHORING-065 reset persists after relaunch")

        // Restore the test machine's original application preferences through
        // the same public native Settings controls, not a launch mutation.
        tab("Appearance")
        if originalAppearanceDefault { application.buttons["settings.appearance.reset"].click() }
        else { application.radioButtons[originalAppearance].click() }
        if application.buttons["settings.appearance.apply"].isEnabled {
            application.buttons["settings.appearance.apply"].click()
        }
        tab("Canvas")
        if originalCanvasDefault { application.buttons["settings.canvas.reset"].click() }
        else if !originalCanvas { application.checkBoxes["settings.canvas.gridDefault"].click() }
        if application.buttons["settings.canvas.apply"].isEnabled {
            application.buttons["settings.canvas.apply"].click()
        }
        XCTAssertEqual(isOn(application.checkBoxes["settings.canvas.gridDefault"]), originalCanvas)
    }

    // SF-0206-002/003/004/006/008 — application default versus live scene Grid.
    func testCanvasSettingsGridDefaultAppliesOnlyToNewWorkspacesJourney() {
        let application = launchWorkspace()
        let grid = application.descendants(matching: .any)["canvas.grid.toggle"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        @MainActor func isOn(_ element: XCUIElement) -> Bool {
            element.isSelected || (element.value as? NSNumber)?.intValue == 1
                || (element.value as? String)?.contains("On") == true
        }
        let originalSceneGrid = isOn(grid)

        application.typeKey(",", modifierFlags: .command)
        let canvasTab = application.toolbars.buttons["Canvas"]
        XCTAssertTrue(canvasTab.waitForExistence(timeout: 5), application.debugDescription)
        canvasTab.click()
        let setting = application.checkBoxes["settings.canvas.gridDefault"]
        XCTAssertTrue(setting.waitForExistence(timeout: 5), application.debugDescription)
        let originalPreference = isOn(setting)
        let originalWasDefault = (application.staticTexts["settings.canvas.provenance"].value as? String)?
            .contains("Default") == true

        @MainActor func screenshot(_ name: String, window: XCUIElement) {
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let settingsWindow = application.windows.containing(.checkBox, identifier: "settings.canvas.gridDefault").firstMatch
        XCTAssertTrue(settingsWindow.exists)
        screenshot("SF-AUTHORING-064 Canvas Settings initial", window: settingsWindow)
        if isOn(setting) { setting.click() }
        XCTAssertFalse(isOn(setting))
        XCTAssertTrue(application.buttons["settings.canvas.apply"].isEnabled)
        XCTAssertTrue(isOn(grid) == originalSceneGrid)
        screenshot("SF-AUTHORING-064 Canvas Settings draft", window: settingsWindow)
        application.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertEqual(isOn(application.checkBoxes["settings.canvas.gridDefault"]), originalPreference)
        XCTAssertFalse(application.buttons["settings.canvas.apply"].isEnabled)
        if originalPreference { setting.click() }
        else {
            application.buttons["settings.canvas.reset"].click()
            setting.click()
        }
        XCTAssertTrue(application.buttons["settings.canvas.apply"].isEnabled)
        application.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertFalse(isOn(application.checkBoxes["settings.canvas.gridDefault"]))
        XCTAssertTrue((application.staticTexts["settings.canvas.status"].value as? String)?.contains("saved") == true)
        screenshot("SF-AUTHORING-064 Canvas Settings committed", window: settingsWindow)
        XCTAssertEqual(isOn(grid), originalSceneGrid)

        application.terminate()
        application.launch()
        application.activate()
        XCTAssertTrue(waitForLaunchWindow(application))
        XCTAssertTrue(application.buttons["launch.newBlankProject"].waitForExistence(timeout: 5))
        application.buttons["launch.newBlankProject"].click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        let freshGrid = application.descendants(matching: .any)["canvas.grid.toggle"]
        XCTAssertTrue(freshGrid.waitForExistence(timeout: 5))
        XCTAssertFalse(isOn(freshGrid))
        screenshot("SF-AUTHORING-064 new workspace inherits Grid Off", window: application.windows.firstMatch)
        freshGrid.click()
        XCTAssertTrue(isOn(application.descendants(matching: .any)["canvas.grid.toggle"]))
        screenshot("SF-AUTHORING-064 live workspace Grid On", window: application.windows.firstMatch)

        application.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(application.toolbars.buttons["Canvas"].waitForExistence(timeout: 5))
        application.toolbars.buttons["Canvas"].click()
        let restoredSetting = application.checkBoxes["settings.canvas.gridDefault"]
        XCTAssertTrue(restoredSetting.waitForExistence(timeout: 5))
        if originalWasDefault {
            application.buttons["settings.canvas.reset"].click()
        } else if originalPreference != isOn(restoredSetting) {
            restoredSetting.click()
        }
        if application.buttons["settings.canvas.apply"].isEnabled {
            application.buttons["settings.canvas.apply"].click()
        }
        XCTAssertEqual(isOn(application.checkBoxes["settings.canvas.gridDefault"]), originalPreference)
        XCTAssertEqual((application.staticTexts["settings.canvas.provenance"].value as? String)?
            .contains("Default") == true, originalWasDefault)
    }

    // SF-0206-002/003/004/006/008 — real native Settings, no document hooks.
    func testApplicationAppearanceSettingsPreviewApplyCancelResetJourney() {
        let application = launchWorkspace()
        application.typeKey(",", modifierFlags: .command)
        @MainActor func showAppearanceTab() {
            let tab = application.toolbars.buttons["Appearance"]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            tab.click()
        }
        showAppearanceTab()
        let apply = application.buttons["settings.appearance.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        let provenance = application.staticTexts["settings.appearance.provenance"]
        let originalWasDefault = (provenance.value as? String)?.contains("Default") == true
        let originalChoice = ["Follow macOS", "Light", "Dark"].first {
            (application.radioButtons[$0].value as? NSNumber)?.intValue == 1
        }
        XCTAssertNotNil(originalChoice)
        @MainActor func choose(_ title: String) {
            let radio = application.radioButtons[title]
            XCTAssertTrue(radio.isHittable, radio.debugDescription)
            XCTAssertTrue(radio.frame.minX.isFinite && radio.frame.minY.isFinite)
            radio.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
        @MainActor func awaitText(_ identifier: String, _ text: String) {
            let predicate = NSPredicate { _, _ in
                let live = application.staticTexts[identifier]
                return live.exists && (live.value as? String)?.contains(text) == true
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5), .completed)
        }
        defer {
            if originalWasDefault { application.buttons["settings.appearance.reset"].click() }
            else if let originalChoice { choose(originalChoice) }
            if application.buttons["settings.appearance.apply"].isEnabled {
                application.buttons["settings.appearance.apply"].click()
            }
        }
        application.buttons["settings.appearance.reset"].click()
        if application.buttons["settings.appearance.apply"].isEnabled {
            application.buttons["settings.appearance.apply"].click()
        }
        awaitText("settings.appearance.provenance", "Default")
        func capture(_ name: String) {
            let window = application.windows.containing(.button, identifier: "settings.appearance.apply").firstMatch
            XCTAssertTrue(window.exists)
            XCTAssertLessThan(window.frame.width, 700)
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        choose("Dark")
        XCTAssertTrue(application.buttons["settings.appearance.apply"].isEnabled)
        awaitText("settings.appearance.provenance", "Preview")
        capture("SF-SETTINGS dark preview")
        application.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertFalse(application.buttons["settings.appearance.apply"].isEnabled)
        choose("Light")
        application.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        awaitText("settings.appearance.status", "saved")
        awaitText("settings.appearance.provenance", "Authored")
        capture("SF-SETTINGS light committed")
        choose("Dark")
        application.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(application.windows.containing(.button, identifier: "settings.appearance.apply")
            .firstMatch.waitForNonExistence(timeout: 5))
        application.typeKey(",", modifierFlags: .command)
        showAppearanceTab()
        XCTAssertTrue(application.buttons["settings.appearance.apply"].waitForExistence(timeout: 5))
        XCTAssertEqual((application.radioButtons["Light"].value as? NSNumber)?.intValue, 1, application.debugDescription)
        XCTAssertFalse(application.buttons["settings.appearance.apply"].isEnabled)
        capture("SF-SETTINGS reopened cancellation")
        application.buttons["settings.appearance.reset"].click()
        application.buttons["settings.appearance.apply"].click()
        awaitText("settings.appearance.provenance", "Default")
        capture("SF-SETTINGS reset default")
        application.buttons["settings.appearance.restore"].click()
        XCTAssertEqual((application.radioButtons["Light"].value as? NSNumber)?.intValue, 1)
        awaitText("settings.appearance.status", "restored")
        application.terminate()
        application.launch()
        application.activate()
        XCTAssertTrue(waitForLaunchWindow(application))
        application.typeKey(",", modifierFlags: .command)
        showAppearanceTab()
        XCTAssertTrue(application.buttons["settings.appearance.apply"].waitForExistence(timeout: 5))
        XCTAssertEqual((application.radioButtons["Light"].value as? NSNumber)?.intValue, 1)
        awaitText("settings.appearance.provenance", "Authored")
        capture("SF-SETTINGS persisted after relaunch")
    }

    // SF-0206-004/006/008, SF-1507-003/004/006, SF-1602-004/006,
    // SF-1607-002/003/004/006/008 — native, content-free support workflow.
    func testSupportSettingsGeneratesReviewableRedactedReportJourney() {
        let application = launchWorkspace()
        application.typeKey(",", modifierFlags: .command)
        let supportTab = application.toolbars.buttons["Support"]
        XCTAssertTrue(supportTab.waitForExistence(timeout: 5), application.debugDescription)
        supportTab.click()

        let generate = application.buttons["settings.support.generate"]
        let copy = application.buttons["settings.support.copy"]
        let export = application.buttons["settings.support.export"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        XCTAssertTrue(generate.isHittable)
        XCTAssertFalse(copy.isEnabled)
        XCTAssertFalse(export.isEnabled)
        generate.click()

        let report = application.descendants(matching: .any)["settings.support.report"]
        XCTAssertTrue(report.waitForExistence(timeout: 5), application.debugDescription)
        XCTAssertTrue(copy.isEnabled)
        XCTAssertTrue(export.isEnabled)
        let value = report.value as? String ?? ""
        XCTAssertTrue(value.contains("SF-1607-008"), "Support report AX value: \(String(reflecting: report.value))")
        XCTAssertTrue(value.contains("Installed distribution"))
        XCTAssertFalse(value.contains("/Users/"))
        XCTAssertFalse(value.contains("file://"))

        let window = application.windows.containing(.button, identifier: "settings.support.generate").firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertLessThanOrEqual(window.frame.width, 700)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "SF-AUTHORING-104 Support Settings redacted report"
        attachment.lifetime = .keepAlways
        add(attachment)

        copy.click()
        let status = application.staticTexts["settings.support.status"]
        XCTAssertTrue((status.value as? String)?.contains("copied") == true)
    }

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

    /// The product deliberately preserves its 1100-point minimum on a
    /// narrower display. Journeys whose pointer contract is entirely in the
    /// navigator opt into the existing leading-edge constrained placement on
    /// those displays; ordinary displays continue to exercise the normal
    /// maximized window policy.
    private var leadingEdgeAlignmentOnNarrowDisplay: TestWindowAlignment? {
        guard let visibleWidth = NSScreen.main?.visibleFrame.width,
              visibleWidth < 1_100 else { return nil }
        return .left
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
        XCTAssertTrue(waitForKeyboardFocus(identifier: "canvas.text.editor", in: application))
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
        replaceText(in: editor, with: "Cancelled", application: application)
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
        XCTAssertTrue(waitForKeyboardFocus(identifier: "canvas.text.editor", in: application))
        editor.typeKey(.upArrow, modifierFlags: .command)
        editor.typeKey(.downArrow, modifierFlags: [.command, .shift])
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
        replaceStructuralLayoutField(xField, with: "121", in: application)
        XCTAssertTrue(waitForValueToChange(geometry, from: afterPointerResize))
        let afterNumericMove = try XCTUnwrap(geometry.value as? String)
        replaceStructuralLayoutField(yField, with: "122", in: application)
        XCTAssertTrue(waitForValueToChange(geometry, from: afterNumericMove))
        let afterNumericY = try XCTUnwrap(geometry.value as? String)
        replaceStructuralLayoutField(widthField, with: "241", in: application)
        XCTAssertTrue(waitForValueToChange(geometry, from: afterNumericY))
        let afterNumericWidth = try XCTUnwrap(geometry.value as? String)
        replaceStructuralLayoutField(heightField, with: "161", in: application)
        XCTAssertTrue(waitForValueToChange(geometry, from: afterNumericWidth))

        // Native focus loss commits a complete draft through the same typed
        // registry; no text-field draft becomes canonical while it is typed.
        let afterReturnCommit = try XCTUnwrap(geometry.value as? String)
        replaceText(in: xField, with: "131", application: application)
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
        replaceText(in: widthField, with: "0", application: application)
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

    // SF-0505-001...006/008 — native base sizing edits share the geometry
    // transaction and never replace the selected Frame with an editor proxy.
    func testNativeSizingConstraintsClampResetAndAccessibilityJourney() throws {
        let application = launchWorkspace()
        application.buttons["canvas.empty.insert.frame"].click()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["inspector.tab.layout"].click()
        let minimum = application.textFields["inspector.sizing.minWidth"]
        XCTAssertTrue(minimum.waitForExistence(timeout: 5))
        XCTAssertEqual(minimum.label, "Min width")
        XCTAssertTrue((minimum.value as? String)?.contains("Default") == true)
        let geometry = application.descendants(matching: .any)["inspector.transform.geometry"]
        let original = try XCTUnwrap(geometry.value as? String)
        replaceStructuralLayoutField(minimum, with: "300", in: application)
        XCTAssertTrue(waitForValue(minimum, containing: "300"))
        XCTAssertTrue(waitForValueToChange(geometry, from: original))
        XCTAssertTrue(application.buttons["toolbar.undo"].isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-058 minimum width authored")
        let lock = application.descendants(matching: .any)["inspector.sizing.aspectLock"]
        XCTAssertTrue(lock.waitForExistence(timeout: 3))
        XCTAssertTrue(lock.isEnabled)
        lock.click()
        XCTAssertTrue(application.textFields["inspector.sizing.aspectRatio"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-058 aspect locked")
        let reset = application.buttons["inspector.sizing.reset"]
        XCTAssertTrue(reset.isHittable)
        reset.click()
        XCTAssertTrue(waitForValue(minimum, containing: "Default"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-058 reset")
    }

    // SF-0601-001...006/008; SF-0602-001...006/008
    func testResponsiveBreakpointGeometryAuthoringUndoResetAndAccessibilityJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        application.buttons["canvas.empty.insert.frame"].click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["inspector.tab.layout"].click()
        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        let xField = application.textFields["inspector.layout.x"]
        XCTAssertTrue(xField.waitForExistence(timeout: 5))
        XCTAssertTrue((xField.value as? String)?.contains("Desktop") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-016 Desktop base inherited geometry")

        preset.click(); application.menuItems["Tablet"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Tablet"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Inherited from Desktop"))
        let tabletX = application.textFields["inspector.layout.x"]
        XCTAssertTrue(tabletX.waitForExistence(timeout: 3))
        XCTAssertTrue(tabletX.isEnabled, "An inherited responsive value must remain editable when its selected node is clipped by the artboard.")
        tabletX.doubleClick()
        tabletX.typeKey("a", modifierFlags: .command); tabletX.typeText("48"); tabletX.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Authored for Tablet"))
        XCTAssertTrue(application.buttons["inspector.layout.resetBreakpointOverrides"].isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-016 Tablet authored override")

        preset.click(); application.menuItems["Mobile"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Mobile"))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.selectionPath"],
                                   containing: "1 selected; primary selection present; selection outside Mobile artboard"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Inherited from Desktop"))
        let width = application.textFields["inspector.layout.width"]
        XCTAssertTrue(width.waitForExistence(timeout: 3))
        XCTAssertTrue(width.isEnabled)
        width.doubleClick()
        width.typeKey("a", modifierFlags: .command); width.typeText("320"); width.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Authored for Mobile"))
        let mobileX = application.textFields["inspector.layout.x"]
        XCTAssertTrue(mobileX.isEnabled)
        mobileX.doubleClick()
        mobileX.typeKey("a", modifierFlags: .command); mobileX.typeText("24"); mobileX.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Authored for Mobile"))
        XCTAssertFalse((application.descendants(matching: .any)["status.selectionPath"].value as? String)?
            .contains("outside Mobile artboard") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-016 Mobile authored override")

        let reset = application.buttons["inspector.layout.resetBreakpointOverrides"]
        XCTAssertTrue(reset.isHittable); reset.click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Inherited from Desktop"))
        XCTAssertFalse(application.buttons["inspector.layout.resetBreakpointOverrides"].isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-016 Mobile reset inheritance")

        preset.click(); application.menuItems["Tablet"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Authored for Tablet"))
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Authored for Mobile") ||
            application.buttons["toolbar.redo"].isEnabled)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(preset, containing: "Tablet"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-016 responsive undo redo")
    }

    // SF-0601-001...006/008; SF-0602-001...006/008; SF-0603-001...006/008
    @MainActor
    func testResponsiveContainerLayoutAndBreakpointVisibilityJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForWorkspaceReady(application))
        @MainActor func reveal(_ element: XCUIElement) {
            let scroll = application.descendants(matching: .any)["inspector.selection.scroll"]
            for _ in 0..<8 where !element.isHittable { scroll.scroll(byDeltaX: 0, deltaY: -180) }
            XCTAssertTrue(element.isHittable, "Responsive Inspector control \(element.identifier) must remain reachable")
        }
        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.stack"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        for count in 2...3 {
            application.menuBars.menuBarItems["Insert"].click()
            application.menuItems["Insert Frame at Center"].click()
            XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects \(count)", timeout: 5))
            application.buttons["navigator.tab.layers"].click()
            let stackRow = application.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Stack"
            )).firstMatch
            XCTAssertTrue(stackRow.waitForExistence(timeout: 3)); stackRow.click()
        }
        application.buttons["inspector.tab.layout"].click()
        XCTAssertTrue(application.staticTexts["Desktop base"].firstMatch.exists)
        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 Desktop Stack base layout")

        preset.click(); application.menuItems["Tablet"].click()
        let axis = application.descendants(matching: .any)["inspector.layout.container.axis"]
        XCTAssertTrue(axis.waitForExistence(timeout: 3))
        axis.radioButtons["Horizontal"].click()
        XCTAssertTrue(waitForValue(axis, containing: "horizontal"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 Tablet Stack override")

        preset.click(); application.menuItems["Mobile"].click()
        let gap = application.textFields["inspector.layout.container.gap"]
        XCTAssertTrue(gap.waitForExistence(timeout: 3))
        gap.doubleClick(); gap.typeKey("a", modifierFlags: .command); gap.typeText("8"); gap.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(gap, containing: "Authored for Mobile"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 Mobile Stack override")

        application.buttons["navigator.tab.layers"].click()
        let frameRow = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"
        )).firstMatch
        XCTAssertTrue(frameRow.waitForExistence(timeout: 3))
        let selectedFrameIdentifier = frameRow.identifier
        XCTAssertTrue(selectedFrameIdentifier.hasPrefix("navigator.layer.")); frameRow.click()
        application.buttons["inspector.tab.layout"].click()
        let visibility = application.descendants(matching: .any)["inspector.layout.visibility"]
        XCTAssertTrue(visibility.waitForExistence(timeout: 3)); reveal(visibility); XCTAssertTrue(visibility.isEnabled)
        visibility.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertFalse(application.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "canvas.selection.")
        ).firstMatch.exists, "A hidden breakpoint object must not retain canvas chrome")
        application.buttons["navigator.tab.layers"].click()
        let hiddenFrameRow = application.descendants(matching: .any)[selectedFrameIdentifier]
        XCTAssertTrue(waitForValue(hiddenFrameRow, containing: "Hidden at current breakpoint"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 Mobile hidden Layers inspection")

        application.buttons["inspector.tab.layout"].click()
        let hiddenVisibility = application.descendants(matching: .any)["inspector.layout.visibility"]
        XCTAssertTrue(hiddenVisibility.waitForExistence(timeout: 3)); reveal(hiddenVisibility); hiddenVisibility.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        XCTAssertTrue(canvas.exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 visibility restored undo redo")

        preset.click(); application.menuItems["Desktop"].click()
        application.menuBars.menuBarItems["Selection"].click()
        let clearSelection = application.menuItems["Clear Selection"]
        XCTAssertTrue(clearSelection.waitForExistence(timeout: 2)); clearSelection.click()
        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.grid"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 4", timeout: 5))
        for count in 5...6 {
            application.menuBars.menuBarItems["Insert"].click()
            application.menuItems["Insert Frame at Center"].click()
            XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects \(count)", timeout: 5))
            application.buttons["navigator.tab.layers"].click()
            let gridRow = application.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Grid"
            )).firstMatch
            XCTAssertTrue(gridRow.waitForExistence(timeout: 3)); gridRow.click()
        }
        application.buttons["inspector.tab.layout"].click()
        XCTAssertTrue(waitForValue(
            application.staticTexts["inspector.layout.container.announcement"],
            containing: "Container layout inactive"
        ), "Selecting a different container at another breakpoint must not retain stale operation feedback")
        XCTAssertTrue(waitForValue(
            application.staticTexts["inspector.layout.visibility.announcement"],
            containing: "Breakpoint visibility inactive"
        ), "Breakpoint visibility feedback must stay scoped to the selection and breakpoint that produced it")
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 Desktop Stack Grid base layout")
        preset.click(); application.menuItems["Tablet"].click()
        let columns = application.textFields["inspector.layout.container.columns"]
        XCTAssertTrue(columns.waitForExistence(timeout: 3)); reveal(columns)
        columns.doubleClick(); columns.typeKey("a", modifierFlags: .command)
        columns.typeText("1"); columns.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(columns, containing: "Authored for Tablet"))
        XCTAssertTrue(waitForValue(
            application.staticTexts["inspector.layout.container.announcement"], containing: "Columns committed"
        ))
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 Tablet Grid override")
    }

    // SF-AUTHORING-101, SF-0601-003/006, SF-0602-002/003/004/006/008,
    // SF-0603-002/003/006 — comparison reads the live responsive cascade and
    // switches only the scene preset; it never authors an equivalent literal.
    @MainActor
    func testResponsiveBreakpointComparisonReviewsLiveSelectionWithoutMutationJourney() throws {
        let application = launchWorkspace()
        XCTAssertTrue(waitForWorkspaceReady(application))
        application.buttons["canvas.empty.insert.frame"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.buttons["inspector.tab.layout"].click()
        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        preset.click(); application.menuItems["Tablet"].click()
        let xField = application.textFields["inspector.layout.x"]
        XCTAssertTrue(xField.waitForExistence(timeout: 3))
        xField.doubleClick(); xField.typeKey("a", modifierFlags: .command)
        xField.typeText("48"); xField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(xField, containing: "Authored for Tablet"))

        let compare = application.buttons["canvas.viewport.compare"]
        XCTAssertTrue(waitForHittable(compare, in: application)); compare.click()
        XCTAssertTrue(application.descendants(matching: .any)["responsive.compare.sheet"].waitForExistence(timeout: 3))
        let desktop = application.descendants(matching: .any)["responsive.compare.card.desktop"]
        let tablet = application.descendants(matching: .any)["responsive.compare.card.tablet"]
        let mobile = application.descendants(matching: .any)["responsive.compare.card.mobile"]
        XCTAssertTrue(desktop.exists && tablet.exists && mobile.exists)
        XCTAssertTrue((desktop.value as? String)?.contains("Desktop base source") == true)
        XCTAssertTrue((tablet.value as? String)?.contains("1 geometry override") == true)
        XCTAssertTrue((tablet.value as? String)?.contains("authored geometry") == true)
        XCTAssertTrue((mobile.value as? String)?.contains("inherited geometry") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-101 responsive comparison selection")

        let reviewMobile = application.buttons["responsive.compare.review.mobile"]
        XCTAssertTrue(waitForHittable(reviewMobile, in: application)); reviewMobile.click()
        XCTAssertTrue(waitForValue(preset, containing: "Mobile"))
        XCTAssertTrue(application.descendants(matching: .any)["responsive.compare.sheet"].exists)
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["responsive.compare.sheet"]))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Inherited from Desktop"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-101 Mobile reviewed without authoring")
    }

    // SF-AUTHORING-102, SF-0604-001...006/008 — the real Layout Inspector
    // authors one monotonic clamp, the live canvas resolves it across presets,
    // comparison exposes the result, and Escape/reset preserve fixed intent.
    @MainActor
    func testFluidResponsiveValueAuthoringPreviewResetAndAccessibilityJourney() throws {
        let application = launchWorkspace()
        XCTAssertTrue(waitForWorkspaceReady(application))
        application.buttons["canvas.empty.insert.frame"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.buttons["inspector.tab.layout"].click()
        let fluid = application.descendants(matching: .any)["inspector.layout.fluid"]
        XCTAssertTrue(fluid.waitForExistence(timeout: 3))
        let enable = application.buttons["inspector.layout.fluid.enable"]
        XCTAssertTrue(waitForHittable(enable, in: application)); enable.click()
        let minimum = application.textFields["inspector.layout.fluid.minimum"]
        let preferred = application.textFields["inspector.layout.fluid.preferred"]
        let maximum = application.textFields["inspector.layout.fluid.maximum"]
        XCTAssertTrue(minimum.waitForExistence(timeout: 3))
        for (field, value) in [(minimum, "160"), (preferred, "240"), (maximum, "360")] {
            field.click(); field.typeKey("a", modifierFlags: .command); field.typeText(value)
        }
        application.buttons["inspector.layout.fluid.apply"].click()
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.announcement"],
                                   containing: "committed"))
        XCTAssertTrue(application.buttons["inspector.layout.fluid.remove"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-102 fluid width authored at Desktop")

        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        preset.click(); application.menuItems["Mobile"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Mobile"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-102 fluid width resolved at Mobile")
        application.buttons["canvas.viewport.compare"].click()
        XCTAssertTrue(application.descendants(matching: .any)["responsive.compare.sheet"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-102 fluid value breakpoint comparison")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["responsive.compare.sheet"]))

        application.buttons["inspector.layout.fluid.edit"].click()
        minimum.click(); minimum.typeKey("a", modifierFlags: .command); minimum.typeText("500")
        minimum.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.buttons["inspector.layout.fluid.remove"].exists,
                      "Escape must cancel the draft without replacing the committed clamp")
        application.buttons["inspector.layout.fluid.remove"].click()
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.announcement"],
                                   containing: "fixed authored value restored"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-102 fluid width removed to fixed fallback")
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
        replaceText(in: hex, with: "#203040FF", application: application)
        opacity.click()
        XCTAssertTrue(waitForValue(hex, containing: "#203040FF"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 valid focus loss")
        let opacityBeforeInvalidFocusLoss = opacity.value as? String
        replaceText(in: hex, with: "invalid", application: application)
        opacity.click()
        XCTAssertTrue(application.descendants(matching: .any)["inspector.design.validation"].waitForExistence(timeout: 3))
        XCTAssertEqual(opacity.value as? String, opacityBeforeInvalidFocusLoss)
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 invalid focus loss")
        hex.typeKey(.escape, modifierFlags: [])

        let prior = hex.value as? String
        replaceText(in: hex, with: "#20406080", application: application)
        hex.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(hex, containing: "#20406080"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 authored fill")
        replaceText(in: opacity, with: "40", application: application)
        opacity.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(opacity, containing: "40 percent"))
        replaceText(in: hex, with: "bad", application: application)
        hex.typeKey(.return, modifierFlags: [])
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
        replaceStructuralLayoutField(borderWidth, with: "4", in: application)
        let radiusToggle = reveal("inspector.design.cornerRadiusToggle")
        XCTAssertTrue(radiusToggle.isHittable); radiusToggle.click()
        let radius = reveal("inspector.design.cornerRadius")
        replaceStructuralLayoutField(radius, with: "18", in: application)
        let padding = reveal("inspector.design.contentPadding")
        XCTAssertTrue(padding.isEnabled)
        replaceStructuralLayoutField(padding, with: "24", in: application)
        let clipContent = reveal("inspector.design.clipContent")
        XCTAssertTrue(clipContent.isHittable)
        XCTAssertFalse(clipContent.label.isEmpty)
        clipContent.click()
        attachWindowScreenshot(application, named: "SF-AUTHORING-014 border radius")
        let shadowToggle = reveal("inspector.design.shadowToggle")
        XCTAssertTrue(shadowToggle.isHittable); shadowToggle.click()
        let shadow = reveal("inspector.design.shadowValues")
        replaceStructuralLayoutField(shadow, with: "2, 10, 20, 1", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.design.announcement"], containing: "shadow committed"))
        let shadowEnabled = reveal("inspector.design.shadowEnabled")
        XCTAssertTrue(shadowEnabled.isHittable)
        XCTAssertFalse(shadowEnabled.label.isEmpty)
        shadowEnabled.click()
        attachWindowScreenshot(application, named: "SF-AUTHORING-014 shadow")
        let beforeCancel = shadow.value as? String
        replaceStructuralLayoutField(shadow, with: "invalid", in: application, endKey: .escape)
        XCTAssertEqual(shadow.value as? String, beforeCancel)
        application.typeKey("z", modifierFlags: .command)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue((canvas.value as? String)?.contains("rendered objects 1") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-014 undo redo")
    }

    // SF-0509-002/003/006 — native token drafts and solid-fill binding use
    // the visible Inspector; no fixture or automation mutation path is used.
    func testLocalColorTokenInspectorCreateBindAndUnbindJourney() throws {
        let application = launchWorkspace()
        let insert = application.buttons["canvas.empty.insert.frame"]
        XCTAssertTrue(waitForHittable(insert, in: application)); insert.click()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["inspector.tab.design"].click()
        let inspector = application.scrollViews["inspector.selection.scroll"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        func reveal(_ identifier: String) -> XCUIElement {
            let element = application.descendants(matching: .any)[identifier].firstMatch
            for _ in 0..<14 where !element.isHittable {
                let controlFrame = element.frame
                let viewportFrame = inspector.frame
                if controlFrame.maxY > viewportFrame.maxY {
                    inspector.scroll(byDeltaX: 0, deltaY: -100)
                } else if controlFrame.minY < viewportFrame.minY {
                    inspector.scroll(byDeltaX: 0, deltaY: 100)
                } else {
                    break
                }
            }
            return element
        }
        let create = reveal("inspector.tokens.new")
        XCTAssertTrue(create.isHittable); create.click()
        let name = reveal("inspector.tokens.name")
        XCTAssertTrue(name.isHittable)
        replaceText(in: name, with: "Brand", application: application)
        let color = reveal("inspector.tokens.color")
        replaceText(in: color, with: "#204060FF", application: application)
        let apply = reveal("inspector.tokens.apply")
        XCTAssertTrue(apply.isHittable); apply.click()
        let row = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "inspector.tokens.row."
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Brand"))
        XCTAssertTrue(reveal(row.identifier).isHittable)
        row.click()
        XCTAssertTrue(reveal("inspector.tokens.bind").isHittable, application.debugDescription)
        reveal("inspector.tokens.bind").click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.tokens.bindingStatus"], containing: "Brand"))
        let fillHex = application.textFields["inspector.design.fillHex"]
        XCTAssertTrue(waitForValue(fillHex, containing: "#204060FF"))
        XCTAssertFalse(fillHex.isEnabled, "Bound solid color must not offer a misleading literal edit")
        attachWindowScreenshot(application, named: "SF-AUTHORING-057 bound local color token")
        let unbind = reveal("inspector.tokens.unbind")
        XCTAssertTrue(unbind.isHittable); unbind.click()
        XCTAssertFalse(application.descendants(matching: .any)["inspector.tokens.bindingStatus"].waitForExistence(timeout: 2))
        XCTAssertTrue(waitForValue(fillHex, containing: "#204060FF"))
        XCTAssertTrue(fillHex.isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-057 unbound literal fill")
    }

    func testLocalColorTokenBorderAndOuterShadowInspectorJourney() throws {
        let application = launchWorkspace()
        application.buttons["canvas.empty.insert.frame"].click()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["inspector.tab.design"].click()
        let inspector = application.scrollViews["inspector.selection.scroll"]
        func reveal(_ identifier: String) -> XCUIElement {
            let element = application.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing Inspector control: \(identifier)")
            for _ in 0..<24 {
                let bounds = element.frame, viewport = inspector.frame
                if bounds.minY >= viewport.minY + 4, bounds.maxY <= viewport.maxY - 4,
                   element.isHittable { return element }
                inspector.scroll(byDeltaX: 0, deltaY: bounds.maxY > viewport.maxY - 4 ? -100 : 100)
            }
            XCTAssertTrue(element.isHittable && element.frame.minY >= inspector.frame.minY + 4
                && element.frame.maxY <= inspector.frame.maxY - 4,
                "Inspector control is outside its visible scroll viewport: \(identifier)")
            return element
        }
        let borderToggle = reveal("inspector.design.borderToggle")
        XCTAssertTrue(waitForEnabled(borderToggle))
        borderToggle.click()
        XCTAssertTrue(waitForLabel(reveal("inspector.design.borderToggle"), containing: "Remove", timeout: 5))
        let shadowToggle = reveal("inspector.design.shadowToggle")
        XCTAssertTrue(waitForEnabled(shadowToggle))
        XCTAssertTrue(shadowToggle.isHittable, "Shadow control is outside the visible Inspector: \(shadowToggle.frame)")
        shadowToggle.click()
        XCTAssertTrue(waitForLabel(reveal("inspector.design.shadowToggle"), containing: "Remove", timeout: 5),
            "Shadow status: \(String(describing: application.descendants(matching: .any)["inspector.design.announcement"].value))")
        reveal("inspector.tokens.new").click()
        let name = reveal("inspector.tokens.name")
        replaceText(in: name, with: "Accent", application: application)
        let color = reveal("inspector.tokens.color")
        replaceText(in: color, with: "#CC1933FF", application: application)
        reveal("inspector.tokens.apply").click()
        let row = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "inspector.tokens.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); reveal(row.identifier).click()
        let target = reveal("inspector.tokens.target")
        XCTAssertTrue(target.isHittable)
        target.click(); application.menuItems["Border"].click()
        XCTAssertTrue(waitForValue(reveal("inspector.tokens.targetStatus"), containing: "1 applicable"))
        let borderBind = reveal("inspector.tokens.bind")
        XCTAssertTrue(waitForEnabled(borderBind))
        borderBind.click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.tokens.bindingStatus"], containing: "Accent"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-059 border token bound")
        target.click(); application.menuItems["Outer Shadow"].click()
        let shadowBind = reveal("inspector.tokens.bind")
        XCTAssertTrue(waitForEnabled(shadowBind))
        shadowBind.click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.tokens.bindingStatus"], containing: "Accent"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-059 shadow token bound")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(application.descendants(matching: .any)["inspector.tokens.bindingStatus"].exists)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(reveal("inspector.tokens.bindingStatus"), containing: "Accent"))
        reveal("inspector.tokens.unbind").click()
        XCTAssertFalse(application.descendants(matching: .any)["inspector.tokens.bindingStatus"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-059 shadow literal retained")
    }

    // SF-0506-006/008 — the shipping Design controls remain readable and
    // scroll-reachable at the supported practical minimum; no hidden test
    // control substitutes for the native Inspector.
    func testDesignInspectorBoxAppearanceControlsRemainReachableAtPracticalMinimum() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWindowSize", "minimum",
            "-SiteForgeUITestWindowAlignment", TestWindowAlignment.right.rawValue,
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
            "inspector.design.contentPaddingToggle",
            "inspector.design.clipContent",
            "inspector.design.shadowToggle",
        ] {
            let control = reveal(identifier)
            XCTAssertTrue(control.isHittable, identifier)
            XCTAssertFalse(control.label.isEmpty, identifier)
        }
        attachWindowScreenshot(application, named: "SF-AUTHORING-014 practical minimum inspector")
    }

    // SF-0507-001...008 — the shipping Design Inspector authors canonical
    // typography and the same metrics drive committed and live inline text.
    func testTextForegroundNativeInspectorTokenAndInlineParityJourney() throws {
        let application = launchWorkspace()
        application.buttons["canvas.empty.insert.text"].click()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["inspector.tab.design"].click()
        let inspector = application.scrollViews["inspector.selection.scroll"]
        func reveal(_ identifier: String) -> XCUIElement {
            let element = application.descendants(matching: .any)[identifier].firstMatch
            guard element.waitForExistence(timeout: 5) else { return element }
            for _ in 0..<12 where !element.isHittable {
                let upperEdge = inspector.frame.minY + 16
                let lowerEdge = inspector.frame.maxY - 56
                if element.frame.midY <= upperEdge {
                    inspector.swipeDown() // Reveal content above the viewport.
                } else if element.frame.midY >= lowerEdge {
                    inspector.swipeUp() // Reveal content below the viewport.
                } else {
                    break // A visible but disabled/occluded field is not a scrolling problem.
                }
            }
            return element
        }
        let foreground = reveal("inspector.design.typography.foregroundHex")
        XCTAssertTrue(waitForHittable(foreground, in: application) && foreground.isEnabled)
        XCTAssertTrue(waitForValue(reveal("inspector.design.typography.foregroundStatus"), containing: "Automatic"))
        foreground.click(); foreground.typeText("#C02040FF"); foreground.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(reveal("inspector.design.typography.foregroundStatus"), containing: "Authored"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-060 authored text foreground")
        replaceText(in: foreground, with: "bad", application: application)
        foreground.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(reveal("inspector.design.validation").waitForExistence(timeout: 3))
        foreground.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(reveal("inspector.design.typography.foregroundStatus"), containing: "#C02040FF"))
        let newToken = reveal("inspector.tokens.new")
        XCTAssertTrue(waitForHittable(newToken, in: application))
        newToken.click()
        let name = reveal("inspector.tokens.name")
        XCTAssertTrue(name.waitForExistence(timeout: 5), "New Color Token must reveal its native draft form")
        XCTAssertTrue(waitForHittable(name, in: application))
        replaceText(in: name, with: "Ink", application: application)
        let tokenColor = reveal("inspector.tokens.color")
        replaceText(in: tokenColor, with: "#20A040FF", application: application)
        reveal("inspector.tokens.apply").click()
        let row = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "inspector.tokens.row.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5)); reveal(row.identifier).click()
        let target = reveal("inspector.tokens.target")
        target.click(); application.menuItems["Text Foreground"].click()
        XCTAssertTrue(waitForValue(reveal("inspector.tokens.targetStatus"), containing: "1 applicable"))
        reveal("inspector.tokens.bind").click()
        XCTAssertTrue(waitForValue(reveal("inspector.design.typography.foregroundStatus"), containing: "Ink"))
        XCTAssertFalse(reveal("inspector.design.typography.foregroundHex").isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-060 bound text foreground")
        application.menuBars.menuBarItems["Selection"].click()
        application.menuItems["Edit Selected Text"].click()
        let editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let objectFrame = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object.")).firstMatch.frame
        XCTAssertEqual(editor.frame.minX, objectFrame.minX, accuracy: 1)
        XCTAssertEqual(editor.frame.minY, objectFrame.minY, accuracy: 1)
        attachWindowScreenshot(application, named: "SF-AUTHORING-060 bound foreground inline editor")
        editor.typeKey(.escape, modifierFlags: [])
        reveal("inspector.tokens.unbind").click()
        XCTAssertTrue(waitForValue(reveal("inspector.design.typography.foregroundStatus"), containing: "Authored"))
        reveal("inspector.design.typography.foregroundReset").click()
        XCTAssertTrue(waitForValue(reveal("inspector.design.typography.foregroundStatus"), containing: "Automatic"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-060 automatic foreground restored")
    }

    func testDesignInspectorTypographyInlineUndoRedoAccessibilityJourney() throws {
        let fixture = legacyFixtureURL(named: "schema-v4-legacy-surface")
        let project = fixtureRoot.appendingPathComponent("typography-native-save.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: fixture)
        XCTAssertTrue(waitForWorkspaceReady(application))
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        application.buttons["canvas.empty.insert.text"].click()
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["inspector.tab.design"].click()
        let inspector = application.scrollViews["inspector.selection.scroll"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        func reveal(_ identifier: String) -> XCUIElement {
            let element = application.descendants(matching: .any)[identifier]
            for _ in 0..<14 where !element.isHittable { inspector.scroll(byDeltaX: 0, deltaY: -120) }
            return element
        }
        let family = reveal("inspector.design.typography.family")
        let size = reveal("inspector.design.typography.size")
        let lineHeight = reveal("inspector.design.typography.lineHeight")
        let tracking = reveal("inspector.design.typography.tracking")
        XCTAssertTrue(family.isHittable && size.isEnabled && lineHeight.isEnabled && tracking.isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-015 default typography")

        replaceText(in: family, with: "Menlo", application: application); family.typeKey(.return, modifierFlags: [])
        replaceText(in: size, with: "22", application: application); size.typeKey(.return, modifierFlags: [])
        replaceText(in: lineHeight, with: "30", application: application); lineHeight.typeKey(.return, modifierFlags: [])
        replaceText(in: tracking, with: "1.5", application: application); tracking.typeKey(.return, modifierFlags: [])
        let weight = reveal("inspector.design.typography.weight")
        weight.click(); application.menuItems["Bold"].click()
        let alignment = reveal("inspector.design.typography.alignment")
        alignment.click()
        alignment.menuItems["Center"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.design.announcement"], containing: "Typography"))
        XCTAssertTrue(waitForValue(family, containing: "Menlo"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-015 authored family size tracking")

        let beforeInvalid = size.value as? String
        replaceText(in: size, with: "invalid", application: application); size.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(size.value as? String, beforeInvalid)
        application.typeKey("z", modifierFlags: .command)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(family, containing: "Menlo"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-015 undo redo preservation")

        application.menuBars.menuBarItems["Selection"].click()
        application.menuItems["Edit Selected Text"].click()
        let editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let objectFrame = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object."))
            .firstMatch.frame
        XCTAssertEqual(editor.frame.minX, objectFrame.minX, accuracy: 1)
        XCTAssertEqual(editor.frame.minY, objectFrame.minY, accuracy: 1)
        XCTAssertEqual(editor.frame.width, objectFrame.width, accuracy: 1)
        XCTAssertEqual(editor.frame.height, objectFrame.height, accuracy: 1)
        attachWindowScreenshot(application, named: "SF-AUTHORING-015 live inline typography parity")
        editor.typeKey(.escape, modifierFlags: [])

        replaceText(in: family, with: "Unavailable SiteForge Test Font", application: application)
        family.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(family, containing: "Unavailable SiteForge Test Font"))
        XCTAssertTrue(application.descendants(matching: .any)["inspector.design.typography.fallback"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-015 deterministic font fallback")

        saveDocumentIfModified(in: application)
        terminateAndWait(application)

        let reopenRecoveryDirectory = fixtureRoot.appendingPathComponent("typography-reopen-recovery", isDirectory: true)
        application = launchExistingIntegrationProject(project, recoveryDirectory: reopenRecoveryDirectory)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.buttons["navigator.tab.layers"].click()
        let reopenedText = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text"
        )).firstMatch
        XCTAssertTrue(reopenedText.waitForExistence(timeout: 5)); reopenedText.click()
        application.buttons["inspector.tab.design"].click()
        let reopenedFamily = application.textFields["inspector.design.typography.family"]
        XCTAssertTrue(waitForValue(reopenedFamily, containing: "Unavailable SiteForge Test Font"))
        XCTAssertTrue(application.descendants(matching: .any)["inspector.design.typography.fallback"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-015 save reopen preservation")
    }

    // SF-1203-001...006 — semantic metadata is authored from the visible
    // Design Inspector, never from a test-only document mutation path.
    func testSemanticHTMLElementInspectorKeyboardResetAndPreviewJourney() throws {
        let application = launchWorkspace()
        application.buttons["canvas.empty.insert.frame"].click()
        // Insertion replaces the live canvas accessibility host; re-query the
        // real adopted element rather than retaining its pre-insertion proxy.
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        application.buttons["inspector.tab.design"].click()
        let inspector = application.scrollViews["inspector.selection.scroll"]
        let element = application.descendants(matching: .any)["inspector.semantic.element"]
        for _ in 0..<14 where !element.isHittable { inspector.scroll(byDeltaX: 0, deltaY: -120) }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue((element.value as? String ?? "").contains("<div>"))
        element.click(); application.menuItems["<article>"].click()
        let status = application.descendants(matching: .any)["inspector.semantic.status"]
        XCTAssertTrue(waitForValue(status, containing: "Authored"))
        application.buttons["inspector.semantic.reset"].click()
        XCTAssertTrue(waitForValue(status, containing: "Defaulted"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-026 semantic element inspector")
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
        replaceText(in: hex, with: "#315A7C99", application: application)
        hex.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(hex, containing: "#315A7C99"))
        let designAnnouncement = application.descendants(matching: .any)["inspector.design.announcement"]
        XCTAssertTrue(waitForValue(designAnnouncement, containing: "Design solid-fill committed"))
        replaceText(in: opacity, with: "60", application: application)
        opacity.typeKey(.return, modifierFlags: [])
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

    // SF-0801-001...008 — project-local organization is edited through the
    // visible Assets sheet; draft/filter state never becomes document content.
    func testNativeAssetOrganizationSearchFavoriteUndoAndReopenJourney() throws {
        let imageURL = try makeLocalImageFixture(named: "siteforge-organized.png")
        let project = fixtureRoot.appendingPathComponent("asset-organization.siteforge")
        var application = launchIntegrationOpen(project,
            base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"),
            windowAlignment: leadingEdgeAlignmentOnNarrowDisplay)
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application,
            permitsLeadingEdgeConstrainedPlacementOnNarrowDisplay: leadingEdgeAlignmentOnNarrowDisplay != nil)
        application.buttons["navigator.tab.assets"].click()
        application.buttons["assets.empty.import"].click()
        XCTAssertTrue(waitForNativeOpenPanel(in: application))
        application.typeKey("g", modifierFlags: [.command, .shift])
        let path = application.sheets.textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 3))
        replaceText(in: path, with: imageURL.path, application: application)
        path.typeKey(.return, modifierFlags: [])
        if path.exists {
            let go = application.sheets.buttons["Go"]
            if go.exists && go.isEnabled { go.click() }
        }
        let row = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "assets.row.", "siteforge-organized"
        )).firstMatch
        if !row.exists { application.typeKey(.return, modifierFlags: []) }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { [weak application] _, _ in
                guard let application else { return false }
                if row.exists { return true }
                let action = application.buttons["OKButton"]
                return action.exists && action.isEnabled
            }, object: application
        )], timeout: 8), .completed,
        "The native panel must either import the chosen image or expose an enabled Import action")
        if !row.exists {
            let importButton = application.buttons["OKButton"]
            XCTAssertTrue(importButton.exists && importButton.isEnabled); importButton.click()
        }
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.click()
        attachWindowScreenshot(application, named: "SF-AUTHORING-063 unorganized asset")

        // SF-AUTHORING-081/082: usage is a scene-local projection, while Quick
        // Open returns the same AssetID and reveals the actual Assets row.
        let unused = application.descendants(matching: .any)["assets.filter.usage.unused"]
        XCTAssertTrue(unused.waitForExistence(timeout: 3))
        unused.click()
        XCTAssertTrue(row.exists)
        application.descendants(matching: .any)["assets.filter.usage.used"].click()
        XCTAssertFalse(row.exists)
        application.descendants(matching: .any)["assets.filter.usage.all"].click()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        application.buttons["navigator.quickOpen"].click()
        let quickAssetSearch = application.textFields["quickOpen.search"]
        XCTAssertTrue(waitForHittable(quickAssetSearch, in: application))
        quickAssetSearch.click(); quickAssetSearch.typeText("siteforge-organized")
        let assetID = row.identifier.replacingOccurrences(of: "assets.row.", with: "")
        let assetResult = application.buttons["quickOpen.asset.\(assetID)"]
        XCTAssertTrue(assetResult.waitForExistence(timeout: 3))
        assetResult.click()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertTrue(application.descendants(matching: .any)["navigator.assets.library"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-081-082 asset usage and Quick Open reveal")

        application.buttons["navigator.quickOpen"].click()
        let insertSearch = application.textFields["quickOpen.search"]
        XCTAssertTrue(waitForHittable(insertSearch, in: application))
        insertSearch.click(); insertSearch.typeText("siteforge-organized")
        let insert = application.buttons["quickOpen.asset.insert.\(assetID)"]
        XCTAssertTrue(waitForHittable(insert, in: application))
        insert.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-084 Quick Open asset inserted")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))

        let organize = application.buttons["assets.organize.selected"]
        XCTAssertTrue(organize.waitForExistence(timeout: 3)); organize.click()
        let folder = application.textFields["assets.organization.folder"]
        let tags = application.textFields["assets.organization.tags"]
        XCTAssertTrue(folder.waitForExistence(timeout: 3))
        folder.click(); folder.typeText("Campaign/Summer")
        tags.click(); tags.typeText("hero, launch")
        application.descendants(matching: .any)["assets.organization.favorite"].click()
        attachWindowScreenshot(application, named: "SF-AUTHORING-063 organization draft")
        application.buttons["assets.organization.save"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["assets.status"], containing: "Updated asset organization"))
        XCTAssertTrue(waitForValue(row, containing: "Campaign/Summer"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-063 organized asset")

        let search = application.textFields["assets.search"]
        search.click(); search.typeText("launch")
        XCTAssertTrue(row.exists)
        replaceText(in: search, with: "missing-tag", application: application)
        XCTAssertTrue(application.descendants(matching: .any)["assets.empty"].waitForExistence(timeout: 3))
        replaceText(in: search, with: "", application: application)
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(row, containing: "not favorite"))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(row, containing: "Campaign/Summer"))
        application.descendants(matching: .any)["assets.filter.favorites"].click()
        XCTAssertTrue(row.exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-063 favorite filtered")
        saveDocumentIfModified(in: application)
        terminateAndWait(application)

        application = launchExistingIntegrationProject(project,
            recoveryDirectory: fixtureRoot.appendingPathComponent("organization-reopen-recovery", isDirectory: true),
            windowAlignment: leadingEdgeAlignmentOnNarrowDisplay)
        XCTAssertTrue(waitForWorkspaceReady(application))
        application.buttons["navigator.tab.assets"].click()
        let reopened = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "assets.row.", "siteforge-organized"
        )).firstMatch
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(reopened, containing: "Campaign/Summer"))
        XCTAssertTrue((reopened.value as? String)?.contains("favorite") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-063 reopened asset")
    }

    // SF-0801-001...008, SF-0802-001...008 — a real native Open panel feeds
    // the production resource store, then the visible Assets/Image surfaces
    // drive canonical insertion, non-destructive fit/focal/alt edits, history,
    // native Save, process teardown, and package reopen.
    func testLocalImageAssetImportAuthoringUndoRedoAndReopenJourney() throws {
        let imageURL = try makeLocalImageFixture(named: "siteforge-image.png")
        let fixture = legacyFixtureURL(named: "schema-v4-legacy-surface")
        let project = fixtureRoot.appendingPathComponent("local-image-authoring.siteforge")
        var application = launchIntegrationOpen(
            project,
            base64Fixture: fixture,
            windowAlignment: leadingEdgeAlignmentOnNarrowDisplay
        )
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(
            in: application,
            permitsLeadingEdgeConstrainedPlacementOnNarrowDisplay:
                leadingEdgeAlignmentOnNarrowDisplay != nil
        )

        application.buttons["navigator.tab.assets"].click()
        let empty = application.descendants(matching: .any)["assets.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-019 empty Assets")

        application.buttons["assets.empty.import"].click()
        XCTAssertTrue(waitForNativeOpenPanel(in: application))
        application.typeKey("g", modifierFlags: [.command, .shift])
        // Match the native Go to Folder field, not the first text field of
        // whichever sheet replaces it (the open panel also has text fields).
        let pathField = application.sheets.textFields["PathTextField"]
        XCTAssertTrue(pathField.waitForExistence(timeout: 3))
        replaceText(in: pathField, with: imageURL.path, application: application)
        XCTAssertEqual(pathField.value as? String, imageURL.path,
                       "The native Go-to-Folder field must contain the exact fixture path before confirming import.")
        pathField.typeKey(.return, modifierFlags: [])
        // Native OpenPanel variants either accept Return in the path field or
        // expose the real Go action. Do not proceed until that sheet changes.
        if pathField.exists {
            let go = application.sheets.buttons["Go"]
            if go.exists && go.isEnabled { go.click() }
        }
        let assetRow = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "assets.row.", "siteforge-image"
        )).firstMatch
        // The Go-to-Folder accessory may remain in the AX hierarchy after it
        // has selected the file in the enclosing open panel. Its disappearance
        // is not the completion contract; an enabled native Import action (or
        // an imported asset row) is. The assertion below verifies that real
        // user-visible outcome on both panel implementations.
        // Go to Folder selects the exact file. Activate the native panel's
        // default Import action from that selection, avoiding unstable AX
        // proxies for Finder's column browser and filename field.
        if !assetRow.exists {
            application.typeKey(.return, modifierFlags: [])
        }
        let importCompletedOrAwaitsConfirmation = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { [weak application] _, _ in
                    guard let application else { return false }
                    if assetRow.exists { return true }
                    let liveImport = application.buttons["OKButton"]
                    return liveImport.exists && liveImport.isEnabled
                },
                object: application
            )],
            timeout: 8
        ) == .completed
        XCTAssertTrue(
            importCompletedOrAwaitsConfirmation,
            "The native panel must either import the chosen file or expose an enabled Import action"
        )
        if !assetRow.exists {
            let liveImport = application.buttons["OKButton"]
            XCTAssertTrue(liveImport.exists && liveImport.isEnabled)
            liveImport.click()
        }
        XCTAssertTrue(assetRow.waitForExistence(timeout: 8))
        XCTAssertTrue((assetRow.value as? String)?.contains("siteforge-image.png, 320 by 180 pixels") == true)
        assetRow.click()
        attachWindowScreenshot(application, named: "SF-AUTHORING-019 imported asset list")

        let insert = application.buttons["assets.insert.selected"]
        XCTAssertTrue(waitForEnabled(insert)); insert.click()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1", timeout: 8))
        application.buttons["inspector.tab.design"].click()
        let imageFields = application.descendants(matching: .any)["inspector.image.fields"]
        XCTAssertTrue(imageFields.waitForExistence(timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-019 Image Fit")

        let fit = application.descendants(matching: .any)["inspector.image.fit"]
        XCTAssertTrue(fit.exists)
        let fillMode = fit.radioButtons["Fill"]
        XCTAssertTrue(fillMode.waitForExistence(timeout: 3))
        fillMode.click()
        let focalX = application.textFields["inspector.image.focalX"]
        let focalY = application.textFields["inspector.image.focalY"]
        replaceText(in: focalX, with: "25", application: application)
        replaceText(in: focalY, with: "75", application: application)
        focalY.typeKey(.return, modifierFlags: [])
        let alt = application.textFields["inspector.image.alt"]
        replaceText(in: alt, with: "A generated orange and teal test image", application: application)
        alt.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.image.status"], containing: "committed"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-019 Image Fill focal alt")

        let committedAlt = "A generated orange and teal test image"
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { [weak application] _, _ in
                    guard let application else { return false }
                    return (application.textFields["inspector.image.alt"].value as? String) != committedAlt
                },
                object: application
            )],
            timeout: 5
        ) == .completed)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(
            application.textFields["inspector.image.alt"],
            containing: committedAlt,
            timeout: 5
        ))
        attachWindowScreenshot(application, named: "SF-AUTHORING-019 Image undo redo")

        application.menuBars.menuBarItems["File"].click()
        let save = application.menuItems["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3)); save.click()
        XCTAssertTrue(waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 8))
        terminateAndWait(application)

        let reopenRecovery = fixtureRoot.appendingPathComponent("image-reopen-recovery", isDirectory: true)
        application = launchExistingIntegrationProject(
            project,
            recoveryDirectory: reopenRecovery,
            windowAlignment: leadingEdgeAlignmentOnNarrowDisplay
        )
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 8))
        application.buttons["navigator.tab.layers"].click()
        let imageLayer = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Image"
        )).firstMatch
        XCTAssertTrue(imageLayer.waitForExistence(timeout: 5)); imageLayer.click()
        application.buttons["inspector.tab.design"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.image.focalX"], containing: "25"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.image.focalY"], containing: "75"))
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.image.alt",
            containing: "A generated orange and teal test image",
            timeout: 5
        ))
        attachWindowScreenshot(application, named: "SF-AUTHORING-019 Image reopened")

        // SF-AUTHORING-061: the same imported AssetID is a bounded Frame
        // background reference, edited through the visible native Inspector.
        application.buttons["toolbar.tool.frame"].click()
        let liveCanvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        liveCanvas.coordinate(withNormalizedOffset: .init(dx: 0.28, dy: 0.32)).click()
        XCTAssertTrue(waitForValue(liveCanvas, containing: "rendered objects 2"))
        application.buttons["toolbar.tool.select"].click()
        application.buttons["inspector.tab.design"].click()
        let imageFillStatus = application.descendants(matching: .any)["inspector.imageFill.status"].firstMatch
        XCTAssertTrue(imageFillStatus.waitForExistence(timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-061 Frame image fill empty")
        XCTAssertTrue(waitForValue(imageFillStatus, containing: "No image fill"))
        let chooseImage = application.descendants(matching: .any)["inspector.imageFill.choose"].firstMatch
        XCTAssertTrue(chooseImage.isHittable)
        chooseImage.click()
        // The native SwiftUI Menu item exposes its asset name as AX title,
        // not label. This fixture imports exactly one asset; target its real
        // visible menu item within this control rather than the app menu bar.
        let assetMenuItems = chooseImage.menus.menuItems
        XCTAssertEqual(assetMenuItems.count, 1)
        assetMenuItems.firstMatch.click()
        XCTAssertTrue(waitForValue(imageFillStatus, containing: "siteforge-image"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-061 Frame image fill authored")
        let mode = application.descendants(matching: .any)["inspector.imageFill.mode"].firstMatch
        XCTAssertTrue(mode.exists)
        mode.click()
        application.menuItems["Fit"].click()
        XCTAssertTrue(waitForValue(imageFillStatus, containing: "Fit"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-061 Frame image fill fit")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(imageFillStatus, containing: "Fill"))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(imageFillStatus, containing: "Fit"))
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(
            project,
            recoveryDirectory: fixtureRoot.appendingPathComponent("image-fill-reopen-recovery", isDirectory: true),
            windowAlignment: leadingEdgeAlignmentOnNarrowDisplay
        )
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 8))
        application.buttons["navigator.tab.layers"].click()
        let frameLayer = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"
        )).firstMatch
        XCTAssertTrue(frameLayer.waitForExistence(timeout: 5))
        frameLayer.click()
        application.buttons["inspector.tab.design"].click()
        let reopenedImageFillStatus = application.descendants(matching: .any)["inspector.imageFill.status"].firstMatch
        XCTAssertTrue(waitForValue(reopenedImageFillStatus, containing: "Fit"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-061 Frame image fill reopened")
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

        let inspectorScroll = application.scrollViews["inspector.selection.scroll"]
        XCTAssertTrue(inspectorScroll.exists)
        func revealInspectorControl(_ identifier: String, deltaY: CGFloat) -> XCUIElement {
            for _ in 0..<8 {
                let control = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
                if control.isHittable { return control }
                inspectorScroll.scroll(byDeltaX: 0, deltaY: deltaY)
            }
            let control = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(waitForHittable(control, in: application), "Inspector control must be visible before pointer interaction: \(identifier)")
            return control
        }
        revealInspectorControl("inspector.snapping.suppress", deltaY: -160).click()
        XCTAssertTrue(application.descendants(matching: .any)["status.snapping"].waitForExistence(timeout: 2))
        attachWindowScreenshot(application, named: "SF-AUTHORING-007 snapping suppressed")
        revealInspectorControl("inspector.snapping.suppress", deltaY: -160).click()

        revealInspectorControl("inspector.guide.remove", deltaY: 160).click()
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

    // SF-AUTHORING-097, SF-0402-002/003/006 — the real AppKit canvas owns
    // directional marquee gestures while Layers and status expose the same
    // stable semantic selection. The gesture never depends on a test-only
    // mutation path.
    func testCanvasMarqueeDirectionalMultiSelectionJourney() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeSelectionFixture", "multiple",
        ])
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let authored = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object."))
            .allElementsBoundByAccessibilityElement
        XCTAssertEqual(authored.count, 2)
        let bounds = authored.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        XCTAssertFalse(bounds.isNull)
        let anchor = canvas.coordinate(withNormalizedOffset: .zero)
        func coordinate(x: CGFloat, y: CGFloat) -> XCUICoordinate {
            anchor.withOffset(CGVector(
                dx: min(max(x - canvas.frame.minX, 2), canvas.frame.width - 2),
                dy: min(max(y - canvas.frame.minY, 2), canvas.frame.height - 2)
            ))
        }
        let topLeft = coordinate(x: bounds.minX - 12, y: bounds.minY - 12)
        let bottomRight = coordinate(x: bounds.maxX + 12, y: bounds.maxY + 12)
        topLeft.click(forDuration: 0.15, thenDragTo: bottomRight)

        let status = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(waitForValue(status, containing: "2 selected"))
        application.buttons["navigator.tab.layers"].click()
        let selectedRows = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
            .allElementsBoundByAccessibilityElement.filter(\.isSelected)
        XCTAssertEqual(selectedRows.count, 2)
        attachWindowScreenshot(application, named: "SF-AUTHORING-097 containment marquee selection")

        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(status, containing: "0 selected"))
        bottomRight.click(forDuration: 0.15, thenDragTo: topLeft)
        XCTAssertTrue(waitForValue(status, containing: "2 selected"))
        XCTAssertTrue((canvas.value as? String)?.contains("intersects marquee") != true,
                      "Committed marquee chrome must be removed after mouse-up.")
        attachWindowScreenshot(application, named: "SF-AUTHORING-097 intersection marquee selection")
    }

    // SF-0205-002/003/004/006 — Layers search remains scene-local and selects
    // only through the existing real Layers command when Return is pressed.
    func testLayersSearchFiltersSelectsAndRecoversWithoutChangingDocumentJourney() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeSelectionFixture", "multiple",
        ])
        application.buttons["navigator.tab.layers"].click()
        let search = application.textFields["navigator.layers.search"]
        XCTAssertTrue(waitForHittable(search, in: application))
        let rows = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
        XCTAssertEqual(rows.count, 3)
        let textRow = rows.allElementsBoundByAccessibilityElement.first { $0.label == "Fixture Layer 2" }
        XCTAssertNotNil(textRow)
        textRow?.click()
        XCTAssertTrue((textRow?.value as? String)?.contains("Primary selection") == true)
        search.click(); search.typeText("Layer 1")
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(waitForValue(application.staticTexts["navigator.layers.search.status"], containing: "1 of 3"))
        XCTAssertTrue(application.buttons["navigator.layers.search.showSelected"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-067 Layers filtered")
        search.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        let first = rows.element(boundBy: 0)
        XCTAssertTrue((first.value as? String)?.contains("Primary selection") == true)
        search.click(); search.typeKey("a", modifierFlags: .command); search.typeText("no matching layer")
        XCTAssertTrue(application.descendants(matching: .any)["navigator.layers.search.empty"].waitForExistence(timeout: 3))
        XCTAssertEqual(rows.count, 0)
        XCTAssertTrue(application.buttons["navigator.layers.search.showSelected"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-067 Layers no result")
        application.buttons["navigator.layers.search.showSelected"].click()
        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue((rows.element(boundBy: 0).value as? String)?.contains("Primary selection") == true)
        search.click(); search.typeText("Text")
        application.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertEqual(rows.count, 3)
        attachWindowScreenshot(application, named: "SF-AUTHORING-067 Layers cleared")
    }

    // SF-0205-003/004/006 — native type filter composes with the live Layers
    // query and never changes the selected NodeID merely by filtering.
    func testLayersTypeFilterKeepsSelectionAndRevealsSelectedNodeJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        application.buttons["toolbar.tool.frame"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.35, dy: 0.38)).click()
        application.buttons["toolbar.tool.text"].click()
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.56, dy: 0.45)).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        application.buttons["navigator.tab.layers"].click()
        let rows = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
        let textRow = rows.matching(NSPredicate(format: "label == %@", "Text")).firstMatch
        XCTAssertTrue(textRow.waitForExistence(timeout: 3))
        textRow.click()
        let selectedID = textRow.identifier
        let type = application.popUpButtons["navigator.layers.typeFilter"]
        XCTAssertTrue(type.waitForExistence(timeout: 3))
        type.click(); type.menuItems["Frame"].click()
        XCTAssertFalse(application.descendants(matching: .any)[selectedID].exists)
        XCTAssertTrue(application.buttons["navigator.layers.search.showSelected"].exists)
        // The page root is also a Frame-kind layer; type filtering retains it
        // alongside the inserted Frame while excluding the selected Text.
        XCTAssertTrue(waitForValue(application.staticTexts["navigator.layers.search.status"], containing: "2 of 3 layers match"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-069 Layers type filtered")
        application.buttons["navigator.layers.search.showSelected"].click()
        let restored = application.descendants(matching: .any)[selectedID]
        XCTAssertTrue(restored.waitForExistence(timeout: 3))
        XCTAssertTrue((restored.value as? String)?.contains("Primary selection") == true)
        XCTAssertTrue(waitForValue(application.popUpButtons["navigator.layers.typeFilter"], containing: "All Types"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-069 Layers selected restored")
    }

    // SF-0205-002/003/004/006 — native Quick Open uses existing page and
    // Layers selection paths; Cancel is noncanonical.
    func testQuickOpenMenuKeyboardPageLayerAndCancelJourney() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeSelectionFixture", "multiple",
        ])
        application.buttons["navigator.quickOpen"].click()
        let search = application.textFields["quickOpen.search"]
        XCTAssertTrue(waitForHittable(search, in: application))
        search.click(); search.typeText("/404")
        let page = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "quickOpen.page."
        )).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-070 Quick Open page")
        page.click()
        XCTAssertFalse(application.descendants(matching: .any)["quickOpen.sheet"].exists)
        application.typeKey("o", modifierFlags: [.command, .shift])
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click(); search.typeText("no matching result")
        XCTAssertTrue(application.descendants(matching: .any)["quickOpen.empty"].waitForExistence(timeout: 3))
        application.buttons["quickOpen.cancel"].click()
        XCTAssertFalse(application.descendants(matching: .any)["quickOpen.sheet"].exists)
        // Quick Open does not change the navigator tab. On a narrow hosted
        // display the production-minimum window can place this tab partially
        // offscreen, so verify its live selected state without a redundant click.
        XCTAssertTrue(application.buttons["navigator.tab.pages"].isSelected)
        pageRow(named: "Home", in: application).click()
        application.buttons["navigator.quickOpen"].click()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click(); search.typeText("Fixture Layer 1")
        let layer = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "quickOpen.layer."
        )).firstMatch
        XCTAssertTrue(layer.waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-070 Quick Open layer")
        layer.click()
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label.contains("Fixture Layer 1"))
    }

    // SF-0205-002/006 — Quick Open View actions use the same scene-local
    // viewport/Grid boundary as their native menu counterparts.
    func testQuickOpenViewActionsFitAndToggleGridWithoutDocumentMutationJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        let initialDocumentStatus = application.descendants(matching: .any)["status.document"]
        let initial = initialDocumentStatus.value as? String
        application.buttons["navigator.quickOpen"].click()
        let search = application.textFields["quickOpen.search"]
        XCTAssertTrue(waitForHittable(search, in: application))
        search.click(); search.typeText("fit document")
        XCTAssertTrue(application.buttons["quickOpen.action.fitDocument"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-071 Quick Open View action")
        application.buttons["quickOpen.action.fitDocument"].click()
        XCTAssertFalse(application.descendants(matching: .any)["quickOpen.sheet"].exists)
        application.buttons["navigator.quickOpen"].click()
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click(); search.typeText("grid")
        let grid = application.buttons["quickOpen.action.toggleGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 3))
        grid.click()
        let gridValue = application.descendants(matching: .any)["canvas.grid.toggle"].value as? NSNumber
        XCTAssertEqual(gridValue?.intValue, 0)
        XCTAssertEqual(application.descendants(matching: .any)["status.document"].value as? String, initial)
        attachWindowScreenshot(application, named: "SF-AUTHORING-071 Quick Open Grid off")
    }

    // SF-AUTHORING-075–078: Quick Open invokes the same validated one-shot
    // insertion commands as the native Insert menu, not a parallel mutation.
    func testQuickOpenInsertActionsCreateOneObjectAndExposeImageRecoveryJourney() throws {
        let application = launchWorkspace()
        for (offset, action) in ["frame", "text", "section", "stack", "grid", "button", "link", "form"].enumerated() {
            application.buttons["navigator.quickOpen"].click()
            let search = application.textFields["quickOpen.search"]
            XCTAssertTrue(waitForHittable(search, in: application))
            search.click()
            search.typeText("insert \(action) at center")
            let result = application.buttons["quickOpen.insert.\(action)"]
            XCTAssertTrue(waitForHittable(result, in: application), action)
            result.click()
            XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects \(offset + 1)", timeout: 5), action)
            XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label.localizedCaseInsensitiveContains(action), action)
        }
        attachWindowScreenshot(application, named: "SF-AUTHORING-075-078 Quick Open authored insertions")
        application.buttons["navigator.quickOpen"].click()
        let search = application.textFields["quickOpen.search"]
        XCTAssertTrue(waitForHittable(search, in: application))
        search.click(); search.typeText("image")
        XCTAssertFalse(application.buttons["quickOpen.insert.selectedImage"].exists)
        XCTAssertTrue(application.buttons["quickOpen.insert.importImage"].waitForExistence(timeout: 3))
        application.buttons["quickOpen.cancel"].click()
    }

    // SF-AUTHORING-086–089: the visible Insert menu exposes real Divider and
    // semantic site containers rather than disabled Elements lookalikes.
    func testDividerHeaderNavigationFooterInsertThroughNativeMenuJourney() throws {
        let application = launchWorkspace()
        for (offset, title) in ["Divider", "Header", "Navigation", "Footer"].enumerated() {
            componentMenu("Insert", "Insert \(title) at Center", in: application)
            XCTAssertTrue(waitForLiveCanvasValue(in: application,
                containing: "rendered objects \(offset + 1)", timeout: 5), title)
            XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label
                .localizedCaseInsensitiveContains(title), title)
            if offset < 3 { componentMenu("Selection", "Clear Selection", in: application) }
        }
        attachWindowScreenshot(application, named: "SF-AUTHORING-086-089 authored site and divider templates")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 4", timeout: 5))
    }

    // SF-AUTHORING-090: the native menu commits a real Form-owned Text field.
    func testFormInputTemplateInsertsOnlyIntoSelectedFormJourney() throws {
        let application = launchWorkspace()
        application.menuBars.menuBarItems["Insert"].click()
        XCTAssertFalse(application.menuItems["Insert Input into Selected Form"].isEnabled)
        application.typeKey(.escape, modifierFlags: [])
        componentMenu("Insert", "Insert Form at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application,
            containing: "rendered objects 1", timeout: 5))
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label
            .localizedCaseInsensitiveContains("Form"))
        application.menuBars.menuBarItems["Insert"].click()
        XCTAssertTrue(application.menuItems["Insert Input into Selected Form"].isEnabled)
        application.typeKey(.escape, modifierFlags: [])
        componentMenu("Insert", "Insert Input into Selected Form", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application,
            containing: "rendered objects 2", timeout: 5))
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label
            .localizedCaseInsensitiveContains("Input"))
        application.buttons["inspector.tab.content"].click()
        XCTAssertTrue(application.staticTexts["Form Field"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-090 Form Input field")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application,
            containing: "rendered objects 1", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application,
            containing: "rendered objects 2", timeout: 5))
    }

    // SF-AUTHORING-091–095: every native field action remains Form-scoped,
    // adopts one canonical child, and opens the shared Content Inspector.
    func testFormFieldTemplateMenuParityInspectorAndHistoryJourney() throws {
        let application = launchWorkspace()
        let actions = ["Email", "Text Area", "Checkbox", "Select", "Submit"]
        let elementIDs = ["emailInput", "textArea", "checkbox", "selectField", "submit"]
        application.buttons["navigator.tab.elements"].click()
        for identifier in elementIDs {
            let field = application.buttons["navigator.elements.\(identifier)"]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            XCTAssertFalse(field.isEnabled)
        }
        application.menuBars.menuBarItems["Insert"].click()
        for title in actions {
            XCTAssertFalse(application.menuItems["Insert \(title) into Selected Form"].isEnabled)
        }
        application.typeKey(.escape, modifierFlags: [])
        componentMenu("Insert", "Insert Form at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application,
            containing: "rendered objects 1", timeout: 5))
        for identifier in elementIDs {
            XCTAssertTrue(application.buttons["navigator.elements.\(identifier)"].isEnabled)
        }
        for (offset, title) in actions.enumerated() {
            if offset > 0 {
                application.buttons["navigator.tab.layers"].click()
                let form = application.buttons.matching(NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label == %@",
                    "navigator.layer.", "Form"
                )).firstMatch
                XCTAssertTrue(form.waitForExistence(timeout: 3))
                form.click()
            }
            componentMenu("Insert", "Insert \(title) into Selected Form", in: application)
            XCTAssertTrue(waitForLiveCanvasValue(in: application,
                containing: "rendered objects \(offset + 2)", timeout: 5), title)
            XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label
                .localizedCaseInsensitiveContains(title), title)
            application.buttons["inspector.tab.content"].click()
            XCTAssertTrue(application.staticTexts["Form Field"].waitForExistence(timeout: 3), title)
        }
        attachWindowScreenshot(application,
            named: "SF-AUTHORING-091-095 supported Form field templates")
        for expectedCount in stride(from: 5, through: 1, by: -1) {
            application.typeKey("z", modifierFlags: .command)
            XCTAssertTrue(waitForLiveCanvasValue(in: application,
                containing: "rendered objects \(expectedCount)", timeout: 5))
        }
        for expectedCount in 2...6 {
            application.typeKey("z", modifierFlags: [.command, .shift])
            XCTAssertTrue(waitForLiveCanvasValue(in: application,
                containing: "rendered objects \(expectedCount)", timeout: 5))
        }
    }

    // SF-AUTHORING-096: canonical field metadata is editable through Content,
    // projected truthfully through Accessibility, and local validation remains
    // scene-local while static submission stays disabled and unconfigured.
    func testFormAccessibilityValidationAndContentInspectorJourney() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Form at Center", in: application)
        componentMenu("Insert", "Insert Email into Selected Form", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))

        application.buttons["inspector.tab.content"].click()
        let label = application.textFields["inspector.form.label"]
        XCTAssertTrue(waitForHittable(label, in: application))
        replaceText(in: label, with: "Work email", application: application)
        let requirement = application.popUpButtons["inspector.form.required"]
        XCTAssertTrue(waitForHittable(requirement, in: application))
        requirement.click(); application.menuItems["Required"].click()
        application.buttons["inspector.form.apply"].click()
        XCTAssertTrue(waitForLiveValue(in: application,
                                       identifier: "inspector.form.status",
                                       containing: "committed"))

        application.buttons["inspector.tab.accessibility"].click()
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.accessibility.formField.kind"],
                                   containing: "Email"))
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.accessibility.formField.name"],
                                   containing: "Work email"))
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.accessibility.formField.required"],
                                   containing: "Required"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-096 accessible Email field")

        application.buttons["navigator.tab.layers"].click()
        let form = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Form"
        )).firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3))
        form.click()
        application.buttons["inspector.tab.accessibility"].click()
        XCTAssertTrue(application.descendants(matching: .any)["inspector.accessibility.form.status"]
            .waitForExistence(timeout: 3))
        let validate = application.buttons["inspector.accessibility.form.validate"]
        XCTAssertTrue(waitForHittable(validate, in: application))
        validate.click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.accessibility.form.validation"],
                                   containing: "field issue"))
        XCTAssertTrue(application.staticTexts["Submit controls"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-096 local validation and safe submit boundary")

        application.typeKey("z", modifierFlags: .command)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(application.descendants(matching: .any)["inspector.accessibility.form.status"].exists)
    }

    // SF-AUTHORING-098, SF-0701-002/006, SF-0702-002/006, SF-1203-002/006
    // — the shipping Accessibility tab edits canonical metadata through the
    // same transaction used by keyboard/accessibility clients and the canvas
    // immediately republishes the authored semantic label.
    func testGeneralAccessibilityMetadataInspectorUndoRedoJourney() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.buttons["inspector.tab.accessibility"].click()
        let name = application.textFields["inspector.accessibility.name"]
        let help = application.textFields["inspector.accessibility.help"]
        XCTAssertTrue(waitForHittable(name, in: application))
        XCTAssertTrue(waitForHittable(help, in: application))
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.accessibility.role"],
                                   containing: "<div>"))
        name.click(); name.typeText("Hero region"); name.typeKey(.return, modifierFlags: [])
        help.click(); help.typeText("Introduces the page"); help.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.accessibility.announcement"],
                                   containing: "committed"))
        let object = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object."))
            .firstMatch
        XCTAssertTrue(object.waitForExistence(timeout: 3))
        XCTAssertEqual(object.label, "Hero region")
        XCTAssertTrue(waitForValue(help, containing: "Introduces the page"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-098 authored accessibility metadata")

        application.typeKey("z", modifierFlags: .command)
        application.typeKey("z", modifierFlags: .command)
        XCTAssertNotEqual(application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object."))
            .firstMatch.label, "Hero region")
        application.typeKey("z", modifierFlags: [.command, .shift])
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object."))
            .firstMatch.label, "Hero region")

        name.click(); name.typeKey("a", modifierFlags: .command); name.typeText("Cancelled name")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object."))
            .firstMatch.label, "Hero region")
    }

    // SF-AUTHORING-099: Elements and the native Insert menu create the same
    // semantic, editable Text-backed Heading without a parallel node kind.
    func testHeadingTemplateElementsMenuTypographyAndHistoryJourney() throws {
        let application = launchWorkspace()
        application.buttons["navigator.tab.elements"].click()
        let heading = application.buttons["navigator.elements.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        XCTAssertTrue(heading.isEnabled)
        componentMenu("Insert", "Insert Heading at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label
            .localizedCaseInsensitiveContains("Heading"))
        application.buttons["inspector.tab.design"].click()
        let inspector = application.scrollViews["inspector.selection.scroll"]
        let element = application.descendants(matching: .any)["inspector.semantic.element"]
        for _ in 0..<14 where !element.isHittable { inspector.scroll(byDeltaX: 0, deltaY: -120) }
        XCTAssertTrue(element.isHittable)
        XCTAssertTrue((element.value as? String ?? "").contains("<h2>"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-099 semantic Heading template")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
    }

    // SF-AUTHORING-079 — the Quick Open action opens the real Page editor;
    // cancellation is noncanonical and Apply uses the existing page command.
    func testQuickOpenNewPageOpensNativeEditorAndPreservesCancelJourney() throws {
        let application = launchWorkspace()
        @MainActor func openNewPage() {
            application.buttons["navigator.quickOpen"].click()
            let search = application.textFields["quickOpen.search"]
            XCTAssertTrue(waitForHittable(search, in: application))
            search.click(); search.typeText("new page")
            let action = application.buttons["quickOpen.pageAction.newPage"]
            XCTAssertTrue(waitForHittable(action, in: application))
            action.click()
            XCTAssertTrue(application.textFields["page.editor.name"].waitForExistence(timeout: 3))
        }
        openNewPage()
        attachWindowScreenshot(application, named: "SF-AUTHORING-079 Quick Open New Page draft")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(application.textFields["page.editor.name"].exists)
        openNewPage()
        let name = application.textFields["page.editor.name"]
        replaceText(in: name, with: "Quick Open Page", application: application)
        application.buttons["page.editor.apply"].click()
        XCTAssertTrue(waitForNonexistence(application.textFields["page.editor.name"]))
        application.activate()
        revealComponentPointerTarget("navigator.tab.pages", in: application).click()
        let created = pageRow(named: "Quick Open Page", in: application)
        XCTAssertTrue(created.waitForExistence(timeout: 5), application.debugDescription)
        attachWindowScreenshot(application, named: "SF-AUTHORING-079 Quick Open page created")
    }

    // SF-AUTHORING-080/083 — navigator and Quick Open use the same stable
    // definition identity; search alone neither inserts nor edits an instance.
    func testComponentsSearchAndQuickOpenRevealDefinitionJourney() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        componentMenu("Component", "Create Component from Selection", in: application)
        let overflow = application.descendants(matching: .any)["navigator.tab.overflow"]
        if overflow.exists && overflow.isHittable {
            overflow.click(); application.menuItems["Components"].click()
        } else {
            application.buttons["navigator.tab.components"].click()
        }
        let search = application.textFields["components.search"]
        XCTAssertTrue(waitForHittable(search, in: application))
        search.click(); search.typeText("Frame")
        let row = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "components.definition."
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let definitionID = row.identifier.replacingOccurrences(of: "components.definition.", with: "")
        search.typeKey("a", modifierFlags: .command); search.typeText("no component matches")
        XCTAssertTrue(application.descendants(matching: .any)["components.search.empty"].waitForExistence(timeout: 3))
        application.buttons["components.search.clear"].click()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-080 Components search recovery")
        application.buttons["navigator.quickOpen"].click()
        let quickSearch = application.textFields["quickOpen.search"]
        XCTAssertTrue(waitForHittable(quickSearch, in: application))
        quickSearch.click(); quickSearch.typeText("Frame")
        let result = application.buttons["quickOpen.component.\(definitionID)"]
        XCTAssertTrue(result.waitForExistence(timeout: 3))
        result.click()
        XCTAssertTrue(application.descendants(matching: .any)["components.definition.\(definitionID)"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.descendants(matching: .any)["components.definition.revealed.\(definitionID)"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-083 Quick Open component revealed")
        application.buttons["navigator.quickOpen"].click()
        let insertSearch = application.textFields["quickOpen.search"]
        XCTAssertTrue(waitForHittable(insertSearch, in: application))
        insertSearch.click(); insertSearch.typeText("Frame")
        let insert = application.buttons["quickOpen.component.insert.\(definitionID)"]
        XCTAssertTrue(waitForHittable(insert, in: application))
        insert.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-085 Quick Open component inserted")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
    }

    // SF-AUTHORING-100: rename uses the visible native Components workflow
    // and preserves linked instance identity through exact history.
    func testComponentDefinitionRenamePropagatesToLinkedInstancesJourney() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Frame at Center", in: application)
        componentMenu("Component", "Create Component from Selection", in: application)
        let overflow = application.descendants(matching: .any)["navigator.tab.overflow"]
        if overflow.exists && overflow.isHittable {
            overflow.click(); application.menuItems["Components"].click()
        } else { application.buttons["navigator.tab.components"].click() }
        let definition = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "components.definition."
        )).firstMatch
        XCTAssertTrue(definition.waitForExistence(timeout: 3))
        let id = definition.identifier.replacingOccurrences(of: "components.definition.", with: "")
        let rename = application.buttons["components.rename.\(id)"]
        XCTAssertTrue(waitForHittable(rename, in: application))
        rename.click()
        let name = liveStructuralLayoutControl("components.rename.name", in: application)
        XCTAssertTrue(waitForHittable(name, in: application))
        replaceText(in: name, with: "Feature Card", application: application)
        application.buttons["components.rename.apply"].click()
        XCTAssertTrue(waitForLiveValue(in: application,
                                       identifier: "components.definition.\(id)",
                                       containing: "linked instances"))
        XCTAssertEqual(application.descendants(matching: .any)["components.definition.\(id)"].label,
                       "Feature Card")
        attachWindowScreenshot(application, named: "SF-AUTHORING-100 renamed linked component")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(application.descendants(matching: .any)["components.definition.\(id)"].label,
                       "Frame")
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertEqual(application.descendants(matching: .any)["components.definition.\(id)"].label,
                       "Feature Card")
    }

    // SF-0205-003/004/006 — explicit page navigation yields a bounded,
    // scene-local recent list that opens via the existing PageID command.
    func testQuickOpenRecentPagesPreserveIDsAndOpenThroughNativeJourney() throws {
        let application = launchWorkspace()
        let home = pageRow(named: "Home", in: application)
        let missing = pageRow(named: "Not Found", in: application)
        missing.click(); home.click()
        application.buttons["navigator.quickOpen"].click()
        let recent = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "quickOpen.recentPage."
        )).allElementsBoundByAccessibilityElement
        XCTAssertEqual(recent.count, 2)
        XCTAssertTrue(recent[0].label.contains("Home"))
        XCTAssertTrue(recent[1].label.contains("Not Found"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-072 Quick Open recent pages")
        recent[1].click()
        XCTAssertEqual(pageRow(named: "Not Found", in: application).value as? String, "Not Found page; Selected")
        application.buttons["navigator.quickOpen"].click()
        XCTAssertEqual(application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "quickOpen.recentPage."
        )).count, 2)
    }

    // SF-0205-003/004/006 — recent layers retain NodeID and cannot reveal
    // targets outside the current authorized Layers projection.
    func testQuickOpenRecentLayersUseLiveSelectedNodeJourney() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeSelectionFixture", "multiple",
        ])
        application.buttons["navigator.tab.layers"].click()
        let rows = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
        let first = rows.matching(NSPredicate(format: "label == %@", "Fixture Layer 1")).firstMatch
        let second = rows.matching(NSPredicate(format: "label == %@", "Fixture Layer 2")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 3) && second.waitForExistence(timeout: 3))
        first.click(); second.click()
        application.buttons["navigator.quickOpen"].click()
        let recent = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "quickOpen.recentLayer."
        )).allElementsBoundByAccessibilityElement
        XCTAssertEqual(recent.count, 2)
        XCTAssertTrue(recent[0].label.contains("Fixture Layer 2"))
        XCTAssertTrue(recent[1].label.contains("Fixture Layer 1"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-073 Quick Open recent layers")
        recent[1].click()
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label.contains("Fixture Layer 1"))
    }

    // SF-0205-003/004/006 — native scopes keep the same Quick Open target
    // identities while hiding irrelevant classes and preserving cancellation.
    func testQuickOpenScopesPagesLayersActionsAndCancelJourney() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeSelectionFixture", "multiple",
        ])
        application.buttons["navigator.quickOpen"].click()
        let sheet = application.descendants(matching: .any)["quickOpen.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        let pagesScope = sheet.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Pages")).firstMatch
        XCTAssertTrue(pagesScope.waitForExistence(timeout: 3))
        pagesScope.click()
        XCTAssertTrue(application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quickOpen.page.")).count >= 2)
        XCTAssertEqual(application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quickOpen.layer.")).count, 0)
        sheet.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Layers")).firstMatch.click()
        XCTAssertTrue(application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quickOpen.layer.")).count >= 2)
        XCTAssertEqual(application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quickOpen.page.")).count, 0)
        attachWindowScreenshot(application, named: "SF-AUTHORING-074 Quick Open Layers scope")
        sheet.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Actions")).firstMatch.click()
        XCTAssertEqual(application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quickOpen.action.")).count, 3)
        XCTAssertEqual(application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "quickOpen.layer.")).count, 0)
        attachWindowScreenshot(application, named: "SF-AUTHORING-074 Quick Open Actions scope")
        application.buttons["quickOpen.cancel"].click()
        XCTAssertTrue(waitForLiveNonexistence(in: application, identifier: "quickOpen.sheet"))
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
        windowAlignment: TestWindowAlignment? = nil,
        workspaceReadinessTimeout: TimeInterval = 5,
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
        if let windowAlignment {
            application.launchArguments += ["-SiteForgeUITestWindowAlignment", windowAlignment.rawValue]
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
            XCTAssertTrue(waitForWorkspaceReady(application, timeout: workspaceReadinessTimeout))
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
            "-SiteForgeRecentProjectsStore", fixtureRoot.appendingPathComponent("recent-projects.json").path,
            "-SiteForgeFileBookmarkStore", fixtureRoot.appendingPathComponent("file-bookmarks.json").path,
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
        waitForKeyboardFocus(identifier: element.identifier, in: application, timeout: timeout)
    }

    private func waitForKeyboardFocus(
        identifier: String,
        in application: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let focusedMatch = application.descendants(matching: .any)
            .matching(NSPredicate(
                format: "identifier == %@ AND hasKeyboardFocus == true",
                identifier
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
            attachFocusDiagnostics(expected: identifier, application: application)
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

    /// Replaces a prefilled native macOS text field through ordinary keyboard
    /// input. Xcode 27 can deliver Command-A to the enclosing SwiftUI host
    /// rather than the focused NSTextField, so deleting the known live value
    /// from the end is deterministic without adding an automation-only path.
    private func replaceText(
        in field: XCUIElement,
        with replacement: String,
        application: XCUIApplication
    ) {
        let identifier = field.identifier
        let liveField = field.elementType == .textView
            ? application.textViews[identifier]
            : application.textFields[identifier]
        if !hasKeyboardFocus(liveField) {
            XCTAssertTrue(waitForHittable(liveField, in: application))
            liveField.click()
        }
        XCTAssertTrue(waitForKeyboardFocus(identifier: identifier, in: application))
        liveField.typeKey(.leftArrow, modifierFlags: .command)
        liveField.typeKey(.rightArrow, modifierFlags: [.command, .shift])
        liveField.typeKey(.delete, modifierFlags: [])
        liveField.typeText(replacement)
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

    /// SwiftUI can replace the native host while dismissing a sheet. Re-query
    /// the live accessibility hierarchy so a cached proxy cannot report a
    /// removed Quick Open surface as still present.
    private func waitForLiveNonexistence(
        in application: XCUIApplication,
        identifier: String,
        timeout: TimeInterval = 5
    ) -> Bool {
        let predicate = NSPredicate { [weak application] _, _ in
            guard let application else { return false }
            return !application.descendants(matching: .any)
                .matching(identifier: identifier).firstMatch.exists
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: application)],
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
        application={state=\(application.state.rawValue);enabled=\(application.isEnabled);sheets=\(application.sheets.count);dialogs=\(application.dialogs.count)}
        state={exists=\(controlExists);enabled=\(controlExists && control.isEnabled);hittable=\(controlExists && control.isHittable);focused=\(controlExists && hasKeyboardFocus(control))}
        controlFrame=\(controlExists ? sanitizedFrame(control.frame) : "unavailable")
        visibleScreen={x=0.0;y=0.0;width=\(screenSize.width);height=\(screenSize.height)}
        window={identifier=\(windowExists ? window.identifier : "unavailable");enabled=\(windowExists && window.isEnabled);frame=\(windowExists ? sanitizedFrame(window.frame) : "unavailable")}
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
        retryBase64Fixture: URL? = nil,
        windowAlignment: TestWindowAlignment? = nil
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
        if let windowAlignment {
            application.launchArguments += ["-SiteForgeUITestWindowAlignment", windowAlignment.rawValue]
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
        recoveryDirectory: URL? = nil,
        windowAlignment: TestWindowAlignment? = nil
    ) -> XCUIApplication {
        continueAfterFailure = false
        let application = trackedApplication()
        application.launchArguments += baseLaunchArguments(recoveryDirectory: recoveryDirectory) + [
            "-SiteForgeIntegrationOpenProject", url.path,
        ]
        if let windowAlignment {
            application.launchArguments += ["-SiteForgeUITestWindowAlignment", windowAlignment.rawValue]
        }
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

    private func makeLocalImageFixture(named name: String) throws -> URL {
        let url = fixtureRoot.appendingPathComponent(name)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 180,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw CocoaError(.fileWriteUnknown)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemOrange.setFill(); NSRect(x: 0, y: 0, width: 160, height: 180).fill()
        NSColor.systemTeal.setFill(); NSRect(x: 160, y: 0, width: 160, height: 180).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func waitForNativeOpenPanel(in application: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { object, _ in
                    guard let app = object as? XCUIApplication else { return false }
                    return app.sheets.count > 0 || app.dialogs.count > 0
                },
                object: application
            )],
            timeout: timeout
        ) == .completed
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
        let application = launchWorkspace(windowAlignment: leadingEdgeAlignmentOnNarrowDisplay)

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
        for identifier in ["section", "stack", "grid", "button", "link"] {
            let item = application.buttons["navigator.elements.\(identifier)"]
            XCTAssertTrue(item.exists, identifier)
            XCTAssertTrue(item.isEnabled, identifier)
            XCTAssertTrue(item.label == identifier.capitalized)
        }
        for (identifier, label) in [
            ("divider", "Divider"), ("header", "Header"),
            ("navbar", "Navigation"), ("footer", "Footer")
        ] {
            let item = application.buttons["navigator.elements.\(identifier)"]
            XCTAssertTrue(item.exists, identifier)
            XCTAssertTrue(item.isEnabled, identifier)
            XCTAssertEqual(item.label, label)
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
        XCTAssertTrue(application.descendants(matching: .any)["assets.empty"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForHittable(application.buttons["assets.empty.import"], in: application))

        // Components can be beyond the horizontally scrolled tab strip at
        // the practical minimum width. Use the real, always-visible native
        // overflow menu rather than assuming its direct tab is on screen.
        let navigatorOverflow = application.descendants(matching: .any)["navigator.tab.overflow"]
        XCTAssertTrue(waitForHittable(navigatorOverflow, in: application))
        navigatorOverflow.click()
        let componentsMenuItem = application.menuItems["Components"]
        XCTAssertTrue(componentsMenuItem.waitForExistence(timeout: 3))
        componentsMenuItem.click()
        XCTAssertTrue(application.buttons["components.create"].waitForExistence(timeout: 3))
        XCTAssertFalse(application.buttons["components.create"].isEnabled)
    }

    // SF-0901-002/005/006: only native menus and Inspector controls author
    // definitions/instances; the package is reopened by a fresh app process.
    func testComponentTextPropertiesTwoInstancesResetHistoryAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("component-text-properties.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let firstID = canvasObject(named: "Frame", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + firstID, in: application).click()
        componentMenu("Component", "Create Component from Selection", in: application)
        componentMenu("Component", "Edit Definition", in: application)
        XCTAssertTrue(application.buttons["components.exit"].waitForExistence(timeout: 3))
        let textRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text")).firstMatch
        XCTAssertTrue(textRow.waitForExistence(timeout: 3))
        revealComponentPointerTarget(textRow.identifier, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("component.text.definition.name", with: "Title", in: application)
        replaceComponentTextField("component.text.definition.default", with: "Shared", in: application)
        revealComponentPointerTarget("component.text.definition.apply", in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["component.text.status"], containing: "committed"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-024 exposed definition text")
        revealComponentPointerTarget("components.exit", in: application).click()
        let field = application.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component.text.value.")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        let fieldID = field.identifier, propertyID = fieldID.replacingOccurrences(of: "component.text.value.", with: "")
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Shared"))
        application.menuBars.menuBarItems["Component"].click()
        application.menuItems["Insert Component"].click()
        application.menuItems["Insert Frame Component"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 4", timeout: 5))
        let frames = application.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "canvas.object.", "Frame"))
        let second = try XCTUnwrap(frames.allElementsBoundByIndex.first { $0.identifier != "canvas.object." + firstID })
        let secondID = second.identifier.replacingOccurrences(of: "canvas.object.", with: "")
        revealComponentPointerTarget("inspector.tab.layout", in: application).click()
        replaceStructuralLayoutField(application.textFields["inspector.layout.x"], with: "80", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.layout.y"], with: "80", in: application)
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField(fieldID, with: "Second", in: application)
        application.textFields[fieldID].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Second"))
        XCTAssertTrue(waitForComponentRenderedText("Second", in: application))
        XCTAssertTrue(waitForComponentRenderedText("Shared", in: application))
        attachWindowScreenshot(application, named: "SF-AUTHORING-024 independent instance override")
        revealComponentPointerTarget("navigator.layer." + firstID, in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Shared"))
        componentMenu("Component", "Edit Definition", in: application)
        XCTAssertTrue(textRow.waitForExistence(timeout: 3))
        revealComponentPointerTarget(textRow.identifier, in: application).click()
        replaceComponentTextField("component.text.definition.default", with: "Revised", in: application)
        revealComponentPointerTarget("component.text.definition.apply", in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["component.text.status"], containing: "committed"))
        revealComponentPointerTarget("components.exit", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Revised"))
        XCTAssertTrue(waitForComponentRenderedText("Revised", in: application))
        XCTAssertTrue(waitForComponentRenderedText("Second", in: application))
        attachWindowScreenshot(application, named: "SF-AUTHORING-024 default propagation preserves override")
        revealComponentPointerTarget("navigator.layer." + secondID, in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Second"))
        revealComponentPointerTarget("component.text.reset." + propertyID, in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Revised"))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Second"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Revised"))
        replaceComponentTextField(fieldID, with: "Discard", in: application)
        application.textFields[fieldID].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Revised"))
        XCTAssertFalse(waitForComponentRenderedText("Discard", in: application, timeout: 0))
        attachWindowScreenshot(application, named: "SF-AUTHORING-024 reset history and cancelled draft")
        replaceComponentTextField(fieldID, with: "Saved instance", in: application)
        revealComponentPointerTarget("component.text.apply." + propertyID, in: application).click()
        XCTAssertTrue(waitForComponentRenderedText("Saved instance", in: application), application.debugDescription)
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("component-text-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + secondID, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Saved instance"))
        XCTAssertTrue(waitForComponentRenderedText("Saved instance", in: application))
        XCTAssertTrue(waitForComponentRenderedText("Revised", in: application))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier.hasPrefix("canvas.object."), true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-024 reopened linked text properties")
        revealComponentPointerTarget("component.text.resetAll", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Revised"))
        XCTAssertFalse(application.buttons["component.text.resetAll"].isEnabled)
    }

    func testComponentVisibilityDefinitionInstanceResetAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("component-visibility.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let frameID = canvasObject(named: "Frame", in: application).identifier
            .replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + frameID, in: application).click()
        componentMenu("Component", "Create Component from Selection", in: application)
        componentMenu("Component", "Edit Definition", in: application)
        let textRow = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text")).firstMatch
        XCTAssertTrue(textRow.waitForExistence(timeout: 3))
        revealComponentPointerTarget(textRow.identifier, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("component.visibility.definition.name", with: "Optional caption", in: application)
        revealComponentPointerTarget("component.visibility.definition.default", in: application).click()
        revealComponentPointerTarget("component.visibility.definition.apply", in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["component.visibility.status"], containing: "committed"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-062 hidden definition default")
        revealComponentPointerTarget("components.exit", in: application).click()
        let toggle = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "component.visibility.value.")).firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        let propertyID = toggle.identifier.replacingOccurrences(of: "component.visibility.value.", with: "")
        XCTAssertTrue(waitForComponentVisibilityState(toggle.identifier, visible: false, in: application))
        XCTAssertTrue(application.descendants(matching: .any)["navigator.componentVisibility." + propertyID].exists)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-062 instance inherits hidden")
        revealComponentPointerTarget(toggle.identifier, in: application).click()
        XCTAssertTrue(waitForComponentVisibilityState(toggle.identifier, visible: true, in: application))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertTrue(waitForComponentRenderedText("Text", in: application))
        attachWindowScreenshot(application, named: "SF-AUTHORING-062 authored visible override")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForComponentVisibilityState(toggle.identifier, visible: false, in: application))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForComponentVisibilityState(toggle.identifier, visible: true, in: application))
        revealComponentPointerTarget("component.visibility.reset." + propertyID, in: application).click()
        XCTAssertTrue(waitForComponentVisibilityState(toggle.identifier, visible: false, in: application))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-062 reset inherits hidden")
        revealComponentPointerTarget(toggle.identifier, in: application).click()
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project,
            recoveryDirectory: fixtureRoot.appendingPathComponent("component-visibility-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + frameID, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        XCTAssertTrue(waitForComponentVisibilityState(toggle.identifier, visible: true, in: application))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-062 reopened visible override")
    }

    private func waitForComponentVisibilityState(_ identifier: String, visible: Bool,
                                                  in application: XCUIApplication) -> Bool {
        let expected = visible ? 1 : 0
        let predicate = NSPredicate { _, _ in
            let control = application.checkBoxes[identifier]
            return control.exists && (control.value as? NSNumber)?.intValue == expected
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: application)],
                             timeout: 5) == .completed
    }

    private func replaceComponentTextField(_ identifier: String, with value: String, in application: XCUIApplication) {
        let exposed = revealComponentPointerTarget(identifier, in: application)
        replaceText(in: application.textFields[exposed.identifier], with: value, application: application)
    }

    private func waitForComponentRenderedText(_ text: String, in application: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        let live = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND value == %@", "canvas.object.", "Text: " + text)).firstMatch
        // A zero-duration waiter interrupts AX snapshot work. Negative checks
        // use a single current query; positive checks await the exact value.
        return timeout == 0 ? live.exists : live.waitForExistence(timeout: timeout)
    }

    func testLocalComponentsCreateLinkEditDetachAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("local-components.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        editComponentHex("#336699FF", in: application)
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        application.buttons["navigator.tab.layers"].click()
        let frameRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame")).firstMatch
        XCTAssertTrue(frameRow.waitForExistence(timeout: 3)); frameRow.click()
        let originalID = canvasObject(named: "Frame", in: application).identifier
        componentMenu("Component", "Create Component from Selection", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, originalID)
        revealComponentPointerTarget("navigator.tab.overflow", in: application).click()
        application.menuItems["Components"].click()
        XCTAssertTrue(application.buttons["components.create"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.staticTexts["inspector.component.provenance"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 original linked instance")

        let deleteDefinition = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "components.delete.")).firstMatch
        revealComponentPointerTarget(deleteDefinition.identifier, in: application)
        XCTAssertTrue(waitForHittable(deleteDefinition, in: application))
        deleteDefinition.click()
        XCTAssertTrue(application.buttons["Detach Uses and Delete"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 safe delete confirmation")
        application.buttons["components.delete.cancel"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, originalID)
        XCTAssertTrue(application.staticTexts["inspector.component.provenance"].exists)

        componentMenu("Page", "New Page…", in: application)
        let name = application.textFields["page.editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        replaceText(in: name, with: "Instances", application: application)
        application.buttons["page.editor.apply"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        application.menuBars.menuBarItems["Component"].click()
        application.menuItems["Insert Component"].click()
        application.menuItems["Insert Frame Component"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        let secondID = canvasObject(named: "Frame", in: application).identifier
        XCTAssertNotEqual(secondID, originalID)
        componentMenu("Component", "Edit Definition", in: application)
        XCTAssertTrue(application.buttons["components.exit"].waitForExistence(timeout: 3))
        revealComponentPointerTarget("components.exit", in: application)
        XCTAssertTrue(waitForHittable(application.buttons["components.exit"], in: application))
        editComponentHex("#994422FF", in: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 definition editing")
        revealComponentPointerTarget("components.exit", in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, secondID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 propagated second instance")
        componentMenu("Component", "Detach Instance", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: "#994422FF"))
        application.typeKey("z", modifierFlags: .command)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: "#994422FF"))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, secondID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 detached undo redo")
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("components-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        revealComponentPointerTarget("navigator.tab.pages", in: application).click()
        let page = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "navigator.page.", "Instances, route ")).firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 3)); page.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, secondID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 reopened detached instance")
    }

    // Instance methods preserve MainActor isolation under the hosted Swift
    // compiler; nested helpers must not capture the non-Sendable XCTestCase.
    private func componentMenu(_ menu: String, _ action: String, in application: XCUIApplication) {
        application.menuBars.menuBarItems[menu].click()
        XCTAssertTrue(waitForEnabled(application.menuItems[action]))
        application.menuItems[action].click()
    }

    private func editComponentHex(_ value: String, in application: XCUIApplication) {
        application.buttons["inspector.tab.design"].click()
        revealComponentPointerTarget("inspector.design.fillHex", in: application)
        let field = application.textFields["inspector.design.fillHex"]
        XCTAssertTrue(waitForHittable(field, in: application))
        replaceText(in: field, with: value, application: application)
        field.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: value))
    }

    func testLocalComponentsConstrainedMinimumOverflowAndCancellationJourney() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWindowSize", "minimum", "-SiteForgeUITestWindowAlignment", TestWindowAlignment.left.rawValue
        ])
        XCTAssertEqual(application.descendants(matching: .any)["workspace.shell"].frame.width, 1_100, accuracy: 2)
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Frame at Center"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let originalID = canvasObject(named: "Frame", in: application).identifier
        application.menuBars.menuBarItems["Component"].click()
        application.menuItems["Create Component from Selection"].click()
        let overflow = application.descendants(matching: .any)["navigator.tab.overflow"]
        XCTAssertTrue(waitForHittable(overflow, in: application))
        overflow.click()
        XCTAssertTrue(application.menuItems["Components"].isEnabled)
        application.menuItems["Components"].click()
        for prefix in ["components.insert.", "components.edit.", "components.delete."] {
            let button = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
            XCTAssertTrue(waitForHittable(button, in: application))
            XCTAssertTrue(button.isEnabled)
        }
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 compact Components overflow")
        application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "components.delete.")).firstMatch.click()
        XCTAssertTrue(application.buttons["Detach Uses and Delete"].waitForExistence(timeout: 3))
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, originalID)
        XCTAssertTrue(application.buttons["components.edit.selected"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 compact keyboard cancellation")
    }

    func testNarrowDisplayPointerAlignmentPreservesWindowAndRevealsBothEdges() {
        let visible = CGRect(x: 0, y: 24, width: 1024, height: 700)
        let leadingWindow = CGRect(x: 16, y: 47, width: 1100, height: 642)
        let undo = CGRect(x: 993, y: 47, width: 41, height: 52)
        let trailingShift = PointerWindowPlacement.horizontalTranslation(window: leadingWindow, target: undo, visible: visible)
        XCTAssertEqual(trailingShift, -10)
        let trailingWindow = leadingWindow.offsetBy(dx: trailingShift, dy: 0)
        XCTAssertEqual(trailingWindow.width, 1100)
        XCTAssertLessThanOrEqual(undo.offsetBy(dx: trailingShift, dy: 0).maxX, visible.maxX)
        let pages = CGRect(x: -32.5, y: 97.5, width: 44, height: 26)
        let leadingShift = PointerWindowPlacement.horizontalTranslation(window: trailingWindow, target: pages, visible: visible)
        XCTAssertEqual(leadingShift, 32.5)
        XCTAssertGreaterThanOrEqual(pages.offsetBy(dx: leadingShift, dy: 0).minX, visible.minX)
        XCTAssertEqual(trailingWindow.offsetBy(dx: leadingShift, dy: 0).width, 1100)
        // Both a long Content-Inspector field and a canvas target can live
        // in the obscured strip of the approved 1100-point window. The same
        // real title-bar translation must reveal either actual target.
        let componentTextField = CGRect(x: 1_070, y: 260, width: 210, height: 22)
        let componentShift = PointerWindowPlacement.horizontalTranslation(
            window: leadingWindow, target: componentTextField, visible: visible
        )
        XCTAssertEqual(componentShift, -256)
        XCTAssertLessThanOrEqual(componentTextField.offsetBy(dx: componentShift, dy: 0).maxX, visible.maxX)
        // A constrained AppKit drag can be clamped before it applies the full
        // request. Re-querying the live target yields one bounded corrective
        // translation instead of assuming the first drag completed.
        let partiallyMovedComponent = componentTextField.offsetBy(dx: -180, dy: 0)
        let correctiveShift = PointerWindowPlacement.horizontalTranslation(
            window: leadingWindow.offsetBy(dx: -180, dy: 0), target: partiallyMovedComponent, visible: visible
        )
        XCTAssertEqual(correctiveShift, -76)
        XCTAssertLessThanOrEqual(partiallyMovedComponent.offsetBy(dx: correctiveShift, dy: 0).maxX, visible.maxX)
        let canvasTarget = CGRect(x: -86, y: 340, width: 240, height: 160)
        let canvasShift = PointerWindowPlacement.horizontalTranslation(
            window: leadingWindow, target: canvasTarget, visible: visible
        )
        XCTAssertEqual(canvasShift, 86)
        XCTAssertGreaterThanOrEqual(canvasTarget.offsetBy(dx: canvasShift, dy: 0).minX, visible.minX)
        XCTAssertEqual(PointerWindowPlacement.horizontalTranslation(window: trailingWindow,
            target: CGRect(x: 200, y: 100, width: 100, height: 30), visible: visible), 0)
    }

    func testConstrainedWindowPlacementPreservesNativeTitleBarMoveAcrossViewUpdates() {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWindowSize", "minimum", "-SiteForgeUITestWindowAlignment", "left"
        ])
        XCTAssertTrue(waitForWorkspaceReady(application))
        let before = application.windows.firstMatch.frame
        let displayLeadingEdge = NSScreen.main?.visibleFrame.minX ?? before.minX
        PointerWindowPlacement.moveWindowHorizontally(by: -80, in: application)
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            application.windows.firstMatch.frame.minX < displayLeadingEdge
        }, object: application)], timeout: 3) == .completed, "Native movement must not be undone by placement observers: before=\(before), after=\(application.windows.firstMatch.frame)")
        // AppKit may snap a dragged window at the screen edge. Its accepted
        // frame, not an assumed pointer-to-window translation, is the state
        // subsequent SwiftUI updates must preserve.
        let moved = application.windows.firstMatch.frame
        let grid = application.descendants(matching: .any).matching(identifier: "canvas.grid.toggle").firstMatch
        XCTAssertTrue(grid.isEnabled && grid.isHittable)
        grid.click()
        XCTAssertEqual(application.windows.firstMatch.frame, moved)
        XCTAssertEqual(application.windows.firstMatch.frame.width, before.width, accuracy: 1)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 constrained native movement retained")
    }

    /// A 1100-point window can exceed the hosted display. Move the actual
    /// title bar to expose a target, retaining the production minimum and
    /// real pointer/focus assertions rather than bypassing the control.
    @discardableResult
    private func revealComponentPointerTarget(_ identifier: String, in application: XCUIApplication) -> XCUIElement {
        let query = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 3))
        guard let visible = NSScreen.main?.visibleFrame else {
            XCTFail("A usable display is required for pointer interaction")
            return query
        }
        // A canonical command may finish before its native sheet dismisses.
        // Window AXEnabled is not a control-availability signal on macOS;
        // require the foreground application and actual enabled target.
        guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            application.state == .runningForeground
                && application.descendants(matching: .any).matching(identifier: identifier).firstMatch.isEnabled
        }, object: application)], timeout: 3) == .completed else {
            XCTFail("The app must be active and the live pointer control enabled: \(application.debugDescription)")
            return query
        }
        // AppKit can accept a constrained title-bar drag while clamping the
        // window origin. Re-query the AX target after each real drag and make
        // one bounded corrective movement when it remains clipped.
        for _ in 0..<2 {
            let live = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
            let delta = PointerWindowPlacement.horizontalTranslation(
                window: application.windows.firstMatch.frame, target: live.frame, visible: visible
            )
            guard delta != 0 else { break }
            PointerWindowPlacement.moveWindowHorizontally(by: delta, in: application)
        }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let live = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
            return live.isEnabled && live.isHittable && live.frame.minX >= visible.minX - 1
                && live.frame.maxX <= visible.maxX + 1
        }, object: application)], timeout: 3) == .completed,
            "The live component control must be enabled, hittable and inside the display")
        return application.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    // SF-0402-001 through SF-0402-008, SF-0407-001 through SF-0407-006
    // The virtual canvas accessibility object and the selected render object
    // are both derived from the adopted render plan. This fresh-process
    // journey retains one settled application-window image for every
    // supported authored kind, so enclosure by the editor-only outline is a
    // visual contract rather than an object-count-only assertion.
    @MainActor
    // SF-0806-002/005/006, SF-1102-002/005/006: visible native controls,
    // canonical history and a separate-process package reopen.
    func testStaticPageManagementRoutesHistoryAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("static-pages.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"),
            windowAlignment: leadingEdgeAlignmentOnNarrowDisplay)
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application,
            permitsLeadingEdgeConstrainedPlacementOnNarrowDisplay: leadingEdgeAlignmentOnNarrowDisplay != nil)
        // Preserve real pointer coverage on a display narrower than the
        // product minimum. Drag the native title bar to reveal the region;
        // never change product sizing or synthesize a command/model shortcut.
        @MainActor func reveal(_ query: @autoclosure @escaping () -> XCUIElement) {
            guard let visible = NSScreen.main?.visibleFrame else { return }
            guard XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                application.state == .runningForeground && query().isEnabled
            }, object: application)], timeout: 3) == .completed else {
                XCTFail("The app must be active and the live pointer control enabled: \(application.debugDescription)")
                return
            }
            // A control already inside the display is valid. The constrained
            // window inset is not an additional per-control clipping margin.
            let safe = visible
            for _ in 0..<2 {
                let live = query()
                let delta = PointerWindowPlacement.horizontalTranslation(
                    window: application.windows.firstMatch.frame, target: live.frame, visible: safe
                )
                guard delta != 0 else { break }
                // Use the native title-bar interior, not the upper resize
                // edge. X coordinates agree between AppKit and XCTest.
                PointerWindowPlacement.moveWindowHorizontally(by: delta, in: application)
            }
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let element = query()
                return element.isHittable && element.frame.minX >= safe.minX - 1 && element.frame.maxX <= safe.maxX + 1
            }, object: application)], timeout: 3) == .completed,
                "The real control must be fully inside the usable display: \(query().debugDescription)")
        }
        @MainActor func clickButton(_ identifier: String) {
            reveal(application.buttons[identifier])
            application.buttons[identifier].click()
        }
        @MainActor func pageRow(_ name: String) -> XCUIElement {
            application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "navigator.page.", name + ", route ")).firstMatch
        }
        @MainActor func menu(_ title: String) {
            application.menuBars.menuBarItems["Page"].click()
            XCTAssertTrue(application.menuItems[title].isEnabled)
            application.menuItems[title].click()
        }
        @MainActor func draft(_ id: String, _ value: String) {
            let field = application.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 3))
            reveal(application.textFields[id])
            let liveField = application.textFields[id]
            replaceText(in: liveField, with: value, application: application)
        }
        clickButton("navigator.tab.pages")
        clickButton("navigator.pages.new")
        draft("page.editor.name", "About")
        draft("page.editor.route", "/about")
        clickButton("page.editor.apply")
        XCTAssertTrue(pageRow("About").waitForExistence(timeout: 3))
        let stableID = pageRow("About").identifier
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-021 new empty page")
        menu("Rename Page…")
        draft("page.editor.name", "Team")
        clickButton("page.editor.apply")
        XCTAssertTrue(pageRow("Team").waitForExistence(timeout: 3))
        XCTAssertEqual(pageRow("Team").identifier, stableID)
        menu("Edit Route…")
        draft("page.editor.route", "/404")
        clickButton("page.editor.apply")
        XCTAssertTrue(application.staticTexts["page.editor.validation"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-021 invalid protected route")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(pageRow("Team").label, "Team, route /about")
        menu("Edit Route…")
        draft("page.editor.route", "/team")
        clickButton("page.editor.apply")
        XCTAssertEqual(pageRow("Team").label, "Team, route /team")
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Frame at Center"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let frameID = canvasObject(named: "Frame", in: application).identifier
        menu("Duplicate Page")
        XCTAssertTrue(pageRow("Team Copy").waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertNotEqual(canvasObject(named: "Frame", in: application).identifier, frameID)
        menu("Move Page Earlier")
        attachWindowScreenshot(application, named: "SF-AUTHORING-021 duplicate reordered")
        menu("Delete Page…")
        attachWindowScreenshot(application, named: "SF-AUTHORING-021 delete impact")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(pageRow("Team Copy").exists)
        menu("Delete Page…")
        clickButton("page.editor.apply")
        XCTAssertTrue(pageRow("Team Copy").waitForNonExistence(timeout: 3))
        clickButton("toolbar.undo")
        XCTAssertTrue(pageRow("Team Copy").waitForExistence(timeout: 3))
        clickButton("toolbar.redo")
        XCTAssertTrue(pageRow("Team Copy").waitForNonExistence(timeout: 3))
        reveal(pageRow("Team"))
        pageRow("Team").click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, frameID)
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("pages-reopen-recovery"),
            windowAlignment: leadingEdgeAlignmentOnNarrowDisplay)
        XCTAssertTrue(waitForWorkspaceReady(application))
        clickButton("navigator.tab.pages")
        XCTAssertTrue(pageRow("Team").waitForExistence(timeout: 3))
        XCTAssertEqual(pageRow("Team").identifier, stableID)
        XCTAssertEqual(pageRow("Team").label, "Team, route /team")
        pageRow("Team").click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, frameID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-021 reopened page")
    }

    func testStaticPageCompactProtectedRolesAndLiveLinkTargetJourney() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWindowSize", "minimum", "-SiteForgeUITestWindowAlignment", TestWindowAlignment.right.rawValue,
        ])
        XCTAssertEqual(application.descendants(matching: .any)["workspace.shell"].frame.width, 1_100, accuracy: 2)
        application.menuBars.menuBarItems["Page"].click()
        XCTAssertFalse(application.menuItems["Delete Page…"].isEnabled)
        XCTAssertFalse(application.menuItems["Edit Route…"].isEnabled)
        application.typeKey(.escape, modifierFlags: [])
        application.typeKey("n", modifierFlags: [.command, .shift])
        let name = application.textFields["page.editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        replaceText(in: name, with: "Contact", application: application)
        let route = application.textFields["page.editor.route"]
        replaceText(in: route, with: "/contact", application: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-021 compact page fields")
        application.buttons["page.editor.apply"].click()
        let home = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.page.", "Home, route /")).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 3)); home.click()
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Button at Center"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.buttons["inspector.tab.interactions"].click()
        application.popUpButtons["inspector.interactions.link.type"].click()
        application.menuItems["Page"].click()
        let target = application.popUpButtons["inspector.interactions.link.page"]
        revealStructuralLayoutControl(target, in: application)
        target.click()
        XCTAssertTrue(application.menuItems["Contact — /contact"].exists)
        application.menuItems["Contact — /contact"].click()
        XCTAssertTrue(waitForValue(target, containing: "Contact"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-021 compact live page target")
    }

    func testButtonLinkContentTargetsUndoRedoAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("button-link.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.button"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let buttonID = canvasObject(named: "Button", in: application).identifier
        XCTAssertTrue(canvasObject(named: "Button", in: application).isSelected)
        application.buttons["inspector.tab.content"].click()
        replaceStructuralLayoutField(application.textFields["inspector.content.control.label"], with: "Read guide", in: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 button label")
        let controlStatus = application.descendants(matching: .any)["inspector.control.status"].firstMatch
        XCTAssertTrue(waitForValue(controlStatus, containing: "label committed"), "Status: \(controlStatus.label) / \(String(describing: controlStatus.value)); field: \(String(describing: application.textFields["inspector.content.control.label"].value))")
        application.buttons["inspector.tab.interactions"].click()
        application.popUpButtons["inspector.interactions.link.type"].click()
        application.menuItems["External HTTP(S)"].click()
        replaceStructuralLayoutField(application.textFields["inspector.interactions.link.url"], with: "https://example.com/guide", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.control.status"], containing: "target committed"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 external target")
        replaceStructuralLayoutField(application.textFields["inspector.interactions.link.url"], with: "javascript:invalid", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.control.status"], containing: "HTTP or HTTPS"))
        application.textFields["inspector.interactions.link.url"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.interactions.link.url"], containing: "https://example.com/guide"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 invalid cancelled")
        application.buttons["toolbar.undo"].click()
        XCTAssertTrue(application.popUpButtons["inspector.interactions.link.type"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(application.popUpButtons["inspector.interactions.link.type"], containing: "No target"))
        application.buttons["toolbar.redo"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.interactions.link.url"], containing: "https://example.com/guide"))
        XCTAssertEqual(canvasObject(named: "Button", in: application).identifier, buttonID)
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Link at Center"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertTrue(canvasObject(named: "Link", in: application).isSelected)
        // Center insertion intentionally shares a location. Author a distinct
        // position through Layout so both labels can be visually inspected.
        application.buttons["inspector.tab.layout"].click()
        replaceStructuralLayoutField(application.textFields["inspector.layout.x"], with: "200", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.layout.y"], with: "200", in: application)
        application.buttons["inspector.tab.content"].click()
        replaceStructuralLayoutField(application.textFields["inspector.content.control.label"], with: "More details", in: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 link selected")
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("control-reopen-recovery"))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        application.buttons["navigator.tab.layers"].click()
        let row = application.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Button")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3)); row.click()
        XCTAssertEqual(canvasObject(named: "Button", in: application).identifier, buttonID)
        application.buttons["inspector.tab.content"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.content.control.label"], containing: "Read guide"))
        application.buttons["inspector.tab.interactions"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.interactions.link.url"], containing: "https://example.com/guide"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 reopened")
    }

    // SF-0806-002/005, SF-1102-002: real additive selection and atomic
    // applicable-subset editing, with no primary-value borrowing.
    func testButtonLinkMixedAndIncompatibleContentJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        for (index, kind) in ["Button", "Link", "Text"].enumerated() {
            application.menuBars.menuBarItems["Insert"].click()
            application.menuItems["Insert \(kind) at Center"].click()
            XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects \(index + 1)", timeout: 5))
            application.buttons["inspector.tab.layout"].click()
            replaceStructuralLayoutField(application.textFields["inspector.layout.x"], with: String(200 + index * 300), in: application)
            replaceStructuralLayoutField(application.textFields["inspector.layout.y"], with: "200", in: application)
        }
        application.buttons["navigator.tab.layers"].click()
        @MainActor func row(_ name: String) -> XCUIElement {
            application.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", name
            )).firstMatch
        }
        row("Button").click()
        XCUIElement.perform(withKeyModifiers: .shift) { row("Link").click() }
        let selection = application.descendants(matching: .any)["status.selectionPath"]
        XCTAssertTrue(waitForValue(selection, containing: "2 selected"))
        XCTAssertTrue(row("Button").isSelected); XCTAssertTrue(row("Link").isSelected)
        application.buttons["inspector.tab.content"].click()
        XCTAssertEqual(application.textFields["inspector.content.control.label"].placeholderValue, "Mixed labels")
        replaceStructuralLayoutField(application.textFields["inspector.content.control.label"], with: "Shared label", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.control.status"], containing: "2 object(s)"))
        XCTAssertTrue(row("Button").isSelected); XCTAssertTrue(row("Link").isSelected)
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 compatible mixed labels")
        application.buttons["toolbar.undo"].click()
        XCTAssertEqual(application.textFields["inspector.content.control.label"].placeholderValue, "Mixed labels")
        application.buttons["toolbar.redo"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.content.control.label"], containing: "Shared label"))
        row("Button").click()
        XCUIElement.perform(withKeyModifiers: .shift) { row("Text").click() }
        XCTAssertTrue(waitForValue(selection, containing: "2 selected"))
        replaceStructuralLayoutField(application.textFields["inspector.content.control.label"], with: "Applicable only", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.control.status"], containing: "skipped 1 incompatible"))
        XCTAssertTrue(row("Button").isSelected); XCTAssertTrue(row("Text").isSelected)
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 partial selection")
        row("Text").click()
        XCTAssertTrue(application.descendants(matching: .any)["inspector.content.unavailable"].waitForExistence(timeout: 3))
        XCTAssertFalse(application.textFields["inspector.content.control.label"].exists)
        XCTAssertTrue(waitForValue(selection, containing: "1 selected"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 incompatible selection")
    }

    func testButtonLinkInternalTargetControlsAtPracticalMinimum() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWindowSize", "minimum",
            "-SiteForgeUITestWindowAlignment", TestWindowAlignment.right.rawValue,
        ])
        XCTAssertEqual(application.descendants(matching: .any)["workspace.shell"].frame.width, 1_100, accuracy: 2)
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Button at Center"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        // At the practical minimum the native strip may overflow. Use its
        // visible production menu rather than asking XCTest to scroll a
        // clipped 25-point strip whose hit point may be outside the display.
        revealComponentPointerTarget("inspector.tab.overflow", in: application).click()
        application.menuItems["Content"].click()
        replaceStructuralLayoutField(application.textFields["inspector.content.control.label"], with: "Open page", in: application)
        revealComponentPointerTarget("inspector.tab.overflow", in: application).click()
        application.menuItems["Interactions"].click()
        application.popUpButtons["inspector.interactions.link.type"].click()
        application.menuItems["Page"].click()
        let page = application.popUpButtons["inspector.interactions.link.page"]
        XCTAssertTrue(waitForHittable(page, in: application)); page.click()
        application.menuItems["Home — /"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.control.status"], containing: "target committed"))
        let context = application.popUpButtons["inspector.interactions.link.context"]
        XCTAssertTrue(waitForHittable(context, in: application)); context.click()
        application.menuItems["New context"].click()
        XCTAssertTrue(waitForValue(context, containing: "New context"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 compact internal page target")
        let remove = application.buttons["inspector.interactions.link.remove"]
        revealStructuralLayoutControl(remove, in: application)
        remove.click()
        XCTAssertTrue(waitForValue(application.popUpButtons["inspector.interactions.link.type"], containing: "No target"))
        application.buttons["toolbar.undo"].click()
        XCTAssertTrue(waitForValue(application.popUpButtons["inspector.interactions.link.page"], containing: "Home"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 compact restored target")
    }

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

    // SF-0502-001...006/008; SF-0503-001...006/008; SF-0506-001...006/008
    @MainActor
    func testStructuralLayoutInspectorReflowsSectionStackAndGridJourney() throws {
        let fixture = legacyFixtureURL(named: "schema-v1-empty")
        let project = fixtureRoot.appendingPathComponent("structural-layout-native-save.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: fixture)
        XCTAssertTrue(waitForWorkspaceReady(application))
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0", timeout: 5))

        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.section"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        insertStructuralFrame(in: application, expectedCount: 2)
        selectStructuralLayer("Section", in: application)
        application.buttons["inspector.tab.layout"].click()
        let padding = application.textFields["inspector.layout.container.padding"]
        XCTAssertTrue(padding.waitForExistence(timeout: 3))
        XCTAssertTrue((padding.value as? String)?.contains("48") == true)
        let sectionChildBefore = canvasObject(named: "Frame", in: application).frame
        replaceStructuralLayoutField(padding, with: "72", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.layout.container.announcement"], containing: "Padding committed", timeout: 3))
        let sectionChildAfter = canvasObject(named: "Frame", in: application).frame
        XCTAssertGreaterThan(sectionChildAfter.minX, sectionChildBefore.minX)
        XCTAssertGreaterThan(sectionChildAfter.minY, sectionChildBefore.minY)
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 section padding")
        padding.click(); padding.typeKey("a", modifierFlags: .command)
        padding.typeText("invalid"); padding.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["inspector.layout.container.validation"]
            .waitForExistence(timeout: 3))
        padding.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.padding"], containing: "72"))

        selectStructuralLayer("Section", in: application)
        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.stack"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        insertStructuralFrame(in: application, expectedCount: 4)
        selectStructuralLayer("Stack", in: application)
        insertStructuralFrame(in: application, expectedCount: 5)
        selectStructuralLayer("Stack", in: application)
        application.buttons["inspector.tab.layout"].click()
        let axis = application.descendants(matching: .any)["inspector.layout.container.axis"]
        revealStructuralLayoutControl(axis, in: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 stack vertical default")
        clickStructuralLayoutRadioButton(
            "Horizontal",
            groupIdentifier: "inspector.layout.container.axis",
            in: application
        )
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.announcement",
            containing: "Direction committed",
            timeout: 3
        ))
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 stack horizontal")
        let gap = application.textFields["inspector.layout.container.gap"]
        replaceStructuralLayoutField(gap, with: "36", in: application)
        // The radio-group container need not itself be a pointer target.
        // Reveal and validate the actual native Center segment below.
        clickStructuralLayoutRadioButton(
            "Center",
            groupIdentifier: "inspector.layout.container.alignment",
            in: application
        )
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.announcement",
            containing: "Alignment committed",
            timeout: 3
        ))
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.alignment",
            containing: "center"
        ))
        let alignmentLabel = application.staticTexts[
            "inspector.layout.container.alignment.label"
        ]
        XCTAssertTrue(alignmentLabel.exists)
        XCTAssertGreaterThan(alignmentLabel.frame.width, 40)
        XCTAssertLessThanOrEqual(alignmentLabel.frame.height, 24,
            "Alignment must remain a readable single-line Inspector label")
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 stack gap alignment")

        selectStructuralLayer("Section", in: application)
        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.grid"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 6", timeout: 5))
        insertStructuralFrame(in: application, expectedCount: 7)
        selectStructuralLayer("Grid", in: application)
        insertStructuralFrame(in: application, expectedCount: 8)
        selectStructuralLayer("Grid", in: application)
        insertStructuralFrame(in: application, expectedCount: 9)
        selectStructuralLayer("Grid", in: application)
        application.buttons["inspector.tab.layout"].click()
        let columns = application.textFields["inspector.layout.container.columns"]
        XCTAssertTrue(columns.waitForExistence(timeout: 3))
        revealStructuralLayoutControl(columns, in: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 grid two columns sparse row")
        replaceStructuralLayoutField(columns, with: "3", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.layout.container.announcement"], containing: "Columns committed", timeout: 3))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 9", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 grid three columns")

        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.columns"], containing: "2", timeout: 3))
        XCTAssertTrue(application.buttons["toolbar.redo"].isEnabled)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.columns"], containing: "3", timeout: 3))
        let reset = revealStructuralLayoutControl(
            application.buttons["inspector.layout.container.columns.reset"],
            in: application
        )
        XCTAssertTrue(reset.isEnabled); reset.click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.columns"], containing: "2", timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 grid reset default")

        application.menuBars.menuBarItems["File"].click()
        let save = application.menuItems["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 3)); XCTAssertTrue(save.isEnabled); save.click()
        XCTAssertTrue(waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 5))
        terminateAndWait(application)

        let reopenRecoveryDirectory = fixtureRoot.appendingPathComponent("structural-layout-reopen-recovery", isDirectory: true)
        application = launchExistingIntegrationProject(project, recoveryDirectory: reopenRecoveryDirectory)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 9", timeout: 5))
        selectStructuralLayer("Section", in: application)
        application.buttons["inspector.tab.layout"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.padding"], containing: "72"))
        selectStructuralLayer("Stack", in: application)
        application.buttons["inspector.tab.layout"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.layout.container.axis"], containing: "horizontal"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.gap"], containing: "36"))
        selectStructuralLayer("Grid", in: application)
        application.buttons["inspector.tab.layout"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.columns"], containing: "2"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 save reopen")
    }

    // SF-0502-006, SF-0503-006, SF-0506-006
    @MainActor
    func testStructuralLayoutControlsRemainReachableAtPracticalMinimum() throws {
        let application = launchWorkspace(windowAlignment: .right)
        application.buttons["navigator.tab.elements"].click()
        application.buttons["navigator.elements.stack"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.buttons["inspector.tab.layout"].click()

        let scroll = application.descendants(matching: .any)["inspector.selection.scroll"]
        let identifiers = [
            "inspector.layout.container.padding",
            "inspector.layout.container.gap",
            "inspector.layout.container.axis",
            "inspector.layout.container.alignment",
            "inspector.layout.visibility",
        ]
        for identifier in identifiers {
            let control = application.descendants(matching: .any)[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 3), "Missing compact control \(identifier)")
            for _ in 0..<6 where !control.isHittable {
                scroll.scroll(byDeltaX: 0, deltaY: -220)
            }
            XCTAssertTrue(control.isHittable, "Compact control \(identifier) must be reachable")
        }
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 practical minimum inspector")
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 practical minimum responsive inspector")
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
        // SF-AUTHORING-020 enables Content/Interactions for Button/Link.
        // An empty selection remains unavailable without falsely claiming
        // that the entire feature is not implemented.
        let contentUnavailable = application.descendants(matching: .any)["inspector.empty"]
        XCTAssertTrue(contentUnavailable.waitForExistence(timeout: 5))
        XCTAssertTrue(contentUnavailable.label.localizedCaseInsensitiveContains("Nothing Selected"))
        XCTAssertTrue(contentUnavailable.label.localizedCaseInsensitiveContains("content"))
        XCTAssertFalse(application.textFields["inspector.content.control.label"].exists)
        XCTAssertTrue(application.descendants(matching: .button)["inspector.transform.moveRight"].exists == false)
        attachScreenshot(named: "SF-PRODUCT-UI-003 inspector content unavailable")

        XCTAssertTrue(waitForHittable(interactions, in: application))
        XCTAssertEqual(interactions.label, "Interactions")
        interactions.click()
        let interactionsUnavailable = application.descendants(matching: .any)["inspector.empty"]
        XCTAssertTrue(interactionsUnavailable.waitForExistence(timeout: 5))
        XCTAssertTrue(interactionsUnavailable.label.localizedCaseInsensitiveContains("Nothing Selected"))
        XCTAssertTrue(interactionsUnavailable.label.localizedCaseInsensitiveContains("interactions"))
        XCTAssertFalse(application.popUpButtons["inspector.interactions.link.type"].exists)
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

    // SF-0205-002/003/004/006 — native, noncanonical Pages search.
    func testPagesSearchFiltersRoutesOpensFirstAndPreservesSelectionJourney() throws {
        let application = launchWorkspace()
        let search = application.textFields["navigator.pages.search"]
        XCTAssertTrue(waitForHittable(search, in: application))
        let home = pageRow(named: "Home", in: application)
        let missing = pageRow(named: "Not Found", in: application)
        XCTAssertTrue(home.exists && missing.exists)
        search.click(); search.typeText("/404")
        XCTAssertFalse(home.exists)
        XCTAssertTrue(missing.exists)
        XCTAssertTrue(waitForValue(application.staticTexts["navigator.pages.search.status"], containing: "1 of 2"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-066 Pages route search")
        search.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertEqual(missing.value as? String, "Not Found page; Selected")
        search.click(); search.typeKey("a", modifierFlags: .command); search.typeText("no matching page")
        XCTAssertTrue(application.descendants(matching: .any)["navigator.pages.search.empty"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.buttons["navigator.pages.search.showSelected"].exists)
        XCTAssertFalse(missing.exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-066 Pages empty search")
        application.buttons["navigator.pages.search.showSelected"].click()
        XCTAssertTrue(missing.waitForExistence(timeout: 3))
        XCTAssertEqual(missing.value as? String, "Not Found page; Selected")
        search.click(); search.typeText("home")
        XCTAssertTrue(home.waitForExistence(timeout: 3))
        application.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(home.exists && missing.exists)
        XCTAssertEqual(missing.value as? String, "Not Found page; Selected")
        attachWindowScreenshot(application, named: "SF-AUTHORING-066 Pages search cleared")
    }

    // SF-0205-002/003/004/006 — catalogue search preserves supported
    // insertion rows and their transactional behavior.
    func testElementsSearchFindsAndInsertsSupportedItemWithoutEnablingUnavailableJourney() throws {
        let application = launchWorkspace()
        application.buttons["navigator.tab.elements"].click()
        let search = application.textFields["navigator.elements.search"]
        XCTAssertTrue(waitForHittable(search, in: application))
        search.click(); search.typeText("stack")
        XCTAssertTrue(application.buttons["navigator.elements.stack"].waitForExistence(timeout: 3))
        XCTAssertFalse(application.buttons["navigator.elements.section"].exists)
        XCTAssertTrue(waitForValue(application.staticTexts["navigator.elements.search.status"], containing: "1 of 20"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-068 Elements filtered")
        application.buttons["navigator.elements.stack"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        replaceText(in: search, with: "navigation", application: application)
        let navigation = application.buttons["navigator.elements.navbar"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 3))
        XCTAssertTrue(navigation.isEnabled)
        navigation.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-068 Elements supported navigation")
        replaceText(in: search, with: "no matching element", application: application)
        XCTAssertTrue(application.descendants(matching: .any)["navigator.elements.search.empty"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-068 Elements empty")
        application.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(application.buttons["navigator.elements.section"].exists)
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
            let button = application.buttons["toolbar.tool.\(tool)"]
            XCTAssertTrue(button.exists, tool)
            XCTAssertTrue(button.isHittable, tool)
        }
        let moreTools = application.menuButtons["toolbar.moreTools"]
        XCTAssertTrue(moreTools.exists)
        XCTAssertTrue(moreTools.isHittable)

        XCTAssertEqual(application.buttons["toolbar.tool.select"].value as? String, "Selected")
        XCTAssertFalse(application.buttons["toolbar.undo"].isEnabled)
        XCTAssertFalse(application.buttons["toolbar.redo"].isEnabled)

        application.buttons["toolbar.tool.frame"].click()
        XCTAssertTrue(application.staticTexts["Tool: Frame"].waitForExistence(timeout: 2))

        application.typeKey("t", modifierFlags: [])
        XCTAssertTrue(application.staticTexts["Tool: Text"].waitForExistence(timeout: 2))

        moreTools.click()
        let section = application.menuItems["toolbar.moreTool.section"]
        XCTAssertTrue(section.waitForExistence(timeout: 2))
        section.click()
        XCTAssertTrue(application.staticTexts["Tool: Section"].waitForExistence(timeout: 2))
        XCTAssertTrue((moreTools.value as? String)?.contains("Section") == true)

        let preview = application.buttons["toolbar.preview"]
        XCTAssertTrue(preview.exists)
        XCTAssertTrue(preview.isEnabled)
        XCTAssertEqual(preview.label, "Preview")
        application.typeKey("p", modifierFlags: [.command, .shift])
        XCTAssertTrue(application.descendants(matching: .any)["preview.local"].waitForExistence(timeout: 2))
        XCTAssertTrue(application.descendants(matching: .any)["preview.status"].exists)
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(application.descendants(matching: .any)["preview.local"].waitForExistence(timeout: 1))
        XCTAssertTrue(hasKeyboardFocus(application.buttons["navigator.tab.pages"]))
    }

    // SF-0201-006, SF-0201-008, SF-0203-006, SF-1902-008
    @MainActor
    func testPreviewPointerUsesRightAlignedTestWindow() throws {
        let application = launchWorkspace(windowAlignment: .right)
        let preview = application.buttons["toolbar.preview"]

        XCTAssertTrue(waitForHittable(preview, in: application))
        preview.click()
        XCTAssertTrue(application.descendants(matching: .any)["preview.local"].waitForExistence(timeout: 2))
    }

    // SF-1201-001/002/003/004/006, SF-1202-001/003/006 — Preview owns a
    // deliberate immutable authored snapshot and contains no editor canvas.
    @MainActor
    func testLocalPreviewRefreshesOnlyOnExplicitRequestJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"]
        application.buttons["toolbar.tool.frame"].click()
        XCTAssertTrue(waitForHittable(canvas, in: application))
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.52, dy: 0.48)).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.buttons["toolbar.preview"].click()
        XCTAssertTrue(application.descendants(matching: .any)["preview.local"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.descendants(matching: .any)["preview.canvas"].exists)
        XCTAssertTrue(application.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Previewing Home")
        ).firstMatch.waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-025 local preview authored snapshot")
        application.buttons["preview.refresh"].click()
        XCTAssertTrue(application.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "already shows the current revision")
        ).firstMatch.waitForExistence(timeout: 3))
        application.buttons["preview.done"].click()
        XCTAssertTrue(hasKeyboardFocus(application.buttons["navigator.tab.pages"]))
    }

    // SF-1102-002/003/004/006, SF-1201-001/002/003/004/006 — committed
    // stable PageID navigation operates inside isolated Preview history and
    // never changes the editor's active page or selection.
    @MainActor
    func testLocalPreviewFollowsAuthoredPageLinkWithBackForwardAndNoEditorMutation() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        application.typeKey("n", modifierFlags: [.command, .shift])
        let name = application.textFields["page.editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        replaceText(in: name, with: "Contact", application: application)
        let route = application.textFields["page.editor.route"]
        replaceText(in: route, with: "/contact", application: application)
        application.buttons["page.editor.apply"].click()
        let home = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.page.", "Home, route /"
        )).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 3)); home.click()
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Link at Center"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let stableLinkID = canvasObject(named: "Link", in: application).identifier
        application.buttons["inspector.tab.interactions"].click()
        application.popUpButtons["inspector.interactions.link.type"].click()
        application.menuItems["Page"].click()
        let pageTarget = revealStructuralLayoutControl(
            application.popUpButtons["inspector.interactions.link.page"], in: application
        )
        pageTarget.click()
        let contact = application.menuItems["Contact — /contact"]
        XCTAssertTrue(contact.waitForExistence(timeout: 3))
        contact.click()
        XCTAssertTrue(waitForValue(pageTarget, containing: "Contact"))

        application.buttons["toolbar.preview"].click()
        let previewPage = application.menuButtons["preview.page"]
        XCTAssertTrue(previewPage.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForValue(previewPage, containing: "Home"))
        let link = application.buttons["Link"]
        XCTAssertTrue(link.waitForExistence(timeout: 5)); XCTAssertTrue(link.isEnabled); link.click()
        XCTAssertTrue(waitForValue(previewPage, containing: "Contact"))
        XCTAssertTrue(application.buttons["preview.back"].isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-103 preview internal navigation")
        application.buttons["preview.back"].click()
        XCTAssertTrue(waitForValue(previewPage, containing: "Home"))
        XCTAssertTrue(application.buttons["preview.forward"].isEnabled)
        application.buttons["preview.done"].click()
        XCTAssertEqual(canvasObject(named: "Link", in: application).identifier, stableLinkID)
        XCTAssertTrue(home.isSelected)
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
        replaceText(in: editor, with: "Pointer commit", application: application)

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
        replaceText(in: editor, with: "Pointer cancel", application: application)
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
        // Keep the constrained right edge required by this pointer journey,
        // while placing its toolbar below transient system top-edge surfaces.
        let application = launchWorkspace(windowAlignment: .right, verticalAlignment: .bottom)
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
        let application = launchWorkspace(windowAlignment: leadingEdgeAlignmentOnNarrowDisplay)
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
        XCTAssertTrue(waitForKeyboardFocus(application.textFields["navigator.pages.search"], in: application))
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
            application.textFields["navigator.pages.search"],
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
    // SF-0401/0405/0407: native pointer screen coordinates are the independent
    // oracle; painted blue pixels must occur there, not at a reflected rect.
    func testNativePointerPreviewAndFrameTextCommitFollowScreenCoordinates() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        for mode in ["fitted", "actual", "panned-zoomed"] {
            if mode == "actual" { componentMenu("View", "Actual Size", in: application) }
            if mode == "panned-zoomed" {
                componentMenu("View", "Zoom Out", in: application)
                componentMenu("View", "Pan Down", in: application)
                componentMenu("View", "Pan Right", in: application)
            }
            let viewportValue = try XCTUnwrap(canvas.value as? String)
            let zoom = try XCTUnwrap(Double(viewportValue.split(separator: " ")[1])) / 100
            for kind in ["Frame", "Text"] {
                componentMenu("Insert", kind, in: application)
                XCTAssertTrue(application.descendants(matching: .any)["canvas.empty.state"].waitForNonExistence(timeout: 3))
                let size = CGSize(width: (kind == "Frame" ? 240 : 120) * zoom,
                                  height: (kind == "Frame" ? 160 : 24) * zoom)
                let current = try XCTUnwrap(canvas.value as? String)
                let origin = current.components(separatedBy: "origin ")[1].components(separatedBy: ";")[0]
                    .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                XCTAssertEqual(origin.count, 2)
                // Plan genuine pointer positions inside this blank Desktop
                // artboard (1440 x 900), not pasteboard. On a narrow display
                // the correctly clipped AX frame is not the full object rect.
                // The assertions below still use independent mouse positions
                // and painted pixels, never renderer-derived expected bounds.
                let points = nativePointerSamplePoints(canvasSize: canvas.frame.size,
                    artboard: CGRect(x: -origin[0] * zoom, y: -origin[1] * zoom,
                                     width: 1440 * zoom, height: 900 * zoom), objectSize: size)
                XCTAssertEqual(points.count, 6, "The visible artboard must fit the entire test object.")
                for point in points {
                    canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).hover()
                    XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.insertion"], containing: "Previewing"))
                    try assertPointerChromePixels(canvas: canvas, localRect: CGRect(origin: point, size: size))
                }
                attachWindowScreenshot(application, named: "SF-POINTER \(mode) \(kind) preview")
                let point = try XCTUnwrap(points.last)
                canvas.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).click()
                XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
                application.typeKey(.escape, modifierFlags: [])
                let object = canvasObject(named: kind == "Text" ? "Text object" : kind, in: application)
                XCTAssertTrue(object.waitForExistence(timeout: 3))
                XCTAssertEqual(object.frame.minX, canvas.frame.minX + point.x, accuracy: 2)
                XCTAssertEqual(object.frame.minY, canvas.frame.minY + point.y, accuracy: 2)
                XCTAssertEqual(object.frame.width, size.width, accuracy: 2)
                XCTAssertEqual(object.frame.height, size.height, accuracy: 2)
                try assertPointerChromePixels(canvas: canvas, localRect: CGRect(origin: point, size: size))
                attachWindowScreenshot(application, named: "SF-POINTER \(mode) \(kind) committed")
                componentMenu("Edit", "Undo", in: application)
                XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
            }
        }
    }

    @MainActor
    func testNativePointerSamplesStayInsideVisibleArtboardAtNarrowWidths() {
        for width in [500.0, 1044.0] {
            for zoom in [0.28, 0.66, 0.8, 1.0] {
                let canvas = CGSize(width: width, height: 618)
                // Hosted 100% artboard starts 128 points into the viewport;
                // include a negative origin to cover a panned artboard too.
                for origin in [CGPoint(x: 128, y: 108), CGPoint(x: -90, y: -60)] {
                    let artboard = CGRect(origin: origin, size: CGSize(width: 1440 * zoom, height: 900 * zoom))
                    let visible = CGRect(origin: .zero, size: canvas).intersection(artboard)
                    for size in [CGSize(width: 240 * zoom, height: 160 * zoom),
                                 CGSize(width: 120 * zoom, height: 24 * zoom)] {
                        let points = nativePointerSamplePoints(canvasSize: canvas, artboard: artboard, objectSize: size)
                        XCTAssertEqual(points.count, 6)
                        for point in points { XCTAssertTrue(visible.contains(CGRect(origin: point, size: size))) }
                        guard points.count == 6 else { continue }
                        XCTAssertGreaterThan(points[1].x, points[0].x)
                        XCTAssertGreaterThan(points[2].y, points[1].y)
                        XCTAssertLessThan(points[3].x, points[2].x)
                        XCTAssertLessThan(points[4].y, points[3].y)
                    }
                }
            }
        }
    }

    private func nativePointerSamplePoints(canvasSize: CGSize, artboard: CGRect, objectSize: CGSize) -> [CGPoint] {
        let visible = CGRect(origin: .zero, size: canvasSize).intersection(artboard).insetBy(dx: 8, dy: 8)
        guard visible.width > objectSize.width, visible.height > objectSize.height else { return [] }
        let left = visible.minX, right = visible.maxX - objectSize.width
        let top = visible.minY, bottom = visible.maxY - objectSize.height
        let center = CGPoint(x: (left + right) / 2, y: (top + bottom) / 2)
        let dx = min(100, (right - left) / 2), dy = min(100, (bottom - top) / 2)
        return [center, .init(x: center.x + dx, y: center.y),
                .init(x: center.x + dx, y: center.y + dy),
                .init(x: center.x - dx, y: center.y + dy),
                .init(x: center.x - dx, y: center.y - dy), .init(x: left, y: top)]
    }

    private func assertPointerChromePixels(canvas: XCUIElement, localRect: CGRect,
                                          file: StaticString = #filePath, line: UInt = #line) throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: canvas.screenshot().pngRepresentation))
        let scaleX = CGFloat(bitmap.pixelsWide) / canvas.frame.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / canvas.frame.height
        var edges = [0, 0, 0, 0]
        for y in max(0, Int((localRect.minY - 3) * scaleY))..<min(bitmap.pixelsHigh, Int((localRect.maxY + 3) * scaleY)) {
            for x in max(0, Int((localRect.minX - 3) * scaleX))..<min(bitmap.pixelsWide, Int((localRect.maxX + 3) * scaleX)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      color.blueComponent > 0.5, color.blueComponent > color.redComponent + 0.25 else { continue }
                let px = CGFloat(x) / scaleX, py = CGFloat(y) / scaleY
                if abs(px - localRect.minX) <= 3 { edges[0] += 1 }
                if abs(px - localRect.maxX) <= 3 { edges[1] += 1 }
                if abs(py - localRect.minY) <= 3 { edges[2] += 1 }
                if abs(py - localRect.maxY) <= 3 { edges[3] += 1 }
            }
        }
        XCTAssertTrue(edges.allSatisfy { $0 >= 4 }, "Painted preview/selection must enclose the actual pointer rect; edge pixels=\(edges), rect=\(localRect)", file: file, line: line)
    }

    func testWorldGridArtboardHierarchyVisualJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"))
        let grid = application.descendants(matching: .any)["canvas.grid.toggle"]
        XCTAssertTrue(waitForHittable(grid, in: application))
        // An application-local Canvas Settings default may start a new scene
        // with Grid off. This journey explicitly exercises the Grid-on state.
        if !(grid.isSelected || (grid.value as? NSNumber)?.intValue == 1 || (grid.value as? String)?.contains("On") == true) {
            grid.click()
        }
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
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.selectionPath"],
                                   containing: "1 selected; primary selection present; selection outside Mobile artboard"))
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
        XCTAssertEqual(newProject.label, "New Site")
        let brand = application.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS[c] %@", "SiteForge. Design durable websites")
        ).firstMatch
        XCTAssertTrue(brand.waitForExistence(timeout: 3))
        XCTAssertTrue(brand.label.contains("SiteForge"))
        for (identifier, label) in [
            ("launch.assurance.local", "Local projects"),
            ("launch.assurance.private", "Private by default"),
            ("launch.assurance.recovery", "Recovery protected")
        ] {
            let assurance = application.descendants(matching: .any)[identifier]
            XCTAssertTrue(assurance.exists, label)
            let semanticText = assurance.label + " " + String(describing: assurance.value ?? "")
            XCTAssertTrue(semanticText.contains(label), "Expected semantic assurance text: \(label)")
        }
        XCTAssertTrue(newProject.isHittable)
        XCTAssertTrue(openProject.isHittable)
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 2))
    }

    // SF-AUTHORING-105 / SF-0201-002/003/004/006,
    // SF-0204-002/003/004/006 — a successful user-authorized Open becomes a
    // path-free native launch choice and reopens through the same bookmark and
    // lifecycle pipeline after a fresh process.
    func testAuthorizedRecentProjectReopensFromWelcomeWithoutPersistingPathJourney() throws {
        let project = fixtureRoot.appendingPathComponent("Recent Client.siteforge")
        let fixture = legacyFixtureURL(named: "schema-v4-legacy-surface")
        let opened = launchIntegrationOpen(project, base64Fixture: fixture)
        XCTAssertTrue(waitForWorkspaceReady(opened, timeout: 8))
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent("recent-projects.json").path),
            "A successful authorized open must durably record path-free recency before the workspace is published."
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent("file-bookmarks.json").path),
            "A successful authorized open must durably record its test-isolated bookmark before the workspace is published."
        )
        let recentData = try Data(contentsOf: fixtureRoot.appendingPathComponent("recent-projects.json"))
        XCTAssertTrue(String(decoding: recentData, as: UTF8.self).contains("Recent Client"),
                      "The durable path-free recent record must preserve its display name.")
        terminateAndWait(opened)

        let application = launchScenario("welcome")
        let title = application.descendants(matching: .any)["launch.recentProjects.title"]
        if !title.waitForExistence(timeout: 3) {
            // A fresh process can briefly lose its AX subtree while the new
            // AppKit window becomes key after the prior process exits. Bring
            // that real window forward and query the replacement hierarchy.
            application.activate()
        }
        XCTAssertTrue(title.waitForExistence(timeout: 5), application.debugDescription)
        let recent = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "launch.recentProject.recent-"
        )).firstMatch
        XCTAssertTrue(recent.waitForExistence(timeout: 3))
        XCTAssertEqual(recent.label, "Open recent project Recent Client")
        XCTAssertFalse(application.debugDescription.contains(project.deletingLastPathComponent().path))
        attachWindowScreenshot(application, named: "SF-AUTHORING-105 authorized recent project")

        recent.click()
        XCTAssertTrue(waitForWorkspaceReady(application, timeout: 8))
        XCTAssertTrue(application.windows.firstMatch.title.contains("Recent Client"))
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

    /// A committed SwiftUI control may be replaced after publishing its
    /// binding. Re-query the live accessibility value so the assertion observes
    /// the current semantic state rather than a stale native proxy.
    private func waitForLiveValue(
        in application: XCUIApplication,
        identifier: String,
        containing text: String,
        timeout: TimeInterval = 2
    ) -> Bool {
        let expected = text.lowercased()
        let predicate = NSPredicate { [weak application] _, _ in
            guard let application else { return false }
            let element = application.descendants(matching: .any)[identifier].firstMatch
            guard element.exists else { return false }
            return String(describing: element.value ?? "")
                .lowercased()
                .contains(expected)
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: application)],
            timeout: timeout
        ) == .completed
    }

    private func waitForLiveSemanticText(
        in application: XCUIApplication,
        identifier: String,
        containing text: String,
        timeout: TimeInterval = 2
    ) -> Bool {
        let expected = text.lowercased()
        let predicate = NSPredicate { [weak application] _, _ in
            guard let application else { return false }
            let element = application.descendants(matching: .any)[identifier].firstMatch
            guard element.exists else { return false }
            let semanticText = [element.label, String(describing: element.value ?? "")]
                .joined(separator: " ")
                .lowercased()
            return semanticText.contains(expected)
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: application)],
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

    /// Keep structural-layout journey helpers as actor-isolated instance
    /// methods. Nested local functions capture the XCTestCase across an
    /// isolation boundary under Swift 6's x86_64 hosted compiler, even when
    /// both declarations spell `@MainActor`.
    private func selectStructuralLayer(_ name: String, in application: XCUIApplication) {
        application.buttons["navigator.tab.layers"].click()
        let row = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", name
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "Missing \(name) Layers row")
        row.click()
    }

    private func insertStructuralFrame(in application: XCUIApplication, expectedCount: Int) {
        application.menuBars.menuBarItems["Insert"].click()
        let insert = application.menuItems["Insert Frame at Center"]
        XCTAssertTrue(insert.waitForExistence(timeout: 2))
        insert.click()
        XCTAssertTrue(waitForLiveCanvasValue(
            in: application,
            containing: "rendered objects \(expectedCount)",
            timeout: 5
        ))
    }

    @discardableResult
    private func revealStructuralLayoutControl(
        _ element: XCUIElement,
        in application: XCUIApplication
    ) -> XCUIElement {
        let identifier = element.identifier
        let scroll = application.descendants(matching: .any)["inspector.selection.scroll"]
        var liveElement = liveStructuralLayoutControl(identifier, in: application)
        for _ in 0..<10 where !isSafelyVisibleForPointer(liveElement, inside: scroll) {
            let targetFrame = liveElement.frame
            let safeViewport = pointerSafeIntersection(for: scroll.frame)
            let deltaY: CGFloat = targetFrame.minY < safeViewport.minY + 8 ? 180 : -180
            scroll.scroll(byDeltaX: 0, deltaY: deltaY)
            // Undo/redo and reset can replace the SwiftUI control host. A
            // fresh, role-preserving AX query observes the live shipping
            // control rather than retaining an obsolete proxy or resolving
            // the non-hittable SwiftUI wrapper that shares its identifier.
            liveElement = liveStructuralLayoutControl(identifier, in: application)
        }
        XCTAssertTrue(
            isSafelyVisibleForPointer(liveElement, inside: scroll),
            "Inspector control \(identifier) must remain inside the usable display and reachable; control=\(liveElement.frame), scroll=\(scroll.frame), safe=\(pointerSafeIntersection(for: scroll.frame)), hittable=\(liveElement.isHittable)"
        )
        return liveElement
    }

    /// XCTest can report a control as hittable when an oversized product
    /// window extends beneath the Dock on a display narrower or shorter than
    /// the supported minimum. Pointer journeys must scroll the shipping
    /// control into the real AppKit usable screen before clicking it.
    private func isSafelyVisibleForPointer(
        _ element: XCUIElement,
        inside scroll: XCUIElement
    ) -> Bool {
        guard element.exists, element.isHittable else { return false }
        return pointerSafeIntersection(for: scroll.frame).contains(element.frame)
    }

    private func pointerSafeIntersection(for viewport: CGRect) -> CGRect {
        guard let screen = NSScreen.main else { return viewport.insetBy(dx: 0, dy: 8) }
        let visible = screen.visibleFrame
        // AppKit screen geometry is Y-up; XCTest screen geometry is Y-down.
        // This is the one conversion needed to compare a native visibleFrame
        // with an XCUIElement frame on the main display.
        let visibleInXCUI = CGRect(
            x: visible.minX,
            y: screen.frame.maxY - visible.maxY,
            width: visible.width,
            height: visible.height
        )
        return viewport.intersection(visibleInXCUI).insetBy(dx: 0, dy: 8)
    }

    private func liveStructuralLayoutControl(
        _ identifier: String,
        in application: XCUIApplication
    ) -> XCUIElement {
        if identifier.hasSuffix(".reset") {
            return application.buttons[identifier]
        }
        if ["inspector.layout.x", "inspector.layout.y", "inspector.layout.width", "inspector.layout.height"].contains(identifier)
            || ["inspector.content.control.label", "inspector.interactions.link.url"].contains(identifier)
            || ["inspector.design.borderWidth", "inspector.design.cornerRadius", "inspector.design.shadowValues"].contains(identifier)
            || identifier.hasSuffix(".padding")
            || identifier.hasSuffix(".gap")
            || identifier.hasSuffix(".columns") {
            return application.textFields[identifier]
        }
        let matches = application.descendants(matching: .any)
            .matching(identifier: identifier)
            .allElementsBoundByAccessibilityElement
        if let visible = matches.first(where: {
            let frame = $0.frame
            return $0.exists && $0.isHittable
                && frame.origin.x.isFinite && frame.origin.y.isFinite
                && frame.width.isFinite && frame.height.isFinite
                && !frame.isEmpty
        }) {
            return visible
        }
        return application.descendants(matching: .any)[identifier].firstMatch
    }

    /// Segmented SwiftUI pickers expose native radio buttons. Re-query the
    /// concrete segment after foreground adoption and scrolling so a retained
    /// group proxy cannot route the pointer after AppKit has yielded the app.
    private func clickStructuralLayoutRadioButton(
        _ label: String,
        groupIdentifier: String,
        in application: XCUIApplication
    ) {
        let scroll = application.descendants(matching: .any)["inspector.selection.scroll"]
        var group = liveStructuralLayoutControl(groupIdentifier, in: application)
        var button = group.radioButtons[label]

        for _ in 0..<10 where !isSafelyVisibleForPointer(button, inside: scroll) {
            let targetFrame = button.frame
            let safeViewport = pointerSafeIntersection(for: scroll.frame)
            let deltaY: CGFloat = targetFrame.minY < safeViewport.minY + 8 ? 180 : -180
            scroll.scroll(byDeltaX: 0, deltaY: deltaY)
            group = liveStructuralLayoutControl(groupIdentifier, in: application)
            button = group.radioButtons[label]
        }

        if application.state != .runningForeground {
            application.activate()
        }
        let safeViewport = pointerSafeIntersection(for: scroll.frame)
        let ready = NSPredicate { [weak application] _, _ in
            // Hosted macOS can expose AXEnabled=false on the Application and
            // Window containers even while the native window remains key/main
            // and its concrete control is enabled. Gate the genuine interaction
            // surface instead of inherited container metadata.
            guard let application,
                  application.state == .runningForeground,
                  application.sheets.count == 0,
                  application.dialogs.count == 0 else { return false }
            let window = application.windows.firstMatch
            let liveGroup = application.descendants(matching: .any)[groupIdentifier].firstMatch
            let liveButton = liveGroup.radioButtons[label]
            return window.exists
                && liveGroup.exists
                && liveGroup.isEnabled
                && liveButton.exists
                && liveButton.isEnabled
                && liveButton.isHittable
                && safeViewport.contains(liveButton.frame)
        }
        guard XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: ready, object: application)],
            timeout: 5
        ) == .completed else {
            attachPointerDiagnostics(control: button, application: application)
            XCTFail("Inspector segment \(groupIdentifier).\(label) did not become foreground, enabled, and safely visible")
            return
        }

        group = liveStructuralLayoutControl(groupIdentifier, in: application)
        button = group.radioButtons[label]
        button.click()
    }

    private func replaceStructuralLayoutField(
        _ field: XCUIElement,
        with text: String,
        in application: XCUIApplication,
        endKey: XCUIKeyboardKey = .return
    ) {
        let identifier = field.identifier
        _ = revealStructuralLayoutControl(field, in: application)
        guard waitForLiveStructuralFieldReadiness(identifier, in: application) else {
            attachStructuralFieldDiagnostics(identifier: identifier, application: application)
            XCTFail("Inspector field \(identifier) did not become active, enabled, and hittable")
            return
        }
        application.textFields[identifier].doubleClick()
        guard waitForKeyboardFocus(
            application.textFields[identifier],
            in: application,
            timeout: 5
        ) else { return }
        let focusedField = application.textFields[identifier]
        focusedField.typeKey(.leftArrow, modifierFlags: .command)
        focusedField.typeKey(.rightArrow, modifierFlags: [.command, .shift])
        focusedField.typeKey(.delete, modifierFlags: [])
        focusedField.typeText(text)
        application.textFields[identifier].typeKey(endKey, modifierFlags: [])
    }

    private func waitForLiveStructuralFieldReadiness(
        _ identifier: String,
        in application: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        // A retained screenshot or native menu can momentarily yield foreground
        // ownership on a slow hosted runner. Reactivate the real application,
        // then query the replacement SwiftUI field rather than typing through
        // the pre-update AX proxy.
        application.activate()
        let predicate = NSPredicate { [weak application] _, _ in
            guard let application,
                  application.state == .runningForeground,
                  application.sheets.count == 0,
                  application.dialogs.count == 0 else { return false }
            let live = application.textFields[identifier]
            return live.exists && live.isEnabled && live.isHittable
        }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: application)],
            timeout: timeout
        ) == .completed
    }

    private func attachStructuralFieldDiagnostics(
        identifier: String,
        application: XCUIApplication
    ) {
        let field = application.textFields[identifier]
        let window = application.windows.firstMatch
        let focus = application.descendants(matching: .any)["workspace.focus.diagnostics"]
        let details = """
        application={state=\(application.state.rawValue);enabled=\(application.isEnabled);sheets=\(application.sheets.count);dialogs=\(application.dialogs.count)}
        window={exists=\(window.exists);enabled=\(window.exists && window.isEnabled);frame=\(window.exists ? sanitizedFrame(window.frame) : "unavailable")}
        field={identifier=\(identifier);exists=\(field.exists);enabled=\(field.exists && field.isEnabled);hittable=\(field.exists && field.isHittable);focused=\(field.exists && hasKeyboardFocus(field));frame=\(field.exists ? sanitizedFrame(field.frame) : "unavailable")}
        focus=\(focus.exists ? ((focus.value as? String) ?? "unavailable") : "unavailable")
        """
        let attachment = XCTAttachment(string: details)
        attachment.name = "structural-layout-field-readiness"
        attachment.lifetime = .keepAlways
        add(attachment)
        let hierarchy = XCTAttachment(string: redactedAccessibilityHierarchy(for: application))
        hierarchy.name = "structural-layout-field-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        attachScreenshot(named: "structural-layout-field-readiness")
    }

    private func saveDocumentIfModified(in application: XCUIApplication) {
        func liveStatus() -> String {
            let status = application.descendants(matching: .any)["status.document"].firstMatch
            return status.label + " " + ((status.value as? String) ?? "")
        }

        let settled = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in
                    let status = liveStatus()
                    return status.contains("Modified") || status.contains("Saved")
                },
                object: application
            )],
            timeout: 5
        ) == .completed
        XCTAssertTrue(settled, "Document status must settle as Modified or Saved before persistence")
        if liveStatus().contains("Saved") { return }

        XCTAssertTrue(
            liveStatus().contains("Modified"),
            "Document status must be Modified or Saved before persistence"
        )
        application.menuBars.menuBarItems["File"].click()
        let saveBecamePossibleOrUnnecessary = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(
                predicate: NSPredicate { [weak application] _, _ in
                    guard let application else { return false }
                    let status = application.descendants(matching: .any)["status.document"].firstMatch
                    if status.label.contains("Saved")
                        || (status.value as? String)?.contains("Saved") == true {
                        return true
                    }
                    let liveSave = application.menuItems["Save"]
                    return liveSave.exists && liveSave.isEnabled
                },
                object: application
            )],
            timeout: 5
        ) == .completed
        XCTAssertTrue(
            saveBecamePossibleOrUnnecessary,
            "Autosave must either finish or leave the native Save command enabled"
        )
        if waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 0.25) {
            application.typeKey(.escape, modifierFlags: [])
            return
        }
        let liveSave = application.menuItems["Save"]
        XCTAssertTrue(liveSave.exists)
        XCTAssertTrue(liveSave.isEnabled)
        liveSave.click()
        XCTAssertTrue(waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 8))
    }

    private func assertNormalWindowPolicy(
        in application: XCUIApplication,
        permitsLeadingEdgeConstrainedPlacementOnNarrowDisplay: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let window = application.windows.firstMatch
        XCTAssertTrue(window.exists, file: file, line: line)
        XCTAssertGreaterThanOrEqual(window.frame.width, 1_100, file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            window.frame.height,
            TestWindowGeometry.minimumExpectedHeight,
            file: file,
            line: line
        )
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        if visible.width >= 1_100 {
            XCTAssertEqual(window.frame.width, visible.width, accuracy: 3, file: file, line: line)
        } else {
            XCTAssertEqual(window.frame.width, 1_100, accuracy: 3, file: file, line: line)
            if permitsLeadingEdgeConstrainedPlacementOnNarrowDisplay {
                XCTAssertEqual(
                    window.frame.minX,
                    visible.minX + TestWindowGeometry.safeScreenInset,
                    accuracy: 3,
                    file: file,
                    line: line
                )
            } else {
                XCTAssertEqual(window.frame.maxX, visible.maxX, accuracy: 3, file: file, line: line)
            }
        }
        if !permitsLeadingEdgeConstrainedPlacementOnNarrowDisplay,
           visible.height >= window.frame.height - 3 {
            XCTAssertEqual(window.frame.height, visible.height, accuracy: 3, file: file, line: line)
        }
        XCTAssertLessThan(
            window.frame.height,
            screen.frame.height,
            "A normal SiteForge window must leave system UI available and never enter a native full-screen Space.",
            file: file,
            line: line
        )
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

    // SF-0308-001...008
    @MainActor
    func testTransactionalClipboardDuplicateCutPasteUndoRedoAccessibilityJourney() throws {
        let application = launchWorkspace()
        XCTAssertTrue(waitForWorkspaceReady(application))
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Frame at Center"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))

        application.typeKey("d", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertTrue(waitForValue(
            application.descendants(matching: .any)["status.clipboard"], containing: "Duplicated 1 object"
        ))
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))

        let frame = canvasObject(named: "Frame", in: application)
        XCTAssertTrue(frame.waitForExistence(timeout: 3))
        frame.click()
        application.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(waitForValue(
            application.descendants(matching: .any)["status.clipboard"], containing: "Copied 1 object"
        ))
        application.typeKey("v", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        // Paste replaces the immutable renderer host. Re-establish selection
        // and first responder through the live authored object before sending
        // the real Cut shortcut; a cached tiled AX proxy is not a command
        // target on slower hosted runners.
        let cutTarget = canvasObject(named: "Frame", in: application)
        XCTAssertTrue(waitForHittable(cutTarget, in: application))
        cutTarget.click()
        XCTAssertTrue(waitForKeyboardFocus(identifier: "canvas.interaction", in: application))
        application.typeKey("x", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        application.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-107 clipboard duplicate cut paste")
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
            let application = launchScenario(
                "workspace",
                windowAlignment: leadingEdgeAlignmentOnNarrowDisplay,
                extraArguments: arguments
            )
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
        // The 10,000-page AX projection is deliberately much larger than an
        // ordinary workspace. Preserve the exact window/shell readiness check
        // while allowing its first hosted AX query to finish under load.
        let application = launchScenario("workspace", workspaceReadinessTimeout: 30, extraArguments: [
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
