import AppKit
import ImageIO
import XCTest
import SwiftUI
@testable import SiteForge

@MainActor
final class CanvasTextRenderingTests: XCTestCase {

    // SF-0806-006, SF-1203-006: exercise the real SwiftUI/AppKit sizing
    // boundary at Header's 24-point row, not only a standalone 32-point popup.
    func testNativePreviewMenuFitsActualHeaderAndFooterHostingBounds() async throws {
        let page = PageID()
        var navigation = PageNavigationSnapshot(ownerID: NodeID(), links: [
            .init(id: NodeID(), pageID: page, label: "Home", isAvailable: true)],
            hamburgerEnabled: true, usesHamburger: true, alignment: "start", padding: 0,
            currentPageID: page)
        for height in [24.0, 32.0] {
            for width in [90.0, 110.0, 160.0] {
            navigation.rowHeight = height
            let host = NSHostingView(rootView: NativePageNavigationPreview(navigation: navigation, availableWidth: width, onFollow: { _ in })
                .frame(width: width, height: height))
            let window = NSWindow(contentRect: .init(x: 100, y: 100, width: width, height: height),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.orderOut(nil); window.close() }
            window.contentView = host
            window.orderFront(nil)
            await Task.yield()
            host.layoutSubtreeIfNeeded()
            @MainActor func popup(_ view: NSView) -> NativePreviewNavigationButton? {
                if let button = view as? NativePreviewNavigationButton { return button }
                return view.subviews.lazy.compactMap(popup).first
            }
            let button = try XCTUnwrap(popup(host))
            let presented = host.convert(button.bounds, from: button)
            let receipt = XCTAttachment(string: "row=\(height);host=\(host.bounds);control=\(presented);alignmentInsets=\(button.alignmentRectInsets);visible=\(button.visibleRect)")
            receipt.name = "SF-NARROW real representable control layout"; receipt.lifetime = .keepAlways; add(receipt)
            let tolerance = 1 / (window.backingScaleFactor)
            XCTAssertTrue(host.bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(presented),
                "The real native popup must fit its Header/Footer allocation without clipped interactive bounds")
            XCTAssertEqual(presented.width, width, accuracy: tolerance)
            XCTAssertEqual(presented.midX, host.bounds.midX, accuracy: tolerance,
                "The popup must not be capped/right-shifted inside a wider resolved navigation frame")
            XCTAssertEqual(presented.midY, host.bounds.midY, accuracy: tolerance)
            }
        }
    }

