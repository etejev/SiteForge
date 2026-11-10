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
    // SF-LOCAL-BUILDER-008; SF-0606-002/003/004/006/008,
    // SF-0602-002/003/004/006, SF-0402-002/003/006, SF-0701-003/006.
    // SOURCE ONLY. Later acceptance must inspect every retained original.
    func testResponsiveLayoutReviewJumpsToExactElementAndRefreshesAfterFixJourney() throws {
        let application = launchWorkspace()
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        application.buttons["canvas.empty.insert.frame"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let row = application.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3)); XCTAssertTrue(row.isSelected)
        let nodeID = row.identifier.replacingOccurrences(of: "navigator.layer.", with: "")
        selectInspectorTab("Layout", identifier: "layout", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.layout.x"], with: "400", in: application)
        attachWindowScreenshot(application, named: "SF-REVIEW Desktop fixed authored Frame")
        let width = application.textFields["canvas.viewport.width"]
        replaceText(in: width, with: "430", application: application)
        width.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.width", containing: "430"))
        let findingPrefix = "responsive.finding." + nodeID + ".430.0.true."
        func revealCurrentSample() -> XCUIElement {
            XCTAssertTrue(waitForLiveValue(in: application, identifier: "responsive.compare.status", containing: "horizontal boundary reviews"))
            let scroll = application.scrollViews["responsive.compare.results"]
            var card = application.descendants(matching: .any)["responsive.compare.card.current"]
            for _ in 0..<10 where !card.exists || !card.isHittable {
                scroll.scroll(byDeltaX: 0, deltaY: -180)
                card = application.descendants(matching: .any)["responsive.compare.card.current"]
            }
            XCTAssertTrue(card.exists)
            return card
        }
        func openComparisonAndFindCurrentReview() -> XCUIElement {
            application.buttons["canvas.viewport.compare"].click()
            XCTAssertTrue(application.descendants(matching: .any)["responsive.compare.sheet"].waitForExistence(timeout: 3))
            XCTAssertTrue(waitForValue(revealCurrentSample(), containing: "430"))
            let scroll = application.scrollViews["responsive.compare.results"]
            var button = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", findingPrefix)).firstMatch
            for _ in 0..<10 where !button.exists || !button.isHittable {
                scroll.scroll(byDeltaX: 0, deltaY: -180)
                button = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", findingPrefix)).firstMatch
            }
            XCTAssertTrue(waitForHittable(button, in: application))
            return button
        }
        let review = openComparisonAndFindCurrentReview()
        XCTAssertTrue(review.isEnabled)
        XCTAssertTrue(review.label.contains("Frame") && review.label.contains("430"))
        attachWindowScreenshot(application, named: "SF-REVIEW custom Mobile measured boundary")
        review.click()
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["responsive.compare.sheet"]))
        XCTAssertTrue(application.buttons["navigator.layer." + nodeID].isSelected)
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.width", containing: "430"))
        XCTAssertTrue(waitForLiveSemanticText(in: application, identifier: "inspector.layout.responsiveReview", containing: "430"))
        let x = application.textFields["inspector.layout.x"]
        XCTAssertTrue(x.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(x, containing: "400"))
        attachWindowScreenshot(application, named: "SF-REVIEW exact node Layout and winning width source")
        replaceStructuralLayoutField(x, with: "20", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Set here · Mobile"))
        application.buttons["canvas.viewport.compare"].click()
        let current = revealCurrentSample()
        XCTAssertTrue(waitForValue(current, containing: "430"))
        XCTAssertTrue(waitForValue(current, containing: "0 horizontal boundary reviews"))
        XCTAssertFalse(application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", findingPrefix)).firstMatch.exists)
        attachWindowScreenshot(application, named: "SF-REVIEW atomic Mobile correction refreshed")
        application.buttons["responsive.compare.done"].click()
        application.menuBars.menuBarItems["Edit"].click(); application.menuItems["Undo"].click()
        let restored = openComparisonAndFindCurrentReview()
        XCTAssertTrue(restored.exists)
        attachWindowScreenshot(application, named: "SF-REVIEW Undo restores measured review")
        application.buttons["responsive.compare.done"].click()
        application.menuBars.menuBarItems["Edit"].click(); application.menuItems["Redo"].click()
        application.buttons["canvas.viewport.compare"].click()
        XCTAssertTrue(waitForValue(revealCurrentSample(), containing: "0 horizontal boundary reviews"))
        attachWindowScreenshot(application, named: "SF-REVIEW Redo preserves corrected geometry")
        application.buttons["responsive.compare.done"].click()
        XCTAssertTrue(application.buttons["navigator.layer." + nodeID].isSelected)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
    }

    // SF-LOCAL-BUILDER-007; SF-0602-002/003/004/006/008,
    // SF-0601-003/006, SF-0604-003/006, SF-0401-003/006.
    // SOURCE ONLY: not executed or visually accepted during the owner hold.
    func testCustomResponsiveViewportWidthEntryComparisonAndCancellationJourney() throws {
        let application = launchWorkspace()
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        let widthID = "canvas.viewport.width"
        func committedWidth(_ text: String) -> Bool {
            let formatter = NumberFormatter()
            formatter.locale = .current; formatter.numberStyle = .decimal
            let expected = formatter.number(from: text)?.doubleValue
            let predicate = NSPredicate { _, _ in
                let live = application.textFields[widthID]
                guard live.exists, let value = live.value as? String,
                      !value.contains("uncommitted draft"),
                      let first = value.split(separator: ";").first,
                      let number = formatter.number(from: String(first)) else { return false }
                return number.doubleValue == expected
            }
            return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3) == .completed
        }
        func enterWidth(_ text: String) {
            let field = application.textFields[widthID]
            XCTAssertTrue(waitForHittable(field, in: application))
            replaceText(in: field, with: text, application: application)
            XCTAssertTrue(waitForKeyboardFocus(application.textFields[widthID], in: application))
            application.textFields[widthID].typeKey(.return, modifierFlags: [])
        }
        enterWidth("430")
        XCTAssertTrue(committedWidth("430"))
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.preset", containing: "Mobile"))
        application.buttons["canvas.empty.insert.frame"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let row = application.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3)); XCTAssertTrue(row.isSelected)
        let nodeID = row.identifier.replacingOccurrences(of: "navigator.layer.", with: "")
        XCTAssertTrue(application.descendants(matching: .any)["canvas.object." + nodeID].exists)
        attachWindowScreenshot(application, named: "SF-WIDTH custom 430 Mobile insertion")

        for (width, breakpoint) in [("599", "Mobile"), ("600", "Tablet"),
                                    ("900", "Tablet"), ("1023", "Tablet"), ("1024", "Desktop")] {
            enterWidth(width)
            XCTAssertTrue(committedWidth(width), "Require committed numeric width, independent of locale grouping")
            XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.preset", containing: breakpoint))
            XCTAssertTrue(application.buttons["navigator.layer." + nodeID].isSelected)
        }
        attachWindowScreenshot(application, named: "SF-WIDTH exact 1024 Desktop boundary")

        // Genuine native blur commits; Compare is reached by normal traversal.
        replaceText(in: application.textFields[widthID], with: "900", application: application)
        application.textFields[widthID].typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["canvas.viewport.compare"], in: application))
        XCTAssertTrue(committedWidth("900"))
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.preset", containing: "Tablet"))
        attachWindowScreenshot(application, named: "SF-WIDTH custom 900 Tablet focus loss")

        replaceText(in: application.textFields[widthID], with: "430", application: application)
        application.textFields[widthID].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(committedWidth("900"))
        enterWidth("invalid")
        XCTAssertTrue(application.descendants(matching: .any)["canvas.viewport.width.validation"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.preset", containing: "Tablet"))
        XCTAssertTrue(application.buttons["navigator.layer." + nodeID].isSelected)
        attachWindowScreenshot(application, named: "SF-WIDTH invalid draft preserves Tablet")
        application.textFields[widthID].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(committedWidth("900"))

        application.buttons["canvas.viewport.compare"].click()
        let sheet = application.descendants(matching: .any)["responsive.compare.sheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-WIDTH comparison opened current context")
        for reference in ["desktop", "tablet", "mobile"] {
            XCTAssertTrue(revealResponsiveComparisonControl("responsive.compare.card." + reference,
                in: application, scrollDelta: reference == "desktop" ? 180 : -180).exists)
        }
        _ = revealResponsiveComparisonControl("responsive.compare.card.current", in: application)
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "responsive.compare.card.current", containing: "900"))
        attachWindowScreenshot(application, named: "SF-WIDTH current sample with preset references")
        _ = revealResponsiveComparisonControl("responsive.compare.review.desktop", in: application, scrollDelta: 180)
        application.buttons["responsive.compare.review.desktop"].click()
        _ = revealResponsiveComparisonControl("responsive.compare.card.current", in: application)
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "responsive.compare.card.current", containing: "1440"))
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(sheet))
        XCTAssertTrue(committedWidth("1440"))
        XCTAssertTrue(application.buttons["navigator.layer." + nodeID].isSelected)
        XCTAssertTrue(application.descendants(matching: .any)["canvas.object." + nodeID].exists)
        attachWindowScreenshot(application, named: "SF-WIDTH exact Desktop reference preserves identity")
    }

    private func revealResponsiveComparisonControl(_ identifier: String, in application: XCUIApplication,
                                                  scrollDelta: CGFloat = -180) -> XCUIElement {
        let adopted = waitForLiveValue(in: application, identifier: "responsive.compare.status", containing: "horizontal boundary reviews")
        if !adopted { attachReadinessDiagnostics(for: application) }
        XCTAssertTrue(adopted)
        let scroll = application.scrollViews["responsive.compare.results"]
        var element = application.descendants(matching: .any)[identifier].firstMatch
        for _ in 0..<12 where !element.exists || !element.isHittable {
            scroll.scroll(byDeltaX: 0, deltaY: scrollDelta)
            element = application.descendants(matching: .any)[identifier].firstMatch
        }
        XCTAssertTrue(element.exists && element.isHittable, "Comparison control must be genuinely revealed before interaction")
        return element
    }

    // Opt-in owner authoring audit: attach to the already-open independent
    // project, never launch/terminate the ordinary app or generate project data.
    // SF-0508-002/006. Not part of the unattended fixture-driven suite.
    func testOwnerDarkFlowVisibleGradientControls() throws {
        guard ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW"] == "1" else {
            throw XCTSkip("Requires the owner-open independent Dark Flow project")
        }
        continueAfterFailure = false
        let application = XCUIApplication(bundleIdentifier: ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW_APP"] ?? "app.siteforge.SiteForge")
        XCTAssertNotEqual(application.state, .notRunning)
        application.activate()
        XCTAssertTrue(application.windows.matching(NSPredicate(format: "title == %@", "Aurora — Dark Flow")).firstMatch.waitForExistence(timeout: 5))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let section = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section"
        )).firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5)); section.click()
        selectInspectorTab("Design", identifier: "design", in: application)
        attachWindowScreenshot(application, named: "Dark Flow existing Section Design controls")
        let hierarchy = XCTAttachment(string: redactedAccessibilityHierarchy(for: application))
        hierarchy.name = "Dark Flow native Design authoring audit"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        XCTAssertTrue(application.buttons["inspector.design.layers.addGradient"].exists)
        guard ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW_STAGE"] == "gradient" else { return }
        let imageRemove = application.buttons["inspector.imageFill.remove"]
        if imageRemove.exists && imageRemove.isEnabled {
            revealStructuralLayoutControl(imageRemove, in: application).click()
        }
        let angles = application.textFields.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "inspector.design.layers.", ".angle"))
        if angles.count == 0 {
            let deletes = application.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
                "inspector.design.layers.", ".delete"))
            for identifier in deletes.allElementsBoundByIndex.map(\.identifier) {
                revealStructuralLayoutControl(application.buttons[identifier], in: application).click()
            }
            revealStructuralLayoutControl(application.buttons["inspector.design.layers.addGradient"], in: application).click()
        }
        XCTAssertEqual(angles.count, 1)
        let angle = angles.firstMatch
        replaceStructuralLayoutField(angle, with: "45", in: application)
        let prefix = angle.identifier.replacingOccurrences(of: ".angle", with: "")
        let positions = application.textFields.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", prefix + ".stop.", ".position"))
        if positions.count == 2 {
            revealStructuralLayoutControl(application.buttons[prefix + ".addStop"], in: application).click()
        }
        XCTAssertEqual(positions.count, 3)
        let wells = application.colorWells.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", prefix + ".stop.", ".color"))
        XCTAssertEqual(wells.count, 3)
        let panel = application.windows.matching(NSPredicate(format: "title == %@", "Colors")).firstMatch
        let stopIdentifiers = wells.allElementsBoundByIndex.map(\.identifier)
        for identifier in stopIdentifiers {
            let stopPrefix = String(identifier.dropLast(".color".count))
            let position = application.textFields[stopPrefix + ".position"].value as? String ?? ""
            let color: String
            switch position {
            case "0": color = "160D2B"
            case "50": color = "6A36C8"
            case "100": color = "C52E53"
            default: XCTFail("Unexpected authored stop position: \(position)"); return
            }
            revealStructuralLayoutControl(application.colorWells[identifier], in: application).click()
            XCTAssertTrue(panel.waitForExistence(timeout: 3))
            panel.buttons["Color Sliders"].click()
            if (panel.popUpButtons.firstMatch.value as? String) != "RGB Sliders" {
                panel.popUpButtons.firstMatch.click()
                application.menuItems["RGB Sliders"].click()
            }
            let colors = XCTAttachment(string: panel.debugDescription)
            colors.name = "Dark Flow standard RGB Colors panel controls"; colors.lifetime = .keepAlways; add(colors)
            let hexadecimal = panel.textFields.matching(NSPredicate(format: "value MATCHES %@", "[0-9A-Fa-f]{6}")).firstMatch
            XCTAssertTrue(hexadecimal.waitForExistence(timeout: 3), panel.debugDescription)
            replaceText(in: hexadecimal, with: color, application: application)
            hexadecimal.typeKey(.return, modifierFlags: [])
            let picker = XCTAttachment(screenshot: panel.screenshot())
            picker.name = "Dark Flow native gradient stop \(position) color"; picker.lifetime = .keepAlways; add(picker)
            panel.buttons["_XCUI:CloseWindow"].click()
            application.activate()
            XCTAssertTrue(waitForValue(application.colorWells[identifier], containing: "#\(color)FF"))
        }
        // Preserve each real stop identity while ordering its authored rows.
        let middle = positions.allElementsBoundByIndex.first { ($0.value as? String) == "50" }
        let middleID = try XCTUnwrap(middle?.identifier)
        let middleUp = application.buttons[middleID.replacingOccurrences(of: ".position", with: ".up")]
        if (positions.element(boundBy: 1).value as? String) != "50" {
            revealStructuralLayoutControl(middleUp, in: application).click()
        }
        XCTAssertEqual(positions.element(boundBy: 1).value as? String, "50")
        saveDocumentIfModified(in: application)
        attachWindowScreenshot(application, named: "Dark Flow authored three-stop plum purple ruby gradient")
    }

    // SF-0701-003/006, SF-1207-003/004/006: no-op Apply is a validated
    // dismissal, not an appearance error or an empty history transaction.
    func testSiteSettingsUnchangedApplyClosesWithoutHistoryJourney() throws {
        let application = launchWorkspace()
        componentMenu("File", "Site & Page Settings…", in: application)
        XCTAssertTrue(application.buttons["siteSettings.apply"].waitForExistence(timeout: 5))
        application.buttons["siteSettings.apply"].click()
        XCTAssertTrue(application.buttons["siteSettings.apply"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(application.windows.firstMatch.title.contains("Edited"))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.document"].firstMatch, containing: "Saved"))
        application.menuBars.menuBarItems["Edit"].click()
        XCTAssertFalse(application.menuItems["Undo"].isEnabled)
        application.typeKey(.escape, modifierFlags: [])
        componentMenu("File", "Site & Page Settings…", in: application)
        XCTAssertEqual(application.textFields["siteSettings.siteName"].value as? String, "")
        attachWindowScreenshot(application, named: "Workflow unchanged Site Settings remains truthful")
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.buttons["siteSettings.apply"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(application.windows.firstMatch.title.contains("Edited"))
    }

    // SF-0201-003/006, SF-0701-003/006. Measure the real native layout;
    // tab availability is not satisfied by a hidden overflow destination.
    func testNormalFiveDestinationRowsAndInspectorFieldStabilityJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        for (prefix, tabs) in [("navigator.tab.", ["pages", "layers", "elements", "assets", "components"]),
                               ("inspector.tab.", ["design", "layout", "content", "interactions", "accessibility"])] {
            var previous: CGRect?
            for tab in tabs {
                let button = application.buttons[prefix + tab]
                XCTAssertTrue(button.waitForExistence(timeout: 3), tab)
                XCTAssertTrue(button.isHittable, tab)
                XCTAssertGreaterThanOrEqual(button.frame.height, 28)
                if let previous {
                    XCTAssertEqual(button.frame.minY, previous.minY, accuracy: 1)
                    XCTAssertGreaterThanOrEqual(button.frame.minX, previous.maxX - 1)
                }
                previous = button.frame
            }
            XCTAssertFalse(application.buttons[prefix + "overflow"].exists)
        }
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.buttons["inspector.tab.layout"].click()
        let x = application.textFields["inspector.layout.x"]
        XCTAssertTrue(x.waitForExistence(timeout: 3))
        XCTAssertTrue(revealStructuralLayoutControl(x, in: application).isHittable)
        let baseline = x.frame
        var observations: [[String: Any]] = []
        func measure(_ stage: String) {
            let pane = application.descendants(matching: .any)["shell.inspector"].firstMatch.frame
            let field = application.textFields["inspector.layout.x"].frame
            let group = application.descendants(matching: .any)["inspector.layout.geometryFields"].firstMatch.frame
            let scroll = application.scrollViews["inspector.selection.scroll"]
            observations.append(["stage": stage, "fieldX": field.minX - pane.minX,
                "fieldY": field.minY - pane.minY, "fieldWidth": field.width,
                "headingX": group.minX - pane.minX, "contentWidth": group.width,
                "scrollbarValues": scroll.scrollBars.allElementsBoundByIndex.map { String(describing: $0.value ?? "unavailable") }])
            XCTAssertEqual(field.minX, baseline.minX, accuracy: 0.5, stage)
            XCTAssertEqual(field.width, baseline.width, accuracy: 0.5, stage)
        }
        measure("selected Frame")
        attachWindowScreenshot(application, named: "Workflow all five destinations and Inspector before edit")
        replaceStructuralLayoutField(x, with: "20", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.transform.geometry"].firstMatch, containing: "X 20"))
        measure("numeric Return")
        componentMenu("Edit", "Undo", in: application); measure("Undo")
        componentMenu("Edit", "Redo", in: application); measure("Redo")
        application.buttons["inspector.tab.design"].click()
        application.buttons["inspector.tab.layout"].click()
        XCTAssertTrue(revealStructuralLayoutControl(application.textFields["inspector.layout.x"], in: application).isHittable)
        measure("Design to Layout")
        for preset in ["Tablet", "Mobile", "Desktop"] {
            application.popUpButtons["canvas.viewport.preset"].click()
            application.menuItems[preset].click()
            measure(preset)
        }
        let data = try JSONSerialization.data(withJSONObject: observations, options: [.prettyPrinted, .sortedKeys])
        let geometry = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        geometry.name = "Workflow Inspector measured update sequence"; geometry.lifetime = .keepAlways; add(geometry)
        attachWindowScreenshot(application, named: "Workflow Inspector after edit Undo Redo tabs and breakpoints")
    }

    // Owner-requested website authoring macro. Every action is a shipped
    // control; the opt-in driver contains no canonical mutation or fixture.
    func testOwnerDarkFlowNativeThemeAndFlow() throws {
        guard ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW"] == "1" else {
            throw XCTSkip("Requires the owner-open independent Dark Flow project")
        }
        continueAfterFailure = false
        let application = XCUIApplication(bundleIdentifier: ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW_APP"] ?? "app.siteforge.SiteForge")
        try authorDarkFlowThemeAndFlow(in: application)
    }

    private func authorDarkFlowThemeAndFlow(in application: XCUIApplication) throws {
        XCTAssertNotEqual(application.state, .notRunning); application.activate()
        XCTAssertTrue(application.windows.matching(NSPredicate(format: "title BEGINSWITH %@", "Aurora — Dark Flow")).firstMatch.waitForExistence(timeout: 5))
        func revealLayer(_ identifier: String) -> XCUIElement {
            let row = application.buttons[identifier]
            let list = application.scrollViews["navigator.layers.list"]
            for _ in 0..<14 {
                if row.isHittable, row.frame.minY >= list.frame.minY - 1, row.frame.maxY <= list.frame.maxY + 1 { break }
                list.scroll(byDeltaX: 0, deltaY: row.frame.minY < list.frame.minY ? 180 : -180)
            }
            XCTAssertTrue(row.isHittable); return row
        }
        func selectLayers(_ identifiers: [String]) {
            XCTAssertFalse(identifiers.isEmpty)
            for (index, identifier) in identifiers.enumerated() {
                let row = revealLayer(identifier)
                if index == 0 { row.click() }
                else { XCUIElement.perform(withKeyModifiers: .shift) { row.click() } }
            }
            for identifier in identifiers { XCTAssertTrue(application.buttons[identifier].isSelected) }
        }
        func token(_ name: String, color: String) {
            let row = application.buttons.matching(NSPredicate(format: "label == %@", "Color token " + name)).firstMatch
            if !row.exists {
                revealStructuralLayoutControl(application.buttons["inspector.tokens.new"], in: application).click()
                replaceComponentTextField("inspector.tokens.name", with: name, in: application)
                replaceComponentTextField("inspector.tokens.color", with: color, in: application)
                revealStructuralLayoutControl(application.buttons["inspector.tokens.apply"], in: application).click()
            }
            XCTAssertTrue(row.exists)
        }
        func bind(_ name: String, target: String) {
            let row = application.buttons.matching(NSPredicate(format: "label == %@", "Color token " + name)).firstMatch
            revealStructuralLayoutControl(row, in: application).click()
            XCTAssertEqual(application.textFields["inspector.tokens.name"].value as? String, name)
            let destination = application.popUpButtons["inspector.tokens.target"]
            if (destination.value as? String) != target {
                revealStructuralLayoutControl(destination, in: application).click()
                application.menuItems[target].click()
            }
            let status = application.descendants(matching: .any)["inspector.tokens.targetStatus"]
            if target == "Text Foreground", (status.value as? String ?? status.label).hasPrefix("No applicable") {
                // The shipping contract binds an existing authored target.
                // Explicitly create the intended foreground through its real
                // field; do not click a disabled Bind button or alter registry policy.
                guard let color = application.textFields["inspector.tokens.color"].value as? String else {
                    XCTFail("The selected token must expose its actual normalized color"); return
                }
                replaceStructuralLayoutField(application.textFields["inspector.design.typography.foregroundHex"], with: color, in: application)
                // Reopen the same token editor after canonical adoption.
                revealStructuralLayoutControl(row, in: application).click()
            }
            let button = revealStructuralLayoutControl(application.buttons["inspector.tokens.bind"], in: application)
            XCTAssertTrue(button.isEnabled); button.click()
            XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.tokens.bindingStatus"], containing: name))
        }
        func clearSelection() {
            application.menuBars.menuBarItems["Selection"].click()
            let clear = application.menuItems["Clear Selection"]
            if clear.isEnabled { clear.click() } else { application.typeKey(.escape, modifierFlags: []) }
        }
        func insert(_ item: String) {
            componentMenu("Insert", item, in: application)
            XCTAssertTrue(waitForWorkspaceReady(application))
            application.buttons["toolbar.tool.select"].click()
        }
        func editText(_ text: String) {
            componentMenu("Selection", "Edit Selected Text", in: application)
            let editor = application.textViews["canvas.text.editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForKeyboardFocus(editor, in: application))
            if (editor.value as? String) != text {
                editor.typeKey("a", modifierFlags: .command); editor.typeText(text)
            }
            XCTAssertEqual(editor.value as? String, text, "Native Select All must replace, not append to authored content")
            editor.typeKey(.return, modifierFlags: .command)
            XCTAssertTrue(waitForNonexistence(editor))
            saveDocumentIfModified(in: application)
        }
        func sizing(_ dimension: String, _ mode: String) {
            let control = application.popUpButtons["inspector.sizing.\(dimension)Mode"]
            if (control.value as? String) != mode {
                revealStructuralLayoutControl(control, in: application).click()
                application.menuItems[mode].click()
                XCTAssertTrue(waitForValue(application.popUpButtons["inspector.sizing.\(dimension)Mode"], containing: mode))
            }
        }
        func bound(_ key: String, _ value: String) {
            let field = application.textFields["inspector.sizing." + key]
            if !field.exists {
                revealStructuralLayoutControl(application.descendants(matching: .any)["inspector.sizing.boundsDisclosure"].firstMatch, in: application).click()
            }
            attachWindowScreenshot(application, named: "Dark Flow native sizing before \(key)")
            if (field.value as? String) != value { replaceStructuralLayoutField(field, with: value, in: application) }
        }
        func textStyle(heading: Bool, level: String = "<h1>") {
            selectInspectorTab("Design", identifier: "design", in: application)
            if heading, (application.textFields["inspector.design.typography.family"].value as? String) != "Georgia" {
                replaceStructuralLayoutField(application.textFields["inspector.design.typography.family"], with: "Georgia", in: application)
            }
            for (key, value) in [("size", heading ? "44" : "18"), ("lineHeight", heading ? "56" : "28")] {
                let field = application.textFields["inspector.design.typography." + key]
                if (field.value as? String) != value { replaceStructuralLayoutField(field, with: value, in: application) }
            }
            let alignment = application.popUpButtons["inspector.design.typography.alignment"]
            if (alignment.value as? String) != "Leading" {
                revealStructuralLayoutControl(alignment, in: application).click(); alignment.menuItems["Leading"].click()
            }
            if heading {
                let element = application.descendants(matching: .any)["inspector.semantic.element"].firstMatch
                revealStructuralLayoutControl(element, in: application).click(); application.menuItems[level].click()
            }
            if !heading { token("Muted Lavender", color: "#D4C6E8FF") }
            bind(heading ? "Warm White" : "Muted Lavender", target: "Text Foreground")
            selectInspectorTab("Layout", identifier: "layout", in: application)
            sizing("width", "Fill available space"); sizing("height", "Fit content")
        }
        func editorialColumn(_ sectionID: String, expectedStacks: Int) throws -> String {
            let stacks = application.buttons.matching(NSPredicate(format:
                "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Stack"))
            if stacks.count < expectedStacks { selectLayers([sectionID]); insert("Insert Stack at Center") }
            XCTAssertEqual(stacks.count, expectedStacks)
            let id = try XCTUnwrap(stacks.allElementsBoundByIndex.last?.identifier)
            selectLayers([id]); selectInspectorTab("Design", identifier: "design", in: application)
            let removeFill = application.buttons["inspector.design.fillRemove"]
            if removeFill.exists && removeFill.isEnabled { revealStructuralLayoutControl(removeFill, in: application).click() }
            selectInspectorTab("Layout", identifier: "layout", in: application)
            sizing("width", "Fill available space"); sizing("height", "Fit content")
            replaceStructuralLayoutField(application.textFields["inspector.layout.container.padding"], with: "0", in: application)
            replaceStructuralLayoutField(application.textFields["inspector.layout.container.gap"], with: "24", in: application)
            bound("maxWidth", "720")
            return id
        }
        func nest(_ sourceID: String, in targetID: String) {
            let source = revealLayer(sourceID), target = revealLayer(targetID)
            // Layers rows have a flat visual layout. Their semantic parent,
            // not row indentation, determines whether this move is a no-op.
            if (source.value as? String)?.contains("Parent: " + target.label) == true { return }
            selectLayers([sourceID]); revealLayer(targetID).rightClick()
            XCTAssertTrue(application.buttons[sourceID].isSelected)
            let command = application.menuItems["Nest In"]
            XCTAssertTrue(command.waitForExistence(timeout: 3)); XCTAssertTrue(command.isEnabled); command.click()
            XCTAssertTrue(waitForValue(application.buttons["toolbar.undo"], containing: "Move Node"))
            XCTAssertTrue(application.buttons[sourceID].isSelected)
        }
        func fillSection(_ id: String, minimum: String) {
            selectLayers([id]); selectInspectorTab("Design", identifier: "design", in: application)
            bind("Dark Surface", target: "Fill")
            selectInspectorTab("Layout", identifier: "layout", in: application)
            sizing("height", "Fit content")
            replaceStructuralLayoutField(application.textFields["inspector.layout.container.padding"], with: "48", in: application)
            bound("minHeight", minimum)
        }
        func convertFlow(_ id: String) {
            selectLayers([id]); selectInspectorTab("Layout", identifier: "layout", in: application)
            let button = application.buttons["inspector.sizing.convertContent"]
            if button.isEnabled {
                revealStructuralLayoutControl(button, in: application).click()
                let confirm = application.sheets.firstMatch.buttons["Convert to automatic sizing"].firstMatch
                XCTAssertTrue(confirm.waitForExistence(timeout: 3)); confirm.click()
            }
            XCTAssertTrue(waitForValue(application.popUpButtons["inspector.sizing.heightMode"], containing: "Hug"))
        }
        let pages = (ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW_PAGES"] ?? "Home").split(separator: ",").map(String.init)
        let contentOnly = ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW_STAGE"] == "content"
        for page in pages {
            selectNavigatorTab("Pages", identifier: "pages", in: application)
            pageRow(named: page, in: application).click()
            selectNavigatorTab("Layers", identifier: "layers", in: application)
            if ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW_STAGE"] == "flow" {
                let sections = application.buttons.matching(NSPredicate(format:
                    "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section"))
                    .allElementsBoundByIndex.map(\.identifier)
                XCTAssertFalse(sections.isEmpty)
                for id in sections { convertFlow(id) }
                for preset in ["Desktop", "Tablet", "Mobile"] {
                    application.popUpButtons["canvas.viewport.preset"].click(); application.menuItems[preset].click()
                    for id in sections {
                        selectLayers([id]); selectInspectorTab("Layout", identifier: "layout", in: application)
                        XCTAssertTrue(waitForValue(application.staticTexts["inspector.sizing.heightMode.source"], containing: "Effective Hug"))
                        XCTAssertFalse(application.buttons["inspector.sizing.height.resetOverride"].exists)
                    }
                    application.buttons["canvas.zoom.fit"].click()
                    attachWindowScreenshot(application, named: "Dark Flow \(page) \(preset) confirmed responsive flow")
                }
                saveDocumentIfModified(in: application)
                continue
            }
            if page == "Not Found", application.buttons.matching(NSPredicate(format:
                "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Header")).count == 0 {
                for item in ["Insert Header at Page Top", "Insert Section in Flow", "Insert Footer after Page Content"] {
                    clearSelection(); insert(item)
                }
            }
            if !contentOnly {
            let chrome = application.buttons.matching(NSPredicate(format:
                "identifier BEGINSWITH %@ AND (label == %@ OR label == %@)", "navigator.layer.", "Header", "Footer"))
                .allElementsBoundByIndex.map(\.identifier)
            XCTAssertEqual(chrome.count, 2)
            selectLayers(chrome)
            selectInspectorTab("Design", identifier: "design", in: application)
            token("Dark Surface", color: "#100B1CFF")
            token("Warm White", color: "#FAF7FFFF")
            bind("Dark Surface", target: "Fill")
            // These are independent real chrome owners, not an implicit
            // cross-page component or a write into their generated link nodes.
            for identifier in chrome {
                revealLayer(identifier).click()
                selectInspectorTab("Content", identifier: "content", in: application)
                let title = application.textFields["inspector.navigation.title"]
                if (title.value as? String) != "AURORA" {
                    replaceStructuralLayoutField(title, with: "AURORA", in: application)
                }
            }
            // The actual sample's preorder Layers list separates its leaf
            // sibling groups with container rows. Do not pretend page-wide
            // selection survives the existing active-parent scope boundary.
            let textualNames: Set<String> = ["Text", "Site title", "Navigation Link", "Home", "Journal", "About", "Contact", "Button"]
            let rows = application.buttons.matching(NSPredicate(format:
                "identifier BEGINSWITH %@", "navigator.layer.")).allElementsBoundByIndex
            var groups: [[String]] = [], group: [String] = []
            for row in rows {
                if textualNames.contains(row.label) { group.append(row.identifier) }
                else if !group.isEmpty { groups.append(group); group = [] }
            }
            if !group.isEmpty { groups.append(group) }
            for identifiers in groups {
                selectLayers(identifiers)
                selectInspectorTab("Design", identifier: "design", in: application)
                bind("Warm White", target: "Text Foreground")
            }
            attachWindowScreenshot(application, named: "Dark Flow \(page) shared tokens and native multi-selection")
            saveDocumentIfModified(in: application)
            }
            if page == "Home" {
                selectStructuralLayer("Frame", in: application)
                selectInspectorTab("Design", identifier: "design", in: application)
                let removeFill = application.buttons["inspector.design.fillRemove"]
                if removeFill.exists && removeFill.isEnabled {
                    revealStructuralLayoutControl(removeFill, in: application).click()
                }
                selectStructuralLayer("Section", in: application)
                selectInspectorTab("Layout", identifier: "layout", in: application)
                if !(application.popUpButtons["inspector.sizing.heightMode"].value as? String ?? "").contains("Hug") {
                    revealStructuralLayoutControl(application.buttons["inspector.sizing.convertContent"], in: application).click()
                    let confirm = application.sheets.firstMatch.buttons["Convert to automatic sizing"].firstMatch
                    XCTAssertTrue(confirm.waitForExistence(timeout: 3)); confirm.click()
                }
                replaceStructuralLayoutField(application.textFields["inspector.layout.container.padding"], with: "48", in: application)
                let actions = application.buttons.matching(NSPredicate(format:
                    "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Stack")).allElementsBoundByIndex
                XCTAssertTrue((2...3).contains(actions.count))
                let actionsID = actions[1].identifier
                application.popUpButtons["canvas.viewport.preset"].click(); application.menuItems["Mobile"].click()
                revealLayer(actionsID).click()
                selectInspectorTab("Layout", identifier: "layout", in: application)
                let vertical = try XCTUnwrap(revealStructuralLayoutRadioButton("Vertical", groupIdentifier: "inspector.layout.container.axis", in: application))
                vertical.click()
                selectStructuralLayer("Section", in: application)
                replaceStructuralLayoutField(application.textFields["inspector.layout.container.padding"], with: "24", in: application)
                application.buttons["canvas.zoom.fit"].click()
                attachWindowScreenshot(application, named: "Dark Flow Mobile real flow and vertical actions")
                application.popUpButtons["canvas.viewport.preset"].click(); application.menuItems["Desktop"].click()
                if ["site", "content"].contains(ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW_STAGE"] ?? "") {
                    let sections = application.buttons.matching(NSPredicate(format:
                        "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section"))
                    if sections.count == 1 { clearSelection(); insert("Insert Section in Flow") }
                    XCTAssertEqual(sections.count, 2)
                    let extraID = sections.element(boundBy: 1).identifier
                    let columnID = try editorialColumn(extraID, expectedStacks: 3)
                    selectLayers([columnID])
                    let heading = application.buttons.matching(NSPredicate(format:
                        "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Heading"))
                    if heading.count == 0 { insert("Insert Heading at Center") }
                    else { selectLayers([heading.firstMatch.identifier]) }
                    editText("Ideas worth following."); textStyle(heading: true, level: "<h2>")
                    let texts = application.buttons.matching(NSPredicate(format:
                        "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text"))
                    if texts.count == 3 { selectLayers([columnID]); insert("Insert Text at Center") }
                    else { XCTAssertEqual(texts.count, 4); selectLayers([texts.element(boundBy: 3).identifier]) }
                    editText("Good stories begin with close attention. Aurora follows the details that make a place, an object or an ordinary day feel different.\n\nIn the Journal, explore three short field notes: how everyday spaces shape the way we meet; why useful design leaves room for surprise; and what changes when we take the slower route.\n\nThis is a small, independent editorial study. There is no feed to chase and no account to create—just considered writing, open questions and room to be curious. Read the Journal, learn about the project, or visit Contact to see the current demonstration boundaries.")
                    textStyle(heading: false)
                    fillSection(extraID, minimum: "480")
                    convertFlow(extraID)
                    application.popUpButtons["canvas.viewport.preset"].click(); application.menuItems["Mobile"].click()
                    selectLayers([extraID])
                    replaceStructuralLayoutField(application.textFields["inspector.layout.container.padding"], with: "24", in: application)
                    application.buttons["canvas.zoom.fit"].click()
                    attachWindowScreenshot(application, named: "Dark Flow Home Mobile complete editorial content")
                    application.popUpButtons["canvas.viewport.preset"].click(); application.menuItems["Desktop"].click()
                }
            } else if ["site", "content"].contains(ProcessInfo.processInfo.environment["SITEFORGE_OWNER_DARK_FLOW_STAGE"] ?? "") {
                let section = application.buttons.matching(NSPredicate(format:
                    "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section")).firstMatch
                let sectionID = section.identifier
                let texts = application.buttons.matching(NSPredicate(format:
                    "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text"))
                let existingTextIDs = texts.allElementsBoundByIndex.map(\.identifier)
                XCTAssertLessThanOrEqual(existingTextIDs.count, 2)
                let columnID = try editorialColumn(sectionID, expectedStacks: 1)
                if existingTextIDs.isEmpty { selectLayers([columnID]); insert("Insert Text at Center") }
                let headingID = existingTextIDs.first ?? texts.firstMatch.identifier
                if !existingTextIDs.isEmpty { nest(headingID, in: columnID) }
                let bodyID: String
                if existingTextIDs.count < 2 {
                    selectLayers([columnID]); insert("Insert Text at Center")
                    bodyID = try XCTUnwrap(texts.allElementsBoundByIndex.map(\.identifier).first {
                        $0 != headingID && !existingTextIDs.contains($0)
                    })
                } else { bodyID = existingTextIDs[1] }
                if existingTextIDs.count == 2 { nest(bodyID, in: columnID) }
                selectLayers([headingID])
                let title: String = switch page {
                case "Journal": "The Journal"
                case "About": "A more curious world."
                case "Contact": "Let’s talk ideas."
                default: "Lost in the margins?"
                }
                editText(title); textStyle(heading: true)
                let body: String = switch page {
                case "Journal": "THE SPACES BETWEEN\nA doorway, a shared table, a patch of afternoon shade: the places we remember are often made from small invitations. Good design does not simply move people efficiently. It gives them a reason to pause, meet and notice one another.\n\nROOM FOR SURPRISE\nA useful object can be generous without becoming complicated. A handle that fits the hand, a page with room to breathe, a familiar material used in an unexpected way—these are modest decisions with lasting effects. Attention is a practical design tool.\n\nTHE SLOWER ROUTE\nTaking the long way changes what comes into view. A walk without a destination can reveal the rhythm of a neighborhood, the way a season alters the light, or the everyday ingenuity we otherwise hurry past. Curiosity begins when the route stops being the whole point.\n\nThese short field notes are original demonstration writing for Aurora. Browse About for the project’s approach, or return Home to begin again."
                case "About": "Aurora is an independent editorial design study about design, culture and the places that shape us. It is built around a simple idea: thoughtful writing starts with attention, and attention can make an ordinary subject feel newly alive.\n\nThe project favors clear language, useful questions and an unhurried reading experience. Its visual identity pairs a quiet serif voice with a plum, purple and ruby spectrum—an evening atmosphere rather than a collection of effects.\n\nEverything here remains editable: the words, the page structure, the navigation and the native three-stop gradient. The same authored project produces the local browser preview and website export.\n\nAurora is a demonstration, not a claim about an established publication or a reporting team. The Journal contains original short sample essays. Contact explains what is and is not connected. No account, subscription or external service is required to explore the site."
                case "Contact": "A good conversation can start with a question, an overlooked detail or an idea that will not quite leave you alone. Aurora makes room for that kind of curiosity.\n\nThis is a local editorial demonstration. It does not collect contact details, submit messages or send email. No mailbox or contact backend has been configured, and there is no form pretending otherwise.\n\nIf you adapt this project, connect a contact destination you control before publishing. For now, use the real page navigation to read the Journal, learn About Aurora, or return Home. Your exploration stays on this locally generated website."
                default: "This address is not part of Aurora. The page may have moved, or the link may have taken a wrong turn.\n\nUse Home in the navigation to return to the beginning, or open the Journal for a few ideas worth following. The original pages and your authored work have not been removed."
                }
                selectLayers([bodyID])
                editText(body); textStyle(heading: false)
                fillSection(sectionID, minimum: "640")
                convertFlow(sectionID)
                application.popUpButtons["canvas.viewport.preset"].click(); application.menuItems["Mobile"].click()
                selectLayers([sectionID])
                replaceStructuralLayoutField(application.textFields["inspector.layout.container.padding"], with: "24", in: application)
                application.buttons["canvas.zoom.fit"].click()
                attachWindowScreenshot(application, named: "Dark Flow \(page) Mobile real editorial content")
                application.popUpButtons["canvas.viewport.preset"].click(); application.menuItems["Desktop"].click()
            }
            saveDocumentIfModified(in: application)
            application.buttons["canvas.zoom.fit"].click()
            attachWindowScreenshot(application, named: "Dark Flow \(page) saved theme and responsive content")
        }
    }

    // SF-0406-002/006, SF-0507-002: native Select All must be enabled
    // immediately on inline activation, before the first character is typed.
    func testInlineTextNativeSelectAllReplacesExactlyAndCancelPreservesIdentity() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Text at Center", in: application)
        let object = canvasObject(named: "Text object", in: application)
        XCTAssertTrue(object.waitForExistence(timeout: 5))
        let identifier = object.identifier
        let editor = application.textViews["canvas.text.editor"]
        @MainActor func beginInlineEdit() {
            if application.state != .runningForeground { application.activate() }
            XCTAssertTrue(application.wait(for: .runningForeground, timeout: 5))
            let selected = application.descendants(matching: .any)[identifier].firstMatch
            XCTAssertTrue(selected.exists && selected.isSelected)
            // Do not let XCTest discover/reopen a global menu match while
            // AppKit is tracking the Selection menu for this window.
            let selection = application.menuBars.menuBarItems["Selection"]
            selection.click()
            let action = selection.menus.firstMatch.menuItems["Edit Selected Text"]
            XCTAssertTrue(waitForEnabled(action))
            action.click()
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForKeyboardFocus(editor, in: application))
        }
        beginInlineEdit()
        application.menuBars.menuBarItems["Edit"].click()
        let selectAll = application.menuItems["Select All"]
        XCTAssertTrue(selectAll.isEnabled)
        selectAll.click()
        editor.typeText("Exact replacement")
        XCTAssertEqual(editor.value as? String, "Exact replacement")
        editor.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(waitForNonexistence(editor))
        let committed = application.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(waitForValue(committed, containing: "Text: Exact replacement"))
        XCTAssertEqual(canvasObject(named: "Text object", in: application).identifier, identifier)
        beginInlineEdit()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText("Cancelled replacement")
        XCTAssertEqual(editor.value as? String, "Cancelled replacement")
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER native Select All exact inline replacement")
        editor.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(editor))
        XCTAssertTrue(waitForValue(committed, containing: "Text: Exact replacement"))
        XCTAssertEqual(canvasObject(named: "Text object", in: application).identifier, identifier)
        application.buttons["toolbar.undo"].click()
        XCTAssertTrue(waitForValue(committed, containing: "Text: Text"))
        application.buttons["toolbar.redo"].click()
        XCTAssertTrue(waitForValue(committed, containing: "Text: Exact replacement"))
    }

    // SF-0408-003/005/006: hierarchy is semantic, not inferred from flat row frames.
    func testLayersParentAccessibilityTracksNativeNestingInsertionAndHistory() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Stack at Center", in: application)
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let stack = application.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Stack")).firstMatch
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        let stackID = stack.identifier
        componentMenu("Selection", "Clear Selection", in: application)
        componentMenu("Insert", "Insert Text at Center", in: application)
        let texts = application.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text"))
        attachWindowScreenshot(application, named: "Layers parent regression after sibling text insertion")
        XCTAssertTrue(texts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(texts.count, 1)
        let textID = texts.firstMatch.identifier
        let originalValue = try XCTUnwrap(texts.firstMatch.value as? String)
        XCTAssertTrue(originalValue.contains("; Parent: "))
        let originalParent = try XCTUnwrap(originalValue.components(separatedBy: "; Parent: ").last)
        XCTAssertNotEqual(originalParent, "Stack")
        XCTAssertTrue(application.buttons[textID].isSelected)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        application.buttons[stackID].rightClick()
        let nest = application.menuItems["Nest In"]
        XCTAssertTrue(nest.waitForExistence(timeout: 3)); XCTAssertTrue(waitForEnabled(nest))
        nest.click()
        XCTAssertTrue(waitForValue(application.buttons[textID], containing: "; Parent: Stack"))
        XCTAssertTrue(application.buttons[textID].isSelected)
        application.buttons["toolbar.undo"].click()
        XCTAssertTrue(waitForValue(application.buttons[textID], containing: "; Parent: " + originalParent))
        XCTAssertTrue(application.buttons[textID].isSelected)
        application.buttons["toolbar.redo"].click()
        XCTAssertTrue(waitForValue(application.buttons[textID], containing: "; Parent: Stack"))
        XCTAssertTrue(application.buttons[textID].isSelected)
        application.buttons[stackID].click()
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            texts.count == 2
        }, object: nil)], timeout: 5), .completed)
        XCTAssertEqual(texts.count, 2)
        let inserted = try XCTUnwrap(texts.allElementsBoundByIndex.first { $0.identifier != textID })
        XCTAssertTrue(inserted.isSelected)
        XCTAssertTrue((inserted.value as? String)?.contains("; Parent: Stack") == true)
        XCTAssertTrue((application.buttons[textID].value as? String)?.contains("; Parent: Stack") == true)
        attachWindowScreenshot(application, named: "Layers semantic parents after native nesting and insertion")
    }

    // SF-0701-006, SF-0508-002/006: token-row center is a real pointer target.
    func testColorTokenRowCenterSelectsItsOwnEditorAndBinding() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Frame at Center", in: application)
        selectInspectorTab("Design", identifier: "design", in: application)
        for (name, color) in [("First Surface", "#100B1CFF"), ("Second Surface", "#FAF7FFFF")] {
            revealStructuralLayoutControl(application.buttons["inspector.tokens.new"], in: application).click()
            replaceComponentTextField("inspector.tokens.name", with: name, in: application)
            replaceComponentTextField("inspector.tokens.color", with: color, in: application)
            revealStructuralLayoutControl(application.buttons["inspector.tokens.apply"], in: application).click()
        }
        revealStructuralLayoutControl(application.buttons["inspector.tokens.cancel"], in: application).click()
        let first = application.buttons.matching(NSPredicate(format: "label == %@", "Color token First Surface")).firstMatch
        revealStructuralLayoutControl(first, in: application).click()
        XCTAssertEqual(application.textFields["inspector.tokens.name"].value as? String, "First Surface")
        XCTAssertEqual(application.textFields["inspector.tokens.color"].value as? String, "#100B1CFF")
        revealStructuralLayoutControl(application.buttons["inspector.tokens.bind"], in: application).click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.tokens.bindingStatus"], containing: "First Surface"))
        attachWindowScreenshot(application, named: "Token full-row pointer selects exact token")
    }

    func testOwnerDarkFlowTransferSavedProjectToCurrentBuild() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SITEFORGE_OWNER_DARK_FLOW"] == "1",
              let projectPath = environment["SITEFORGE_OWNER_DARK_FLOW_PROJECT"] else {
            throw XCTSkip("Requires explicit owner-session project and isolation storage")
        }
        continueAfterFailure = false
        let project = URL(fileURLWithPath: projectPath)
        XCTAssertEqual(project.lastPathComponent, "Aurora — Dark Flow.siteforge")
        // Resolve the same application-owned private temporary policy as the
        // supported harness before any owner-window transition. The runner
        // need not acquire write access to a Documents checkout for UI state.
        let root = try ApplicationOwnedTestFixture.create("dark-flow-authoring").url
        let ordinary = XCUIApplication(bundleIdentifier: "app.siteforge.SiteForge")
        if ordinary.state != .notRunning {
            ordinary.activate()
            let workspaces = ordinary.windows.matching(NSPredicate(format: "title BEGINSWITH %@", "Aurora — Dark Flow"))
            XCTAssertEqual(ordinary.windows.count, 1, "Do not quit over another owner window or panel")
            XCTAssertEqual(workspaces.count, 1)
            XCTAssertTrue(workspaces.firstMatch.title.hasPrefix("Aurora — Dark Flow"))
            saveDocumentIfModified(in: ordinary)
            XCTAssertTrue(waitForLiveDocumentStatus(in: ordinary, containing: "Saved", timeout: 5))
            ordinary.typeKey("q", modifierFlags: .command)
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            ordinary.state == .notRunning
        }, object: nil)], timeout: 5), .completed)
        let target = XCUIApplication(bundleIdentifier: "app.siteforge.SiteForge.OwnerTesting")
        XCTAssertEqual(target.state, .notRunning, "Never replace an unknown current-build session")
        target.launchArguments = ["-NSTreatUnknownArgumentsAsOpen", "NO", "-ApplePersistenceIgnoreState", "YES",
            "-AppleKeyboardUIMode", "3", "-SiteForgeUITestMode", "YES",
            "-SiteForgeUITestRunID", UUID().uuidString,
            "-SiteForgeUITestDiagnosticPath", root.appendingPathComponent("launch.txt").path,
            "-SiteForgeRecoveryDirectory", root.appendingPathComponent("recovery").path,
            "-SiteForgeRecentProjectsStore", root.appendingPathComponent("recent.json").path,
            "-SiteForgeFileBookmarkStore", root.appendingPathComponent("bookmarks.json").path]
        target.launch(); target.activate()
        XCTAssertTrue(target.buttons["launch.openProject"].waitForExistence(timeout: 5))
        openProjectThroughNativePanel(project, in: target)
        // This owner package includes accumulated persisted history/resources.
        // Use the existing native-package reopen budget (8s), not the blank
        // workspace's 5s budget. The prior trace adopted at the final 5s poll.
        XCTAssertTrue(waitForWorkspaceReady(target, timeout: 8)); assertNormalWindowPolicy(in: target)
        selectStructuralLayer("Section", in: target)
        selectInspectorTab("Design", identifier: "design", in: target)
        attachWindowScreenshot(target, named: "Dark Flow current production build endpoint coverage")
        if ["theme", "site", "content", "flow"].contains(environment["SITEFORGE_OWNER_DARK_FLOW_STAGE"] ?? "") {
            try authorDarkFlowThemeAndFlow(in: target)
            saveDocumentIfModified(in: target)
            target.typeKey("q", modifierFlags: .command)
        } else if environment["SITEFORGE_OWNER_DARK_FLOW_STAGE"] == "review" {
            let output = URL(fileURLWithPath: try XCTUnwrap(environment["SITEFORGE_OWNER_DARK_FLOW_EXPORT"]))
            try reviewOwnerDarkFlow(in: target, project: project, output: output)
        } else if environment["SITEFORGE_OWNER_DARK_FLOW_STAGE"] == "export" {
            let output = URL(fileURLWithPath: try XCTUnwrap(environment["SITEFORGE_OWNER_DARK_FLOW_EXPORT"]))
            try exportOwnerDarkFlow(in: target, output: output)
            target.typeKey("q", modifierFlags: .command)
        } else if environment["SITEFORGE_OWNER_DARK_FLOW_STAGE"] == "browser" {
            let output = URL(fileURLWithPath: try XCTUnwrap(environment["SITEFORGE_OWNER_DARK_FLOW_EXPORT"]))
            try reviewOwnerDarkFlowMobilePreview(in: target)
            target.activate()
            try exportOwnerDarkFlow(in: target, output: output, previewAlreadyOpen: true)
            target.typeKey("q", modifierFlags: .command)
        }
        // The authored package is owner content, not a disposable test fixture.
        // Save and quit normally above; only the isolated session stores are temporary.
    }

    // SF-1207-002/003/005/006: project metadata uses genuine native fields
    // and a single transaction, separate from global appearance preferences.
    // SF-SOURCE-BATCH-20261027-01: acceptance source only; testing held.
    @MainActor
    func testPagesSiteSetupPageIndexingResetAndCancelJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        @MainActor func open() {
            let action = application.buttons["navigator.pages.siteSettings"]
            XCTAssertTrue(waitForHittable(action, in: application)); action.click()
            XCTAssertTrue(application.textFields["siteSettings.siteName"].waitForExistence(timeout: 5))
        }
        @MainActor func reveal(_ identifier: String) -> XCUIElement {
            revealSiteSettingsControl(identifier, in: application)
        }
        open()
        replaceText(in: application.textFields["siteSettings.siteName"], with: "Studio", application: application)
        replaceText(in: application.textFields["siteSettings.titlePattern"], with: "{page} | {site}", application: application)
        let title = reveal("siteSettings.pageTitle")
        replaceText(in: title, with: "Authored browser title", application: application)
        reveal("siteSettings.pageIndexing").click()
        application.menuItems["Discourage indexing"].click()
        XCTAssertTrue(waitForValue(application.staticTexts["siteSettings.previewTitle"], containing: "Authored browser title"))
        attachWindowScreenshot(application, named: "SF-SOURCE-01 local site page draft")
        application.buttons["siteSettings.apply"].click()
        XCTAssertTrue(application.buttons["siteSettings.apply"].waitForNonExistence(timeout: 5))
        open()
        XCTAssertTrue((reveal("siteSettings.pageIndexing").value as? String ?? "").contains("Discourage indexing"))
        reveal("siteSettings.pageReset").click()
        XCTAssertTrue(waitForValue(application.staticTexts["siteSettings.previewSources"], containing: "Uses website default"))
        attachWindowScreenshot(application, named: "SF-SOURCE-01 inherited page reset draft")
        application.typeKey(.escape, modifierFlags: [])
        open()
        XCTAssertEqual(application.textFields["siteSettings.pageTitle"].value as? String, "Authored browser title")
        XCTAssertTrue((reveal("siteSettings.pageIndexing").value as? String ?? "").contains("Discourage indexing"))
        application.typeKey(.escape, modifierFlags: [])
        application.buttons["toolbar.undo"].click()
        open()
        XCTAssertEqual(application.textFields["siteSettings.siteName"].value as? String, "")
        XCTAssertEqual(application.textFields["siteSettings.pageTitle"].value as? String, "")
        application.typeKey(.escape, modifierFlags: [])
    }

    private func revealSiteSettingsControl(_ identifier: String, in application: XCUIApplication) -> XCUIElement {
        let form = application.scrollViews["siteSettings.form"]
        var control = application.descendants(matching: .any)[identifier].firstMatch
        for _ in 0..<12 {
            let visible = form.frame.insetBy(dx: 0, dy: 12)
            if control.isHittable && visible.contains(control.frame) { break }
            form.scroll(byDeltaX: 0, deltaY: control.frame.midY < visible.midY ? 120 : -120)
            control = application.descendants(matching: .any)[identifier].firstMatch
        }
        XCTAssertTrue(control.isHittable)
        XCTAssertTrue(form.frame.contains(control.frame), "Focus must target a fully visible field, not an offscreen AX proxy")
        return control
    }

    func testSiteSettingsMetadataApplyCancelAndUndoJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("File", "Site & Page Settings…", in: application)
        let name = application.textFields["siteSettings.siteName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(in: revealSiteSettingsControl("siteSettings.siteName", in: application), with: "Aurora", application: application)
        replaceText(in: revealSiteSettingsControl("siteSettings.titlePattern", in: application), with: "{page} · {site}", application: application)
        replaceText(in: revealSiteSettingsControl("siteSettings.pageTitle", in: application), with: "Aurora — Coastal Journal", application: application)
        XCTAssertTrue(application.staticTexts["siteSettings.previewTitle"].isHittable)
        attachWindowScreenshot(application, named: "SF-SITE SETTINGS project metadata draft")
        application.buttons["siteSettings.apply"].click()
        XCTAssertTrue(application.buttons["siteSettings.apply"].waitForNonExistence(timeout: 5))
        componentMenu("File", "Site & Page Settings…", in: application)
        XCTAssertEqual(application.textFields["siteSettings.siteName"].value as? String, "Aurora")
        XCTAssertEqual(application.textFields["siteSettings.pageTitle"].value as? String, "Aurora — Coastal Journal")
        replaceText(in: revealSiteSettingsControl("siteSettings.siteName", in: application), with: "Cancelled draft", application: application)
        application.typeKey(.escape, modifierFlags: [])
        componentMenu("File", "Site & Page Settings…", in: application)
        XCTAssertEqual(application.textFields["siteSettings.siteName"].value as? String, "Aurora")
        application.typeKey(.escape, modifierFlags: [])
        componentMenu("Edit", "Undo", in: application)
        componentMenu("File", "Site & Page Settings…", in: application)
        XCTAssertEqual(application.textFields["siteSettings.siteName"].value as? String, "")
        application.typeKey(.escape, modifierFlags: [])
        componentMenu("Edit", "Redo", in: application)
        componentMenu("File", "Site & Page Settings…", in: application)
        XCTAssertEqual(application.textFields["siteSettings.siteName"].value as? String, "Aurora")
        attachWindowScreenshot(application, named: "SF-SITE SETTINGS restored canonical metadata")
        application.typeKey(.escape, modifierFlags: [])
    }

    // SF-1201-002/003/006, SF-1206-003: the shipping menu builds actual
    // website output and opens Safari, not the native canvas snapshot sheet.
    func testWebsitePreviewBuildsAuthoredOutputAndOpensActualSafari() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        let title = application.textFields["inspector.navigation.title"]
        replaceText(in: title, with: "AURORA browser acceptance", application: application)
        title.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.navigation.title", containing: "AURORA browser acceptance"))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER authored Header before Safari")
        let preview = application.buttons["toolbar.preview"]
        XCTAssertTrue(waitForHittable(preview, in: application))
        preview.click()
        let link = application.staticTexts["preview.website.url"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        let address = (link.value as? String) ?? link.label
        let url = try XCTUnwrap(URL(string: address))
        XCTAssertEqual(url.host, "127.0.0.1")
        XCTAssertNotNil(url.port)
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        let foreground = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            safari.state == .runningForeground
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 10), .completed)
        let authoredTitle = safari.webViews.staticTexts["AURORA browser acceptance"].firstMatch
        XCTAssertTrue(authoredTitle.waitForExistence(timeout: 10), safari.debugDescription)
        let browser = XCTAttachment(screenshot: safari.windows.firstMatch.screenshot())
        browser.name = "SF-LOCAL-BUILDER actual Safari authored website"
        browser.lifetime = .keepAlways
        add(browser)
        // Close only the newly opened preview tab while it displays our
        // unique authored title. Never terminate Safari or its other tabs.
        safari.typeKey("w", modifierFlags: .command)
        application.activate()
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER website preview controls")
        application.buttons["Stop"].click()
        XCTAssertFalse(application.staticTexts["preview.website.url"].exists)
        application.buttons["preview.website.done"].click()
        XCTAssertTrue(application.descendants(matching: .any)["canvas.interaction"].exists)
    }

    // SF-0201-002/006, SF-0206-003/006: actual dark editor sections, not a
    // palette-only proof. Website paper/content must remain independently light.
    func testDarkEditorialEditorAndSharedInspectorVisualJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        if application.windows.firstMatch.frame.width >= 1_400 {
            let navigator = application.descendants(matching: .any)["shell.navigator"]
            let inspector = application.descendants(matching: .any)["shell.inspector"]
            let canvas = application.descendants(matching: .any)["canvas.interaction"]
            // Five directly visible destinations require the measured normal
            // pane minima. Keep both panes bounded and reserve the remainder
            // for canvas; the former 300/340 caps forced native overflow.
            XCTAssertGreaterThanOrEqual(navigator.frame.width, 324 - 1)
            XCTAssertLessThanOrEqual(navigator.frame.width, 360 + 1)
            XCTAssertGreaterThanOrEqual(inspector.frame.width, 356 - 1)
            XCTAssertLessThanOrEqual(inspector.frame.width, 420 + 1)
            XCTAssertGreaterThanOrEqual(canvas.frame.width,
                max(500, application.windows.firstMatch.frame.width - 360 - 420 - 2) - 1)
            for prefix in ["navigator.tab.", "inspector.tab."] {
                XCTAssertFalse(application.buttons[prefix + "overflow"].exists)
            }
        }
        attachWindowScreenshot(application, named: "SF-DARK editorial blank")
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        let alignment = application.popUpButtons["inspector.navigation.alignment"]
        XCTAssertTrue(alignment.waitForExistence(timeout: 5))
        XCTAssertEqual(alignment.value as? String, "End", "Inspector must expose the same trailing default as native layout and Safari")
        XCTAssertTrue(application.textFields["inspector.navigation.title"].isHittable)
        attachWindowScreenshot(application, named: "SF-DARK editorial Content section")
        selectInspectorTab("Accessibility", identifier: "accessibility", in: application)
        XCTAssertTrue(application.buttons["inspector.accessibility.reset"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.descendants(matching: .any)["inspector.accessibility.general"].exists)
        attachWindowScreenshot(application, named: "SF-DARK editorial Accessibility section")
        selectInspectorTab("Design", identifier: "design", in: application)
        attachWindowScreenshot(application, named: "SF-DARK editorial Design section")
        application.typeKey(",", modifierFlags: .command)
        let appearance = application.descendants(matching: .any)["settings.sidebar.appearance"]
        XCTAssertTrue(waitForHittable(appearance, in: application))
        appearance.click()
        XCTAssertTrue(application.buttons["settings.appearance.apply"].waitForExistence(timeout: 5))
        XCTAssertEqual((application.radioButtons["Dark"].value as? NSNumber)?.intValue, 1)
        attachWindowScreenshot(application, named: "SF-DARK fixed Settings")
        application.buttons["settings.appearance.close"].click()
        XCTAssertTrue(application.descendants(matching: .any)["canvas.interaction"].exists)
    }

    // SF-0206-006/008, SF-1605-006/008: source acceptance for the shared
    // Settings hierarchy. Execution is reserved for the owner's Prompt-10 gate.
    // SF-0204-006, SF-0206-002/003/006. UNRUN source: global preference
    // drafts remain discoverable without a website; Advanced never autoruns.
    func testWelcomeGlobalSettingsDraftReviewCancelAndFixedGeometryJourney() {
        let application = launchScenario("welcome")
        XCTAssertTrue(application.descendants(matching: .any)["launch.welcome"].waitForExistence(timeout: 5))
        application.typeKey(",", modifierFlags: .command)
        let root = application.descendants(matching: .any)["settings.root"].firstMatch
        XCTAssertTrue(root.waitForExistence(timeout: 5))
        let originalFrame = root.frame
        @MainActor func tab(_ destination: String) {
            let row = application.descendants(matching: .any)["settings.sidebar." + destination].firstMatch
            XCTAssertTrue(waitForHittable(row, in: application)); row.click()
        }
        tab("appearance")
        let originalChoice = ["Follow macOS", "Light", "Dark"].first {
            (application.radioButtons[$0].value as? NSNumber)?.intValue == 1
        }
        XCTAssertNotNil(originalChoice)
        let light = application.radioButtons["Light"]
        XCTAssertTrue(waitForHittable(light, in: application))
        let currentIsLight = (light.value as? NSNumber)?.intValue == 1
        let other = application.radioButtons[currentIsLight ? "Dark" : "Light"]
        other.click()
        XCTAssertTrue(waitForValue(application.staticTexts["settings.drafts.status"], containing: "Appearance"))
        tab("canvas")
        let grid = application.checkBoxes["settings.canvas.gridDefault"]
        XCTAssertTrue(waitForHittable(grid, in: application)); grid.click()
        XCTAssertTrue(waitForValue(application.staticTexts["settings.drafts.status"], containing: "Appearance and Canvas"))
        XCTAssertEqual(root.frame, originalFrame)
        attachWindowScreenshot(application, named: "SF-SOURCE-09 global Settings retains both native preference drafts")
        tab("support")
        XCTAssertTrue(application.buttons["settings.drafts.review.appearance"].exists)
        application.buttons["settings.drafts.review.appearance"].click()
        XCTAssertTrue(application.buttons["settings.appearance.apply"].exists)
        XCTAssertEqual((application.radioButtons[currentIsLight ? "Dark" : "Light"].value as? NSNumber)?.intValue, 1)
        tab("advanced")
        XCTAssertTrue(application.buttons["settings.testing.full"].exists)
        XCTAssertTrue(application.buttons["settings.testing.ui"].exists)
        // Do not press either testing action. An enclosing owner-local run may
        // already have a report, so its presence is not evidence of an autorun.
        XCTAssertFalse(application.descendants(matching: .any)["workspace.shell"].exists)
        XCTAssertEqual(root.frame, originalFrame)
        attachWindowScreenshot(application, named: "SF-SOURCE-09 Advanced remains manual and independent of a project")
        application.buttons["settings.drafts.cancel"].click()
        XCTAssertFalse(application.staticTexts["settings.drafts.status"].exists)
        tab("appearance")
        XCTAssertTrue(waitForValue(application.staticTexts["settings.appearance.status"], containing: "cancelled"))
        let original = application.radioButtons[originalChoice ?? "Dark"]
        XCTAssertEqual((original.value as? NSNumber)?.intValue, 1)
        tab("canvas")
        XCTAssertFalse(application.buttons["settings.canvas.apply"].isEnabled)
        XCTAssertEqual(root.frame, originalFrame)
        attachWindowScreenshot(application, named: "SF-SOURCE-09 cancelled global drafts retain fixed Settings geometry")
        application.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(application.descendants(matching: .any)["launch.welcome"].exists)
    }

    func testConceptAlignedSettingsSidebarAndInheritedAccessibilityJourney() {
        let application = launchWorkspace()
        application.typeKey(",", modifierFlags: .command)
        let sidebar = application.descendants(matching: .any)["settings.sidebar"]
        let content = application.descendants(matching: .any)["settings.content"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(content.exists)
        XCTAssertLessThanOrEqual(sidebar.frame.maxX, content.frame.minX + 1,
                                 "Settings categories belong in the left sidebar")
        for destination in ["appearance", "canvas", "accessibility", "defaults", "updates", "support", "advanced"] {
            let category = application.descendants(matching: .any)["settings.sidebar.\(destination)"]
            XCTAssertTrue(waitForHittable(category, in: application))
            category.click()
            XCTAssertTrue(content.exists)
            if destination == "accessibility" {
                for preference in ["transparency", "contrast", "motion"] {
                    XCTAssertTrue(application.descendants(matching: .any)["settings.accessibility.\(preference)"].exists)
                }
                XCTAssertFalse(application.checkBoxes["settings.accessibility.transparency"].exists,
                               "Inherited macOS settings must not appear as app-authored overrides")
            }
            attachWindowScreenshot(application, named: "SF-PRODUCT-UI-008 Settings \(destination)")
        }
    }

    // SF-0206-002/004/006 — real native application preference-group reset.
    func testApplicationSettingsGroupResetCancelRestoreAndRelaunchJourney() {
        let application = launchWorkspace()
        let grid = application.descendants(matching: .any)["canvas.grid.toggle"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        application.typeKey(",", modifierFlags: .command)
        @MainActor func tab(_ name: String) {
            let identifier = "settings.sidebar.\(name.lowercased())"
            let item = application.descendants(matching: .any)[identifier]
            XCTAssertTrue(waitForHittable(item, in: application), application.debugDescription)
            item.click()
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
        let originalAppearanceDefault = (application.buttons["settings.appearance.reset"].value as? String) == "Already default"
        if originalAppearance != "Dark" { application.radioButtons["Dark"].click() }
        if application.buttons["settings.appearance.apply"].isEnabled {
            application.buttons["settings.appearance.apply"].click()
        }
        tab("Canvas")
        let canvasSetting = application.checkBoxes["settings.canvas.gridDefault"]
        XCTAssertTrue(canvasSetting.waitForExistence(timeout: 5))
        let originalCanvas = isOn(canvasSetting)
        let originalCanvasDefault = (application.buttons["settings.canvas.reset"].value as? String) == "Already default"
        if isOn(canvasSetting) { canvasSetting.click() }
        if application.buttons["settings.canvas.apply"].isEnabled {
            application.buttons["settings.canvas.apply"].click()
        }

        tab("Defaults")
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
        tab("Defaults")
        XCTAssertFalse(application.buttons["settings.group.confirm"].exists)
        XCTAssertTrue((application.staticTexts["settings.group.status"].value as? String)?.contains("cancelled") == true)
        stage.click()
        application.buttons["settings.group.confirm"].click()
        XCTAssertTrue((application.staticTexts["settings.group.status"].value as? String)?.contains("reset") == true)
        capture("SF-AUTHORING-065 application defaults reset")
        tab("Appearance")
        XCTAssertEqual((application.radioButtons["Dark"].value as? NSNumber)?.intValue, 1)
        tab("Canvas")
        XCTAssertTrue(isOn(application.checkBoxes["settings.canvas.gridDefault"]))
        tab("Defaults")
        application.buttons["settings.group.restore"].click()
        XCTAssertTrue((application.staticTexts["settings.group.status"].value as? String)?.contains("restored") == true)
        capture("SF-AUTHORING-065 previous defaults restored")
        tab("Appearance")
        XCTAssertEqual((application.radioButtons["Dark"].value as? NSNumber)?.intValue, 1)
        tab("Canvas")
        XCTAssertFalse(isOn(application.checkBoxes["settings.canvas.gridDefault"]))

        tab("Defaults")
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
        XCTAssertEqual((application.radioButtons["Dark"].value as? NSNumber)?.intValue, 1)
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
        let canvasTab = application.descendants(matching: .any)["settings.sidebar.canvas"]
        XCTAssertTrue(waitForHittable(canvasTab, in: application), application.debugDescription)
        canvasTab.click()
        let setting = application.checkBoxes["settings.canvas.gridDefault"]
        XCTAssertTrue(setting.waitForExistence(timeout: 5), application.debugDescription)
        let originalPreference = isOn(setting)
        let originalWasDefault = (application.buttons["settings.canvas.reset"].value as? String) == "Already default"

        @MainActor func screenshot(_ name: String, window: XCUIElement) {
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let settingsWindow = application.windows.containing(.checkBox, identifier: "settings.canvas.gridDefault").firstMatch
        XCTAssertTrue(settingsWindow.exists)
        screenshot("SF-AUTHORING-064 Canvas Settings initial", window: settingsWindow)
        let targetPreference = !originalPreference
        setting.click()
        XCTAssertEqual(isOn(setting), targetPreference)
        XCTAssertTrue(application.buttons["settings.canvas.apply"].isEnabled)
        XCTAssertTrue(isOn(grid) == originalSceneGrid)
        screenshot("SF-AUTHORING-064 Canvas Settings draft", window: settingsWindow)
        application.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertEqual(isOn(application.checkBoxes["settings.canvas.gridDefault"]), originalPreference)
        XCTAssertFalse(application.buttons["settings.canvas.apply"].isEnabled)
        application.checkBoxes["settings.canvas.gridDefault"].click()
        XCTAssertTrue(application.buttons["settings.canvas.apply"].isEnabled)
        application.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        XCTAssertEqual(isOn(application.checkBoxes["settings.canvas.gridDefault"]), targetPreference)
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
        XCTAssertEqual(isOn(freshGrid), targetPreference)
        screenshot("SF-AUTHORING-064 new workspace inherits Grid preference", window: application.windows.firstMatch)
        freshGrid.click()
        XCTAssertEqual(isOn(application.descendants(matching: .any)["canvas.grid.toggle"]), !targetPreference)
        screenshot("SF-AUTHORING-064 live workspace toggled Grid", window: application.windows.firstMatch)

        application.typeKey(",", modifierFlags: .command)
        let restoredCanvasTab = application.descendants(matching: .any)["settings.sidebar.canvas"]
        XCTAssertTrue(waitForHittable(restoredCanvasTab, in: application))
        restoredCanvasTab.click()
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
        XCTAssertEqual((application.buttons["settings.canvas.reset"].value as? String) == "Already default", originalWasDefault)
    }

    // SF-0206-002/003/004/006/008 — real native Settings, no document hooks.
    func testSelectedReferencesLightSettingsPreviewAndRestoreVisualJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        application.typeKey(",", modifierFlags: .command)
        let appearance = application.descendants(matching: .any)["settings.sidebar.appearance"]
        XCTAssertTrue(waitForHittable(appearance, in: application)); appearance.click()
        let light = application.radioButtons["Light"]
        XCTAssertTrue(waitForHittable(light, in: application))
        light.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate:
            NSPredicate { _, _ in
                let live = application.radioButtons["Light"]
                return live.exists && (live.isSelected || (live.value as? NSNumber)?.boolValue == true)
            }, object: nil)], timeout: 5) == .completed)
        XCTAssertTrue(waitForValue(application.staticTexts["settings.appearance.status"], containing: "preview"))
        for destination in ["appearance", "canvas", "accessibility", "defaults", "updates", "support"] {
            let live = application.descendants(matching: .any)["settings.sidebar." + destination]
            XCTAssertTrue(waitForHittable(live, in: application)); live.click()
            XCTAssertTrue(application.descendants(matching: .any)["settings.content"].exists)
            attachWindowScreenshot(application, named: "SF-UI-009 light Settings " + destination)
        }
        let restore = application.descendants(matching: .any)["settings.sidebar.appearance"]
        XCTAssertTrue(waitForHittable(restore, in: application)); restore.click()
        let cancel = application.buttons["settings.appearance.cancel"]
        XCTAssertTrue(waitForHittable(cancel, in: application)); cancel.click()
        XCTAssertFalse(application.buttons["settings.appearance.apply"].isEnabled)
        application.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
    }

    func testFixedSettingsSharesCardWidthTitlebarClearanceAndReopenGeometryJourney() {
        let application = launchScenario("welcome")
        application.typeKey(",", modifierFlags: .command)
        let settings = application.windows["SiteForge Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        let visibleFrame = try! XCTUnwrap(NSScreen.main?.visibleFrame)
        let expectedWidth = min(970, visibleFrame.width - 16)
        XCTAssertEqual(settings.frame.width, expectedWidth, accuracy: 1)
        let initialSize = settings.frame.size
        let expectedFormWidth = min(680, expectedWidth - 250 - 40)
        for destination in ["appearance", "canvas", "accessibility", "defaults", "updates", "support", "advanced"] {
            let row = settings.descendants(matching: .any)["settings.sidebar." + destination]
            XCTAssertTrue(waitForHittable(row, in: application)); row.click()
            let form = settings.descendants(matching: .any)["settings.form"]
            XCTAssertTrue(form.waitForExistence(timeout: 5))
            XCTAssertEqual(settings.frame.size, initialSize)
            // SwiftUI's semantic form group reports its children's union,
            // excluding visual page insets. Assert the actual card geometry.
            XCTAssertGreaterThanOrEqual(form.frame.width, expectedFormWidth - 48)
            XCTAssertGreaterThanOrEqual(row.frame.minY, settings.frame.minY + 28)
            XCTAssertEqual(settings.splitGroups.count, 0, "Settings has no collapsible or resizable split divider")
            XCTAssertEqual(settings.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).count, 0)
            let cards = settings.descendants(matching: .any).matching(identifier: "settings.card").allElementsBoundByIndex
            XCTAssertFalse(cards.isEmpty, destination)
            for card in cards {
                XCTAssertEqual(card.frame.width, expectedFormWidth - 48, accuracy: 1, destination)
                XCTAssertEqual(card.frame.midX, settings.frame.minX + 250 + (expectedWidth - 250) / 2, accuracy: 2, destination)
            }
            let capture = XCTAttachment(screenshot: settings.screenshot())
            capture.name = "SF-UI-010 fixed Settings " + destination
            capture.lifetime = .keepAlways; add(capture)
        }
        application.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForNonexistence(settings))
        application.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        XCTAssertEqual(settings.frame.size, initialSize)
        let reopened = XCTAttachment(screenshot: settings.screenshot())
        reopened.name = "SF-UI-010 fixed Settings reopened"; reopened.lifetime = .keepAlways; add(reopened)
    }

    func testOwnerLocalSettingsAndCenteredEmptyCanvasUseRealControlsJourney() {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        let viewport = application.descendants(matching: .any)["canvas.viewport.surface"]
        for (prefix, region, destinations) in [
            ("navigator.tab.", "shell.navigator", ["pages", "layers", "elements", "assets", "components"]),
            ("inspector.tab.", "shell.inspector", ["design", "layout", "content", "interactions", "accessibility"])
        ] {
            for destination in destinations {
                let control = application.buttons[prefix + destination]
                XCTAssertTrue(waitForHittable(control, in: application), destination)
                assertElement(control, isContainedIn: application.descendants(matching: .any)[region], destination)
            }
        }
        let hint = application.descendants(matching: .any)["canvas.empty.hint"]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertTrue(viewport.exists)
        XCTAssertEqual(hint.frame.midX, viewport.frame.midX, accuracy: 2)
        XCTAssertEqual(hint.frame.midY, viewport.frame.midY, accuracy: 2)
        XCTAssertLessThan(hint.frame.width, viewport.frame.width)
        XCTAssertLessThan(hint.frame.height, viewport.frame.height / 2)
        viewport.coordinate(withNormalizedOffset: .init(dx: 0.1, dy: 0.1)).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "interactions 1", timeout: 5))
        attachWindowScreenshot(application, named: "SF-UI-009 compact toolbar centered empty canvas")
        let insert = application.buttons["canvas.empty.insert.frame"]
        XCTAssertTrue(waitForHittable(insert, in: application)); insert.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertTrue(hint.waitForNonExistence(timeout: 5))
        attachWindowScreenshot(application, named: "SF-UI-009 paired Inspector real Frame")
        application.typeKey(",", modifierFlags: .command)
        let advanced = application.descendants(matching: .any)["settings.sidebar.advanced"]
        XCTAssertTrue(waitForHittable(advanced, in: application)); advanced.click()
        XCTAssertTrue(application.buttons["settings.testing.full"].exists)
        XCTAssertTrue(application.buttons["settings.testing.ui"].exists)
        // An ordinary test build has no owner-local provision; do not pretend
        // it contains a runnable development harness or trigger a nested suite.
        XCTAssertFalse(application.buttons["settings.testing.full"].isEnabled)
        XCTAssertFalse(application.buttons["settings.testing.ui"].isEnabled)
        XCTAssertFalse(application.checkBoxes["settings.experimental.enabled"].exists)
        attachWindowScreenshot(application, named: "SF-UI-009 Advanced truthful unavailable harness")
        application.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(application.windows.containing(.button, identifier: "settings.testing.full")
            .firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(application.descendants(matching: .any)["settings.sidebar.updates"].waitForExistence(timeout: 5))
        application.descendants(matching: .any)["settings.sidebar.updates"].click()
        XCTAssertFalse(application.descendants(matching: .any)["settings.updates.channel"].exists)
        attachWindowScreenshot(application, named: "SF-UI-009 Updates fixed policy")
    }

    func testNativeSaveAsUpdatesLiveDocumentWindowTitleJourney() {
        let application = launchWorkspace()
        let insert = application.buttons["canvas.empty.insert.frame"]
        XCTAssertTrue(waitForHittable(insert, in: application)); insert.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(application.menuItems["Save As…"].isEnabled)
        application.menuItems["Save As…"].click()
        let name = application.textFields["saveAsNameTextField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(in: name, with: "Native Title Regression", application: application)
        application.typeKey("g", modifierFlags: [.command, .shift])
        let path = application.textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        replaceText(in: path, with: fixtureRoot.path, application: application)
        path.typeKey(.return, modifierFlags: [])
        let save = application.buttons["OKButton"]
        XCTAssertTrue(waitForHittable(save, in: application)); save.click()
        XCTAssertTrue(waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 5), application.debugDescription)
        attachWindowScreenshot(application, named: "SF-UI-009 native Save As title diagnostic")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            application.windows["Native Title Regression"].exists
        }, object: nil)], timeout: 5), .completed, "Durable Save As must publish the live clean document title. \(application.windows.firstMatch.debugDescription)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureRoot.appendingPathComponent("Native Title Regression.siteforge").path))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        attachWindowScreenshot(application, named: "SF-UI-009 native Save As live clean title")
        // Native File commands remain usable after the last document closes;
        // reopening must adopt a new live scene, not a retained closed state.
        application.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForNonexistence(application.windows["Native Title Regression"]))
        application.menuBars.menuBarItems["File"].click()
        XCTAssertTrue(application.menuItems["Open…"].isEnabled)
        application.menuItems["Open…"].click()
        application.typeKey("g", modifierFlags: [.command, .shift])
        let reopenPath = application.textFields["PathTextField"]
        XCTAssertTrue(reopenPath.waitForExistence(timeout: 5))
        replaceText(in: reopenPath, with: fixtureRoot.appendingPathComponent("Native Title Regression.siteforge").path, application: application)
        reopenPath.typeKey(.return, modifierFlags: [])
        let open = application.buttons["OKButton"]
        XCTAssertTrue(waitForHittable(open, in: application)); open.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertTrue(waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 5))
        XCTAssertTrue(application.windows["Native Title Regression"].exists)
        attachWindowScreenshot(application, named: "SF-UI-009 native last-window Open adopts reopened document")
    }

    func testNativeSelectAllInPageEditorReplacesDefaultDraftJourney() {
        let application = launchWorkspace()
        application.menuBars.menuBarItems["Page"].click()
        application.menuItems["New Page…"].click()
        let name = application.textFields["page.editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.click()
        XCTAssertTrue(waitForKeyboardFocus(identifier: "page.editor.name", in: application))
        application.menuBars.menuBarItems["Edit"].click()
        XCTAssertTrue(application.menuItems["Select All"].isEnabled)
        application.menuItems["Select All"].click()
        name.typeText("About")
        XCTAssertEqual(application.textFields["page.editor.name"].value as? String, "About")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        application.buttons["canvas.empty.insert.frame"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let width = application.textFields["inspector.layout.width"]
        XCTAssertTrue(width.waitForExistence(timeout: 5)); width.click()
        XCTAssertTrue(waitForKeyboardFocus(identifier: "inspector.layout.width", in: application))
        width.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(identifier: "inspector.layout.height", in: application))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Default · Desktop"))
        application.textFields["inspector.layout.height"].typeKey(.tab, modifierFlags: .shift)
        XCTAssertTrue(waitForKeyboardFocus(identifier: "inspector.layout.width", in: application))
        width.typeKey("a", modifierFlags: .command); width.typeText("320")
        width.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "320"))
        focusDocumentCommands(in: application)
        application.menuBars.menuBarItems["Edit"].click(); application.menuItems["Undo"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "240"))
    }

    func testApplicationAppearanceSettingsPreviewApplyCancelResetJourney() {
        let application = launchWorkspace()
        application.typeKey(",", modifierFlags: .command)
        @MainActor func showAppearanceTab() {
            let tab = application.descendants(matching: .any)["settings.sidebar.appearance"]
            XCTAssertTrue(waitForHittable(tab, in: application))
            tab.click()
        }
        showAppearanceTab()
        let apply = application.buttons["settings.appearance.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        let originalWasDefault = (application.buttons["settings.appearance.reset"].value as? String) == "Already default"
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
                let live = application.descendants(matching: .any)[identifier]
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
        awaitText("settings.appearance.reset", "Already default")
        func capture(_ name: String) {
            let window = application.windows.containing(.button, identifier: "settings.appearance.apply").firstMatch
            XCTAssertTrue(window.exists)
            // The production Settings redesign uses a readable two-column
            // NavigationSplitView. Keep the sidebar and detail pane available
            // instead of forcing the obsolete compact toolbar width.
            XCTAssertGreaterThanOrEqual(window.frame.width, 820)
            let attachment = XCTAttachment(screenshot: window.screenshot())
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        choose("Light") // The owner-selected default is Dark; preview an actual change.
        XCTAssertTrue(application.buttons["settings.appearance.apply"].isEnabled)
        awaitText("settings.appearance.status", "preview")
        capture("SF-SETTINGS light preview from dark default")
        application.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertFalse(application.buttons["settings.appearance.apply"].isEnabled)
        choose("Light")
        application.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        awaitText("settings.appearance.status", "saved")
        awaitText("settings.appearance.reset", "Reset available")
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
        awaitText("settings.appearance.reset", "Already default")
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
        awaitText("settings.appearance.reset", "Reset available")
        capture("SF-SETTINGS persisted after relaunch")
    }

    // SF-0206-004/006/008, SF-1507-003/004/006, SF-1602-004/006,
    // SF-1607-002/003/004/006/008 — native, content-free support workflow.
    func testSupportSettingsGeneratesReviewableRedactedReportJourney() {
        let application = launchWorkspace()
        application.typeKey(",", modifierFlags: .command)
        let supportTab = application.descendants(matching: .any)["settings.sidebar.support"]
        XCTAssertTrue(waitForHittable(supportTab, in: application), application.debugDescription)
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
        XCTAssertGreaterThanOrEqual(window.frame.width, 820)
        XCTAssertLessThanOrEqual(window.frame.width, XCUIScreen.main.screenshot().image.size.width)
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = "SF-AUTHORING-104 Support Settings redacted report"
        attachment.lifetime = .keepAlways
        add(attachment)

        copy.click()
        let status = application.staticTexts["settings.support.status"]
        XCTAssertTrue((status.value as? String)?.contains("copied") == true)
    }

    private static let applicationBundleIdentifier = Bundle(for: SiteForgeLaunchTests.self)
        .object(forInfoDictionaryKey: "SiteForgeTestApplicationIdentifier") as? String ?? "app.siteforge.SiteForge"
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

        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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

        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        XCTAssertTrue((xField.value as? String)?.contains("Set here · Desktop") == true)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        XCTAssertTrue(application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
            .firstMatch.exists)
        XCTAssertFalse(beforeEscape.isEmpty)
        attachScreenshot(named: "SF-AUTHORING-006 cancelled selection scope")
        XCTAssertTrue(application.buttons["toolbar.undo"].isEnabled)
    }

    // SF-0505-001...006/008 — native base sizing edits share the geometry
    // transaction and never replace the selected Frame with an editor proxy.
    func testContextualEssentialsEditLinkedButtonWithoutInspectorTabSwitchesJourney() throws {
        let application = launchWorkspace()
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.button"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let identity = canvasObject(named: "Button", in: application).identifier
        selectInspectorTab("Design", identifier: "design", in: application)
        XCTAssertTrue(application.descendants(matching: .any)["inspector.essentials"].firstMatch.waitForExistence(timeout: 5))
        replaceStructuralLayoutField(application.textFields["inspector.content.control.label"], with: "Read the journal", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.essentials.label.status"], containing: "label committed"))
        replaceStructuralLayoutField(application.textFields["inspector.layout.width"], with: "260", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.layout.height"], with: "52", in: application)
        attachWindowScreenshot(application, named: "SF-WORKFLOW Essentials label and size on Design")
        let type = revealStructuralLayoutControl(application.popUpButtons["inspector.interactions.link.type"], in: application)
        type.click(); application.menuItems["External HTTP(S)"].click()
        replaceStructuralLayoutField(application.textFields["inspector.interactions.link.url"], with: "https://example.com/journal", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.essentials.target.status"], containing: "target committed"))
        attachWindowScreenshot(application, named: "SF-WORKFLOW Essentials native destination on Design")
        replaceStructuralLayoutField(application.textFields["inspector.interactions.link.url"], with: "javascript:invalid", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.essentials.target.status"], containing: "HTTP or HTTPS"))
        application.textFields["inspector.interactions.link.url"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.interactions.link.url"], containing: "https://example.com/journal"))
        application.buttons["toolbar.undo"].click()
        XCTAssertTrue(waitForValue(application.popUpButtons["inspector.interactions.link.type"], containing: "No target"))
        application.buttons["toolbar.redo"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.interactions.link.url"], containing: "https://example.com/journal"))
        XCTAssertTrue(application.buttons["inspector.tab.design"].isSelected)
        XCTAssertEqual(canvasObject(named: "Button", in: application).identifier, identity,
            "The Layers/object name is independent of the authored control label")
        XCTAssertTrue(waitForValue(application.textFields["inspector.content.control.label"], containing: "Read the journal"))
        attachWindowScreenshot(application, named: "SF-WORKFLOW Essentials exact redo and selection")
    }

    func testNativeFillHugSizingModesPreserveIdentityUndoAndComputedGeometryJourney() throws {
        let application = launchWorkspace()
        application.buttons["canvas.empty.insert.text"].click()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        selectInspectorTab("Layout", identifier: "layout", in: application)
        let selected = application.descendants(matching: .any)["status.selectionPath"].firstMatch.label
        let height = revealStructuralLayoutControl(application.descendants(matching: .any)["inspector.sizing.heightMode"].firstMatch, in: application)
        height.click()
        application.menuItems["Fit content"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.height"], containing: "Computed by Hug"))
        XCTAssertFalse(application.textFields["inspector.layout.height"].isEnabled)
        attachWindowScreenshot(application, named: "SF-WORKFLOW Text intrinsic Hug height")
        let width = revealStructuralLayoutControl(application.descendants(matching: .any)["inspector.sizing.widthMode"].firstMatch, in: application)
        width.click()
        application.menuItems["Fill available space"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Computed by Fill"))
        XCTAssertFalse(application.textFields["inspector.layout.width"].isEnabled)
        XCTAssertEqual(application.descendants(matching: .any)["status.selectionPath"].firstMatch.label, selected)
        attachWindowScreenshot(application, named: "SF-WORKFLOW Text containing-width Fill")
        application.buttons["toolbar.undo"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "120"))
        XCTAssertTrue(application.textFields["inspector.layout.width"].isEnabled)
        application.buttons["toolbar.redo"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Computed by Fill"))
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
    }

    func testPracticalResponsiveSizingConversionWinnerResetAndDraftJourney() throws {
        let project = fixtureRoot.appendingPathComponent("practical-responsive-sizing.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        let frame = canvasObject(named: "Frame", in: application).identifier
        componentMenu("Insert", "Insert Text at Center", in: application)
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let layer = "navigator.layer." + frame.replacingOccurrences(of: "canvas.object.", with: "")
        revealComponentPointerTarget(layer, in: application).click()
        selectInspectorTab("Layout", identifier: "layout", in: application)
        let conversionID = "inspector.sizing.convertContent"
        revealComponentPointerTarget(conversionID, in: application).click()
        let confirm = application.sheets.firstMatch.buttons["Convert to automatic sizing"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "240"))
        revealComponentPointerTarget(conversionID, in: application).click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3)); confirm.click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Computed by Fill"))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-003 automatic sizing and adjacent dimensions")
        let presetID = "canvas.viewport.preset"
        revealComponentPointerTarget(presetID, in: application).click(); application.menuItems["Mobile"].click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        replaceStructuralLayoutField(application.textFields["inspector.layout.width"], with: "180", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "180"))
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.sizing.widthMode.source"], containing: "Exact size"))
        XCTAssertTrue(application.buttons[layer].isSelected)
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-003 Mobile explicit width winner")
        revealComponentPointerTarget("inspector.sizing.width.resetOverride", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Computed by Fill"))
        // Document history is distinct from the still-focused numeric editor.
        application.textFields["inspector.layout.width"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.buttons[layer].isSelected)
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "180"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Computed by Fill"))
        let x = "inspector.layout.x"
        let committedX = try XCTUnwrap(application.textFields[x].value as? String)
        replaceComponentTextField(x, with: "-", in: application)
        revealComponentPointerTarget(presetID, in: application).click(); application.menuItems["Tablet"].click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        XCTAssertTrue(application.staticTexts["inspector.layout.validation"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)[presetID], containing: "Mobile"))
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "workspace.editBoundary.status", containing: "paused"))
        XCTAssertTrue(waitForValue(application.textFields[x], containing: "-"))
        _ = revealComponentPointerTarget(x, in: application)
        let liveX = application.textFields[x]
        liveX.click()
        XCTAssertTrue(waitForKeyboardFocus(liveX, in: application), "The retained editor must actually regain focus before Escape")
        liveX.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse((application.textFields[x].value as? String) == "-")
        let restored = waitForValue(application.textFields[x], containing: committedX)
        if !restored {
            attachWindowScreenshot(application, named: "Sizing Escape did not restore committed input")
            let diagnostic = XCTAttachment(string: launchLifecycleDiagnostics(for: application))
            diagnostic.name = "Sizing cancellation lifecycle"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        }
        XCTAssertTrue(restored, "Escape must restore the committed value, not recreate a retained draft")
        revealComponentPointerTarget(presetID, in: application).click(); application.menuItems["Tablet"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)[presetID], containing: "Tablet"))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-003 context-safe draft cancellation and Tablet fit")
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("responsive-sizing-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        revealComponentPointerTarget(layer, in: application).click()
        selectInspectorTab("Layout", identifier: "layout", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Computed by Fill"))
        XCTAssertTrue(application.buttons[layer].isSelected)
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-003 responsive sizing saved and reopened")
    }

    func testNativeSizingConstraintsClampResetAndAccessibilityJourney() throws {
        let application = launchWorkspace()
        application.buttons["canvas.empty.insert.frame"].click()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        selectInspectorTab("Layout", identifier: "layout", in: application)
        let boundsControl = application.descendants(matching: .any)["inspector.sizing.boundsDisclosure"]
        XCTAssertTrue(boundsControl.waitForExistence(timeout: 5))
        let bounds = revealStructuralLayoutControl(boundsControl, in: application)
        XCTAssertTrue(bounds.isEnabled)
        bounds.click()
        XCTAssertTrue(waitForDisclosureExpanded(application.descendants(matching: .any)["inspector.sizing.boundsDisclosure"]))
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
        selectInspectorTab("Layout", identifier: "layout", in: application)
        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        let xField = application.textFields["inspector.layout.x"]
        XCTAssertTrue(xField.waitForExistence(timeout: 5))
        XCTAssertTrue((xField.value as? String)?.contains("Desktop") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-016 Desktop base inherited geometry")

        preset.click(); application.menuItems["Tablet"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Tablet"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Uses Desktop"))
        let tabletX = application.textFields["inspector.layout.x"]
        XCTAssertTrue(tabletX.waitForExistence(timeout: 3))
        XCTAssertTrue(tabletX.isEnabled, "An inherited responsive value must remain editable when its selected node is clipped by the artboard.")
        tabletX.doubleClick()
        tabletX.typeKey("a", modifierFlags: .command); tabletX.typeText("48"); tabletX.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Set here · Tablet"))
        XCTAssertTrue(application.buttons["inspector.layout.resetBreakpointOverrides"].isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-016 Tablet authored override")

        preset.click(); application.menuItems["Mobile"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Mobile"))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.selectionPath"],
                                   containing: "1 selected; primary selection present; selection outside Mobile artboard"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Uses Desktop"))
        let width = application.textFields["inspector.layout.width"]
        XCTAssertTrue(width.waitForExistence(timeout: 3))
        XCTAssertTrue(width.isEnabled)
        width.doubleClick()
        width.typeKey("a", modifierFlags: .command); width.typeText("320"); width.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Set here · Mobile"))
        let mobileX = application.textFields["inspector.layout.x"]
        XCTAssertTrue(mobileX.isEnabled)
        mobileX.doubleClick()
        mobileX.typeKey("a", modifierFlags: .command); mobileX.typeText("24"); mobileX.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Set here · Mobile"))
        XCTAssertFalse((application.descendants(matching: .any)["status.selectionPath"].value as? String)?
            .contains("outside Mobile artboard") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-016 Mobile authored override")

        let reset = application.buttons["inspector.layout.resetBreakpointOverrides"]
        XCTAssertTrue(reset.isHittable); reset.click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Uses Desktop"))
        XCTAssertFalse(application.buttons["inspector.layout.resetBreakpointOverrides"].isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-016 Mobile reset inheritance")

        preset.click(); application.menuItems["Tablet"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Set here · Tablet"))
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Set here · Mobile") ||
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
            _ = revealStructuralLayoutControl(element, in: application)
        }
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.stack"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        for count in 2...3 {
            application.menuBars.menuBarItems["Insert"].click()
            application.menuItems["Insert Frame at Center"].click()
            XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects \(count)", timeout: 5))
            selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
            let stackRow = application.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Stack"
            )).firstMatch
            XCTAssertTrue(stackRow.waitForExistence(timeout: 3)); stackRow.click()
        }
        selectInspectorTab("Layout", identifier: "layout", in: application)
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
        replaceStructuralLayoutField(gap, with: "8", in: application)
        XCTAssertTrue(waitForValue(gap, containing: "Set here · Mobile"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 Mobile Stack override")

        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let frameRow = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"
        )).firstMatch
        XCTAssertTrue(frameRow.waitForExistence(timeout: 3))
        let selectedFrameIdentifier = frameRow.identifier
        XCTAssertTrue(selectedFrameIdentifier.hasPrefix("navigator.layer.")); frameRow.click()
        selectInspectorTab("Layout", identifier: "layout", in: application)
        let visibility = application.descendants(matching: .any)["inspector.layout.visibility"]
        XCTAssertTrue(visibility.waitForExistence(timeout: 3)); reveal(visibility); XCTAssertTrue(visibility.isEnabled)
        visibility.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertFalse(application.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "canvas.selection.")
        ).firstMatch.exists, "A hidden breakpoint object must not retain canvas chrome")
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let hiddenFrameRow = application.descendants(matching: .any)[selectedFrameIdentifier]
        XCTAssertTrue(waitForValue(hiddenFrameRow, containing: "Hidden at current breakpoint"))
        XCTAssertTrue(waitForHittable(hiddenFrameRow, in: application))
        hiddenFrameRow.click()
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 Mobile hidden Layers inspection")

        selectInspectorTab("Layout", identifier: "layout", in: application)
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
        componentMenu("Insert", "Insert Grid at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 4", timeout: 5))
        for count in 5...6 {
            application.menuBars.menuBarItems["Insert"].click()
            application.menuItems["Insert Frame at Center"].click()
            XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects \(count)", timeout: 5))
            selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
            let gridRow = application.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Grid"
            )).firstMatch
            XCTAssertTrue(gridRow.waitForExistence(timeout: 3)); gridRow.click()
        }
        selectInspectorTab("Layout", identifier: "layout", in: application)
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.announcement",
            containing: "Container layout inactive"
        ), "Selecting a different container at another breakpoint must not retain stale operation feedback")
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.visibility.announcement",
            containing: "Breakpoint visibility inactive"
        ), "Breakpoint visibility feedback must stay scoped to the selection and breakpoint that produced it")
        attachWindowScreenshot(application, named: "SF-AUTHORING-018 Desktop Stack Grid base layout")
        preset.click(); application.menuItems["Tablet"].click()
        let columns = application.textFields["inspector.layout.container.columns"]
        XCTAssertTrue(columns.waitForExistence(timeout: 3)); reveal(columns)
        replaceStructuralLayoutField(columns, with: "1", in: application)
        XCTAssertTrue(waitForValue(columns, containing: "Set here · Tablet"))
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.announcement",
            containing: "Columns committed"
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
        selectInspectorTab("Layout", identifier: "layout", in: application)
        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        preset.click(); application.menuItems["Tablet"].click()
        let xField = application.textFields["inspector.layout.x"]
        XCTAssertTrue(xField.waitForExistence(timeout: 3))
        xField.doubleClick(); xField.typeKey("a", modifierFlags: .command)
        xField.typeText("48"); xField.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(xField, containing: "Set here · Tablet"))

        let compare = application.buttons["canvas.viewport.compare"]
        XCTAssertTrue(waitForHittable(compare, in: application)); compare.click()
        XCTAssertTrue(application.descendants(matching: .any)["responsive.compare.sheet"].waitForExistence(timeout: 3))
        let desktop = revealResponsiveComparisonControl("responsive.compare.card.desktop", in: application, scrollDelta: 180)
        XCTAssertTrue((desktop.value as? String)?.contains("Desktop base source") == true)
        let tablet = revealResponsiveComparisonControl("responsive.compare.card.tablet", in: application)
        XCTAssertTrue((tablet.value as? String)?.contains("Custom size or position: 1 object") == true)
        XCTAssertTrue((tablet.value as? String)?.contains("authored geometry") == true)
        let mobile = revealResponsiveComparisonControl("responsive.compare.card.mobile", in: application)
        XCTAssertTrue((mobile.value as? String)?.contains("inherited geometry") == true)
        attachWindowScreenshot(application, named: "SF-AUTHORING-101 responsive comparison selection")

        let reviewMobile = revealResponsiveComparisonControl("responsive.compare.review.mobile", in: application)
        XCTAssertTrue(waitForHittable(reviewMobile, in: application)); reviewMobile.click()
        XCTAssertTrue(waitForValue(preset, containing: "Mobile"))
        XCTAssertTrue(application.descendants(matching: .any)["responsive.compare.sheet"].exists)
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["responsive.compare.sheet"]))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.x"], containing: "Uses Desktop"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-101 Mobile reviewed without authoring")
    }

    // SF-AUTHORING-102, SF-0604-001...006/008 — the real Layout Inspector
    // authors one monotonic clamp, the live canvas resolves it across presets,
    // comparison exposes the result, and Escape/reset preserve fixed intent.
    @MainActor
    // SF-0501-006, SF-0502-003/006: the real connected Section reaches
    // the existing fluid editor; fixed, inherited and override values stay honest.
    // Source-only acceptance: leave UNRUN while the owner testing hold applies.
    func testConnectedContainerFluidSpacingNavigationOverrideResetAndCancelJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        selectNavigatorTab("Elements", identifier: "elements", in: application)
        application.buttons["navigator.elements.section"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        insertStructuralFrame(in: application, expectedCount: 2)
        selectStructuralLayer("Section", in: application)
        selectInspectorTab("Layout", identifier: "layout", in: application)
        @MainActor func padding() -> XCUIElement {
            revealStructuralLayoutControl(application.textFields["inspector.layout.container.padding"], in: application)
        }
        @MainActor func preset(_ name: String) {
            application.descendants(matching: .any)["canvas.viewport.preset"].firstMatch.click()
            application.menuItems[name].click()
        }
        XCTAssertTrue(waitForValue(padding(), containing: "48"))
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.enable"], in: application).click()
        for (identifier, value) in [("minimum", "8"), ("preferred", "16"), ("maximum", "32")] {
            let field = revealStructuralLayoutControl(application.textFields["inspector.layout.fluid.\(identifier)"], in: application)
            field.click(); field.typeKey("a", modifierFlags: .command); field.typeText(value)
        }
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.apply"], in: application).click()
        XCTAssertTrue(waitForValue(padding(), containing: "32"))
        XCTAssertFalse(application.textFields["inspector.layout.container.padding"].isEnabled)
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.container.padding.source"], containing: "Smooth scaling"))
        attachWindowScreenshot(application, named: "SF-SOURCE-03 connected Section fluid padding Desktop")
        revealStructuralLayoutControl(application.buttons["inspector.layout.container.padding.fluid"], in: application).click()
        XCTAssertTrue(waitForHittable(application.buttons["inspector.layout.fluid.edit"], in: application))
        application.buttons["inspector.layout.fluid.edit"].click()
        let minimum = application.textFields["inspector.layout.fluid.minimum"]
        minimum.click(); minimum.typeKey("a", modifierFlags: .command); minimum.typeText("800")
        minimum.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.staticTexts["inspector.layout.fluid.validation"].waitForExistence(timeout: 3))
        minimum.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(padding(), containing: "32"))
        preset("Tablet")
        XCTAssertTrue(waitForValue(padding(), containing: "16"))
        XCTAssertTrue(application.textFields["inspector.layout.container.padding"].isEnabled)
        replaceStructuralLayoutField(padding(), with: "10", in: application)
        XCTAssertTrue(waitForValue(padding(), containing: "10"))
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.container.padding.source"], containing: "Set here · Tablet"))
        attachWindowScreenshot(application, named: "SF-SOURCE-03 Section Tablet override with fluid intent retained")
        revealStructuralLayoutControl(application.buttons["inspector.layout.container.padding.reset"], in: application).click()
        XCTAssertTrue(waitForValue(padding(), containing: "16"))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(padding(), containing: "10"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(padding(), containing: "16"))
        preset("Desktop")
        XCTAssertTrue(waitForValue(padding(), containing: "32"))
        revealStructuralLayoutControl(application.buttons["inspector.layout.container.padding.fluid"], in: application).click()
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.remove"], in: application).click()
        XCTAssertTrue(waitForValue(padding(), containing: "48"))
        XCTAssertTrue(application.textFields["inspector.layout.container.padding"].isEnabled)
        attachWindowScreenshot(application, named: "SF-SOURCE-03 explicit fluid removal restores fixed fallback")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(padding(), containing: "32"))
        XCTAssertFalse(application.textFields["inspector.layout.container.padding"].isEnabled)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
    }

    // SF-0602-006, SF-0603-002/006, SF-0604-002/003/006.
    // UNRUN source: real fluid typography controls, invalid/Escape, device
    // visibility/restore and exact native history; no launch-argument mutation.
    func testFluidTypographyScopeEffectiveValuesVisibilityResetAndCancelJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectStructuralLayer("Text", in: application)
        selectInspectorTab("Layout", identifier: "layout", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.layout.x"], with: "24", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.layout.y"], with: "24", in: application)
        selectInspectorTab("Design", identifier: "design", in: application)
        revealStructuralLayoutControl(application.buttons["inspector.design.typography.fluid"], in: application).click()
        @MainActor func chooseFontSize() {
            revealStructuralLayoutControl(application.descendants(matching: .any)["inspector.layout.fluid.target"].firstMatch, in: application).click()
            application.menuItems["Font Size"].click()
        }
        @MainActor func preset(_ name: String) {
            application.descendants(matching: .any)["canvas.viewport.preset"].firstMatch.click()
            application.menuItems[name].click()
        }
        chooseFontSize()
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.enable"], in: application).click()
        for (fieldName, value) in [("minimum", "12"), ("preferred", "16"), ("maximum", "20")] {
            let field = revealStructuralLayoutControl(application.textFields["inspector.layout.fluid.\(fieldName)"], in: application)
            field.click(); field.typeKey("a", modifierFlags: .command); field.typeText(value)
        }
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.apply"], in: application).click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.layout.fluid.target"].firstMatch, containing: "Font Size"),
            "A successful commit must not reset the property picker to Width")
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.current"], containing: "20"))
        attachWindowScreenshot(application, named: "SF-SOURCE-04 Desktop fluid typography effective source")
        selectInspectorTab("Design", identifier: "design", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.typography.effective"], containing: "size 20"))
        attachWindowScreenshot(application, named: "SF-SOURCE-04 Design fixed fallback and effective typography")
        preset("Mobile")
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.typography.effective"], containing: "size 12"))
        revealStructuralLayoutControl(application.buttons["inspector.design.typography.fluid"], in: application).click()
        chooseFontSize()
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.edit"], in: application).click()
        let minimum = application.textFields["inspector.layout.fluid.minimum"]
        minimum.click(); minimum.typeKey("a", modifierFlags: .command); minimum.typeText("800")
        minimum.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.staticTexts["inspector.layout.fluid.validation"].waitForExistence(timeout: 3))
        minimum.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.current"], containing: "12"))
        selectStructuralLayer("Text", in: application)
        let row = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text")).firstMatch
        let identifier = row.identifier
        revealStructuralLayoutControl(application.descendants(matching: .any)["inspector.layout.visibility"].firstMatch, in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        XCTAssertFalse(application.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "canvas.selection.")).firstMatch.exists)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)[identifier], containing: "Hidden at current breakpoint"))
        attachWindowScreenshot(application, named: "SF-SOURCE-04 Mobile hidden text retained in Layers without ghost")
        application.descendants(matching: .any)[identifier].click()
        revealStructuralLayoutControl(application.buttons["inspector.layout.visibility.reset"], in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        chooseFontSize()
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.remove"], in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.current"], containing: "Fixed Desktop fallback"))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.current"], containing: "Smooth scaling"))
        attachWindowScreenshot(application, named: "SF-SOURCE-04 Mobile fluid intent restored by Undo")
    }

    // SF-0604-002/003/005/006: unlike common-value drafts, a mixed
    // fallback has no legitimate seed. All three numbers are explicitly entered.
    func testMixedFluidFallbacksAcceptExplicitRangeWithoutBorrowingPrimaryValuesJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectInspectorTab("Layout", identifier: "layout", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.layout.width"], with: "200", in: application)
        componentMenu("Selection", "Clear Selection", in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let rows = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"))
        XCTAssertEqual(rows.count, 2)
        let first = rows.element(boundBy: 0).identifier, second = rows.element(boundBy: 1).identifier
        application.buttons[first].click()
        XCUIElement.perform(withKeyModifiers: .shift) { application.buttons[second].click() }
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.selectionPath"], containing: "2 selected; primary selection present"))
        selectInspectorTab("Layout", identifier: "layout", in: application)
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.enable"], in: application).click()
        for fieldName in ["minimum", "preferred", "maximum"] {
            XCTAssertEqual(application.textFields["inspector.layout.fluid.\(fieldName)"].value as? String, "")
        }
        for (fieldName, value) in [("minimum", "100"), ("preferred", "200"), ("maximum", "300")] {
            let field = revealStructuralLayoutControl(application.textFields["inspector.layout.fluid.\(fieldName)"], in: application)
            field.click(); field.typeText(value)
        }
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.apply"], in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.provenance"], containing: "Set here · 2 compatible"))
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.current"], containing: "300"))
        XCTAssertTrue(application.buttons["inspector.layout.fluid.remove"].exists,
            "Equal ranges with distinct FluidValueIDs must present one common range, not spurious Mixed")
        XCTAssertTrue(application.buttons[first].isSelected)
        XCTAssertTrue(application.buttons[second].isSelected)
        attachWindowScreenshot(application, named: "SF-SOURCE-04 explicit common fluid range from mixed fixed fallbacks")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "Mixed"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.current"], containing: "300"))
    }

    func testFluidResponsiveValueAuthoringPreviewResetAndAccessibilityJourney() throws {
        let application = launchWorkspace()
        XCTAssertTrue(waitForWorkspaceReady(application))
        application.buttons["canvas.empty.insert.frame"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectInspectorTab("Layout", identifier: "layout", in: application)
        let fluid = application.descendants(matching: .any)["inspector.layout.fluid"]
        XCTAssertTrue(fluid.waitForExistence(timeout: 3))
        let enable = revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.enable"], in: application)
        XCTAssertTrue(waitForHittable(enable, in: application)); enable.click()
        let minimum = application.textFields["inspector.layout.fluid.minimum"]
        let preferred = application.textFields["inspector.layout.fluid.preferred"]
        let maximum = application.textFields["inspector.layout.fluid.maximum"]
        XCTAssertTrue(minimum.waitForExistence(timeout: 3))
        for (field, value) in [(minimum, "160"), (preferred, "240"), (maximum, "360")] {
            let live = revealStructuralLayoutControl(field, in: application)
            live.click(); live.typeKey("a", modifierFlags: .command); live.typeText(value)
        }
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.apply"], in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.announcement"],
                                   containing: "applied"))
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

        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.edit"], in: application).click()
        let liveMinimum = revealStructuralLayoutControl(application.textFields["inspector.layout.fluid.minimum"], in: application)
        liveMinimum.click(); liveMinimum.typeKey("a", modifierFlags: .command); liveMinimum.typeText("500")
        liveMinimum.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.buttons["inspector.layout.fluid.remove"].exists,
                      "Escape must cancel the draft without replacing the committed clamp")
        revealStructuralLayoutControl(application.buttons["inspector.layout.fluid.remove"], in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.announcement"],
                                   containing: "uses the base exact value"))
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
        selectInspectorTab("Design", identifier: "design", in: application)
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
        _ = revealStructuralLayoutControl(opacityStepper, in: application)
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
        _ = revealStructuralLayoutControl(opacity, in: application)
        opacity.click()
        XCTAssertTrue(waitForValue(hex, containing: "#203040FF"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-012 valid focus loss")
        let opacityBeforeInvalidFocusLoss = opacity.value as? String
        replaceText(in: hex, with: "invalid", application: application)
        _ = revealStructuralLayoutControl(opacity, in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)
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
        focusDocumentCommands(in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)
        func reveal(_ identifier: String) -> XCUIElement {
            let element = application.descendants(matching: .any)[identifier].firstMatch
            guard element.waitForExistence(timeout: 5) else { return element }
            // Hittability alone permits a field clipped below the ScrollView.
            // Reuse strict live-control containment before a real focus click.
            return revealStructuralLayoutControl(element, in: application)
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
        XCTAssertTrue(waitForValue(target, containing: "Text Foreground"),
            "Plain Text must open the real token controls in its foreground context without two extra picker clicks")
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

    // SF-0507-002/005/006, SF-0805-003/006. UNRUN source: genuine
    // installed-weight menu, cancel/no-op neutrality and one-step paired Undo.
    func testInstalledFontPairChooserCancelAtomicUndoAndHeadingSemanticsJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let objectID = canvasObject(named: "Text object", in: application).identifier
        focusDocumentCommands(in: application)
        let insertionUndo = try XCTUnwrap(application.buttons["toolbar.undo"].value as? String)
        XCTAssertNotEqual(insertionUndo, "Text editing")
        selectInspectorTab("Design", identifier: "design", in: application)
        revealComponentPointerTarget("inspector.design.typography.chooseFont", in: application).click()
        XCTAssertTrue(application.descendants(matching: .any)["typography.font.chooser"].waitForExistence(timeout: 3))
        application.buttons["typography.font.cancel"].click()
        focusDocumentCommands(in: application)
        XCTAssertEqual(application.buttons["toolbar.undo"].value as? String, insertionUndo,
            "Cancel must preserve the document history head and leave native editor Undo")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5),
            "Cancelling the font chooser must not add a history entry above insertion")
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertTrue(application.descendants(matching: .any)[objectID].exists)
        selectStructuralLayer("Text", in: application)
        selectInspectorTab("Design", identifier: "design", in: application)
        let semantics = revealComponentPointerTarget("inspector.semantic.element", in: application)
        semantics.click(); application.menuItems["<h2>"].click()
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.typography.role"], containing: "Heading 2"))
        replaceStructuralLayoutField(application.textFields["inspector.design.typography.family"], with: "Missing SiteForge Pair Fixture", in: application)
        let weight = revealComponentPointerTarget("inspector.design.typography.weight", in: application)
        weight.click(); application.menuItems["Medium"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.family"], containing: "Missing SiteForge Pair Fixture"))
        @MainActor func chooseSystemBold(capture: Bool) {
            revealComponentPointerTarget("inspector.design.typography.chooseFont", in: application).click()
            replaceComponentTextField("typography.font.search", with: "System", in: application)
            let weights = revealComponentPointerTarget("typography.font.weights.System", in: application)
            XCTAssertTrue(weights.isEnabled)
            if capture { attachWindowScreenshot(application, named: "SF-SOURCE-05 installed family and upright weight controls") }
            weights.click()
            let bold = application.descendants(matching: .any)["typography.font.face.System.bold"].firstMatch
            XCTAssertTrue(bold.waitForExistence(timeout: 3)); bold.click()
            XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["typography.font.chooser"]))
        }
        chooseSystemBold(capture: true)
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.family"], containing: "System"))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.design.typography.weight"], containing: "Bold"))
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.typography.role"], containing: "Heading 2"))
        attachWindowScreenshot(application, named: "SF-SOURCE-05 atomic installed font pair preserves Heading 2")
        chooseSystemBold(capture: false)
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.family"], containing: "Missing SiteForge Pair Fixture"))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.design.typography.weight"], containing: "Medium"),
            "One Undo restores both properties; repeated identical choice must not add history")
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.family"], containing: "System"))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.design.typography.weight"], containing: "Bold"))
        componentMenu("Selection", "Edit Selected Text", in: application)
        let editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let frame = application.descendants(matching: .any)[objectID].frame
        XCTAssertEqual(editor.frame.minX, frame.minX, accuracy: 1)
        XCTAssertEqual(editor.frame.minY, frame.minY, accuracy: 1)
        XCTAssertEqual(editor.frame.width, frame.width, accuracy: 1)
        XCTAssertEqual(editor.frame.height, frame.height, accuracy: 1)
        attachWindowScreenshot(application, named: "SF-SOURCE-05 live editor after paired font choice")
        editor.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)[objectID].exists)
    }

    // SF-0702/0703/0308 — execution receipts are recorded in the closeout evidence.
    // All mutations use shipping Inspector fields and native Edit menu actions.
    // SF-LOCAL-BUILDER-014 / SF-0201-009, SF-0202-003, SF-0701-002/003/006.
    // Real native controls, geometry and keyboard focus; no model mutation shortcut.
    @MainActor
    func testStableInspectorStripsFieldsDraftsAndComponentRecoveryAtNormalAndCompactWidthsJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        let window = application.windows.firstMatch
        @MainActor func strips() throws {
            for (prefix, labels) in [
                ("navigator.tab", [("pages", "Pages"), ("layers", "Layers"), ("elements", "Elements"), ("assets", "Assets"), ("components", "Components")]),
                ("inspector.tab", [("design", "Design"), ("layout", "Layout"), ("content", "Content"), ("interactions", "Interactions"), ("accessibility", "Accessibility")]),
            ] {
                let bar = application.descendants(matching: .any)[prefix + ".bar"].firstMatch
                XCTAssertTrue(bar.waitForExistence(timeout: 3))
                let minima = labels.map { ceil(($0.1 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width) + 8 }
                let full = minima.reduce(0, +) + CGFloat(labels.count - 1) * 2 <= bar.frame.width - 6
                if full {
                    var previous: CGRect?
                    for (index, entry) in labels.enumerated() {
                        let button = application.buttons[prefix + "." + entry.0]
                        XCTAssertTrue(button.exists); XCTAssertEqual(button.label, entry.1)
                        XCTAssertTrue(bar.frame.insetBy(dx: -1, dy: -1).contains(button.frame))
                        XCTAssertGreaterThanOrEqual(button.frame.width, minima[index] - 1)
                        XCTAssertEqual(button.frame.height, 32, accuracy: 1)
                        if let previous {
                            XCTAssertEqual(button.frame.minY, previous.minY, accuracy: 1)
                            XCTAssertGreaterThanOrEqual(button.frame.minX, previous.maxX)
                        } else { XCTAssertEqual(button.frame.minX, bar.frame.minX + 3, accuracy: 1) }
                        previous = button.frame
                    }
                    XCTAssertEqual(try XCTUnwrap(previous).maxX, bar.frame.maxX - 3, accuracy: 1)
                    XCTAssertFalse(application.descendants(matching: .any)[prefix + ".overflow"].exists)
                } else {
                    let overflow = application.descendants(matching: .any)[prefix + ".overflow"].firstMatch
                    XCTAssertTrue(overflow.isHittable)
                    for entry in labels {
                        selectShellTab(entry.1, directIdentifier: prefix + "." + entry.0,
                            overflowIdentifier: prefix + ".overflow", in: application)
                        XCTAssertTrue(application.buttons[prefix + "." + entry.0].isSelected
                            || application.descendants(matching: .any)[prefix + ".overflow"].value as? String == entry.1)
                    }
                }
            }
        }
        @MainActor func control(_ identifier: String) -> XCUIElement {
            let live = revealComponentPointerTarget(identifier, in: application)
            let inspector = application.descendants(matching: .any)["shell.inspector"].firstMatch
            XCTAssertTrue(live.isHittable)
            XCTAssertTrue(inspector.frame.insetBy(dx: -1, dy: -1).contains(live.frame))
            XCTAssertGreaterThan(live.frame.width, 16); XCTAssertGreaterThan(live.frame.height, 12)
            return live
        }
        @MainActor func resizeWindow(to width: CGFloat, atMinimum: Bool = false) {
            let frame = window.frame
            @MainActor func dragRightEdge(to targetWidth: CGFloat) {
                let liveWindow = application.windows.firstMatch
                let current = liveWindow.frame
                // Resize along the straight AppKit edge, away from the
                // rounded corner and Dock.
                let start = liveWindow.coordinate(withNormalizedOffset: .init(dx: 1, dy: 0.5))
                    .withOffset(.init(dx: -2, dy: 0))
                let anchor = application.menuBars.firstMatch.coordinate(withNormalizedOffset: .zero)
                let origin = anchor.screenPoint
                let target = anchor.withOffset(.init(dx: current.minX + targetWidth - 2 - origin.x,
                                                    dy: current.midY - origin.y))
                start.click(forDuration: 0.2, thenDragTo: target)
            }
            // Drive past the minimum so AppKit's real size clamp, not the
            // pointer grip's release offset, determines the compact width.
            dragRightEdge(to: atMinimum ? width - 12 : width)
            let intermediate = application.windows.firstMatch.frame.width
            let edgeOffset = intermediate - width
            // The native resize grip can finish a few points from the cursor
            // target. Correct only a measured near miss after real movement;
            // a missed hit or background app still fails the assertion.
            if !atMinimum, application.state == .runningForeground, abs(intermediate - frame.width) > 2,
               abs(edgeOffset) > 2, abs(edgeOffset) <= 6 {
                dragRightEdge(to: width - edgeOffset)
            }
            let resized = NSPredicate { _, _ in
                abs(application.windows.firstMatch.frame.width - width) <= 2
            }
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: resized, object: nil)], timeout: 4)
            if result != .completed {
                attachWindowScreenshot(application, named: "SF-INSPECTOR native width resize failure")
            }
            XCTAssertEqual(result, .completed,
                           "Native resize to \(width); starting frame \(frame); live frame \(application.windows.firstMatch.frame); app state \(application.state.rawValue)")
        }
        try strips()
        attachWindowScreenshot(application, named: "SF-INSPECTOR empty normal complete destination strips")
        let maximizedWidth = window.frame.width
        resizeWindow(to: 1280)
        try strips()
        attachWindowScreenshot(application, named: "SF-INSPECTOR normal 1280 complete destination strips")
        resizeWindow(to: maximizedWidth)
        try strips()
        attachWindowScreenshot(application, named: "SF-INSPECTOR wider supported destination strips")
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        let title = control("inspector.navigation.title")
        let titleValue = title.value as? String ?? ""
        replaceText(in: title, with: "A readable project title with ordinary navigation", application: application)
        _ = control("inspector.navigation.title.apply")
        application.typeKey(.escape, modifierFlags: [])
        let cancelledTitle = NSPredicate { _, _ in application.textFields["inspector.navigation.title"].value as? String == titleValue }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: cancelledTitle, object: nil)], timeout: 4), .completed)
        let spacing = control("inspector.navigation.linkGap")
        spacing.click(); XCTAssertTrue(waitForKeyboardFocus(spacing, in: application))
        control("inspector.navigation.linkGap.cancel").click()
        _ = control("inspector.navigation.includeAll")
        attachWindowScreenshot(application, named: "SF-INSPECTOR Header title spacing and included pages normal")
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        _ = control("inspector.navigation.title")
        _ = control("inspector.navigation.linkGap")
        _ = control("inspector.navigation.hamburger")
        attachWindowScreenshot(application, named: "SF-INSPECTOR Footer shared content and menu framing normal")
        application.buttons["toolbar.tool.select"].click()
        application.descendants(matching: .any)["canvas.interaction"].firstMatch
            .coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.94)).click()
        componentMenu("Insert", "Insert Frame at Center", in: application)
        let frameID = canvasObject(named: "Frame", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Text at Center", in: application)
        // Header/Footer titles also expose the truthful Text object role.
        // Capture the newly selected insertion, not the first title in paint order.
        let insertedTextQuery = application.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ AND identifier BEGINSWITH %@", "Text object", "canvas.object."))
        let textAdopted = NSPredicate { _, _ in
            insertedTextQuery.allElementsBoundByIndex.filter(\.isSelected).count == 1
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: textAdopted, object: nil)], timeout: 5), .completed)
        let insertedTexts = insertedTextQuery.allElementsBoundByIndex.filter(\.isSelected)
        XCTAssertEqual(insertedTexts.count, 1)
        let textID = try XCTUnwrap(insertedTexts.first).identifier
        selectInspectorTab("Design", identifier: "design", in: application)
        let size = control("inspector.design.typography.size")
        let original = size.value as? String ?? "14"
        replaceText(in: size, with: "1e", application: application)
        XCTAssertTrue(waitForKeyboardFocus(application.textFields["inspector.design.typography.size"], in: application))
        resizeWindow(to: 1100, atMinimum: true)
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.design.typography.size", containing: "1e"))
        application.textFields["inspector.design.typography.size"].click()
        application.typeKey(.return, modifierFlags: [])
        let invalid = control("inspector.design.validation")
        XCTAssertFalse((invalid.value as? String ?? invalid.label).isEmpty)
        let familyFrame = control("inspector.design.typography.family").frame
        attachWindowScreenshot(application, named: "SF-INSPECTOR compact typography invalid draft retained")
        application.textFields["inspector.design.typography.size"].click()
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.design.typography.size", containing: original))
        XCTAssertEqual(control("inspector.design.typography.family").frame.minX, familyFrame.minX, accuracy: 1)
        let width = control("inspector.design.typography.weight"), alignment = control("inspector.design.typography.alignment")
        XCTAssertFalse(width.frame.intersects(alignment.frame))
        _ = control("inspector.design.typography.foregroundHex")
        _ = control("inspector.design.typography.effective")
        _ = control("inspector.tokens.targetStatus")
        _ = control("inspector.tokens.empty")
        _ = control("inspector.design.opacity")
        XCTAssertTrue(application.descendants(matching: .any)[textID].firstMatch.isSelected)
        try strips()
        attachWindowScreenshot(application, named: "SF-INSPECTOR compact full-width typography appearance and strips")
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        revealComponentPointerTarget("navigator.layer." + frameID, in: application).click()
        componentMenu("Component", "Create Component from Selection", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        control("inspector.component.edit").click()
        selectStructuralLayer("Text", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceComponentTextField("component.text.definition.name", with: "Introduction shared across this component", in: application)
        control("component.text.definition.apply").click()
        application.buttons["components.exit"].click()
        selectInspectorTab("Content", identifier: "content", in: application)
        let property = application.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component.text.value.")).firstMatch
        XCTAssertTrue(property.waitForExistence(timeout: 4))
        let propertyID = property.identifier
        replaceComponentTextField(propertyID, with: "A retained copy value long enough to wrap in compact Inspector layouts.", in: application)
        application.textFields[propertyID].typeKey(.return, modifierFlags: [])
        _ = control("inspector.component.edit"); _ = control("inspector.component.detach")
        attachWindowScreenshot(application, named: "SF-INSPECTOR compact component copy controls and long value")
        control("inspector.component.edit").click()
        selectStructuralLayer("Text", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        control("component.text.definition.remove").click()
        application.buttons["components.exit"].click()
        selectInspectorTab("Content", identifier: "content", in: application)
        _ = control("component.recovery.summary")
        attachWindowScreenshot(application, named: "SF-INSPECTOR compact missing-property recovery is readable")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(application.textFields[propertyID].waitForExistence(timeout: 4))
        XCTAssertTrue(waitForValue(application.textFields[propertyID], containing: "A retained copy value"))
    }

    // SF-LOCAL-BUILDER-012 / SF-0203-006, SF-0701-002.
    func testFormattingCommandsRemainVisibleAcrossInspectorDestinationsWithoutToolsDisclosureJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let selected = try XCTUnwrap(application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object."))
            .allElementsBoundByIndex.first(where: { $0.isSelected }))
        let identity = selected.identifier
        let bounds = selected.frame
        let openingCanvasFrame = liveCanvas(in: application).frame
        let openingCanvasValue = String(describing: liveCanvas(in: application).value ?? "")
        let initialLiveBounds = application.descendants(matching: .any)[identity].firstMatch.frame
        let openingGeometry = XCTAttachment(string: "snapshot-object=\(bounds)\nlive-object=\(initialLiveBounds)\ncanvas=\(openingCanvasFrame)\nviewport=\(openingCanvasValue)\nwindow=\(application.windows.firstMatch.frame)")
        openingGeometry.name = "SF-USABILITY opening snapshot versus live geometry"
        openingGeometry.lifetime = .keepAlways; add(openingGeometry)
        for (title, identifier) in [("Design", "design"), ("Layout", "layout"),
                                    ("Content", "content"), ("Interactions", "interactions"),
                                    ("Accessibility", "accessibility")] {
            selectInspectorTab(title, identifier: identifier, in: application)
            // Do not open Inspector Tools: common commands must be directly
            // exposed by the real selected-object header in every destination.
            let menu = application.descendants(matching: .any)["inspector.formatting.menu"].firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 3))
            XCTAssertTrue(menu.isEnabled)
            XCTAssertTrue(menu.isHittable)
            XCTAssertTrue(application.scrollViews["inspector.selection.scroll"].frame.contains(menu.frame))
            XCTAssertTrue(application.descendants(matching: .any)[identity].firstMatch.isSelected)
            if application.descendants(matching: .any)[identity].firstMatch.frame != bounds {
                let diagnostic = XCTAttachment(string: "tab=\(identifier)\nopening-object=\(bounds)\ncurrent-object=\(application.descendants(matching: .any)[identity].firstMatch.frame)\nopening-canvas=\(openingCanvasFrame)\ncurrent-canvas=\(liveCanvas(in: application).frame)\nopening-viewport=\(openingCanvasValue)\ncurrent-viewport=\(String(describing: liveCanvas(in: application).value ?? ""))\nwindow=\(application.windows.firstMatch.frame)")
                diagnostic.name = "SF-USABILITY exact viewport and object geometry boundary"
                diagnostic.lifetime = .keepAlways; add(diagnostic)
                attachWindowScreenshot(application, named: "SF-USABILITY geometry mismatch before assertion")
            }
            XCTAssertEqual(application.descendants(matching: .any)[identity].firstMatch.frame, bounds)
        }
        let menu = application.descendants(matching: .any)["inspector.formatting.menu"].firstMatch
        menu.click()
        XCTAssertTrue(application.menuItems["formatting.copy.appearance"].isEnabled)
        XCTAssertFalse(application.menuItems["formatting.copy.textStyle"].isEnabled)
        application.menuItems["formatting.copy.appearance"].click()
        attachWindowScreenshot(application, named: "SF-USABILITY direct formatting in selected-object header")
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.formatting.status", containing: "Copied base Appearance"))
        componentMenu("File", "Site & Page Settings…", in: application)
        XCTAssertTrue(application.buttons["siteSettings.apply"].waitForExistence(timeout: 3))
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.buttons["siteSettings.apply"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(application.descendants(matching: .any)[identity].firstMatch.isSelected)
        application.menuBars.menuBarItems["Edit"].click()
        XCTAssertTrue(application.menuItems["Undo"].isEnabled, "Copy, tab navigation and cancelled settings must preserve insertion history")
        application.typeKey(.escape, modifierFlags: [])
        componentMenu("Component", "Create Component from Selection", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        let editOriginal = revealComponentPointerTarget("inspector.component.edit", in: application)
        XCTAssertEqual(editOriginal.label, "Edit original component")
        XCTAssertTrue(editOriginal.isEnabled && editOriginal.isHittable)
        editOriginal.click()
        let back = application.buttons["components.exit"]
        XCTAssertTrue(back.waitForExistence(timeout: 3))
        XCTAssertEqual(back.label, "Back to this copy")
        back.click()
        // AppKit click completion does not await the newly prepared page scene.
        let returnedSelection = NSPredicate { _, _ in
            let object = application.descendants(matching: .any)[identity].firstMatch
            return object.exists && object.isSelected
        }
        XCTAssertEqual(XCTWaiter.wait(for: [
            XCTNSPredicateExpectation(predicate: returnedSelection, object: application)
        ], timeout: 5), .completed,
                      "Original editing must return to the exact copy, not a same-named replacement")
        XCTAssertEqual(application.descendants(matching: .any)[identity].firstMatch.frame, bounds)
        attachWindowScreenshot(application, named: "SF-USABILITY exact component copy after original return")
    }

    func testFormattingReuseNativeAppearanceTextStyleAndAtomicUndoJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        @MainActor func field(_ identifier: String, _ value: String) {
            replaceStructuralLayoutField(application.textFields[identifier], with: value, in: application)
        }
        @MainActor func formatting(_ title: String) {
            application.menuBars.menuBarItems["Edit"].click()
            let enabled = NSPredicate { _, _ in
                let item = application.menuItems[title].firstMatch
                return item.exists && item.isEnabled
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: nil)], timeout: 5), .completed)
            application.menuItems[title].firstMatch.click()
        }
        @MainActor func status(_ text: String) {
            let live = revealComponentPointerTarget("inspector.formatting.status", in: application)
            XCTAssertTrue(waitForValue(live, containing: text))
        }
        @MainActor func exactField(_ identifier: String, _ value: String?) {
            let adopted = NSPredicate { _, _ in application.textFields[identifier].value as? String == value }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: adopted, object: nil)], timeout: 5), .completed)
        }
        @MainActor func clearSelection() {
            application.buttons["toolbar.tool.select"].click()
            application.descendants(matching: .any)["canvas.interaction"].firstMatch
                .coordinate(withNormalizedOffset: .init(dx: 0.92, dy: 0.92)).click()
            XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.selectionPath"], containing: "0 selected"))
        }
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectInspectorTab("Design", identifier: "design", in: application)
        attachWindowScreenshot(application, named: "SF-FORMATTING default target family")
        field("inspector.design.fillHex", "#24486CFF")
        field("inspector.design.opacity", "60")
        attachWindowScreenshot(application, named: "SF-FORMATTING authored appearance source")
        formatting("Copy Appearance"); status("Copied base Appearance")
        clearSelection()
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        selectInspectorTab("Design", identifier: "design", in: application)
        let originalFill = application.textFields["inspector.design.fillHex"].value as? String
        let originalOpacity = application.textFields["inspector.design.opacity"].value as? String
        let selectedObject = try XCTUnwrap(application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object."))
            .allElementsBoundByIndex.first(where: { $0.isSelected }))
        let identity = selectedObject.identifier, bounds = selectedObject.frame
        formatting("Paste Appearance"); status("Pasted base Appearance")
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: "#24486C"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.opacity"], containing: "60"))
        XCTAssertEqual(application.descendants(matching: .any)[identity].firstMatch.frame, bounds)
        XCTAssertTrue(application.descendants(matching: .any)[identity].firstMatch.isSelected)
        attachWindowScreenshot(application, named: "SF-FORMATTING appearance pasted geometry retained")
        componentMenu("Edit", "Undo", in: application)
        exactField("inspector.design.fillHex", originalFill)
        exactField("inspector.design.opacity", originalOpacity)
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: "#24486C"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.opacity"], containing: "60"))
        attachWindowScreenshot(application, named: "SF-FORMATTING one undo redo appearance")
        formatting("Paste Appearance"); status("No Undo entry was added")

        clearSelection()
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        selectInspectorTab("Design", identifier: "design", in: application)
        field("inspector.design.typography.size", "22")
        field("inspector.design.typography.lineHeight", "30")
        formatting("Copy Text Style"); status("Copied base Text Style")
        clearSelection()
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 4", timeout: 5))
        selectInspectorTab("Design", identifier: "design", in: application)
        formatting("Paste Text Style"); status("Pasted base Text Style")
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.size"], containing: "22"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.lineHeight"], containing: "30"))
        attachWindowScreenshot(application, named: "SF-FORMATTING text style target")
        // Ordinary control cancellation remains native, not a formatting paste.
        replaceStructuralLayoutField(application.textFields["inspector.design.typography.size"], with: "invalid", in: application, endKey: .escape)
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.size"], containing: "22"))
        attachWindowScreenshot(application, named: "SF-FORMATTING invalid draft escape retained")
    }

    func testDesignInspectorTypographyInlineUndoRedoAccessibilityJourney() throws {
        let fixture = legacyFixtureURL(named: "schema-v4-legacy-surface")
        let project = fixtureRoot.appendingPathComponent("typography-native-save.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: fixture)
        XCTAssertTrue(waitForWorkspaceReady(application))
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertFalse(application.buttons["canvas.empty.insert.text"].exists,
            "A retained legacy surface is not a genuinely blank page")
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        selectInspectorTab("Design", identifier: "design", in: application)
        let inspector = application.scrollViews["inspector.selection.scroll"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        func reveal(_ identifier: String) -> XCUIElement {
            revealStructuralLayoutControl(application.descendants(matching: .any)[identifier], in: application)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let reopenedText = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text"
        )).firstMatch
        XCTAssertTrue(reopenedText.waitForExistence(timeout: 5)); reopenedText.click()
        selectInspectorTab("Design", identifier: "design", in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)

        let layerList = application.descendants(matching: .any)["inspector.design.layers"]
        let addSolid = application.buttons["inspector.design.layers.addSolid"]
        let addGradient = application.buttons["inspector.design.layers.addGradient"]
        XCTAssertTrue(layerList.waitForExistence(timeout: 5))
        _ = revealStructuralLayoutControl(addGradient, in: application)
        XCTAssertTrue(addSolid.isHittable && addGradient.isHittable)
        addGradient.click()
        let angle = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS %@", ".angle"))
            .firstMatch
        XCTAssertTrue(angle.waitForExistence(timeout: 5))
        XCTAssertEqual(angle.label, "Linear gradient angle")
        replaceText(in: angle, with: "90", application: application)
        angle.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(angle, containing: "90"))

        let gradientPrefix = angle.identifier.replacingOccurrences(of: ".angle", with: "")
        let stopColorWells = application.colorWells.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier CONTAINS %@ AND identifier ENDSWITH %@",
            "\(gradientPrefix).stop.", ".stop.", ".color"
        ))
        XCTAssertEqual(stopColorWells.count, 2)
        let inspectorScroll = application.descendants(matching: .any)["inspector.selection.scroll"]
        XCTAssertTrue(inspectorScroll.waitForExistence(timeout: 3))
        func reveal(_ element: XCUIElement) -> Bool {
            let live = revealStructuralLayoutControl(element, in: application)
            return live.exists && live.isEnabled && live.isHittable
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
        let delete = revealStructuralLayoutControl(application.buttons[deleteIdentifier], in: application)
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

        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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

        selectInspectorTab("Design", identifier: "design", in: application)
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

    // SF-0504/SF-0510/SF-0511 — native Inspector controls author positioning,
    // reusable appearance, and a bounded hover variant through the shipping
    // transaction path. Forced state preview remains scene-local.
    // SF-0510-002/003/005/006, SF-0508-003/006. UNRUN source:
    // real ordered links, explicit inheritance, scoped update/cancel and None.
    func testReusableStyleLinksInheritanceScopedUpdateAndNonePreservationJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectInspectorTab("Design", identifier: "design", in: application)
        @MainActor func action(_ identifier: String) {
            _ = revealComponentPointerTarget(identifier, in: application)
            let ready = NSPredicate { _, _ in
                let live = application.descendants(matching: .any)[identifier].firstMatch
                return live.exists && live.isEnabled && live.isHittable
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 3), .completed)
            application.descendants(matching: .any)[identifier].firstMatch.click()
        }
        @MainActor func create(_ name: String, color: String, opacity: String) -> String {
            replaceStructuralLayoutField(application.textFields["inspector.design.fillHex"], with: color, in: application)
            replaceStructuralLayoutField(application.textFields["inspector.design.opacity"], with: opacity, in: application)
            replaceComponentTextField("inspector.design.style.name", with: name, in: application)
            action("inspector.design.style.create")
            let link = application.buttons["Apply reusable style \(name)"]
            XCTAssertTrue(link.waitForExistence(timeout: 5))
            XCTAssertTrue(link.identifier.hasSuffix(".link"))
            let prefix = String(link.identifier.dropLast(".link".count))
            action(prefix + ".link")
            return prefix
        }
        @MainActor func confirm(_ title: String) {
            let button = application.sheets.buttons[title].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3)); button.click()
        }
        let warm = create("Warm", color: "#FF0000FF", opacity: "40")
        let cool = create("Cool", color: "#0000FFFF", opacity: "70")
        XCTAssertTrue(waitForValue(application.staticTexts[warm + ".usage"], containing: "1 selected"))
        XCTAssertTrue(waitForValue(application.staticTexts[cool + ".usage"], containing: "1 selected"))
        attachWindowScreenshot(application, named: "SF-SOURCE-06 ordered reusable links preserve local overrides")
        action("inspector.design.style.inheritFill")
        confirm("Cancel")
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: "#0000FFFF"))
        action("inspector.design.style.inheritFill"); confirm("Use Linked Fill")
        action("inspector.design.style.inheritOpacity"); confirm("Use Linked Opacity")
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.opacitySource"], containing: "Cool"))
        action(cool + ".earlier")
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: "#FF0000FF"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.opacity"], containing: "40"))
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.fillSource"], containing: "Warm"))
        attachWindowScreenshot(application, named: "SF-SOURCE-06 linked precedence matches fill opacity Inspector")
        action(cool + ".update")
        attachWindowScreenshot(application, named: "SF-SOURCE-06 shared update scope and captured values")
        confirm("Cancel")
        action(cool + ".later")
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: "#0000FFFF"),
            "Cancelled shared update must leave Cool's original definition intact")
        action(cool + ".earlier")
        action(cool + ".update"); confirm("Update Shared Style")
        action(cool + ".later")
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: "#FF0000FF"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.opacity"], containing: "40"))
        action("inspector.design.fillRemove")
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.style.fillResetStatus"], containing: "Transparent / None"))
        XCTAssertFalse(application.buttons["inspector.design.style.inheritFill"].isEnabled)
        action(cool + ".unlink")
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.style.fillResetStatus"], containing: "Transparent / None"))
        attachWindowScreenshot(application, named: "SF-SOURCE-06 explicit None survives style unlink and shared edits")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts[cool + ".usage"], containing: "1 selected"))
        XCTAssertFalse(application.buttons["inspector.design.style.inheritFill"].isEnabled)
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.style.fillResetStatus"], containing: "Transparent / None"))
    }

    func testPositioningReusableStyleAndInteractionStateAuthoringJourney() throws {
        let application = launchScenario("workspace")
        let shell = application.descendants(matching: .any)["workspace.shell"]
        XCTAssertTrue(shell.waitForExistence(timeout: 5))
        let insert = application.buttons["canvas.empty.insert.frame"]
        XCTAssertTrue(waitForHittable(insert, in: application)); insert.click()

        selectInspectorTab("Layout", identifier: "layout", in: application)
        let mode = application.descendants(matching: .any)["inspector.layout.position.mode"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5)); mode.click()
        application.menuItems["Absolute"].click()
        let top = application.textFields["inspector.layout.position.top"]
        XCTAssertTrue(waitForHittable(top, in: application))
        replaceText(in: top, with: "24\n", application: application)
        let containingBlock = application.staticTexts["inspector.layout.position.containingBlock"]
        XCTAssertTrue(containingBlock.waitForExistence(timeout: 5))
        XCTAssertEqual(containingBlock.label, "Containing block")
        XCTAssertEqual(containingBlock.value as? String, "Root")

        selectInspectorTab("Design", identifier: "design", in: application)
        let inspector = application.scrollViews["inspector.selection.scroll"]
        XCTAssertTrue(inspector.waitForExistence(timeout: 5))
        @MainActor func reveal(_ identifier: String) -> XCUIElement {
            revealStructuralLayoutControl(application.descendants(matching: .any)[identifier], in: application)
        }
        replaceText(in: reveal("inspector.design.style.name"), with: "Card", application: application)
        reveal("inspector.design.style.create").click()
        XCTAssertTrue(application.buttons["Apply reusable style Card"].waitForExistence(timeout: 5))
        application.buttons["Apply reusable style Card"].click()
        replaceText(in: reveal("inspector.design.state.fill"), with: "#1933CCFF", application: application)
        replaceText(in: reveal("inspector.design.state.opacity"), with: "50", application: application)
        reveal("inspector.design.state.apply").click()
        XCTAssertTrue(waitForValue(
            application.descendants(matching: .any)["inspector.design.announcement"],
            containing: "committed"))
        let preview = reveal("inspector.design.state.preview")
        preview.click(); application.menuItems["Hover"].click()
        attachWindowScreenshot(application, named: "SF-AUTHORING-109 positioning reusable hover state")
        application.typeKey("z", modifierFlags: .command)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(
            application.textFields["inspector.design.state.fill"],
            containing: "#1933CCFF"))
        XCTAssertTrue(waitForValue(
            application.textFields["inspector.design.state.opacity"],
            containing: "50"))
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
        // authored object. Insert one real Frame through the public Insert
        // menu action, keeping the legacy member as unrelated package data
        // while this journey proves renderer adoption across Save/Close/Open.
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"))
        XCTAssertFalse(application.descendants(matching: .any)["canvas.empty.hint"].exists,
                       "A retained legacy node is not a genuinely blank page.")
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let reopenedLegacyFrame = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Legacy Surface Frame"
        )).firstMatch
        XCTAssertTrue(reopenedLegacyFrame.waitForExistence(timeout: 5))
        let reopenedFrame = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"
        )).firstMatch
        XCTAssertTrue(reopenedFrame.waitForExistence(timeout: 5))
        reopenedFrame.click()
        selectInspectorTab("Design", identifier: "design", in: application)
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
        selectShellTab("Assets", directIdentifier: "navigator.tab.assets", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        focusDocumentCommands(in: application)
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
        selectShellTab("Assets", directIdentifier: "navigator.tab.assets", overflowIdentifier: "navigator.tab.overflow", in: application)
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
    // SF-0802-002/003/005/006, SF-0807-002/003/006. Source-only;
    // native import, draft ownership, mixed properties and independent reuse.
    func testImageMixedFitAltDraftAndIndependentAssetReuseJourney() throws {
        let url = try makeLocalImageFixture(named: "source-seven-image.png")
        let project = fixtureRoot.appendingPathComponent("source-seven-images.siteforge")
        let application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Import and Insert Image…", in: application)
        XCTAssertTrue(waitForNativeOpenPanel(in: application))
        application.typeKey("g", modifierFlags: [.command, .shift])
        let path = application.sheets.textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 3))
        replaceText(in: path, with: url.path, application: application)
        path.typeKey(.return, modifierFlags: [])
        let go = application.sheets.buttons["Go"]
        if path.exists && go.exists && go.isEnabled { go.click() }
        let open = application.buttons["OKButton"]
        XCTAssertTrue(waitForHittable(open, in: application)); open.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let first = canvasObject(named: "Image: source-seven-image; alternative text is empty", in: application)
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        let firstID = first.identifier
        componentMenu("Insert", "Insert Selected Image at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        let images = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "canvas.object.", "Image:"))
        let secondID = try XCTUnwrap(images.allElementsBoundByIndex.first { $0.identifier != firstID }?.identifier)
        let secondFrame = application.descendants(matching: .any)[secondID].firstMatch.frame
        selectInspectorTab("Design", identifier: "design", in: application)
        for mode in ["Fit", "Stretch", "Fill"] {
            let fit = revealComponentPointerTarget("inspector.image.fit", in: application)
            let choice = fit.radioButtons[mode]
            XCTAssertTrue(waitForHittable(choice, in: application)); choice.click()
            let settled = NSPredicate { _, _ in
                let live = application.descendants(matching: .any)["inspector.image.fit"].firstMatch.radioButtons[mode]
                return live.exists && (live.value as? NSNumber)?.intValue == 1
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 3), .completed)
            XCTAssertEqual(application.descendants(matching: .any)[secondID].firstMatch.frame, secondFrame)
            attachWindowScreenshot(application, named: "SF-SOURCE-07 Image \(mode) preserves authored bounds")
        }
        replaceComponentTextField("inspector.image.alt", with: "Meaningful image description", in: application)
        application.textFields["inspector.image.alt"].typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.image.status"], containing: "committed"))
        replaceComponentTextField("inspector.image.focalX", with: "-", in: application)
        application.textFields["inspector.image.focalX"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.staticTexts["inspector.design.validation"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-SOURCE-07 invalid focal draft retains committed image")
        application.textFields["inspector.image.focalX"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.image.focalX"], containing: "50"))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let firstRowID = "navigator.layer." + firstID.replacingOccurrences(of: "canvas.object.", with: "")
        let secondRowID = "navigator.layer." + secondID.replacingOccurrences(of: "canvas.object.", with: "")
        let firstRow = revealComponentPointerTarget(firstRowID, in: application)
        firstRow.click()
        let secondRow = revealComponentPointerTarget(secondRowID, in: application)
        XCUIElement.perform(withKeyModifiers: .shift) { secondRow.click() }
        XCTAssertTrue(firstRow.isSelected); XCTAssertTrue(secondRow.isSelected)
        selectInspectorTab("Design", identifier: "design", in: application)
        XCTAssertTrue(application.staticTexts["inspector.image.mixed"].waitForExistence(timeout: 3))
        let alt = revealComponentPointerTarget("inspector.image.alt", in: application)
        XCTAssertTrue(alt.isEnabled); XCTAssertTrue((alt.value as? String)?.contains("Mixed") == true)
        replaceStructuralLayoutField(application.textFields["inspector.image.alt"], with: "Common description", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.image.status"], containing: "2 objects"))
        XCTAssertTrue(firstRow.isSelected); XCTAssertTrue(secondRow.isSelected)
        attachWindowScreenshot(application, named: "SF-SOURCE-07 mixed Images expose common fit and explicit alt editing")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.image.alt"], containing: "Mixed"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.image.alt"], containing: "Common description"))
        selectNavigatorTab("Assets", identifier: "assets", in: application)
        replaceComponentTextField("assets.search", with: "no-such-project-image", in: application)
        XCTAssertTrue(application.buttons["assets.empty.clearFilters"].waitForExistence(timeout: 3))
        revealComponentPointerTarget("inspector.image.choose", in: application).click()
        let choices = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "asset.use.choose."))
        XCTAssertEqual(choices.count, 1, "Navigator filters must not hide reusable project images")
        attachWindowScreenshot(application, named: "SF-SOURCE-07 reuse sheet independent of navigator filters")
        application.buttons["asset.use.cancel"].click()
        XCTAssertEqual(application.textFields["assets.search"].value as? String, "no-such-project-image")
        application.buttons["assets.empty.clearFilters"].click()
        XCTAssertEqual(application.descendants(matching: .any)[secondID].firstMatch.frame, secondFrame)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        let fitLabel = application.staticTexts["inspector.image.fit.label"]
        let fitControl = application.descendants(matching: .any)["inspector.image.fit"].firstMatch
        XCTAssertTrue(fitLabel.exists)
        XCTAssertLessThanOrEqual(fitLabel.frame.height, 22, "Fit Mode must remain a single readable line in mixed selection")
        XCTAssertLessThanOrEqual(fitLabel.frame.maxY, fitControl.frame.minY + 1,
                                 "The full-width mixed picker must not squeeze its label")
        attachWindowScreenshot(application, named: "SF-SOURCE-07 reused assets preserve image geometry and semantic edits")
    }

    func testPracticalImageReuseScopedReplacementAndTypographyJourney() throws {
        let firstURL = try makeLocalImageFixture(named: "workflow-picture-one.png")
        let secondURL = try makeLocalImageFixture(named: "workflow-picture-two.png", palette: 1)
        let thirdURL = try makeLocalImageFixture(named: "workflow-picture-three.png", palette: 2)
        let project = fixtureRoot.appendingPathComponent("image-type-workflow.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        func chooseFile(_ url: URL) {
            XCTAssertTrue(waitForNativeOpenPanel(in: application))
            application.typeKey("g", modifierFlags: [.command, .shift])
            let path = application.sheets.textFields["PathTextField"]
            XCTAssertTrue(path.waitForExistence(timeout: 3))
            replaceText(in: path, with: url.path, application: application); path.typeKey(.return, modifierFlags: [])
            let go = application.sheets.buttons["Go"]
            if path.exists && go.exists && go.isEnabled { go.click() }
            let confirm = application.buttons["OKButton"]
            XCTAssertTrue(waitForHittable(confirm, in: application)); confirm.click()
        }
        componentMenu("Insert", "Import and Insert Image…", in: application); chooseFile(firstURL)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let firstImage = canvasObject(named: "Image: workflow-picture-one; alternative text is empty", in: application)
        XCTAssertTrue(firstImage.waitForExistence(timeout: 5))
        let firstID = firstImage.identifier
        componentMenu("Insert", "Insert Selected Image at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        let images = application.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@", "canvas.object.", "Image:"))
        let secondID = try XCTUnwrap(images.allElementsBoundByIndex.first { $0.identifier != firstID }?.identifier)
        let before = application.descendants(matching: .any)[secondID].firstMatch.frame
        selectInspectorTab("Design", identifier: "design", in: application)
        revealComponentPointerTarget("inspector.image.import", in: application).click(); chooseFile(secondURL)
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.image.status"], containing: "selected uses"))
        XCTAssertEqual(application.descendants(matching: .any)[secondID].firstMatch.frame, before)
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-004 selected-use replacement preserves geometry")
        revealComponentPointerTarget("inspector.image.choose", in: application).click()
        replaceComponentTextField("asset.use.search", with: "picture-one", in: application)
        XCTAssertEqual(application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "asset.use.choose.")).count, 1)
        application.buttons["asset.use.cancel"].click()
        revealComponentPointerTarget("inspector.image.sharedActions", in: application).click()
        application.menuItems["Replace Asset Everywhere…"].click()
        XCTAssertTrue(application.staticTexts["Replace Asset Everywhere?"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-004 explicit global replacement reference scope")
        let globalReplacement = application.dialogs.firstMatch.buttons["Choose Global Replacement…"]
        XCTAssertTrue(waitForHittable(globalReplacement, in: application))
        globalReplacement.click(); chooseFile(thirdURL)
        XCTAssertTrue(application.staticTexts["workflow-picture-three.png"].waitForExistence(timeout: 5))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(application.staticTexts["workflow-picture-two.png"].waitForExistence(timeout: 5))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(application.staticTexts["workflow-picture-three.png"].waitForExistence(timeout: 5))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        revealComponentPointerTarget("navigator.layer." + firstID.replacingOccurrences(of: "canvas.object.", with: ""), in: application).click()
        XCTAssertTrue(application.staticTexts["workflow-picture-one"].waitForExistence(timeout: 3))
        componentMenu("Insert", "Insert Text at Center", in: application)
        let textObject = canvasObject(named: "Text object", in: application)
        XCTAssertTrue(textObject.waitForExistence(timeout: 5))
        let textID = textObject.identifier
        selectInspectorTab("Design", identifier: "design", in: application)
        replaceComponentTextField("inspector.design.typography.family", with: "Missing SiteForge Workflow Family", in: application)
        application.textFields["inspector.design.typography.family"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.design.typography.fallback"], containing: "preserved"))
        revealComponentPointerTarget("inspector.design.typography.chooseFont", in: application).click()
        replaceComponentTextField("typography.font.search", with: "System", in: application)
        let system = application.buttons["typography.font.choose.System"]
        XCTAssertTrue(waitForHittable(system, in: application)); system.click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.family"], containing: "System"))
        revealComponentPointerTarget("inspector.design.typography.weight", in: application).click(); application.menuItems["Bold"].click()
        let alignment = revealComponentPointerTarget("inspector.design.typography.alignment", in: application)
        alignment.click(); alignment.menuItems["Center"].click()
        replaceStructuralLayoutField(application.textFields["inspector.design.typography.size"], with: "22", in: application)
        replaceComponentTextField("inspector.design.typography.lineHeight", with: "30", in: application)
        application.textFields["inspector.design.typography.lineHeight"].typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.lineHeight"], containing: "30"))
        replaceComponentTextField("inspector.design.typography.size", with: "-", in: application)
        application.textFields["inspector.design.typography.size"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.size"], containing: "22"))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-004 explicit installed font and cancelled numeric draft")
        // SF-LOCAL-BUILDER-005 extends this connected journey rather than
        // adding another near-identical import/typography/reopen launch.
        replaceComponentTextField("inspector.design.typography.size", with: "-", in: application)
        componentMenu("Preview", "Canvas Device Preview", in: application)
        XCTAssertTrue(application.staticTexts["workspace.editBoundary.status"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "workspace.editBoundary.status", containing: "Preview paused"))
        XCTAssertFalse(application.buttons["preview.done"].exists)
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.size"], containing: "-"))
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.size"], containing: "22"))
        selectInspectorTab("Layout", identifier: "layout", in: application)
        replaceComponentTextField("inspector.layout.width", with: "320", in: application)
        // File > Save must synchronously ask the live editor to finish before
        // it captures a package; no explicit Return or blur is sent first.
        componentMenu("File", "Save", in: application)
        XCTAssertTrue(waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 5))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "320"))
        let committedTextFrame = application.descendants(matching: .any)[textID].firstMatch.frame
        // Save commits the canonical edit without ending the native editor's
        // typing group. End that edit before testing a fresh native Undo group.
        application.textFields["inspector.layout.width"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "320"))
        revealComponentPointerTarget("inspector.layout.width", in: application).click()
        application.textFields["inspector.layout.width"].typeKey(.rightArrow, modifierFlags: .command)
        application.textFields["inspector.layout.width"].typeText("1")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "320"))
        XCTAssertEqual(application.descendants(matching: .any)[textID].firstMatch.frame, committedTextFrame)
        application.textFields["inspector.layout.width"].typeKey(.escape, modifierFlags: [])
        revealComponentPointerTarget("toolbar.undo", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "120"))
        revealComponentPointerTarget("toolbar.redo", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "320"))
        revealComponentPointerTarget("canvas.viewport.preset", in: application).click(); application.menuItems["Tablet"].click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        XCTAssertTrue(application.buttons["navigator.layer." + textID.replacingOccurrences(of: "canvas.object.", with: "")].isSelected)
        revealComponentPointerTarget("canvas.viewport.preset", in: application).click(); application.menuItems["Desktop"].click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-005 committed draft context and native versus document Undo")
        saveDocumentIfModified(in: application); terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("image-type-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        revealComponentPointerTarget("navigator.layer." + secondID.replacingOccurrences(of: "canvas.object.", with: ""), in: application).click()
        selectInspectorTab("Design", identifier: "design", in: application)
        XCTAssertTrue(application.staticTexts["workflow-picture-three.png"].waitForExistence(timeout: 5))
        revealComponentPointerTarget("navigator.layer." + textID.replacingOccurrences(of: "canvas.object.", with: ""), in: application).click()
        selectInspectorTab("Design", identifier: "design", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.family"], containing: "System"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.typography.size"], containing: "22"))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-004 asset and typography save reopen")
        componentMenu("Preview", "Canvas Device Preview", in: application)
        XCTAssertTrue(application.buttons["preview.done"].waitForExistence(timeout: 5))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-005 reopened committed canvas preview")
        application.buttons["preview.done"].click()
    }

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

        selectShellTab("Assets", directIdentifier: "navigator.tab.assets", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)
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
        // Commit left the field editor active. Select the same visible image
        // before exercising document Undo rather than native text Undo.
        let committedImage = canvasObject(named: committedAlt, in: application)
        XCTAssertTrue(waitForHittable(committedImage, in: application))
        let committedImageID = committedImage.identifier
        committedImage.click()
        XCTAssertTrue(hasKeyboardFocus(canvas))
        XCTAssertTrue(application.descendants(matching: .any)[committedImageID].firstMatch.isSelected)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let imageLayer = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Image"
        )).firstMatch
        XCTAssertTrue(imageLayer.waitForExistence(timeout: 5)); imageLayer.click()
        selectInspectorTab("Design", identifier: "design", in: application)
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
        selectInspectorTab("Design", identifier: "design", in: application)
        let imageFillStatus = application.descendants(matching: .any)["inspector.imageFill.status"].firstMatch
        XCTAssertTrue(imageFillStatus.waitForExistence(timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-061 Frame image fill empty")
        XCTAssertTrue(waitForValue(imageFillStatus, containing: "No image fill"))
        let chooseImage = application.descendants(matching: .any)["inspector.imageFill.choose"].firstMatch
        XCTAssertTrue(chooseImage.isHittable)
        chooseImage.click()
        let choices = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "asset.use.choose."))
        XCTAssertTrue(choices.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(choices.count, 1)
        choices.firstMatch.click()
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let frameLayer = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame"
        )).firstMatch
        XCTAssertTrue(frameLayer.waitForExistence(timeout: 5))
        frameLayer.click()
        selectInspectorTab("Design", identifier: "design", in: application)
        let reopenedImageFillStatus = application.descendants(matching: .any)["inspector.imageFill.status"].firstMatch
        XCTAssertTrue(waitForValue(reopenedImageFillStatus, containing: "Fit"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-061 Frame image fill reopened")

        // SF-AUTHORING-115: expose the already imported local AssetID from a
        // real Image child and verify the linked instance receives the native
        // media picker without serializing a path or test-only mutation.
        componentMenu("Component", "Create Component from Selection", in: application)
        componentMenu("Component", "Edit original component", in: application)
        XCTAssertTrue(application.buttons["components.exit"].waitForExistence(timeout: 3))
        revealComponentPointerTarget("navigator.tab.assets", in: application).click()
        let reusableAsset = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "assets.row.", "siteforge-image"
        )).firstMatch
        XCTAssertTrue(reusableAsset.waitForExistence(timeout: 3)); reusableAsset.click()
        revealComponentPointerTarget("assets.insert.selected", in: application).click()
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        let definitionImage = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Image")).firstMatch
        XCTAssertTrue(definitionImage.waitForExistence(timeout: 3)); definitionImage.click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("component.media.definition.name", with: "Hero Image", in: application)
        revealComponentPointerTarget("component.media.definition.apply", in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["component.media.status"], containing: "committed"))
        revealComponentPointerTarget("components.exit", in: application).click()
        let mediaPicker = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "component.media.value.")).firstMatch
        XCTAssertTrue(mediaPicker.waitForExistence(timeout: 3))
        XCTAssertTrue((mediaPicker.value as? String)?.contains("siteforge-image") == true)
        XCTAssertTrue(mediaPicker.isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-115 component image property")
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
        XCTAssertFalse(application.descendants(matching: .any)["canvas.empty.state"].exists)
        let emptyHint = application.descendants(matching: .any)["canvas.empty.hint"]
        XCTAssertTrue(emptyHint.waitForExistence(timeout: 5))
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        let gridToggle = application.descendants(matching: .any)["canvas.grid.toggle"]
        let gridWasOn = gridToggle.isSelected || (gridToggle.value as? NSNumber)?.intValue == 1
        grid.click()
        let liveGrid = application.descendants(matching: .any)["canvas.grid.toggle"]
        let gridIsOn = liveGrid.isSelected || (liveGrid.value as? NSNumber)?.intValue == 1
        XCTAssertEqual(gridIsOn, !gridWasOn)
        XCTAssertEqual(application.descendants(matching: .any)["status.document"].value as? String, initial)
        attachWindowScreenshot(application, named: "SF-AUTHORING-071 Quick Open Grid toggled")
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
            let action = title == "Header" ? "Insert Header at Page Top"
                : title == "Footer" ? "Insert Footer after Page Content" : "Insert \(title) at Center"
            componentMenu("Insert", action, in: application)
            XCTAssertTrue(waitForLiveCanvasValue(in: application,
                containing: "rendered objects \([1, 6, 7, 12][offset])", timeout: 5), title)
            XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label
                .localizedCaseInsensitiveContains(title), title)
            if offset < 3 { componentMenu("Selection", "Clear Selection", in: application) }
        }
        attachWindowScreenshot(application, named: "SF-AUTHORING-086-089 authored site and divider templates")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 7", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 12", timeout: 5))
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
        selectInspectorTab("Content", identifier: "content", in: application)
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
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
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
                selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
            selectInspectorTab("Content", identifier: "content", in: application)
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

        selectInspectorTab("Content", identifier: "content", in: application)
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

        selectInspectorTab("Accessibility", identifier: "accessibility", in: application)
        let accessibilityScroll = application.descendants(matching: .any)["inspector.selection.scroll"]
        XCTAssertTrue(accessibilityScroll.waitForExistence(timeout: 3))
        accessibilityScroll.scroll(byDeltaX: 0, deltaY: 1_000)
        XCTAssertTrue(waitForLiveValue(in: application,
                                       identifier: "inspector.accessibility.formField.kind",
                                       containing: "Email"))
        XCTAssertTrue(waitForLiveValue(in: application,
                                       identifier: "inspector.accessibility.formField.name",
                                       containing: "Work email"))
        XCTAssertTrue(waitForLiveValue(in: application,
                                       identifier: "inspector.accessibility.formField.required",
                                       containing: "Required"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-096 accessible Email field")

        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let form = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Form"
        )).firstMatch
        XCTAssertTrue(form.waitForExistence(timeout: 3))
        form.click()
        selectInspectorTab("Accessibility", identifier: "accessibility", in: application)
        XCTAssertTrue(application.descendants(matching: .any)["inspector.accessibility.form.status"]
            .waitForExistence(timeout: 3))
        let validate = application.buttons["inspector.accessibility.form.validate"]
        XCTAssertTrue(waitForHittable(validate, in: application))
        validate.click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.accessibility.form.validation"],
                                   containing: "field issue"))
        XCTAssertTrue(application.staticTexts["Submit controls"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-096 local validation and safe submit boundary")

        // Use the visible history controls for this accessibility journey so
        // the operation is owned by the live workspace state. Keyboard
        // routing is covered independently; synthesizing Command-Z against
        // the application element has an undefined AX frame after the native
        // validation button relinquishes focus and can target a stale menu
        // snapshot instead of the visible document window.
        let undo = application.buttons["toolbar.undo"]
        XCTAssertTrue(waitForEnabled(undo))
        undo.click()
        let redo = application.buttons["toolbar.redo"]
        XCTAssertTrue(waitForEnabled(redo))
        redo.click()
        // History may legitimately repair a selection while the immutable
        // canvas scene for the restored revision adopts. Re-select the
        // canonical Form through the shipping Layers surface before proving
        // the redone accessibility metadata, rather than querying a stale
        // Inspector proxy from the prior revision.
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let restoredForm = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Form"
        )).firstMatch
        XCTAssertTrue(restoredForm.waitForExistence(timeout: 3))
        restoredForm.click()
        selectInspectorTab("Accessibility", identifier: "accessibility", in: application)
        let liveAccessibilityScroll = application.descendants(matching: .any)["inspector.selection.scroll"]
        XCTAssertTrue(liveAccessibilityScroll.waitForExistence(timeout: 3))
        liveAccessibilityScroll.scroll(byDeltaX: 0, deltaY: 1_000)
        XCTAssertTrue(waitForLiveSemanticText(
            in: application,
            identifier: "inspector.accessibility.form.status",
            containing: "form"
        ))
    }

    // SF-AUTHORING-098, SF-0701-002/006, SF-0702-002/006, SF-1203-002/006
    // — the shipping Accessibility tab edits canonical metadata through the
    // same transaction used by keyboard/accessibility clients and the canvas
    // immediately republishes the authored semantic label.
    func testGeneralAccessibilityMetadataInspectorUndoRedoJourney() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectInspectorTab("Accessibility", identifier: "accessibility", in: application)
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
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        let heading = application.buttons["navigator.elements.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 3))
        XCTAssertTrue(heading.isEnabled)
        componentMenu("Insert", "Insert Heading at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertTrue(application.descendants(matching: .any)["status.selectionPath"].label
            .localizedCaseInsensitiveContains("Heading"))
        selectInspectorTab("Design", identifier: "design", in: application)
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
            selectShellTab("Components", directIdentifier: "navigator.tab.components", overflowIdentifier: "navigator.tab.overflow", in: application)
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

    // SF-AUTHORING-112, SF-0205-003/004/006/007, SF-0901-003/004/007,
    // SF-0902-002/006, SF-0907-003/004/006/007/008 — the native Components
    // surface exposes scene-local organization, dependency inspection and a
    // stable Where Used navigation path without mutating canonical content.
    func testComponentOrganizationDependencyInspectionAndWhereUsedJourney() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let selectedObject = canvasObject(named: "Frame", in: application).identifier
        componentMenu("Component", "Create Component from Selection", in: application)
        let overflow = application.descendants(matching: .any)["navigator.tab.overflow"]
        if overflow.exists && overflow.isHittable {
            overflow.click(); application.menuItems["Components"].click()
        } else {
            selectShellTab("Components", directIdentifier: "navigator.tab.components", overflowIdentifier: "navigator.tab.overflow", in: application)
        }
        XCTAssertTrue(application.popUpButtons["components.filter"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.popUpButtons["components.sort"].exists)
        let row = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "components.definition."
        )).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let definitionID = row.identifier.replacingOccurrences(of: "components.definition.", with: "")
        let details = application.buttons["components.details.\(definitionID)"]
        XCTAssertTrue(waitForHittable(details, in: application)); details.click()
        XCTAssertTrue(application.descendants(matching: .any)["components.dependencies"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.staticTexts["Where Used · 1"].exists)
        XCTAssertTrue(application.staticTexts["Static output: use Build Diagnostics for the current project revision."].exists)
        XCTAssertTrue(application.staticTexts["Replace Definition is unavailable in this bounded model because compatible replacement semantics are not yet specified."].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-112 component dependency inspection")

        let usage = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "components.usage."
        )).firstMatch
        XCTAssertTrue(waitForHittable(usage, in: application)); usage.click()
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["components.dependencies"]),
                      "Opening a usage must dismiss Component Details before adopting its selection")
        XCTAssertTrue(application.buttons["navigator.tab.layers"].waitForExistence(timeout: 3))
        let selectedNodeID = selectedObject.replacingOccurrences(of: "canvas.object.", with: "")
        let adopted = NSPredicate { _, _ in
            application.descendants(matching: .any)[selectedObject].firstMatch.exists
                && application.buttons["navigator.layer." + selectedNodeID].isSelected
        }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: adopted, object: application)], timeout: 5) == .completed,
                      "Where Used must adopt and select the original instance, not a same-named object")
        XCTAssertEqual(application.descendants(matching: .any).matching(identifier: selectedObject).count, 1)
        XCTAssertTrue(waitForLabel(
            application.descendants(matching: .any)["status.selectionPath"],
            containing: "Frame"
        ))
        attachWindowScreenshot(application, named: "SF-AUTHORING-112 Where Used selection")
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
        } else { selectShellTab("Components", directIdentifier: "navigator.tab.components", overflowIdentifier: "navigator.tab.overflow", in: application) }
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
        focusDocumentCommands(in: application)
        let undo = application.buttons["toolbar.undo"], redo = application.buttons["toolbar.redo"]
        application.typeKey("z", modifierFlags: .command)
        let restoredName = waitForLabel(application.descendants(matching: .any)["components.definition.\(id)"],
                                        containing: "Frame")
        if !restoredName {
            attachFocusDiagnostics(expected: "canvas.viewport.preset", application: application)
            let history = XCTAttachment(string: "Undo: \(String(describing: undo.value)); Redo: \(String(describing: redo.value))")
            history.name = "rename-after-undo-history"; history.lifetime = .keepAlways; add(history)
            attachWindowScreenshot(application, named: "Component rename document Undo failure")
        }
        XCTAssertTrue(restoredName)
        XCTAssertEqual(application.descendants(matching: .any)["components.definition.\(id)"].label,
                       "Frame")
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLabel(application.descendants(matching: .any)["components.definition.\(id)"],
                                   containing: "Feature Card"))
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        let cancel = application.buttons["quickOpen.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        XCTAssertTrue(cancel.isEnabled)
        // The production window intentionally remains 1100 points wide on a
        // narrower hosted display, where XCTest can synthesize a clipped
        // fallback click for the bottom button. Exercise the native macOS
        // cancellation key while retaining proof that the visible command is
        // present and enabled.
        application.typeKey(.escape, modifierFlags: [])
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

    @MainActor override func setUp() async throws {
        try await super.setUp()
        // Integration packages and recovery artifacts exercise descriptor-bound
        // application-owned I/O. Keep them in the same private temporary
        // container policy used by the package tests—not in a checkout whose
        // ancestor can be mediated by a File Provider.
        fixtureLease = try ApplicationOwnedTestFixture.create("ui")
        uiTestRunID = ProcessInfo.processInfo.environment["SITEFORGE_TEST_RUN_ID"]
            ?? UUID().uuidString.lowercased()
        launchStateRecords.removeAll(keepingCapacity: true)
    }

    @MainActor override func tearDown() async throws {
        for application in launchedApplications where application.state != .notRunning {
            application.terminate()
        }
        launchedApplications.removeAll()
        try fixtureLease?.cleanup()
        fixtureLease = nil
        try await super.tearDown()
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
        if application.state != .runningForeground { application.activate() }
        var liveField = field.elementType == .textView
            ? application.textViews[identifier]
            : application.textFields[identifier]
        if identifier.hasPrefix("inspector.") {
            let scroll = application.scrollViews["inspector.selection.scroll"]
            if scroll.exists, scroll.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists {
                // AXHittable alone can be true below the native scroll clip.
                // Reveal at use time: prior edits can move/replace the field.
                _ = revealStructuralLayoutControl(liveField, in: application)
                liveField = field.elementType == .textView
                    ? application.textViews[identifier] : application.textFields[identifier]
            }
        }
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
        let ready = NSPredicate { [weak application] _, _ in
            guard let application else { return false }
            // Opening replaces the launch/loading SwiftUI host. Resolve the
            // live host each time instead of retaining that replacement's proxy.
            let element = application.descendants(matching: .any)
                .matching(identifier: "workspace.shell").firstMatch
            return element.exists && element.label == "SiteForge workspace"
        }
        let result = window.waitForExistence(timeout: timeout)
            && XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: ready, object: application)],
                timeout: timeout
            ) == .completed
        if !result {
            let shell = application.descendants(matching: .any)
                .matching(identifier: "workspace.shell").firstMatch
            let state = XCTAttachment(string: "applicationState=\(application.state.rawValue); windowEnabled=\(window.isEnabled); shellExists=\(shell.exists); expectedWorkspaceLabel=\(shell.exists && shell.label == "SiteForge workspace"); sheets=\(application.sheets.count); dialogs=\(application.dialogs.count)")
            state.name = "workspace-live-readiness-state"; state.lifetime = .keepAlways; add(state)
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
        let controlIdentifier = controlExists && !control.identifier.isEmpty
            ? control.identifier : "unavailable"
        let details = """
        control=\(controlIdentifier)
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
        attachment.name = "pointer-failure-\(controlIdentifier)"
        attachment.lifetime = XCTAttachment.Lifetime.keepAlways
        add(attachment)
        attachScreenshot(named: "pointer-failure-\(controlIdentifier)")
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
        // A native sheet is its own AppKit window. The parent-window capture
        // can omit it, so retain the actual app-owned modal surface instead
        // of a misleading picture of the obscured editor or a desktop overlay.
        let surface = application.sheets.firstMatch.exists ? application.sheets.firstMatch : application.windows.firstMatch
        let attachment = XCTAttachment(screenshot: surface.screenshot())
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
        let staged = fixtureRoot.appendingPathComponent("legacy-\(name).siteforge.b64")
        guard name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }),
              let resources = Bundle(for: Self.self).resourceURL else {
            XCTFail("A valid bundled historical fixture is required."); return staged
        }
        do {
            let source = resources.appendingPathComponent("Legacy/\(name).siteforge.b64")
            let bytes = try Data(contentsOf: source)
            try bytes.write(to: staged, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
        } catch {
            XCTFail("The historical fixture could not be staged in owned temporary storage.")
        }
        return staged
    }

    func testBundledLegacyFixtureStagesExactBytesInOwnedTemporaryStorage() throws {
        let name = "schema-v4-legacy-surface"
        let staged = legacyFixtureURL(named: name)
        let resources = try XCTUnwrap(Bundle(for: Self.self).resourceURL)
        XCTAssertEqual(try Data(contentsOf: staged), try Data(contentsOf: resources.appendingPathComponent("Legacy/\(name).siteforge.b64")))
        XCTAssertTrue(staged.path.hasPrefix(fixtureRoot.path + "/"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: staged.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    private func makeLocalImageFixture(named name: String, palette: Int = 0) throws -> URL {
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
        let colors: (NSColor, NSColor) = palette == 1 ? (.systemTeal, .systemOrange)
            : palette == 2 ? (.systemGreen, .systemPurple) : (.systemOrange, .systemTeal)
        colors.0.setFill(); NSRect(x: 0, y: 0, width: 160, height: 180).fill()
        colors.1.setFill(); NSRect(x: 160, y: 0, width: 160, height: 180).fill()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func navigateReviewSavePanel(to directory: URL, in application: XCUIApplication) {
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
                      && isDirectory.boolValue, "The intended Save folder must exist")
        application.typeKey("g", modifierFlags: [.command, .shift])
        let folder = application.textFields["PathTextField"]
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        // Specify a directory, not a last-component completion candidate.
        let path = directory.path.hasSuffix("/") ? directory.path : directory.path + "/"
        replaceText(in: folder, with: path, application: application)
        XCTAssertTrue(folder.value as? String == path, "Go to Folder must contain the exact intended path")
        folder.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(application.textFields["PathTextField"]),
                      "Native Go to Folder must resolve the requested directory")
    }

    private func openProjectThroughNativePanel(_ url: URL, in application: XCUIApplication) {
        componentMenu("File", "Open…", in: application)
        XCTAssertTrue(waitForNativeOpenPanel(in: application))
        application.typeKey("g", modifierFlags: [.command, .shift])
        let path = application.textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 5))
        // Resolve the parent first: Go to Folder autocompletion can otherwise
        // enter the similarly named .siteforge.resources-v1 sidecar directory.
        replaceText(in: path, with: url.deletingLastPathComponent().path, application: application)
        path.typeKey(.return, modifierFlags: [])
        let package = application.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR value == %@", url.lastPathComponent, url.lastPathComponent
        )).firstMatch
        XCTAssertTrue(package.waitForExistence(timeout: 5), application.debugDescription)
        package.click()
        // The panel resolves the typed package asynchronously. A visible Open
        // button is not yet an enabled, validated file selection.
        let ready = XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let liveOpen = application.buttons["OKButton"]
                return liveOpen.exists && liveOpen.isEnabled && liveOpen.isHittable
            }, object: nil
        )], timeout: 5) == .completed
        if !ready {
            attachPointerDiagnostics(control: application.buttons["OKButton"], application: application)
            let hierarchy = XCTAttachment(string: application.debugDescription)
            hierarchy.name = "Native Open unresolved package hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        }
        XCTAssertTrue(ready, "Native Open must resolve the selected package before submission")
        guard ready else { return }
        application.buttons["OKButton"].click()
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
    // SF-0508-002/005/006, SF-0701-003/006. Source-only coverage added
    // during owner testing hold; this journey has NOT been executed.
    @MainActor
    func testPageBackgroundEntryUsesSharedFillEditorAndTransparentHistory() throws {
        let application = launchWorkspace()
        @MainActor func requireDarkPagePixel() throws {
            let capture = application.descendants(matching: .any)["canvas.interaction"].firstMatch.screenshot()
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: capture.pngRepresentation))
            let color = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2,
                y: Int(Double(bitmap.pixelsHigh) * 0.35))?.usingColorSpace(.sRGB))
            XCTAssertEqual(color.redComponent, 34.0 / 255, accuracy: 0.03)
            XCTAssertEqual(color.greenComponent, 51.0 / 255, accuracy: 0.03)
            XCTAssertEqual(color.blueComponent, 68.0 / 255, accuracy: 0.03)
        }
        let open = application.buttons["navigator.pages.background"]
        XCTAssertTrue(waitForHittable(open, in: application))
        open.click()
        XCTAssertTrue(application.descendants(matching: .any)["inspector.pageBackground.value"].waitForExistence(timeout: 5))
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"), "Selecting page structure must not fabricate a canvas object")
        let hex = application.textFields["inspector.design.fillHex"]
        replaceStructuralLayoutField(hex, with: "#223344FF", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.pageBackground.value"], containing: "#223344FF"))
        try requireDarkPagePixel()
        attachWindowScreenshot(application, named: "SF-PAGE-BACKGROUND shared authored fill")
        application.buttons["inspector.pageBackground.none"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.pageBackground.value"], containing: "Transparent / None"))
        focusDocumentCommands(in: application)
        application.buttons["toolbar.undo"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.pageBackground.value"], containing: "#223344FF"))
        try requireDarkPagePixel()
        application.buttons["toolbar.redo"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.pageBackground.value"], containing: "Transparent / None"))
        attachWindowScreenshot(application, named: "SF-PAGE-BACKGROUND transparent redo")
        application.buttons["navigator.tab.layers"].click()
        let roots = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND value CONTAINS %@", "navigator.layer.", "Page structure"))
        XCTAssertEqual(roots.count, 1)
        XCTAssertFalse((roots.firstMatch.value as? String ?? "").contains("Hidden"))
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 0"))
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
        selectNavigatorTab("Components", identifier: "components", in: application)
        selectInspectorTab("Accessibility", identifier: "accessibility", in: application)
        assertElement(application.buttons["navigator.tab.components"],
                      isContainedIn: application.descendants(matching: .any)["shell.navigator"])
        assertElement(application.buttons["inspector.tab.accessibility"],
                      isContainedIn: application.descendants(matching: .any)["shell.inspector"])
        attachWindowScreenshot(application, named: "SF-UI-009 compact selected tab labels fully revealed")

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
            let owner = identifier.hasPrefix("canvas.empty.")
                ? application.descendants(matching: .any)["canvas.viewport.surface"] : viewportControls
            assertElement(control, isContainedIn: owner, identifier)
        }

        application.buttons["canvas.empty.insert.frame"].click()
        let canvas = application.descendants(matching: .any)["canvas.interaction"].firstMatch
        XCTAssertTrue(waitForValue(canvas, containing: "rendered objects 1"))
        selectInspectorTab("Design", identifier: "design", in: application)

        let inspector = application.descendants(matching: .any)["shell.inspector"]
        let inspectorScroll = application.descendants(matching: .any)["inspector.selection.scroll"]
        XCTAssertTrue(inspectorScroll.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(inspector.frame.width, 280 - 2)
        assertElement(inspectorScroll, isContainedIn: inspector)

        // Native AX hittability alone can include a partly clipped row. Use
        // the shared complete-frame, live-control pointer contract instead.
        let addGradient = revealStructuralLayoutControl(
            application.buttons["inspector.design.layers.addGradient"], in: application)
        XCTAssertTrue(waitForHittable(addGradient, in: application))
        assertElement(addGradient, isContainedIn: inspectorScroll)
        addGradient.click()
        let angle = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier CONTAINS %@", ".angle"))
            .firstMatch
        XCTAssertTrue(angle.waitForExistence(timeout: 5))
        let gradientPrefix = angle.identifier.replacingOccurrences(of: ".angle", with: "")
        let addStopIdentifier = "\(gradientPrefix).addStop"
        for _ in 0..<4 {
            let addStop = revealStructuralLayoutControl(application.buttons[addStopIdentifier], in: application)
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
        // A hittable remove button can still belong to a partly clipped row.
        // Reveal the complete compound row before asserting every subcontrol.
        for _ in 0..<8 {
            if inspectorScroll.frame.insetBy(dx: -1, dy: -1).contains(lastRow.frame) { break }
            if lastRow.frame.maxY > inspectorScroll.frame.maxY {
                inspectorScroll.scroll(byDeltaX: 0, deltaY: -100)
            } else if lastRow.frame.minY < inspectorScroll.frame.minY {
                inspectorScroll.scroll(byDeltaX: 0, deltaY: 100)
            } else { break }
        }
        assertElement(lastRow, isContainedIn: inspectorScroll)
        let stopLabel = application.staticTexts["Stop 6"]
        XCTAssertTrue(stopLabel.exists)
        XCTAssertLessThanOrEqual(stopLabel.frame.height, 20, "The standard caption must remain on one readable line.")
        assertElement(stopLabel, isContainedIn: lastRow)
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
        selectNavigatorTab("Components", identifier: "components", in: application)
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
        componentMenu("Component", "Edit original component", in: application)
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
        componentMenu("Component", "Edit original component", in: application)
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

    // SF-0902-002/004/006, SF-0905-002/005/006: source-only Prompt-4
    // acceptance; execute at the accumulated Prompt-10 gate.
    func testComponentActionNativeInspectorDraftResetHistoryAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("component-actions.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let instanceID = canvasObject(named: "Frame", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Link at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + instanceID, in: application).click()
        componentMenu("Component", "Create Component from Selection", in: application)
        componentMenu("Component", "Edit original component", in: application)
        let linkRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Link")).firstMatch
        XCTAssertTrue(linkRow.waitForExistence(timeout: 5))
        revealComponentPointerTarget(linkRow.identifier, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("component.action.definition.name", with: "Destination", in: application)
        revealComponentPointerTarget("component.action.definition.apply", in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["component.action.status"], containing: "committed"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-117 exposed Link action")
        revealComponentPointerTarget("components.exit", in: application).click()
        let type = application.popUpButtons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "component.action.target.", ".type")).firstMatch
        XCTAssertTrue(type.waitForExistence(timeout: 5))
        let propertyID = type.identifier.replacingOccurrences(of: "component.action.target.", with: "").replacingOccurrences(of: ".type", with: "")
        let typeID = type.identifier, urlID = "component.action.target." + propertyID + ".url"
        revealComponentPointerTarget(typeID, in: application).click()
        application.menuItems["External HTTP(S)"].click()
        replaceComponentTextField(urlID, with: "https://example.com/component-action", in: application)
        application.textFields[urlID].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.staticTexts["component.action.provenance." + propertyID], containing: "Set here · this instance"))
        XCTAssertTrue(waitForValue(application.textFields[urlID], containing: "https://example.com/component-action"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-117 authored external action")
        replaceComponentTextField(urlID, with: "javascript:invalid", in: application)
        revealComponentPointerTarget("component.action.apply." + propertyID, in: application).click()
        XCTAssertTrue(application.staticTexts["component.action.validation." + propertyID].waitForExistence(timeout: 5))
        application.textFields[urlID].click()
        application.textFields[urlID].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields[urlID], containing: "https://example.com/component-action"))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts["component.action.provenance." + propertyID], containing: "Uses component default"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.textFields[urlID], containing: "https://example.com/component-action"))
        revealComponentPointerTarget("component.action.reset." + propertyID, in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["component.action.provenance." + propertyID], containing: "Uses component default"))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields[urlID], containing: "https://example.com/component-action"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-117 exact reset undo and cancelled draft")
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("component-action-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + instanceID, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[urlID], containing: "https://example.com/component-action"))
        XCTAssertTrue(waitForValue(application.staticTexts["component.action.provenance." + propertyID], containing: "Set here · this instance"))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, "canvas.object." + instanceID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-117 reopened action and stable instance")
    }

    // SF-0902/0903/0905: source-only fallback acceptance; supplied-content
    // ownership is explicitly unavailable pending OD-018.
    func testInspectorWorkflowSearchPinGeometryPasteUndoAndMixedJourney() throws {
        let project = fixtureRoot.appendingPathComponent("inspector-workflow.siteforge")
        let application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let firstFrameID = canvasObject(named: "Frame", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        revealComponentPointerTarget("inspector.tab.layout", in: application).click()
        replaceComponentTextField("inspector.workflow.search", with: "width", in: application)
        application.textFields["inspector.workflow.search"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.buttons["inspector.workflow.section.layout"].exists)
        revealComponentPointerTarget("inspector.workflow.pin", in: application).click()
        XCTAssertTrue(waitForValue(application.buttons["inspector.workflow.pin"], containing: "Pinned"))
        replaceComponentTextField("inspector.layout.width", with: "320", in: application)
        application.textFields["inspector.layout.width"].typeKey(.return, modifierFlags: [])
        revealComponentPointerTarget("inspector.workflow.copy", in: application).click()
        replaceComponentTextField("inspector.layout.width", with: "280", in: application)
        application.textFields["inspector.layout.width"].typeKey(.return, modifierFlags: [])
        revealComponentPointerTarget("inspector.workflow.paste", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "320"))
        application.typeKey("z", modifierFlags: [.command])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "280"))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "320"))
        replaceComponentTextField("inspector.workflow.search", with: "no matching properties", in: application)
        XCTAssertTrue(application.staticTexts["inspector.workflow.empty"].exists)
        application.textFields["inspector.workflow.search"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(application.buttons["inspector.workflow.section.design"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-124 Inspector search pins typed paste and exact undo redo")
        componentMenu("Selection", "Clear Selection", in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        let secondRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@ AND identifier != %@",
            "navigator.layer.", "Frame", "navigator.layer." + firstFrameID)).firstMatch
        XCTAssertTrue(secondRow.waitForExistence(timeout: 5))
        let secondID = secondRow.identifier
        revealComponentPointerTarget("navigator.layer." + firstFrameID, in: application).click()
        let liveSecondRow = revealComponentPointerTarget(secondID, in: application)
        XCUIElement.perform(withKeyModifiers: .shift) { liveSecondRow.click() }
        XCTAssertTrue(application.buttons["navigator.layer." + firstFrameID].isSelected)
        XCTAssertTrue(application.buttons[secondID].isSelected)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.selectionPath"], containing: "2 selected"))
        // Selection replacement recreates the contextual Inspector with its
        // tools disclosure collapsed. Reveal that real shipping surface before
        // asserting its mixed-state explanation and disabled Copy action.
        let mixedExplanation = revealComponentPointerTarget("inspector.workflow.transfer.mixed", in: application)
        XCTAssertTrue(mixedExplanation.exists)
        XCTAssertFalse(application.buttons["inspector.workflow.copy"].isEnabled)
        revealComponentPointerTarget("inspector.workflow.paste", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.width"], containing: "320"))
        XCTAssertTrue(application.buttons["navigator.layer." + firstFrameID].isSelected)
        XCTAssertTrue(application.buttons[secondID].isSelected)
        attachWindowScreenshot(application, named: "SF-AUTHORING-124 mixed values unified atomically with selection retained")
    }

    func testComponentPropertyDiscoveryNativeSearchClearTraversalAndContextJourney() throws {
        let project = fixtureRoot.appendingPathComponent("component-property-discovery.siteforge")
        let application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let frameID = canvasObject(named: "Frame", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + frameID, in: application).click()
        componentMenu("Component", "Create Component from Selection", in: application)
        componentMenu("Component", "Edit original component", in: application)
        let textRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text")).firstMatch
        XCTAssertTrue(textRow.waitForExistence(timeout: 5)); revealComponentPointerTarget(textRow.identifier, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("component.text.definition.name", with: "Editorial Title", in: application)
        revealComponentPointerTarget("component.text.definition.apply", in: application).click()
        revealComponentPointerTarget("components.exit", in: application).click()
        replaceComponentTextField("component.discovery.search", with: "text inherited", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts["component.discovery.count"], containing: "1 matching"))
        application.textFields["component.discovery.search"].typeKey(.return, modifierFlags: [])
        application.typeKey(.tab, modifierFlags: [])
        let field = application.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component.text.value.")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(hasKeyboardFocus(field))
        replaceComponentTextField("component.discovery.search", with: "unmatched", in: application)
        XCTAssertTrue(application.staticTexts["component.discovery.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(application.buttons["component.discovery.next"].isEnabled)
        application.textFields["component.discovery.search"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.staticTexts["component.discovery.count"], containing: "1 matching"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-123 component discovery restored and keyboard traversal")
        componentMenu("Component", "Edit original component", in: application)
        revealComponentPointerTarget("components.exit", in: application).click()
        XCTAssertEqual(application.textFields["component.discovery.search"].value as? String, "")
        XCTAssertTrue(waitForValue(application.staticTexts["component.discovery.count"], containing: "1 matching"))
    }

    func testComponentPropertyOrganizationNativeKeyboardCancelHistoryAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("component-property-organization.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let instanceID = canvasObject(named: "Frame", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + instanceID, in: application).click()
        componentMenu("Component", "Create Component from Selection", in: application)
        componentMenu("Component", "Edit original component", in: application)
        let textRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text")).firstMatch
        XCTAssertTrue(textRow.waitForExistence(timeout: 5)); revealComponentPointerTarget(textRow.identifier, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("component.text.definition.name", with: "Title", in: application)
        replaceComponentTextField("component.text.definition.default", with: "Shared Title", in: application)
        revealComponentPointerTarget("component.text.definition.apply", in: application).click()
        let group = application.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component.organization.group.text:")).firstMatch
        XCTAssertTrue(group.waitForExistence(timeout: 5)); let groupID = group.identifier
        replaceComponentTextField(groupID, with: "Editorial", in: application)
        application.textFields[groupID].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields[groupID], containing: "Editorial"))
        XCTAssertTrue(waitForValue(application.staticTexts["component.organization.status"], containing: "committed"))
        replaceComponentTextField(groupID, with: "Discarded group", in: application)
        application.textFields[groupID].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields[groupID], containing: "Editorial"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-119 definition organization and cancelled draft")
        revealComponentPointerTarget("components.exit", in: application).click()
        let groupedID = "component.organization.instance.group.named.Editorial"
        XCTAssertTrue(application.descendants(matching: .any)[groupedID].waitForExistence(timeout: 5))
        let field = application.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component.text.value.")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); let fieldID = field.identifier
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Shared Title"))
        XCTAssertTrue(waitForComponentRenderedText("Shared Title", in: application))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(application.descendants(matching: .any)["component.organization.instance.group.default"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Shared Title"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(application.descendants(matching: .any)[groupedID].waitForExistence(timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, "canvas.object." + instanceID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-119 grouped inherited instance and unchanged render")
        saveDocumentIfModified(in: application); terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("organization-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + instanceID, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        XCTAssertTrue(application.descendants(matching: .any)[groupedID].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Shared Title"))
        XCTAssertTrue(waitForComponentRenderedText("Shared Title", in: application))
        attachWindowScreenshot(application, named: "SF-AUTHORING-119 reopened property group and stable identity")
    }

    func testComponentRetainedOverrideRecoveryConfirmationUndoAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("component-override-recovery.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let instanceID = canvasObject(named: "Frame", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + instanceID, in: application).click()
        componentMenu("Component", "Create Component from Selection", in: application)
        componentMenu("Component", "Edit original component", in: application)
        let textRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text")).firstMatch
        XCTAssertTrue(textRow.waitForExistence(timeout: 5)); let sourceID = textRow.identifier
        revealComponentPointerTarget(sourceID, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("component.text.definition.name", with: "Title", in: application)
        replaceComponentTextField("component.text.definition.default", with: "Default title", in: application)
        revealComponentPointerTarget("component.text.definition.apply", in: application).click()
        revealComponentPointerTarget("components.exit", in: application).click()
        let textField = application.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component.text.value.")).firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 5)); let valueID = textField.identifier
        let bindingID = valueID.replacingOccurrences(of: "component.text.value.", with: "")
        replaceComponentTextField(valueID, with: "Retained title", in: application)
        application.textFields[valueID].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForComponentRenderedText("Retained title", in: application))
        componentMenu("Component", "Edit original component", in: application)
        revealComponentPointerTarget(sourceID, in: application).click()
        revealComponentPointerTarget("component.text.definition.remove", in: application).click()
        revealComponentPointerTarget("components.exit", in: application).click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["component.recovery.summary"], containing: "1 custom value needs attention"))
        let resetID = "component.recovery.reset.text:" + bindingID
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["component.recovery.value.text:" + bindingID], containing: "Retained title"))
        revealComponentPointerTarget(resetID, in: application).click()
        assertComponentRecoveryConfirmation(in: application)
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(application.staticTexts["Remove affected custom values?"]))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["component.recovery.summary"], containing: "1 custom value needs attention"))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, "canvas.object." + instanceID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-120 retained conflict and cancelled reset")
        revealComponentPointerTarget("component.recovery.definition.reveal", in: application).click()
        XCTAssertTrue(application.buttons["components.exit"].waitForExistence(timeout: 3))
        componentMenu("Edit", "Undo", in: application)
        revealComponentPointerTarget("components.exit", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[valueID], containing: "Retained title"))
        XCTAssertFalse(application.descendants(matching: .any)["component.recovery.summary"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-120 original binding restored with stable override")
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["component.recovery.summary"], containing: "1 custom value needs attention"))
        saveDocumentIfModified(in: application); terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("override-conflict-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + instanceID, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["component.recovery.summary"], containing: "1 custom value needs attention"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-120 reopened retained authored intent")
        revealComponentPointerTarget("component.recovery.resetAll", in: application).click()
        let confirmation = assertComponentRecoveryConfirmation(in: application)
        confirmation.buttons["component.recovery.confirm"].click()
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["component.recovery.summary"]))
        XCTAssertTrue(waitForValue(application.staticTexts["component.organization.status"], containing: "Removed 1 affected custom value"))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["component.recovery.summary"], containing: "1 custom value needs attention"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["component.recovery.summary"]))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, "canvas.object." + instanceID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-120 confirmed reset and exact history")
    }

    @discardableResult
    private func assertComponentRecoveryConfirmation(in application: XCUIApplication) -> XCUIElement {
        // Native macOS confirmation sheets need not have XCUI's Alert role.
        // Require the actual title and both visible actions, not an unrelated
        // container classification or a merely present background reset button.
        let sheet = application.sheets.containing(.button, identifier: "component.recovery.confirm").firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 3), application.debugDescription)
        XCTAssertTrue(sheet.staticTexts["Remove affected custom values?"].exists, application.debugDescription)
        for identifier in ["component.recovery.confirm", "component.recovery.cancel"] {
            let actions = sheet.buttons.matching(identifier: identifier)
            XCTAssertEqual(actions.count, 1, "Confirmation must expose one unambiguous on-screen action")
            let action = actions.firstMatch
            XCTAssertTrue(action.exists && action.isEnabled && action.isHittable, application.debugDescription)
        }
        return sheet
    }

    func testConnectedNestedSectionContainerGeometryAndBreakpointJourney() throws {
        let application = launchWorkspace()
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        componentMenu("Insert", "Insert Section in Flow", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        componentMenu("Insert", "Insert Stack at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        let stackID = canvasObject(named: "Stack", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        // Each chrome owner contains its real content Stack, title, navigation
        // and Home link; they are canonical rendered nodes, not fixture chrome.
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 7", timeout: 5))
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 12", timeout: 5))
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("inspector.flow.height", with: "240", in: application)
        application.textFields["inspector.flow.height"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.flow.height"], containing: "240"))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.flow.height"], containing: "200"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.flow.height"], containing: "240"))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + stackID, in: application).click()
        componentMenu("Insert", "Insert Grid at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 13", timeout: 5))
        componentMenu("Insert", "Insert Section in Flow", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 14", timeout: 5))
        let selected = application.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "canvas.object."))
            .allElementsBoundByIndex.filter(\.isSelected)
        XCTAssertEqual(selected.count, 1)
        let nestedID = try XCTUnwrap(selected.first?.identifier)
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        XCTAssertTrue(application.descendants(matching: .any)["inspector.flow.resolved"].waitForExistence(timeout: 5))
        for presetName in ["Desktop", "Tablet", "Mobile", "Desktop"] {
            application.descendants(matching: .any)["canvas.viewport.preset"].click()
            application.menuItems[presetName].click()
            XCTAssertTrue(waitForValue(application.descendants(matching: .any)["canvas.viewport.preset"], containing: presetName))
            application.buttons["canvas.zoom.fit"].click()
            // Closed Mobile navigation retains both Home link nodes in Layers
            // but excludes their canvas pixels/hit/AX surfaces, leaving 12.
            let expectedRenderedCount = presetName == "Mobile" ? 12 : 14
            XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects \(expectedRenderedCount)", timeout: 5))
            let object = application.descendants(matching: .any)[nestedID]
            XCTAssertTrue(object.waitForExistence(timeout: 5)); XCTAssertTrue(object.isSelected)
            XCTAssertGreaterThan(object.frame.width, 0); XCTAssertGreaterThan(object.frame.height, 0)
            XCTAssertTrue(application.descendants(matching: .any)["inspector.flow.provenance"].exists)
            attachWindowScreenshot(application, named: "SF-AUTHORING-122 nested Grid Section \(presetName) resolved selection")
        }
    }

    // SF-0303/0308, SF-0502, SF-0701/0702, SF-0806: matched public controls,
    // not a model shortcut or a percentage inferred from screenshots.
    func testRelatedPageReuseControlsAtPracticalMinimum() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWindowSize", "minimum", "-SiteForgeUITestWindowAlignment", TestWindowAlignment.right.rawValue])
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        let source = canvasObject(named: "Header", in: application).identifier
        selectInspectorTab("Content", identifier: "content", in: application)
        let include = revealStructuralLayoutControl(application.buttons["inspector.navigation.includeAll"], in: application)
        assertElement(include, isContainedIn: application.descendants(matching: .any)["shell.inspector"])
        attachWindowScreenshot(application, named: "Workflow reuse compact Header controls")
        componentMenu("Page", "New Page…", in: application)
        let toggle = application.checkBoxes["page.editor.copyCurrent"]
        XCTAssertTrue(waitForHittable(toggle, in: application))
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 0, "New Page remains blank unless copying is explicitly selected")
        assertElement(toggle, isContainedIn: application.sheets.firstMatch)
        toggle.click()
        attachWindowScreenshot(application, named: "Workflow reuse compact copy page sheet")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(application.textFields["page.editor.name"]))
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, source)
        componentMenu("Page", "New Page…", in: application)
        XCTAssertTrue(application.checkBoxes["page.editor.copyCurrent"].waitForExistence(timeout: 5))
        XCTAssertEqual((application.checkBoxes["page.editor.copyCurrent"].value as? NSNumber)?.intValue, 0,
            "Cancelled copy intent must not leak into a later blank page request")
        application.typeKey(.escape, modifierFlags: [])
    }

    func testContextualTypographyReturnTabEscapeAndColorTargetJourney() throws {
        let application = launchWorkspace(); assertNormalWindowPolicy(in: application)
        application.buttons["canvas.empty.insert.text"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectInspectorTab("Design", identifier: "design", in: application)
        let textObject = canvasObject(named: "Text object", in: application)
        XCTAssertTrue(textObject.waitForExistence(timeout: 5))
        XCTAssertTrue(textObject.isSelected)
        let node = textObject.identifier
        let height = revealStructuralLayoutControl(application.textFields["inspector.layout.height"], in: application)
        replaceText(in: height, with: "80", application: application)
        height.typeKey(.return, modifierFlags: [])
        let size = revealStructuralLayoutControl(application.textFields["inspector.design.typography.size"], in: application)
        replaceText(in: size, with: "22", application: application)
        size.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.design.typography.size", containing: "22"))
        size.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(identifier: "inspector.design.typography.lineHeight", in: application))
        let line = application.textFields["inspector.design.typography.lineHeight"]
        replaceText(in: line, with: "30", application: application)
        line.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(identifier: "inspector.design.typography.tracking", in: application))
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.design.typography.lineHeight", containing: "30"))
        let tracking = application.textFields["inspector.design.typography.tracking"]
        replaceText(in: tracking, with: "invalid", application: application)
        tracking.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["inspector.design.validation"].waitForExistence(timeout: 3))
        tracking.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.design.typography.tracking", containing: "0"))
        XCTAssertTrue(application.descendants(matching: .any)[node].exists)
        XCTAssertTrue(application.descendants(matching: .any)[node].isSelected)
        let target = revealStructuralLayoutControl(application.popUpButtons["inspector.tokens.target"], in: application)
        XCTAssertTrue(waitForValue(target, containing: "Text Foreground"))
        attachWindowScreenshot(application, named: "Workflow typography Return Tab Escape contextual colors")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.design.typography.lineHeight", containing: "17"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.design.typography.lineHeight", containing: "30"))
        attachWindowScreenshot(application, named: "Workflow typography exact Undo Redo without destination changes")
    }

    func testRelatedPageReuseNavigationActionAuditAndNativeReopenJourney() throws {
        continueAfterFailure = false
        let project = fixtureRoot.appendingPathComponent("related-page-workflow.siteforge")
        // Stage only starting bytes. A fixture-writing process argument would
        // seed the original package again when native Open creates a new scene.
        let encoded = try String(contentsOf: legacyFixtureURL(named: "schema-v4-legacy-surface"), encoding: .utf8)
        let bytes = try XCTUnwrap(Data(base64Encoded: encoded.filter { !$0.isWhitespace }))
        try bytes.write(to: project, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: project.path)
        let application = trackedApplication()
        application.launchArguments += baseLaunchArguments()
        recordLaunchState("before-real-welcome", application)
        application.launch(); application.activate()
        recordLaunchState("after-real-welcome", application)
        XCTAssertTrue(application.buttons["launch.newBlankProject"].waitForExistence(timeout: 5))
        openProjectThroughNativePanel(project, in: application)
        XCTAssertTrue(waitForWorkspaceReady(application, timeout: 8)); assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        let originalHeader = canvasObject(named: "Header", in: application).identifier
        componentMenu("Selection", "Clear Selection", in: application)
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        let sourceRow = pageRow(named: "Legacy Surface", in: application)
        let sourceID = sourceRow.identifier
        attachWindowScreenshot(application, named: "Workflow reuse independent source page")

        var phase = ""
        var clicks: [String: [String]] = [:]
        @MainActor func tap(_ element: XCUIElement, _ action: String) {
            XCTAssertTrue(waitForHittable(element, in: application), action)
            XCTAssertTrue(element.isEnabled, action)
            element.click()
            if !phase.isEmpty { clicks[phase, default: []].append(action) }
        }
        @MainActor func pageMenu(_ action: String) {
            tap(application.menuBars.menuBarItems["Page"], "Open Page menu")
            tap(application.menuItems[action], action)
        }
        @MainActor func draft(_ identifier: String, _ value: String) {
            let field = application.textFields[identifier]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            tap(field, "Focus " + identifier)
            XCTAssertTrue(waitForKeyboardFocus(identifier: identifier, in: application))
            field.typeKey(.leftArrow, modifierFlags: .command)
            field.typeKey(.rightArrow, modifierFlags: [.command, .shift])
            field.typeKey(.delete, modifierFlags: [])
            field.typeText(value)
        }

        // Add a real destination after authoring the source Header, so the
        // matched navigation task has two genuinely missing destinations.
        pageMenu("New Page…")
        draft("page.editor.name", "Contact")
        draft("page.editor.route", "/contact")
        tap(application.buttons["page.editor.apply"], "Create comparison destination")
        tap(pageRow(named: "Legacy Surface", in: application), "Select source")
        phase = "old-page"
        pageMenu("Duplicate Page")
        XCTAssertTrue(pageRow(named: "Legacy Surface Copy", in: application).waitForExistence(timeout: 5))
        pageMenu("Rename Page…")
        draft("page.editor.name", "Related")
        tap(application.buttons["page.editor.apply"], "Apply name")
        pageMenu("Edit Route…")
        draft("page.editor.route", "/related")
        tap(application.buttons["page.editor.apply"], "Apply route")
        XCTAssertTrue(pageRow(named: "Related", in: application).waitForExistence(timeout: 5))

        phase = ""
        for _ in 0..<3 { componentMenu("Edit", "Undo", in: application) }
        XCTAssertTrue(waitForNonexistence(pageRow(named: "Related", in: application)))
        tap(pageRow(named: "Legacy Surface", in: application), "Select unchanged source")
        XCTAssertEqual(pageRow(named: "Legacy Surface", in: application).identifier, sourceID)
        phase = "new-page"
        pageMenu("New Page…")
        draft("page.editor.name", "Related")
        draft("page.editor.route", "/related")
        tap(application.checkBoxes["page.editor.copyCurrent"], "Copy current page content")
        attachWindowScreenshot(application, named: "Workflow reuse named independent page copy")
        tap(application.buttons["page.editor.apply"], "Apply name route and content")
        let copied = pageRow(named: "Related", in: application)
        XCTAssertTrue(copied.waitForExistence(timeout: 5))
        XCTAssertTrue(copied.label.contains("/related"))
        let copyID = copied.identifier
        phase = ""
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForNonexistence(pageRow(named: "Related", in: application)))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(pageRow(named: "Related", in: application).waitForExistence(timeout: 5))
        XCTAssertEqual(pageRow(named: "Related", in: application).identifier, copyID)
        tap(pageRow(named: "Related", in: application), "Select redone page")
        selectStructuralLayer("Header", in: application)
        let copiedHeader = canvasObject(named: "Header", in: application).identifier
        XCTAssertNotEqual(copiedHeader, originalHeader)
        selectInspectorTab("Content", identifier: "content", in: application)
        let missing = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "inspector.navigation.include."
        )).allElementsBoundByAccessibilityElement.filter { ($0.value as? NSNumber)?.intValue == 0 }.map(\.identifier)
        XCTAssertEqual(missing.count, 2, "Only the source and Contact are absent from this independent copy")
        phase = "old-navigation"
        for identifier in missing {
            let control = revealStructuralLayoutControl(application.descendants(matching: .any)[identifier], in: application)
            tap(control, "Include one page")
        }
        phase = ""
        for _ in missing { componentMenu("Edit", "Undo", in: application) }
        for identifier in missing {
            XCTAssertEqual((application.descendants(matching: .any)[identifier].value as? NSNumber)?.intValue, 0)
        }
        phase = "new-navigation"
        tap(revealStructuralLayoutControl(application.buttons["inspector.navigation.includeAll"], in: application), "Include All Pages")
        phase = ""
        for identifier in missing {
            XCTAssertEqual((application.descendants(matching: .any)[identifier].value as? NSNumber)?.intValue, 1)
        }
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, copiedHeader)
        attachWindowScreenshot(application, named: "Workflow reuse all pages included atomically")
        componentMenu("Edit", "Undo", in: application)
        for identifier in missing {
            XCTAssertEqual((application.descendants(matching: .any)[identifier].value as? NSNumber)?.intValue, 0)
        }
        componentMenu("Edit", "Redo", in: application)
        attachWindowScreenshot(application, named: "Workflow reuse navigation Undo Redo")
        let audit = XCTAttachment(data: try JSONSerialization.data(withJSONObject: [
            "unit": "actual pointer activations; text-entry keystrokes excluded equally",
            "pointerActions": clicks
        ], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        audit.name = "Workflow matched public-control action audit"; audit.lifetime = .keepAlways; add(audit)
        XCTAssertLessThan(clicks["new-page", default: []].count, clicks["old-page", default: []].count)
        XCTAssertLessThan(clicks["new-navigation", default: []].count, clicks["old-navigation", default: []].count)

        saveDocumentIfModified(in: application)
        let savedPackage = try Data(contentsOf: project)
        let title = application.windows.firstMatch.title
        application.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForNonexistence(application.windows[title]))
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["workspace.shell"]),
            "Native Close must remove the document workspace before reopening")
        openProjectThroughNativePanel(project, in: application)
        XCTAssertTrue(waitForWorkspaceReady(application))
        XCTAssertTrue(try Data(contentsOf: project) == savedPackage,
            "Native reopen must preserve saved bytes, never reseed the historical starting fixture")
        selectShellTab("Pages", directIdentifier: "navigator.tab.pages", overflowIdentifier: "navigator.tab.overflow", in: application)
        XCTAssertTrue(pageRow(named: "Related", in: application).waitForExistence(timeout: 5))
        XCTAssertEqual(pageRow(named: "Related", in: application).identifier, copyID)
        tap(pageRow(named: "Legacy Surface", in: application), "Inspect original page")
        selectStructuralLayer("Header", in: application)
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, originalHeader)
        selectInspectorTab("Content", identifier: "content", in: application)
        for name in ["Contact", "Related"] {
            let choice = application.descendants(matching: .any).matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@", "inspector.navigation.include.", name)).firstMatch
            XCTAssertEqual((choice.value as? NSNumber)?.intValue, 0, "Copy/navigation edits must not rewrite the source Header")
        }
        attachWindowScreenshot(application, named: "Workflow reuse reopened original remains independent")
    }

    // SF-SOURCE-BATCH-20261027-02 — new source only; not run under owner hold.
    @MainActor
    // SF-LOCAL-BUILDER-010: ordinary page/chrome controls.
    func testCopyHeaderFooterToPagesIndependentAtomicUndoAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("chrome-reuse-native.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        let sourceHeader = canvasObject(named: "Header", in: application).identifier
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: "Studio Header", in: application)
        XCTAssertTrue(waitForComponentRenderedText("Studio Header", in: application))
        componentMenu("Insert", "Insert Section in Flow", in: application)
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: "Studio Footer", in: application)
        XCTAssertTrue(waitForComponentRenderedText("Studio Footer", in: application))
        attachWindowScreenshot(application, named: "SF-CHROME source editable Header body Footer")
        for (name, route) in [("Contact", "/contact"), ("Journal", "/journal")] {
            componentMenu("Page", "New Page…", in: application)
            XCTAssertTrue(application.textFields["page.editor.name"].waitForExistence(timeout: 5))
            replaceText(in: application.textFields["page.editor.name"], with: name, application: application)
            replaceText(in: application.textFields["page.editor.route"], with: route, application: application)
            XCTAssertEqual((application.checkBoxes["page.editor.copyCurrent"].value as? NSNumber)?.intValue, 0)
            application.buttons["page.editor.apply"].click()
            XCTAssertTrue(waitForNonexistence(application.textFields["page.editor.name"]))
        }
        pageRow(named: "Legacy Surface", in: application).click()
        XCTAssertTrue(waitForComponentRenderedText("Studio Header", in: application))
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, sourceHeader)
        componentMenu("Page", "Copy Header/Footer to Pages…", in: application)
        let sheet = application.sheets.firstMatch
        let copyPresented = application.buttons["page.chrome.copy.commit"].waitForExistence(timeout: 5)
        if !copyPresented { attachReadinessDiagnostics(for: application) }
        XCTAssertTrue(copyPresented)
        XCTAssertFalse(application.buttons["page.chrome.copy.commit"].isEnabled)
        for name in ["Contact", "Journal"] {
            let target = sheet.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "page.chrome.copy.target.", name)).firstMatch
            XCTAssertTrue(target.exists && target.isEnabled)
            XCTAssertEqual((target.value as? NSNumber)?.intValue, 0)
            target.click()
        }
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["page.chrome.copy.summary"], containing: "4 missing roles"))
        attachWindowScreenshot(application, named: "SF-CHROME normal native sheet explicit targets")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(application.buttons["page.chrome.copy.commit"]))
        pageRow(named: "Contact", in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        pageRow(named: "Legacy Surface", in: application).click()
        componentMenu("Page", "Copy Header/Footer to Pages…", in: application)
        for name in ["Contact", "Journal"] {
            application.sheets.firstMatch.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "page.chrome.copy.target.", name)).firstMatch.click()
        }
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["page.chrome.copy.status"], containing: "Copied 4 Header/Footer roles to 2 pages"))
        attachWindowScreenshot(application, named: "SF-CHROME adopted atomic copy summary")
        application.descendants(matching: .any)["page.chrome.copy.openTarget"].firstMatch.click()
        application.menuItems["Contact"].click()
        XCTAssertTrue(waitForComponentRenderedText("Studio Header", in: application))
        XCTAssertTrue(waitForComponentRenderedText("Studio Footer", in: application))
        let copiedHeader = canvasObject(named: "Header", in: application).identifier
        let copiedFooter = canvasObject(named: "Footer", in: application).identifier
        XCTAssertNotEqual(copiedHeader, sourceHeader)
        attachWindowScreenshot(application, named: "SF-CHROME target editable copies")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForComponentRenderedText("Studio Header", in: application))
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, copiedHeader)
        XCTAssertEqual(canvasObject(named: "Footer", in: application).identifier, copiedFooter)
        attachWindowScreenshot(application, named: "SF-CHROME one undo redo exact identities")
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        application.descendants(matching: .any)[copiedHeader.replacingOccurrences(of: "canvas.object.", with: "navigator.layer.")].firstMatch.click()
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: "Local Contact", in: application)
        XCTAssertTrue(waitForComponentRenderedText("Local Contact", in: application))
        XCTAssertTrue(revealComponentPointerTarget("inspector.navigation.includeAll", in: application).isEnabled)
        attachWindowScreenshot(application, named: "SF-CHROME target ordinary title and navigation controls")
        selectNavigatorTab("Pages", identifier: "pages", in: application)
        pageRow(named: "Legacy Surface", in: application).click()
        XCTAssertTrue(waitForComponentRenderedText("Studio Header", in: application))
        componentMenu("Page", "Copy Header/Footer to Pages…", in: application)
        for name in ["Contact", "Journal"] {
            application.sheets.firstMatch.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "page.chrome.copy.target.", name)).firstMatch.click()
        }
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["page.chrome.copy.summary"], containing: "0 missing roles"))
        XCTAssertFalse(application.buttons["page.chrome.copy.commit"].isEnabled)
        attachWindowScreenshot(application, named: "SF-CHROME existing roles explicitly kept")
        application.buttons["page.chrome.copy.cancel"].click()
        saveDocumentIfModified(in: application); terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("chrome-reopen-recovery", isDirectory: true))
        XCTAssertTrue(waitForWorkspaceReady(application))
        pageRow(named: "Contact", in: application).click()
        XCTAssertTrue(waitForComponentRenderedText("Local Contact", in: application))
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, copiedHeader)
        XCTAssertEqual(canvasObject(named: "Footer", in: application).identifier, copiedFooter)
        attachWindowScreenshot(application, named: "SF-CHROME saved reopened independent target")
    }

    func testCopyHeaderFooterSheetAtPracticalMinimumKeepsMissingRolesTruthful() throws {
        let application = launchScenario("workspace", extraArguments: [
            "-SiteForgeWindowSize", "minimum", "-SiteForgeUITestWindowAlignment", TestWindowAlignment.right.rawValue])
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        let header = canvasObject(named: "Header", in: application).identifier
        selectInspectorTab("Content", identifier: "content", in: application)
        let action = revealComponentPointerTarget("page.chrome.copy.context", in: application)
        XCTAssertTrue(action.isHittable && action.isEnabled); action.click()
        let source = application.descendants(matching: .any)["page.chrome.copy.source"].firstMatch
        let sourcePresented = source.waitForExistence(timeout: 5)
        if !sourcePresented { attachReadinessDiagnostics(for: application) }
        XCTAssertTrue(sourcePresented)
        XCTAssertFalse(application.checkBoxes["page.chrome.copy.role.footer"].isEnabled)
        XCTAssertTrue(application.checkBoxes["page.chrome.copy.role.header"].isEnabled)
        XCTAssertFalse(application.buttons["page.chrome.copy.commit"].isEnabled)
        assertElement(application.buttons["page.chrome.copy.cancel"], isContainedIn: application.windows.firstMatch)
        assertElement(application.buttons["page.chrome.copy.commit"], isContainedIn: application.windows.firstMatch)
        attachWindowScreenshot(application, named: "SF-CHROME practical minimum native copy sheet")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForNonexistence(application.buttons["page.chrome.copy.commit"]))
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, header)
    }

    func testHeaderFooterInlineGapResponsiveResetAndDraftCancellationJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        @MainActor func gap() -> XCUIElement {
            revealStructuralLayoutControl(application.textFields["inspector.navigation.linkGap"], in: application)
        }
        @MainActor func preset(_ name: String) {
            application.descendants(matching: .any)["canvas.viewport.preset"].firstMatch.click()
            application.menuItems[name].click()
        }
        replaceStructuralLayoutField(gap(), with: "32", in: application)
        XCTAssertTrue(waitForValue(gap(), containing: "32"))
        attachWindowScreenshot(application, named: "SF-SOURCE-02 Header inline gap Desktop")
        replaceStructuralLayoutField(gap(), with: "invalid", in: application)
        XCTAssertTrue(application.staticTexts["inspector.navigation.content.validation"].exists)
        revealStructuralLayoutControl(application.buttons["inspector.navigation.linkGap.cancel"], in: application).click()
        XCTAssertTrue(waitForValue(gap(), containing: "32"))
        preset("Tablet")
        replaceStructuralLayoutField(gap(), with: "8", in: application)
        XCTAssertTrue(waitForValue(gap(), containing: "8"))
        attachWindowScreenshot(application, named: "SF-SOURCE-02 Header Tablet gap override")
        revealStructuralLayoutControl(application.buttons["inspector.navigation.linkGap.reset"], in: application).click()
        XCTAssertTrue(waitForValue(gap(), containing: "32"))
        preset("Mobile")
        XCTAssertTrue(waitForValue(gap(), containing: "32"))
        XCTAssertTrue(application.descendants(matching: .any)["inspector.navigation.hamburger"].exists)
        attachWindowScreenshot(application, named: "SF-SOURCE-02 Header Mobile inherited controls")
        preset("Desktop")
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(gap(), with: "24", in: application)
        XCTAssertTrue(waitForValue(gap(), containing: "24"))
        attachWindowScreenshot(application, named: "SF-SOURCE-02 Footer independent gap")
        focusDocumentCommands(in: application)
        application.buttons["toolbar.undo"].click()
        XCTAssertTrue(waitForValue(gap(), containing: "16"))
    }

    func testConnectedHeaderFooterNavigationMenuHeightUndoAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("connected-page-structure.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 5", timeout: 5))
        let headerID = canvasObject(named: "Header", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("inspector.navigation.title", with: "Studio Site", in: application)
        application.textFields["inspector.navigation.title"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForComponentRenderedText("Studio Site", in: application))
        attachWindowScreenshot(application, named: "SF-UI-010 editable Header title and included pages")
        let showTitle = application.descendants(matching: .any)["inspector.navigation.title.visible"]
        showTitle.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 4", timeout: 5))
        showTitle.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 5", timeout: 5))
        XCTAssertTrue(waitForComponentRenderedText("Studio Site", in: application))
        replaceComponentTextField("inspector.flow.height", with: "240", in: application)
        application.textFields["inspector.flow.height"].typeKey(.return, modifierFlags: [])
        let customize = revealComponentPointerTarget("inspector.navigation.customize", in: application)
        _ = revealStructuralLayoutControl(customize, in: application)
        customize.click()
        XCTAssertTrue(waitForDisclosureExpanded(customize))
        replaceComponentTextField("inspector.navigation.content.gap", with: "8", in: application)
        application.textFields["inspector.navigation.content.gap"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.navigation.content.gap"], containing: "8"))
        revealComponentPointerTarget("inspector.navigation.content.direction", in: application).click()
        application.menuItems["Vertical"].click()
        XCTAssertTrue(waitForValue(application.popUpButtons["inspector.navigation.content.direction"], containing: "Vertical"))
        attachWindowScreenshot(application, named: "SF-UI-010 custom vertical Header contents")
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.popUpButtons["inspector.navigation.content.direction"], containing: "Horizontal"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.popUpButtons["inspector.navigation.content.direction"], containing: "Vertical"))
        revealComponentPointerTarget("inspector.navigation.content.reset", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.navigation.content.gap"], containing: "24"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.navigation.title"], containing: "Studio Site"))
        componentMenu("Insert", "Insert Section in Flow", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 6", timeout: 5))
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 11", timeout: 5))
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        XCTAssertTrue(application.textFields["inspector.flow.height"].waitForExistence(timeout: 5))
        replaceComponentTextField("inspector.flow.height", with: "240", in: application)
        application.textFields["inspector.flow.height"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.flow.status"], containing: "committed"))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.flow.height"], containing: "200"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.flow.height"], containing: "240"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-121 connected Header body Footer and dedicated settings")
        componentMenu("Page", "New Page…", in: application)
        XCTAssertTrue(application.textFields["page.editor.name"].waitForExistence(timeout: 3))
        replaceText(in: application.textFields["page.editor.name"], with: "About", application: application)
        application.buttons["page.editor.apply"].click()
        revealComponentPointerTarget("navigator.tab.pages", in: application).click()
        let home = pageRow(named: "Legacy Surface", in: application)
        XCTAssertTrue(home.waitForExistence(timeout: 5)); home.click()
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + headerID, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        application.popUpButtons["inspector.navigation.add.page"].click(); application.menuItems["About"].click()
        revealComponentPointerTarget("inspector.navigation.add", in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 12", timeout: 5))
        let includedAbout = application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "inspector.navigation.include.", "About")).firstMatch
        revealStructuralLayoutControl(includedAbout, in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 11", timeout: 5))
        revealStructuralLayoutControl(includedAbout, in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 12", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, "canvas.object." + headerID)
        let toggle = application.descendants(matching: .any)["inspector.navigation.hamburger"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual((toggle.value as? NSNumber)?.intValue, 1)
        toggle.click(); toggle.click()
        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        preset.click(); application.menuItems["Mobile"].click()
        XCTAssertTrue(waitForValue(preset, containing: "Mobile"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-121 Mobile full-width header and navigation policy")
        componentMenu("Preview", "Canvas Device Preview", in: application)
        let menu = application.descendants(matching: .any)["preview.navigation.menu." + headerID]
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); XCTAssertTrue(menu.isHittable)
        assertElement(application.descendants(matching: .any)["preview.local"],
                      isContainedIn: application.sheets.firstMatch)
        assertElement(menu, isContainedIn: application.descendants(matching: .any)["preview.canvas"])
        menu.click(); application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(menu.isHittable, "Native Escape closes the menu and returns a usable control")
        XCTAssertTrue(waitForKeyboardFocus(menu, in: application))
        menu.click(); application.menuItems["About"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["preview.page"], containing: "About"))
        attachWindowScreenshot(application, named: "SF-UI-010 native Preview followed About page")
        revealComponentPointerTarget("preview.done", in: application).click()
        attachWindowScreenshot(application, named: "SF-AUTHORING-121 functional native page-menu navigation")
        saveDocumentIfModified(in: application); terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("connected-page-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        revealComponentPointerTarget("navigator.tab.pages", in: application).click()
        pageRow(named: "Legacy Surface", in: application).click()
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + headerID, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        XCTAssertTrue(application.descendants(matching: .any)["inspector.navigation.hamburger"].exists)
        XCTAssertEqual((application.descendants(matching: .any)["inspector.navigation.hamburger"].value as? NSNumber)?.intValue, 1)
        let linkDisclosure = revealComponentPointerTarget("inspector.navigation.links", in: application)
        linkDisclosure.click()
        XCTAssertTrue(waitForDisclosureExpanded(linkDisclosure))
        XCTAssertTrue(application.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "inspector.navigation.label.")).firstMatch.exists)
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, "canvas.object." + headerID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-121 reopened connected structure and stable navigation")
    }

    func testComponentSlotFallbackNativeAuthoringCancelHistoryAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("component-slot-fallback.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let instanceID = canvasObject(named: "Frame", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Stack at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + instanceID, in: application).click()
        componentMenu("Component", "Create Component from Selection", in: application)
        componentMenu("Component", "Edit original component", in: application)
        let stack = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Stack")).firstMatch
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        revealComponentPointerTarget(stack.identifier, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("component.slot.definition.name", with: "Content", in: application)
        revealComponentPointerTarget("component.slot.definition.apply", in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["component.slot.status"], containing: "committed"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-118 exposed ordered fallback slot")
        replaceComponentTextField("component.slot.definition.name", with: "Discarded name", in: application)
        application.textFields["component.slot.definition.name"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["component.slot.definition.name"], containing: "Content"))
        revealComponentPointerTarget("components.exit", in: application).click()
        let edit = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component.slot.editFallback.")).firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        let slotID = edit.identifier.replacingOccurrences(of: "component.slot.editFallback.", with: "")
        XCTAssertTrue(waitForValue(application.staticTexts["component.slot.provenance." + slotID], containing: "Contents from original"))
        XCTAssertTrue(application.staticTexts["component.slot.supply.unavailable"].exists)
        XCTAssertFalse(application.buttons["component.slot.supply"].exists, "No fake supplied-content mutation route is exposed")
        revealComponentPointerTarget(edit.identifier, in: application).click()
        XCTAssertTrue(application.buttons["components.exit"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(application.textFields["component.slot.definition.name"], containing: "Content"))
        componentMenu("Insert", "Insert Text at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 4", timeout: 5))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        revealComponentPointerTarget(stack.identifier, in: application).click()
        XCTAssertTrue(waitForValue(application.textFields["component.slot.definition.name"], containing: "Content"))
        revealComponentPointerTarget("component.slot.definition.remove", in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields["component.slot.definition.name"], containing: "Content"))
        revealComponentPointerTarget("components.exit", in: application).click()
        XCTAssertTrue(application.staticTexts["component.slot.provenance." + slotID].waitForExistence(timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, "canvas.object." + instanceID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-118 inherited fallback and preserved instance")
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("slot-fallback-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        revealComponentPointerTarget("navigator.tab.layers", in: application).click()
        revealComponentPointerTarget("navigator.layer." + instanceID, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["component.slot.provenance." + slotID], containing: "Contents from original"))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-118 reopened fallback slot")
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
        componentMenu("Component", "Edit original component", in: application)
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
        revealComponentPointerTarget("component.visibility.resetAll", in: application).click()
        XCTAssertTrue(waitForComponentVisibilityState(toggle.identifier, visible: false, in: application))
        XCTAssertFalse(application.buttons["component.visibility.resetAll"].isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-113 reset all visibility overrides")
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

    // SF-0901-002/003/006, SF-0902-002/003/005/006, SF-0905-003/005.
    // UNRUN: real direct-source navigation, repeated definition text edits,
    // exact Return to Instance, independent override and explicit Reset.
    func testComponentDirectPropertySourceRetainsDefinitionDraftAndExactInstanceJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Frame at Center", in: application)
        let frame = canvasObject(named: "Frame", in: application)
        XCTAssertTrue(frame.waitForExistence(timeout: 5))
        let instanceID = frame.identifier
        componentMenu("Insert", "Insert Text at Center", in: application)
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        revealComponentPointerTarget("navigator.layer." + instanceID.replacingOccurrences(of: "canvas.object.", with: ""), in: application).click()
        selectNavigatorTab("Components", identifier: "components", in: application)
        revealComponentPointerTarget("components.create", in: application).click()
        replaceComponentTextField("components.create.name", with: "Source workflow card", in: application)
        application.buttons["components.create.apply"].click()
        componentMenu("Component", "Edit original component", in: application)
        XCTAssertTrue(application.buttons["components.exit"].waitForExistence(timeout: 3))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let text = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 3)); revealComponentPointerTarget(text.identifier, in: application).click()
        let sourceLayerID = text.identifier
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceComponentTextField("component.text.definition.name", with: "Title", in: application)
        replaceComponentTextField("component.text.definition.default", with: "First shared default", in: application)
        revealComponentPointerTarget("component.text.definition.apply", in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.text.content"], containing: "First shared default"))
        replaceStructuralLayoutField(application.textFields["component.text.definition.default"], with: "Second shared default", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.text.content"], containing: "Second shared default"))
        replaceComponentTextField("component.text.definition.default", with: "Uncommitted cancelled default", in: application)
        application.textFields["component.text.definition.default"].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["component.text.definition.default"], containing: "Second shared default"))
        attachWindowScreenshot(application, named: "SF-SOURCE-08 repeated definition edits and cancelled draft")
        revealComponentPointerTarget("components.exit", in: application).click()
        selectInspectorTab("Design", identifier: "design", in: application)
        let value = application.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component.text.value.")).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        let valueID = value.identifier
        let propertyID = String(valueID.dropFirst("component.text.value.".count))
        replaceStructuralLayoutField(application.textFields[valueID], with: "Independent instance title", in: application)
        XCTAssertTrue(waitForValue(application.textFields[valueID], containing: "Independent instance title"))
        XCTAssertFalse(application.buttons["component.text.apply." + propertyID].exists,
            "Stable fields must not show a redundant clean-draft Apply action")
        let before = application.descendants(matching: .any)[instanceID].firstMatch.frame
        revealComponentPointerTarget("component.property.source.text:" + propertyID, in: application).click()
        XCTAssertTrue(application.buttons["components.exit"].waitForExistence(timeout: 3))
        XCTAssertEqual(application.buttons["components.exit"].label, "Back to this copy")
        XCTAssertTrue(application.buttons[sourceLayerID].isSelected)
        XCTAssertTrue(application.textFields["component.text.definition.default"].waitForExistence(timeout: 3))
        replaceStructuralLayoutField(application.textFields["component.text.definition.default"], with: "Updated shared source", in: application)
        XCTAssertTrue(waitForValue(application.staticTexts["inspector.text.content"], containing: "Updated shared source"))
        attachWindowScreenshot(application, named: "SF-SOURCE-08 direct property source has shared scope and original layer")
        revealComponentPointerTarget("components.exit", in: application).click()
        selectInspectorTab("Design", identifier: "design", in: application)
        XCTAssertTrue(waitForValue(application.textFields[valueID], containing: "Independent instance title"))
        XCTAssertEqual(application.descendants(matching: .any)[instanceID].firstMatch.frame, before)
        attachWindowScreenshot(application, named: "SF-SOURCE-08 Return preserves canonical instance and authored override")
        revealComponentPointerTarget("component.text.reset." + propertyID, in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[valueID], containing: "Updated shared source"))
        componentMenu("Edit", "Undo", in: application)
        XCTAssertTrue(waitForValue(application.textFields[valueID], containing: "Independent instance title"))
        componentMenu("Edit", "Redo", in: application)
        XCTAssertTrue(waitForValue(application.textFields[valueID], containing: "Updated shared source"))
        attachWindowScreenshot(application, named: "SF-SOURCE-08 explicit Reset undo redo retains property identity")
    }

    func testPracticalComponentNamedCreationDesignDraftAndReturnJourney() throws {
        let project = fixtureRoot.appendingPathComponent("practical-component-reuse.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        selectNavigatorTab("Components", identifier: "components", in: application)
        XCTAssertFalse(application.buttons["components.create"].isEnabled)
        revealComponentPointerTarget("components.empty.insertFrame", in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let first = canvasObject(named: "Frame", in: application).identifier
        componentMenu("Insert", "Insert Text at Center", in: application)
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        revealComponentPointerTarget("navigator.layer." + first.replacingOccurrences(of: "canvas.object.", with: ""), in: application).click()
        selectNavigatorTab("Components", identifier: "components", in: application)
        revealComponentPointerTarget("components.create", in: application).click()
        replaceComponentTextField("components.create.name", with: "Cancelled Card", in: application)
        application.buttons["components.create.cancel"].click()
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, first)
        revealComponentPointerTarget("components.create", in: application).click()
        replaceComponentTextField("components.create.name", with: "Editorial Card", in: application)
        application.buttons["components.create.apply"].click()
        revealComponentPointerTarget("inspector.tab.design", in: application).click()
        XCTAssertTrue(application.buttons["inspector.tab.design"].isSelected)
        XCTAssertTrue(application.staticTexts["inspector.component.provenance"].waitForExistence(timeout: 5))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-002 named component and empty exposed properties")
        componentMenu("Component", "Edit original component", in: application)
        XCTAssertTrue(application.buttons["components.exit"].waitForExistence(timeout: 3))
        XCTAssertEqual(application.buttons["components.exit"].label, "Back to this copy")
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let text = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Text")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        revealComponentPointerTarget(text.identifier, in: application).click()
        revealComponentPointerTarget("inspector.tab.content", in: application).click()
        replaceComponentTextField("component.text.definition.name", with: "Title", in: application)
        replaceComponentTextField("component.text.definition.default", with: "Shared title", in: application)
        revealComponentPointerTarget("component.text.definition.apply", in: application).click()
        XCTAssertTrue(waitForValue(application.staticTexts["component.text.status"], containing: "committed"))
        revealComponentPointerTarget("components.exit", in: application).click()
        revealComponentPointerTarget("inspector.tab.design", in: application).click()
        let field = application.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "component.text.value.")).firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let fieldID = field.identifier
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Shared title"))
        XCTAssertTrue(application.buttons["navigator.layer." + first.replacingOccurrences(of: "canvas.object.", with: "")].isSelected)
        replaceComponentTextField(fieldID, with: "Independent title", in: application)
        application.textFields[fieldID].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForComponentRenderedText("Independent title", in: application))
        replaceComponentTextField(fieldID, with: "Blur committed", in: application)
        revealComponentPointerTarget("component.discovery.search", in: application).click()
        XCTAssertTrue(waitForComponentRenderedText("Blur committed", in: application))
        replaceComponentTextField(fieldID, with: "Discard this draft", in: application)
        application.textFields[fieldID].typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Blur committed"))
        XCTAssertFalse(waitForComponentRenderedText("Discard this draft", in: application, timeout: 0))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-002 Design override focus-loss and Escape")
        componentMenu("Component", "Edit original component", in: application)
        revealComponentPointerTarget("components.exit", in: application).click()
        revealComponentPointerTarget("inspector.tab.design", in: application).click()
        XCTAssertTrue(application.buttons["inspector.tab.design"].isSelected)
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Blur committed"))
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("practical-component-recovery"))
        XCTAssertTrue(waitForWorkspaceReady(application))
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        revealComponentPointerTarget("navigator.layer." + first.replacingOccurrences(of: "canvas.object.", with: ""), in: application).click()
        revealComponentPointerTarget("inspector.tab.design", in: application).click()
        XCTAssertTrue(waitForValue(application.textFields[fieldID], containing: "Blur committed"))
        XCTAssertTrue(waitForComponentRenderedText("Blur committed", in: application))
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER-002 reopened instance identity and value")
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let frameRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame")).firstMatch
        XCTAssertTrue(frameRow.waitForExistence(timeout: 3)); frameRow.click()
        let originalID = canvasObject(named: "Frame", in: application).identifier
        componentMenu("Component", "Create Component from Selection", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, originalID)
        selectNavigatorTab("Components", identifier: "components", in: application)
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
        componentMenu("Component", "Edit original component", in: application)
        XCTAssertTrue(application.buttons["components.exit"].waitForExistence(timeout: 3))
        revealComponentPointerTarget("components.exit", in: application)
        XCTAssertTrue(waitForHittable(application.buttons["components.exit"], in: application))
        editComponentHex("#994422FF", in: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 definition editing")
        revealComponentPointerTarget("components.exit", in: application).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        XCTAssertEqual(canvasObject(named: "Frame", in: application).identifier, secondID)
        attachWindowScreenshot(application, named: "SF-AUTHORING-022 propagated second instance")
        componentMenu("Component", "Make independent", in: application)
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
        // Activation during AppKit menu tracking dismisses the pending menu.
        // Establish foreground ownership before opening its real menu bar.
        if application.state != .runningForeground { application.activate() }
        if menu == "Edit", action == "Undo" || action == "Redo" {
            focusDocumentCommands(in: application)
        }
        application.menuBars.menuBarItems[menu].click()
        // Commands' native NSMenuItem bridge exposes title rather than the
        // SwiftUI identifier, and AppKit may normalize its ellipsis. Match the
        // two exact semantic spellings; never accept a different command.
        let settings = action == "Site & Page Settings…" ? application.menuBars.menuBarItems[menu].menus.firstMatch.menuItems.matching(NSPredicate(
            format: "title == %@ OR title == %@ OR label == %@ OR label == %@",
            action, "Site & Page Settings...", action, "Site & Page Settings...")) : nil
        let item = settings?.firstMatch ?? application.menuItems[action]
        let enabled = waitForEnabled(item)
        if !enabled, settings != nil {
            let receipt = XCTAttachment(string: application.debugDescription)
            receipt.name = "SF-USABILITY live native Settings command hierarchy"
            receipt.lifetime = .keepAlways; add(receipt)
        }
        XCTAssertTrue(enabled)
        if let settings { XCTAssertEqual(settings.count, 1) }
        item.click()
    }

    /// Document-history assertions must not ask the still-focused native field
    /// editor to undo its own draft. Focus a real non-editing viewport control
    /// without changing the document, selection, preset, or viewport transform.
    private func focusDocumentCommands(in application: XCUIApplication) {
        let preset = application.descendants(matching: .any)["canvas.viewport.preset"]
        XCTAssertTrue(waitForHittable(preset, in: application))
        preset.click()
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(preset, in: application))
    }

    private func editComponentHex(_ value: String, in application: XCUIApplication) {
        selectInspectorTab("Design", identifier: "design", in: application)
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
        selectNavigatorTab("Components", identifier: "components", in: application)
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
    private func selectNavigatorTab(_ title: String, identifier: String, in application: XCUIApplication) {
        selectShellTab(title, directIdentifier: "navigator.tab.\(identifier)",
                       overflowIdentifier: "navigator.tab.overflow", in: application)
    }

    private func selectInspectorTab(_ title: String, identifier: String, in application: XCUIApplication) {
        selectShellTab(title, directIdentifier: "inspector.tab.\(identifier)",
                       overflowIdentifier: "inspector.tab.overflow", in: application)
    }

    /// The shipping tab bar adaptively exposes either direct buttons or its
    /// native overflow menu. Both are equivalent pointer surfaces.
    private func selectShellTab(
        _ title: String,
        directIdentifier: String,
        overflowIdentifier: String,
        in application: XCUIApplication
    ) {
        let direct = application.buttons[directIdentifier]
        let paneID = directIdentifier.hasPrefix("navigator.") ? "shell.navigator" : "shell.inspector"
        let pane = application.descendants(matching: .any)[paneID]
        // Scroll-view children can exist and even report AXHittable outside
        // the viewport. Only click a fully visible tab; otherwise use the
        // same native overflow menu offered to pointer/keyboard users.
        if direct.exists && direct.isHittable && pane.exists && pane.frame.contains(direct.frame) {
            revealComponentPointerTarget(directIdentifier, in: application).click()
            return
        }
        revealComponentPointerTarget(overflowIdentifier, in: application).click()
        let item = application.menuItems[title]
        XCTAssertTrue(item.waitForExistence(timeout: 3), application.debugDescription)
        XCTAssertTrue(item.isEnabled)
        item.click()
    }

    @discardableResult
    private func revealComponentPointerTarget(_ identifier: String, in application: XCUIApplication) -> XCUIElement {
        if application.state != .runningForeground { application.activate() }
        if !application.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists {
            let disclosureID = identifier.hasPrefix("inspector.workflow.") ? "inspector.workflow.disclosure" :
                identifier.hasPrefix("component.") ? "component.definition.properties" : ""
            if !disclosureID.isEmpty {
                let disclosure = application.descendants(matching: .any)[disclosureID]
                if disclosure.exists {
                    _ = revealStructuralLayoutControl(disclosure, in: application)
                    disclosure.click()
                    XCTAssertTrue(waitForDisclosureExpanded(disclosure), "The real disclosure must expand before its controls are used")
                }
            }
        }
        let query = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
        XCTAssertTrue(query.waitForExistence(timeout: 3), application.debugDescription)
        let inspector = application.scrollViews["inspector.selection.scroll"]
        // SwiftUI includes an anchored popover in its source view's AX subtree.
        // Its controls belong to the visible popover, not the scroll view behind it.
        let fontChooser = application.descendants(matching: .any)["typography.font.chooser"]
        if fontChooser.exists, fontChooser.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists {
            assertElement(query, isContainedIn: fontChooser)
        } else if inspector.exists, inspector.descendants(matching: .any).matching(identifier: identifier).firstMatch.exists {
            _ = revealStructuralLayoutControl(query, in: application)
        }
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
            XCTFail("The app must be active and the live pointer control enabled: state=\(application.state.rawValue); target=\(identifier); enabled=\(query.isEnabled); hittable=\(query.isHittable); frame=\(query.frame)\n\(application.debugDescription)")
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
        let pointerReady = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let live = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
            return live.isEnabled && live.isHittable && live.frame.minX >= visible.minX - 1
                && live.frame.maxX <= visible.maxX + 1
        }, object: application)], timeout: 3) == .completed
        if !pointerReady {
            let live = application.descendants(matching: .any).matching(identifier: identifier).firstMatch
            let details = XCTAttachment(string: "target=\(identifier); appState=\(application.state.rawValue); exists=\(live.exists); enabled=\(live.exists && live.isEnabled); hittable=\(live.exists && live.isHittable); frame=\(live.exists ? sanitizedFrame(live.frame) : "unavailable"); visible=\(sanitizedFrame(visible))\n\(redactedAccessibilityHierarchy(for: application))")
            details.name = "live-pointer-boundary-diagnostics"; details.lifetime = .keepAlways; add(details)
            attachWindowScreenshot(application, named: "live-pointer-boundary-failure")
        }
        XCTAssertTrue(pointerReady, "The live component control must be enabled, hittable and inside the display")
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
        selectInspectorTab("Interactions", identifier: "interactions", in: application)
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
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.button"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        let buttonID = canvasObject(named: "Button", in: application).identifier
        XCTAssertTrue(canvasObject(named: "Button", in: application).isSelected)
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.content.control.label"], with: "Read guide", in: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 button label")
        let controlStatus = application.descendants(matching: .any)["inspector.control.status"].firstMatch
        XCTAssertTrue(waitForValue(controlStatus, containing: "label committed"), "Status: \(controlStatus.label) / \(String(describing: controlStatus.value)); field: \(String(describing: application.textFields["inspector.content.control.label"].value))")
        selectInspectorTab("Interactions", identifier: "interactions", in: application)
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
        selectInspectorTab("Layout", identifier: "layout", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.layout.x"], with: "200", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.layout.y"], with: "200", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.content.control.label"], with: "More details", in: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-020 link selected")
        saveDocumentIfModified(in: application)
        terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("control-reopen-recovery"))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 2", timeout: 5))
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let row = application.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Button")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3)); row.click()
        XCTAssertEqual(canvasObject(named: "Button", in: application).identifier, buttonID)
        selectInspectorTab("Content", identifier: "content", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.content.control.label"], containing: "Read guide"))
        selectInspectorTab("Interactions", identifier: "interactions", in: application)
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
            selectInspectorTab("Layout", identifier: "layout", in: application)
            replaceStructuralLayoutField(application.textFields["inspector.layout.x"], with: String(200 + index * 300), in: application)
            replaceStructuralLayoutField(application.textFields["inspector.layout.y"], with: "200", in: application)
        }
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        selectInspectorTab("Content", identifier: "content", in: application)
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
        XCTAssertTrue(application.buttons["inspector.text.edit"].waitForExistence(timeout: 3))
        XCTAssertTrue(application.descendants(matching: .any)["inspector.text.content"].exists)
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
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.content.control.label"], with: "Open page", in: application)
        selectInspectorTab("Interactions", identifier: "interactions", in: application)
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
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.section"].click()
        assertSelection("Section", count: 1)
        application.buttons["navigator.elements.stack"].click()
        assertSelection("Stack", count: 2)
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let sectionLayer = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section"))
            .firstMatch
        XCTAssertTrue(sectionLayer.waitForExistence(timeout: 3))
        sectionLayer.click()
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.grid"].click()
        assertSelection("Grid", count: 3)
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Frame at Center"].click()
        assertSelection("Frame", count: 4)
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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

        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let sectionLayer = application.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section"))
            .firstMatch
        XCTAssertTrue(sectionLayer.waitForExistence(timeout: 3))
        sectionLayer.click()
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
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

        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.section"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        insertStructuralFrame(in: application, expectedCount: 2)
        selectStructuralLayer("Section", in: application)
        selectInspectorTab("Layout", identifier: "layout", in: application)
        let padding = application.textFields["inspector.layout.container.padding"]
        XCTAssertTrue(padding.waitForExistence(timeout: 3))
        XCTAssertTrue((padding.value as? String)?.contains("48") == true)
        let sectionChildBefore = canvasObject(named: "Frame", in: application).frame
        replaceStructuralLayoutField(padding, with: "72", in: application)
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.announcement",
            containing: "Inner spacing committed",
            timeout: 3
        ))
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
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.stack"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 3", timeout: 5))
        insertStructuralFrame(in: application, expectedCount: 4)
        selectStructuralLayer("Stack", in: application)
        insertStructuralFrame(in: application, expectedCount: 5)
        selectStructuralLayer("Stack", in: application)
        selectInspectorTab("Layout", identifier: "layout", in: application)
        // NSSegmentedControl's AX group includes an outdented bezel. Prove
        // both actual user targets fit instead of scrolling a noninteractive
        // wrapper that cannot be brought inward by vertical scrolling.
        for label in ["Vertical", "Horizontal"] {
            XCTAssertNotNil(revealStructuralLayoutRadioButton(
                label, groupIdentifier: "inspector.layout.container.axis", in: application))
        }
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
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.grid"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 6", timeout: 5))
        insertStructuralFrame(in: application, expectedCount: 7)
        selectStructuralLayer("Grid", in: application)
        insertStructuralFrame(in: application, expectedCount: 8)
        selectStructuralLayer("Grid", in: application)
        insertStructuralFrame(in: application, expectedCount: 9)
        selectStructuralLayer("Grid", in: application)
        selectInspectorTab("Layout", identifier: "layout", in: application)
        let columns = application.textFields["inspector.layout.container.columns"]
        XCTAssertTrue(columns.waitForExistence(timeout: 3))
        revealStructuralLayoutControl(columns, in: application)
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 grid two columns sparse row")
        replaceStructuralLayoutField(columns, with: "3", in: application)
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.announcement",
            containing: "Columns committed",
            timeout: 3
        ))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 9", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 grid three columns")

        focusDocumentCommands(in: application)
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.columns",
            containing: "2",
            timeout: 3
        ))
        XCTAssertTrue(application.buttons["toolbar.redo"].isEnabled)
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.columns",
            containing: "3",
            timeout: 3
        ))
        let reset = revealStructuralLayoutControl(
            application.buttons["inspector.layout.container.columns.reset"],
            in: application
        )
        XCTAssertTrue(reset.isEnabled); reset.click()
        XCTAssertTrue(waitForLiveValue(
            in: application,
            identifier: "inspector.layout.container.columns",
            containing: "2",
            timeout: 3
        ))
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
        selectInspectorTab("Layout", identifier: "layout", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.padding"], containing: "72"))
        selectStructuralLayer("Stack", in: application)
        selectInspectorTab("Layout", identifier: "layout", in: application)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["inspector.layout.container.axis"], containing: "horizontal"))
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.gap"], containing: "36"))
        selectStructuralLayer("Grid", in: application)
        selectInspectorTab("Layout", identifier: "layout", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.container.columns"], containing: "2"))
        attachWindowScreenshot(application, named: "SF-AUTHORING-017 save reopen")
    }

    // SF-0502-006, SF-0503-006, SF-0506-006
    @MainActor
    func testStructuralLayoutControlsRemainReachableAtPracticalMinimum() throws {
        let application = launchWorkspace(windowAlignment: .right)
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.stack"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        selectInspectorTab("Layout", identifier: "layout", in: application)

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
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        application.typeKey("p", modifierFlags: [.command, .option])
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
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        let title = application.textFields["inspector.navigation.title"]
        replaceText(in: title, with: "Pointer preview acceptance", application: application)
        title.typeKey(.return, modifierFlags: [])
        let preview = application.buttons["toolbar.preview"]

        XCTAssertTrue(waitForHittable(preview, in: application))
        preview.click()
        let link = application.staticTexts["preview.website.url"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        let url = try XCTUnwrap(URL(string: (link.value as? String) ?? link.label))
        XCTAssertEqual(url.host, "127.0.0.1")
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            safari.state == .runningForeground
        }, object: nil)], timeout: 10), .completed)
        XCTAssertTrue(safari.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(safari.webViews.staticTexts["Pointer preview acceptance"].firstMatch.waitForExistence(timeout: 10))
        // The unique authored title proves this is our newly opened tab;
        // closing it cannot discard another Safari tab or its editing state.
        safari.typeKey("w", modifierFlags: .command)
        application.activate()
        application.buttons["Stop"].click()
        application.buttons["preview.website.done"].click()
    }

    // SF-1201-001/002/003/004/006, SF-1202-001/003/006 — Preview owns a
    // deliberate immutable authored snapshot and contains no editor canvas.
    @MainActor
    // SF-LOCAL-BUILDER-011 — Safari, panels and screenshots below are
    // future acceptance source, never permission to execute under the hold.
    func testConnectedFluidPreflightSafariExportCancelAndReopenJourney() throws {
        let project = fixtureRoot.appendingPathComponent("connected-fluid-native.siteforge")
        var application = launchIntegrationOpen(project, base64Fixture: legacyFixtureURL(named: "schema-v4-legacy-surface"))
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: "Connected Fluid Browser Receipt", in: application)
        componentMenu("Insert", "Insert Section in Flow", in: application)
        let sectionID = canvasObject(named: "Section", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Stack at Center", in: application)
        let stackID = canvasObject(named: "Stack", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Text at Center", in: application)
        componentMenu("Insert", "Insert Text at Center", in: application)
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        @MainActor func selectLayer(_ id: String) {
            selectNavigatorTab("Layers", identifier: "layers", in: application)
            let row = application.descendants(matching: .any)["navigator.layer." + id].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5)); row.click()
            selectInspectorTab("Layout", identifier: "layout", in: application)
        }
        @MainActor func authorFluid(_ field: String, values: [String]) {
            revealComponentPointerTarget("inspector.layout.fluid.target", in: application).click()
            let title: String = switch field {
            case "padding": "Inner spacing"
            case "gap": "Space between items"
            default: field.capitalized
            }
            application.menuItems[title].click()
            revealComponentPointerTarget("inspector.layout.fluid.enable", in: application).click()
            for (identifier, text) in zip(["minimum", "preferred", "maximum"], values) {
                let control = revealStructuralLayoutControl(application.textFields["inspector.layout.fluid." + identifier], in: application)
                replaceText(in: control, with: text, application: application)
            }
            revealComponentPointerTarget("inspector.layout.fluid.apply", in: application).click()
            XCTAssertTrue(waitForValue(application.staticTexts["inspector.layout.fluid.announcement"], containing: "applied"))
        }
        selectLayer(sectionID); authorFluid("padding", values: ["8", "16", "24"])
        selectLayer(stackID); authorFluid("gap", values: ["8", "16", "24"])
        attachWindowScreenshot(application, named: "SF-FLUID-OUTPUT Desktop connected authoring")
        replaceText(in: application.textFields["canvas.viewport.width"], with: "430", application: application)
        application.textFields["canvas.viewport.width"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.width", containing: "430"))
        attachWindowScreenshot(application, named: "SF-FLUID-OUTPUT custom 430 native intent")
        componentMenu("Build", "Build Diagnostics…", in: application)
        XCTAssertTrue(application.buttons["build.preflight"].waitForExistence(timeout: 5))
        application.buttons["build.preflight"].click()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let live = application.buttons["build.write"]
            return live.exists && live.isEnabled
        }, object: nil)], timeout: 10), .completed)
        attachWindowScreenshot(application, named: "SF-FLUID-OUTPUT current revision preflight exportable")
        application.buttons["Done"].firstMatch.click()
        componentMenu("Preview", "Preview Website in Safari", in: application)
        // Selectable native text may expose AXTextArea rather than AXStaticText.
        // Require the same real address and URL, not one incidental AX role.
        let address = application.descendants(matching: .any)["preview.website.url"].firstMatch
        let previewReady = address.waitForExistence(timeout: 10)
        if !previewReady {
            attachReadinessDiagnostics(for: application)
            let screen = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screen.name = "SF-FLUID-OUTPUT preview startup failure screen"
            screen.lifetime = .keepAlways; add(screen)
        }
        XCTAssertTrue(previewReady)
        let previewURL = try XCTUnwrap(URL(string: (address.value as? String) ?? address.label))
        XCTAssertEqual(previewURL.scheme, "http"); XCTAssertEqual(previewURL.host, "127.0.0.1")
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        XCTAssertTrue(safari.webViews.staticTexts["Connected Fluid Browser Receipt"].firstMatch.waitForExistence(timeout: 10))
        let browser = XCTAttachment(screenshot: safari.windows.firstMatch.screenshot())
        browser.name = "SF-FLUID-OUTPUT Safari view \(Int(safari.webViews.firstMatch.frame.width)) points — CSS viewport and zoom review required"
        browser.lifetime = .keepAlways; add(browser)
        safari.typeKey("w", modifierFlags: .command); application.activate()
        application.buttons["preview.website.export"].click()
        let cancel = application.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); XCTAssertTrue(cancel.isHittable); cancel.click()
        XCTAssertTrue(application.staticTexts["preview.website.url"].exists)
        XCTAssertTrue(application.buttons["preview.website.export"].isEnabled)
        attachWindowScreenshot(application, named: "SF-FLUID-OUTPUT native export chooser cancelled")
        application.buttons["Stop"].click(); application.buttons["preview.website.done"].click()
        saveDocumentIfModified(in: application); terminateAndWait(application)
        application = launchExistingIntegrationProject(project, recoveryDirectory: fixtureRoot.appendingPathComponent("connected-fluid-reopen", isDirectory: true))
        XCTAssertTrue(waitForWorkspaceReady(application)); selectLayer(stackID)
        revealComponentPointerTarget("inspector.layout.container.gap.fluid", in: application).click()
        revealComponentPointerTarget("inspector.layout.fluid.target", in: application).click()
        application.menuItems["Space between items"].click()
        XCTAssertTrue(revealComponentPointerTarget("inspector.layout.fluid.edit", in: application).isEnabled)
        attachWindowScreenshot(application, named: "SF-FLUID-OUTPUT reopened retained fluid intent")
    }

    // SF-0806-006, SF-1203-003/006, SF-1211-004. Diagnostic companion only:
    // ordinary pointer behavior is observed independently of computed readiness.
    // The strict narrow-chrome acceptance journey below remains unchanged.
    @MainActor
    func testNativePreviewHeaderPublicPointerBoundaryProbe() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Page", "New Page…", in: application)
        XCTAssertTrue(application.textFields["page.editor.name"].waitForExistence(timeout: 3))
        replaceText(in: application.textFields["page.editor.name"], with: "About", application: application)
        application.buttons["page.editor.apply"].click()
        selectNavigatorTab("Pages", identifier: "pages", in: application)
        pageRow(named: "Home", in: application).click()
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        let headerID = canvasObject(named: "Header", in: application).identifier
            .replacingOccurrences(of: "canvas.object.", with: "")
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        let footerID = canvasObject(named: "Footer", in: application).identifier
            .replacingOccurrences(of: "canvas.object.", with: "")
        replaceText(in: application.textFields["canvas.viewport.width"], with: "320", application: application)
        application.textFields["canvas.viewport.width"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.width", containing: "320"))
        application.buttons["canvas.zoom.reset"].click()
        componentMenu("Preview", "Canvas Device Preview", in: application)

        @MainActor func menu(_ owner: String) -> XCUIElement {
            application.sheets.firstMatch.descendants(matching: .menuButton)["preview.navigation.menu." + owner].firstMatch
        }
        @MainActor func receipt(_ phase: String) {
            let live = menu(headerID)
            let done = application.buttons["preview.done"]
            var lines = ["phase=\(phase)",
                "header count=\(application.sheets.firstMatch.descendants(matching: .menuButton).matching(identifier: live.identifier).count); frame=\(live.frame); enabled=\(live.isEnabled); hittable=\(live.isHittable); focus=\(hasKeyboardFocus(live))",
                "done frame=\(done.frame); enabled=\(done.isEnabled); hittable=\(done.isHittable)"]
            // XCTest's existing native observation is sufficient here. Do not
            // repeat direct system-wide AX access previously denied by macOS.
            lines.append(application.debugDescription)
            lines.append(launchLifecycleDiagnostics(for: application))
            let attachment = XCTAttachment(string: lines.joined(separator: "\n"))
            attachment.name = "SF-NARROW public pointer boundary \(phase)"
            attachment.lifetime = .keepAlways; add(attachment)
            attachWindowScreenshot(application, named: "SF-NARROW pointer probe \(phase)")
        }
        XCTAssertTrue(menu(headerID).waitForExistence(timeout: 5))
        receipt("before ordinary Header click")
        // Deliberately no isHittable guard or coordinate fallback. This is the
        // real current element's ordinary pointer operation, not acceptance
        // of the separately failing strict readiness requirement.
        menu(headerID).click()
        XCTAssertTrue(application.menuItems["About"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-NARROW pointer probe Header opened")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(menu(headerID), in: application))
        receipt("Header Escape focus")
        XCTAssertTrue(menu(footerID).exists)
        menu(footerID).click()
        XCTAssertTrue(application.menuItems["About"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-NARROW pointer probe Footer opened")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(menu(footerID), in: application))
        menu(footerID).click(); application.menuItems["About"].click()
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["preview.page"], containing: "About"))
        attachWindowScreenshot(application, named: "SF-NARROW pointer probe actual Footer About destination")
        application.buttons["preview.done"].click()
    }

    // SF-0806-006, SF-1203-003/006, SF-1211-004. Independent diagnostic
    // observations: a Footer pointer failure is retained, not allowed to
    // conceal the separate keyboard and generated-browser-output outcomes.
    @MainActor
    func testNarrowChromeFooterAndMeasuredSafariBoundaryCompanion() throws {
        try runNarrowChromeBoundaryCompanion(includeNativeFooter: true)
    }

    @MainActor
    func testMeasuredSafariNarrowChromeBoundaryCompanion() throws {
        try runNarrowChromeBoundaryCompanion(includeNativeFooter: false)
    }

    @MainActor
    func testGeneratedWebsiteMenuEscapeStateAndPaintJourney() throws {
        try runNarrowChromeBoundaryCompanion(includeNativeFooter: false, widths: [320, 430, 768], observeClosure: true)
    }

    @MainActor
    func testGeneratedWebsiteMenuEscapePresentationContextComparison() throws {
        try runNarrowChromeBoundaryCompanion(includeNativeFooter: false, widths: [560], observeClosure: true, comparePresentation: true)
    }

    @MainActor
    private func runNarrowChromeBoundaryCompanion(includeNativeFooter: Bool, widths: [Int] = [320, 430, 768], observeClosure: Bool = false, comparePresentation: Bool = false) throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Page", "New Page…", in: application)
        XCTAssertTrue(application.textFields["page.editor.name"].waitForExistence(timeout: 3))
        replaceText(in: application.textFields["page.editor.name"], with: "About", application: application)
        application.buttons["page.editor.apply"].click()
        selectNavigatorTab("Pages", identifier: "pages", in: application)
        pageRow(named: "Home", in: application).click()
        // Keep a visible document identity even when the long title ellipsizes.
        // This distinguishes this fixture from retained tabs of older runs.
        let receiptIdentity = observeClosure ? String(UUID().uuidString.prefix(6)) : "Narrow"
        let headerTitle = "\(receiptIdentity) Header Pointer Receipt"
        let footerTitle = "\(receiptIdentity) Footer Pointer Receipt"
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: headerTitle, in: application)
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: footerTitle, in: application)
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let footerRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Footer")).firstMatch
        XCTAssertTrue(footerRow.waitForExistence(timeout: 3))
        let footerID = footerRow.identifier.replacingOccurrences(of: "navigator.layer.", with: "")
        replaceText(in: application.textFields["canvas.viewport.width"], with: "320", application: application)
        application.textFields["canvas.viewport.width"].typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.width", containing: "320"))
        application.buttons["canvas.zoom.reset"].click()
        if includeNativeFooter {
        componentMenu("Preview", "Canvas Device Preview", in: application)
        @MainActor func footerMenu() -> XCUIElement {
            application.sheets.firstMatch.descendants(matching: .menuButton)["preview.navigation.menu." + footerID].firstMatch
        }
        XCTAssertTrue(footerMenu().waitForExistence(timeout: 5))
        let before = XCTAttachment(string: application.debugDescription)
        before.name = "SF-NARROW independent Footer before ordinary click"; before.lifetime = .keepAlways; add(before)
        attachWindowScreenshot(application, named: "SF-NARROW independent Footer before pointer")
        // Only this companion continues to collect independent failures. No
        // expected-failure waiver and no fallback pointer coordinates/actions.
        continueAfterFailure = true
        footerMenu().click()
        let pointerOpened = application.menuItems["About"].waitForExistence(timeout: 3)
        XCTAssertTrue(pointerOpened, "The ordinary Footer click must open its native menu")
        if pointerOpened {
            attachWindowScreenshot(application, named: "SF-NARROW independent Footer pointer opened")
            application.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(waitForKeyboardFocus(footerMenu(), in: application))
        }
        for _ in 0..<16 {
            if hasKeyboardFocus(footerMenu()) { break }
            application.typeKey(.tab, modifierFlags: [])
        }
        XCTAssertTrue(waitForKeyboardFocus(footerMenu(), in: application))
        application.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(application.menuItems["About"].waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-NARROW independent Footer keyboard opened")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(footerMenu(), in: application))
        application.typeKey(.downArrow, modifierFlags: [])
        let reopened = application.menuItems["About"].waitForExistence(timeout: 3)
        XCTAssertTrue(reopened)
        if reopened {
            application.menuItems["About"].click()
            XCTAssertTrue(waitForValue(application.descendants(matching: .any)["preview.page"], containing: "About"))
            attachWindowScreenshot(application, named: "SF-NARROW independent Footer actual About destination")
        }
        application.buttons["preview.done"].click()
        continueAfterFailure = false
        }

        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        let observationKey = "__sfEscapeReceipt" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var presentation = "responsive"
        var pixelFailures: [String] = []
        var artifactIdentity: String?
        var runtimeHash: String?
        @MainActor func measured(_ role: String, phase: String = "geometry", arm: Bool = false) throws -> [String: Any] {
            let marker = "SF_CHROME_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + " "
            let prompt = safari.textViews["Console prompt"].firstMatch
            if !comparePresentation || !prompt.exists { safari.typeKey("c", modifierFlags: [.command, .option]) }
            XCTAssertTrue(prompt.waitForExistence(timeout: 5))
            prompt.coordinate(withNormalizedOffset: .init(dx: 0.03, dy: 0.5)).click()
            // Existing authorized, read-only DOM inspection. This neither
            // modifies the website nor substitutes for a real menu click.
            let observation = observeClosure ? """
            function state(){return {time:performance.now(),wall:Date.now(),focus:document.activeElement&&{tag:document.activeElement.tagName,label:document.activeElement.getAttribute('aria-label')},hasFocus:document.hasFocus(),menus:Array.from(document.querySelectorAll('details[data-siteforge-navigation]')).map(function(d){var s=d.querySelector('summary'),p=d.querySelector('nav'),b=p.getBoundingClientRect(),c=getComputedStyle(p);return {owner:d.getAttribute('data-siteforge-navigation'),open:d.open,expanded:s.getAttribute('aria-expanded'),summaryFocused:s===document.activeElement,panel:{x:b.x,y:b.y,width:b.width,height:b.height,rects:p.getClientRects().length,display:c.display,visibility:c.visibility,paintEligible:p.checkVisibility({contentVisibilityAuto:true})}}})};}
            var key='\(observationKey)',trace=window[key];
            if(\(arm) && !trace){trace={events:[],toggles:[],afterFrames:null,controller:new AbortController()};window[key]=trace;window.addEventListener('keydown',function(e){if(e.key!=='Escape')return;trace.events.push({key:e.key,trusted:e.isTrusted,target:e.target.tagName,before:state()});requestAnimationFrame(function(){requestAnimationFrame(function(){trace.afterFrames={defaultPrevented:e.defaultPrevented,state:state()};});});},{capture:true,passive:true,signal:trace.controller.signal});document.addEventListener('toggle',function(e){if(!(e.target instanceof HTMLDetailsElement))return;requestAnimationFrame(function(){requestAnimationFrame(function(){trace.toggles.push(state());});});},{capture:true,passive:true,signal:trace.controller.signal});}
            await new Promise(function(resolve){requestAnimationFrame(function(){requestAnimationFrame(resolve);});});
            result.phase='\(phase)';result.dom=state();result.eventTrace=trace?{events:trace.events,toggles:trace.toggles,afterFrames:trace.afterFrames}:null;
            result.context={url:document.URL,name:window.name,isTop:window===top,frameCount:frames.length,frameElement:frameElement&&{tag:frameElement.tagName,id:frameElement.id},timeOrigin:performance.timeOrigin,visibility:document.visibilityState,ready:document.readyState,scrollX:scrollX,scrollY:scrollY,outerWidth:outerWidth,outerHeight:outerHeight,devicePixelRatio:devicePixelRatio,viewport:{width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale,offsetLeft:visualViewport.offsetLeft,offsetTop:visualViewport.offsetTop}};
            result.navigation=Array.from(document.querySelectorAll('nav')).map(function(n){var b=n.getBoundingClientRect(),c=getComputedStyle(n);return {id:n.id,classes:n.className,owner:n.closest('[data-siteforge-node]')?.getAttribute('data-siteforge-node'),x:b.x,y:b.y,width:b.width,height:b.height,display:c.display,visible:n.checkVisibility({contentVisibilityAuto:true}),links:Array.from(n.querySelectorAll('a')).map(function(a){return {text:a.textContent,visible:a.checkVisibility({contentVisibilityAuto:true})};})};});
            if(trace&&trace.events.length){result.formerPanelHits=trace.events.at(-1).before.menus.filter(function(m){return m.open;}).map(function(m){var p=m.panel;return {owner:m.owner,x:p.x+p.width/2,y:p.y+p.height/2,elements:document.elementsFromPoint(p.x+p.width/2,p.y+p.height/2).map(function(e){return {tag:e.tagName,id:e.id,classes:e.className};})};});}
            var script=document.querySelector('script[src$="siteforge-navigation.js"]');result.script={element:!!script,url:script&&new URL(script.src).pathname,resources:performance.getEntriesByType('resource').filter(function(e){return e.name.endsWith('/siteforge-navigation.js');}).map(function(e){return {path:new URL(e.name).pathname,duration:e.duration,transfer:e.transferSize};})};
            if(script){var response=await fetch(script.src,{cache:'no-store'}),bytes=await response.arrayBuffer();result.script.status=response.status;result.script.mime=response.headers.get('content-type');result.script.bytes=bytes.byteLength;result.script.text=new TextDecoder().decode(bytes);result.script.sha256=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))).map(function(v){return v.toString(16).padStart(2,'0');}).join('');}
            if('\(phase)'==='after closed screenshot'&&trace){trace.controller.abort();delete window[key];}
            """ : ""
            // The optional passive observer records genuine key dispatch and
            // two rendered frames. It never closes, clicks or focuses content.
            // Web Inspector truncates long logged strings in its AX value.
            // Transfer the complete read-only result in bounded messages;
            // retaining every byte keeps the strict DOM/pixel proof intact.
            let script = "(async function(){var h=document.querySelector('\(role)[data-siteforge-node]'),q=h&&h.querySelector('[data-siteforge-text]'),t=q&&q.parentElement,n=h&&h.querySelector('.sf-page-navigation'),s=n&&n.querySelector('summary');function r(e){if(!e)return null;var b=e.getBoundingClientRect();return {x:b.x,y:b.y,right:b.right,width:b.width,height:b.height}}var result={width:innerWidth,scale:visualViewport.scale,host:location.host,path:location.pathname,title:t&&t.textContent,titleRect:r(t),navRect:r(n),menuRect:r(s),links:h?Array.from(h.querySelectorAll('a[href]')).map(function(a){return {label:a.textContent,path:new URL(a.getAttribute('href'),location.href).pathname}}):[]};\(observation)var payload=btoa(Array.from(new TextEncoder().encode(JSON.stringify(result)),function(b){return String.fromCharCode(b);}).join('')),parts=Math.ceil(payload.length/384);console.log('\(marker)COUNT:'+parts+':'+payload.length);for(var i=0;i<parts;i++)console.log('\(marker)PART'+i+':'+payload.slice(i*384,(i+1)*384));}())"
            let board = NSPasteboard.general
            let saved = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
            do {
                defer {
                    board.clearContents()
                    board.writeObjects(saved.map { values in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item })
                }
                board.clearContents(); board.setString(script, forType: .string)
                prompt.typeKey("v", modifierFlags: .command); prompt.typeKey(.return, modifierFlags: [])
            }
            @MainActor func message(_ suffix: String) throws -> String {
                let prefix = marker + suffix
                let live = safari.descendants(matching: .any).matching(NSPredicate(
                    format: "label BEGINSWITH %@ OR value BEGINSWITH %@", prefix, prefix)).firstMatch
                XCTAssertTrue(live.waitForExistence(timeout: 5), "Missing complete Inspector diagnostic message")
                let text = (live.value as? String) ?? live.label
                let range = try XCTUnwrap(text.range(of: prefix))
                return String(text[range.upperBound...])
            }
            let dimensions = try message("COUNT:").split(separator: ":", omittingEmptySubsequences: false)
            XCTAssertEqual(dimensions.count, 2)
            let count = try XCTUnwrap(dimensions.first.flatMap { Int($0) })
            let encodedLength = try XCTUnwrap(dimensions.last.flatMap { Int($0) })
            guard (1...131_072).contains(encodedLength), count == (encodedLength + 383) / 384 else {
                XCTFail("Bound the complete observational receipt without truncation")
                throw NSError(domain: "SiteForgeInspectorReceipt", code: 1)
            }
            let lastPrefix = marker + "PART\(count - 1):"
            let last = safari.descendants(matching: .any).matching(NSPredicate(
                format: "label BEGINSWITH %@ OR value BEGINSWITH %@", lastPrefix, lastPrefix)).firstMatch
            XCTAssertTrue(last.waitForExistence(timeout: 5), "Inspector must expose the complete receipt")
            // Read one immutable public snapshot after the final chunk exists.
            // Reading each chunk's exists/value separately repeatedly traversed
            // the growing Inspector tree and made a diagnostic take an hour.
            // Leave room for the marker inside snapshot attribute limits.
            // Keep every byte and reject absent/conflicting chunks, not breadth.
            var pending: [any XCUIElementSnapshot] = [try safari.snapshot()]
            var chunks: [Int: String] = [:]
            var visited = 0
            let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/="
            while let node = pending.popLast() {
                visited += 1
                guard visited <= 50_000 else { throw NSError(domain: "SiteForgeInspectorReceipt", code: 2) }
                pending.append(contentsOf: node.children)
                for candidate in [node.value as? String, node.label].compactMap({ $0 }) {
                    guard candidate.hasPrefix(marker + "PART") else { continue }
                    let body = candidate.dropFirst((marker + "PART").count)
                    let fields = body.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    guard fields.count == 2, let index = Int(fields[0]), (0..<count).contains(index),
                          !fields[1].isEmpty, fields[1].count <= 384,
                          fields[1].allSatisfy({ alphabet.contains($0) }) else { continue }
                    let chunk = String(fields[1])
                    if let previous = chunks[index] { XCTAssertEqual(previous, chunk, "Conflicting diagnostic chunk") }
                    chunks[index] = chunk
                }
            }
            let text = try (0..<count).map { index in
                let chunk = try XCTUnwrap(chunks[index], "Missing complete Inspector diagnostic chunk \(index)")
                XCTAssertEqual(chunk.count, min(384, encodedLength - index * 384), "Truncated diagnostic chunk")
                return chunk
            }.joined()
            XCTAssertEqual(text.count, encodedLength, "Every diagnostic byte must survive the public snapshot")
            let attachment = XCTAttachment(string: text); attachment.name = "SF-NARROW \(presentation) measured \(role) \(phase)"; attachment.lifetime = .keepAlways; add(attachment)
            let payload = try XCTUnwrap(Data(base64Encoded: text), "Inspector must expose every diagnostic byte")
            let values = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            if comparePresentation {
                let identity = try XCTUnwrap(values["host"] as? String) + (try XCTUnwrap(values["path"] as? String))
                let script = try XCTUnwrap(values["script"] as? [String: Any])
                let hash = try XCTUnwrap(script["sha256"] as? String)
                if arm {
                    // Safari need not expose a context selector for the
                    // current page. Prove the evaluated context itself, not
                    // a version-specific selector caption or cached proxy.
                    XCTAssertEqual(identity, try XCTUnwrap(artifactIdentity))
                    XCTAssertEqual(hash, try XCTUnwrap(runtimeHash))
                    XCTAssertEqual(values["title"] as? String, role == "header" ? headerTitle : footerTitle)
                    XCTAssertNotNil(values["menuRect"] as? [String: Double])
                }
                let receipt = XCTAttachment(string: "window=\(safari.windows.firstMatch.identifier);frame=\(safari.windows.firstMatch.frame);prompt=\(prompt.frame);evaluatedDocument=\(identity);runtime=\(hash)")
                receipt.name = "SF-CONTEXT \(presentation) live public target \(role) \(phase)"; receipt.lifetime = .keepAlways; add(receipt)
            } else { safari.typeKey("i", modifierFlags: [.command, .option]) }
            return values
        }
        @MainActor func responsiveMode(_ enabled: Bool) {
            safari.menuBars.menuBarItems["Develop"].click()
            let item = safari.menuItems[enabled ? "Enter Responsive Design Mode" : "Exit Responsive Design Mode"]
            if item.exists { item.click() } else { safari.typeKey(.escape, modifierFlags: []) }
        }
        for requestedWidth in widths {
            var width = requestedWidth
            var commonHeight: Int?
            application.activate()
            selectNavigatorTab("Pages", identifier: "pages", in: application)
            pageRow(named: "Home", in: application).click()
            componentMenu("Preview", "Preview Website in Safari", in: application)
            XCTAssertTrue(safari.webViews.staticTexts[headerTitle].firstMatch.waitForExistence(timeout: 10))
            safari.typeKey("0", modifierFlags: .command)
            for mode in (comparePresentation ? ["ordinary", "responsive"] : ["responsive"]) {
            presentation = mode
            var allClosedBaseline: XCUIScreenshot?
            var baselineWindowFrame: CGRect?
            responsiveMode(mode == "responsive")
            if mode == "ordinary" {
                var actual = try measured("header", phase: "ordinary viewport observation")
                var cssWidth = try XCTUnwrap(actual["width"] as? Int)
                // Use real tab-local native zoom, not an unproven window
                // resize or a mislabeled nominal RDM width. Match both CSS
                // dimensions so RDM need not shrink its presentation to fit.
                for step in 0..<6 where cssWidth >= 600 {
                    safari.menuBars.menuBarItems["View"].click()
                    safari.menuItems["Zoom In"].click()
                    actual = try measured("header", phase: "ordinary native zoom \(step + 1)")
                    cssWidth = try XCTUnwrap(actual["width"] as? Int)
                }
                XCTAssertTrue((320..<600).contains(cssWidth), "Record Safari's real limit; do not relabel a non-hamburger viewport")
                width = cssWidth
                let context = try XCTUnwrap(actual["context"] as? [String: Any])
                let viewport = try XCTUnwrap(context["viewport"] as? [String: Any])
                commonHeight = Int(try XCTUnwrap(viewport["height"] as? Double))
            } else {
            if comparePresentation {
                // The Console prompt can consume Command-0, leaving the
                // ordinary tab's page zoom active inside responsive mode.
                // Route through the visible browser menu before requesting
                // dimensions; measured CSS width/height remain exact checks.
                safari.menuBars.menuBarItems["View"].click()
                let actualSize = safari.menuItems["Actual Size"]
                XCTAssertTrue(actualSize.exists)
                if actualSize.isEnabled { actualSize.click() }
                else { safari.typeKey(.escape, modifierFlags: []) }
            }
            let browserWidth = safari.textFields.matching(NSPredicate(format: "label == %@ OR title == %@", "Width", "Width")).firstMatch
            XCTAssertTrue(browserWidth.waitForExistence(timeout: 5))
            if let commonHeight {
                let height = safari.textFields.matching(NSPredicate(format: "label == %@ OR title == %@", "Height", "Height")).firstMatch
                XCTAssertTrue(height.waitForExistence(timeout: 5))
                height.click(); height.typeKey("a", modifierFlags: .command)
                height.typeText(String(commonHeight)); height.typeKey(.return, modifierFlags: [])
            }
            replaceSafariResponsiveWidth(with: width, in: safari)
            }
            var header = try measured("header")
            // RDM can round its scaled CSS width by one pixel. Use one
            // measured correction through the real field, never a universal
            // +1 heuristic or an assertion accepting the wrong viewport.
            if mode == "responsive", let actual = header["width"] as? Int, abs(actual - width) == 1 {
                replaceSafariResponsiveWidth(with: width + (width - actual), in: safari)
                header = try measured("header")
            }
            let footer = try measured("footer")
            if comparePresentation {
                let context = try XCTUnwrap(header["context"] as? [String: Any])
                let viewport = try XCTUnwrap(context["viewport"] as? [String: Any])
                XCTAssertEqual(Int(try XCTUnwrap(viewport["height"] as? Double)), commonHeight)
                let identity = try XCTUnwrap(header["host"] as? String) + (try XCTUnwrap(header["path"] as? String))
                let script = try XCTUnwrap(header["script"] as? [String: Any])
                let hash = try XCTUnwrap(script["sha256"] as? String)
                if let artifactIdentity { XCTAssertEqual(identity, artifactIdentity) } else { artifactIdentity = identity }
                if let runtimeHash { XCTAssertEqual(hash, runtimeHash) } else { runtimeHash = hash }
            }
            for (role, context, title) in [("Header", header, headerTitle), ("Footer", footer, footerTitle)] {
                XCTAssertEqual(context["width"] as? Int, width)
                XCTAssertEqual(context["scale"] as? Double, 1)
                XCTAssertEqual(context["title"] as? String, title)
                if width < 600 {
                    let t = try XCTUnwrap(context["titleRect"] as? [String: Double])
                    let n = try XCTUnwrap(context["navRect"] as? [String: Double])
                    XCTAssertGreaterThanOrEqual(try XCTUnwrap(n["width"]), 89)
                    XCTAssertLessThanOrEqual(try XCTUnwrap(t["right"]), try XCTUnwrap(n["x"]) + 1)
                    let menu = safari.descendants(matching: .any).matching(NSPredicate(format: "label == %@", role + " navigation menu")).firstMatch
                    if observeClosure {
                        let beforeState = try measured(role.lowercased(), phase: "before opening", arm: true)
                        let dom = try XCTUnwrap(beforeState["dom"] as? [String: Any])
                        let menus = try XCTUnwrap(dom["menus"] as? [[String: Any]])
                        if role == "Header" {
                            XCTAssertTrue(menus.allSatisfy { ($0["open"] as? Bool) == false })
                        } else {
                            // Header was deliberately reopened to challenge
                            // exclusive menu ownership. Its painted panel is
                            // not an all-closed pixel baseline for Footer.
                            XCTAssertEqual(menus.filter { ($0["open"] as? Bool) == true }.count, 1)
                        }
                    }
                    let summaryFrame = observeClosure ? menu.frame : .zero
                    let beforeOpening = observeClosure ? XCUIScreen.main.screenshot() : nil
                    if observeClosure, role == "Header" {
                        allClosedBaseline = beforeOpening
                        baselineWindowFrame = safari.windows.firstMatch.frame
                    }
                    if let beforeOpening {
                        let attachment = XCTAttachment(screenshot: beforeOpening)
                        attachment.name = "SF-NARROW \(presentation) live screen \(role) baseline before opening \(width)"
                        attachment.lifetime = .keepAlways
                        add(attachment)
                    }
                    XCTAssertTrue(menu.isHittable); menu.click()
                    if observeClosure {
                        attachScreenshot(named: "SF-NARROW \(presentation) live screen \(role) open \(width)")
                    } else {
                        attachWindowScreenshot(safari, named: "SF-NARROW independent Safari \(role) open \(width)")
                    }
                    safari.typeKey(.escape, modifierFlags: [])
                    // WebKit disclosure controls need not have AX identifiers.
                    // Require focus on this exact named disclosure, not on any
                    // Safari element that happens to share an empty identifier.
                    let menuLabel = role + " navigation menu"
                    let focusedMenu = safari.disclosureTriangles.matching(NSPredicate(
                        format: "label == %@ AND hasKeyboardFocus == true", menuLabel)).firstMatch
                    let restoredMenuFocus = focusedMenu.waitForExistence(timeout: 5)
                    if !restoredMenuFocus {
                        attachFocusDiagnostics(expected: menuLabel, application: safari)
                    }
                    XCTAssertTrue(restoredMenuFocus, "Escape must restore focus to \(menuLabel)")
                    if observeClosure {
                        // Resolve label and collapsed value in one native
                        // snapshot. Separate exists/value round trips can
                        // overrun this same bounded deadline even when AX
                        // already exposes zero after the real Escape.
                        let collapsed = safari.descendants(matching: .any).matching(NSPredicate(
                            format: "label == %@ AND (value == 0 OR value == %@)",
                            role + " navigation menu", "0")).firstMatch
                        let collapsedInAccessibility = collapsed.waitForExistence(timeout: 3)
                        if !collapsedInAccessibility {
                            let live = safari.descendants(matching: .any).matching(NSPredicate(
                                format: "label == %@", role + " navigation menu")).firstMatch
                            let exists = live.exists
                            let value = exists ? String(describing: live.value) : "missing"
                            let frame = exists ? String(describing: live.frame) : "missing"
                            let diagnostics = XCTAttachment(string:
                                "presentation=\(presentation);role=\(role);appState=\(safari.state.rawValue);exists=\(exists);value=\(value);frame=\(frame)")
                            diagnostics.name = "SF-CONTEXT menu collapse accessibility failure"
                            diagnostics.lifetime = .keepAlways; add(diagnostics)
                            attachScreenshot(named: "SF-CONTEXT menu collapse failure before Inspector")
                            // Observe the same public artifact after the real
                            // Escape; never close it through JavaScript or
                            // accept DOM state in place of the AX assertion.
                            _ = try measured(role.lowercased(), phase: "collapse accessibility failure")
                        }
                        XCTAssertTrue(collapsedInAccessibility)
                        // Preserve the actual screen before Inspector or a
                        // window-specific capture can perturb the RDM surface.
                        let closedCapture = XCUIScreen.main.screenshot()
                        let closedAttachment = XCTAttachment(screenshot: closedCapture)
                        closedAttachment.name = "SF-NARROW \(presentation) live screen \(role) closed before Inspector \(width)"
                        closedAttachment.lifetime = .keepAlways
                        add(closedAttachment)
                        let capturedAt = Date().timeIntervalSince1970 * 1_000
                        let closed = try measured(role.lowercased(), phase: "after application Escape and rendered frames")
                        let dom = try XCTUnwrap(closed["dom"] as? [String: Any])
                        let menus = try XCTUnwrap(dom["menus"] as? [[String: Any]])
                        let trace = try XCTUnwrap(closed["eventTrace"] as? [String: Any])
                        let events = try XCTUnwrap(trace["events"] as? [[String: Any]])
                        let event = try XCTUnwrap(events.last)
                        XCTAssertEqual(event["trusted"] as? Bool, true)
                        XCTAssertEqual(event["target"] as? String, "SUMMARY")
                        let frames = try XCTUnwrap(trace["afterFrames"] as? [String: Any])
                        XCTAssertEqual(frames["defaultPrevented"] as? Bool, true)
                        let frameState = try XCTUnwrap(frames["state"] as? [String: Any])
                        XCTAssertEqual(frameState["hasFocus"] as? Bool, true)
                        XCTAssertLessThanOrEqual(try XCTUnwrap(frameState["wall"] as? Double), capturedAt)
                        let framedMenus = try XCTUnwrap(frameState["menus"] as? [[String: Any]])
                        XCTAssertEqual(framedMenus.filter { ($0["summaryFocused"] as? Bool) == true }.count, 1)
                        XCTAssertTrue(menus.allSatisfy { ($0["open"] as? Bool) == false && ($0["expanded"] as? String) == "false" }, "Escape must close the actual DOM menus, not merely leave a focused summary")
                        XCTAssertTrue(menus.allSatisfy { ($0["panel"] as? [String: Any])?["paintEligible"] as? Bool == false })
                        let navigation = try XCTUnwrap(closed["navigation"] as? [[String: Any]])
                        XCTAssertTrue(navigation.allSatisfy { ($0["visible"] as? Bool) == false }, "Neither inline nor popup links may remain visible after Escape at a narrow width")
                        let hitSamples = try XCTUnwrap(closed["formerPanelHits"] as? [[String: Any]])
                        XCTAssertFalse(hitSamples.isEmpty)
                        for sample in hitSamples {
                            let elements = try XCTUnwrap(sample["elements"] as? [[String: Any]])
                            XCTAssertFalse(elements.contains { ["A", "NAV"].contains($0["tag"] as? String ?? "") }, "Closed panel must no longer own its former hit target")
                        }
                        let afterCapture = try measured(role.lowercased(), phase: "after closed screenshot")
                        let capturedDOM = try XCTUnwrap(afterCapture["dom"] as? [String: Any])
                        let capturedMenus = try XCTUnwrap(capturedDOM["menus"] as? [[String: Any]])
                        XCTAssertTrue(capturedMenus.allSatisfy { ($0["open"] as? Bool) == false })
                        if !comparePresentation {
                            safari.typeKey(.tab, modifierFlags: [])
                            attachScreenshot(named: "SF-NARROW live screen \(role) closed after genuine Tab \(width)")
                        }
                        XCTAssertEqual(safari.windows.firstMatch.frame, try XCTUnwrap(baselineWindowFrame))
                        let before = try XCTUnwrap(allClosedBaseline)
                        let baseline = try XCTUnwrap(NSBitmapImageRep(data: before.pngRepresentation))
                        let painted = try XCTUnwrap(NSBitmapImageRep(data: closedCapture.pngRepresentation))
                        let summary = try XCTUnwrap(context["menuRect"] as? [String: Double])
                        let beforeState = try XCTUnwrap(event["before"] as? [String: Any])
                        let beforeMenus = try XCTUnwrap(beforeState["menus"] as? [[String: Any]])
                        let openedMenu = try XCTUnwrap(beforeMenus.first { $0["open"] as? Bool == true })
                        let panel = try XCTUnwrap(openedMenu["panel"] as? [String: Any])
                        let factor = summaryFrame.width / CGFloat(try XCTUnwrap(summary["width"]))
                        // Screenshot NSImage.size is physical pixels on this
                        // runtime; AX frames are points on the primary screen.
                        let screen = try XCTUnwrap(NSScreen.screens.first)
                        XCTAssertEqual(screen.frame.origin, .zero)
                        let scale = CGFloat(painted.pixelsWide) / screen.frame.width
                        XCTAssertEqual(CGFloat(painted.pixelsHigh) / screen.frame.height, scale, accuracy: 0.001)
                        let panelRect = CGRect(
                            x: summaryFrame.minX + CGFloat(try XCTUnwrap(panel["x"] as? Double) - XCTUnwrap(summary["x"])) * factor,
                            y: summaryFrame.minY + CGFloat(try XCTUnwrap(panel["y"] as? Double) - XCTUnwrap(summary["y"])) * factor,
                            width: CGFloat(try XCTUnwrap(panel["width"] as? Double)) * factor,
                            height: CGFloat(try XCTUnwrap(panel["height"] as? Double)) * factor).insetBy(dx: 8 * factor, dy: 8 * factor)
                        var changed = 0, sampled = 0
                        for y in max(0, Int(panelRect.minY * scale))..<min(painted.pixelsHigh, Int(panelRect.maxY * scale)) {
                            for x in max(0, Int(panelRect.minX * scale))..<min(painted.pixelsWide, Int(panelRect.maxX * scale)) {
                                let old = try XCTUnwrap(baseline.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                                let new = try XCTUnwrap(painted.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                                sampled += 1
                                if max(abs(old.redComponent - new.redComponent), abs(old.greenComponent - new.greenComponent), abs(old.blueComponent - new.blueComponent)) > 0.08 { changed += 1 }
                            }
                        }
                        XCTAssertGreaterThan(sampled, 100)
                        let pixelReceipt = "\(presentation) \(role) CSS\(width): changed=\(changed)/\(sampled);allowed=\(max(4, sampled / 1_000));rect=\(panelRect);AXsummary=\(summaryFrame);DOMsummary=\(summary);backing=\(scale)"
                        let receipt = XCTAttachment(string: pixelReceipt)
                        receipt.name = "SF-CONTEXT \(presentation) \(role) exact pixel comparison"; receipt.lifetime = .keepAlways; add(receipt)
                        if comparePresentation {
                            // Observe both modes before failing their shared
                            // strict pixel gate; never accept stale pixels.
                            if changed > max(4, sampled / 1_000) { pixelFailures.append(pixelReceipt) }
                        } else {
                            XCTAssertLessThanOrEqual(changed, max(4, sampled / 1_000), "Escape must restore the former panel's actual pixels, not merely close its DOM; \(pixelReceipt)")
                        }
                        if role == "Header" {
                            // Reopen through the actual summary. The following
                            // Footer click must close this Header, not orphan it.
                            menu.click()
                            XCTAssertTrue(safari.webViews.links["About"].firstMatch.waitForExistence(timeout: 3))
                        }
                    }
                }
            }
            attachWindowScreenshot(safari, named: "SF-NARROW \(presentation) independent Safari measured \(width)")
            if width < 600 && !comparePresentation {
                let destination = try XCTUnwrap((header["links"] as? [[String: String]])?.first { $0["label"] == "About" }?["path"])
                let menu = safari.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Header navigation menu")).firstMatch
                menu.click(); let about = safari.webViews.links["About"].firstMatch
                XCTAssertTrue(about.isHittable); about.click()
                let followed = try measured("header")
                XCTAssertEqual(followed["path"] as? String, destination)
                XCTAssertEqual(followed["host"] as? String, header["host"] as? String)
                attachWindowScreenshot(safari, named: "SF-NARROW independent Safari actual About \(width)")
            }
            }
            if comparePresentation {
                if safari.textViews["Console prompt"].firstMatch.exists { safari.typeKey("i", modifierFlags: [.command, .option]) }
                safari.typeKey("0", modifierFlags: .command)
            }
            safari.typeKey("w", modifierFlags: .command)
            application.activate(); application.buttons["Stop"].click(); application.buttons["preview.website.done"].click()
        }
        XCTAssertTrue(pixelFailures.isEmpty, "Escape must restore actual pixels in every observed presentation: \(pixelFailures.joined(separator: "; "))")
    }

    @MainActor
    private func replaceSafariResponsiveWidth(with width: Int, in safari: XCUIApplication) {
        let fields = safari.textFields.matching(NSPredicate(format: "label == %@ OR title == %@", "Width", "Width"))
        XCTAssertTrue(fields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(fields.count, 1)
        let field = fields.firstMatch
        XCTAssertTrue(field.isEnabled && field.isHittable)
        field.click()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hasKeyboardFocus == true"), object: fields.firstMatch)], timeout: 3) == .completed)
        fields.firstMatch.typeKey("a", modifierFlags: .command)
        fields.firstMatch.typeText(String(width))
        fields.firstMatch.typeKey(.return, modifierFlags: [])
        fields.firstMatch.typeKey(.tab, modifierFlags: [])
    }

    // SF-0507-003/006, SF-0604-003/006, SF-1202-003/004, SF-1204-003/004.
    // Read-only Web Inspector evaluation measures the actual CSS viewport;
    // neither outer-window pixels nor editor zoom stand in for browser width.
    @MainActor
    // SF-LOCAL-BUILDER-013 — strict native Header pointer and geometry acceptance.
    // Independent companions do not waive this path.
    func testAutomaticNarrowChromeNativeAndMeasuredSafariMenuJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Page", "New Page…", in: application)
        XCTAssertTrue(application.textFields["page.editor.name"].waitForExistence(timeout: 3))
        replaceText(in: application.textFields["page.editor.name"], with: "About", application: application)
        application.buttons["page.editor.apply"].click()
        selectNavigatorTab("Pages", identifier: "pages", in: application)
        let home = pageRow(named: "Home", in: application)
        XCTAssertTrue(home.waitForExistence(timeout: 3)); home.click()
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        let headerID = canvasObject(named: "Header", in: application).identifier.replacingOccurrences(of: "canvas.object.", with: "")
        let title = "Phone Header Layout Receipt"
        selectInspectorTab("Content", identifier: "content", in: application)
        replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: title, in: application)
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        let footerTitle = "Phone Footer Layout Receipt"
        replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: footerTitle, in: application)
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        let footer = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Footer")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 3))
        let footerID = footer.identifier.replacingOccurrences(of: "navigator.layer.", with: "")
        let titleRow = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Site title")).firstMatch
        XCTAssertTrue(titleRow.waitForExistence(timeout: 3))
        let titleID = titleRow.identifier.replacingOccurrences(of: "navigator.layer.", with: "")
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")

        @MainActor func measuredContext(role: String = "header") throws -> [String: Any] {
            let marker = "SF_CHROME_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + " "
            safari.typeKey("c", modifierFlags: [.command, .option])
            let prompt = safari.textViews["Console prompt"].firstMatch
            XCTAssertTrue(prompt.waitForExistence(timeout: 5))
            prompt.coordinate(withNormalizedOffset: .init(dx: 0.03, dy: 0.5)).click()
            // Read-only DOM geometry in the real visible Web Inspector. No page
            // state, styles, window size or navigation is changed by this code.
            let script = "(function(){var h=document.querySelector('\(role)[data-siteforge-node]'),q=h&&h.querySelector('[data-siteforge-text]'),t=q&&q.parentElement,n=h&&h.querySelector('.sf-page-navigation'),s=n&&n.querySelector('summary');function r(e){if(!e)return null;var b=e.getBoundingClientRect();return {x:b.x,right:b.right,width:b.width,height:b.height}}console.log('\(marker)'+JSON.stringify({width:innerWidth,scale:visualViewport.scale,host:location.host,path:location.pathname,title:t&&t.textContent,id:t&&t.getAttribute('data-siteforge-node'),titleRect:r(t),navRect:r(n),menuRect:r(s),links:h?Array.from(h.querySelectorAll('a[href]')).map(function(a){return {label:a.textContent,path:new URL(a.getAttribute('href'),location.href).pathname}}):[]}))}())"
            let board = NSPasteboard.general
            let saved = (board.pasteboardItems ?? []).map { item in item.types.compactMap { type in item.data(forType: type).map { (type, $0) } } }
            do {
                defer {
                    board.clearContents()
                    board.writeObjects(saved.map { values in let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item })
                }
                board.clearContents(); board.setString(script, forType: .string)
                prompt.typeKey("v", modifierFlags: .command); prompt.typeKey(.return, modifierFlags: [])
            }
            let readout = safari.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", marker + "{", marker + "{")).firstMatch
            XCTAssertTrue(readout.waitForExistence(timeout: 5))
            let text = (readout.value as? String) ?? readout.label
            let attachment = XCTAttachment(string: text); attachment.name = "SF-NARROW measured CSS context"; attachment.lifetime = .keepAlways; add(attachment)
            let start = try XCTUnwrap(text.range(of: "{"))
            let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text[start.lowerBound...].utf8)) as? [String: Any])
            safari.typeKey("i", modifierFlags: [.command, .option])
            return values
        }

        @MainActor func nativeMenu(_ owner: String) -> XCUIElement {
            application.sheets.firstMatch.descendants(matching: .menuButton)["preview.navigation.menu." + owner].firstMatch
        }
        @MainActor func nativeMenuReady(_ owner: String) -> Bool {
            let ready = NSPredicate { _, _ in
                let live = nativeMenu(owner)
                return live.exists && live.isEnabled && live.isHittable
            }
            return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 5) == .completed
        }
        for width in [320, 430, 768] {
            application.activate()
            selectStructuralLayer("Header", in: application)
            replaceText(in: application.textFields["canvas.viewport.width"], with: String(width), application: application)
            application.textFields["canvas.viewport.width"].typeKey(.return, modifierFlags: [])
            XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.width", containing: String(width)))
            application.buttons["canvas.zoom.reset"].click()
            XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, "canvas.object." + headerID)
            attachWindowScreenshot(application, named: "SF-NARROW native automatic Header Footer \(width)")
            if width < 600 {
                let authoredHeader = canvasObject(named: "Header", in: application).frame
                let authoredNavigation = application.descendants(matching: .any).matching(NSPredicate(
                    format: "identifier BEGINSWITH %@ AND label == %@", "canvas.object.", "Navigation"))
                    .allElementsBoundByIndex.filter { authoredHeader.contains($0.frame) }
                XCTAssertEqual(authoredNavigation.count, 1)
                let navigationFrame = try XCTUnwrap(authoredNavigation.first).frame
                componentMenu("Preview", "Canvas Device Preview", in: application)
                var menu = nativeMenu(headerID)
                XCTAssertTrue(menu.waitForExistence(timeout: 5))
                XCTAssertEqual(application.sheets.firstMatch.descendants(matching: .menuButton)
                    .matching(identifier: "preview.navigation.menu." + headerID).count, 1)
                let headers = application.sheets.firstMatch.descendants(matching: .any)
                    .matching(NSPredicate(format: "label == %@", "Header"))
                XCTAssertEqual(headers.count, 1)
                let previewHeader = headers.firstMatch.frame
                let pixel = 1 / (NSScreen.main?.backingScaleFactor ?? 1)
                XCTAssertEqual(previewHeader.width, authoredHeader.width, accuracy: pixel)
                XCTAssertEqual(previewHeader.height, authoredHeader.height, accuracy: pixel)
                XCTAssertEqual(menu.frame.midX, previewHeader.minX + navigationFrame.midX - authoredHeader.minX, accuracy: pixel)
                XCTAssertEqual(menu.frame.midY, previewHeader.minY + navigationFrame.midY - authoredHeader.minY, accuracy: pixel)
                XCTAssertTrue(waitForValue(application.descendants(matching: .any)["preview.page"], containing: "Home"))
                let initiallyHittable = nativeMenuReady(headerID)
                // Exercise the genuine native keyboard path before the pointer
                // path; focus must belong to this sheet's live menu, not the
                // underlying editor's still-retained first responder.
                for _ in 0..<16 {
                    if hasKeyboardFocus(nativeMenu(headerID)) { break }
                    application.typeKey(.tab, modifierFlags: [])
                }
                XCTAssertTrue(waitForKeyboardFocus(nativeMenu(headerID), in: application))
                let peers = XCTAttachment(string: "menuHittable=\(nativeMenu(headerID).isHittable); doneHittable=\(application.buttons["preview.done"].isHittable); pagePickerHittable=\(application.descendants(matching: .any)["preview.page"].isHittable)")
                peers.name = "SF-NARROW native sheet peer hit readiness"
                peers.lifetime = .keepAlways; add(peers)
                application.typeKey(.downArrow, modifierFlags: [])
                XCTAssertTrue(application.menuItems["About"].waitForExistence(timeout: 3))
                application.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(waitForKeyboardFocus(nativeMenu(headerID), in: application))
                XCTAssertTrue(initiallyHittable, "The real control must be hittable before keyboard interaction too")
                let menuIsHittable = nativeMenuReady(headerID)
                menu = nativeMenu(headerID)
                if !menuIsHittable {
                    attachReadinessDiagnostics(for: application)
                    let done = application.buttons["preview.done"]
                    let pagePicker = application.descendants(matching: .any)["preview.page"]
                    let diagnostic = XCTAttachment(string: "menu=\(menu.frame); enabled=\(menu.isEnabled); hittable=\(menu.isHittable)\ndone=\(done.frame); enabled=\(done.isEnabled); hittable=\(done.isHittable)\npagePicker=\(pagePicker.frame); enabled=\(pagePicker.isEnabled); hittable=\(pagePicker.isHittable)\npreview=\(application.descendants(matching: .any)["preview.canvas"].frame)\n\(application.debugDescription)")
                    diagnostic.name = "SF-NARROW real native menu geometry and hierarchy"
                    diagnostic.lifetime = .keepAlways; add(diagnostic)
                    attachWindowScreenshot(application, named: "SF-NARROW native menu unavailable before pointer action")
                }
                XCTAssertTrue(menuIsHittable)
                assertElement(menu, isContainedIn: application.descendants(matching: .any)["preview.canvas"])
                menu.click(); application.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(waitForKeyboardFocus(menu, in: application))
                attachWindowScreenshot(application, named: "SF-NARROW native menu Escape restored focus \(width)")
                XCTAssertTrue(nativeMenuReady(footerID))
                let footerMenu = nativeMenu(footerID)
                assertElement(footerMenu, isContainedIn: application.descendants(matching: .any)["preview.canvas"])
                footerMenu.click(); application.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(waitForKeyboardFocus(footerMenu, in: application))
                attachWindowScreenshot(application, named: "SF-NARROW native Footer menu and Escape focus \(width)")
                menu.click(); application.menuItems["About"].click()
                XCTAssertTrue(waitForValue(application.descendants(matching: .any)["preview.page"], containing: "About"))
                application.buttons["preview.done"].click()
                XCTAssertTrue(application.buttons["navigator.layer." + headerID].isSelected)
            }
            componentMenu("Preview", "Preview Website in Safari", in: application)
            XCTAssertTrue(safari.webViews.staticTexts[title].firstMatch.waitForExistence(timeout: 10))
            safari.typeKey("0", modifierFlags: .command)
            safari.menuBars.menuBarItems["Develop"].click()
            let responsive = safari.menuItems["Enter Responsive Design Mode"]
            if responsive.exists { responsive.click() } else { safari.typeKey(.escape, modifierFlags: []) }
            let browserWidth = safari.textFields.matching(NSPredicate(format: "label == %@ OR title == %@", "Width", "Width")).firstMatch
            XCTAssertTrue(browserWidth.waitForExistence(timeout: 5))
            replaceSafariResponsiveWidth(with: width, in: safari)
            var context = try measuredContext()
            if let actual = context["width"] as? Int, abs(actual - width) == 1 {
                replaceSafariResponsiveWidth(with: width + (width - actual), in: safari)
                context = try measuredContext()
            }
            XCTAssertEqual(context["width"] as? Int, width, "Use measured innerWidth, never the RDM border-inclusive field")
            XCTAssertEqual(context["scale"] as? Double, 1)
            XCTAssertEqual(context["title"] as? String, title)
            XCTAssertEqual(context["id"] as? String, titleID)
            let footerContext = try measuredContext(role: "footer")
            XCTAssertEqual(footerContext["width"] as? Int, width)
            XCTAssertEqual(footerContext["scale"] as? Double, 1)
            XCTAssertEqual(footerContext["title"] as? String, footerTitle)
            if width < 600 {
                let ft = try XCTUnwrap(footerContext["titleRect"] as? [String: Double])
                let fn = try XCTUnwrap(footerContext["navRect"] as? [String: Double])
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(fn["width"]), 89)
                XCTAssertLessThanOrEqual(try XCTUnwrap(ft["right"]), try XCTUnwrap(fn["x"]) + 1)
                let footerMenu = safari.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Footer navigation menu")).firstMatch
                XCTAssertTrue(footerMenu.isHittable); footerMenu.click(); safari.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(waitForKeyboardFocus(footerMenu, in: safari))
                attachWindowScreenshot(safari, named: "SF-NARROW Safari measured Footer menu and title \(width)")
                let t = try XCTUnwrap(context["titleRect"] as? [String: Double])
                let n = try XCTUnwrap(context["navRect"] as? [String: Double])
                let m = try XCTUnwrap(context["menuRect"] as? [String: Double])
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(n["width"]), 89)
                XCTAssertLessThanOrEqual(try XCTUnwrap(t["right"]), try XCTUnwrap(n["x"]) + 1)
                XCTAssertGreaterThanOrEqual(try XCTUnwrap(m["x"]), try XCTUnwrap(n["x"]) - 1)
                XCTAssertLessThanOrEqual(try XCTUnwrap(m["right"]), try XCTUnwrap(n["right"]) + 1)
                let menu = safari.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Header navigation menu")).firstMatch
                XCTAssertTrue(menu.isHittable); menu.click(); safari.typeKey(.escape, modifierFlags: [])
                XCTAssertTrue(waitForKeyboardFocus(menu, in: safari))
                attachWindowScreenshot(safari, named: "SF-NARROW Safari measured menu and full title \(width)")
                let destination = try XCTUnwrap((context["links"] as? [[String: String]])?.first { $0["label"] == "About" }?["path"])
                menu.click(); let about = safari.webViews.links["About"].firstMatch
                XCTAssertTrue(about.isHittable); about.click()
                XCTAssertTrue(safari.webViews.staticTexts[title].firstMatch.waitForNonExistence(timeout: 5))
                let followed = try measuredContext()
                XCTAssertEqual(followed["path"] as? String, destination)
                XCTAssertEqual(followed["host"] as? String, context["host"] as? String)
                attachWindowScreenshot(safari, named: "SF-NARROW Safari actual About navigation \(width)")
            } else {
                attachWindowScreenshot(safari, named: "SF-NARROW Safari larger inline navigation \(width)")
            }
            // Close only the tab opened by this isolated local Preview and
            // verified above by its unique title / followed same-host route.
            safari.typeKey("w", modifierFlags: .command)
            application.activate(); application.buttons["Stop"].click(); application.buttons["preview.website.done"].click()
            XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, "canvas.object." + headerID)
            XCTAssertTrue(application.buttons["navigator.layer." + footerID].exists)
        }
    }

    func testManagedChromeTitleMatchedSafariWidthsAndOverflowJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        let longTitle = "Connected Fluid Browser Receipt"
        replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: longTitle, in: application)
        componentMenu("Insert", "Insert Section in Flow", in: application)
        componentMenu("Insert", "Insert Text at Center", in: application)
        selectInspectorTab("Layout", identifier: "layout", in: application)
        for (field, value) in [("x", "20"), ("y", "20"), ("width", "160"), ("height", "60")] {
            replaceStructuralLayoutField(application.textFields["inspector.layout." + field], with: value, in: application)
        }
        componentMenu("Selection", "Edit Selected Text", in: application)
        let editor = application.textViews["canvas.text.editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        replaceText(in: editor, with: "Body first line\nBody second line", application: application)
        editor.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(waitForNonexistence(editor))
        componentMenu("Insert", "Insert Footer after Page Content", in: application)
        selectStructuralLayer("Header", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        for (width, title, visible, name) in [(1440, longTitle, true, "long"),
                (430, longTitle, true, "long"), (320, longTitle, true, "long"),
                (430, "Short Title", true, "short"), (430, "Short Title", false, "hidden")] {
            if title != longTitle && visible {
                replaceStructuralLayoutField(application.textFields["inspector.navigation.title"], with: title, in: application)
            }
            if !visible { application.checkBoxes["inspector.navigation.title.visible"].click() }
            replaceText(in: application.textFields["canvas.viewport.width"], with: String(width), application: application)
            application.textFields["canvas.viewport.width"].typeKey(.return, modifierFlags: [])
            XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.viewport.width", containing: String(width == 1440 ? "1,440" : "\(width)")))
            application.buttons["canvas.zoom.reset"].click()
            XCTAssertTrue(waitForLiveValue(in: application, identifier: "canvas.zoom.value", containing: "100"))
            attachWindowScreenshot(application, named: "SF-TITLE native \(width) CSS width \(name) title at100percent")
            componentMenu("Preview", "Preview Website in Safari", in: application)
            XCTAssertTrue(application.staticTexts["preview.website.url"].waitForExistence(timeout: 10))
            XCTAssertTrue(safari.webViews.firstMatch.waitForExistence(timeout: 10))
            if visible { XCTAssertTrue(safari.webViews.staticTexts[title].firstMatch.waitForExistence(timeout: 10)) }
            safari.typeKey("0", modifierFlags: .command)
            safari.menuBars.menuBarItems["Develop"].click()
            let enter = safari.menuItems["Enter Responsive Design Mode"]
            if enter.exists { enter.click() } else { safari.typeKey(.escape, modifierFlags: []) }
            let browserWidth = safari.textFields.matching(NSPredicate(format: "label == %@ OR title == %@", "Width", "Width")).firstMatch
            XCTAssertTrue(browserWidth.waitForExistence(timeout: 5))
            browserWidth.click(); browserWidth.typeKey("a", modifierFlags: .command)
            // Request the actual CSS width. A historical universal +1
            // compensation now creates a genuinely mismatched viewport.
            // Evaluated innerWidth below must still equal the request exactly.
            browserWidth.typeText(String(width)); browserWidth.typeKey(.return, modifierFlags: [])
            XCTAssertEqual(browserWidth.value as? String, String(width))
            browserWidth.typeKey(.tab, modifierFlags: [])
            safari.typeKey("c", modifierFlags: [.command, .option])
            let prompt = safari.textViews["Console prompt"].firstMatch
            XCTAssertTrue(prompt.waitForExistence(timeout: 5))
            // Web Inspector exposes the real prompt but its native hit-point
            // search fails inside the docked WebView. Click its visible leading
            // edge, not the application's undefined bounding rectangle.
            XCTAssertTrue(prompt.frame.minX.isFinite && prompt.frame.minY.isFinite)
            prompt.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).click()
            let marker = "SF_TITLE_CONTEXT_" + UUID().uuidString.replacingOccurrences(of: "-", with: "") + " "
            let script = "console.log('\(marker)'+JSON.stringify({width:innerWidth,scale:visualViewport.scale,dpr:devicePixelRatio,title:Array.from(document.querySelectorAll('p[data-siteforge-node]')).filter(function(e){return e.textContent==='\(title)'}).map(function(e){var s=getComputedStyle(e),r=e.getBoundingClientRect(),t=e.querySelector('[data-siteforge-text]'),q=t&&t.getBoundingClientRect();return {id:e.getAttribute('data-siteforge-node'),tag:e.tagName,width:r.width,height:r.height,font:s.font,lineHeight:s.lineHeight,whiteSpace:s.whiteSpace,display:s.display,text:e.textContent,lines:t&&getComputedStyle(t).webkitLineClamp,textHeight:q&&q.height,centerDelta:q&&(q.y+q.height/2-r.y-r.height/2)}}),body:Array.from(document.querySelectorAll('p[data-siteforge-node]')).filter(function(e){return e.textContent.indexOf('Body first line')===0}).map(function(e){return {text:e.textContent,helpers:e.querySelectorAll('[data-siteforge-text]').length}})}))"
            let pasteboard = NSPasteboard.general
            let saved = (pasteboard.pasteboardItems ?? []).map { item in
                item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
            }
            do {
                defer {
                    pasteboard.clearContents()
                    pasteboard.writeObjects(saved.map { values in
                        let item = NSPasteboardItem(); for (type, data) in values { item.setData(data, forType: type) }; return item
                    })
                }
                pasteboard.clearContents(); pasteboard.setString(script, forType: .string)
                prompt.typeKey("v", modifierFlags: .command)
                // Safari exposes a placeholder AXValue for this contenteditable;
                // the actual evaluated readout below is the proof, not AXValue.
                prompt.typeKey(.return, modifierFlags: [])
            }
            let readout = safari.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", marker + "{", marker + "{")).firstMatch
            let measured = readout.waitForExistence(timeout: 5)
            let capture = XCTAttachment(screenshot: safari.windows.firstMatch.screenshot())
            capture.name = "SF-TITLE Safari \(width) \(name) measured console context"; capture.lifetime = .keepAlways; add(capture)
            XCTAssertTrue(measured)
            if measured {
                let text = (readout.value as? String) ?? readout.label
                let context = XCTAttachment(string: text)
                context.name = "SF-TITLE measured CSS context \(width) \(name)"; context.lifetime = .keepAlways; add(context)
                let json = try XCTUnwrap(text.range(of: "{"))
                let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text[json.lowerBound...].utf8)) as? [String: Any])
                XCTAssertEqual(values["width"] as? Int, width)
                XCTAssertEqual(values["scale"] as? Double, 1)
                let projected = try XCTUnwrap((values["title"] as? [[String: Any]])?.first)
                XCTAssertEqual(projected["text"] as? String, title)
                XCTAssertEqual(projected["display"] as? String, visible ? "flex" : "none")
                if visible {
                    XCTAssertEqual(projected["lines"] as? String, "1")
                    XCTAssertEqual(projected["textHeight"] as? Double ?? -1, 17, accuracy: 1)
                    XCTAssertEqual(projected["centerDelta"] as? Double ?? -10, 0, accuracy: 1)
                }
                let body = try XCTUnwrap((values["body"] as? [[String: Any]])?.first)
                XCTAssertEqual(body["text"] as? String, "Body first line\nBody second line")
                XCTAssertEqual(body["helpers"] as? Int, 0)
            }
            safari.typeKey("i", modifierFlags: [.command, .option])
            let image = XCTAttachment(screenshot: safari.windows.firstMatch.screenshot())
            image.name = "SF-TITLE Safari \(width) matched \(name) title"; image.lifetime = .keepAlways; add(image)
            safari.typeKey("w", modifierFlags: .command)
            application.activate()
            application.buttons["Stop"].click(); application.buttons["preview.website.done"].click()
        }
    }

    // SF-0202-003, SF-0701-006, SF-1202/1203/1204-003/004/006:
    // real findings open the existing editor; navigation itself has no undo step.
    // Execution receipts are recorded in the closeout evidence.
    @MainActor
    func testPreviewAndCheckWebsiteFindingRepairUsesExistingEditorJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        XCTAssertTrue(canvasObject(named: "Header", in: application).waitForExistence(timeout: 5))
        let headerID = canvasObject(named: "Header", in: application).identifier
        XCTAssertFalse(headerID.isEmpty)
        selectInspectorTab("Content", identifier: "content", in: application)
        let title = application.textFields["inspector.navigation.title"]
        let websiteTitle = "Output repair " + UUID().uuidString
        replaceText(in: title, with: websiteTitle, application: application)
        title.typeKey(.return, modifierFlags: [])
        selectInspectorTab("Design", identifier: "design", in: application)

        // 016 integration: invalid Design input blocks commit-capable Preview
        // without being reset by a display refresh or silently entering history.
        let fillDraft = revealComponentPointerTarget("inspector.design.fillHex", in: application)
        let originalFill = try XCTUnwrap(fillDraft.value as? String)
        replaceText(in: fillDraft, with: "#GG", application: application)
        componentMenu("Preview", "Preview Website in Safari", in: application)
        XCTAssertTrue(application.staticTexts["workspace.editBoundary.status"].waitForExistence(timeout: 3))
        XCTAssertFalse(application.descendants(matching: .any)["preview.website"].exists)
        XCTAssertTrue(waitForValue(application.textFields["inspector.design.fillHex"], containing: "#GG"))
        attachWindowScreenshot(application, named: "SF-OUTPUT-REPAIR invalid draft retained before Preview")
        application.textFields["inspector.design.fillHex"].click()
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let live = application.textFields["inspector.design.fillHex"]
            return live.exists && (live.value as? String) == originalFill
        }, object: nil)], timeout: 3), .completed)

        @MainActor func clipControl() -> XCUIElement {
            revealComponentPointerTarget("inspector.design.clipContent", in: application)
        }
        @MainActor func clipIsOn() -> Bool {
            let live = application.descendants(matching: .any)["inspector.design.clipContent"].firstMatch
            return (live.value as? NSNumber)?.boolValue == true || (live.value as? String) == "1"
        }
        @MainActor func waitForClip(_ expected: Bool) -> Bool {
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let live = application.descendants(matching: .any)["inspector.design.clipContent"].firstMatch
                return live.exists && clipIsOn() == expected
            }, object: nil)], timeout: 5) == .completed
        }
        @MainActor func repairButton(_ prefix: String) -> XCUIElement {
            application.buttons.matching(NSPredicate(format:
                "identifier BEGINSWITH %@ AND identifier CONTAINS %@",
                prefix + ".reveal.", "page-flow-navigation-clipped")).firstMatch
        }
        @MainActor func assertEditorAdopted() {
            XCTAssertTrue(application.staticTexts["inspector.outputRepair.status"].waitForExistence(timeout: 5))
            XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, headerID)
            XCTAssertTrue(waitForLabel(application.descendants(matching: .any)["status.selectionPath"], containing: "Header"))
            XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.selectionPath"], containing: "1 selected"))
            XCTAssertTrue(clipControl().isEnabled)
        }

        XCTAssertFalse(clipIsOn())
        clipControl().click()
        XCTAssertTrue(waitForClip(true))
        componentMenu("Preview", "Preview Website in Safari", in: application)
        let previewRepair = repairButton("preview.website.finding")
        XCTAssertTrue(previewRepair.waitForExistence(timeout: 10))
        XCTAssertEqual(previewRepair.label, "Open Design")
        XCTAssertFalse(application.buttons["preview.website.export"].isEnabled)
        XCTAssertTrue(waitForLiveSemanticText(in: application, identifier: "preview.website.artifact", containing: "No successful website"))
        attachWindowScreenshot(application, named: "SF-OUTPUT-REPAIR Preview blocked with exact repair action")
        // Traverse actual native focus order, never invoke a model/test-only action.
        for _ in 0..<32 {
            if hasKeyboardFocus(repairButton("preview.website.finding")) { break }
            application.typeKey(.tab, modifierFlags: [])
        }
        XCTAssertTrue(hasKeyboardFocus(repairButton("preview.website.finding")))
        application.typeKey(" ", modifierFlags: [])
        assertEditorAdopted()
        attachWindowScreenshot(application, named: "SF-OUTPUT-REPAIR selected Header in existing Design editor")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForClip(false), "Reveal must not insert a navigation transaction into undo history")
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForClip(true))

        componentMenu("Build", "Check Website", in: application)
        XCTAssertTrue(repairButton("build.finding").waitForExistence(timeout: 10))
        attachWindowScreenshot(application, named: "SF-OUTPUT-REPAIR Check Website shares repair semantics")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(clipIsOn(), "Cancel must not repair content")
        componentMenu("Build", "Check Website", in: application)
        let checkRepair = repairButton("build.finding")
        XCTAssertTrue(waitForHittable(checkRepair, in: application))
        checkRepair.click()
        assertEditorAdopted()
        clipControl().click()
        XCTAssertTrue(waitForClip(false))

        componentMenu("Preview", "Preview Website in Safari", in: application)
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        XCTAssertTrue(safari.webViews.staticTexts[websiteTitle].firstMatch.waitForExistence(timeout: 10))
        // Close only the tab proven to contain this isolated journey's title.
        safari.typeKey("w", modifierFlags: .command)
        application.activate()
        attachWindowScreenshot(application, named: "SF-OUTPUT-REPAIR repaired successful output ready for explicit Refresh")
        application.buttons["preview.website.refresh"].click()
        XCTAssertTrue(safari.webViews.staticTexts[websiteTitle].firstMatch.waitForExistence(timeout: 10))
        safari.typeKey("w", modifierFlags: .command)
        application.activate()
        XCTAssertTrue(application.buttons["preview.website.export"].isEnabled)
        application.buttons["Stop"].click()
        application.buttons["preview.website.done"].click()
        XCTAssertEqual(canvasObject(named: "Header", in: application).identifier, headerID)
    }

    func testBrowserPreviewCommittedHeaderRefreshAndStopJourney() throws {
        let application = launchWorkspace()
        assertNormalWindowPolicy(in: application)
        componentMenu("Insert", "Insert Header at Page Top", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        let title = application.textFields["inspector.navigation.title"]
        replaceText(in: title, with: "Source batch preview snapshot", application: application)
        title.typeKey(.return, modifierFlags: [])
        let preview = application.buttons["toolbar.preview"]
        XCTAssertTrue(waitForHittable(preview, in: application)); preview.click()
        let address = application.staticTexts["preview.website.url"]
        XCTAssertTrue(address.waitForExistence(timeout: 10))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        XCTAssertTrue(safari.webViews.staticTexts["Source batch preview snapshot"].firstMatch.waitForExistence(timeout: 10))
        safari.typeKey("w", modifierFlags: .command)
        application.activate()
        attachWindowScreenshot(application, named: "SF-SOURCE-10 immutable website preview ready")
        application.buttons["preview.website.refresh"].click()
        XCTAssertTrue(safari.webViews.staticTexts["Source batch preview snapshot"].firstMatch.waitForExistence(timeout: 10))
        safari.typeKey("w", modifierFlags: .command)
        application.activate()
        application.buttons["Stop"].click()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let live = application.staticTexts["preview.website.status"]
            return live.exists && (live.value as? String) == "Website preview stopped."
        }, object: nil)], timeout: 3), .completed)
        XCTAssertFalse(application.buttons["preview.website.export"].isEnabled)
        attachWindowScreenshot(application, named: "SF-SOURCE-10 stopped preview has no export target")
        application.buttons["preview.website.done"].click()
        XCTAssertTrue(application.buttons["navigator.tab.pages"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLocalPreviewRefreshesOnlyOnExplicitRequestJourney() throws {
        let application = launchWorkspace()
        let canvas = application.descendants(matching: .any)["canvas.interaction"]
        application.buttons["toolbar.tool.frame"].click()
        XCTAssertTrue(waitForHittable(canvas, in: application))
        canvas.coordinate(withNormalizedOffset: .init(dx: 0.52, dy: 0.48)).click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        componentMenu("Preview", "Canvas Device Preview", in: application)
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
        selectInspectorTab("Interactions", identifier: "interactions", in: application)
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

        componentMenu("Preview", "Canvas Device Preview", in: application)
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
        @MainActor func exposedTabs(_ prefix: String, titles: [(String, String)]) -> [XCUIElement] {
            var elements = titles.compactMap { id, _ -> XCUIElement? in
                let button = application.buttons[prefix + "." + id]
                return button.exists ? button : nil
            }
            let overflow = application.descendants(matching: .any)[prefix + ".overflow"].firstMatch
            if overflow.exists {
                XCTAssertTrue(waitForHittable(overflow, in: application))
                overflow.click()
                // Slim render-01 panes use genuine native overflow. Every
                // destination still has a real operable menu action.
                for (_, title) in titles {
                    XCTAssertTrue(application.menuItems[title].waitForExistence(timeout: 3), title)
                    XCTAssertTrue(application.menuItems[title].isEnabled, title)
                }
                application.typeKey(.escape, modifierFlags: [])
                elements.append(overflow)
            } else { XCTAssertEqual(elements.count, titles.count) }
            XCTAssertGreaterThanOrEqual(elements.count, 2)
            return elements
        }
        let navigatorTabs = exposedTabs("navigator.tab", titles: [
            ("pages", "Pages"), ("layers", "Layers"), ("elements", "Elements"),
            ("assets", "Assets"), ("components", "Components")])
        let inspectorTabs = exposedTabs("inspector.tab", titles: [
            ("design", "Design"), ("layout", "Layout"), ("content", "Content"),
            ("interactions", "Interactions"), ("accessibility", "Accessibility")])

        pages.click()
        XCTAssertTrue(waitForKeyboardFocus(pages, in: application))
        for destination in navigatorTabs.dropFirst() {
            application.typeKey("\t", modifierFlags: [])
            XCTAssertTrue(waitForKeyboardFocus(destination, in: application))
        }
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
        XCTAssertTrue(waitForKeyboardFocus(application.textFields["canvas.viewport.width"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(application.buttons["canvas.viewport.compare"], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(
            application.descendants(matching: .any)["canvas.grid.toggle"],
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
        for destination in inspectorTabs {
            application.typeKey("\t", modifierFlags: [])
            XCTAssertTrue(waitForKeyboardFocus(destination, in: application))
        }
        application.typeKey("\t", modifierFlags: .shift)
        XCTAssertTrue(waitForKeyboardFocus(inspectorTabs[inspectorTabs.count - 2], in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(try XCTUnwrap(inspectorTabs.last), in: application))
        application.typeKey("\t", modifierFlags: [])
        XCTAssertTrue(waitForKeyboardFocus(pages, in: application))

        let reverseTraversal: [XCUIElement] = Array(inspectorTabs.reversed()) + [
            application.descendants(matching: .any)["canvas.interaction"],
            application.buttons["canvas.zoom.fit"],
            application.buttons["canvas.zoom.fitCanvas"],
            application.buttons["canvas.zoom.reset"],
            application.buttons["canvas.zoom.in"],
            application.buttons["canvas.zoom.out"],
            application.checkBoxes["canvas.grid.toggle"],
            application.buttons["canvas.viewport.compare"],
            application.textFields["canvas.viewport.width"],
            application.descendants(matching: .any)["canvas.viewport.preset"],
            pageRow(named: "Not Found", in: application),
            pageRow(named: "Home", in: application),
            application.textFields["navigator.pages.search"],
        ] + Array(navigatorTabs.reversed())
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
        let starterProject = application.buttons["launch.newStarterProject"]
        let openProject = application.buttons["launch.openProject"]
        XCTAssertTrue(newProject.exists)
        XCTAssertTrue(starterProject.exists)
        XCTAssertTrue(openProject.exists)
        XCTAssertEqual(newProject.label, "Blank Site")
        XCTAssertEqual(starterProject.label, "Starter Site")
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
        XCTAssertTrue(starterProject.isHittable)
        XCTAssertTrue(openProject.isHittable)
        application.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 2))
    }

    // SF-LOCAL-BUILDER-001 / SF-0204-002/004/005/006.
    @MainActor
    func testAuroraResponsiveContentConversionPreservesSelectionAndReflowsAcrossPresetsJourney() throws {
        let application = launchScenario("welcome")
        @MainActor func assertLiveHugHeight() {
            let inspector = application.scrollViews["inspector.selection.scroll"]
            // A preset can rebuild the Inspector at its top. The computed,
            // disabled geometry readout is below the container/sizing cards;
            // off-viewport SwiftUI fields need not exist in the AX collection.
            // Reveal the shipping readout without trying to edit/enable it.
            for _ in 0..<10 {
                let field = application.textFields["inspector.layout.height"]
                if field.exists, pointerSafeIntersection(for: inspector.frame).contains(field.frame) { break }
                inspector.scroll(byDeltaX: 0, deltaY: -180)
            }
            let field = application.textFields["inspector.layout.height"]
            XCTAssertTrue(field.exists, "The real computed geometry readout must be exposed after scrolling")
            XCTAssertTrue(waitForLiveValue(in: application, identifier: "inspector.layout.height", containing: "Computed by Hug"))
        }
        application.buttons["launch.newAuroraProject"].click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let section = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section"
        )).firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 5))
        let identity = section.identifier
        section.click()
        selectInspectorTab("Layout", identifier: "layout", in: application)
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.height"], containing: "800"))
        attachWindowScreenshot(application, named: "SF-WORKFLOW Aurora fixed content before opt-in")
        let conversion = revealStructuralLayoutControl(application.buttons["inspector.sizing.convertContent"], in: application)
        conversion.click()
        let confirm = application.sheets.firstMatch.buttons["Convert to automatic sizing"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.height"], containing: "800"))
        revealStructuralLayoutControl(application.buttons["inspector.sizing.convertContent"], in: application).click()
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()
        assertLiveHugHeight()
        for name in ["Desktop", "Tablet", "Mobile"] {
            let preset = application.descendants(matching: .any)["canvas.viewport.preset"].firstMatch
            preset.click(); application.menuItems[name].click()
            XCTAssertTrue(waitForValue(preset, containing: name))
            XCTAssertTrue(waitForWorkspaceReady(application))
            application.buttons["canvas.zoom.fit"].click()
            assertLiveHugHeight()
            XCTAssertTrue(application.buttons[identity].isSelected)
            attachWindowScreenshot(application, named: "SF-WORKFLOW Aurora responsive content \(name)")
        }
        application.buttons["toolbar.undo"].click()
        XCTAssertTrue(waitForValue(application.textFields["inspector.layout.height"], containing: "800"))
        application.buttons["toolbar.redo"].click()
        assertLiveHugHeight()
        XCTAssertTrue(application.buttons[identity].isSelected)
    }

    // Normal Welcome / native file panels only. Optional input/output paths
    // belong to the test driver, never to an app mutation hook. The default
    // full-suite case uses a fresh packaged sample and owned temporary output.
    func testAuroraRelatedPageReuseNativeCopyAndSafariJourney() throws {
        continueAfterFailure = false
        if Self.applicationBundleIdentifier == "app.siteforge.SiteForge" {
            XCTAssertTrue(NSRunningApplication.runningApplications(withBundleIdentifier: Self.applicationBundleIdentifier).isEmpty,
                "The ordinary installed app must be saved and quit normally before this isolated review")
            guard NSRunningApplication.runningApplications(withBundleIdentifier: Self.applicationBundleIdentifier).isEmpty else { return }
        }
        let environment = ProcessInfo.processInfo.environment
        let source = environment["SITEFORGE_REVIEW_SOURCE_PATH"].map { URL(fileURLWithPath: $0) }
        let sourceBytes = try source.map { try Data(contentsOf: $0) }
        let destination = environment["SITEFORGE_REVIEW_DESTINATION_PATH"].map { URL(fileURLWithPath: $0) }
            ?? fixtureRoot.appendingPathComponent("Aurora Workflow Review.siteforge")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path), "Review must never overwrite an existing project")
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        let application = trackedApplication()
        application.launchArguments += baseLaunchArguments()
        application.launch(); application.activate()
        XCTAssertTrue(application.buttons["launch.newBlankProject"].waitForExistence(timeout: 5))
        if let source { openProjectThroughNativePanel(source, in: application) }
        else { application.buttons["launch.newAuroraProject"].click() }
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        selectShellTab("Pages", directIdentifier: "navigator.tab.pages", overflowIdentifier: "navigator.tab.overflow", in: application)
        pageRow(named: "Home", in: application).click()
        let homeID = pageRow(named: "Home", in: application).identifier
        attachWindowScreenshot(application, named: "Aurora reuse normal source before independent Save As")

        componentMenu("File", "Save As…", in: application)
        let filename = application.textFields["saveAsNameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 5))
        replaceText(in: filename, with: destination.deletingPathExtension().lastPathComponent, application: application)
        navigateReviewSavePanel(to: destination.deletingLastPathComponent(), in: application)
        let save = application.buttons["OKButton"]
        XCTAssertTrue(waitForHittable(save, in: application)); save.click()
        XCTAssertTrue(waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 5))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        if let source, let sourceBytes {
            XCTAssertTrue(try Data(contentsOf: source) == sourceBytes, "Save As must preserve the source package")
        }

        componentMenu("Page", "New Page…", in: application)
        replaceText(in: application.textFields["page.editor.name"], with: "Workflow Review", application: application)
        replaceText(in: application.textFields["page.editor.route"], with: "/workflow-review", application: application)
        application.checkBoxes["page.editor.copyCurrent"].click()
        application.buttons["page.editor.apply"].click()
        let review = pageRow(named: "Workflow Review", in: application)
        XCTAssertTrue(review.waitForExistence(timeout: 5)); XCTAssertNotEqual(review.identifier, homeID)
        let reviewID = review.identifier
        selectStructuralLayer("Header", in: application)
        selectInspectorTab("Content", identifier: "content", in: application)
        revealStructuralLayoutControl(application.buttons["inspector.navigation.includeAll"], in: application).click()
        attachWindowScreenshot(application, named: "Aurora reuse copied Header content and page inclusion")
        for presetName in ["Tablet", "Mobile", "Desktop"] {
            let preset = application.popUpButtons["canvas.viewport.preset"]
            preset.click(); application.menuItems[presetName].click()
            XCTAssertTrue(waitForValue(preset, containing: presetName))
            application.buttons["canvas.zoom.fit"].click()
            attachWindowScreenshot(application, named: "Aurora reuse independent page \(presetName) fit")
        }
        saveDocumentIfModified(in: application)
        let committed = try Data(contentsOf: destination)
        application.buttons["toolbar.preview"].click()
        let previewURL = application.staticTexts["preview.website.url"]
        XCTAssertTrue(previewURL.waitForExistence(timeout: 10))
        let address = (previewURL.value as? String) ?? previewURL.label
        let url = try XCTUnwrap(URL(string: address))
        XCTAssertEqual(url.host, "127.0.0.1"); XCTAssertTrue(url.path.contains("workflow-review"))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            safari.state == .runningForeground
        }, object: nil)], timeout: 10), .completed)
        // Safari exposes native web-link names as titles; their labels may be empty.
        let currentLink = safari.webViews.links.matching(NSPredicate(format: "title == %@", "Workflow Review")).firstMatch
        XCTAssertTrue(currentLink.waitForExistence(timeout: 10), safari.debugDescription)
        let browser = XCTAttachment(screenshot: safari.windows.firstMatch.screenshot())
        browser.name = "Aurora reuse actual Safari independent page"; browser.lifetime = .keepAlways; add(browser)
        safari.typeKey("w", modifierFlags: .command) // Only our verified new preview tab.
        application.activate()
        // Exercise the actual exporter, preserving an optional independently
        // owned output for browser review. No generated HTML is hand-edited.
        let exported = environment["SITEFORGE_REVIEW_EXPORT_PATH"].map { URL(fileURLWithPath: $0) }
            ?? fixtureRoot.appendingPathComponent("Website Review")
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path))
        application.buttons["Export…"].click()
        XCTAssertTrue(application.textFields["saveAsNameTextField"].waitForExistence(timeout: 5))
        application.windows["save-panel"].buttons["CancelButton"].click()
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path), "Cancel must not create output")
        application.buttons["Export…"].click()
        let exportName = application.textFields["saveAsNameTextField"]
        XCTAssertTrue(exportName.waitForExistence(timeout: 5))
        replaceText(in: exportName, with: exported.lastPathComponent, application: application)
        navigateReviewSavePanel(to: exported.deletingLastPathComponent(), in: application)
        let exportSave = application.windows["save-panel"].buttons["OKButton"]
        XCTAssertTrue(waitForHittable(exportSave, in: application)); exportSave.click()
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "preview.website.status", containing: "Exported"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exported.appendingPathComponent("workflow-review.html").path))
        attachWindowScreenshot(application, named: "Aurora independent immutable website export after cancellation and retry")
        application.buttons["Stop"].click(); application.buttons["preview.website.done"].click()
        XCTAssertTrue(try Data(contentsOf: destination) == committed, "Preview and preset fitting remain noncanonical")
        application.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["workspace.shell"]))
        openProjectThroughNativePanel(destination, in: application)
        XCTAssertTrue(waitForWorkspaceReady(application))
        selectShellTab("Pages", directIdentifier: "navigator.tab.pages", overflowIdentifier: "navigator.tab.overflow", in: application)
        XCTAssertEqual(pageRow(named: "Workflow Review", in: application).identifier, reviewID)
        XCTAssertEqual(pageRow(named: "Home", in: application).identifier, homeID)
        pageRow(named: "Workflow Review", in: application).click()
        attachWindowScreenshot(application, named: "Aurora reuse saved reopened ordinary copy")
        if let source, let sourceBytes {
            XCTAssertTrue(try Data(contentsOf: source) == sourceBytes, "Review edits must never rewrite the source")
        }
        saveDocumentIfModified(in: application)
        componentMenu("SiteForge", "Quit SiteForge", in: application)
        XCTAssertTrue(application.wait(for: .notRunning, timeout: 5))
    }

    func testAuroraPackagedSampleCreatesEditableFourPageWebsiteJourney() throws {
        let application = launchScenario("welcome")
        let sample = application.buttons["launch.newAuroraProject"]
        XCTAssertTrue(sample.waitForExistence(timeout: 3))
        XCTAssertTrue(sample.isEnabled)
        XCTAssertTrue(sample.isHittable)
        attachWindowScreenshot(application, named: "Aurora packaged sample Welcome")
        sample.click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)
        selectShellTab("Pages", directIdentifier: "navigator.tab.pages", overflowIdentifier: "navigator.tab.overflow", in: application)
        for (name, route) in [("Home", "/"), ("Journal", "/journal"), ("About", "/about"), ("Contact", "/contact")] {
            let page = application.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@", "navigator.page.", "\(name), route \(route)"
            )).firstMatch
            XCTAssertTrue(page.waitForExistence(timeout: 3), name)
            page.click()
            XCTAssertTrue(waitForWorkspaceReady(application))
        }
        application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.page.", "Home, route /"
        )).firstMatch.click()
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let section = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section"
        )).firstMatch
        XCTAssertTrue(section.waitForExistence(timeout: 3))
        section.click()
        selectInspectorTab("Layout", identifier: "layout", in: application)
        XCTAssertTrue(application.textFields["inspector.layout.height"].waitForExistence(timeout: 3))
        XCTAssertFalse(application.windows.firstMatch.title.contains("Edited"), "Opening and inspecting a sample must retain the clean creation baseline")
        application.menuBars.menuBarItems["Edit"].click()
        XCTAssertFalse(application.menuItems["Undo"].isEnabled, "The source project's authoring history must not enter a new sample")
        application.typeKey(.escape, modifierFlags: [])
        application.buttons["inspector.tab.layout"].click()
        attachWindowScreenshot(application, named: "Aurora packaged sample editable Home")
    }

    // SF-AUTHORING-106 / SF-0204-001...008
    @MainActor
    func testStarterSiteCreatesOrdinaryHomeAboutSemanticWorkspaceJourney() throws {
        let application = launchScenario("welcome")
        let starter = application.buttons["launch.newStarterProject"]
        XCTAssertTrue(starter.waitForExistence(timeout: 3))
        XCTAssertTrue(starter.isHittable)
        starter.click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        assertNormalWindowPolicy(in: application)

        selectShellTab("Pages", directIdentifier: "navigator.tab.pages", overflowIdentifier: "navigator.tab.overflow", in: application)
        let home = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.page.", "Home, route /"
        )).firstMatch
        let about = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.page.", "About, route /about"
        )).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 3))
        XCTAssertTrue(about.waitForExistence(timeout: 3))
        XCTAssertEqual(application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "navigator.page."
        )).count, 2)
        XCTAssertFalse(application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS[c] %@", "navigator.page.", "Not Found"
        )).firstMatch.exists)

        about.click()
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        for name in ["Header", "Main", "Footer", "Site title", "Introduction", "Footer text"] {
            XCTAssertTrue(application.buttons.matching(NSPredicate(
                format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", name
            )).firstMatch.waitForExistence(timeout: 3), name)
        }
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 6", timeout: 5))
        attachWindowScreenshot(application, named: "SF-AUTHORING-106 Starter Site Home About")
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
        let history = application.buttons["launch.recovery.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let review = application.buttons["launch.recovery.review"]
        XCTAssertFalse(review.exists, "A historical fixture has no crash evidence and must not be automatically promoted")
        assertNormalWindowPolicy(in: application)
        @MainActor func retainedBytes() throws -> [String: Data] {
            if try recovery.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                return ["recovery": try Data(contentsOf: recovery)]
            }
            let files = try XCTUnwrap(FileManager.default.enumerator(at: recovery,
                includingPropertiesForKeys: [.isRegularFileKey]))
            var result: [String: Data] = [:]
            for case let file as URL in files where try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[String(file.path.dropFirst(recovery.path.count))] = try Data(contentsOf: file)
            }
            return result
        }
        let before = try retainedBytes()
        XCTAssertFalse(before.isEmpty)
        attachWindowScreenshot(application, named: "SF-LOCAL-BUILDER Welcome retains manual recovery history")
        history.click()
        XCTAssertTrue(application.buttons["launch.recovery.later"].waitForExistence(timeout: 5))
        attachWindowScreenshot(application, named: "SF-UI-010 Recovery Review and Later")
        application.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        XCTAssertEqual(try retainedBytes(), before)
        review.click()
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
        let historyAgain = application.buttons["launch.recovery.history"]
        XCTAssertTrue(historyAgain.waitForExistence(timeout: 5))
        XCTAssertFalse(application.buttons["launch.recovery.review"].exists)
        historyAgain.click()
        let discard = application.buttons["launch.recovery.discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.click()
        XCTAssertTrue(application.descendants(matching: .any)["shell.canvas"].waitForExistence(timeout: 5))
    }

    // SF-0306-003/004/005/006. Only this test-owned Debug process may be
    // force-terminated; the owner's installed ordinary app is never eligible.
    @MainActor
    func testCrashQualifiedRecoverySeparatesFirstCleanAndInterruptedLaunchJourney() throws {
        var application = launchWorkspace()
        XCTAssertFalse(application.buttons["launch.recovery.review"].exists)
        application.menuBars.menuBarItems["SiteForge"].click()
        application.menuItems["Quit SiteForge"].click()
        XCTAssertTrue(application.wait(for: .notRunning, timeout: 5))

        func launchRealWelcome() -> XCUIApplication {
            let app = trackedApplication()
            app.launchArguments += baseLaunchArguments()
            recordLaunchState("before-launch", app)
            app.launch(); app.activate()
            recordLaunchState("after-activate", app)
            XCTAssertTrue(app.buttons["launch.newBlankProject"].waitForExistence(timeout: 5))
            return app
        }
        application = launchRealWelcome()
        XCTAssertFalse(application.buttons["launch.recovery.review"].exists)
        attachWindowScreenshot(application, named: "Recovery clean launch has no crash offer")
        application.buttons["launch.newBlankProject"].click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        application.menuBars.menuBarItems["Insert"].click()
        application.menuItems["Insert Frame at Center"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        var snapshot: URL?
        let recovered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            snapshot = (try? FileManager.default.contentsOfDirectory(at: self.recoveryDirectory,
                includingPropertiesForKeys: [.fileSizeKey]))?.first {
                $0.pathExtension == "siteforge-recovery" && ((try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
            }
            return snapshot != nil && String(describing: application.descendants(matching: .any)["status.document"].firstMatch.value ?? "").contains("Modified")
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [recovered], timeout: 10), .completed)
        let url = try XCTUnwrap(snapshot)
        let bytes = try Data(contentsOf: url)
        let diagnostics = try String(contentsOf: lifecycleDiagnosticURL, encoding: .utf8)
        let pids = Set(diagnostics.split(separator: "\n").filter { $0.contains("run=\(uiTestRunID);") }
            .flatMap { $0.split(separator: ";") }.filter { $0.hasPrefix("pid=") }
            .compactMap { Int32($0.dropFirst(4)) })
        XCTAssertEqual(pids.count, 2, "Two real app sessions were launched in this isolated fixture")
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.applicationBundleIdentifier)
            .filter { pids.contains($0.processIdentifier) }
        XCTAssertEqual(running.count, 1)
        let owned = try XCTUnwrap(running.first)
        let executable = try XCTUnwrap(owned.executableURL).resolvingSymlinksInPath().path
        // The runner and tested app are siblings in this exact build product
        // directory, including isolated unattended builds. Never accept the
        // ordinary installed app or another run based on a suffix alone.
        let runner = Bundle.main.bundleURL.resolvingSymlinksInPath()
        XCTAssertEqual(runner.lastPathComponent, "SiteForgeUITests-Runner.app")
        let products = runner.deletingLastPathComponent()
        XCTAssertEqual(products.lastPathComponent, "Debug")
        let testedBundle = products.appendingPathComponent("SiteForge.app")
        let expectedExecutable = testedBundle.appendingPathComponent("Contents/MacOS/SiteForge")
            .resolvingSymlinksInPath().path
        XCTAssertEqual(Bundle(url: testedBundle)?.bundleIdentifier, Self.applicationBundleIdentifier)
        XCTAssertEqual(executable, expectedExecutable)
        guard runner.lastPathComponent == "SiteForgeUITests-Runner.app",
              products.lastPathComponent == "Debug",
              Bundle(url: testedBundle)?.bundleIdentifier == Self.applicationBundleIdentifier,
              owned.bundleIdentifier == Self.applicationBundleIdentifier,
              executable == expectedExecutable,
              diagnostics.split(separator: "\n").contains(where: {
                  let fields = $0.split(separator: ";")
                  return fields.contains("run=\(uiTestRunID)")
                      && fields.contains("pid=\(owned.processIdentifier)")
                      && fields.contains("bundle=\(Self.applicationBundleIdentifier)")
                      && fields.contains("executable=SiteForge.app/Contents/MacOS/SiteForge")
              }) else {
            XCTFail("Refusing termination: launched artifact/run/PID ownership does not match")
            return
        }
        XCTAssertTrue(owned.forceTerminate())
        XCTAssertTrue(application.wait(for: .notRunning, timeout: 5))

        application = launchRealWelcome()
        let review = application.buttons["launch.recovery.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 8))
        attachWindowScreenshot(application, named: "Recovery interrupted isolated session offers retained work")
        review.click()
        XCTAssertTrue(application.buttons["launch.recovery.later"].waitForExistence(timeout: 5))
        attachWindowScreenshot(application, named: "Recovery interrupted work can be inspected without restoration")
        application.buttons["launch.recovery.later"].click()
        XCTAssertTrue(application.buttons["launch.newBlankProject"].waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
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
        let canvasPoint = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1))
        let hint = application.descendants(matching: .any)["canvas.empty.hint"]
        if hint.exists {
            XCTAssertFalse(hint.frame.contains(canvasPoint.screenPoint), "Exercise canvas outside the intentional bounded hint")
        }
        canvasPoint.click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "interactions 1", timeout: 5))

        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        let layerRows = application.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "navigator.layer."))
        XCTAssertEqual(layerRows.count, 1, "A blank page exposes only its structural Root, not sample objects")
        let rootRow = layerRows.element(boundBy: 0)
        XCTAssertEqual(rootRow.label, "Root")
        XCTAssertTrue((rootRow.value as? String)?.contains("Page structure") == true)
        XCTAssertFalse(rootRow.isSelected)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        for prefix in ["canvas.object.", "canvas.selection."] {
            XCTAssertFalse(application.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch.exists,
                "Structural Root must not fabricate authored paint, hit targets or selection chrome")
        }
        attachWindowScreenshot(application, named: "SF-ACCEPTANCE structural Root with zero authored canvas objects")

        // Structural page ownership is discoverable in Layers. Only a real
        // insertion may create an authored canvas object and selected layer.
        selectShellTab("Pages", directIdentifier: "navigator.tab.pages", overflowIdentifier: "navigator.tab.overflow", in: application)
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

        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
        XCTAssertEqual(layerRows.count, 2)
        let frameRow = application.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Frame")).firstMatch
        XCTAssertTrue(frameRow.isSelected)
        let frameID = frameRow.identifier.replacingOccurrences(of: "navigator.layer.", with: "")
        XCTAssertTrue(application.descendants(matching: .any)["canvas.object." + frameID].firstMatch.exists,
                      "The inserted canonical layer and adopted render object must share identity")
        attachWindowScreenshot(application, named: "SF-ACCEPTANCE native material and inserted Frame adoption")
        selectShellTab("Pages", directIdentifier: "navigator.tab.pages", overflowIdentifier: "navigator.tab.overflow", in: application)
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

    private func waitForDisclosureExpanded(_ element: XCUIElement) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let control = object as? XCUIElement, control.exists else { return false }
            return (control.value as? NSNumber)?.intValue == 1 || (control.value as? String) == "1"
                || (control.value as? String) == "Expanded"
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 3) == .completed
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
        let result = XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: application)],
            timeout: timeout
        )
        if result != .completed {
            let element = application.descendants(matching: .any)[identifier].firstMatch
            if element.exists {
                print("Live AX value mismatch for \(identifier): exists=true label=\(element.label) value=\(String(describing: element.value))")
            } else {
                print("Live AX value mismatch for \(identifier): exists=false")
            }
            let selection = application.descendants(matching: .any)["status.selectionPath"].firstMatch
            if selection.exists {
                print("Live selection at mismatch: label=\(selection.label) value=\(String(describing: selection.value))")
            }
        }
        return result == .completed
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
            guard let value = canvas.value as? String else { return false }
            if text.hasPrefix("rendered objects ") {
                // A count of 1 must never accept 12 after an adopted insertion.
                return value.split(separator: ";").contains {
                    $0.trimmingCharacters(in: .whitespaces) == text
                }
            }
            return value.contains(text)
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
        selectShellTab("Layers", directIdentifier: "navigator.tab.layers", overflowIdentifier: "navigator.tab.overflow", in: application)
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
        for _ in 0..<10 {
            if isSafelyVisibleForPointer(liveElement, inside: scroll) { break }
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
        let safelyVisible = isSafelyVisibleForPointer(liveElement, inside: scroll)
        if !safelyVisible {
            attachPointerDiagnostics(control: liveElement, application: application)
        }
        XCTAssertTrue(
            safelyVisible,
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
        guard let button = revealStructuralLayoutRadioButton(label,
            groupIdentifier: groupIdentifier, in: application) else { return }
        button.click()
    }

    /// A native segmented group's bezel can extend outside the logical
    /// scroll frame. Its concrete buttons are the real pointer/AX targets;
    /// keep their strict screen containment and bounded readiness contract.
    private func revealStructuralLayoutRadioButton(
        _ label: String,
        groupIdentifier: String,
        in application: XCUIApplication
    ) -> XCUIElement? {
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
            return nil
        }

        group = liveStructuralLayoutControl(groupIdentifier, in: application)
        button = group.radioButtons[label]
        return button
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
        let saved = waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 8)
        if !saved {
            let details = XCTAttachment(string: redactedAccessibilityHierarchy(for: application))
            details.name = "native-save-live-status-boundary"; details.lifetime = .keepAlways; add(details)
            attachWindowScreenshot(application, named: "native-save-live-status-failure")
        }
        XCTAssertTrue(saved)
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

    // SF-AUTHORING-111 / SF-0308-001...008 / SF-0901-006 — the real native
    // clipboard path reviews a complete cross-project definition import before
    // one atomic paste; cancellation remains destination-neutral.
    @MainActor
    func testCrossProjectComponentPastePreflightImportUndoRedoAccessibilityJourney() throws {
        let application = launchWorkspace()
        componentMenu("Insert", "Insert Frame at Center", in: application)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        componentMenu("Component", "Create Component from Selection", in: application)
        application.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.clipboard"],
                                   containing: "Copied 1 object"))

        application.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(application.buttons["documentTransition.discard"].waitForExistence(timeout: 3))
        application.buttons["documentTransition.discard"].click()
        XCTAssertTrue(waitForWorkspaceReady(application))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))

        application.typeKey("v", modifierFlags: .command)
        let preflight = application.descendants(matching: .any)["clipboard.component.preflight"]
        XCTAssertTrue(preflight.waitForExistence(timeout: 5))
        let summary = application.descendants(matching: .any)["clipboard.component.summary"]
        XCTAssertTrue(
            waitForValue(summary, containing: "1 imported") ||
            waitForLabel(summary, containing: "1 imported"),
            "The native preflight must expose its transfer summary through a stable AX value or label."
        )
        attachWindowScreenshot(application, named: "SF-AUTHORING-111 component import preflight")
        application.buttons["clipboard.component.cancel"].click()
        XCTAssertTrue(waitForNonexistence(preflight))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))

        application.typeKey("v", modifierFlags: .command)
        XCTAssertTrue(preflight.waitForExistence(timeout: 5))
        application.buttons["clipboard.component.confirm"].click()
        XCTAssertTrue(waitForNonexistence(preflight))
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        XCTAssertTrue(waitForValue(application.descendants(matching: .any)["status.clipboard"],
                                   containing: "Imported component dependencies"))
        let overflow = application.descendants(matching: .any)["navigator.tab.overflow"]
        if overflow.exists && overflow.isHittable {
            overflow.click(); application.menuItems["Components"].click()
        } else { selectShellTab("Components", directIdentifier: "navigator.tab.components", overflowIdentifier: "navigator.tab.overflow", in: application) }
        XCTAssertTrue(application.descendants(matching: .any).matching(NSPredicate(
            format: "identifier BEGINSWITH %@", "components.definition."
        )).firstMatch.waitForExistence(timeout: 3))
        attachWindowScreenshot(application, named: "SF-AUTHORING-111 imported component selected")
        application.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 0", timeout: 5))
        application.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
    }

    // SF-0409-001...008
    @MainActor
    func testCanvasIsolationFocusAndPresentationJourney() throws {
        let application = launchWorkspace()
        XCTAssertTrue(waitForWorkspaceReady(application))
        selectShellTab("Elements", directIdentifier: "navigator.tab.elements", overflowIdentifier: "navigator.tab.overflow", in: application)
        application.buttons["navigator.elements.section"].click()
        XCTAssertTrue(waitForLiveCanvasValue(in: application, containing: "rendered objects 1", timeout: 5))
        application.menuBars.menuBarItems["Selection"].click()
        let isolate = application.menuItems["Isolate Selection"]
        XCTAssertTrue(isolate.isEnabled); isolate.click()
        XCTAssertTrue(application.descendants(matching: .any)["canvas.isolation.breadcrumb"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["canvas.isolation.exit"].isHittable)
        attachWindowScreenshot(application, named: "SF-AUTHORING-108 isolated canvas")

        componentMenu("Preview", "Toggle Focus Mode", in: application)
        XCTAssertFalse(application.descendants(matching: .any)["shell.navigator"].exists)
        XCTAssertFalse(application.descendants(matching: .any)["shell.inspector"].exists)
        attachWindowScreenshot(application, named: "SF-AUTHORING-108 focus mode")
        componentMenu("Preview", "Toggle Focus Mode", in: application)
        XCTAssertTrue(application.descendants(matching: .any)["shell.navigator"].waitForExistence(timeout: 5))
        application.buttons["canvas.isolation.exit"].click()
        XCTAssertFalse(application.descendants(matching: .any)["canvas.isolation.breadcrumb"].exists)
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
            let navigatorTabs = ["pages", "layers", "elements", "assets", "components"].compactMap { name -> XCUIElement? in
                let element = application.buttons["navigator.tab.\(name)"]
                return element.exists ? element : nil
            }
            XCTAssertGreaterThanOrEqual(navigatorTabs.count, 2)
            XCTAssertLessThanOrEqual((navigatorTabs.map(\.frame.midY).max() ?? 0) -
                                     (navigatorTabs.map(\.frame.midY).min() ?? 0), 1,
                                     "Navigator destinations must remain on one visual row")
            let inspectorTabs = ["design", "layout", "content", "interactions", "accessibility"].compactMap { name -> XCUIElement? in
                let element = application.buttons["inspector.tab.\(name)"]
                return element.exists ? element : nil
            }
            XCTAssertGreaterThanOrEqual(inspectorTabs.count, 2)
            XCTAssertLessThanOrEqual((inspectorTabs.map(\.frame.midY).max() ?? 0) -
                                     (inspectorTabs.map(\.frame.midY).min() ?? 0), 1,
                                     "Inspector destinations must remain on one visual row")
            for identifier in ["canvas.viewport.preset", "canvas.grid.toggle", "canvas.zoom.out",
                               "canvas.zoom.in", "canvas.zoom.reset", "canvas.zoom.fitCanvas", "canvas.zoom.fit"] {
                XCTAssertTrue(application.descendants(matching: .any)[identifier].exists,
                              "Persistent viewport control missing: \(identifier)")
            }
            application.typeKey("\t", modifierFlags: [])
            XCTAssertTrue(application.descendants(matching: .any)["workspace.shell"].exists)
            attachWindowScreenshot(application, named: "workspace-\(name)")
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

    // SF-1208-002/004/006, SF-1211-002/004/006 — source journey; runtime
    // execution remains deferred under the owner-directed testing pause.
    @MainActor
    func testStaticBuildDiagnosticsPreflightProfileCancelAndAccessibilityJourney() throws {
        let application = launchScenario("workspace")
        application.menuBars.menuBarItems["Build"].click()
        let diagnostics = application.menuItems["Build Diagnostics…"]
        XCTAssertTrue(diagnostics.isEnabled)
        diagnostics.click()

        let sheet = application.descendants(matching: .any)["build.diagnostics"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        let profile = application.popUpButtons["Build profile"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5), application.debugDescription)
        XCTAssertTrue(application.buttons["build.preflight"].isEnabled)
        XCTAssertTrue(application.descendants(matching: .any)["build.status"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["build.copySummary"].waitForExistence(timeout: 5))
        XCTAssertTrue(application.buttons["build.write"].exists)
        XCTAssertFalse(application.buttons["build.cancel"].isEnabled)
        attachWindowScreenshot(application, named: "SF-AUTHORING-110 build diagnostics preflight")
    }

    // Opt-in owner authoring acceptance: all mutations and output use visible
    // shipping controls. The owner package is never synthesized by this driver.
    private func reviewOwnerDarkFlow(in application: XCUIApplication, project: URL, output: URL) throws {
        selectNavigatorTab("Pages", identifier: "pages", in: application)
        let names = ["Home", "Journal", "About", "Contact", "Not Found"]
        let pageIDs = names.map { pageRow(named: $0, in: application).identifier }
        pageRow(named: "Home", in: application).click()
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        selectStructuralLayer("Section", in: application)
        let section = application.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND label == %@", "navigator.layer.", "Section")).firstMatch.identifier
        selectInspectorTab("Layout", identifier: "layout", in: application)
        application.popUpButtons["canvas.viewport.preset"].click(); application.menuItems["Desktop"].click()
        let padding = application.textFields["inspector.layout.container.padding"]
        func assertPadding(_ expected: String) {
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let live = application.textFields["inspector.layout.container.padding"]
                guard live.exists, let value = live.value as? String else { return false }
                return value.components(separatedBy: ";").first?.trimmingCharacters(in: .whitespaces) == expected
            }, object: nil)], timeout: 5), .completed)
        }
        assertPadding("48")
        XCTAssertTrue((padding.value as? String)?.contains("authored; Desktop base") == true)
        replaceStructuralLayoutField(padding, with: "49", in: application)
        assertPadding("49")
        // Return commits the property but intentionally leaves native text
        // editing active. End that responder session before document Undo.
        padding.typeKey(.escape, modifierFlags: [])
        assertPadding("49")
        XCTAssertNotEqual(application.buttons["toolbar.undo"].value as? String, "Text editing")
        application.buttons["toolbar.undo"].click(); assertPadding("48")
        application.buttons["toolbar.redo"].click(); assertPadding("49")
        attachWindowScreenshot(application, named: "Dark Flow real document Undo Redo with stable selection")
        application.buttons["toolbar.undo"].click(); assertPadding("48")
        XCTAssertTrue(application.buttons[section].isSelected)
        saveDocumentIfModified(in: application)
        selectInspectorTab("Design", identifier: "design", in: application)
        let angles = application.textFields.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "inspector.design.layers.", ".angle"))
        XCTAssertEqual(angles.count, 1)
        let angleID = angles.firstMatch.identifier
        application.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForNonexistence(application.descendants(matching: .any)["workspace.shell"]))
        openProjectThroughNativePanel(project, in: application)
        XCTAssertTrue(waitForWorkspaceReady(application)); assertNormalWindowPolicy(in: application)
        selectNavigatorTab("Pages", identifier: "pages", in: application)
        XCTAssertEqual(names.map { pageRow(named: $0, in: application).identifier }, pageIDs)
        pageRow(named: "Home", in: application).click()
        selectNavigatorTab("Layers", identifier: "layers", in: application)
        selectStructuralLayer("Section", in: application)
        XCTAssertTrue(application.buttons[section].isSelected)
        selectInspectorTab("Design", identifier: "design", in: application)
        XCTAssertTrue(application.textFields[angleID].exists)
        XCTAssertEqual(application.textFields[angleID].value as? String, "45")
        let prefix = angleID.replacingOccurrences(of: ".angle", with: ".stop.")
        let positions = application.textFields.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", prefix, ".position"))
        XCTAssertEqual(positions.allElementsBoundByIndex.map { $0.value as? String }, ["0", "50", "100"])
        let wells = application.colorWells.matching(NSPredicate(format:
            "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", prefix, ".color"))
        XCTAssertEqual(wells.allElementsBoundByIndex.map { $0.value as? String }, ["#160D2BFF", "#6A36C8FF", "#C52E53FF"])
        _ = revealStructuralLayoutControl(positions.element(boundBy: 2), in: application)
        attachWindowScreenshot(application, named: "Dark Flow reopened editable three-stop native gradient")
        application.buttons["toolbar.preview"].click()
        let link = application.staticTexts["preview.website.url"]
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        let url = try XCTUnwrap(URL(string: (link.value as? String) ?? link.label))
        XCTAssertEqual(url.host, "127.0.0.1")
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            safari.state == .runningForeground
        }, object: nil)], timeout: 10), .completed)
        let editorial = safari.webViews.descendants(matching: .any).matching(NSPredicate(format:
            "label == %@ OR title == %@", "Ideas worth following.", "Ideas worth following.")).firstMatch
        XCTAssertTrue(editorial.waitForExistence(timeout: 10))
        let previewCapture = XCTAttachment(screenshot: safari.windows.firstMatch.screenshot())
        previewCapture.name = "Dark Flow actual shared-compiler Safari preview"; previewCapture.lifetime = .keepAlways; add(previewCapture)
        safari.typeKey("w", modifierFlags: .command) // Only this verified preview tab.
        application.activate()
        try exportOwnerDarkFlow(in: application, output: output, previewAlreadyOpen: true)
        safari.activate()
        // Closing the verified preview can close Safari's last window. New
        // Tab is unavailable without a window; use the native New Window action.
        safari.typeKey(safari.windows.count == 0 ? "n" : "t", modifierFlags: .command)
        XCTAssertTrue(safari.windows.firstMatch.waitForExistence(timeout: 5))
        safari.typeKey("l", modifierFlags: .command)
        safari.typeText(output.appendingPathComponent("index.html").absoluteString)
        safari.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(editorial.waitForExistence(timeout: 10))
        let exportCapture = XCTAttachment(screenshot: safari.windows.firstMatch.screenshot())
        exportCapture.name = "Dark Flow actual exported website in Safari"; exportCapture.lifetime = .keepAlways; add(exportCapture)
        application.activate(); application.typeKey("q", modifierFlags: .command)
    }

    @MainActor
    private func reviewOwnerDarkFlowMobilePreview(in application: XCUIApplication) throws {
        application.buttons["toolbar.preview"].click()
        XCTAssertTrue(application.staticTexts["preview.website.url"].waitForExistence(timeout: 10))
        let safari = XCUIApplication(bundleIdentifier: "com.apple.Safari")
        safari.activate()
        safari.menuBars.menuBarItems["Develop"].click()
        let enter = safari.menuItems["Enter Responsive Design Mode"]
        if enter.exists { enter.click() } else { safari.typeKey(.escape, modifierFlags: []) }
        let width = safari.textFields.matching(NSPredicate(format: "label == %@ OR title == %@", "Width", "Width")).firstMatch
        XCTAssertTrue(width.waitForExistence(timeout: 5), safari.debugDescription)
        width.click(); width.typeKey("a", modifierFlags: .command); width.typeText("320")
        width.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(width.value as? String, "320")
        let summary = safari.webViews.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Header navigation menu")).firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5), safari.debugDescription)
        func expanded(_ expected: Bool) -> Bool {
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                guard summary.exists else { return false }
                if let number = summary.value as? NSNumber { return number.boolValue == expected }
                let value = (summary.value as? String)?.lowercased()
                return expected ? ["1", "true", "on", "expanded"].contains(value ?? "")
                    : ["0", "false", "off", "collapsed"].contains(value ?? "")
            }, object: nil)], timeout: 5) == .completed
        }
        summary.click(); XCTAssertTrue(expanded(true))
        let capture = XCTAttachment(screenshot: safari.windows.firstMatch.screenshot())
        capture.name = "Dark Flow actual loopback 320 intrinsic menu open"; capture.lifetime = .keepAlways; add(capture)
        safari.typeKey(.escape, modifierFlags: []); XCTAssertTrue(expanded(false))
        safari.typeKey(.return, modifierFlags: []); XCTAssertTrue(expanded(true))
        let contact = safari.webViews.links["Contact"].firstMatch
        XCTAssertTrue(contact.exists); contact.click()
        XCTAssertTrue(safari.webViews.staticTexts["Let’s talk ideas."].waitForExistence(timeout: 5))
        let destination = XCTAttachment(screenshot: safari.windows.firstMatch.screenshot())
        destination.name = "Dark Flow actual loopback 320 Contact destination"; destination.lifetime = .keepAlways; add(destination)
    }

    @MainActor
    private func exportOwnerDarkFlow(in application: XCUIApplication, output: URL, previewAlreadyOpen: Bool = false) throws {
        if !previewAlreadyOpen {
            application.buttons["toolbar.preview"].click()
            XCTAssertTrue(application.staticTexts["preview.website.url"].waitForExistence(timeout: 10))
        }
        func chooseExportName(_ name: String) {
            application.buttons["Export…"].click()
            let field = application.textFields["saveAsNameTextField"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            replaceText(in: field, with: name, application: application)
            application.typeKey("g", modifierFlags: [.command, .shift])
            let folder = application.textFields["PathTextField"]
            XCTAssertTrue(folder.waitForExistence(timeout: 5))
            replaceText(in: folder, with: output.deletingLastPathComponent().path, application: application)
            folder.typeKey(.return, modifierFlags: [])
        }
        chooseExportName(output.lastPathComponent + " cancelled")
        application.windows["save-panel"].buttons["CancelButton"].click()
        chooseExportName(output.lastPathComponent)
        application.windows["save-panel"].buttons["OKButton"].click()
        XCTAssertTrue(waitForLiveValue(in: application, identifier: "preview.website.status", containing: "Exported"))
        attachWindowScreenshot(application, named: "Dark Flow native website export after cancel and retry")
        application.buttons["Stop"].click(); application.buttons["preview.website.done"].click()
        XCTAssertTrue(waitForLiveDocumentStatus(in: application, containing: "Saved", timeout: 5))
    }
}