    // SF-0806-006, SF-1203-003/006: focus belongs to the real popup, not a
    // separate ring proxy. Native item dispatch retains immutable identities.
    func testNativePreviewNavigationOwnsFirstResponderAndRejectsStaleMenuItems() throws {
        let parent = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 800, height: 600),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 420),
            styleMask: [.titled], backing: .buffered, defer: false)
        for window in [parent, sheet] { window.isReleasedWhenClosed = false; window.animationBehavior = .none }
        defer { parent.endSheet(sheet); sheet.orderOut(nil); sheet.close(); parent.close() }
        let home = PageID(), about = PageID(), missing = PageID(), owner = NodeID()
        var snapshot = PageNavigationSnapshot(ownerID: owner, links: [
            .init(id: NodeID(), pageID: home, label: "Home", isAvailable: true),
            .init(id: NodeID(), pageID: about, label: "About", isAvailable: true),
            .init(id: NodeID(), pageID: missing, label: "Missing", isAvailable: false)],
            hamburgerEnabled: true, usesHamburger: true, alignment: "start", padding: 0,
            currentPageID: home)
        let button = NativePreviewNavigationButton(frame: NSRect(x: 30, y: 180, width: 90, height: 32), pullsDown: true)
        var followed: [CanvasPreviewLink] = []
        button.configure(snapshot) { followed.append($0) }
        sheet.contentView?.addSubview(button)
        parent.makeKeyAndOrderFront(nil)
        parent.beginSheet(sheet, completionHandler: { _ in })
        XCTAssertTrue(button.acceptsFirstResponder)
        XCTAssertTrue(button.canBecomeKeyView)
        XCTAssertTrue(sheet.makeFirstResponder(button))
        XCTAssertTrue(sheet.firstResponder === button)
        let accessible = try XCTUnwrap(button.cell)
        XCTAssertEqual(accessible.accessibilityRole(), .menuButton)
        XCTAssertEqual(accessible.accessibilityIdentifier(), "preview.navigation.menu.\(owner)")
        XCTAssertEqual(accessible.accessibilityLabel(), "Page navigation menu")
        XCTAssertTrue(accessible.accessibilityFrame().contains(accessible.accessibilityActivationPoint()),
            "The native pointer activation point must lie inside its actual control frame")
        let center = sheet.convertPoint(toScreen: button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil))
        XCTAssertTrue(button.accessibilityHitTest(center) as AnyObject? === accessible)
        let originalPoint = accessible.accessibilityActivationPoint()
        button.setFrameOrigin(NSPoint(x: button.frame.minX + 20, y: button.frame.minY + 10))
        XCTAssertEqual(accessible.accessibilityActivationPoint(), NSPoint(x: originalPoint.x + 20, y: originalPoint.y + 10))
        XCTAssertTrue(accessible.accessibilityFrame().contains(accessible.accessibilityActivationPoint()))
        let initial = try XCTUnwrap(button.menu)
        XCTAssertEqual(initial.items.map(\.title), ["Menu", "Home", "About", "Missing"])
        XCTAssertEqual(initial.item(at: 1)?.state, .on)
        XCTAssertFalse(try XCTUnwrap(initial.item(at: 3)).isEnabled)
        initial.performActionForItem(at: 2)
        XCTAssertEqual(followed.map(\.target), [.page(about)])
        initial.performActionForItem(at: 3)
        XCTAssertEqual(followed.count, 1)
        snapshot.currentPageID = about
        button.configure(snapshot) { followed.append($0) }
        initial.performActionForItem(at: 2)
        XCTAssertEqual(followed.count, 1, "A retained item from an old menu cannot navigate a replacement snapshot")
        let current = try XCTUnwrap(button.menu)
        XCTAssertEqual(current.item(at: 2)?.state, .on)
        button.menuWillOpen(current)
        snapshot.currentPageID = home
        button.configure(snapshot) { followed.append($0) }
        XCTAssertTrue(button.menu === current, "An open native menu is not rebuilt during tracking")
        current.performActionForItem(at: 1)
        XCTAssertEqual(followed.count, 1, "A superseded tracking snapshot cannot dispatch")
        button.menuDidClose(current)
        let replacement = try XCTUnwrap(button.menu)
        XCTAssertFalse(replacement === current)
        XCTAssertEqual(replacement.item(at: 1)?.state, .on)
        button.detach()
        replacement.performActionForItem(at: 1)
        XCTAssertEqual(followed.count, 1)
        XCTAssertFalse(button.acceptsFirstResponder)
        XCTAssertFalse(button.canBecomeKeyView)
    }

    // SF-0407-003: retained canvas actions cannot bypass document modality.
    func testNativeCanvasAccessibilityModalOwnershipRejectsRetainedActionsAndRestoresAfterDismissal() async throws {
        let parent = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 500, height: 400),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let other = NSWindow(contentRect: NSRect(x: 650, y: 100, width: 300, height: 300),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 250, height: 150),
                             styleMask: [.titled], backing: .buffered, defer: false)
        for window in [parent, other, sheet] {
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
        }
        defer {
            if parent.attachedSheet != nil { parent.endSheet(sheet) }
            sheet.orderOut(nil)
            sheet.close(); other.close(); parent.close()
        }
        let canvas = NativeCanvasViewportView(frame: parent.contentView!.bounds)
        let otherCanvas = NativeCanvasViewportView(frame: other.contentView!.bounds)
        parent.contentView = canvas
        other.contentView = otherCanvas
        var insertionCount = 0
        canvas.onInsertFrame = { insertionCount += 1; return true }
        parent.makeKeyAndOrderFront(nil)
        XCTAssertTrue(canvas.isAccessibilityElement())
        let originalChildCount = canvas.accessibilityChildren()?.count
        let retainedAction = try XCTUnwrap(canvas.accessibilityCustomActions()?.first {
            $0.name == "Insert Frame at Center"
        })
        parent.beginSheet(sheet, completionHandler: { _ in })
        XCTAssertNotNil(parent.attachedSheet)
        XCTAssertFalse(canvas.isAccessibilityElement())
        XCTAssertEqual(canvas.accessibilityChildren()?.count, 0)
        XCTAssertEqual(canvas.accessibilityCustomActions()?.count, 0)
        let canvasCenter = parent.convertPoint(toScreen: NSPoint(x: 250, y: 200))
        XCTAssertNil(canvas.accessibilityHitTest(canvasCenter))
        XCTAssertFalse(try XCTUnwrap(retainedAction.handler)())
        XCTAssertEqual(insertionCount, 0)
        XCTAssertTrue(otherCanvas.isAccessibilityElement())
        XCTAssertFalse(otherCanvas.accessibilityCustomActions()?.isEmpty ?? true)
        parent.endSheet(sheet)
        sheet.orderOut(nil)
        for _ in 0..<100 where parent.attachedSheet != nil { await Task.yield() }
        XCTAssertNil(parent.attachedSheet)
        XCTAssertTrue(canvas.isAccessibilityElement())
        XCTAssertEqual(canvas.accessibilityChildren()?.count, originalChildCount)
        XCTAssertTrue(try XCTUnwrap(retainedAction.handler)())
        XCTAssertEqual(insertionCount, 1)
    }

    // SF-0508-003/006, SF-0407-003: a structural page background is real
    // authored paint without becoming an authored object, hit target or ghost.
    func testStructuralPageBackgroundPaintsExactPixelsWithoutCanvasObject() async throws {
        let original = ProjectCreation.blank()
        var document = original
        let rootID = document.pages[0].rootNodeIDs[0]
        let color = CanonicalSolidColor(red: 34.0 / 255, green: 51.0 / 255, blue: 68.0 / 255, alpha: 1)
        document.pages[0].nodes[0].properties += CanonicalFillLayerCodec.propertyValues(for: [.solid(color: color)]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored)
        }
        try document.validate()
        let previewWorker = LocalPreviewRuntimeCompiler()
        let unpaintedPreview = try await previewWorker.compile(document: original, imageResourceData: [:], pixelRatio: .init(1))
        let paintedPreview = try await previewWorker.compile(document: document, imageResourceData: [:], pixelRatio: .init(1))
        XCTAssertNotEqual(unpaintedPreview.deterministicDigest, paintedPreview.deterministicDigest)
        XCTAssertEqual(paintedPreview.pages.first?.pageBackground?.id, rootID)
        XCTAssertTrue(paintedPreview.pages.first?.objects.isEmpty == true)
        let worker = WorkspaceScenePreparationWorker(), core = CanvasRendererCore()
        for scale in [1.0, 2.0] {
            let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0),
                viewportSize: .init(width: 300, height: 120),
                contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 200, height: 80)),
                pixelRatio: CanvasPixelRatio(scale))
            let request = WorkspaceScenePreparationRequest(document: document,
                activePageID: document.pages[0].id, activeContainerID: nil, viewport: viewport, surfaceID: .init())
            let prepared = try await worker.prepare(request)
            let plan = try core.prepare(scene: prepared.renderScene, overlays: prepared.overlays, viewport: viewport)
            let background = try XCTUnwrap(plan.pageBackground)
            XCTAssertEqual(background.id, rootID); XCTAssertEqual(background.frame, viewport.contentBounds)
            XCTAssertTrue(plan.authoredObjects.isEmpty); XCTAssertTrue(plan.accessibilityElements.isEmpty)
            XCTAssertNil(core.hitTest(.init(x: 80, y: 40), in: plan))
            XCTAssertTrue(plan.tiles.contains { $0.objectIDs.contains(rootID) })
            let bytes = rasterizedBytes(object: background, viewport: viewport, backingScale: scale)
            let inside = rgba(at: (Int(80 * scale), Int(40 * scale)), in: bytes,
                              width: Int(300 * scale), height: Int(120 * scale))
            XCTAssertEqual(Double(inside.red), 34, accuracy: 2)
            XCTAssertEqual(Double(inside.green), 51, accuracy: 2)
            XCTAssertEqual(Double(inside.blue), 68, accuracy: 2)
            XCTAssertEqual(inside.alpha, 255)
            XCTAssertEqual(rgba(at: (Int(250 * scale), Int(100 * scale)), in: bytes,
                               width: Int(300 * scale), height: Int(120 * scale)).alpha, 0)
            let cleared = try await worker.prepare(.init(document: original, activePageID: original.pages[0].id,
                activeContainerID: nil, viewport: viewport, surfaceID: request.surfaceID))
            let clearedPlan = try core.prepare(scene: cleared.renderScene, overlays: cleared.overlays,
                viewport: viewport, previous: prepared.renderScene)
            XCTAssertNil(clearedPlan.pageBackground); XCTAssertTrue(clearedPlan.authoredObjects.isEmpty)
            XCTAssertNotEqual(clearedPlan.invalidation, .compositorOnly)
            XCTAssertFalse(clearedPlan.dirtyWorldRegions.isEmpty)
        }
        XCTAssertNil(document.pages[0].nodes[0].insertionGeometry)
    }

    private func fontPairParagraphDocument() throws -> (CanonicalDocument, NodeID) {
        var document = ProjectCreation.blank()
        let root = document.pages[0].rootNodeIDs[0]
        let text = DocumentNode(kind: .text, name: "Heading paragraph", parent: .node(root), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(40)),
            .init(key: .init(rawValue: "layout.y"), value: .number(40)),
            .init(key: .init(rawValue: "layout.width"), value: .number(320)),
            .init(key: .init(rawValue: "layout.height"), value: .number(140)),
            .init(key: .init(rawValue: "content.text"), value: .string("A meaningful heading\nA second line wraps within the same authored column.")),
            .init(key: .init(rawValue: CanonicalSemanticElement.key), value: .string("h2")),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "family"), value: .string("Missing SiteForge Pair Fixture")),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "weight"), value: .string("medium")),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "size"), value: .number(18)),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "lineHeight"), value: .number(26)),
            .init(key: .init(rawValue: CanonicalTypography.namespace + "tracking"), value: .number(0.5))])
        document.pages[0].nodes[0].childIDs = [text.id]
        document.pages[0].nodes.append(text)
        try document.validate()
        return (document, text.id)
    }

    // SF-0406-005/006, SF-0507-003/005: the paired edit changes
    // only font intent; shared renderer/editor/output keep paragraph metrics.
    func testChosenFontPairSharesRendererInlineAndCompilerParagraphMetrics() async throws {
        let (document, textID) = try fontPairParagraphDocument()
        let session = DocumentSession(document: document)
        let state = WorkspaceShellState(documentSession: session)
        let live = state.documentSession
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        func adopt() async {
            let deadline = ContinuousClock.now + .seconds(3)
            while (state.canvasRenderPlan?.identity.revision != live.document.revision
                || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation), ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertEqual(state.canvasRenderPlan?.identity.revision, live.document.revision)
        }
        await adopt(); state.selectLayer(textID)
        XCTAssertTrue(state.typographyRoleSummary.contains("Heading 2"))
        XCTAssertTrue(state.commitTypography(.fontFace(family: "System", weight: .semibold),
            operation: "font family and weight", provenance: .picker, expectedContext: state.responsiveInspectorEditContext))
        await adopt()
        let object = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == textID })
        let typography = try XCTUnwrap(object.typography)
        XCTAssertEqual(typography.authoredFamily, "System"); XCTAssertEqual(typography.weight, "semibold")
        XCTAssertEqual(typography.size, 18); XCTAssertEqual(typography.lineHeight, 26); XCTAssertEqual(typography.tracking, 0.5)
        XCTAssertFalse(typography.usesFallback)
        XCTAssertEqual(object.frame, document.pages[0].nodes[1].insertionGeometry?.frame)
        for zoom in [0.25, 1.0, 8.0] {
            for backing in [1.0, 2.0] {
                let rect = CGRect(x: -40 * zoom, y: 30 * zoom, width: 320 * zoom, height: 140 * zoom)
                let layout = CanvasTextLayout(viewportObjectRect: rect, zoom: zoom,
                    text: object.plainText ?? "", typography: typography)
                let editor = InlineCanvasTextView()
                editor.frame = rect
                editor.string = object.plainText ?? ""
                let caret = NSRange(location: 2, length: 3)
                editor.setSelectedRange(caret)
                editor.applyCanvasTextLayout(layout)
                XCTAssertEqual(editor.string, object.plainText)
                XCTAssertEqual(editor.selectedRange(), caret)
                XCTAssertEqual(editor.frame, rect)
                XCTAssertEqual(editor.font?.fontName, layout.font.fontName)
                XCTAssertEqual(editor.textContainerInset, layout.textContainerInset)
                XCTAssertEqual(editor.typingAttributes[.kern] as? CGFloat, layout.tracking)
                let layer = try XCTUnwrap(CanvasAuthoredTextLayerFactory.makeLayer(for: object,
                    viewportObjectRect: rect, zoom: zoom, contentsScale: backing))
                XCTAssertEqual(layer.fontSize, layout.fontSize)
                XCTAssertEqual(layer.frame.minY, layout.glyphBounds.minY, accuracy: 1 / backing)
                XCTAssertEqual(layer.frame.width, layout.glyphBounds.width, accuracy: 1 / backing)
                XCTAssertEqual(layer.borderWidth, 0); XCTAssertNil(layer.backgroundColor)
            }
        }
        let authored = live.document
        let plan = try MultiPageStaticBuildPlanner.plan(document: authored)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("font-family: system-ui;")); XCTAssertTrue(css.contains("font-weight: 600;"))
        XCTAssertTrue(css.contains("line-height: 26.0px;")); XCTAssertTrue(css.contains("letter-spacing: 0.5px;"))
        XCTAssertTrue(css.contains("white-space: pre-wrap;")); XCTAssertFalse(css.contains("@font-face"))
        XCTAssertTrue(plan.files.contains { $0.path == "index.html" && $0.contents.contains("<h2") })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(authored)), authored)
        try live.undo(); XCTAssertEqual(live.document.pages, document.pages)
        try live.redo(); XCTAssertEqual(live.document.pages, authored.pages)
    }

    // SF-0507-004/005, SF-0805-003/004: a retained chooser cannot
    // overwrite a later context; missing font intent and no-op history survive.
    func testFontChooserCapturedContextPreservesMissingIntentAndNoOpHistory() async throws {
        let (document, textID) = try fontPairParagraphDocument()
        let session = DocumentSession(document: document)
        let state = WorkspaceShellState(documentSession: session)
        let live = state.documentSession
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        func adopt() async {
            let deadline = ContinuousClock.now + .seconds(3)
            while (state.canvasRenderPlan?.identity.revision != live.document.revision
                || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation), ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertEqual(state.canvasRenderPlan?.identity.revision, live.document.revision)
        }
        await adopt(); state.selectLayer(textID)
        XCTAssertTrue(state.canvasRenderPlan?.authoredObjects.first { $0.id == textID }?.typography?.usesFallback == true)
        let count = live.historySnapshot().undoEntries.count
        XCTAssertTrue(state.commitTypography(.fontFace(family: "Missing SiteForge Pair Fixture", weight: .medium),
            operation: "unchanged font pair", expectedContext: state.responsiveInspectorEditContext))
        XCTAssertEqual(live.historySnapshot().undoEntries.count, count)
        XCTAssertEqual(live.document, document)
        let opening = state.responsiveInspectorEditContext
        state.reviewBreakpoint(.mobile); await adopt()
        XCTAssertFalse(state.commitTypography(.fontFace(family: "System", weight: .bold),
            operation: "old font chooser", expectedContext: opening))
        XCTAssertEqual(live.document, document)
        XCTAssertTrue(state.typographyResolutionStatus?.contains("preserved") == true)
        XCTAssertEqual(session.document, document)
    }

    func testTypographyScopeGuardPreservesMissingFamilyFluidSizingAndExactHistory() async throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id, root = document.pages[0].rootNodeIDs[0]
        let fluid = CanonicalFluidValue(minimum: 16, preferred: 20, maximum: 30)
        let text = DocumentNode(kind: .text, name: "Workflow text", parent: .node(root), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(40)), .init(key: .init(rawValue: "layout.y"), value: .number(40)),
            .init(key: .init(rawValue: "layout.width"), value: .number(320)), .init(key: .init(rawValue: "layout.height"), value: .number(80)),
            .init(key: .init(rawValue: "content.text"), value: .string("Typography intent remains stable.")),
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.fontSize)), value: .string(try CanonicalFluidValueCodec.encode(fluid, target: .fontSize)))])
        document.pages[0].nodes[0].childIDs = [text.id]; document.pages[0].nodes.append(text)
        let fixture = try ApplicationOwnedTestFixture.create("typography-workflow")
        defer { try? fixture.cleanup() }
        let session = DocumentSession(document: document)
        let lifecycle = DocumentLifecycleController(session: session, recoveryDirectory: fixture.url.appendingPathComponent("recovery"))
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        func ready() async {
            let deadline = ContinuousClock.now + .seconds(3)
            while state.canvasRenderPlan?.identity.revision != session.document.revision
                || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation {
                if ContinuousClock.now >= deadline { break }; await Task.yield()
            }
            XCTAssertEqual(state.canvasRenderPlan?.identity.revision, session.document.revision)
        }
        await ready(); state.selectLayer(text.id)
        let scope = state.layoutInspectorDraftScope, missing = "Missing SiteForge Workflow Family"
        XCTAssertTrue(state.commitTypography(.family(missing), operation: "family", draftScope: scope))
        await ready()
        XCTAssertTrue(state.typographyResolutionStatus?.contains("preserved") == true)
        let authored = session.document
        XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: authored.pages[0].nodes[1])?.family, missing)
        state.reviewBreakpoint(.mobile); await ready()
        XCTAssertFalse(state.commitTypography(.size(99), operation: "size", draftScope: scope))
        XCTAssertEqual(session.document, authored)
        XCTAssertTrue(state.commitTypography(.size(22), operation: "size", draftScope: state.layoutInspectorDraftScope))
        await ready()
        let current = session.document
        XCTAssertEqual(current.pages[0].nodes[1].insertionProperty(CanonicalFluidValueCodec.key(.fontSize)), text.insertionProperty(CanonicalFluidValueCodec.key(.fontSize)))
        XCTAssertEqual(state.canvasRenderPlan?.authoredObjects.first { $0.id == text.id }?.typography?.size, 16)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(current)), current)
        try session.undo(); XCTAssertEqual(session.document.pages, authored.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, current.pages)
        let output = try MultiPageStaticBuildPlanner.plan(document: current)
        XCTAssertTrue(output.files.contains { $0.contents.contains(missing) })
        XCTAssertEqual(current.pages[0].nodes[1].id, text.id)
        XCTAssertEqual(current.pages[0].nodes[1].insertionGeometry, text.insertionGeometry)
    }
    func testInstalledFontCatalogOffersOnlyDiscoveredWeightsAndPreservesMissingIntent() async throws {
        let families = await Task.detached(priority: .utility) { InstalledTypographyCatalog.load() }.value
        XCTAssertTrue(families.contains { $0.name == "System" && $0.weights == CanonicalFontWeight.allCases })
        XCTAssertEqual(Set(families.map(\.name)).count, families.count)
        XCTAssertFalse(families.contains { $0.name.hasPrefix(".") })
        XCTAssertEqual(InstalledTypographyCatalog.namedWeight(for: 0), .regular)
        XCTAssertEqual(InstalledTypographyCatalog.namedWeight(for: 0.4), .bold)
        XCTAssertNil(InstalledTypographyCatalog.namedWeight(for: -0.8))
        XCTAssertNil(InstalledTypographyCatalog.namedWeight(for: .nan))
        XCTAssertTrue(InstalledTypographyCatalog.matching(" sYsTeM ", in: families).contains { $0.name == "System" })
        let authored = "Missing SiteForge Workflow Family"
        let resolved = ResponsiveTextMetrics.font(family: authored, weight: "bold", size: 20)
        XCTAssertTrue(resolved.usesFallback)
        XCTAssertNotEqual(resolved.family, authored)
        let scope = LayoutInspectorDraftScope(documentID: DocumentID(), pageID: PageID(), sceneID: CanvasViewportSceneID(),
            orderedNodeIDs: [NodeID()], breakpoint: .desktop, viewportWidth: 1440)
        var draft = LayoutInspectorNumericDraft(text: authored, committed: "System", scope: scope)
        draft.adopt(committed: "System", scope: scope)
        XCTAssertEqual(draft.text, authored)
        XCTAssertTrue(draft.canCommit(in: scope))
        draft.adopt(committed: "Georgia", scope: scope)
        XCTAssertEqual(draft.conflict, .valueChanged)
        XCTAssertEqual(draft.text, authored)
    }
    func testIntrinsicSizingAndLiveCanvasUseSameFontAndWrappingBounds() throws {
        let text = "Thoughtful writing for a curious world.\nDesign, culture, and the places that shape us."
        for family in ["System", "Georgia", "Missing SiteForge Sizing Font"] {
            let typography = CanonicalTypography(family: family, weight: .semibold,
                size: 40, lineHeight: 48, tracking: 0, alignment: .leading)
            for width in [320.0, 375, 390, 430, 574, 768, 1024, 1440] {
                let height = ResponsiveTextMetrics.height(text: text, width: width, typography: typography)
                let resolved = ResponsiveTextMetrics.font(family: family, weight: "semibold", size: 40)
                let snapshot = CanvasTypography(authoredFamily: family, resolvedFamily: resolved.family,
                    weight: "semibold", size: 40, lineHeight: 48, tracking: 0, alignment: .leading,
                    usesFallback: resolved.usesFallback)
                XCTAssertEqual(resolved.usesFallback, family.hasPrefix("Missing"))
                for zoom in [0.25, 1, 8] {
                    let layout = CanvasTextLayout(viewportObjectRect: .init(x: 0, y: 0,
                        width: width * zoom, height: height * zoom), zoom: zoom, text: text, typography: snapshot)
                    let font = ResponsiveTextMetrics.font(family: family, weight: "semibold", size: 40 * zoom)
                    XCTAssertEqual(layout.font.fontName, font.postScriptName)
                    XCTAssertTrue(layout.isInsideObjectRect)
                    let measured = NSAttributedString(string: text, attributes: [.font: layout.font,
                        .kern: layout.tracking, .paragraphStyle: layout.paragraphStyle]).boundingRect(
                            with: .init(width: (width - 8) * zoom, height: .greatestFiniteMagnitude),
                            options: [.usesLineFragmentOrigin, .usesFontLeading])
                    XCTAssertLessThanOrEqual(measured.height, height * zoom + 1,
                        "Intrinsic height must contain native wrapping: family \(family), width \(width), zoom \(zoom)")
                }
            }
        }
    }

    func testFittedPreviewTextSharesCanvasMetricsWithoutNativeFontTruncationOrChrome() throws {
        @MainActor func assertSameRect(_ actual: CGRect, _ expected: CGRect) {
            // CALayer stores position/anchor separately: reconstructing a
            // frame may differ at floating-point epsilon, not a device pixel.
            XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.000_000_01)
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.000_000_01)
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.000_000_01)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.000_000_01)
        }
        let object = CanvasRenderObject(id: NodeID(),
            frame: .init(origin: .init(x: 48, y: 48), size: .init(width: 360, height: 24)),
            clipRect: nil, paintOrder: 0, style: .textPlaceholder, isVisible: true,
            accessibilityLabel: "Site title", plainText: "Installed Owner Site", opacity: 0.5)
        for zoom in [0.125, 0.25, 0.58, 1.0, 8.0] {
            let rect = CGRect(x: 0, y: 0, width: 360 * zoom, height: 24 * zoom)
            let layout = CanvasTextLayout(viewportObjectRect: rect, zoom: zoom,
                text: try XCTUnwrap(object.plainText), typography: object.typography)
            for backing in [1.0, 2.0] {
                let preview = try XCTUnwrap(CanvasAuthoredTextLayerFactory.makeLayer(for: object,
                    viewportObjectRect: rect, zoom: zoom, contentsScale: backing))
                assertSameRect(preview.frame, layout.glyphBounds)
                XCTAssertEqual(preview.fontSize, layout.fontSize)
                XCTAssertEqual(preview.contentsScale, backing)
                XCTAssertEqual(preview.opacity, 0.5)
                let string = try XCTUnwrap(preview.string as? NSAttributedString)
                XCTAssertEqual(string.string, object.plainText)
                XCTAssertEqual(string.attribute(.font, at: 0, effectiveRange: nil) as? NSFont, layout.font)
                XCTAssertTrue(layout.isInsideObjectRect)
                let pixels = rasterizedTextLayerBytes(preview,
                    width: Int(ceil(rect.width)), height: Int(ceil(rect.height)))
                XCTAssertTrue(pixels.contains { $0 != 0 }, "Fitting must not erase glyphs at \(zoom)×")
            }
            let view = CanvasPreviewTextView(frame: rect)
            view.configure(object: object, scale: zoom)
            view.layout()
            let layer = try XCTUnwrap(view.layer?.sublayers?.first as? CATextLayer)
            assertSameRect(layer.frame, layout.glyphBounds)
            XCTAssertEqual(layer.opacity, 1, "The enclosing authored group applies opacity exactly once")
            XCTAssertNil(layer.backgroundColor)
            XCTAssertEqual(layer.borderWidth, 0, "Preview must not fabricate a box around plain text")
            XCTAssertEqual(view.layer?.sublayers?.count, 1)
            XCTAssertNil(view.hitTest(.zero), "The real Preview link/button retains pointer ownership")
        }
        XCTAssertNil(CanvasAuthoredTextLayerFactory.makeLayer(for: object,
            viewportObjectRect: .zero, zoom: 1, contentsScale: 2))
        XCTAssertNil(CanvasAuthoredTextLayerFactory.makeLayer(for: object,
            viewportObjectRect: .init(x: 0, y: 0, width: 360, height: 24), zoom: .nan, contentsScale: 2))
    }

    func testTypographyRepeatedFocusReconciliationIsNeutralAndNotValidationFailure() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        @MainActor func waitForAdoption() async throws {
            let deadline = ContinuousClock.now + .seconds(3)
            while state.canvasRenderPlan?.identity.revision != session.document.revision, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(5))
            }
        }
        try await waitForAdoption()
        state.performDefaultInsertion(.text, provenance: .menu)
        try await waitForAdoption()
        XCTAssertNotNil(state.selectionState.primaryID)
        let before = session.document
        XCTAssertTrue(state.commitTypography(.weight(.bold), operation: "weight", provenance: .picker))
        try await waitForAdoption()
        let committed = session.document
        XCTAssertTrue(state.commitTypography(.weight(.bold), operation: "weight", provenance: .focusLoss))
        XCTAssertEqual(session.document, committed)
        XCTAssertEqual(state.lastDesignInspectorAnnouncement, "Typography unchanged")
        try session.undo()
        XCTAssertEqual(session.document.pages, before.pages, "A repeated focus commit must not add another undo entry")
    }

    func testDefaultWebsiteTextInkIgnoresEditorAppearanceAndMatchesInlineLayout() throws {
        let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 300, height: 120))
        let object = CanvasRenderObject(id: NodeID(),
            frame: .init(origin: .init(x: 20, y: 24), size: .init(width: 120, height: 24)),
            clipRect: nil, paintOrder: 0, style: .textPlaceholder, isVisible: true,
            accessibilityLabel: "Text", plainText: "About")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                let layer = CanvasAuthoredTextLayerFactory.makeLayer(for: object, viewport: viewport, contentsScale: 2)
                XCTAssertNotNil(layer)
                XCTAssertEqual(layer?.foregroundColor, NSColor.black.cgColor)
                let layout = CanvasTextLayout(viewportObjectRect: .init(x: 20, y: 24, width: 120, height: 24), zoom: 1, text: "About")
                let editor = InlineCanvasTextView()
                editor.string = "About"
                editor.applyCanvasTextLayout(layout)
                XCTAssertEqual(editor.textColor, NSColor.black)
                if let layer {
                    let pixels = rasterizedTextLayerBytes(layer, width: 300, height: 120)
                    XCTAssertTrue(pixels.contains { $0 != 0 }, "Logical frame equality must not hide absent glyphs")
                }
            }
        }
    }

    func testFrameImageFillPaintsInsideAuthoredBoundsAtNativeScale() throws {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(Array(repeating: [UInt8(255), 0, 0, 255], count: 4).flatMap { $0 }) as CFData))
        let redImage = try XCTUnwrap(CGImage(width: 2, height: 2,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, redImage, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let png = encoded as Data
        XCTAssertNotNil(NSImage(data: png))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true,
        ] as CFDictionary))
        for scale in [1.0, 2.0] {
            let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0),
                viewportSize: .init(width: 300, height: 120),
                contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
                pixelRatio: CanvasPixelRatio(scale))
            let object = CanvasRenderObject(id: NodeID(),
                frame: .init(origin: .init(x: 40, y: 30), size: .init(width: 160, height: 60)),
                clipRect: nil, paintOrder: 0, style: .frameSurface, isVisible: true,
                accessibilityLabel: "Frame with image fill", imageAssetID: AssetID(),
                imageData: png, imagePixelWidth: 2, imagePixelHeight: 2,
                imageFitMode: .fill)
            let pixels = rasterizedBytes(object: object, viewport: viewport)
            let inside = rgba(at: (x: 120, y: 60), in: pixels, width: 300, height: 120)
            XCTAssertGreaterThan(inside.red, 200)
            XCTAssertLessThan(inside.green, 40)
            XCTAssertLessThan(inside.blue, 40)
            XCTAssertEqual(inside.alpha, 255)
            let outside = rgba(at: (x: 4, y: 4), in: pixels, width: 300, height: 120)
            XCTAssertEqual(outside.alpha, 0)
            let translucent = CanvasRenderObject(id: object.id, frame: object.frame,
                clipRect: nil, paintOrder: 0, style: .frameSurface, isVisible: true,
                accessibilityLabel: object.accessibilityLabel, fillRGBA: [0, 0, 1, 1],
                opacity: 0.5, imageAssetID: object.imageAssetID, imageData: png,
                imagePixelWidth: 2, imagePixelHeight: 2, imageFitMode: .fill)
            let translucentInside = rgba(at: (x: 120, y: 60),
                in: rasterizedBytes(object: translucent, viewport: viewport), width: 300, height: 120)
            XCTAssertEqual(Int(translucentInside.alpha), 128, accuracy: 3,
                "Object opacity must apply once after image-over-color compositing")
        }
    }

    func testAuthoredTextForegroundSharesLiveLayerAndInlineEditorWithoutGeometryChange() throws {
        let color = CanonicalSolidColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1)
        for zoom in [0.25, 1.0, 8.0] {
            for scale in [1.0, 2.0] {
                var typography = CanvasTypography(authoredFamily: "System", resolvedFamily: "System",
                    weight: "regular", size: 14, lineHeight: 17, tracking: 0,
                    alignment: .leading, usesFallback: false)
                let frame = WorldRect(origin: .init(x: 20, y: 24), size: .init(width: 120, height: 24))
                let viewport = try CanvasViewportState(worldOrigin: .init(x: -12, y: 8),
                    viewportSize: .init(width: 500, height: 300), zoom: CanvasZoom(zoom),
                    pixelRatio: CanvasPixelRatio(scale))
                let object = CanvasRenderObject(id: NodeID(), frame: frame, clipRect: nil, paintOrder: 0,
                    style: .textPlaceholder, isVisible: true, accessibilityLabel: "Text object",
                    plainText: "Text", typography: typography)
                let automatic = try XCTUnwrap(CanvasAuthoredTextLayerFactory.makeLayer(for: object,
                    viewport: viewport, contentsScale: scale))
                typography.foregroundRGBA = [color.red, color.green, color.blue, color.alpha]
                let coloredObject = CanvasRenderObject(id: object.id, frame: frame, clipRect: nil,
                    paintOrder: 0, style: .textPlaceholder, isVisible: true,
                    accessibilityLabel: "Text object", plainText: "Text", typography: typography)
                let colored = try XCTUnwrap(CanvasAuthoredTextLayerFactory.makeLayer(for: coloredObject,
                    viewport: viewport, contentsScale: scale))
                XCTAssertEqual(colored.frame, automatic.frame)
                XCTAssertEqual(colored.contentsScale, scale)
                let ink = try XCTUnwrap(NSColor(cgColor: try XCTUnwrap(colored.foregroundColor))?.usingColorSpace(.sRGB))
                XCTAssertEqual(ink.redComponent, color.red, accuracy: 1 / 255)
                XCTAssertEqual(ink.greenComponent, color.green, accuracy: 1 / 255)
                let layout = CanvasTextLayout(viewportObjectRect: colored.frame, zoom: zoom,
                    text: "Text", typography: typography)
                let editor = InlineCanvasTextView()
                editor.string = "Text"
                editor.frame = layout.viewportObjectRect
                editor.applyCanvasTextLayout(layout)
                XCTAssertEqual(editor.frame, layout.viewportObjectRect)
                let editorInk = try XCTUnwrap((editor.textStorage?.attribute(.foregroundColor,
                    at: 0, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB))
                XCTAssertEqual(editorInk.redComponent,
                    color.red, accuracy: 1 / 255)
                XCTAssertEqual(editorInk.greenComponent, color.green, accuracy: 1 / 255)
                XCTAssertTrue(layout.isInsideObjectRect)
            }
        }
    }

    // SF-0401/0405/0407: compare real NSEvent and native backing-layer
    // conversion, not two copies of the renderer's own transform formula.
    func testNativePointerPreviewAndOwnedLayersShareUnreflectedViewportCoordinates() throws {
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 700, height: 500),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = NativeCanvasViewportView(frame: .init(x: 0, y: 0, width: 700, height: 500))
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let root = try XCTUnwrap(view.layer)
        XCTAssertTrue(root.isGeometryFlipped, "AppKit owns the only composition flip")
        for zoom in [0.25, 0.66, 1.0, 2.0, 8.0] {
            for scale in [1.0, 2.0] {
                for origin in [WorldPoint(x: -40, y: 25), WorldPoint(x: 120, y: -80)] {
                    view.viewportState = try CanvasViewportState(worldOrigin: origin,
                        viewportSize: .init(width: 700, height: 500), zoom: CanvasZoom(zoom), pixelRatio: CanvasPixelRatio(scale))
                    for local in [CGPoint(x: 60, y: 80), .init(x: 260, y: 80), .init(x: 260, y: 230), .init(x: 60, y: 230)] {
                        let native = view.convert(local, to: nil)
                        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: native,
                            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                            context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
                        var received: WorldPoint?
                        view.onPointerPreview = { received = $0 }
                        view.mouseMoved(with: event)
                        let world = try XCTUnwrap(received)
                        XCTAssertEqual(world.x, local.x / zoom + origin.x, accuracy: 1e-8)
                        XCTAssertEqual(world.y, local.y / zoom + origin.y, accuracy: 1e-8)
                        for kind in InsertionKind.allCases {
                            let nodeID = NodeID()
                            let geometry = InsertionGeometry.defaultValue(for: kind, at: world)
                            view.insertionPreviewOverlay = .init(id: CanvasOverlayID(), objectID: nodeID,
                                frame: geometry.frame, kind: "insertion-preview")
                            let containers = try XCTUnwrap(root.sublayers)
                            for name in ["renderer.authored-content", "renderer.authored-text", "renderer.editor-overlays"] {
                                let container = try XCTUnwrap(containers.first { $0.name == name })
                                XCTAssertEqual(container.convert(local, to: root).x, local.x, accuracy: 1 / scale)
                                XCTAssertEqual(container.convert(local, to: root).y, local.y, accuracy: 1 / scale)
                            }
                            let overlays = try XCTUnwrap(containers.first { $0.name == "renderer.editor-overlays" })
                            let preview = try XCTUnwrap(overlays.sublayers?.first { $0.name == "renderer.overlay.insertion-preview" })
                            let painted = overlays.convert(preview.frame, to: root)
                            XCTAssertEqual(painted.minX, local.x, accuracy: 1 / scale)
                            XCTAssertEqual(painted.minY, local.y, accuracy: 1 / scale)
                            XCTAssertEqual(painted.width, geometry.size.width * zoom, accuracy: 1 / scale)
                            XCTAssertEqual(painted.height, geometry.size.height * zoom, accuracy: 1 / scale)
                        }
                    }
                }
            }
        }
    }

    // SF-1102-001/006: Button surfaces must not suppress their authored text
    // subtree. Link and Button glyphs use the same upright layout at zoom.
    func testControlGlyphPixelsRemainVisibleWithinAuthoredBounds() throws {
        for scale in [1.0, 2.0] {
            for zoom in [0.25, 1.0, 8.0] {
                let viewport = try CanvasViewportState(
                    worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 1500, height: 500), zoom: CanvasZoom(zoom),
                    pixelRatio: CanvasPixelRatio(scale))
                for style in [CanvasPaintStyle.frameSurface, .textPlaceholder] {
                    let frame = WorldRect(origin: .init(x: 4, y: 4), size: .init(width: 160, height: 44))
                    let object = CanvasRenderObject(id: NodeID(), frame: frame, clipRect: nil,
                        paintOrder: 0, style: style, isVisible: true, accessibilityLabel: "Control",
                        plainText: "Continue", fillRGBA: style == .frameSurface ? [0.92, 0.92, 0.92, 1] : nil)
                    let layer = try XCTUnwrap(CanvasAuthoredTextLayerFactory.makeLayer(for: object, viewport: viewport, contentsScale: scale))
                    if style == .frameSurface {
                        XCTAssertEqual(layer.foregroundColor, NSColor.black.cgColor)
                    }
                    let pixels = rasterizedTextLayerBytes(layer, width: 1500, height: 500)
                    let changed = changedPixels(from: Data(repeating: 0, count: pixels.count), to: pixels, width: 1500)
                    XCTAssertFalse(changed.isEmpty, "An authored control label must paint glyphs, including on a filled surface")
                    XCTAssertTrue(changed.allSatisfy { layer.frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: $0.x, y: $0.y)) })
                }
            }
        }
    }
    // SF-0405-006, SF-1202-003: structural names are editor metadata, not
    // authored pixels. Actual text uses the independent authored text layer.
    func testNativeTileStructuralNamesNeverEnterAuthoredPixels() throws {
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 300, height: 120),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
            pixelRatio: CanvasPixelRatio(2)
        )
        let base = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000201")!),
            frame: .init(origin: .init(x: 32, y: 24), size: .init(width: 180, height: 42)),
            clipRect: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
            paintOrder: 0,
            style: .textPlaceholder,
            isVisible: true,
            accessibilityLabel: "Text object"
        )
        let namedFrame = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000202")!),
            frame: base.frame,
            clipRect: base.clipRect,
            paintOrder: 0,
            style: .frameSurface,
            isVisible: true,
            accessibilityLabel: "Frame object",
            displayName: "Frame"
        )
        let unnamedFrame = CanvasRenderObject(
            id: namedFrame.id,
            frame: namedFrame.frame,
            clipRect: namedFrame.clipRect,
            paintOrder: namedFrame.paintOrder,
            style: namedFrame.style,
            isVisible: namedFrame.isVisible,
            accessibilityLabel: namedFrame.accessibilityLabel
        )
        let frameLabelPixels = changedPixels(
            from: rasterizedBytes(object: unnamedFrame, viewport: viewport),
            to: rasterizedBytes(object: namedFrame, viewport: viewport),
            width: 300
        )
        XCTAssertTrue(frameLabelPixels.isEmpty, "Editor names must not alter authored surface bytes")
    }

    // SF-0401-003/004, SF-0407-003: editor validation/header resizing must
    // retain the same native painted rect as selection without authored edits.
    func testNativeViewportResizePreservesReprojectedRasterAndTextCoordinates() throws {
        let view = NativeCanvasViewportView(frame: .init(x: 0, y: 0, width: 700, height: 500))
        let initial = try CanvasViewportState(viewportSize: .init(width: 700, height: 500))
        view.viewportState = initial
        let object = CanvasRenderObject(id: NodeID(),
            frame: .init(origin: .init(x: 80, y: 60), size: .init(width: 240, height: 160)),
            clipRect: nil, paintOrder: 0, style: .frameSurface, isVisible: true,
            accessibilityLabel: "Authored Frame", fillRGBA: [0.6, 0.2, 0.8, 1])
        let identity = CanvasRenderRequestIdentity(documentID: DocumentID(), revision: 1,
            sceneID: initial.sceneID, sceneGeneration: 1, viewportGeneration: 1, scale: initial.pixelRatio)
        let plan = try CanvasRendererCore().prepare(scene: .init(identity: identity, surfaceID: .init(), objects: [object]),
            overlays: .init(identity: identity, overlays: []), viewport: initial)
        view.renderPlan = plan
        let rasterPoint = try initial.transform.worldToViewport(object.frame.origin)
        for zoom in [0.25, 0.85, 1.0, 8.0] {
            view.viewportState = try CanvasViewportState(sceneID: initial.sceneID,
                worldOrigin: .init(x: -40, y: 25), viewportSize: initial.viewportSize,
                contentBounds: initial.contentBounds, zoom: .init(zoom), pixelRatio: initial.pixelRatio)
            for size in [NSSize(width: 700, height: 480), .init(width: 680, height: 480), .init(width: 700, height: 500)] {
                view.setFrameSize(size)
                let expected = try view.viewportState.transform.worldToViewport(object.frame.origin)
                for name in ["renderer.authored-content", "renderer.authored-text"] {
                    let container = try XCTUnwrap(view.layer?.sublayers?.first { $0.name == name })
                    let actual = container.convert(.init(x: rasterPoint.x, y: rasterPoint.y), to: view.layer)
                    XCTAssertEqual(actual.x, expected.x, accuracy: 0.000001, name)
                    XCTAssertEqual(actual.y, expected.y, accuracy: 0.000001, name)
                }
            }
        }
    }

    // SF-0401-003/004: the artboard mask belongs to the container's local
    // coordinates even while old valid raster is reprojected during pan/zoom.
    func testNativeViewportArtboardMaskSharesLiveViewportDuringReprojection() throws {
        let view = NativeCanvasViewportView(frame: .init(x: 0, y: 0, width: 700, height: 500))
        view.setFrameSize(view.bounds.size)
        let initial = try CanvasViewportState(viewportSize: .init(width: 700, height: 500),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 430, height: 900)))
        view.viewportState = initial
        let object = CanvasRenderObject(id: NodeID(),
            frame: .init(origin: .init(x: 400, y: 60), size: .init(width: 240, height: 160)),
            clipRect: nil, paintOrder: 0, style: .frameSurface, isVisible: true, accessibilityLabel: "Partial Frame")
        let identity = CanvasRenderRequestIdentity(documentID: DocumentID(), revision: 1,
            sceneID: initial.sceneID, sceneGeneration: 1, viewportGeneration: 1, scale: initial.pixelRatio)
        view.renderPlan = try CanvasRendererCore().prepare(scene: .init(identity: identity, surfaceID: .init(), objects: [object]),
            overlays: .init(identity: identity, overlays: []), viewport: initial)
        func assertClip(_ expected: CGRect) throws {
            for name in ["renderer.authored-content", "renderer.authored-text"] {
                let container = try XCTUnwrap(view.layer?.sublayers?.first { $0.name == name })
                let mask = try XCTUnwrap(container.mask as? CAShapeLayer)
                let path = try XCTUnwrap(mask.path)
                let actual = container.convert(path.boundingBoxOfPath, to: view.layer)
                XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.000001, name)
                XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.000001, name)
                XCTAssertEqual(actual.width, expected.width, accuracy: 0.000001, name)
                XCTAssertEqual(actual.height, expected.height, accuracy: 0.000001, name)
            }
        }
        for zoom in [0.25, 0.85, 1.0, 8.0] {
            for pan in [WorldPoint(x: -40, y: 25), .init(x: 200, y: -30)] {
                view.viewportState = try CanvasViewportState(sceneID: initial.sceneID, worldOrigin: pan,
                    viewportSize: initial.viewportSize, contentBounds: initial.contentBounds,
                    zoom: .init(zoom), pixelRatio: initial.pixelRatio)
                let origin = try view.viewportState.transform.worldToViewport(initial.contentBounds.origin)
                let expected = CGRect(x: origin.x, y: origin.y,
                    width: 430 * zoom, height: 900 * zoom)
                try assertClip(expected)
                view.renderPlan = try CanvasRendererCore().prepare(
                    scene: .init(identity: identity, surfaceID: .init(), objects: [object]),
                    overlays: .init(identity: identity, overlays: []), viewport: view.viewportState)
                try assertClip(expected)
            }
        }
    }

    func testNativeViewportRetainsWorldAlignedRasterDuringZoomAndClearsAtArtboardChange() throws {
        let view = NativeCanvasViewportView(frame: .init(x: 0, y: 0, width: 700, height: 500))
        view.setFrameSize(view.bounds.size)
        let initial = try CanvasViewportState(viewportSize: .init(width: 700, height: 500))
        view.viewportState = initial
        let object = CanvasRenderObject(id: NodeID(),
            frame: .init(origin: .init(x: 80, y: 60), size: .init(width: 240, height: 160)),
            clipRect: nil, paintOrder: 0, style: .frameSurface, isVisible: true,
            accessibilityLabel: "Authored Frame", fillRGBA: [0.6, 0.2, 0.8, 1])
        let identity = CanvasRenderRequestIdentity(documentID: DocumentID(), revision: 1,
            sceneID: initial.sceneID, sceneGeneration: 1, viewportGeneration: 1, scale: initial.pixelRatio)
        let scene = CanvasRenderSceneSnapshot(identity: identity, surfaceID: CanvasRenderSurfaceID(), objects: [object])
        let plan = try CanvasRendererCore().prepare(scene: scene,
            overlays: .init(identity: identity, overlays: []), viewport: initial)
        view.renderPlan = plan
        let content = try XCTUnwrap(view.layer?.sublayers?.first { $0.name == "renderer.authored-content" })
        XCTAssertEqual(content.bounds.size, view.bounds.size)
        let tiles = try XCTUnwrap(content.sublayers)
        XCTAssertFalse(tiles.isEmpty)
        let rasterOrigin = try initial.transform.worldToViewport(object.frame.origin)
        for zoom in [0.25, 0.5, 1, 1.75, 8] {
            for origin in [WorldPoint(x: -40, y: 30), WorldPoint(x: 55, y: -25)] {
                view.viewportState = try CanvasViewportState(sceneID: initial.sceneID, worldOrigin: origin,
                    viewportSize: initial.viewportSize, contentBounds: initial.contentBounds,
                    zoom: CanvasZoom(zoom), pixelRatio: initial.pixelRatio)
                XCTAssertEqual(content.sublayers?.count, tiles.count, "Zoom must not blank the valid scene")
                XCTAssertTrue(content.sublayers?.first === tiles.first)
                let native = content.convert(CGPoint(x: rasterOrigin.x, y: rasterOrigin.y), to: view.layer)
                let expected = try view.viewportState.transform.worldToViewport(object.frame.origin)
                XCTAssertEqual(native.x, expected.x, accuracy: 0.000001)
                XCTAssertEqual(native.y, expected.y, accuracy: 0.000001)
                view.renderPlan = plan // A late old-generation result cannot erase the retained raster.
                XCTAssertEqual(content.sublayers?.count, tiles.count)
            }
        }
        view.viewportState = try CanvasViewportState(sceneID: initial.sceneID, viewportSize: initial.viewportSize,
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 390, height: 844)))
        XCTAssertTrue(content.sublayers?.isEmpty ?? true, "A different artboard must resolve its own layout")
        view.viewportState = initial
        view.renderPlan = plan
        XCTAssertFalse(content.sublayers?.isEmpty ?? true)
        view.viewportState = try CanvasViewportState(viewportSize: initial.viewportSize,
                                                     contentBounds: initial.contentBounds)
        XCTAssertTrue(content.sublayers?.isEmpty ?? true, "A new scene cannot reuse another scene's pixels")
        view.renderPlan = nil
        XCTAssertTrue(content.sublayers?.isEmpty ?? true)
    }

    // SF-0401-001, SF-0401-004, SF-0402-006, SF-0405-006, SF-0406-001 —
    // the shared AppKit/Core Graphics tile boundary performs exactly one
    // reversible Y conversion across canonical viewport values.
    func testFrameAndTextUseOneUprightTopLeftTileConventionAcrossViewportMatrix() throws {
        let tileBounds = CGRect(x: 0, y: 0, width: 320, height: 240)
        for zoom in [CanvasZoom.minimum, .actualSize, CanvasZoom.maximum] {
            for pixelRatio in [try CanvasPixelRatio(1), try CanvasPixelRatio(2)] {
                for worldOrigin in [WorldPoint(x: -32, y: -24), WorldPoint(x: 20, y: 16)] {
                    let transform = try CanvasCoordinateTransform(
                        worldOrigin: worldOrigin,
                        zoom: zoom,
                        pixelRatio: pixelRatio
                    )
                    let canonicalOrigin = WorldPoint(x: worldOrigin.x + 16, y: worldOrigin.y + 14)
                    let viewportOrigin = try transform.worldToViewport(canonicalOrigin)
                    let canonicalRect = CGRect(
                        x: viewportOrigin.x,
                        y: viewportOrigin.y,
                        width: 40 * zoom.value,
                        height: 28 * zoom.value
                    )
                    let rasterRect = CanvasTileTextCoordinateSpace.drawingRect(for: canonicalRect, in: tileBounds)
                    XCTAssertEqual(rasterRect.minX, canonicalRect.minX, accuracy: 0.000_001)
                    XCTAssertEqual(rasterRect.height, canonicalRect.height, accuracy: 0.000_001)
                    XCTAssertTrue(abs((rasterRect.minY + canonicalRect.maxY) - tileBounds.height) < 0.000_001)
                    XCTAssertEqual(try transform.viewportToWorld(viewportOrigin), canonicalOrigin)
                }
            }
        }
    }

    // SF-0401-001, SF-0405-006, SF-0406-001, SF-0406-002 — the committed
    // tile and native inline editor share one rect/inset/baseline contract.
    func testSharedTextLayoutKeepsGlyphsInsideOneViewportRectAcrossMatrix() throws {
        let text = "Canvas text"
        for zoom in [CanvasZoom.minimum.value, 1.0, CanvasZoom.maximum.value] {
            for pixelRatio in [try CanvasPixelRatio(1), try CanvasPixelRatio(2)] {
                for origin in [WorldPoint(x: -512, y: -256), WorldPoint(x: 384, y: 192)] {
                    let transform = try CanvasCoordinateTransform(
                        worldOrigin: origin,
                        zoom: try CanvasZoom(zoom),
                        pixelRatio: pixelRatio
                    )
                    let worldFrame = WorldRect(
                        origin: .init(x: origin.x + 128, y: origin.y + 96),
                        size: .init(width: 240, height: 48)
                    )
                    let viewportOrigin = try transform.worldToViewport(worldFrame.origin)
                    let objectRect = CGRect(
                        x: viewportOrigin.x,
                        y: viewportOrigin.y,
                        width: worldFrame.size.width * zoom,
                        height: worldFrame.size.height * zoom
                    )
                    let layout = CanvasTextLayout(
                        viewportObjectRect: objectRect,
                        zoom: zoom,
                        text: text
                    )
                    let tolerance = 1 / pixelRatio.value
                    XCTAssertEqual(layout.viewportObjectRect, objectRect)
                    XCTAssertGreaterThanOrEqual(layout.glyphBounds.minX + tolerance, objectRect.minX)
                    XCTAssertLessThanOrEqual(layout.glyphBounds.maxX - tolerance, objectRect.maxX)
                    XCTAssertGreaterThanOrEqual(layout.glyphBounds.minY + tolerance, objectRect.minY)
                    XCTAssertLessThanOrEqual(layout.glyphBounds.maxY - tolerance, objectRect.maxY)
                    XCTAssertEqual(
                        layout.glyphBounds.midY,
                        objectRect.midY,
                        accuracy: tolerance,
                        "glyph baseline drifted at zoom \(zoom), scale \(pixelRatio.value)"
                    )
                    let tileRect = CanvasTileTextCoordinateSpace.drawingRect(
                        for: layout.lineFragmentRect,
                        in: CGRect(x: 0, y: 0, width: 512, height: 512)
                    )
                    XCTAssertEqual(tileRect.height, layout.lineFragmentRect.height, accuracy: 0.000_001)
                }
            }
        }
    }

    // SF-0507-003/004/006: this is the actual authored CATextLayer path.
    func testManagedTitleNativeLineCapacityAndInsetsShareResolvedTypography() throws {
        let text = "Connected Fluid Browser Receipt"
        for zoom in [0.25, 1.0, 8.0] {
            for height in [24.0, 72] {
                let rect = CGRect(x: 30, y: 50, width: 200 * zoom, height: height * zoom)
                let typography = CanvasTypography(authoredFamily: "System", resolvedFamily: "System",
                    weight: "regular", size: 14, lineHeight: 17, tracking: 0,
                    alignment: .leading, usesFallback: false)
                let layout = CanvasTextLayout(viewportObjectRect: rect, zoom: zoom, text: text, typography: typography)
                XCTAssertEqual(layout.visibleLineCapacity, height == 24 ? 1 : 4)
                XCTAssertEqual(layout.textContainerInset.width, CanvasTextLayoutPolicy.horizontalInset * zoom, accuracy: 0.000_001)
                for scale in [1.0, 2] {
                    let object = CanvasRenderObject(id: NodeID(), frame: .init(origin: .init(x: 0, y: 0),
                        size: .init(width: 200, height: height)), clipRect: nil, paintOrder: 0,
                        style: .textPlaceholder, isVisible: true, accessibilityLabel: text,
                        plainText: text, typography: typography)
                    let layer = try XCTUnwrap(CanvasAuthoredTextLayerFactory.makeLayer(for: object,
                        viewportObjectRect: rect, zoom: zoom, contentsScale: scale))
                    XCTAssertTrue(layer.isWrapped)
                    XCTAssertEqual(layer.truncationMode, .end)
                    XCTAssertEqual(layer.frame, layout.glyphBounds)
                    XCTAssertEqual((layer.string as? NSAttributedString)?.string, text)
                    XCTAssertTrue(layout.isInsideObjectRect)
                }
            }
        }
        XCTAssertEqual(CanvasTextLayoutPolicy.visibleLineCapacity(height: .nan, lineHeight: 17), 0)
        XCTAssertEqual(CanvasTextLayoutPolicy.visibleLineCapacity(height: 24, lineHeight: 0), 0)
    }

    func testCanonicalTypographySharesRendererAndInlineMetricsAcrossZoomAndAlignment() throws {
        for zoom in [0.25, 1.0, 8.0] {
            for alignment in [CanvasTextAlignment.leading, .center, .trailing] {
                let typography = CanvasTypography(
                    authoredFamily: "Menlo", resolvedFamily: "Menlo", weight: "bold",
                    size: 18, lineHeight: 26, tracking: 1.25,
                    alignment: alignment, usesFallback: false
                )
                let rect = CGRect(x: -48, y: 72, width: 240 * zoom, height: 96 * zoom)
                let committed = CanvasTextLayout(
                    viewportObjectRect: rect, zoom: zoom,
                    text: "Typography\nparity", typography: typography
                )
                let editor = InlineCanvasTextView()
                editor.string = "Typography\nparity"
                editor.frame = rect
                editor.applyCanvasTextLayout(committed)
                XCTAssertEqual(editor.frame, committed.viewportObjectRect)
                XCTAssertEqual(editor.font?.fontName, committed.font.fontName)
                XCTAssertEqual(editor.font?.pointSize ?? 0, committed.fontSize, accuracy: 0.000_001)
                XCTAssertEqual(editor.textContainerInset, committed.textContainerInset)
                XCTAssertEqual(editor.alignment, committed.alignment)
                XCTAssertEqual(editor.typingAttributes[.kern] as? CGFloat, committed.tracking)
                XCTAssertTrue(committed.isInsideObjectRect)
                XCTAssertEqual(committed.lineHeight, min(max(committed.fontSize * 0.5, 26 * zoom), rect.height), accuracy: 0.000_001)
            }
        }

        let fallback = CanvasTypography(
            authoredFamily: "Unavailable SiteForge Test Font", resolvedFamily: "System",
            weight: "regular", size: 14, lineHeight: 17, tracking: 0,
            alignment: .leading, usesFallback: true
        )
        let fallbackLayout = CanvasTextLayout(
            viewportObjectRect: CGRect(x: 0, y: 0, width: 180, height: 48),
            zoom: 1, text: "Fallback", typography: fallback
        )
        XCTAssertEqual(fallback.authoredFamily, "Unavailable SiteForge Test Font")
        XCTAssertEqual(fallbackLayout.font.familyName, NSFont.systemFont(ofSize: 14).familyName)
    }

    // SF-0406-001, SF-0406-002, SF-0508-005 — committed plain-text glyphs
    // use the production CATextLayer path and inherit authored object opacity
    // exactly like the tiled surface (including fully transparent text).
    func testProductionAuthoredTextLayerPixelsHonorObjectOpacity() throws {
        let width = 240
        let height = 100
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: Double(width), height: Double(height)),
            contentBounds: .init(
                origin: .init(x: 0, y: 0),
                size: .init(width: Double(width), height: Double(height))
            ),
            pixelRatio: CanvasPixelRatio(2)
        )
        let frame = WorldRect(
            origin: .init(x: 20, y: 20),
            size: .init(width: 180, height: 40)
        )

        var maximumAlpha: [Double: UInt8] = [:]
        for opacity in [1.0, 0.5, 0.0] {
            let object = CanvasRenderObject(
                id: NodeID(),
                frame: frame,
                clipRect: nil,
                paintOrder: 0,
                style: .textPlaceholder,
                isVisible: true,
                accessibilityLabel: "Opacity text",
                plainText: "SiteForge opacity",
                opacity: opacity
            )
            let layer = try XCTUnwrap(CanvasAuthoredTextLayerFactory.makeLayer(
                for: object,
                viewport: viewport,
                contentsScale: 2
            ))
            XCTAssertEqual(layer.opacity, Float(opacity), accuracy: 0.000_001)
            let pixels = rasterizedTextLayerBytes(layer, width: width, height: height)
            maximumAlpha[opacity] = stride(from: 3, to: pixels.count, by: 4)
                .map { pixels[$0] }
                .max() ?? 0
            let changed = changedPixels(
                from: Data(repeating: 0, count: pixels.count),
                to: pixels,
                width: width
            )
            if opacity == 0 {
                XCTAssertTrue(changed.isEmpty, "Zero-opacity authored text must paint no glyph pixels.")
            } else {
                XCTAssertFalse(changed.isEmpty)
                XCTAssertTrue(
                    changed.allSatisfy { layer.frame.insetBy(dx: -1, dy: -1).contains(CGPoint(x: $0.x, y: $0.y)) },
                    "Authored text pixels escaped the production CATextLayer bounds: \(pixelBounds(changed))"
                )
            }
        }

        let opaque = try XCTUnwrap(maximumAlpha[1.0])
        let half = try XCTUnwrap(maximumAlpha[0.5])
        XCTAssertGreaterThan(opaque, 0)
        XCTAssertEqual(Double(half) / Double(opaque), 0.5, accuracy: 0.08)
        XCTAssertEqual(maximumAlpha[0.0], 0)
    }

    // SF-0508-001...005, SF-0508-008 — authored RGBA/opacity is composited
    // by the production tile layer. Editor overlays are a different scene and
    // cannot affect these raw authored pixels.
    func testAuthoredSolidFillAndOpacityUseExactTilePixelsWithoutEditorOverlayContamination() throws {
        let authored = [32.0 / 255.0, 64.0 / 255.0, 96.0 / 255.0, 1.0]
        for zoom in [CanvasZoom.minimum, .actualSize, CanvasZoom.maximum] {
            for pixelRatio in [try CanvasPixelRatio(1), try CanvasPixelRatio(2)] {
                for origin in [WorldPoint(x: -256, y: 192), WorldPoint(x: 320, y: -224)] {
                    let viewport = try CanvasViewportState(
                        worldOrigin: origin,
                        viewportSize: .init(width: 300, height: 120),
                        contentBounds: .init(origin: .init(x: -2_000, y: -2_000), size: .init(width: 8_000, height: 8_000)),
                        zoom: zoom,
                        pixelRatio: pixelRatio
                    )
                    // Keep the sample interior in the finite test bitmap at
                    // every zoom while retaining a different canonical frame
                    // for each transform. This also puts the tile's local
                    // origin inside the object rather than testing a
                    // screen-fixed rectangle.
                    let worldFrame = WorldRect(
                        origin: .init(x: origin.x + 96 / zoom.value, y: origin.y + 48 / zoom.value),
                        size: .init(width: 80 / zoom.value, height: 48 / zoom.value)
                    )
                    let viewportOrigin = try viewport.transform.worldToViewport(worldFrame.origin)
                    // rgba/changedPixels convert bitmap scanlines once into
                    // top-left coordinates. Expected bounds therefore use
                    // the native viewport rect without a second reflection.
                    let center = (
                        x: Int((viewportOrigin.x + worldFrame.size.width * zoom.value / 2).rounded()),
                        y: Int((viewportOrigin.y + worldFrame.size.height * zoom.value / 2).rounded())
                    )
                    let expectedBitmapRect = CGRect(
                        x: viewportOrigin.x,
                        y: viewportOrigin.y,
                        width: worldFrame.size.width * zoom.value,
                        height: worldFrame.size.height * zoom.value
                    )
                    for (opacity, expectedAlpha) in [(1.0, 255), (0.5, 128), (0.0, 0)] {
                        autoreleasepool {
                        let object = CanvasRenderObject(
                            id: NodeID(), frame: worldFrame, clipRect: nil, paintOrder: 0,
                            style: .frameSurface, isVisible: true, accessibilityLabel: "Frame",
                            fillRGBA: authored, opacity: opacity
                        )
                        let pixels = rasterizedBytes(object: object, viewport: viewport)
                        let inside = rgba(at: center, in: pixels, width: 300, height: 120)
                        let hidden = CanvasRenderObject(
                            id: object.id, frame: object.frame, clipRect: object.clipRect,
                            paintOrder: object.paintOrder, style: object.style,
                            isVisible: false, accessibilityLabel: object.accessibilityLabel,
                            fillRGBA: object.fillRGBA, opacity: object.opacity
                        )
                        let changed = changedPixels(
                            from: rasterizedBytes(object: hidden, viewport: viewport),
                            to: pixels, width: 300
                        )
                        if opacity == 0 {
                            XCTAssertTrue(changed.isEmpty, "A zero-opacity authored fill must not paint any pixel.")
                        } else {
                            XCTAssertFalse(changed.isEmpty)
                            XCTAssertTrue(
                                changed.allSatisfy {
                                    expectedBitmapRect.insetBy(dx: -1, dy: -1).contains(
                                        CGPoint(x: $0.x, y: $0.y)
                                    )
                                },
                                "The production tile painted outside its exact resolved object bounds: \(pixelBounds(changed)) expected \(expectedBitmapRect)"
                            )
                        }
                        XCTAssertEqual(Int(inside.alpha), expectedAlpha, accuracy: 3, "alpha at zoom \(zoom.value), scale \(pixelRatio.value), origin \(origin), center \(center), changed \(pixelBounds(changed))")
                        // The production renderer resolves calibrated input
                        // into the active device RGB target. Test that target
                        // directly: alpha is exact and the normalized 1:2:3
                        // channel relationship survives premultiplication
                        // within the compositor's three-byte tolerance.
                        if opacity > 0 {
                            XCTAssertGreaterThan(inside.red, 0)
                            XCTAssertEqual(Double(inside.green) / Double(inside.red), 2, accuracy: 0.10)
                            // At 50% alpha, 8-bit premultiplication rounds
                            // the smallest red channel before the other two.
                            // A quarter-ratio tolerance is therefore the
                            // explicit device-pixel policy, not a broad
                            // changed-pixel assertion.
                            XCTAssertEqual(Double(inside.blue) / Double(inside.red), 3, accuracy: 0.25)
                        } else {
                            XCTAssertEqual(inside.red, 0)
                            XCTAssertEqual(inside.green, 0)
                            XCTAssertEqual(inside.blue, 0)
                        }
                        let outside = rgba(at: (x: 4, y: 4), in: pixels, width: 300, height: 120)
                        XCTAssertEqual(outside.red, 0, "Authoring fill must not paint outside the exact object bounds.")
                        XCTAssertEqual(outside.green, 0)
                        XCTAssertEqual(outside.blue, 0)
                        XCTAssertEqual(outside.alpha, 0)
                        }
                    }
                }
            }
        }
    }

    // SF-0508-001, SF-0508-003, SF-0508-005, SF-0508-008 — the production
    // tile rasterizes the immutable authored layer order, ignores disabled
    // layers, and applies object opacity once after source-over compositing.
    func testAuthoredFillLayerStackAndGradientUseExactProductionTilePixels() throws {
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 300, height: 120),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
            pixelRatio: CanvasPixelRatio(2)
        )
        let frame = WorldRect(
            origin: .init(x: 40, y: 30),
            size: .init(width: 160, height: 60)
        )
        let clip = WorldRect(
            origin: .init(x: 0, y: 0),
            size: .init(width: 300, height: 120)
        )
        func solid(_ uuid: String, _ rgba: [Double], enabled: Bool = true) -> CanvasAuthoredFillLayer {
            CanvasAuthoredFillLayer(
                id: UUID(uuidString: uuid)!, kind: .solid,
                isEnabled: enabled, rgba: rgba, angleDegrees: nil, stops: []
            )
        }

        let layered = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000301")!),
            frame: frame, clipRect: clip, paintOrder: 0,
            style: .frameSurface, isVisible: true, accessibilityLabel: "Layered frame",
            fillLayers: [
                solid("00000000-0000-0000-0000-000000000302", [1, 0, 0, 1]),
                solid("00000000-0000-0000-0000-000000000303", [0, 1, 0, 1], enabled: false),
                solid("00000000-0000-0000-0000-000000000304", [0, 0, 1, 0.5]),
            ],
            opacity: 0.5
        )
        let layeredPixels = rasterizedBytes(object: layered, viewport: viewport)
        let layeredCenter = rgba(at: (x: 120, y: 60), in: layeredPixels, width: 300, height: 120)
        let withoutDisabledLayer = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000309")!),
            frame: frame, clipRect: clip, paintOrder: 0,
            style: .frameSurface, isVisible: true, accessibilityLabel: "Reference layered frame",
            fillLayers: [
                solid("00000000-0000-0000-0000-000000000310", [1, 0, 0, 1]),
                solid("00000000-0000-0000-0000-000000000311", [0, 0, 1, 0.5]),
            ],
            opacity: 0.5
        )
        let referencePixels = rasterizedBytes(object: withoutDisabledLayer, viewport: viewport)
        let referenceCenter = rgba(at: (x: 120, y: 60), in: referencePixels, width: 300, height: 120)
        XCTAssertEqual(
            [layeredCenter.red, layeredCenter.green, layeredCenter.blue, layeredCenter.alpha],
            [referenceCenter.red, referenceCenter.green, referenceCenter.blue, referenceCenter.alpha],
            "A disabled fill layer must have no effect on the production raster."
        )
        XCTAssertEqual(Int(layeredCenter.red), 64, accuracy: 4)
        XCTAssertEqual(Int(layeredCenter.blue), 64, accuracy: 4)
        XCTAssertEqual(Int(layeredCenter.alpha), 128, accuracy: 3, "Object opacity must apply once to the completed opaque layer stack.")
        let layeredOutside = rgba(at: (x: 20, y: 60), in: layeredPixels, width: 300, height: 120)
        XCTAssertEqual(layeredOutside.alpha, 0, "Pixels outside the authored object bounds must remain transparent.")

        let gradient = CanvasAuthoredFillLayer(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000305")!,
            kind: .linearGradient,
            isEnabled: true,
            rgba: nil,
            angleDegrees: 0,
            stops: [
                .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000306")!, position: 0, rgba: [1, 0, 0, 1]),
                .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000307")!, position: 1, rgba: [0, 0, 1, 1]),
            ]
        )
        let gradientObject = CanvasRenderObject(
            id: NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000308")!),
            frame: frame, clipRect: clip, paintOrder: 0,
            style: .frameSurface, isVisible: true, accessibilityLabel: "Gradient frame",
            fillLayers: [gradient]
        )
        let gradientPixels = rasterizedBytes(object: gradientObject, viewport: viewport)
        let left = rgba(at: (x: 60, y: 60), in: gradientPixels, width: 300, height: 120)
        let center = rgba(at: (x: 120, y: 60), in: gradientPixels, width: 300, height: 120)
        let right = rgba(at: (x: 180, y: 60), in: gradientPixels, width: 300, height: 120)
        XCTAssertEqual(Int(left.red), 223, accuracy: 4)
        XCTAssertEqual(Int(left.blue), 32, accuracy: 4)
        XCTAssertEqual(Int(center.red), 127, accuracy: 4)
        XCTAssertEqual(Int(center.blue), 128, accuracy: 4)
        XCTAssertEqual(Int(right.red), 32, accuracy: 4)
        XCTAssertEqual(Int(right.blue), 223, accuracy: 4)
        for sample in [left, center, right] {
            XCTAssertEqual(Int(sample.alpha), 255, accuracy: 3)
        }
        let gradientOutside = rgba(at: (x: 220, y: 60), in: gradientPixels, width: 300, height: 120)
        XCTAssertEqual(gradientOutside.alpha, 0, "Pixels outside the authored object bounds must remain transparent.")
    }

    // SF-0507-003/005, SF-0508-003: plain text paints glyphs, not editor boxes.
    func testCommittedPlainTextHasTransparentNonGlyphPixelsAtBothBackingScales() throws {
        let frame = WorldRect(origin: .init(x: 40, y: 30), size: .init(width: 160, height: 60))
        for scale in [1.0, 2.0] {
            let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0),
                viewportSize: .init(width: 300, height: 120), pixelRatio: .init(scale))
            let object = CanvasRenderObject(id: NodeID(), frame: frame, clipRect: nil,
                paintOrder: 0, style: .textPlaceholder, isVisible: true,
                accessibilityLabel: "Plain text", plainText: "Text")
            let pixels = rasterizedBytes(object: object, viewport: viewport, backingScale: scale, includeText: true)
            let width = Int(300 * scale), height = Int(120 * scale)
            for point in [(40, 31), (199, 31), (40, 88), (199, 88), (42, 32), (197, 32), (42, 87), (197, 87), (120, 28), (120, 92)] {
                XCTAssertEqual(rgba(at: (x: Int(Double(point.0) * scale), y: Int(Double(point.1) * scale)),
                    in: pixels, width: width, height: height).alpha, 0,
                    "Plain text must not bake the editor's placeholder rectangle into authored pixels")
            }
            let inkPixels = pixels.enumerated().filter { $0.offset % 4 == 3 && $0.element > 0 }.count
            XCTAssertGreaterThan(inkPixels, 10, "Transparent fallback must not erase actual glyphs")
            XCTAssertLessThan(inkPixels, Int(frame.size.width * frame.size.height * scale * scale / 2))
            XCTAssertEqual(object.frame, frame)
        }
    }

    // SF-0508-003: a diagonal interpolation segment must extend endpoint
    // colors to every authored corner, without painting outside the shape.
    func testDiagonalGradientEndpointCapsCoverAuthoredCornersWithoutEscapingBounds() throws {
        let frame = WorldRect(origin: .init(x: 40, y: 30), size: .init(width: 160, height: 60))
        for scale in [1.0, 2.0] {
            let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0),
                viewportSize: .init(width: 300, height: 120),
                contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
                pixelRatio: .init(scale))
            for angle in [45.0, 135, 225, 315] {
                let layer = CanvasAuthoredFillLayer(id: UUID(), kind: .linearGradient,
                    isEnabled: true, rgba: nil, angleDegrees: angle, stops: [
                        .init(id: UUID(), position: 0, rgba: [22.0 / 255, 13.0 / 255, 43.0 / 255, 1]),
                        .init(id: UUID(), position: 0.5, rgba: [106.0 / 255, 54.0 / 255, 200.0 / 255, 1]),
                        .init(id: UUID(), position: 1, rgba: [197.0 / 255, 46.0 / 255, 83.0 / 255, 1]),
                    ])
                let object = CanvasRenderObject(id: NodeID(), frame: frame,
                    clipRect: viewport.contentBounds, paintOrder: 0, style: .frameSurface,
                    isVisible: true, accessibilityLabel: "Diagonal gradient", fillLayers: [layer])
                let pixels = rasterizedBytes(object: object, viewport: viewport, backingScale: scale)
                let pixelWidth = Int(300 * scale), pixelHeight = Int(120 * scale)
                for point in [(42, 32), (197, 32), (42, 87), (197, 87), (120, 60)] {
                    let color = rgba(at: (x: Int(Double(point.0) * scale), y: Int(Double(point.1) * scale)),
                        in: pixels, width: pixelWidth, height: pixelHeight)
                    XCTAssertEqual(Int(color.alpha), 255, accuracy: 1,
                        "No transparent diagonal wedge at \(point), angle \(angle), scale \(scale)")
                }
                for point in [(38, 60), (202, 60), (120, 28), (120, 92)] {
                    XCTAssertEqual(rgba(at: (x: Int(Double(point.0) * scale), y: Int(Double(point.1) * scale)),
                        in: pixels, width: pixelWidth, height: pixelHeight).alpha, 0)
                }
                XCTAssertEqual(object.frame, frame)
            }
        }
    }

    // SF-0506-003/005/008 — production raster composition is shadow, rounded
    // clipped fill, then authored border. Editor overlays are not in this tile.
    func testBorderRadiusAndShadowUseProductionTileCompositionWithoutGeometryDrift() throws {
        let viewport = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 300, height: 120),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 300, height: 120)),
            pixelRatio: .init(2)
        )
        let frame = WorldRect(origin: .init(x: 60, y: 24), size: .init(width: 120, height: 64))
        let object = CanvasRenderObject(
            id: NodeID(), frame: frame, clipRect: viewport.contentBounds, paintOrder: 0,
            style: .frameSurface, isVisible: true, accessibilityLabel: "Styled frame",
            fillRGBA: [0.9, 0.9, 0.95, 1],
            border: .init(rgba: [0.1, 0.2, 0.8, 1], width: 4, style: .solid),
            cornerRadius: 16,
            shadow: .init(rgba: [0, 0, 0, 0.35], offsetX: 0, offsetY: 8, blur: 8, spread: 1)
        )
        let pixels = rasterizedBytes(object: object, viewport: viewport)
        let center = rgba(at: (x: 120, y: 64), in: pixels, width: 300, height: 120)
        XCTAssertGreaterThan(center.alpha, 240, "Rounded clipping must retain the authored centre fill.")
        let border = rgba(at: (x: 62, y: 60), in: pixels, width: 300, height: 120)
        XCTAssertGreaterThan(border.blue, border.red, "The authored blue border must win at the edge.")
        let roundedCorner = rgba(at: (x: 60, y: 96), in: pixels, width: 300, height: 120)
        XCTAssertLessThan(roundedCorner.alpha, center.alpha, "Uniform radius must clip the object corner.")
        let withoutShadow = CanvasRenderObject(
            id: object.id, frame: object.frame, clipRect: object.clipRect, paintOrder: object.paintOrder,
            style: object.style, isVisible: true, accessibilityLabel: object.accessibilityLabel,
            fillRGBA: object.fillRGBA, opacity: object.opacity, border: object.border,
            cornerRadius: object.cornerRadius
        )
        let shadowOnlyPixels = changedPixels(
            from: rasterizedBytes(object: withoutShadow, viewport: viewport),
            to: pixels, width: 300
        )
        let objectBitmapRect = CGRect(x: 60, y: 24, width: 120, height: 64)
        XCTAssertTrue(
            shadowOnlyPixels.contains { !objectBitmapRect.contains(CGPoint(x: $0.x, y: $0.y)) },
            "The production shadow must paint beyond the authored object without changing its frame."
        )
        XCTAssertEqual(object.frame, frame)
    }

    private func rasterizedBytes(object: CanvasRenderObject, viewport: CanvasViewportState, backingScale: Double = 1, includeText: Bool = false) -> Data {
        let logicalWidth = 300, logicalHeight = 120
        let width = Int(Double(logicalWidth) * backingScale)
        let height = Int(Double(logicalHeight) * backingScale)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { rawBuffer in
            let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.scaleBy(x: backingScale, y: backingScale)
            // Render through the same native layer composition used by the
            // native viewport. Calling tile.draw(in:) directly bypasses
            // CALayer's geometry transform and cannot prove text/clip parity.
            let root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: logicalWidth, height: logicalHeight)
            // `NativeCanvasViewportView` is an `NSView.isFlipped` host. Its
            // root layer establishes top-left coordinates. Owned containers
            // must not reflect their descendants a second time.
            root.isGeometryFlipped = true
            let container = CALayer()
            container.frame = root.bounds
            container.isGeometryFlipped = false
            root.addSublayer(container)
            let layer = CanvasContentTileLayer()
            // A nonzero tile origin proves the unreflected container
            // keeps tile placement and tile-local text/clipping coordinates
            // in the same authored viewport space.
            layer.frame = CGRect(x: 8, y: 12, width: logicalWidth - 8, height: logicalHeight - 12)
            layer.contentsScale = backingScale
            layer.viewportState = viewport
            layer.objects = [object]
            layer.tileOrigin = layer.frame.origin
            container.addSublayer(layer)
            layer.setNeedsDisplay()
            if includeText, let text = CanvasAuthoredTextLayerFactory.makeLayer(for: object,
                viewport: viewport, contentsScale: backingScale) {
                let textContainer = CALayer()
                textContainer.frame = root.bounds
                textContainer.isGeometryFlipped = false
                root.addSublayer(textContainer)
                textContainer.addSublayer(text)
            }
            root.render(in: context)
        }
        return Data(bytes)
    }

    private func rasterizedTextLayerBytes(_ textLayer: CATextLayer, width: Int, height: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { rawBuffer in
            let context = CGContext(
                data: rawBuffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            let root = CALayer()
            root.frame = CGRect(x: 0, y: 0, width: width, height: height)
            root.isGeometryFlipped = true
            root.addSublayer(textLayer)
            textLayer.setNeedsDisplay()
            root.render(in: context)
        }
        return Data(bytes)
    }

    private func changedPixels(from lhs: Data, to rhs: Data, width: Int) -> [(x: Int, y: Int)] {
        precondition(lhs.count == rhs.count)
        let height = lhs.count / (width * 4)
        return stride(from: 0, to: lhs.count, by: 4).compactMap { offset in
            guard lhs[offset..<(offset + 4)] != rhs[offset..<(offset + 4)] else { return nil }
            let pixel = offset / 4
            // CGContext bitmap storage is bottom-up. Convert scanlines back
            // to the renderer's top-left viewport contract before checking
            // authored frame and ancestor-clip bounds.
            return (pixel % width, height - 1 - pixel / width)
        }
    }

    private func pixelBounds(_ pixels: [(x: Int, y: Int)]) -> String {
        guard let first = pixels.first else { return "empty" }
        let bounds = pixels.dropFirst().reduce(
            (minX: first.x, maxX: first.x, minY: first.y, maxY: first.y)
        ) { partial, pixel in
            (
                minX: min(partial.minX, pixel.x),
                maxX: max(partial.maxX, pixel.x),
                minY: min(partial.minY, pixel.y),
                maxY: max(partial.maxY, pixel.y)
            )
        }
        return "x=\(bounds.minX)...\(bounds.maxX), y=\(bounds.minY)...\(bounds.maxY)"
    }

    private func rgba(at point: (x: Int, y: Int), in bytes: Data, width: Int, height: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        precondition((0..<width).contains(point.x) && (0..<height).contains(point.y))
        // Bitmap storage is bottom-up; all test points use the renderer's
        // canonical top-left viewport coordinate space.
        let offset = ((height - 1 - point.y) * width + point.x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }
}
