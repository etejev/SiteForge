import Combine
import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class InsertionModelTests: XCTestCase {
    private func responsiveCardPage() throws -> (CanonicalDocument, [String: NodeID]) {
        var document = ProjectCreation.blank()
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Fixture image", originalFilename: "fixture.png",
            format: .png, pixelWidth: 120, pixelHeight: 64, byteCount: 1, contentHash: String(repeating: "a", count: 64))
        document.imageAssets = [asset]
        let pageID = document.pages[0].id, rootID = document.pages[0].rootNodeIDs[0]
        var nodes: [DocumentNode] = [], ids: [String: NodeID] = [:]
        func property(_ key: String, _ value: PropertyValue) -> NodeProperty {
            .init(key: .init(rawValue: key), value: value, origin: .authored)
        }
        func add(_ name: String, kind: NodeKind, parent: NodeID, width: Double = 1100, height: Double = 600,
                 automatic: Bool = true, extra: [NodeProperty] = []) -> NodeID {
            let id = NodeID(); ids[name] = id
            var properties = [property("layout.x", .number(0)), property("layout.y", .number(0)),
                property("layout.width", .number(width)), property("layout.height", .number(height))] + extra
            if automatic { properties += [property(CanonicalSizingConstraints.prefix + "widthMode", .string("fill")),
                property(CanonicalSizingConstraints.prefix + "heightMode", .string("hug"))] }
            nodes.append(.init(id: id, kind: kind, name: name, parent: .node(parent), properties: properties))
            if let index = nodes.firstIndex(where: { $0.id == parent }) { nodes[index].childIDs.append(id) }
            return id
        }
        func container(_ kind: String, padding: Double, gap: Double) -> [NodeProperty] {
            let common = [property("layout.container.kind", .string(kind)), property("layout.padding", .number(padding))]
            if kind == "section" { return common + [property("layout.axis", .string("vertical"))] }
            if kind == "grid" { return common + [property("layout.gap", .number(gap))] }
            return common + [property("layout.gap", .number(gap)), property("layout.axis", .string("vertical")), property("layout.align", .string("start"))]
        }
        let section = add("Section", kind: .section, parent: rootID,
            extra: container("section", padding: 16, gap: 12) + [property(CanonicalSizingConstraints.prefix + "maxWidth", .number(1100))])
        _ = add("Heading", kind: .text, parent: section, extra: [property("content.text", .string("A useful responsive collection of independent cards"))])
        let grid = add("Cards", kind: .grid, parent: section, extra: container("grid", padding: 8, gap: 16) + [
            property("layout.grid.columns", .number(2)), property("layout.grid.placement", .string("row-major")),
            property(ResponsiveContainerLayoutResolver.key(.columns, breakpoint: .mobile), .number(1))])
        for index in 1...2 {
            let card = add("Card \(index)", kind: .stack, parent: grid, extra: container("stack", padding: 12, gap: 8))
            _ = add("Title \(index)", kind: .text, parent: card,
                extra: [property("content.text", .string("Thoughtful writing with enough words to wrap in a narrower card without moving the authored fallback."))])
            _ = add("Image \(index)", kind: .image, parent: card, width: 120, height: 64, automatic: false, extra: [
                property(CanonicalImageStyle.namespace + "assetID", .string(asset.id.description)),
                property(CanonicalImageStyle.namespace + "fit", .string("fit")),
                property(CanonicalImageStyle.namespace + "alt", .string("Fixture image")),
                property(CanonicalImageStyle.namespace + "decorative", .boolean(false)),
                property(CanonicalImageStyle.namespace + "focal.x", .number(0.5)), property(CanonicalImageStyle.namespace + "focal.y", .number(0.5))])
            _ = add("Button \(index)", kind: .button, parent: card, width: 100, height: 28, automatic: false,
                extra: [property("content.text", .string("Read story"))])
            _ = add("Optional \(index)", kind: .text, parent: card, extra: [property("content.text", .string("Additional detail")),
                property(ResponsiveVisibilityResolver.key(.mobile), .boolean(false))])
        }
        let footer = add("Closing Section", kind: .section, parent: section, extra: container("section", padding: 10, gap: 0))
        _ = add("Closing text", kind: .text, parent: footer, extra: [property("content.text", .string("End of the collection. Content height follows wrapping; fixed image and button dimensions stay intentional."))])
        document.pages[0].nodes[0].childIDs = [section]
        document.pages[0].nodes += nodes
        XCTAssertEqual(document.pages[0].id, pageID)
        try document.validate()
        return (document, ids)
    }

    func testResponsiveCardSubtreeReflowsAtFreeWidthsWithoutRewritingIntent() async throws {
        let (document, ids) = try responsiveCardPage(), page = document.pages[0]
        let before = try DocumentSerializer.encode(document)
        let worker = WorkspaceScenePreparationWorker(), surface = CanvasRenderSurfaceID()
        var firstScene: CanvasRenderSceneSnapshot?
        for width in [320.0, 375, 390, 430, 574, 768, 1024, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let frames = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
            var reordered = page; reordered.nodes.reverse()
            XCTAssertEqual(reordered.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width), frames)
            let section = try XCTUnwrap(frames[ids["Section"]!]), grid = try XCTUnwrap(frames[ids["Cards"]!])
            XCTAssertEqual(section.size.width, min(width, 1100), accuracy: 0.001)
            XCTAssertEqual(grid.size.width, section.size.width - 32, accuracy: 0.001)
            let columns = breakpoint == .mobile ? 1 : 2
            let cell = (grid.size.width - 16 - Double(columns - 1) * 16) / Double(columns)
            for index in 1...2 {
                let card = try XCTUnwrap(frames[ids["Card \(index)"]!]), text = try XCTUnwrap(frames[ids["Title \(index)"]!])
                XCTAssertEqual(card.size.width, cell, accuracy: 0.001)
                XCTAssertEqual(text.size.width, cell - 24, accuracy: 0.001)
                XCTAssertEqual(frames[ids["Image \(index)"]!]?.size, .init(width: 120, height: 64))
                XCTAssertEqual(frames[ids["Button \(index)"]!]?.size, .init(width: 100, height: 28))
                let titleNode = try XCTUnwrap(page.nodes.first { $0.id == ids["Title \(index)"] })
                XCTAssertEqual(text.size.height, ResponsiveTextMetrics.height(text: titleNode.insertionStringProperty("content.text")!,
                    width: text.size.width, typography: .defaultValue), accuracy: 0.001)
                let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
                XCTAssertEqual(visible.contains(ids["Optional \(index)"]!), breakpoint != .mobile)
                let optionalHeight = breakpoint == .mobile ? 0 : try XCTUnwrap(frames[ids["Optional \(index)"]!]).size.height
                XCTAssertEqual(card.size.height, text.size.height + 64 + 28 + optionalHeight + 24 + (breakpoint == .mobile ? 16 : 24), accuracy: 0.001)
            }
            let firstCard = try XCTUnwrap(frames[ids["Card 1"]!]), secondCard = try XCTUnwrap(frames[ids["Card 2"]!])
            XCTAssertEqual(grid.size.height, (columns == 1 ? firstCard.size.height + secondCard.size.height + 16 : max(firstCard.size.height, secondCard.size.height)) + 16, accuracy: 0.001)
            let heading = try XCTUnwrap(frames[ids["Heading"]!]), closing = try XCTUnwrap(frames[ids["Closing Section"]!])
            XCTAssertEqual(section.size.height, heading.size.height + grid.size.height + closing.size.height + 32, accuracy: 0.001)
            XCTAssertEqual(grid.origin.y, heading.frame.maxY, accuracy: 0.001)
            XCTAssertEqual(closing.origin.y, grid.frame.maxY, accuracy: 0.001)
            let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 1200, height: 900),
                contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: width, height: 2000)), pixelRatio: .init(2))
            let prepared = try await worker.prepare(.init(document: document, activePageID: page.id,
                activeContainerID: nil, viewport: viewport, surfaceID: surface, breakpoint: breakpoint, viewportWidth: width))
            for name in ["Section", "Cards", "Card 1", "Title 1", "Closing Section"] {
                let id = ids[name]!
                XCTAssertEqual(prepared.renderScene.objects.first { $0.id == id }?.frame, frames[id]?.frame)
            }
            XCTAssertEqual(prepared.renderScene.objects.contains { $0.id == ids["Optional 1"] }, breakpoint != .mobile)
            if let firstScene { XCTAssertEqual(firstScene.objects.first { $0.id == ids["Section"] }?.frame.size.width, 320) }
            else { firstScene = prepared.renderScene }
        }
        XCTAssertEqual(try DocumentSerializer.encode(document), before)
        let css = ConnectedPageOutput.css(pages: document.pages)
        XCTAssertTrue(css.contains("grid-template-columns:repeat(1,minmax(0,1fr))"))
        XCTAssertTrue(css.contains("height:auto"))
        XCTAssertFalse(css.contains("canvas.grid"))
    }

    func testResponsiveGridNumericDimensionWinnerIsNotReplacedByTrackWidth() throws {
        var (document, ids) = try responsiveCardPage()
        let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == ids["Card 1"] })
        let card = document.pages[0].nodes[index]
        document.pages[0].nodes[index].properties.append(.init(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(180), origin: .authored))
        document.pages[0].nodes[index].properties.append(.init(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.height, breakpoint: .mobile)), value: .number(300), origin: .authored))
        try document.validate()
        let frames = document.pages[0].resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 390)
        XCTAssertEqual(frames[card.id]?.size.width, 180)
        XCTAssertEqual(frames[card.id]?.size.height, 300)
        XCTAssertEqual(frames[ids["Title 1"]!]?.size.width, 156)
        let css = ConnectedPageOutput.css(pages: document.pages)
        let rules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: card.id) + " {") }
        XCTAssertTrue(rules.last?.contains("width:180.0px;") == true)
        XCTAssertFalse(rules.last?.contains("width:100%;") == true)
        var fixed = document
        for i in fixed.pages[0].nodes.indices {
            fixed.pages[0].nodes[i].properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalSizingConstraints.prefix) }
        }
        try fixed.validate()
        let fixedFrames = fixed.pages[0].resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 390)
        XCTAssertEqual(fixedFrames[card.id]?.size, .init(width: 180, height: 300),
            "An explicit breakpoint size also survives legacy fixed Grid track fitting")
    }

    // SF-0501-003/005/006, SF-0502-003/006: connected ownership must
    // not hide its existing fluid spacing editor or expose ignored fixed edits.
    func testManagedSectionFluidPaddingUsesLiveInspectorAndPreservesFlowHistory() async throws {
        let (session, header, bodies, footer) = try connectedPageSession()
        let body = try XCTUnwrap(bodies.first), pageID = session.document.pages[0].id
        let padding = CanonicalFluidValue(minimum: 8, preferred: 16, maximum: 32)
        try session.execute(.setProperty(.init(pageID: pageID, nodeID: body,
            property: .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.padding)),
                value: .string(try CanonicalFluidValueCodec.encode(padding, target: .padding)), origin: .authored))))
        let baseline = session.document.pages
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        func adopt() async {
            let deadline = ContinuousClock.now + .seconds(3)
            while (state.canvasRenderPlan?.identity.revision != session.document.revision
                || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation),
                ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertEqual(state.canvasRenderPlan?.identity.revision, session.document.revision)
            XCTAssertEqual(state.canvasRenderPlan?.identity.viewportGeneration, state.viewportState.generation)
        }
        await adopt(); state.selectLayer(body)
        XCTAssertTrue(state.hasManagedPageStructureSelection)
        XCTAssertEqual(state.supportedFluidValueTargets, [.padding])
        XCTAssertEqual(state.containerLayoutValue(for: .padding),
            .single(.number(32), .authored, applicableCount: 1, skippedCount: 0))
        XCTAssertEqual(state.containerLayoutResponsiveSource(for: .padding), "Fluid responsive value")
        XCTAssertFalse(state.containerLayoutAvailability(for: .padding).isEnabled)
        XCTAssertFalse(state.commitContainerLayout(field: .padding, value: .number(99), provenance: .keyboard))
        XCTAssertEqual(session.document.pages, baseline)
        let desktopScope = state.layoutInspectorDraftScope
        state.reviewBreakpoint(.tablet); await adopt()
        XCTAssertEqual(state.containerLayoutValue(for: .padding),
            .single(.number(16), .authored, applicableCount: 1, skippedCount: 0))
        XCTAssertFalse(state.commitContainerLayout(field: .padding, value: .number(9), provenance: .keyboard,
            draftScope: desktopScope), "A retained Desktop draft cannot become a Tablet override")
        XCTAssertTrue(state.commitContainerLayout(field: .padding, value: .number(10), provenance: .keyboard,
            draftScope: state.layoutInspectorDraftScope))
        await adopt()
        XCTAssertEqual(state.containerLayoutResponsiveSource(for: .padding), "Authored for Tablet")
        XCTAssertTrue(state.commitContainerLayout(field: .padding, value: nil, provenance: .keyboard,
            draftScope: state.layoutInspectorDraftScope))
        await adopt()
        XCTAssertEqual(session.document.pages, baseline)
        XCTAssertEqual(state.containerLayoutResponsiveSource(for: .padding), "Fluid responsive value")
        try session.undo(); await adopt()
        XCTAssertEqual(state.containerLayoutValue(for: .padding),
            .single(.number(10), .authored, applicableCount: 1, skippedCount: 0))
        try session.redo(); await adopt()
        let originalOrder = session.document.pages[0].nodes.first { $0.id == session.document.pages[0].rootNodeIDs[0] }?.childIDs
        try session.execute(pageStructureCommand(.reorder(bodies[1], pointerY: 121),
            document: session.document, selected: bodies[1]))
        let reordered = session.document.pages
        for breakpoint in ResponsiveBreakpoint.allCases {
            let frames = session.document.pages[0].resolvedStructuralGeometry(breakpoint: breakpoint,
                viewportWidth: CanonicalPageFlow.pageWidth(breakpoint, nil))
            XCTAssertLessThan(try XCTUnwrap(frames[header]).origin.y, try XCTUnwrap(frames[bodies[1]]).origin.y)
            XCTAssertLessThan(try XCTUnwrap(frames[bodies[1]]).origin.y, try XCTUnwrap(frames[body]).origin.y)
            XCTAssertLessThan(try XCTUnwrap(frames[body]).origin.y, try XCTUnwrap(frames[footer]).origin.y)
        }
        try session.undo(); XCTAssertEqual(session.document.pages, baseline)
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == session.document.pages[0].rootNodeIDs[0] }?.childIDs, originalOrder)
        try session.redo(); XCTAssertEqual(session.document.pages, reordered)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    // SF-0501-003/005, SF-0502-003/005, SF-0503-003/005, SF-0505-003:
    // real nested widths precede Hug measurement; style/visibility never rewrite
    // fallback geometry, aspect intent, stable children or fluid records.
    func testNestedFluidContainersShareHugConstraintsHiddenChildrenAndOutputGeometry() async throws {
        var (document, ids) = try responsiveCardPage()
        let fluid = CanonicalFluidValue(minimum: 4, preferred: 8, maximum: 16)
        for (name, target) in [("Section", FluidValueTarget.padding), ("Cards", .gap), ("Card 1", .padding)] {
            let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == ids[name] })
            // Each authored record retains its own stable identity.
            let record = CanonicalFluidValue(minimum: fluid.minimum, preferred: fluid.preferred, maximum: fluid.maximum)
            document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: CanonicalFluidValueCodec.key(target)),
                value: .string(try CanonicalFluidValueCodec.encode(record, target: target)), origin: .authored))
        }
        let imageIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == ids["Image 1"] })
        let prefix = CanonicalSizingConstraints.prefix
        document.pages[0].nodes[imageIndex].properties += [
            .init(key: .init(rawValue: prefix + "minWidth"), value: .number(80)),
            .init(key: .init(rawValue: prefix + "maxWidth"), value: .number(160)),
            .init(key: .init(rawValue: prefix + "minHeight"), value: .number(40)),
            .init(key: .init(rawValue: prefix + "maxHeight"), value: .number(100)),
            .init(key: .init(rawValue: prefix + "aspectRatio"), value: .number(120.0 / 64)),
            .init(key: .init(rawValue: prefix + "aspectEnabled"), value: .boolean(true))
        ]
        try document.validate()
        let before = try DocumentSerializer.encode(document), page = document.pages[0]
        let worker = WorkspaceScenePreparationWorker(), surface = CanvasRenderSurfaceID()
        for width in [320.0, 390, 574, 768, 1024, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let frames = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
            let spacing = try XCTUnwrap(fluid.resolved(viewportWidth: width))
            let section = try XCTUnwrap(frames[ids["Section"]!]), grid = try XCTUnwrap(frames[ids["Cards"]!])
            XCTAssertEqual(grid.size.width, section.size.width - 2 * spacing, accuracy: 0.001)
            let columns = breakpoint == .mobile ? 1 : 2
            let track = (grid.size.width - 16 - Double(columns - 1) * spacing) / Double(columns)
            let card = try XCTUnwrap(frames[ids["Card 1"]!]), title = try XCTUnwrap(frames[ids["Title 1"]!])
            XCTAssertEqual(card.size.width, track, accuracy: 0.001)
            XCTAssertEqual(title.size.width, track - 2 * spacing, accuracy: 0.001)
            let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
            let optionalHeight = visible.contains(ids["Optional 1"]!)
                ? try XCTUnwrap(frames[ids["Optional 1"]!]).size.height : 0
            XCTAssertEqual(card.size.height, title.size.height + 64 + 28 + optionalHeight
                + 2 * spacing + (breakpoint == .mobile ? 16 : 24), accuracy: 0.001)
            XCTAssertEqual(frames[ids["Image 1"]!]?.size, .init(width: 120, height: 64))
            let viewport = try CanvasViewportState(worldOrigin: .init(x: -20, y: 12),
                viewportSize: .init(width: 1200, height: 900),
                contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: width, height: 3000)), pixelRatio: .init(2))
            let prepared = try await worker.prepare(.init(document: document, activePageID: page.id,
                activeContainerID: nil, viewport: viewport, surfaceID: surface,
                breakpoint: breakpoint, viewportWidth: width))
            for name in ["Section", "Cards", "Card 1", "Title 1", "Image 1", "Closing Section"] {
                XCTAssertEqual(prepared.renderScene.objects.first { $0.id == ids[name] }?.frame, frames[ids[name]!]?.frame)
            }
            XCTAssertEqual(prepared.renderScene.objects.contains { $0.id == ids["Optional 1"] }, breakpoint != .mobile)
        }
        let reopened = try DocumentSerializer.decode(before)
        XCTAssertEqual(ConnectedPageOutput.css(pages: reopened.pages), ConnectedPageOutput.css(pages: document.pages))
        let css = ConnectedPageOutput.css(pages: document.pages)
        XCTAssertTrue(css.contains("padding:calc(clamp("))
        XCTAssertTrue(css.contains("gap:calc(clamp("))
        XCTAssertTrue(css.contains("height:auto"))
        XCTAssertEqual(try DocumentSerializer.encode(document), before)
        XCTAssertNil(CanonicalPageFlow.role(page.nodes.first { $0.id == ids["Section"] }!),
            "Inspecting existing nested content must not silently convert legacy flow ownership")
    }

    // SF-0603-002/006, SF-0604-002/006: delayed native callbacks may
    // not turn an old draft into an edit of a different visible context.
    func testResponsiveInspectorCapturedContextRejectsSelectionPageRevisionAndBreakpointRetargeting() async throws {
        var (document, ids) = try responsiveCardPage()
        let secondPage = DocumentPage(name: "Other responsive context")
        document.pages.append(secondPage)
        try document.validate()
        let session = DocumentSession(document: document)
        let state = WorkspaceShellState(documentSession: session)
        let live = state.documentSession
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        func adopt() async {
            let deadline = ContinuousClock.now + .seconds(3)
            while (state.canvasRenderPlan?.identity.revision != live.document.revision
                || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation),
                ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertEqual(state.canvasRenderPlan?.identity.revision, live.document.revision)
            XCTAssertEqual(state.canvasRenderPlan?.identity.viewportGeneration, state.viewportState.generation)
        }
        await adopt(); state.selectLayer(ids["Title 1"]!)
        XCTAssertTrue(state.commitFluidValue(.init(minimum: 12, preferred: 16, maximum: 20), target: .fontSize,
            provenance: .keyboard, expectedContext: state.responsiveInspectorEditContext))
        await adopt()
        let desktop = state.responsiveInspectorEditContext
        state.reviewBreakpoint(.mobile); await adopt()
        let before = live.document
        XCTAssertFalse(state.commitFluidValue(.init(minimum: 10, preferred: 14, maximum: 18), target: .fontSize,
            provenance: .focusLoss, expectedContext: desktop))
        XCTAssertEqual(state.fluidValueFailure, .stale)
        XCTAssertFalse(state.commitResponsiveVisibility(false, provenance: .pointer, expectedContext: desktop))
        XCTAssertEqual(live.document, before)
        XCTAssertTrue(state.fluidValueEffectiveSummary(for: .fontSize).contains("Fluid responsive value"))
        let mobile = state.responsiveInspectorEditContext
        state.selectLayer(ids["Title 2"]!)
        XCTAssertFalse(state.commitFluidValue(nil, target: .fontSize, provenance: .pointer, expectedContext: mobile))
        XCTAssertFalse(state.commitResponsiveVisibility(false, provenance: .pointer, expectedContext: mobile))
        XCTAssertEqual(live.document, before)
        XCTAssertEqual(state.currentFluidValueAnnouncement(for: .lineHeight), "Fluid values inactive",
            "Feedback for one property cannot masquerade as another property's result")
        let oldRevision = state.responsiveInspectorEditContext
        let oldText = try XCTUnwrap(live.document.pages[0].nodes.first { $0.id == ids["Title 2"] }?.insertionProperty("content.text"))
        try live.execute(.setProperty(.init(pageID: document.pages[0].id, nodeID: ids["Title 2"]!,
            property: .init(id: oldText.id, key: oldText.key, value: .string("New committed revision")))))
        await adopt()
        let revised = live.document
        XCTAssertEqual(oldRevision.scope, state.responsiveInspectorEditContext.scope)
        XCTAssertFalse(state.commitFluidValue(.init(minimum: 10, preferred: 14, maximum: 18), target: .fontSize,
            provenance: .focusLoss, expectedContext: oldRevision))
        XCTAssertFalse(state.commitResponsiveVisibility(false, provenance: .pointer, expectedContext: oldRevision))
        XCTAssertEqual(live.document, revised)
        let oldPage = state.responsiveInspectorEditContext
        state.selectPage(secondPage.id); await adopt()
        XCTAssertFalse(state.commitFluidValue(nil, target: .fontSize, provenance: .pointer, expectedContext: oldPage))
        XCTAssertFalse(state.commitResponsiveVisibility(false, provenance: .pointer, expectedContext: oldPage))
        XCTAssertEqual(live.document, revised)
        let replacement = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        let replacementBefore = replacement.documentSession.document
        XCTAssertFalse(replacement.commitFluidValue(nil, target: .fontSize, provenance: .pointer, expectedContext: oldPage))
        XCTAssertFalse(replacement.commitResponsiveVisibility(false, provenance: .pointer, expectedContext: oldPage))
        XCTAssertEqual(replacement.documentSession.document, replacementBefore)
    }

    // SF-0603-003/005, SF-0604-003/005: a hidden container removes
    // descendants from layout/render participation, not from canonical ownership.
    func testHiddenResponsiveFluidTextKeepsRendererOutputAndLayoutParticipationConsistent() async throws {
        var (document, ids) = try responsiveCardPage()
        let sectionIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == ids["Section"] })
        document.pages[0].nodes[sectionIndex].properties.append(.init(
            key: .init(rawValue: CanonicalPageFlow.roleKey), value: .string("body")))
        let font = CanonicalFluidValue(minimum: 12, preferred: 16, maximum: 20)
        let line = CanonicalFluidValue(minimum: 18, preferred: 24, maximum: 30)
        for name in ["Title 1", "Title 2"] {
            let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == ids[name] })
            for (target, value) in [(FluidValueTarget.fontSize, font), (.lineHeight, line)] {
                let record = CanonicalFluidValue(minimum: value.minimum, preferred: value.preferred, maximum: value.maximum)
                document.pages[0].nodes[index].properties.append(.init(
                    key: .init(rawValue: CanonicalFluidValueCodec.key(target)),
                    value: .string(try CanonicalFluidValueCodec.encode(record, target: target)), origin: .authored))
            }
        }
        try document.validate()
        let session = DocumentSession(document: document), card = ids["Card 1"]!, scene = CanvasViewportSceneID()
        func visibility(_ visible: Bool?) throws -> DocumentCommand {
            let current = session.document
            let context = TransformValidationContext(activePageID: current.pages[0].id, currentSceneID: scene,
                rendererGeneration: current.revision, selectedNodeIDs: [card],
                availableNodeIDs: Set(current.pages[0].nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil)
            return try ResponsiveVisibilityCommandRegistry().prepare(.init(identity: .init(editID: GeometryInspectorEditID(),
                documentID: current.id, pageID: current.pages[0].id, revision: current.revision,
                sceneID: scene, rendererGeneration: current.revision), orderedNodeIDs: [card], breakpoint: .mobile,
                visible: visible, provenance: .keyboard, cancelled: false), in: current, context: context).documentCommand
        }
        try session.execute(try visibility(false))
        let hidden = session.document, worker = WorkspaceScenePreparationWorker(), surface = CanvasRenderSurfaceID()
        for width in [390.0, 599, 600, 768, 1023, 1024, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width), page = hidden.pages[0]
            let frames = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
            let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 1000, height: 800),
                contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: width, height: 3000)), pixelRatio: .init(2))
            let prepared = try await worker.prepare(.init(document: hidden, activePageID: page.id, activeContainerID: nil,
                viewport: viewport, surfaceID: surface, breakpoint: breakpoint, viewportWidth: width))
            for name in ["Card 1", "Title 1", "Image 1", "Button 1", "Optional 1"] {
                XCTAssertEqual(prepared.renderScene.objects.contains { $0.id == ids[name] }, breakpoint != .mobile)
            }
            let text = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == ids["Title 2"] })
            XCTAssertEqual(text.frame, frames[ids["Title 2"]!]?.frame)
            XCTAssertEqual(try XCTUnwrap(text.typography).size, try XCTUnwrap(font.resolved(viewportWidth: width)), accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(text.typography).lineHeight, try XCTUnwrap(line.resolved(viewportWidth: width)), accuracy: 0.001)
            if breakpoint == .mobile {
                let grid = try XCTUnwrap(frames[ids["Cards"]!]), remaining = try XCTUnwrap(frames[ids["Card 2"]!])
                XCTAssertEqual(remaining.origin.y, grid.origin.y + 8, accuracy: 0.001)
            }
        }
        let plan = try MultiPageStaticBuildPlanner.plan(document: hidden)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let cardRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: card) + " {") }
        XCTAssertTrue(cardRules.last?.contains("display:none") == true)
        XCTAssertTrue(css.contains("font-size: clamp(12px"))
        XCTAssertTrue(css.contains("line-height: clamp(18px"))
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: DocumentSerializer.decode(DocumentSerializer.encode(hidden))).files, plan.files)
        XCTAssertEqual(hidden.pages[0].nodes.map(\.id), document.pages[0].nodes.map(\.id))
        XCTAssertEqual(hidden.imageAssets, document.imageAssets)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(hidden)), hidden)
        try session.undo(); XCTAssertEqual(session.document.pages, document.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, hidden.pages)
        try session.execute(try visibility(nil))
        XCTAssertEqual(session.document.pages, document.pages)
    }

    func testConnectedResponsiveFluidDimensionsAndGapRemainContinuousBetweenPresets() throws {
        var (document, ids) = try responsiveCardPage()
        let cardID = ids["Card 1"]!, gridID = ids["Cards"]!
        let cardIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == cardID })
        let gridIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == gridID })
        let fluidWidth = CanonicalFluidValue(minimum: 150, preferred: 210, maximum: 300)
        let fluidGap = CanonicalFluidValue(minimum: 8, preferred: 16, maximum: 24)
        document.pages[0].nodes[cardIndex].properties.append(.init(key: .init(rawValue: CanonicalFluidValueCodec.key(.width)),
            value: .string(try CanonicalFluidValueCodec.encode(fluidWidth, target: .width))))
        document.pages[0].nodes[gridIndex].properties.append(.init(key: .init(rawValue: CanonicalFluidValueCodec.key(.gap)),
            value: .string(try CanonicalFluidValueCodec.encode(fluidGap, target: .gap))))
        try document.validate()
        let before = document
        for width in [320.0, 375, 390, 430, 574, 768, 1024, 1440] {
            let frames = document.pages[0].resolvedStructuralGeometry(breakpoint: .resolving(width: width), viewportWidth: width)
            let actual = try XCTUnwrap(frames[cardID])
            XCTAssertEqual(actual.size.width, try XCTUnwrap(fluidWidth.resolved(viewportWidth: width)), accuracy: 0.0001)
            XCTAssertEqual(try XCTUnwrap(frames[ids["Title 1"]!]).size.width, actual.size.width - 24, accuracy: 0.0001)
            let grid = try XCTUnwrap(frames[gridID]), columns = width < 600 ? 1 : 2
            let gap = try XCTUnwrap(fluidGap.resolved(viewportWidth: width))
            XCTAssertEqual(try XCTUnwrap(frames[ids["Card 2"]!]).size.width,
                (grid.size.width - 16 - Double(columns - 1) * gap) / Double(columns), accuracy: 0.0001)
        }
        let css = ConnectedPageOutput.css(pages: document.pages)
        let cardRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: cardID) + " {") }
        let gridRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: gridID) + " {") }
        XCTAssertEqual(cardRules.count, 3)
        XCTAssertTrue(cardRules.allSatisfy { $0.contains("width:calc(clamp(") })
        XCTAssertTrue(gridRules.allSatisfy { $0.contains("gap:calc(clamp(") })
        document.pages[0].nodes[cardIndex].properties.append(.init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(180)))
        let overriddenCSS = ConnectedPageOutput.css(pages: document.pages)
        let overriddenRules = overriddenCSS.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: cardID) + " {") }
        XCTAssertTrue(overriddenRules.last?.contains("width:180.0px;") == true)
        XCTAssertFalse(overriddenRules.last?.contains("width:calc(clamp(") == true)
        XCTAssertEqual(before.pages[0].nodes[cardIndex].insertionNumberProperty("layout.width"), 1100)
        XCTAssertNil(StaticFluidValueOutputEmitter.expression(for: .init(minimum: 300, preferred: 100, maximum: 200)))
    }

    func testSizingInspectorShowsWinningOverrideAndRejectsDraftFromPreviousBreakpoint() async throws {
        var (document, ids) = try responsiveCardPage()
        let cardID = ids["Card 1"]!, pageID = document.pages[0].id
        let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == cardID })
        let override = NodeProperty(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(180))
        document.pages[0].nodes[index].properties.append(override)
        let fixture = try ApplicationOwnedTestFixture.create("sizing-inspector-adoption")
        defer { try? fixture.cleanup() }
        let session = DocumentSession(document: document)
        let lifecycle = DocumentLifecycleController(session: session,
            recoveryDirectory: fixture.url.appendingPathComponent("recovery"), autosaveDebouncer: ManualLifecycleAutosaveDebouncer())
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        func waitForAdoption() async {
            let deadline = ContinuousClock.now + .seconds(3)
            while (state.canvasRenderPlan?.identity.revision != session.document.revision
                || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation), ContinuousClock.now < deadline { await Task.yield() }
            XCTAssertEqual(state.canvasRenderPlan?.identity.revision, session.document.revision)
            XCTAssertEqual(state.canvasRenderPlan?.identity.viewportGeneration, state.viewportState.generation)
        }
        await waitForAdoption()
        state.selectLayer(cardID)
        XCTAssertEqual(state.selectionState.orderedIDs, [cardID])
        XCTAssertTrue(state.sizingModeSource(for: .width).contains("Effective Fill"))
        let desktopScope = state.layoutInspectorDraftScope
        state.reviewBreakpoint(.mobile)
        await waitForAdoption()
        XCTAssertTrue(state.sizingModeSource(for: .width).contains("Effective Fixed"))
        XCTAssertTrue(state.sizingModeSource(for: .width).contains("Mobile"))
        let before = session.document
        XCTAssertFalse(state.commitGeometryInspectorValue(999, field: .width, provenance: .keyboard, draftScope: desktopScope))
        XCTAssertFalse(state.commitSizingConstraint(.setMode(.width, .fixed), draftScope: desktopScope))
        XCTAssertEqual(session.document, before)
        XCTAssertTrue(state.resetSizingDimensionOverride(.width, expectedScope: state.layoutInspectorDraftScope))
        await waitForAdoption()
        XCTAssertTrue(state.sizingModeSource(for: .width).contains("Effective Fill"))
        XCTAssertNil(session.document.pages[0].nodes[index].insertionProperty(override.key.rawValue))
        XCTAssertEqual(session.document.pages[0].nodes[index].insertionGeometry, document.pages[0].nodes[index].insertionGeometry)
        XCTAssertEqual(session.document.pages[0].id, pageID)
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes[index].insertionProperty(override.key.rawValue), override)
    }

    // SF-0502-003/005, SF-0602-003/005, SF-1201-003: changing
    // flex direction must not reinterpret a Desktop width as Mobile height.
    func testHugStackBreakpointOutputResetsFlexBasisAndPreservesButtonLabelAlignment() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = NodeID(), stackID = NodeID(), buttonID = NodeID()
        func property(_ key: String, _ value: PropertyValue) -> NodeProperty {
            .init(key: .init(rawValue: key), value: value, origin: .authored)
        }
        let stack = DocumentNode(id: stackID, kind: .stack, name: "Actions", parent: .node(rootID), childIDs: [buttonID], properties: [
            property("layout.x", .number(0)), property("layout.y", .number(0)),
            property("layout.width", .number(580)), property("layout.height", .number(64)),
            property("layout.container.kind", .string("stack")), property("layout.axis", .string("horizontal")),
            property("layout.align", .string("center")),
            property("layout.padding", .number(0)), property("layout.gap", .number(24)),
            property(CanonicalSizingConstraints.prefix + "widthMode", .string("fill")),
            property(CanonicalSizingConstraints.prefix + "heightMode", .string("hug")),
            property(ResponsiveContainerLayoutResolver.key(.axis, breakpoint: .mobile), .string("vertical"))])
        let button = DocumentNode(id: buttonID, kind: .button, name: "Action", parent: .node(stackID), properties: [
            property("layout.x", .number(0)), property("layout.y", .number(0)),
            property("layout.width", .number(260)), property("layout.height", .number(64)),
            property("content.label", .string("Explore Journal"))])
        let root = DocumentNode(id: rootID, kind: .frame, name: "Root", parent: .page(pageID), childIDs: [stackID], properties: [
            property("layout.x", .number(0)), property("layout.y", .number(0)),
            property("layout.width", .number(1440)), property("layout.height", .number(800)),
            property(CanonicalSizingConstraints.prefix + "heightMode", .string("hug"))])
        document.pages[0].nodes = [root, stack, button]
        document.pages[0].rootNodeIDs = [rootID]
        try document.validate()
        let before = document
        let css = ConnectedPageOutput.css(pages: document.pages)
        let rules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: buttonID) + " {") }
        XCTAssertEqual(rules.count, 3)
        XCTAssertTrue(rules.allSatisfy { $0.contains("display:flex;") && $0.contains("height:64.0px;") }, css)
        XCTAssertTrue(rules[0].contains("flex:0 0 260.0px;"), css)
        XCTAssertTrue(rules[1].contains("flex:0 0 260.0px;"), css)
        XCTAssertTrue(rules[2].contains("flex:0 0 auto;"), "Mobile must reset the inherited Desktop flex-basis: \(css)")
        let rootRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: rootID) + " {") }
        XCTAssertEqual(rootRules.count, 3)
        XCTAssertTrue(rootRules.allSatisfy { $0.contains("grid-template-rows:max-content;") && $0.contains("align-content:start;") },
            "An opt-in free Frame must hug the width-resolved content, not Safari's earlier intrinsic auto track")
        for width in [320.0, 390, 768, 1440] {
            let frames = document.pages[0].resolvedStructuralGeometry(breakpoint: .resolving(width: width), viewportWidth: width)
            XCTAssertEqual(try XCTUnwrap(frames[buttonID]).size.height, 64)
        }
        XCTAssertEqual(document, before)
    }

    func testResponsiveFillAndHugUseContainingWidthAndPropagateWrappedHeightWithoutMutatingIntent() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = NodeID(), stackID = NodeID(), headingID = NodeID(), copyID = NodeID()
        func property(_ key: String, _ value: PropertyValue) -> NodeProperty {
            .init(key: .init(rawValue: key), value: value, origin: .authored)
        }
        func geometry(_ width: Double, _ height: Double) -> [NodeProperty] {
            [property("layout.x", .number(0)), property("layout.y", .number(0)),
             property("layout.width", .number(width)), property("layout.height", .number(height))]
        }
        let prefix = CanonicalSizingConstraints.prefix
        let heading = DocumentNode(id: headingID, kind: .text, name: "Heading", parent: .node(stackID),
            properties: geometry(1100, 280) + [property("content.text", .string("Thoughtful writing for a curious world.")),
                property(CanonicalTypography.namespace + "size", .number(40)),
                property(CanonicalTypography.namespace + "lineHeight", .number(48)),
                property(prefix + "widthMode", .string("fill")), property(prefix + "heightMode", .string("hug"))])
        let copy = DocumentNode(id: copyID, kind: .text, name: "Copy", parent: .node(stackID),
            properties: geometry(1100, 120) + [property("content.text", .string("Essays and perspectives on design, culture, and the places that shape us.")),
                property(prefix + "widthMode", .string("fill")), property(prefix + "heightMode", .string("hug"))])
        let stack = DocumentNode(id: stackID, kind: .stack, name: "Content", parent: .node(rootID),
            childIDs: [headingID, copyID], properties: geometry(1100, 600) + [
                property("layout.container.kind", .string("stack")),
                property("layout.padding", .number(24)), property("layout.gap", .number(16)),
                property("layout.axis", .string("vertical")), property("layout.align", .string("start")),
                property(prefix + "maxWidth", .number(1100)), property(prefix + "widthMode", .string("fill")),
                property(prefix + "heightMode", .string("hug"))])
        let root = DocumentNode(id: rootID, kind: .frame, name: "Root", parent: .page(pageID), childIDs: [stackID])
        document.pages[0].nodes = [root, stack, heading, copy]
        document.pages[0].rootNodeIDs = [rootID]
        try document.validate()
        let before = document
        let originalIDs = document.pages[0].nodes.map(\.id)
        var previousHeight = Double.greatestFiniteMagnitude
        var reordered = document
        reordered.pages[0].nodes.reverse()
        for width in [320.0, 375, 390, 430, 574, 768, 1024, 1440] {
            let frames = document.pages[0].resolvedStructuralGeometry(breakpoint: .resolving(width: width), viewportWidth: width)
            XCTAssertEqual(reordered.pages[0].resolvedStructuralGeometry(breakpoint: .resolving(width: width), viewportWidth: width), frames,
                "Canonical child ownership, not incidental storage order, determines responsive layout")
            let parent = try XCTUnwrap(frames[stackID]), title = try XCTUnwrap(frames[headingID]), body = try XCTUnwrap(frames[copyID])
            XCTAssertEqual(parent.size.width, min(width, 1100), accuracy: 0.001)
            XCTAssertEqual(title.size.width, parent.size.width - 48, accuracy: 0.001)
            XCTAssertEqual(body.origin.y, title.frame.maxY + 16, accuracy: 0.001)
            XCTAssertEqual(parent.size.height, title.size.height + body.size.height + 48 + 16, accuracy: 0.001)
            XCTAssertLessThanOrEqual(parent.size.height, previousHeight)
            XCTAssertLessThan(parent.size.height, 600)
            previousHeight = parent.size.height
        }
        XCTAssertEqual(document, before)
        XCTAssertEqual(document.pages[0].nodes.map(\.id), originalIDs)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
        let css = ConnectedPageOutput.css(pages: document.pages)
        XCTAssertTrue(css.contains("height:auto"))
        XCTAssertTrue(css.contains("flex-direction:column"))
        XCTAssertTrue(css.contains("position:relative;box-sizing:border-box"), css)
        XCTAssertTrue(css.contains("padding-inline:4px"))
        let stackRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: stackID) + " {") }
        XCTAssertTrue(stackRules.allSatisfy { $0.contains("calc(100% - 0.0px)") },
            "An unpadded free Frame must not acquire structural default padding only in browser output")
        XCTAssertTrue(document.pages[0].usesConnectedOutput)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(document)) as? [String: Any])
        historical["schemaVersion"] = 18
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical)))
        var overridden = document
        overridden.pages[0].nodes[2].properties.append(property(
            ResponsiveGeometryResolver.key(.height, breakpoint: .mobile), .number(280)))
        XCTAssertEqual(overridden.pages[0].resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 390)[headingID]?.size.height, 280)
    }

    func testConnectedHugHeightUsesResolvedInspectorAndRejectsFallbackMutation() async throws {
        let (session, _, bodies, _) = try connectedPageSession()
        let body = try XCTUnwrap(bodies.first)
        let pageID = session.document.pages[0].id
        try session.execute(.setProperty(.init(pageID: pageID, nodeID: body,
            property: .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "heightMode"),
                value: .string("hug"), origin: .authored))))
        let before = session.document
        XCTAssertThrowsError(try pageStructureCommand(.height(body, 500, .desktop), document: before, selected: body))
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        let ready = ContinuousClock.now + .seconds(3)
        while !state.layerTargets.contains(where: { $0.id == body }), ContinuousClock.now < ready { await Task.yield() }
        state.selectLayer(body)
        let deadline = ContinuousClock.now + .seconds(3)
        while state.resolvedSelectedGeometrySummary == nil, ContinuousClock.now < deadline { await Task.yield() }
        let object = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == body })
        guard case .computed(let height, _) = state.geometryInspectorValue(for: .height) else {
            return XCTFail("The Inspector must expose computed Hug height, not the stored fallback")
        }
        XCTAssertEqual(height, object.frame.size.height)
        XCTAssertEqual(state.transformGeometrySummary, state.resolvedSelectedGeometrySummary)
        XCTAssertFalse(state.geometryInspectorAvailability(for: .height).isEnabled)
        XCTAssertEqual(session.document, before)
        try session.execute(pageStructureCommand(.height(body, 240, .mobile), document: session.document,
            selected: body, breakpoint: .mobile))
        let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == body })
        XCTAssertEqual(CanonicalSizingConstraints.effectiveMode(.height, node: node, breakpoint: .mobile, width: 390), .fixed)
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: node).heightMode, .hug)
        try session.undo()
        XCTAssertEqual(session.document.pages, before.pages)
    }

    // SF-0501-003, SF-1201-003, SF-1204-003: the browser must not borrow
    // the legacy leading default or a stored fixed navigation width when
    // native editable Header/Footer layout gives it the remaining row.
    func testAutomaticChromeNavigationSharesTrailingDefaultAndRemainingWidthWithStaticOutput() throws {
        let (session, headerID, _, footerID) = try connectedPageSession()
        let document = session.document
        let page = document.pages[0]
        let css = ConnectedPageOutput.css(pages: [page])
        for ownerID in [headerID, footerID] {
            let owner = try XCTUnwrap(page.nodes.first { $0.id == ownerID })
            let navigationID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner))
            let navigation = try XCTUnwrap(page.nodes.first { $0.id == navigationID })
            let contentID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner))
            let contentRules = css.components(separatedBy: "\n").filter {
                $0.hasPrefix(CanonicalCSSRule.selector(for: contentID) + " {")
            }
            XCTAssertFalse(contentRules.isEmpty)
            XCTAssertTrue(contentRules.allSatisfy { $0.contains("width:max(1px,calc(100% - ") },
                          "Managed chrome content must fill the same padded owner width as native layout")
            XCTAssertEqual(CanonicalPageChrome.navigationAlignment(surface: navigation, settings: owner), "end")
            for breakpoint in ResponsiveBreakpoint.allCases {
                let snapshot = try XCTUnwrap(CanonicalPageFlow.navigation(owner: owner, page: page,
                    document: document, breakpoint: breakpoint))
                XCTAssertEqual(snapshot.alignment, "end")
            }
            let selector = CanonicalCSSRule.selector(for: navigationID)
            let navigationRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(selector + " {") }
            XCTAssertFalse(navigationRules.isEmpty)
            XCTAssertTrue(navigationRules.allSatisfy { $0.contains("width:auto;") && $0.contains("flex:1 1 0px;") })
            XCTAssertTrue(css.contains(".sf-page-navigation-\(navigationID) .sf-nav-inline { gap:"))
            XCTAssertTrue(css.contains("justify-content:flex-end"))
        }
        XCTAssertEqual(session.document, document, "Output projection cannot rewrite canonical authored geometry")
    }

    // SF-0501-003, SF-0507-003, SF-0806-003, SF-1201-003: derived menu
    // chrome resolves the same typed color context in native and shared output.
    func testDarkNavigationSharesAuthoredForegroundAndOpaqueSurfaceWithoutMutation() async throws {
        let fixture = makeFixture()
        var initial = fixture.document
        initial.pages[0].nodes.removeAll { $0.id == fixture.textParentID }
        initial.pages[0].nodes[0].childIDs.removeAll { $0 == fixture.textParentID }
        let session = DocumentSession(document: initial)
        let pageID = initial.pages[0].id
        let addition = try PageCommandRegistry().prepare(.create(name: "Journal", route: "/journal"),
            identity: .init(documentID: initial.id, revision: initial.revision, pageID: pageID),
            in: initial, isAvailable: true)
        try session.execute(addition.command)
        let headerID = NodeID()
        let current = fixture.with(document: session.document)
        let insertion = command(.section, fixture: current, nodeID: headerID,
            geometry: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 120)), provenance: .menu)
        try session.execute(InsertionCommandRegistry().prepare(insertion, in: session.document,
            context: current.context, template: .header).documentCommand)
        var document = session.document
        let dark = CanonicalSolidColor(red: 16.0 / 255, green: 11.0 / 255, blue: 28.0 / 255, alpha: 1)
        let white = CanonicalSolidColor(red: 250.0 / 255, green: 247.0 / 255, blue: 1, alpha: 1)
        let surfaceToken = LocalColorToken(name: "Surface", color: dark)
        let textToken = LocalColorToken(name: "Foreground", color: white)
        document.colorTokens = [surfaceToken, textToken]
        let ownerIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == headerID })
        document.pages[0].nodes[ownerIndex].properties.removeAll { $0.key.rawValue.hasPrefix("style.fill") }
        document.pages[0].nodes[ownerIndex].properties += CanonicalFillLayerCodec.propertyValues(for: [
            .solid(id: FillLayerID(), color: .legacySurface)
        ]).map { .init(key: .init(rawValue: $0.0), value: $0.1, origin: .authored) }
        document.pages[0].nodes[ownerIndex].properties.append(.init(
            key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)), value: .string(surfaceToken.id.description)))
        let owner = document.pages[0].nodes[ownerIndex]
        let links = CanonicalPageChrome.links(owner: owner, page: document.pages[0])
        XCTAssertEqual(links.count, 2)
        for link in links {
            let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == link.id })
            document.pages[0].nodes[index].properties += CanonicalTextForeground.values(white).map {
                .init(key: .init(rawValue: $0.0), value: $0.1, origin: .authored)
            }
            document.pages[0].nodes[index].properties.append(.init(
                key: .init(rawValue: LocalColorTokenBinding.key(for: .textForeground)), value: .string(textToken.id.description)))
        }
        try document.validate()
        let before = try DocumentSerializer.encode(document)
        let page = document.pages[0]
        let navID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner))
        let nav = try XCTUnwrap(page.nodes.first { $0.id == navID })
        XCTAssertEqual(CanonicalPageChrome.navigationForeground(surface: nav, page: page, tokens: document.colorTokens), white)
        XCTAssertEqual(CanonicalPageChrome.opaqueNavigationSurface(surface: nav, page: page, tokens: document.colorTokens), dark)
        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains(".sf-page-navigation-\(navID) .sf-nav-menu > summary { color:#FAF7FFFF; }"))
        XCTAssertTrue(css.contains(".sf-page-navigation-\(navID) .sf-nav-menu[open] nav { background:#100B1CFF; }"))
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        for link in links {
            let selector = "[data-siteforge-nav-link=\"\(link.id)\"]"
            let rule = try XCTUnwrap(css.components(separatedBy: "\n").first { $0.contains(selector + " {") })
            XCTAssertTrue(rule.contains("color: rgba(250.0, 247.0, 255.0, 1.0);"))
            XCTAssertEqual(html.components(separatedBy: "data-siteforge-nav-link=\"\(link.id)\"").count - 1, 2,
                "Inline and collapsed copies share authored text styling, not absolute node geometry")
            XCTAssertFalse(html.contains("data-siteforge-node=\"\(link.id)\""))
        }
        let viewport = try CanvasViewportState(viewportSize: .init(width: 1000, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 390, height: 900)), pixelRatio: .init(2))
        let scene = try await WorkspaceScenePreparationWorker().prepare(.init(document: document,
            activePageID: pageID, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID(),
            breakpoint: .mobile, viewportWidth: 390))
        let menu = try XCTUnwrap(scene.renderScene.objects.first { $0.id == navID })
        XCTAssertEqual(menu.plainText, "☰ Menu")
        XCTAssertEqual(menu.typography?.foregroundRGBA, [white.red, white.green, white.blue, white.alpha])
        let resolved = ConnectedPageLayoutSnapshot(page: page, breakpoint: .mobile, width: 390)
        XCTAssertEqual(menu.frame, resolved.frames[navID]?.frame)
        XCTAssertEqual(try DocumentSerializer.encode(document), before)
        var mixed = document
        let mixedIndex = try XCTUnwrap(mixed.pages[0].nodes.firstIndex { $0.id == links[0].id })
        mixed.pages[0].nodes[mixedIndex].properties.removeAll {
            $0.key.rawValue.hasPrefix(CanonicalTextForeground.prefix)
                || $0.key.rawValue == LocalColorTokenBinding.key(for: .textForeground)
        }
        mixed.pages[0].nodes[mixedIndex].properties += CanonicalTextForeground.values(.init(red: 0, green: 0, blue: 0, alpha: 1)).map {
            .init(key: .init(rawValue: $0.0), value: $0.1, origin: .authored)
        }
        XCTAssertNil(CanonicalPageChrome.uniformNavigationTextSource(surface: nav, page: mixed.pages[0], tokens: mixed.colorTokens))
        XCTAssertEqual(CanonicalPageChrome.navigationForeground(surface: nav, page: mixed.pages[0], tokens: mixed.colorTokens),
            .init(red: 1, green: 1, blue: 1, alpha: 1), "Mixed links use readable surface contrast, not the first black link")
    }

    // SF-0205-002/003/004 — discovery cannot change catalogue order or
    // accidentally turn an unavailable element into an insertion command.
    func testElementCatalogSearchPreservesOrderCategoriesAndAvailability() {
        let all = ElementCatalogItem.allCases
        XCTAssertEqual(ElementCatalogSearchPolicy.results(in: all, query: " \n "), all)
        XCTAssertEqual(ElementCatalogSearchPolicy.results(in: all, query: " STACK "), [.stack])
        XCTAssertEqual(
            ElementCatalogSearchPolicy.results(in: all, query: "layout"),
            [.section, .stack, .grid, .frame]
        )
        XCTAssertEqual(ElementCatalogSearchPolicy.results(in: all, query: "navigation"), [.navbar])
        XCTAssertTrue(ElementCatalogSearchPolicy.results(in: all, query: "no matching element").isEmpty)
        XCTAssertEqual(ElementCatalogItem.divider.availability, .available(.frame))
        XCTAssertEqual(ElementCatalogItem.header.availability, .available(.section))
        XCTAssertEqual(ElementCatalogItem.navbar.availability, .available(.section))
        XCTAssertEqual(ElementCatalogItem.footer.availability, .available(.section))
        XCTAssertEqual(ElementCatalogItem.input.category, "Forms")
        XCTAssertEqual(ElementCatalogItem.input.template, .input)
        XCTAssertEqual(
            ElementCatalogSearchPolicy.results(in: all, query: "forms"),
            [.input, .emailInput, .textArea, .checkbox, .selectField, .submit]
        )
        XCTAssertEqual(all, ElementCatalogItem.allCases)
    }

    // SF-AUTHORING-091–095: every supported field template shares the Form-
    // owned Text model, deterministic metadata, history, and safe output.
    func testFormFieldTemplatesPreserveKindsOptionsHistoryAndSafeOutput() throws {
        let fixture = makeFixture()
        let formID = NodeID(UUID(uuidString: "63000000-0000-4000-8000-000000000001")!)
        let form = try prepare(.form, fixture: fixture, nodeID: formID)
        let session = DocumentSession(document: fixture.document)
        try session.execute(form.documentCommand)
        let templates: [AuthoringElementTemplate] = [
            .emailInput, .textArea, .checkbox, .selectField, .submit,
        ]
        var insertedIDs: [NodeID] = []
        for (offset, template) in templates.enumerated() {
            let current = fixture.with(document: session.document)
            let id = NodeID()
            let geometry = InsertionGeometry(origin: .init(x: 20, y: 30), size: template.size)
            let invalid = command(.text, fixture: current, nodeID: id,
                                  parentID: current.rootID, geometry: geometry)
            XCTAssertThrowsError(try InsertionCommandRegistry().prepare(invalid,
                in: current.document, context: current.context, template: template)) { error in
                XCTAssertEqual(error as? InsertionError, .formParentRequired)
            }
            let operation = command(.text, fixture: current, nodeID: id,
                                    parentID: formID, index: offset, geometry: geometry)
            let prepared = try InsertionCommandRegistry().prepare(operation,
                in: current.document, context: current.context, template: template)
            XCTAssertEqual(prepared.node.id, id)
            XCTAssertEqual(prepared.node.kind, .text)
            XCTAssertEqual(prepared.node.parent, .node(formID))
            XCTAssertEqual(prepared.node.name, template.displayName)
            XCTAssertEqual(prepared.geometry.size, template.size)
            XCTAssertEqual(prepared.node.insertionStringProperty(CanonicalFormField.kindKey),
                           template.formFieldKind?.rawValue)
            XCTAssertEqual(prepared.node.insertionStringProperty(CanonicalFormField.labelKey),
                           template.displayName)
            XCTAssertEqual(prepared.node.insertionProperty(CanonicalFormField.requiredKey)?.value,
                           .boolean(false))
            if template == .selectField {
                let encoded = try XCTUnwrap(
                    prepared.node.insertionStringProperty(CanonicalFormField.optionsKey)
                )
                let options = try CanonicalFormSelectOptions.decode(encoded)
                XCTAssertEqual(options.map(\.label), ["Option 1", "Option 2"])
                XCTAssertEqual(options.map(\.value), ["option-1", "option-2"])
                let repeated = try InsertionCommandRegistry().prepare(operation,
                    in: current.document, context: current.context, template: template)
                XCTAssertEqual(repeated.node.insertionStringProperty(CanonicalFormField.optionsKey), encoded)
            } else {
                XCTAssertNil(prepared.node.insertionProperty(CanonicalFormField.optionsKey))
            }
            try session.execute(prepared.documentCommand)
            insertedIDs.append(id)
            XCTAssertNoThrow(try session.document.validate())
        }
        let page = session.document.pages[0]
        XCTAssertEqual(page.nodes.first { $0.id == formID }?.childIDs, insertedIDs)
        let tree = try InternalDocumentRenderTreeCompiler.compile(
            page: page, documentID: session.document.id, revision: session.document.revision
        )
        let output = try SafeHTMLEmitter.emit(tree)
        XCTAssertTrue(output.contains("type=\"email\""))
        XCTAssertTrue(output.contains("<textarea"))
        XCTAssertTrue(output.contains("type=\"checkbox\""))
        XCTAssertTrue(output.contains("<select") && output.contains("option-2"))
        XCTAssertTrue(output.contains("type=\"submit\" disabled aria-disabled=\"true\""))
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened, session.document)
        let reopenedSelect = try XCTUnwrap(reopened.pages[0].nodes.first {
            $0.insertionStringProperty(CanonicalFormField.kindKey) == FormFieldKind.select.rawValue
        })
        XCTAssertEqual(
            try CanonicalFormSelectOptions.decode(try XCTUnwrap(
                reopenedSelect.insertionStringProperty(CanonicalFormField.optionsKey)
            )).map(\.id),
            try CanonicalFormSelectOptions.decode(try XCTUnwrap(
                session.document.pages[0].nodes.first { $0.id == reopenedSelect.id }?
                    .insertionStringProperty(CanonicalFormField.optionsKey)
            )).map(\.id)
        )
        for expectedCount in stride(from: templates.count - 1, through: 0, by: -1) {
            try session.undo()
            let children = session.document.pages[0].nodes.first { $0.id == formID }?.childIDs
            XCTAssertEqual(children?.count, expectedCount)
        }
        for expectedCount in 1...templates.count {
            try session.redo()
            let children = session.document.pages[0].nodes.first { $0.id == formID }?.childIDs
            XCTAssertEqual(children?.count, expectedCount)
        }
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == formID }?.childIDs,
                       insertedIDs)
    }

    // SF-AUTHORING-090: an Input is a canonical Text child of Form, never a
    // standalone field or a second node schema.
    func testInputTemplateRequiresFormParentAndPreservesFieldIdentityThroughHistory() throws {
        let fixture = makeFixture()
        let formID = NodeID(UUID(uuidString: "62000000-0000-4000-8000-000000000001")!)
        let form = try prepare(.form, fixture: fixture, nodeID: formID)
        let session = DocumentSession(document: fixture.document)
        try session.execute(form.documentCommand)
        let current = fixture.with(document: session.document)
        let fieldID = NodeID(UUID(uuidString: "62000000-0000-4000-8000-000000000002")!)
        let geometry = InsertionGeometry(origin: .init(x: 30, y: 40), size: AuthoringElementTemplate.input.size)
        let registry = InsertionCommandRegistry()
        let invalidParent = command(.text, fixture: current, nodeID: fieldID,
                                    parentID: current.rootID, geometry: geometry)
        XCTAssertThrowsError(try registry.prepare(invalidParent, in: current.document,
            context: current.context, template: .input)) { error in
            XCTAssertEqual(error as? InsertionError, .formParentRequired)
        }
        let operation = command(.text, fixture: current, nodeID: fieldID,
                                parentID: formID, geometry: geometry)
        let prepared = try registry.prepare(operation, in: current.document,
                                            context: current.context, template: .input)
        XCTAssertEqual(prepared.node.kind, .text)
        XCTAssertEqual(prepared.node.parent, .node(formID))
        XCTAssertEqual(prepared.node.id, fieldID)
        XCTAssertEqual(prepared.node.name, "Input")
        XCTAssertEqual(prepared.geometry.size, .init(width: 240, height: 36))
        XCTAssertEqual(prepared.node.insertionStringProperty("content.text"), "Input")
        XCTAssertEqual(prepared.node.insertionStringProperty(CanonicalFormField.kindKey), "text")
        XCTAssertEqual(prepared.node.insertionStringProperty(CanonicalFormField.labelKey), "Input")
        XCTAssertEqual(prepared.node.insertionStringProperty(CanonicalFormField.nameKey),
                       "field62000000000040008000000000000002")
        XCTAssertEqual(prepared.node.insertionProperty(CanonicalFormField.kindKey)?.origin, .defaulted)
        XCTAssertEqual(prepared.node.insertionProperty(CanonicalFormField.requiredKey)?.value, .boolean(false))
        XCTAssertEqual(registry.availability(for: operation, in: current.document,
            context: current.context, template: .input), .enabled)
        let cancelled = InsertionCancellation { true }
        XCTAssertThrowsError(try registry.prepare(operation, in: current.document,
            context: current.context, cancellation: cancelled, template: .input)) { error in
            XCTAssertEqual(error as? InsertionError, .cancelled)
        }
        try session.execute(prepared.documentCommand)
        XCTAssertNoThrow(try session.document.validate())
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == formID }?.childIDs, [fieldID])
        try session.undo()
        XCTAssertFalse(session.document.pages[0].nodes.contains { $0.id == fieldID })
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == fieldID }?.properties,
                       prepared.node.properties)
    }

    // SF-AUTHORING-086–089: site/line templates remain single canonical
    // Frame/Section commands with stable IDs and exact history inverses.
    // SF-SOURCE-BATCH-20261027-02: source coverage only; owner testing hold.
    func testHeaderNavigationGapSharesResponsiveFramesCSSAndExactHistory() throws {
        let (session, headerID, _, _) = try connectedPageSession()
        let pageID = session.document.pages[0].id
        @MainActor func page() -> DocumentPage { session.document.pages[0] }
        @MainActor func header() throws -> DocumentNode { try XCTUnwrap(page().nodes.first { $0.id == headerID }) }
        @MainActor func navigation() throws -> DocumentNode {
            let id = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: header()))
            return try XCTUnwrap(page().nodes.first { $0.id == id })
        }
        for _ in 0..<2 where CanonicalPageChrome.links(owner: try header(), page: page()).count < 2 {
            try session.execute(pageStructureCommand(.addLink(owner: headerID, pageID: pageID), document: session.document, selected: headerID))
        }
        let before = session.document.pages
        let nodeIDs = page().nodes.map(\.id)
        try session.execute(pageStructureCommand(.navigationGap(headerID, 40, .desktop), document: session.document, selected: headerID))
        let desktop = session.document.pages
        try session.execute(pageStructureCommand(.navigationGap(headerID, 6.5, .tablet), document: session.document, selected: headerID, breakpoint: .tablet))
        let overridden = session.document.pages
        XCTAssertEqual(CanonicalPageChrome.navigationGap(surface: try navigation(), settings: try header(), breakpoint: .desktop, width: 1440), 40)
        XCTAssertEqual(CanonicalPageChrome.navigationGap(surface: try navigation(), settings: try header(), breakpoint: .tablet, width: 768), 6.5)
        XCTAssertTrue(ConnectedPageOutput.css(pages: [page()]).contains("min(6.5px"))
        let frames = page().resolvedStructuralGeometry(breakpoint: .tablet, viewportWidth: 768)
        let links = CanonicalPageChrome.links(owner: try header(), page: page()).filter { !$0.selectionBooleanProperty("hidden") }
        guard links.count >= 2 else { XCTFail("Two visible links are required to assert resolved spacing"); return }
        let first = try XCTUnwrap(frames[links[0].id]), second = try XCTUnwrap(frames[links[1].id])
        XCTAssertEqual(second.frame.minX - first.frame.maxX, 6.5, accuracy: 0.001)
        let tree = try InternalDocumentRenderTreeCompiler.compile(page: page(), documentID: session.document.id,
            revision: session.document.revision, breakpoint: .tablet, viewportWidth: 768)
        XCTAssertEqual(tree.nodes.first { $0.id == links[0].id }?.frame, first.frame)
        XCTAssertEqual(page().nodes.map(\.id), nodeIDs)
        try session.execute(pageStructureCommand(.navigationGap(headerID, nil, .tablet), document: session.document, selected: headerID, breakpoint: .tablet))
        XCTAssertNil(try navigation().insertionProperty(ResponsiveContainerLayoutResolver.key(.gap, breakpoint: .tablet)))
        XCTAssertEqual(CanonicalPageChrome.navigationGap(surface: try navigation(), settings: try header(), breakpoint: .tablet, width: 768), 40)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened, session.document)
        XCTAssertEqual(ConnectedPageOutput.css(pages: reopened.pages), ConnectedPageOutput.css(pages: session.document.pages))
        try session.undo(); XCTAssertEqual(session.document.pages, overridden)
        try session.undo(); XCTAssertEqual(session.document.pages, desktop)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); try session.redo(); try session.redo()
        XCTAssertEqual(page().nodes.map(\.id), nodeIDs)
    }

    func testHeaderNavigationGapRejectsInvalidCancelledLockedAndWrongScope() throws {
        let (session, headerID, _, _) = try connectedPageSession()
        let before = session.document
        for value in [-1.0, .nan, .infinity, 10_001] {
            XCTAssertThrowsError(try pageStructureCommand(.navigationGap(headerID, value, .desktop), document: before, selected: headerID))
        }
        XCTAssertThrowsError(try pageStructureCommand(.navigationGap(headerID, 12, .mobile), document: before, selected: headerID, breakpoint: .tablet))
        XCTAssertThrowsError(try pageStructureCommand(.navigationGap(headerID, 12, .desktop), document: before, selected: headerID, cancelled: true))
        var locked = before
        let owner = try XCTUnwrap(locked.pages[0].nodes.first { $0.id == headerID })
        let navigationID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner))
        let index = try XCTUnwrap(locked.pages[0].nodes.firstIndex { $0.id == navigationID })
        locked.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: "locked"), value: .boolean(true)))
        XCTAssertThrowsError(try pageStructureCommand(.navigationGap(headerID, 12, .desktop), document: locked, selected: headerID))
        var later = before
        later.revision += 1
        let scene = CanvasViewportSceneID()
        XCTAssertThrowsError(try PageStructureCommandRegistry().prepare(.navigationGap(headerID, 12, .desktop),
            identity: .init(documentID: before.id, pageID: before.pages[0].id, revision: before.revision,
                            sceneID: scene, rendererGeneration: before.revision),
            document: later, context: .init(activePageID: before.pages[0].id, currentSceneID: scene,
                rendererGeneration: later.revision, selectedNodeIDs: [headerID], availableNodeIDs: [headerID],
                isLifecycleAvailable: true, lifecycleDisabledReason: nil), viewportWidth: 1440, breakpoint: .desktop))
        XCTAssertEqual(session.document, before)
    }

    func testNavigationGapPolicyHandlesZeroOneManyAndNarrowBounds() {
        for count in [0, 1, 2, 32] {
            for width in [1.0, 390, 768, 1440] {
                let layout = CanonicalPageFlow.navigationLayout(availableWidth: width, count: count, alignment: "end", requestedGap: 44)
                XCTAssertTrue(layout.width.isFinite && layout.gap.isFinite && layout.offset.isFinite)
                XCTAssertGreaterThanOrEqual(layout.gap, 0)
                if count <= 1 { XCTAssertEqual(layout.gap, 0) }
                if count > 0 {
                    XCTAssertLessThanOrEqual(Double(count) * layout.width + Double(count - 1) * layout.gap, max(1, width) + 0.001)
                }
            }
        }
    }

    func testHeaderImageVisibilityRetainsResponsiveIntentAndExactInverse() throws {
        let (session, headerID, _, _) = try connectedPageSession()
        let pageID = session.document.pages[0].id
        let owner = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == headerID })
        let contentID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner))
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Logo", originalFilename: "logo.png", format: .png,
            pixelWidth: 72, pixelHeight: 32, byteCount: 1, contentHash: String(repeating: "a", count: 64))
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        let image = DocumentNode(kind: .image, name: "Brand mark", parent: .node(contentID), properties: [
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"), value: .string(asset.id.description)),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string("fit")),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string("Brand")),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(false)),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.5)),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.5)),
            .init(key: .init(rawValue: "layout.x"), value: .number(0)), .init(key: .init(rawValue: "layout.y"), value: .number(0)),
            .init(key: .init(rawValue: "layout.width"), value: .number(72)), .init(key: .init(rawValue: "layout.height"), value: .number(32)),
            .init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(false))])
        try session.execute(.insertNode(.init(pageID: pageID, node: image, index: 0)))
        let before = session.document.pages
        try session.execute(pageStructureCommand(.showContentImage(headerID, image.id, false), document: session.document, selected: headerID))
        let changed = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == image.id })
        XCTAssertTrue(changed.selectionBooleanProperty("hidden"))
        XCTAssertEqual(changed.insertionProperty(ResponsiveVisibilityResolver.key(.mobile)), image.insertionProperty(ResponsiveVisibilityResolver.key(.mobile)))
        XCTAssertEqual(session.document.imageAssets, [asset])
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try pageStructureCommand(.showContentImage(headerID, NodeID(), false), document: session.document, selected: headerID))
    }

    func testHeaderIncludedLinksKeepIdentityAcrossZeroOneManyAndPageLifecycle() throws {
        let (session, headerID, _, _) = try connectedPageSession()
        let pageID = session.document.pages[0].id
        @MainActor func apply(_ edit: PageStructureEdit) throws {
            try session.execute(pageStructureCommand(edit, document: session.document, selected: headerID))
        }
        @MainActor func snapshot(_ breakpoint: ResponsiveBreakpoint) throws -> PageNavigationSnapshot? {
            let page = session.document.pages[0]
            let owner = try XCTUnwrap(page.nodes.first { $0.id == headerID })
            let navigationID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner))
            let surface = try XCTUnwrap(page.nodes.first { $0.id == navigationID })
            return CanonicalPageFlow.navigation(owner: surface, page: page, document: session.document,
                breakpoint: breakpoint, width: CanonicalPageFlow.pageWidth(breakpoint, nil))
        }
        let eligible = session.document.websitePages.filter { $0.role != .notFound }
        for page in eligible { try apply(.includePage(headerID, page.id, false)) }
        XCTAssertNil(try snapshot(.mobile), "No links means no empty mobile menu")
        try apply(.includePage(headerID, pageID, true))
        let one = try XCTUnwrap(snapshot(.mobile))
        XCTAssertEqual(one.links.count, 1)
        XCTAssertTrue(one.usesHamburger)
        XCTAssertFalse(try XCTUnwrap(snapshot(.desktop)).usesHamburger)
        let stableLinkID = one.links[0].id
        try apply(.includePage(headerID, pageID, false)); try apply(.includePage(headerID, pageID, true))
        XCTAssertEqual(try snapshot(.mobile)?.links.first?.id, stableLinkID)
        let create = try PageCommandRegistry().prepare(.create(name: "More", route: "/more"), identity: .init(
            documentID: session.document.id, revision: session.document.revision, pageID: pageID), in: session.document, isAvailable: true)
        try session.execute(create.command)
        try apply(.includeAllPages(headerID))
        let more = try XCTUnwrap(snapshot(.mobile)?.links.first { $0.pageID == create.selectedPageID })
        XCTAssertGreaterThan(try XCTUnwrap(snapshot(.mobile)).links.count, 1)
        try apply(.editLink(owner: headerID, link: more.id, pageID: more.pageID, label: "Our custom label"))
        let rename = try PageCommandRegistry().prepare(.rename("Renamed"), identity: .init(documentID: session.document.id,
            revision: session.document.revision, pageID: more.pageID), in: session.document, isAvailable: true)
        try session.execute(rename.command)
        XCTAssertEqual(try snapshot(.mobile)?.links.first { $0.id == more.id }?.label, "Our custom label")
        let remove = try PageCommandRegistry().prepare(.delete, identity: .init(documentID: session.document.id,
            revision: session.document.revision, pageID: more.pageID), in: session.document, isAvailable: true)
        try session.execute(remove.command)
        XCTAssertEqual(try snapshot(.mobile)?.links.first { $0.id == more.id }?.isAvailable, false)
        try session.undo()
        XCTAssertEqual(try snapshot(.mobile)?.links.first { $0.id == more.id }?.isAvailable, true)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    private func connectedPageSession() throws -> (DocumentSession, NodeID, [NodeID], NodeID) {
        let fixture = makeFixture(), session = DocumentSession(document: fixture.document)
        let header = NodeID(), footer = NodeID(), bodies = [NodeID(), NodeID()]
        let insertions: [(NodeID, AuthoringElementTemplate?)] = [(footer, .footer), (header, .header), (bodies[0], nil), (bodies[1], nil)]
        for (id, template) in insertions {
            let current = fixture.with(document: session.document)
            let operation = command(.section, fixture: current, nodeID: id,
                index: session.document.pages[0].nodes[0].childIDs.count,
                geometry: .init(origin: .init(x: 300, y: 400), size: template?.size ?? .init(width: 960, height: 320)), provenance: .menu)
            let prepared = try InsertionCommandRegistry().prepare(operation, in: session.document, context: current.context, template: template)
            try session.execute(prepared.documentCommand)
        }
        return (session, header, bodies, footer)
    }

    // SF-0502-003, SF-1201-003: short pages keep the authored root
    // background across the browser viewport without changing saved geometry.
    func testConnectedPageViewportMinimumBelongsToAuthoredRootWithoutMutation() throws {
        let (session, _, _, _) = try connectedPageSession()
        let original = session.document
        let page = original.pages[0]
        let css = ConnectedPageOutput.css(pages: [page])
        XCTAssertTrue(ConnectedPageOutput.menuCSS.contains("min-height:100vh;"))
        XCTAssertFalse(ConnectedPageOutput.menuCSS.contains("min-height:900px;"))
        for rootID in page.rootNodeIDs {
            let selector = CanonicalCSSRule.selector(for: rootID)
            let roots = css.components(separatedBy: "\n").filter { $0.hasPrefix(selector + " { display:flow-root;") }
            XCTAssertEqual(roots.count, ResponsiveBreakpoint.allCases.count)
            XCTAssertTrue(roots.allSatisfy { $0.contains("min-height:100vh;") })
        }
        XCTAssertEqual(session.document, original)
    }

    // SF-0303-002/003/005, SF-0308-003/005: one independent page-copy transaction.
    func testNamedPageReusePreservesStructureMetadataHistoryAndSerialization() throws {
        let (session, _, _, _) = try connectedPageSession()
        let pageID = session.document.pages[0].id
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id,
            metadata: .init(siteName: "Studio", pages: [.init(pageID: pageID,
                title: "Authored title", description: "Authored description", allowsIndexing: false)]))))
        let before = session.document
        let historyCount = session.historySnapshot().undoEntries.count
        let prepared = try PageCommandRegistry().prepare(.duplicateNamed(name: " Related ", route: " /Related "),
            identity: .init(documentID: before.id, revision: before.revision, pageID: pageID),
            in: before, isAvailable: true)
        try session.execute(prepared.command)
        let after = session.document
        let copy = try XCTUnwrap(after.pages.first { $0.id == prepared.selectedPageID })
        XCTAssertEqual(copy.name, "Related"); XCTAssertEqual(copy.route.rawValue, "/related")
        XCTAssertEqual(after.pages.first { $0.id == pageID }, before.pages[0])
        XCTAssertEqual(copy.nodes.count, before.pages[0].nodes.count)
        XCTAssertTrue(Set(copy.nodes.map(\.id)).isDisjoint(with: before.pages[0].nodes.map(\.id)))
        XCTAssertEqual(copy.nodes.map(\.kind), before.pages[0].nodes.map(\.kind))
        let copiedIDs = Dictionary(uniqueKeysWithValues: zip(before.pages[0].nodes, copy.nodes).map { ($0.id, $1.id) })
        for (original, copied) in zip(before.pages[0].nodes, copy.nodes) {
            XCTAssertEqual(copied.name, original.name)
            XCTAssertEqual(copied.childIDs, original.childIDs.map { copiedIDs[$0]! })
            XCTAssertEqual(copied.properties.map(\.key), original.properties.map(\.key))
            for (old, new) in zip(original.properties, copied.properties) {
                XCTAssertNotEqual(new.id, old.id)
                XCTAssertEqual(new.origin, old.origin)
                if !CanonicalPageChrome.referenceKeys.contains(old.key.rawValue),
                   ![CanonicalLinkTarget.namespace + "pageID", CanonicalLinkTarget.namespace + "nodeID"].contains(old.key.rawValue) {
                    XCTAssertEqual(new.value, old.value, "Copy must preserve authored geometry, responsive modes, styles and content")
                }
            }
        }
        let settings = try XCTUnwrap(after.websiteMetadata?.pages.first { $0.pageID == copy.id })
        XCTAssertEqual(settings.title, "Authored title"); XCTAssertEqual(settings.description, "Authored description")
        XCTAssertEqual(settings.allowsIndexing, false)
        XCTAssertEqual(after.websiteMetadata?.siteName, before.websiteMetadata?.siteName)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, historyCount + 1)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(after)), after)
        XCTAssertNoThrow(try MultiPageStaticBuildPlanner.plan(document: after))
        try session.undo()
        XCTAssertEqual(session.document.pages, before.pages)
        XCTAssertEqual(session.document.websiteMetadata, before.websiteMetadata)
        try session.redo()
        XCTAssertEqual(session.document.pages, after.pages)
        XCTAssertEqual(session.document.websiteMetadata, after.websiteMetadata)
    }

    func testHeaderTitleProvenanceMatchesSiteHomeAndLegacyFallbackResolution() {
        var document = BlankProjectDefaults.document()
        var title = DocumentNode(kind: .text, name: "Site title", parent: .node(document.pages[0].rootNodeIDs[0]),
            properties: [.init(key: .init(rawValue: "content.text"), value: .string("Stored"), origin: .defaulted)])
        XCTAssertEqual(CanonicalPageChrome.resolvedTitle(title, in: document).provenance, "Defaulted from Home page")
        document.websiteMetadata = .init(siteName: "Studio")
        XCTAssertEqual(CanonicalPageChrome.titleText(title, in: document), "Studio")
        XCTAssertEqual(CanonicalPageChrome.resolvedTitle(title, in: document).provenance, "Defaulted from Site Name")
        document.websiteMetadata = nil; document.pages[0].role = .standard
        XCTAssertEqual(CanonicalPageChrome.titleText(title, in: document), "Stored")
        XCTAssertEqual(CanonicalPageChrome.resolvedTitle(title, in: document).provenance, "Stored default title")
        title.properties = [.init(key: .init(rawValue: "content.text"), value: .string("Custom"), origin: .authored)]
        XCTAssertEqual(CanonicalPageChrome.resolvedTitle(title, in: document).provenance, "Authored title")
        XCTAssertEqual(CanonicalPageChrome.titleText(title, in: document), "Custom")
    }

    func testNamedPageReuseInvalidCancelledStaleAndUnavailableAreNeutral() throws {
        let (session, _, _, _) = try connectedPageSession()
        let before = session.document, registry = PageCommandRegistry()
        let identity = PageEditIdentity(documentID: before.id, revision: before.revision, pageID: before.pages[0].id)
        for edit in [PageEdit.duplicateNamed(name: "", route: "/related"),
                     .duplicateNamed(name: "Related", route: before.pages[0].route.rawValue),
                     .duplicateNamed(name: "Related", route: "/../bad")] {
            XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: before, isAvailable: true))
        }
        let valid = PageEdit.duplicateNamed(name: "Related", route: "/related")
        XCTAssertThrowsError(try registry.prepare(valid, identity: identity, in: before, isAvailable: true, cancelled: true))
        XCTAssertThrowsError(try registry.prepare(valid, identity: identity, in: before, isAvailable: false))
        for stale in [PageEditIdentity(documentID: DocumentID(), revision: before.revision, pageID: identity.pageID),
                      .init(documentID: before.id, revision: before.revision + 1, pageID: identity.pageID),
                      .init(documentID: before.id, revision: before.revision, pageID: PageID())] {
            XCTAssertThrowsError(try registry.prepare(valid, identity: stale, in: before, isAvailable: true))
        }
        XCTAssertEqual(session.document, before)
    }

    // SF-0502-003/005, SF-0806-003/005: preserve custom labels and link order.
    func testIncludeAllPagesIsAtomicOrderedAndPreservesCustomNavigation() throws {
        let (session, header, _, _) = try connectedPageSession()
        let first = session.document.pages[0]
        let owner = try XCTUnwrap(first.nodes.first { $0.id == header })
        let initial = CanonicalPageChrome.links(owner: owner, page: first)
        let retained = try XCTUnwrap(initial.first)
        let target = try XCTUnwrap(retained.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID").flatMap(PageID.init(uuidString:)))
        try session.execute(pageStructureCommand(.editLink(owner: header, link: retained.id, pageID: target,
            label: "Custom destination"), document: session.document, selected: header))
        try session.execute(pageStructureCommand(.includePage(header, target, false), document: session.document, selected: header))
        for name in ["Journal", "Contact"] {
            try session.execute(.insertPage(.init(page: .minimum(name: name, route: "/" + name.lowercased(),
                role: .standard, provenance: .authored), index: session.document.pages.count)))
        }
        let before = session.document, historyCount = session.historySnapshot().undoEntries.count
        try session.execute(pageStructureCommand(.includeAllPages(header), document: before, selected: header))
        let after = session.document, page = after.pages[0]
        let updatedOwner = try XCTUnwrap(page.nodes.first { $0.id == header })
        let links = CanonicalPageChrome.links(owner: updatedOwner, page: page)
        XCTAssertEqual(Array(links.prefix(initial.count).map(\.id)), initial.map(\.id))
        XCTAssertEqual(links.first { $0.id == retained.id }?.insertionStringProperty(CanonicalLinkTarget.labelKey), "Custom destination")
        XCTAssertTrue(links.allSatisfy { !$0.selectionBooleanProperty("hidden") })
        XCTAssertEqual(Array(links.suffix(2)).compactMap { $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") },
                       Array(after.pages.suffix(2)).map { $0.id.description })
        XCTAssertEqual(session.historySnapshot().undoEntries.count, historyCount + 1)
        let unchanged = try pageStructureCommand(.includeAllPages(header), document: after, selected: header)
        if case .batch(let commands) = unchanged {
            // Nested empty operations must not masquerade as real history.
            XCTAssertTrue(commands.isEmpty)
        } else { XCTFail("No-change Include All must remain history-neutral") }
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(after)), after)
        XCTAssertNoThrow(try MultiPageStaticBuildPlanner.plan(document: after))
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, after.pages)
    }

    func testIncludeAllPagesRejectsLockedCancelledStaleAndCapacityWithoutMutation() throws {
        let (session, header, _, _) = try connectedPageSession()
        let owner = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == header })
        let link = try XCTUnwrap(CanonicalPageChrome.links(owner: owner, page: session.document.pages[0]).first)
        try setConnectedFixtureProperty("hidden", value: .boolean(true), nodeID: link.id, session: session)
        try setConnectedFixtureProperty("locked", value: .boolean(true), nodeID: link.id, session: session)
        let before = session.document
        XCTAssertThrowsError(try pageStructureCommand(.includeAllPages(header), document: before, selected: header))
        XCTAssertThrowsError(try pageStructureCommand(.includeAllPages(header), document: before, selected: header, cancelled: true))
        let scene = CanvasViewportSceneID()
        XCTAssertThrowsError(try PageStructureCommandRegistry().prepare(.includeAllPages(header), identity: .init(
            documentID: before.id, pageID: before.pages[0].id, revision: before.revision - 1,
            sceneID: scene, rendererGeneration: before.revision), document: before,
            context: .init(activePageID: before.pages[0].id, currentSceneID: scene, rendererGeneration: before.revision,
                selectedNodeIDs: [header], availableNodeIDs: Set(before.pages[0].nodes.map(\.id)),
                isLifecycleAvailable: true, lifecycleDisabledReason: nil), viewportWidth: 1440, breakpoint: .desktop))
        XCTAssertEqual(session.document, before)
        var oversized = before
        for index in 0...CanonicalPageFlow.maximumLinks {
            oversized.pages.append(.minimum(name: "Destination \(index)", route: "/destination-\(index)", role: .standard, provenance: .authored))
        }
        XCTAssertThrowsError(try pageStructureCommand(.includeAllPages(header), document: oversized, selected: header)) {
            XCTAssertTrue($0 is PageStructureEditError)
        }
        XCTAssertEqual(session.document, before)
    }

    func testNamedPageReusePackageRecoveryHistoryAndBranching() async throws {
        let (session, _, _, _) = try connectedPageSession()
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id,
            metadata: .init(pages: [.init(pageID: session.document.pages[0].id,
                title: "Related page settings", allowsIndexing: false)]))))
        let source = session.document
        let prepared = try PageCommandRegistry().prepare(.duplicateNamed(name: "Related", route: "/related"),
            identity: .init(documentID: source.id, revision: source.revision, pageID: source.pages[0].id),
            in: source, isAvailable: true)
        try session.execute(prepared.command)
        let committed = session.document
        let package = try await PersistedHistoryStore().package(
            ProjectPackage(createdAt: .init(date: Date(timeIntervalSince1970: 1)), document: committed), with: session.historySnapshot())
        let store = ProjectPackageStore()
        let encoded = try await store.encode(package)
        let encodedAgain = try await store.encode(package)
        XCTAssertEqual(encoded, encodedAgain)
        let reopened = try await store.decode(encoded)
        XCTAssertEqual(reopened.document, committed)
        guard case .restored(let history) = try await PersistedHistoryStore().load(from: reopened) else {
            return XCTFail("Related page must retain package/recovery history")
        }
        let restored = DocumentSession(document: reopened.document)
        try restored.installValidatedHistory(history)
        try restored.undo(); XCTAssertEqual(restored.document.pages, source.pages)
        XCTAssertEqual(restored.document.websiteMetadata, source.websiteMetadata)
        try restored.redo(); XCTAssertEqual(restored.document.pages, committed.pages)
        XCTAssertEqual(restored.document.websiteMetadata, committed.websiteMetadata)
        try restored.undo()
        try restored.execute(.renamePage(.init(pageID: source.pages[0].id, name: "Branch")))
        XCTAssertFalse(restored.canRedo)
        let diagnostics = CommandDiagnostics()
        diagnostics.recordPagePreparationFailure(.duplicateNamed(name: "Private copied title", route: "/private-route"),
            pageID: source.pages[0].id, durationMilliseconds: 1)
        XCTAssertFalse(String(describing: diagnostics.records).contains("Private copied title"))
        XCTAssertFalse(String(describing: diagnostics.records).contains("/private-route"))
    }
    private func pageStructureCommand(_ edit: PageStructureEdit, document: CanonicalDocument, selected: NodeID,
                                      breakpoint: ResponsiveBreakpoint = .desktop, cancelled: Bool = false) throws -> DocumentCommand {
        let page = document.pages[0], scene = CanvasViewportSceneID()
        return try PageStructureCommandRegistry().prepare(edit, identity: .init(documentID: document.id, pageID: page.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision), document: document,
            context: .init(activePageID: page.id, currentSceneID: scene, rendererGeneration: document.revision,
                selectedNodeIDs: [selected], availableNodeIDs: Set(page.nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil),
            viewportWidth: CanonicalPageFlow.pageWidth(breakpoint, nil), breakpoint: breakpoint, cancelled: cancelled)
    }
    func testConnectedPageFlowAnchorsOrderDynamicWidthHeightAndHistory() throws {
        let (session, header, bodies, footer) = try connectedPageSession()
        let original = session.document.pages
        for breakpoint in ResponsiveBreakpoint.allCases {
            let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
            let frames = session.document.pages[0].resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
            XCTAssertEqual(frames[header]?.origin.y, 0)
            XCTAssertEqual(frames[bodies[0]]?.origin.y, 120)
            XCTAssertEqual(frames[bodies[1]]?.origin.y, 440)
            XCTAssertEqual(frames[footer]?.origin.y, 760)
            for id in [header] + bodies + [footer] { XCTAssertEqual(frames[id]?.size.width, width) }
            XCTAssertEqual(CanonicalPageFlow.contentHeight(session.document.pages[0], breakpoint: breakpoint, width: width), 960)
        }
        try session.execute(pageStructureCommand(.reorder(bodies[1], pointerY: 121), document: session.document, selected: bodies[1]))
        let reordered = session.document.pages
        let frames = session.document.pages[0].resolvedStructuralGeometry(viewportWidth: 1440)
        XCTAssertEqual(frames[bodies[1]]?.origin.y, 120); XCTAssertEqual(frames[footer]?.origin.y, 760)
        try session.undo(); XCTAssertEqual(session.document.pages, original)
        try session.redo(); XCTAssertEqual(session.document.pages, reordered)
        try session.execute(pageStructureCommand(.height(header, 200, .mobile), document: session.document, selected: header, breakpoint: .mobile))
        XCTAssertEqual(session.document.pages[0].resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 390)[bodies[1]]?.origin.y, 200)
        XCTAssertEqual(session.document.pages[0].resolvedStructuralGeometry(breakpoint: .desktop, viewportWidth: 1440)[bodies[1]]?.origin.y, 120)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let forged = String(decoding: try DocumentSerializer.encode(session.document), as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":15")
        XCTAssertThrowsError(try DocumentSerializer.decode(Data(forged.utf8)))
    }

    // SF-0201-003/006 and connected-flow Inspector truthfulness: a computed
    // frame is not the retained insertion default and must not appear stale.
    func testConnectedFlowInspectorUsesAdoptedFrameWithoutChangingAuthoredGeometry() async throws {
        let (session, _, _, footer) = try connectedPageSession()
        let canonical = session.document
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        let readyDeadline = ContinuousClock.now + .seconds(3)
        while !state.layerTargets.contains(where: { $0.id == footer }), ContinuousClock.now < readyDeadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(state.layerTargets.contains { $0.id == footer }, "The adopted selection scene must be ready before a Layers action")
        state.selectLayer(footer)
        XCTAssertEqual(state.selectionState.primaryID, footer)
        for preset in [ViewportPreset.desktop, .tablet, .mobile] {
            state.viewportPreset = preset
            let adoptionDeadline = ContinuousClock.now + .seconds(3)
            while state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation,
                  ContinuousClock.now < adoptionDeadline {
                try await Task.sleep(for: .milliseconds(5))
            }
            XCTAssertEqual(state.canvasRenderPlan?.identity.viewportGeneration, state.viewportState.generation)
            let object = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == footer })
            let expected = String(format: "X %.0f, Y %.0f, Width %.0f, Height %.0f",
                                  object.frame.origin.x, object.frame.origin.y,
                                  object.frame.size.width, object.frame.size.height)
            XCTAssertEqual(state.resolvedSelectedGeometrySummary, expected)
            XCTAssertNotEqual(state.resolvedSelectedGeometrySummary, state.transformGeometrySummary)
            XCTAssertEqual(session.document, canonical)
        }
        let resolvedBeforeInvalidPage = state.resolvedSelectedGeometrySummary
        state.selectPage(PageID())
        XCTAssertEqual(state.resolvedSelectedGeometrySummary, resolvedBeforeInvalidPage,
                       "An invalid page request is neutral, not a selection reset.")
        state.performSelectionCommand(.clear, provenance: .menu)
        XCTAssertNil(state.resolvedSelectedGeometrySummary)
    }
    func testPageFlowLegacyConversionRetainsExactAuthoredGeometryAndRejectsUnsafeEdits() throws {
        let (session, _, bodies, _) = try connectedPageSession()
        var legacy = session.document
        let ni = try XCTUnwrap(legacy.pages[0].nodes.firstIndex { $0.id == bodies[0] })
        legacy.pages[0].nodes[ni].properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalPageFlow.namespace) }
        let xIndex = try XCTUnwrap(legacy.pages[0].nodes[ni].properties.firstIndex { $0.key.rawValue == "layout.x" })
        let yIndex = try XCTUnwrap(legacy.pages[0].nodes[ni].properties.firstIndex { $0.key.rawValue == "layout.y" })
        legacy.pages[0].nodes[ni].properties[xIndex].value = .number(250)
        legacy.pages[0].nodes[ni].properties[yIndex].value = .number(700)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(legacy))
        XCTAssertEqual(reopened.pages[0].nodes[ni].insertionGeometry, legacy.pages[0].nodes[ni].insertionGeometry)
        XCTAssertEqual(reopened.pages[0].resolvedStructuralGeometry(viewportWidth: 1440)[bodies[0]]?.origin.x, 250)
        XCTAssertThrowsError(try pageStructureCommand(.convert(bodies[0], confirmed: false), document: reopened, selected: bodies[0]))
        let conversion = DocumentSession(document: reopened)
        try conversion.execute(pageStructureCommand(.convert(bodies[0], confirmed: true), document: reopened, selected: bodies[0]))
        XCTAssertEqual(conversion.document.pages[0].nodes[ni].insertionGeometry, reopened.pages[0].nodes[ni].insertionGeometry)
        XCTAssertEqual(conversion.document.pages[0].resolvedStructuralGeometry(viewportWidth: 1440)[bodies[0]]?.size.width, 1440)
        try conversion.undo(); XCTAssertEqual(conversion.document.pages, reopened.pages)
        XCTAssertThrowsError(try pageStructureCommand(.height(bodies[1], .nan, .desktop), document: session.document, selected: bodies[1]))
        XCTAssertThrowsError(try pageStructureCommand(.reorder(bodies[1], pointerY: 0), document: session.document, selected: bodies[1], cancelled: true))
    }
    func testHeaderNavigationStableLinksRenameDeleteReorderHamburgerAndOutput() async throws {
        let (session, header, _, _) = try connectedPageSession()
        let about = DocumentPage.minimum(name: "About", route: "/about", role: .standard, provenance: .authored)
        let contact = DocumentPage.minimum(name: "Contact", route: "/contact", role: .standard, provenance: .authored)
        try session.execute(.insertPage(.init(page: about, index: session.document.pages.count)))
        try session.execute(.insertPage(.init(page: contact, index: session.document.pages.count)))
        try session.execute(pageStructureCommand(.addLink(owner: header, pageID: about.id), document: session.document, selected: header))
        try session.execute(pageStructureCommand(.addLink(owner: header, pageID: contact.id), document: session.document, selected: header))
        func navigation(_ document: CanonicalDocument, _ breakpoint: ResponsiveBreakpoint) throws -> PageNavigationSnapshot {
            let owner = try XCTUnwrap(document.pages[0].nodes.first { $0.id == header })
            return try XCTUnwrap(CanonicalPageFlow.navigation(owner: owner, page: document.pages[0], document: document, breakpoint: breakpoint))
        }
        let links = try navigation(session.document, .desktop).links
        try session.execute(.renamePage(.init(pageID: about.id, name: "Company")))
        let aboutLink = try XCTUnwrap(links.first { $0.pageID == about.id })
        XCTAssertEqual(try navigation(session.document, .desktop).links.first { $0.id == aboutLink.id }?.label, "Company")
        try session.execute(pageStructureCommand(.reorderLink(owner: header, link: links[1].id, offset: -1), document: session.document, selected: header))
        XCTAssertEqual(try navigation(session.document, .desktop).links.map(\.id), [links[1].id, links[0].id, links[2].id])
        try session.execute(pageStructureCommand(.hamburger(header, true), document: session.document, selected: header))
        XCTAssertFalse(try navigation(session.document, .desktop).usesHamburger)
        XCTAssertTrue(try navigation(session.document, .mobile).usesHamburger)
        let preview = try await LocalPreviewRuntimeCompiler().compile(document: session.document, imageResourceData: [:], pixelRatio: .init(1), breakpoint: .mobile)
        let owner = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == header })
        let navigationID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner))
        let menu = try XCTUnwrap(preview.pages[0].objects.first { $0.id == navigationID }?.navigation)
        XCTAssertEqual(menu.ownerID, header)
        XCTAssertTrue(menu.usesHamburger)
        XCTAssertEqual(menu.links.map(\.id), try navigation(session.document, .mobile).links.map(\.id))
        XCTAssertNil(preview.pages[0].objects.first { $0.id == header }?.navigation,
                     "The Header must not duplicate its nested Navigation Stack's menu.")
        let plan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("data-siteforge-navigation")); XCTAssertTrue(html.contains("<summary"))
        XCTAssertTrue(html.contains("Company")); XCTAssertFalse(html.contains("selection"))
        XCTAssertTrue(plan.files.contains { $0.path == "siteforge-navigation.js" && $0.contents.contains("Escape") && $0.contents.contains(".focus()") })
        let retained = session.document.pages
        try session.execute(.removePage(.init(pageID: about.id)))
        XCTAssertEqual(try navigation(session.document, .desktop).links.first { $0.id == aboutLink.id }?.isAvailable, false)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo(); XCTAssertEqual(session.document.pages, retained)
    }
    func testPageFlowNestedContainerWidthTransferRejectionAndEmptyPage() throws {
        var fixture = makeFixture()
        let frame = try prepare(.frame, fixture: fixture, nodeID: fixture.frameID)
        let session = DocumentSession(document: fixture.document); try session.execute(frame.documentCommand)
        fixture = fixture.with(document: session.document)
        let id = NodeID(), operation = command(.section, fixture: fixture, nodeID: id, parentID: fixture.frameID,
            geometry: .init(origin: .init(x: 900, y: 900), size: .init(width: 960, height: 320)))
        try session.execute(InsertionCommandRegistry().prepare(operation, in: session.document, context: fixture.context).documentCommand)
        let frames = session.document.pages[0].resolvedStructuralGeometry(viewportWidth: 1440)
        XCTAssertEqual(frames[id]?.size.width, frames[fixture.frameID]?.size.width)
        XCTAssertEqual(frames[id]?.origin.x, frames[fixture.frameID]?.origin.x)
        let compilation = StaticBuildCompiler.compile(document: session.document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertNotNil(compilation.plan)
        XCTAssertFalse(compilation.findings.contains { $0.code == "page-flow-containing-block" })
        let nestedHTML = try XCTUnwrap(compilation.plan?.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(nestedHTML.contains("data-siteforge-node=\"\(fixture.frameID)\""))
        XCTAssertTrue(nestedHTML.contains("data-siteforge-node=\"\(id)\""))
        let scene = CanvasViewportSceneID()
        let identity = ClipboardOperationIdentity(documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision,
            sceneID: scene, rendererGeneration: session.document.revision, selectedNodeIDs: [fixture.frameID])
        XCTAssertThrowsError(try ClipboardTransferRegistry().prepareCopy(identity: identity, document: session.document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedPageStructure)
        }
        let empty = ProjectCreation.blank().pages[0]
        XCTAssertTrue(empty.resolvedStructuralGeometry(viewportWidth: 390).isEmpty)
        XCTAssertEqual(CanonicalPageFlow.contentHeight(empty, breakpoint: .mobile, width: 390), 900)
    }

    private func connectedFixture(_ document: CanonicalDocument) -> Fixture {
        .init(document: document, pageID: document.pages[0].id, rootID: document.pages[0].rootNodeIDs[0],
              otherPageRootID: document.pages[1].rootNodeIDs[0], textParentID: NodeID(), frameID: NodeID(), textID: NodeID())
    }

    private func insertConnectedChild(_ kind: InsertionKind, parent: NodeID, size: WorldSize,
                                      session: DocumentSession) throws -> NodeID {
        let fixture = connectedFixture(session.document), id = NodeID()
        let input = command(kind, fixture: fixture, nodeID: id, parentID: parent,
            index: session.document.pages[0].nodes.first { $0.id == parent }?.childIDs.count ?? 0,
            geometry: .init(origin: .init(x: 777, y: 888), size: size))
        try session.execute(InsertionCommandRegistry().prepare(input, in: session.document, context: fixture.context).documentCommand)
        return id
    }

    private func setConnectedFixtureProperty(_ key: String, value: PropertyValue, nodeID: NodeID,
                                            session: DocumentSession) throws {
        let page = session.document.pages[0]
        let old = page.nodes.first { $0.id == nodeID }?.insertionProperty(key)
        try session.execute(.setProperty(.init(pageID: page.id, nodeID: nodeID,
            property: .init(id: old?.id ?? PropertyID(), key: .init(rawValue: key), value: value, origin: .authored))))
    }

    // SF-0501/0502/0503/1204: source acceptance; deliberately unrun in Prompt 9.
    func testConnectedNestedContainerOutputUsesResolvedOwnershipAtAllBreakpoints() async throws {
        let (session, header, bodies, footer) = try connectedPageSession()
        try session.execute(pageStructureCommand(.height(bodies[0], 600, .desktop), document: session.document, selected: bodies[0]))
        let stack = try insertConnectedChild(.stack, parent: bodies[0], size: .init(width: 600, height: 400), session: session)
        let grid = try insertConnectedChild(.grid, parent: stack, size: .init(width: 500, height: 300), session: session)
        let nested = try insertConnectedChild(.section, parent: grid, size: .init(width: 960, height: 320), session: session)
        let text = try insertConnectedChild(.text, parent: nested, size: .init(width: 120, height: 24), session: session)
        let original = session.document.pages[0]
        for width in [390.0, 520, 599.5, 768, 900, 1023.5, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let snapshot = ConnectedPageLayoutSnapshot(page: original, breakpoint: breakpoint, width: width)
            let gridFrame = try XCTUnwrap(snapshot.frames[grid])
            let nestedFrame = try XCTUnwrap(snapshot.frames[nested])
            let policy = try XCTUnwrap(snapshot.policies[grid])
            XCTAssertEqual(nestedFrame.origin.x, gridFrame.origin.x + policy.padding)
            XCTAssertEqual(nestedFrame.size.width, (gridFrame.size.width - 2 * policy.padding - policy.gap) / 2, accuracy: 0.0001)
            let tree = try InternalDocumentRenderTreeCompiler.compile(page: original, documentID: session.document.id,
                revision: session.document.revision, breakpoint: breakpoint, viewportWidth: width)
            let viewport = try CanvasViewportState(worldOrigin: .init(x: -30, y: 40), viewportSize: .init(width: 700, height: 500),
                contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: width, height: snapshot.contentHeight)),
                zoom: .init(1), pixelRatio: .init(2))
            let scene = try await WorkspaceScenePreparationWorker().prepare(.init(document: session.document,
                activePageID: original.id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID(),
                breakpoint: breakpoint, viewportWidth: width))
            for id in [header, bodies[0], stack, grid, nested, text, footer] {
                let frame = try XCTUnwrap(snapshot.frames[id]?.frame)
                XCTAssertEqual(tree.nodes.first { $0.id == id }?.frame, frame)
                XCTAssertEqual(scene.renderScene.objects.first { $0.id == id }?.frame, frame)
                XCTAssertEqual(scene.selectionScene?.targets.first { $0.id == id }?.frame, frame)
            }
        }
        let plan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("<header")); XCTAssertTrue(html.contains("<footer"))
        let stackStart = try XCTUnwrap(html.range(of: "data-siteforge-node=\"\(stack)\""))
        let nestedStart = try XCTUnwrap(html.range(of: "data-siteforge-node=\"\(nested)\""))
        let footerStart = try XCTUnwrap(html.range(of: "data-siteforge-node=\"\(footer)\""))
        XCTAssertLessThan(stackStart.lowerBound, nestedStart.lowerBound)
        XCTAssertLessThan(nestedStart.lowerBound, footerStart.lowerBound)
        XCTAssertEqual(html.components(separatedBy: "data-siteforge-node=\"\(nested)\"").count - 1, 1)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("max(1px,calc(100%")); XCTAssertTrue(css.contains("/ 2)"))
        XCTAssertTrue(css.contains("(width < 600px)")); XCTAssertTrue(css.contains("(width < 1024px)"))
        XCTAssertFalse(css.contains("left: 777")); XCTAssertFalse(css.contains("top: 888"))
        XCTAssertEqual(session.document.pages[0], original)
        try setConnectedFixtureProperty("layout.width", value: .number(280), nodeID: stack, session: session)
        let resized = ConnectedPageLayoutSnapshot(page: session.document.pages[0], breakpoint: .desktop, width: 1440)
        XCTAssertEqual(resized.frames[nested]?.size.width, 80)
        try session.undo(); XCTAssertEqual(session.document.pages[0], original)
        try session.redo(); XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == stack }?.insertionGeometry?.size.width, 280)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testConnectedHiddenFlowBoundariesNeverUseInvisibleFrames() throws {
        let (session, _, bodies, footer) = try connectedPageSession()
        for id in [bodies[0], footer] {
            try setConnectedFixtureProperty(ResponsiveVisibilityResolver.key(.mobile), value: .boolean(false), nodeID: id, session: session)
        }
        let page = session.document.pages[0], root = try XCTUnwrap(page.nodes.first { $0.id == page.rootNodeIDs[0] })
        let index = CanonicalPageFlow.insertionIndex(role: .body, parent: root, page: page,
            pointerY: 9999, breakpoint: .mobile, width: 390)
        XCTAssertEqual(index, root.childIDs.firstIndex(of: footer))
        let boundary = CanonicalPageFlow.boundaryFrame(parent: root, page: page, index: index, breakpoint: .mobile, width: 390)
        XCTAssertEqual(boundary.origin.y, 440)
        XCTAssertEqual(boundary.size.width, 390)
        XCTAssertEqual(page.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 390)[bodies[1]]?.origin.y, 120)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testConnectedHorizontalStackMinimaRemainBoundedAndOutputHasSingleOwner() throws {
        let (session, _, bodies, _) = try connectedPageSession()
        let stack = try insertConnectedChild(.stack, parent: bodies[0], size: .init(width: 300, height: 120), session: session)
        try setConnectedFixtureProperty(ContainerLayoutField.axis.propertyKey, value: .string("horizontal"), nodeID: stack, session: session)
        let small = try insertConnectedChild(.frame, parent: stack, size: .init(width: 1, height: 40), session: session)
        let large = try insertConnectedChild(.frame, parent: stack, size: .init(width: 999, height: 40), session: session)
        let page = session.document.pages[0]
        let snapshot = ConnectedPageLayoutSnapshot(page: page, breakpoint: .desktop, width: 1440)
        let parent = try XCTUnwrap(snapshot.frames[stack]), first = try XCTUnwrap(snapshot.frames[small]), last = try XCTUnwrap(snapshot.frames[large])
        XCTAssertEqual(first.size.width, 1)
        XCTAssertEqual(last.size.width, 227, accuracy: 0.0001)
        XCTAssertEqual(last.frame.maxX, parent.frame.maxX - 24, accuracy: 0.0001)
        XCTAssertEqual(page.nodes.first { $0.id == large }?.insertionGeometry?.size.width, 999)
        let css = ConnectedPageOutput.css(pages: [page])
        XCTAssertTrue(css.contains("display:flex;")); XCTAssertTrue(css.contains("flex-direction:row;"))
        XCTAssertTrue(css.contains("gap:24.0px;")); XCTAssertTrue(css.contains("padding:24.0px;"))
        XCTAssertTrue(css.contains("flex:0 1 999.0px"))
        XCTAssertFalse(css.contains("left: 777.0px"))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testConnectedRootPaddingHeightRemovalAndReorderHaveExactHistory() throws {
        let (session, header, bodies, footer) = try connectedPageSession()
        let root = session.document.pages[0].rootNodeIDs[0]
        try setConnectedFixtureProperty(DesignBoxStyleCommandRegistry.namespace + "padding.uniform", value: .number(24), nodeID: root, session: session)
        let before = session.document.pages
        for breakpoint in ResponsiveBreakpoint.allCases {
            let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
            let snapshot = ConnectedPageLayoutSnapshot(page: session.document.pages[0], breakpoint: breakpoint, width: width)
            XCTAssertEqual(snapshot.frames[header]?.origin.y, 24)
            XCTAssertEqual(snapshot.frames[header]?.size.height, 120)
            XCTAssertEqual(snapshot.frames[header]?.size.width, width - 48)
            XCTAssertEqual(snapshot.contentHeight, 1008)
        }
        try session.execute(pageStructureCommand(.height(footer, 1200, .desktop), document: session.document, selected: footer))
        XCTAssertEqual(CanonicalPageFlow.contentHeight(session.document.pages[0], breakpoint: .desktop, width: 1440), 2008)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.execute(.removeNode(.init(pageID: session.document.pages[0].id, nodeID: bodies[0])))
        let afterRemoval = session.document.pages
        XCTAssertEqual(session.document.pages[0].resolvedStructuralGeometry(viewportWidth: 1440)[bodies[1]]?.origin.y, 144)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, afterRemoval)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testHeaderFooterDefaultsUseEditableCanonicalContentsAndStablePageLinks() throws {
        let (session, headerID, _, footerID) = try connectedPageSession()
        let baseline = session.document
        try baseline.validate()
        let page = baseline.pages[0]
        for ownerID in [headerID, footerID] {
            let owner = try XCTUnwrap(page.nodes.first { $0.id == ownerID })
            let contentID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner))
            let titleID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.titleKey, on: owner))
            let navigationID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner))
            XCTAssertEqual(owner.childIDs, [contentID])
            XCTAssertEqual(page.nodes.first { $0.id == contentID }?.childIDs, [titleID, navigationID])
            XCTAssertEqual(page.nodes.first { $0.id == titleID }?.kind, .text)
            XCTAssertEqual(CanonicalPageChrome.links(owner: owner, page: page).count,
                baseline.websitePages.filter { $0.role != .notFound }.count)
            for breakpoint in ResponsiveBreakpoint.allCases {
                let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
                let frames = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
                let ownerFrame = try XCTUnwrap(frames[ownerID]?.frame)
                for id in [contentID, titleID, navigationID] {
                    let frame = try XCTUnwrap(frames[id]?.frame)
                    XCTAssertGreaterThanOrEqual(frame.minX, ownerFrame.minX)
                    XCTAssertGreaterThanOrEqual(frame.minY, ownerFrame.minY)
                    XCTAssertLessThanOrEqual(frame.maxX, ownerFrame.maxX + 0.001)
                    XCTAssertLessThanOrEqual(frame.maxY, ownerFrame.maxY + 0.001)
                }
            }
        }
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(baseline)), baseline)
        try session.undo(); try session.redo()
        XCTAssertEqual(session.document.pages, baseline.pages)
    }

    func testSchema16RemainsReadableWithoutChromeAndCannotForgeSchema17References() throws {
        let legacy = makeFixture().document
        let bytes = try DocumentSerializer.encode(legacy)
        var oldEnvelope = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        oldEnvelope["schemaVersion"] = 16
        var oldDocument = try XCTUnwrap(oldEnvelope["document"] as? [String: Any])
        oldDocument.removeValue(forKey: "websiteMetadata") // Not part of schema 16.
        oldEnvelope["document"] = oldDocument
        let old = try JSONSerialization.data(withJSONObject: oldEnvelope)
        XCTAssertEqual(try DocumentSerializer.decode(old), legacy)
        let (session, _, _, _) = try connectedPageSession()
        let authored = try DocumentSerializer.encode(session.document)
        var forgedEnvelope = try XCTUnwrap(JSONSerialization.jsonObject(with: authored) as? [String: Any])
        forgedEnvelope["schemaVersion"] = 16
        var forgedDocument = try XCTUnwrap(forgedEnvelope["document"] as? [String: Any])
        forgedDocument.removeValue(forKey: "websiteMetadata")
        forgedEnvelope["document"] = forgedDocument
        let forged = try JSONSerialization.data(withJSONObject: forgedEnvelope)
        XCTAssertThrowsError(try DocumentSerializer.decode(forged))
        XCTAssertEqual(try DocumentSerializer.decode(authored), session.document)
    }

    func testManagedHeaderContentsRejectIgnoredGeometryAndDoNotOfferTransformHandles() async throws {
        let (session, headerID, _, _) = try connectedPageSession()
        let original = session.document
        let owner = try XCTUnwrap(original.pages[0].nodes.first { $0.id == headerID })
        let contentID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner))
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        let deadline = ContinuousClock.now + .seconds(3)
        while !state.layerTargets.contains(where: { $0.id == contentID }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        state.selectLayer(contentID)
        XCTAssertEqual(state.selectionState.primaryID, contentID)
        XCTAssertTrue(state.hasManagedPageStructureSelection)
        XCTAssertFalse(state.geometryInspectorAvailability(for: .width).isEnabled)
        XCTAssertFalse(state.transformAvailability(.move(delta: .init(dx: 1, dy: 1), constraint: .none)).isEnabled)
        XCTAssertFalse(state.transformOverlays.contains { $0.kind.hasPrefix("transform-handle-") })
        XCTAssertEqual(state.selectedPageChromeOwner?.id, headerID)
        XCTAssertEqual(session.document, original)
    }

    func testHeaderDefaultAndAuthoredTitleUseSameResolutionInInspectorRendererAndOutput() throws {
        let (session, headerID, _, _) = try connectedPageSession()
        let owner = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == headerID })
        let titleID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.titleKey, on: owner))
        let oldTitle = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == titleID })
        let homeID = session.document.pages[0].id
        try session.execute(.renamePage(.init(pageID: homeID, name: "New Home Name")))
        func assertResolved(_ expected: String) throws {
            let page = session.document.pages[0]
            let title = try XCTUnwrap(page.nodes.first { $0.id == titleID })
            XCTAssertEqual(CanonicalPageChrome.titleText(title, in: session.document), expected)
            XCTAssertEqual(CanonicalPageChrome.resolvedLabels(in: page, document: session.document).nodes.first {
                $0.id == titleID
            }?.insertionStringProperty("content.text"), expected)
            let output = try MultiPageStaticBuildPlanner.plan(document: session.document)
            XCTAssertTrue(try XCTUnwrap(output.files.first { $0.path == "index.html" }?.contents).contains(expected))
        }
        try assertResolved("New Home Name")
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == titleID }?.properties, oldTitle.properties)
        try session.execute(pageStructureCommand(.title(headerID, text: "My Studio"), document: session.document, selected: headerID))
        try session.execute(.renamePage(.init(pageID: homeID, name: "Another Home Name")))
        try assertResolved("My Studio")
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testHeaderContentsTitleInclusionCustomizationAndExactHistory() throws {
        let (session, headerID, _, _) = try connectedPageSession()
        let original = session.document
        let owner = try XCTUnwrap(original.pages[0].nodes.first { $0.id == headerID })
        let titleID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.titleKey, on: owner))
        let contentID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner))
        let destination = try XCTUnwrap(original.websitePages.first { $0.role != .notFound })
        let link = try XCTUnwrap(CanonicalPageChrome.links(owner: owner, page: original.pages[0]).first {
            $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == destination.id.description
        })
        let edits: [PageStructureEdit] = [
            .title(headerID, text: "My Studio"), .showTitle(headerID, false),
            .includePage(headerID, destination.id, false), .includePage(headerID, destination.id, true),
            .editLink(owner: headerID, link: link.id, pageID: destination.id, label: "Our Home"),
            .contentLayout(headerID, axis: .vertical, gap: 8, alignment: .end), .automaticLayout(headerID)]
        for edit in edits {
            let before = session.document
            let command = try pageStructureCommand(edit, document: before, selected: headerID)
            try session.execute(command)
            let after = session.document
            try after.validate()
            XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(after)), after)
            try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
            try session.redo(); XCTAssertEqual(session.document.pages, after.pages)
        }
        let page = session.document.pages[0]
        XCTAssertEqual(page.nodes.first { $0.id == titleID }?.insertionStringProperty("content.text"), "My Studio")
        XCTAssertTrue(page.nodes.first { $0.id == titleID }?.selectionBooleanProperty("hidden") == true)
        XCTAssertEqual(page.nodes.first { $0.id == contentID }?.insertionStringProperty("layout.axis"), "horizontal")
        XCTAssertEqual(page.nodes.first { $0.id == link.id }?.controlLabel, "Our Home")
        XCTAssertFalse(page.nodes.first { $0.id == link.id }?.selectionBooleanProperty("hidden") ?? true)
        XCTAssertFalse(CanonicalPageChrome.isCustom(try XCTUnwrap(page.nodes.first { $0.id == headerID })))
        XCTAssertEqual(Set(page.nodes.map(\.id)), Set(original.pages[0].nodes.map(\.id)))
        for invalid in [PageStructureEdit.title(headerID, text: ""), .title(headerID, text: "bad\nlabel"),
                        .contentLayout(headerID, axis: .horizontal, gap: .nan, alignment: .start)] {
            XCTAssertThrowsError(try pageStructureCommand(invalid, document: session.document, selected: headerID))
        }
        XCTAssertThrowsError(try pageStructureCommand(.showTitle(headerID, true), document: session.document,
                                                     selected: headerID, cancelled: true))
        XCTAssertEqual(session.document.pages[0], page)
    }

    func testLegacyHeaderExplicitContentsUpgradePreservesLinksAndUndo() throws {
        let (initial, headerID, _, _) = try connectedPageSession()
        var legacy = initial.document
        let index = try XCTUnwrap(legacy.pages[0].nodes.firstIndex { $0.id == headerID })
        let owner = legacy.pages[0].nodes[index]
        let links = CanonicalPageChrome.links(owner: owner, page: legacy.pages[0])
        let chromeIDs = Set(CanonicalPageChrome.referenceKeys.compactMap { CanonicalPageChrome.reference($0, on: owner) })
        legacy.pages[0].nodes[index].childIDs = links.map(\.id)
        legacy.pages[0].nodes[index].properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalPageChrome.namespace) }
        for child in legacy.pages[0].nodes.indices where links.contains(where: { $0.id == legacy.pages[0].nodes[child].id }) {
            legacy.pages[0].nodes[child].parent = .node(headerID)
        }
        legacy.pages[0].nodes.removeAll { chromeIDs.contains($0.id) }
        try legacy.validate()
        let session = DocumentSession(document: legacy)
        try session.execute(pageStructureCommand(.editableContents(headerID), document: legacy, selected: headerID))
        let upgraded = session.document
        try upgraded.validate()
        let upgradedOwner = try XCTUnwrap(upgraded.pages[0].nodes.first { $0.id == headerID })
        XCTAssertEqual(CanonicalPageChrome.links(owner: upgradedOwner, page: upgraded.pages[0]).map(\.id), links.map(\.id))
        XCTAssertEqual(CanonicalPageChrome.links(owner: upgradedOwner, page: upgraded.pages[0]).map(\.properties), links.map(\.properties))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(upgraded)), upgraded)
        try session.undo(); XCTAssertEqual(session.document.pages, legacy.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, upgraded.pages)
    }

    func testHeaderContentsDuplicateRemapsRolesAndStaticNavigationUsesSameGeometry() throws {
        let (session, headerID, _, _) = try connectedPageSession()
        try session.execute(pageStructureCommand(.title(headerID, text: "Studio & Company"), document: session.document, selected: headerID))
        let source = session.document
        let owner = try XCTUnwrap(source.pages[0].nodes.first { $0.id == headerID })
        let navigationID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner))
        let output = try MultiPageStaticBuildPlanner.plan(document: source)
        let html = try XCTUnwrap(output.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("Studio &amp; Company"))
        XCTAssertTrue(html.contains("sf-page-navigation-\(navigationID)"))
        XCTAssertTrue(html.contains("aria-expanded=\"false\""))
        XCTAssertTrue(html.contains("aria-label=\"Footer navigation\""))
        let css = try XCTUnwrap(output.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains(".sf-page-navigation-\(navigationID) { display:block;left:0.0px;top:0.0px;"))
        let prepared = try PageCommandRegistry().prepare(.duplicate, identity: .init(documentID: source.id,
            revision: source.revision, pageID: source.pages[0].id), in: source, isAvailable: true)
        try session.execute(prepared.command)
        let copied = try XCTUnwrap(session.document.pages.first { $0.id == prepared.selectedPageID })
        let copiedOwner = try XCTUnwrap(copied.nodes.first { CanonicalPageFlow.role($0) == .header })
        for key in CanonicalPageChrome.referenceKeys {
            let id = try XCTUnwrap(CanonicalPageChrome.reference(key, on: copiedOwner))
            XCTAssertNotEqual(id, CanonicalPageChrome.reference(key, on: owner))
            XCTAssertTrue(copied.nodes.contains { $0.id == id })
        }
        XCTAssertTrue(Set(copied.nodes.map(\.id)).isDisjoint(with: Set(source.pages[0].nodes.map(\.id))))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo(); XCTAssertEqual(session.document.pages, source.pages)
    }

    func testResponsiveHeaderMenuUsesOneSurfaceAndKeepsLinkIdentityWithoutGhostTargets() async throws {
        let (session, headerID, _, _) = try connectedPageSession()
        let original = session.document
        let page = original.pages[0]
        let owner = try XCTUnwrap(page.nodes.first { $0.id == headerID })
        let navigationID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner))
        let memberIDs = Set(CanonicalPageChrome.links(owner: owner, page: page).map(\.id))
        let css = ConnectedPageOutput.css(pages: [page])
        XCTAssertTrue(ConnectedPageOutput.menuCSS.contains("cursor:pointer;white-space:nowrap;"))
        XCTAssertTrue(css.contains(".sf-page-navigation-\(navigationID) { display:flex;justify-content:flex-end; }"))
        XCTAssertTrue(css.contains(".sf-page-navigation-\(navigationID) .sf-nav-menu { flex:none;max-width:none;margin:0; }"))
        for breakpoint in ResponsiveBreakpoint.allCases {
            let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
            let viewport = try CanvasViewportState(worldOrigin: .init(x: -30, y: 40), viewportSize: .init(width: 700, height: 500),
                contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: width, height: 1200)), zoom: .init(1), pixelRatio: .init(2))
            let scene = try await WorkspaceScenePreparationWorker().prepare(.init(document: original, activePageID: page.id,
                activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID(), breakpoint: breakpoint, viewportWidth: width))
            let navigation = try XCTUnwrap(scene.renderScene.objects.first { $0.id == navigationID })
            XCTAssertEqual(navigation.navigation?.ownerID, headerID)
            XCTAssertNil(scene.renderScene.objects.first { $0.id == headerID }?.navigation)
            XCTAssertEqual(navigation.navigation?.links.map(\.id), CanonicalPageChrome.links(owner: owner, page: page).map(\.id))
            if breakpoint == .mobile {
                XCTAssertEqual(navigation.plainText, "☰ Menu")
                XCTAssertTrue(memberIDs.isDisjoint(with: Set(scene.renderScene.objects.map(\.id))))
                for id in memberIDs {
                    let target = try XCTUnwrap(scene.selectionScene?.targets.first { $0.id == id })
                    XCTAssertTrue(target.isAvailable); XCTAssertFalse(target.isVisible)
                    XCTAssertFalse(target.participatesInCanvasTraversal)
                }
            } else {
                XCTAssertTrue(memberIDs.isSubset(of: Set(scene.renderScene.objects.map(\.id))))
            }
        }
        XCTAssertEqual(session.document, original)
    }

    func testConnectedNavigationVisibilityCapacityAccessibilityAndNoDecorativeMenu() throws {
        let (session, header, _, footer) = try connectedPageSession()
        let footerOwner = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == footer })
        for link in CanonicalPageChrome.links(owner: footerOwner, page: session.document.pages[0]) {
            try session.execute(pageStructureCommand(.removeLink(owner: footer, link: link.id), document: session.document, selected: footer))
        }
        for _ in 0..<4 {
            try session.execute(pageStructureCommand(.addLink(owner: header, pageID: session.document.pages[0].id), document: session.document, selected: header))
        }
        try session.execute(pageStructureCommand(.hamburger(header, true), document: session.document, selected: header))
        let page = session.document.pages[0], owner = try XCTUnwrap(page.nodes.first { $0.id == header })
        let linkIDs = CanonicalPageChrome.links(owner: owner, page: page).map(\.id)
        try setConnectedFixtureProperty(CanonicalLinkTarget.namespace + "context", value: .string("new"), nodeID: linkIDs[0], session: session)
        for alignment in ["start", "center", "end", "stretch"] {
            for width in [1.0, 80, 294, 1344] {
                let layout = CanonicalPageFlow.navigationLayout(availableWidth: width, count: 4, alignment: alignment)
                XCTAssertGreaterThan(layout.width, 0)
                XCTAssertLessThanOrEqual(layout.offset + 4 * layout.width + 3 * layout.gap, width + 0.001)
            }
        }
        for id in linkIDs {
            try setConnectedFixtureProperty(ResponsiveVisibilityResolver.key(.mobile), value: .boolean(false), nodeID: id, session: session)
        }
        let hiddenPage = session.document.pages[0], hiddenOwner = try XCTUnwrap(hiddenPage.nodes.first { $0.id == header })
        XCTAssertNil(CanonicalPageFlow.navigation(owner: hiddenOwner, page: hiddenPage, document: session.document, breakpoint: .mobile))
        let desktop = try XCTUnwrap(CanonicalPageFlow.navigation(owner: hiddenOwner, page: hiddenPage, document: session.document, breakpoint: .desktop))
        XCTAssertEqual(desktop.currentPageID, hiddenPage.id); XCTAssertEqual(desktop.rowHeight, 24)
        XCTAssertEqual(desktop.links.first?.context, .new)
        let plan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("aria-current=\"page\"")); XCTAssertTrue(html.contains("aria-controls=\"sf-nav-panel-"))
        XCTAssertTrue(html.contains("aria-expanded=\"false\"")); XCTAssertTrue(html.contains("Header navigation"))
        XCTAssertTrue(html.contains("target=\"_blank\" rel=\"noopener noreferrer\""))
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains(".sf-nav-link-\(linkIDs[0]) { display:none; }"))
        let navigationID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: owner))
        XCTAssertTrue(css.contains(".sf-page-navigation-\(navigationID) { display:none; }"))
        let script = try XCTUnwrap(plan.files.first { $0.path == "siteforge-navigation.js" }?.contents)
        // Safari AX activation can focus the document before its target link.
        // That transient focus must not dismiss the link before activation.
        XCTAssertTrue(script.contains("if(event.target===document.body||event.target===document.documentElement)return"))
        XCTAssertTrue(script.contains("aria-expanded")); XCTAssertTrue(script.contains("matchMedia")); XCTAssertTrue(script.contains("Escape"))
        for id in linkIDs {
            try session.execute(pageStructureCommand(.removeLink(owner: header, link: id), document: session.document, selected: header))
        }
        let emptyPlan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        XCTAssertFalse(try XCTUnwrap(emptyPlan.files.first { $0.path == "index.html" }?.contents).contains("<summary"))
        XCTAssertFalse(emptyPlan.files.contains { $0.path == "siteforge-navigation.js" })
    }

    func testConnectedOutputRejectsPositionedOrClippedMenusWithoutDroppingIntent() throws {
        let (session, header, _, _) = try connectedPageSession()
        try session.execute(pageStructureCommand(.addLink(owner: header, pageID: session.document.pages[0].id), document: session.document, selected: header))
        try session.execute(pageStructureCommand(.hamburger(header, true), document: session.document, selected: header))
        try setConnectedFixtureProperty(DesignBoxStyleCommandRegistry.namespace + "clip.content", value: .boolean(true), nodeID: header, session: session)
        let before = session.document
        let result = StaticBuildCompiler.compile(document: before, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertNil(result.plan)
        XCTAssertTrue(result.findings.contains { $0.code == "page-flow-navigation-clipped" && $0.affectedNodeID == header })
        XCTAssertEqual(session.document, before)
        try session.undo()
        XCTAssertNotNil(StaticBuildCompiler.compile(document: session.document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:]).plan)
        let free = try insertConnectedChild(.frame, parent: session.document.pages[0].rootNodeIDs[0], size: .init(width: 200, height: 120), session: session)
        let identity = ClipboardOperationIdentity(documentID: session.document.id, pageID: session.document.pages[0].id,
            revision: session.document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: session.document.revision,
            selectedNodeIDs: [free])
        let envelope = try ClipboardTransferRegistry().prepareCopy(identity: identity, document: session.document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(envelope.nodes.map(\.id), [free])
        XCTAssertFalse(envelope.nodes.contains(where: CanonicalPageFlow.isManaged))
        try setConnectedFixtureProperty(CanonicalPositioning.namespace + "mode", value: .string("fixed"), nodeID: free, session: session)
        let positioned = session.document
        let rejected = StaticBuildCompiler.compile(document: positioned, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertNil(rejected.plan)
        XCTAssertTrue(rejected.findings.contains { $0.code == "page-flow-positioning" && $0.affectedNodeID == free })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(positioned)), positioned)
    }

    func testConnectedStructuredEmitterRejectsCyclesAndRetainsLegacyFlatOutput() throws {
        let root = NodeID(), child = NodeID(), rect = WorldRect(origin: .init(x: 0, y: 0), size: .init(width: 100, height: 40))
        let cyclic = InternalRenderTreeNode(id: root, sourceNodeID: root, parentNodeID: root, paintOrder: 0,
            frame: rect, semanticElement: "div", cssSelector: CanonicalCSSRule.selector(for: root), formField: nil, usesConnectedLayout: true)
        XCTAssertThrowsError(try SafeHTMLEmitter.emit(.init(documentID: DocumentID(), revision: 0, nodes: [cyclic]))) {
            XCTAssertEqual($0 as? SafeHTMLEmissionError, .invalidIdentity)
        }
        let nodes = [InternalRenderTreeNode(id: root, sourceNodeID: root, paintOrder: 0, frame: rect,
            semanticElement: "div", cssSelector: CanonicalCSSRule.selector(for: root), formField: nil),
            InternalRenderTreeNode(id: child, sourceNodeID: child, parentNodeID: root, paintOrder: 1, frame: rect,
            semanticElement: "section", cssSelector: CanonicalCSSRule.selector(for: child), formField: nil)]
        let html = try SafeHTMLEmitter.emit(.init(documentID: DocumentID(), revision: 0, nodes: nodes))
        XCTAssertTrue(html.contains("</div>\n<section"))
    }

    func testConnectedPageFlowSceneRenderSelectionAndHitFramesShareResolvedGeometryAtScale() async throws {
        let (session, header, bodies, footer) = try connectedPageSession()
        let page = session.document.pages[0]
        for breakpoint in ResponsiveBreakpoint.allCases {
            let width = CanonicalPageFlow.pageWidth(breakpoint, nil)
            let resolved = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
            for zoom in [0.25, 1.0, 8.0] {
                for backing in [1.0, 2.0] {
                    for pan in [-40.0, 40.0] {
                        let viewport = try CanvasViewportState(worldOrigin: .init(x: pan, y: pan),
                            viewportSize: .init(width: 680, height: 440),
                            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: width, height: 960)),
                            zoom: .init(zoom), pixelRatio: .init(backing))
                        let result = try await WorkspaceScenePreparationWorker().prepare(.init(document: session.document,
                            activePageID: page.id, activeContainerID: nil, viewport: viewport,
                            surfaceID: CanvasRenderSurfaceID(), breakpoint: breakpoint, viewportWidth: width))
                        for id in [header] + bodies + [footer] {
                            let frame = try XCTUnwrap(resolved[id]?.frame)
                            XCTAssertEqual(result.renderScene.objects.first { $0.id == id }?.frame, frame)
                            XCTAssertEqual(result.selectionScene?.targets.first { $0.id == id }?.frame, frame)
                        }
                    }
                }
            }
        }
        XCTAssertEqual(session.document.pages[0], page)
    }

    func testDividerAndSiteSectionTemplatesUseCanonicalInsertionAndSemanticRoles() throws {
        for template in [AuthoringElementTemplate.divider, .header, .navigation, .footer] {
            let fixture = makeFixture()
            let id = NodeID()
            let geometry = InsertionGeometry(origin: .init(x: 20, y: 30), size: template.size)
            let operation = command(template.insertionKind, fixture: fixture, nodeID: id,
                                    geometry: geometry)
            let prepared = try InsertionCommandRegistry().prepare(operation,
                in: fixture.document, context: fixture.context, template: template)
            XCTAssertEqual(prepared.node.id, id)
            XCTAssertEqual(prepared.node.name, template.rawValue.capitalized)
            XCTAssertEqual(prepared.geometry.size, template.size)
            XCTAssertEqual(prepared.node.kind, template.insertionKind.nodeKind)
            XCTAssertEqual(prepared.node.insertionStringProperty(CanonicalSemanticElement.key),
                template.semanticElement?.rawValue)
            if template == .divider {
                XCTAssertEqual(prepared.node.insertionStringProperty("style.border"), "none")
            }
            let session = DocumentSession(document: fixture.document)
            try session.execute(prepared.documentCommand)
            XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == id }?.name,
                template.rawValue.capitalized)
            try session.undo()
            XCTAssertNil(session.document.pages[0].nodes.first { $0.id == id })
            try session.redo()
            XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == id }?.id, id)
        }
    }

    // SF-AUTHORING-099: Heading is one canonical Text insertion whose
    // semantic and typography defaults remain editable by existing systems.
    func testHeadingTemplateUsesCanonicalTextSemanticAndTypographyDefaults() throws {
        let fixture = makeFixture()
        let id = NodeID()
        let template = AuthoringElementTemplate.heading
        let operation = command(.text, fixture: fixture, nodeID: id,
            geometry: .init(origin: .init(x: 20, y: 30), size: template.size))
        let prepared = try InsertionCommandRegistry().prepare(operation,
            in: fixture.document, context: fixture.context, template: template)
        XCTAssertEqual(prepared.node.kind, .text)
        XCTAssertEqual(prepared.node.name, "Heading")
        XCTAssertEqual(prepared.geometry.size, .init(width: 360, height: 48))
        XCTAssertEqual(prepared.node.insertionStringProperty("content.text"), "Heading")
        XCTAssertEqual(prepared.node.insertionStringProperty(CanonicalSemanticElement.key), "h2")
        XCTAssertEqual(prepared.node.insertionStringProperty(CanonicalTypography.namespace + "weight"), "bold")
        XCTAssertEqual(prepared.node.insertionNumberProperty(CanonicalTypography.namespace + "size"), 32)
        XCTAssertEqual(prepared.node.insertionNumberProperty(CanonicalTypography.namespace + "lineHeight"), 38)
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared.documentCommand)
        XCTAssertNoThrow(try session.document.validate())
        try session.undo(); try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == id }?.id, id)
    }

    // SF-0405-001, SF-0405-002, SF-0405-004, SF-0405-005
    func testFrameAndTextDefaultsHaveStableIdentityOwnershipOrderAndOrigins() throws {
        let fixture = makeFixture()
        let frame = try prepare(.frame, fixture: fixture, nodeID: fixture.frameID, index: 0)
        let text = try prepare(.text, fixture: fixture, nodeID: fixture.textID, index: 1)

        XCTAssertEqual(frame.node.kind, .frame)
        XCTAssertEqual(frame.node.parent, .node(fixture.rootID))
        XCTAssertEqual(frame.geometry.size, .init(width: 240, height: 160))
        XCTAssertEqual(frame.node.insertionStringProperty("style.fill"), "surface")
        XCTAssertEqual(frame.node.insertionStringProperty("style.border"), "subtle")
        XCTAssertEqual(frame.node.insertionProperty("style.fill")?.origin, .defaulted)
        XCTAssertEqual(frame.node.insertionProperty("style.border")?.origin, .defaulted)
        XCTAssertEqual(text.node.kind, .text)
        XCTAssertEqual(text.node.insertionStringProperty("content.text"), "Text")
        XCTAssertEqual(text.geometry.size, .init(width: 120, height: 24))
        XCTAssertEqual(text.node.insertionProperty("content.text")?.origin, .defaulted)
        XCTAssertEqual(frame.node.insertionProperty("layout.x")?.origin, .authored)
        XCTAssertEqual(frame.node.properties.map(\.id), try prepare(.frame, fixture: fixture, nodeID: fixture.frameID, index: 0).node.properties.map(\.id))

        let session = DocumentSession(document: fixture.document)
        try session.execute(frame.documentCommand)
        try session.execute(text.documentCommand)
        let parent = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.rootID })
        XCTAssertEqual(parent.childIDs, [fixture.frameID, fixture.textID, fixture.textParentID])
        XCTAssertEqual(session.document.pages[0].nodes.filter { [fixture.frameID, fixture.textID].contains($0.id) }.map(\.id), [fixture.frameID, fixture.textID])
        XCTAssertNoThrow(try session.document.validate())
    }

    // SF-0405-001, SF-0502-001, SF-0503-001 — v1 structural defaults are
    // canonical, deterministic, and accepted by the same atomic registry.
    func testStructuralContainerDefaultsAreCanonicalAndDeterministic() throws {
        let fixture = makeFixture()
        let section = try prepare(.section, fixture: fixture, nodeID: fixture.frameID)
        let stack = try prepare(.stack, fixture: fixture, nodeID: fixture.textID)
        let grid = try prepare(.grid, fixture: fixture, nodeID: NodeID())

        XCTAssertEqual(section.node.kind, .section)
        XCTAssertEqual(section.geometry.size, .init(width: 960, height: 320))
        XCTAssertEqual(section.node.insertionNumberProperty("layout.padding"), 48)
        XCTAssertEqual(stack.node.kind, .stack)
        XCTAssertEqual(stack.node.insertionStringProperty("layout.axis"), "vertical")
        XCTAssertEqual(stack.node.insertionNumberProperty("layout.padding"), 24)
        XCTAssertEqual(stack.node.insertionNumberProperty("layout.gap"), 24)
        XCTAssertEqual(stack.node.insertionStringProperty("layout.align"), "start")
        XCTAssertEqual(grid.node.kind, .grid)
        XCTAssertEqual(grid.node.insertionNumberProperty("layout.grid.columns"), 2)
        XCTAssertEqual(grid.node.insertionStringProperty("layout.grid.placement"), "row-major")
        XCTAssertTrue(section.node.properties.allSatisfy { $0.origin == .defaulted || $0.key.rawValue == "layout.x" || $0.key.rawValue == "layout.y" })
    }

    // SF-0405-001, SF-1006-001 — Form uses the same bounded, canonical
    // container insertion transaction as structural elements. It is empty
    // until an author explicitly adds Text children to configure as fields.
    func testFormInsertionIsCanonicalEmptyContainerWithStableIdentity() throws {
        let fixture = makeFixture()
        let formID = NodeID(UUID(uuidString: "61000000-0000-4000-8000-000000000001")!)
        let prepared = try prepare(.form, fixture: fixture, nodeID: formID)

        XCTAssertEqual(prepared.node.kind, .form)
        XCTAssertEqual(prepared.node.id, formID)
        XCTAssertEqual(prepared.node.parent, .node(fixture.rootID))
        XCTAssertEqual(prepared.node.childIDs, [])
        XCTAssertEqual(prepared.geometry.size, .init(width: 320, height: 180))

        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == formID }?.kind, .form)
        XCTAssertNoThrow(try session.document.validate())
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == formID })
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == formID }?.id, formID)
    }

    // SF-0502-001, SF-0503-001 — render/selection geometry derives from the
    // one canonical hierarchy, not an editor preview or stored duplicate.
    func testStackAndGridResolveChildrenFromCanonicalDefaults() throws {
        let fixture = makeFixture()
        let stackID = NodeID()
        let firstID = NodeID()
        let secondID = NodeID()
        let stack = try prepare(.stack, fixture: fixture, nodeID: stackID)
        var document = fixture.document
        document.pages[0].nodes.append(stack.node)
        document.pages[0].nodes[0].childIDs.insert(stackID, at: 0)
        let first = DocumentNode(id: firstID, kind: .frame, name: "First", parent: .node(stackID), properties: geometryProperties(firstID, x: 999, y: 999, width: 100, height: 40))
        let second = DocumentNode(id: secondID, kind: .frame, name: "Second", parent: .node(stackID), properties: geometryProperties(secondID, x: 999, y: 999, width: 100, height: 40))
        document.pages[0].nodes[document.pages[0].nodes.firstIndex(where: { $0.id == stackID })!].childIDs = [firstID, secondID]
        document.pages[0].nodes += [first, second]
        let resolved = document.pages[0].resolvedStructuralGeometry()
        XCTAssertEqual(resolved[firstID]?.origin, .init(x: 44, y: 54))
        XCTAssertEqual(resolved[secondID]?.origin, .init(x: 44, y: 118))

        let gridID = NodeID()
        let grid = try prepare(.grid, fixture: fixture, nodeID: gridID)
        var gridDocument = fixture.document
        gridDocument.pages[0].nodes.append(grid.node)
        gridDocument.pages[0].nodes[0].childIDs.insert(gridID, at: 0)
        let gridChildren = (0..<3).map { index in
            DocumentNode(id: NodeID(), kind: .frame, name: "Grid child \(index)", parent: .node(gridID), properties: geometryProperties(NodeID(), x: 900, y: 900, width: 40, height: 30))
        }
        gridDocument.pages[0].nodes[gridDocument.pages[0].nodes.firstIndex(where: { $0.id == gridID })!].childIDs = gridChildren.map(\.id)
        gridDocument.pages[0].nodes += gridChildren
        let gridResolved = gridDocument.pages[0].resolvedStructuralGeometry()
        XCTAssertEqual(gridResolved[gridChildren[0].id]?.origin, .init(x: 44, y: 54))
        XCTAssertEqual(gridResolved[gridChildren[1].id]?.origin, .init(x: 152, y: 54))
        XCTAssertEqual(gridResolved[gridChildren[2].id]?.origin, .init(x: 44, y: 108))
        XCTAssertEqual(gridResolved[gridChildren[0].id]?.size.width, 84)
    }

    // SF-0502-003 / SF-0503-003 — authored controls and renderer adoption use
    // the same deterministic resolved child frames and stable child ordering.
    func testStructuralResolverAppliesSectionPaddingStackAxisAlignmentAndSparseGrid() throws {
        let fixture = makeFixture()
        let registry = InsertionCommandRegistry()
        func prepared(_ kind: InsertionKind, id: NodeID) throws -> PreparedInsertion {
            try registry.prepare(command(kind, fixture: fixture, nodeID: id), in: fixture.document, context: fixture.context)
        }
        let sectionID = NodeID(), stackID = NodeID(), gridID = NodeID()
        var section = try prepared(.section, id: sectionID).node
        var stack = try prepared(.stack, id: stackID).node
        var grid = try prepared(.grid, id: gridID).node
        let children = (0..<5).map { _ in NodeID() }

        func set(_ node: inout DocumentNode, _ key: String, _ value: PropertyValue) {
            let index = node.properties.firstIndex { $0.key.rawValue == key }!
            let property = node.properties[index]
            node.properties[index] = .init(id: property.id, key: property.key, value: value, origin: .authored)
        }
        set(&section, "layout.padding", .number(60))
        set(&stack, "layout.axis", .string("horizontal"))
        set(&stack, "layout.padding", .number(20))
        set(&stack, "layout.gap", .number(10))
        set(&stack, "layout.align", .string("end"))
        set(&grid, "layout.padding", .number(10))
        set(&grid, "layout.gap", .number(10))
        set(&grid, "layout.grid.columns", .number(3))

        section.childIDs = [children[0]]
        stack.childIDs = [children[1], children[2]]
        grid.childIDs = [children[3], children[4]]
        var document = fixture.document
        document.pages[0].nodes[0].childIDs = [sectionID, stackID, gridID, fixture.textParentID]
        document.pages[0].nodes += [section, stack, grid]
        document.pages[0].nodes += [
            DocumentNode(id: children[0], kind: .frame, name: "Section child", parent: .node(sectionID), properties: geometryProperties(children[0], x: 900, y: 900, width: 80, height: 30)),
            DocumentNode(id: children[1], kind: .frame, name: "Stack one", parent: .node(stackID), properties: geometryProperties(children[1], x: 900, y: 900, width: 40, height: 30)),
            DocumentNode(id: children[2], kind: .frame, name: "Stack two", parent: .node(stackID), properties: geometryProperties(children[2], x: 900, y: 900, width: 60, height: 50)),
            DocumentNode(id: children[3], kind: .frame, name: "Grid one", parent: .node(gridID), properties: geometryProperties(children[3], x: 900, y: 900, width: 40, height: 30)),
            DocumentNode(id: children[4], kind: .frame, name: "Grid two", parent: .node(gridID), properties: geometryProperties(children[4], x: 900, y: 900, width: 40, height: 50)),
        ]
        XCTAssertNoThrow(try document.validate())

        let resolved = document.pages[0].resolvedStructuralGeometry()
        XCTAssertEqual(resolved[children[0]]?.origin, .init(x: section.insertionGeometry!.origin.x + 60, y: section.insertionGeometry!.origin.y + 60))
        XCTAssertEqual(resolved[children[1]]?.origin.x, stack.insertionGeometry!.origin.x + 20)
        XCTAssertEqual(resolved[children[2]]?.origin.x, stack.insertionGeometry!.origin.x + 20 + 40 + 10)
        XCTAssertEqual(resolved[children[1]]?.origin.y, stack.insertionGeometry!.origin.y + stack.insertionGeometry!.size.height - 20 - 30)
        XCTAssertEqual(resolved[children[2]]?.origin.y, stack.insertionGeometry!.origin.y + stack.insertionGeometry!.size.height - 20 - 50)
        XCTAssertEqual(resolved[children[3]]?.origin.y, resolved[children[4]]?.origin.y)
        XCTAssertEqual(resolved[children[3]]?.size.width, resolved[children[4]]?.size.width)
        XCTAssertEqual(document.pages[0].nodes.first { $0.id == gridID }?.childIDs, [children[3], children[4]])
    }

    // SF-0502-003 / SF-0503-003 / SF-0506-003 — insertion-size children
    // resolve inside bounded Stack/Grid content boxes without rewriting their
    // canonical authored frames.
    func testStructuralResolverFitsDefaultChildrenInsideBoundedContainers() throws {
        let fixture = makeFixture()
        let stackID = NodeID(), gridID = NodeID()
        var stack = try prepare(.stack, fixture: fixture, nodeID: stackID).node
        var grid = try prepare(.grid, fixture: fixture, nodeID: gridID).node
        let stackChildren = [NodeID(), NodeID()]
        let gridChildren = [NodeID(), NodeID(), NodeID()]
        stack.childIDs = stackChildren
        grid.childIDs = gridChildren

        var document = fixture.document
        document.pages[0].nodes[0].childIDs = [stackID, gridID, fixture.textParentID]
        document.pages[0].nodes += [stack, grid]
        document.pages[0].nodes += stackChildren.map {
            DocumentNode(id: $0, kind: .frame, name: "Stack child", parent: .node(stackID), properties: geometryProperties($0, x: 900, y: 900, width: 240, height: 160))
        }
        document.pages[0].nodes += gridChildren.map {
            DocumentNode(id: $0, kind: .frame, name: "Grid child", parent: .node(gridID), properties: geometryProperties($0, x: 900, y: 900, width: 240, height: 160))
        }

        let resolved = document.pages[0].resolvedStructuralGeometry()
        for (containerID, childIDs) in [(stackID, stackChildren), (gridID, gridChildren)] {
            let container = try XCTUnwrap(resolved[containerID])
            for childID in childIDs {
                let child = try XCTUnwrap(resolved[childID])
                XCTAssertGreaterThanOrEqual(child.origin.x, container.origin.x)
                XCTAssertGreaterThanOrEqual(child.origin.y, container.origin.y)
                XCTAssertLessThanOrEqual(child.origin.x + child.size.width, container.origin.x + container.size.width)
                XCTAssertLessThanOrEqual(child.origin.y + child.size.height, container.origin.y + container.size.height)
            }
        }
        XCTAssertEqual(document.pages[0].nodes.first { $0.id == stackChildren[0] }?.insertionGeometry?.size, .init(width: 240, height: 160))
        XCTAssertEqual(document.pages[0].nodes.first { $0.id == gridChildren[0] }?.insertionGeometry?.size, .init(width: 240, height: 160))
    }

    // SF-0407-007, SF-0503-007, SF-1601-007
    func testGridRowOffsetsReadEveryLargeFixtureChildExactlyOnce() {
        let childCount = 10_000
        var heightReadCount = 0

        let offsets = GridRowOffsetResolver.resolve(
            childCount: childCount,
            columns: 2,
            startY: 10,
            gap: 4
        ) { index in
            heightReadCount += 1
            return index.isMultiple(of: 2) ? 10 : 20
        }

        XCTAssertEqual(heightReadCount, childCount)
        XCTAssertEqual(offsets.count, childCount / 2)
        XCTAssertEqual(offsets.first, 10)
        XCTAssertEqual(offsets.last, 10 + (Double((childCount / 2) - 1) * 24))
    }

    // SF-0405-002, SF-0405-003, SF-0405-008
    func testEveryInputPathUsesTheSameTypedPreparationAndDisabledReasons() throws {
        let fixture = makeFixture()
        for provenance in InsertionProvenance.allCases {
            let prepared = try prepare(.frame, fixture: fixture, nodeID: fixture.frameID, provenance: provenance)
            XCTAssertEqual(prepared.node.id, fixture.frameID)
            XCTAssertEqual(prepared.documentCommand.name, .insertNode)
        }
        let stale = command(.frame, fixture: fixture, nodeID: fixture.frameID, revision: fixture.document.revision + 1)
        let availability = InsertionCommandRegistry().availability(for: stale, in: fixture.document, context: fixture.context)
        XCTAssertFalse(availability.isEnabled)
        XCTAssertEqual(availability.disabledReason, InsertionError.staleRevision.localizedDescription)
    }

    // SF-0405-002, SF-0405-003
    func testInvalidParentIdentityScopeAndStateAreRejectedWithoutMutation() throws {
        var fixture = makeFixture()
        let before = fixture.document
        let registry = InsertionCommandRegistry()
        let cases: [(AuthoringInsertionCommand, InsertionValidationContext, InsertionError)] = [
            (command(.frame, fixture: fixture, nodeID: fixture.frameID, parentID: NodeID()), fixture.context, .missingParent),
            (command(.frame, fixture: fixture, nodeID: fixture.frameID, parentID: fixture.otherPageRootID), fixture.context, .crossPageParent),
            (command(.frame, fixture: fixture, nodeID: fixture.frameID, parentID: fixture.textParentID), fixture.context, .incompatibleParent),
            (command(.frame, fixture: fixture, nodeID: fixture.rootID), fixture.context, .duplicateNode),
            (command(.frame, fixture: fixture, nodeID: fixture.frameID, index: 2), fixture.context, .invalidIndex),
            (command(.frame, fixture: fixture, nodeID: fixture.frameID, documentID: DocumentID()), fixture.context, .staleDocument),
            (command(.frame, fixture: fixture, nodeID: fixture.frameID, generation: 9), fixture.context, .staleGeneration),
        ]
        for (value, context, expected) in cases {
            XCTAssertThrowsError(try registry.prepare(value, in: fixture.document, context: context)) { XCTAssertEqual($0 as? InsertionError, expected) }
            XCTAssertEqual(fixture.document, before)
        }

        fixture.document.pages[0].nodes[0].properties.append(booleanProperty("locked", true))
        XCTAssertThrowsError(try registry.prepare(command(.frame, fixture: fixture, nodeID: fixture.frameID), in: fixture.document, context: fixture.context)) {
            XCTAssertEqual($0 as? InsertionError, .lockedParent)
        }
        fixture.document.pages[0].nodes[0].properties.removeLast()
        fixture.document.pages[0].nodes[0].properties.append(booleanProperty("hidden", true))
        XCTAssertThrowsError(try registry.prepare(command(.frame, fixture: fixture, nodeID: fixture.frameID), in: fixture.document, context: fixture.context)) {
            XCTAssertEqual($0 as? InsertionError, .hiddenParent)
        }
        let unavailable = InsertionValidationContext(activePageID: fixture.pageID, activeRoute: .init(rawValue: "/"), operationGeneration: 1, availableNodeIDs: [])
        fixture.document.pages[0].nodes[0].properties.removeLast()
        XCTAssertThrowsError(try registry.prepare(command(.frame, fixture: fixture, nodeID: fixture.frameID), in: fixture.document, context: unavailable)) {
            XCTAssertEqual($0 as? InsertionError, .unavailableParent)
        }
    }

    // SF-0405-002, SF-0405-003, SF-0405-005
    func testGeometryTextCancellationAndRevisionExhaustionAreStateNeutral() throws {
        let fixture = makeFixture()
        let registry = InsertionCommandRegistry()
        let invalid = InsertionGeometry(origin: .init(x: .nan, y: 0), size: .init(width: 10, height: 10))
        XCTAssertThrowsError(try registry.prepare(command(.frame, fixture: fixture, nodeID: fixture.frameID, geometry: invalid), in: fixture.document, context: fixture.context)) {
            XCTAssertEqual($0 as? InsertionError, .invalidGeometry)
        }
        let oversized = String(repeating: "x", count: InsertionPolicy.maximumTextBytes + 1)
        XCTAssertThrowsError(try registry.prepare(command(.text, fixture: fixture, nodeID: fixture.textID, text: oversized), in: fixture.document, context: fixture.context)) {
            XCTAssertEqual($0 as? InsertionError, .textLimitExceeded)
        }
        XCTAssertThrowsError(try registry.prepare(command(.text, fixture: fixture, nodeID: fixture.textID, text: "bad\u{0000}"), in: fixture.document, context: fixture.context)) {
            XCTAssertEqual($0 as? InsertionError, .invalidText)
        }
        XCTAssertThrowsError(try registry.prepare(command(.frame, fixture: fixture, nodeID: fixture.frameID), in: fixture.document, context: fixture.context, cancellation: .init(isCancelled: { true }))) {
            XCTAssertEqual($0 as? InsertionError, .cancelled)
        }

        var exhausted = fixture.document
        exhausted.revision = UInt64.max - 1
        let prepared = try registry.prepare(command(.frame, fixture: fixture, nodeID: fixture.frameID, revision: exhausted.revision), in: exhausted, context: fixture.context)
        let session = DocumentSession(document: exhausted)
        XCTAssertThrowsError(try session.execute(prepared.documentCommand)) { XCTAssertEqual($0 as? CommandExecutionError, .revisionExhausted) }
        XCTAssertEqual(session.document, exhausted)
        XCTAssertFalse(session.canUndo)
    }

    // SF-0405-002, SF-0405-005, SF-0405-006
    func testOneTransactionUndoRedoExactIdentityOrderingAndBranchInvalidation() throws {
        let fixture = makeFixture()
        let prepared = try prepare(.frame, fixture: fixture, nodeID: fixture.frameID)
        let session = DocumentSession(document: fixture.document)
        let baseline = session.document
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.document.revision, baseline.revision + 1)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == fixture.frameID }, prepared.node)
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.frameID })
        XCTAssertTrue(session.canRedo)
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == fixture.frameID }, prepared.node)
        try session.undo()
        let replacement = try prepare(.text, fixture: fixture.with(document: session.document), nodeID: fixture.textID)
        try session.execute(replacement.documentCommand)
        XCTAssertFalse(session.canRedo)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.frameID })
    }

    // SF-0405-004, SF-0405-006, SF-0405-007
    func testDeterministicPackageRoundTripAndPersistedInsertionHistory() async throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let prepared = try prepare(.text, fixture: fixture, nodeID: fixture.textID)
        try session.execute(prepared.documentCommand)
        let historyStore = PersistedHistoryStore()
        let basePackage = ProjectPackage(
            projectID: ProjectID(UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!),
            createdAt: ProjectTimestamp("2026-07-21T12:00:00.000Z"),
            document: session.document
        )
        let package = try await historyStore.package(basePackage, with: session.historySnapshot())
        let store = ProjectPackageStore()
        let first = try await store.encode(package)
        let second = try await store.encode(package)
        XCTAssertEqual(first, second)
        let reopened = try await store.decode(first)
        XCTAssertEqual(reopened.document, session.document)
        XCTAssertEqual(reopened.document.pages[0].nodes.first { $0.id == fixture.textID }?.insertionStringProperty("content.text"), "Text")
        let restoredHistory = try await historyStore.load(from: reopened)
        guard case .restored(let snapshot) = restoredHistory else { return XCTFail("Expected compatible insertion history") }
        let reopenedSession = DocumentSession(document: reopened.document)
        try reopenedSession.installValidatedHistory(snapshot)
        try reopenedSession.undo()
        XCTAssertNil(reopenedSession.document.pages[0].nodes.first { $0.id == fixture.textID })
        try reopenedSession.redo()
        XCTAssertEqual(reopenedSession.document.pages[0].nodes.first { $0.id == fixture.textID }?.id, fixture.textID)
    }

    // SF-0501-001 through SF-0503-008 — structural nodes are schema-4
    // canonical content, not editor catalog state. Their identities and v1
    // defaults survive a deterministic package/history round trip.
    func testStructuralElementsPersistInSchemaFourAndSchemaThreeRemainsReadable() async throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let sectionID = NodeID()
        let stackID = NodeID()
        let gridID = NodeID()

        for (kind, id) in [(InsertionKind.section, sectionID), (.stack, stackID), (.grid, gridID)] {
            let current = fixture.with(document: session.document)
            try session.execute(try prepare(kind, fixture: current, nodeID: id).documentCommand)
        }
        let bytes = try DocumentSerializer.encode(session.document)
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)"))
        let reopened = try DocumentSerializer.decode(bytes)
        XCTAssertEqual(reopened, session.document)
        XCTAssertEqual(reopened.pages[0].nodes.first { $0.id == sectionID }?.kind, .section)
        XCTAssertEqual(reopened.pages[0].nodes.first { $0.id == stackID }?.insertionNumberProperty("layout.gap"), 24)
        XCTAssertEqual(reopened.pages[0].nodes.first { $0.id == gridID }?.insertionNumberProperty("layout.grid.columns"), 2)

        // Schema 3 was the prior canonical envelope. It intentionally has no
        // structural instances, but must migrate without data loss.
        var legacyEnvelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: DocumentSerializer.encode(fixture.document)) as? [String: Any]
        )
        legacyEnvelope["schemaVersion"] = 3
        var legacyDocument = try XCTUnwrap(legacyEnvelope["document"] as? [String: Any])
        legacyDocument.removeValue(forKey: "imageAssets")
        legacyDocument.removeValue(forKey: "colorTokens")
        legacyDocument.removeValue(forKey: "websiteMetadata")
        legacyEnvelope["document"] = legacyDocument
        let legacy = try JSONSerialization.data(withJSONObject: legacyEnvelope)
        XCTAssertEqual(try DocumentSerializer.decode(legacy), fixture.document)
    }

    // SF-0405-003, SF-0405-004, SF-0405-007
    func testInsertionSessionPreviewIsEditorOnlyAndLifecycleCancellationIsNonmutating() throws {
        let fixture = makeFixture()
        var session = InsertionSession()
        session.arm(kind: .frame, documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision)
        session.preview(at: .init(x: 42, y: 84), nodeID: fixture.frameID)
        guard case .previewing(let preview) = session.phase else { return XCTFail("Expected preview") }
        XCTAssertEqual(preview.geometry.origin, .init(x: 42, y: 84))
        let canonical = try DocumentSerializer.encode(fixture.document)
        XCTAssertFalse(String(decoding: canonical, as: UTF8.self).contains(fixture.frameID.description))
        session.cancel()
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertEqual(try DocumentSerializer.encode(fixture.document), canonical)
    }

    // SF-0405-003 through SF-0405-007
    func testWorkspaceCommitSelectsOnlyAfterSuccessAndUndoRepairsSelection() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        for _ in 0..<200 where state.canvasRenderPlan == nil { await Task.yield() }
        XCTAssertNotNil(state.canvasRenderPlan)
        let before = try DocumentSerializer.encode(state.documentSession.document)
        state.selectTool(.frame)
        state.performDefaultInsertion(.frame, provenance: .keyboard)
        for _ in 0..<200 where state.selectionState.isEmpty { await Task.yield() }

        let inserted = try XCTUnwrap(state.selectionState.primaryID)
        XCTAssertEqual(state.documentSession.document.pages[0].nodes.first { $0.id == inserted }?.kind, .frame)
        XCTAssertTrue(state.canUndo)
        XCTAssertTrue(state.layerTargets.contains { $0.id == inserted })
        XCTAssertNotEqual(try DocumentSerializer.encode(state.documentSession.document), before)
        XCTAssertFalse(String(decoding: try DocumentSerializer.encode(state.documentSession.document), as: UTF8.self).contains("selection"))

        state.undo()
        for _ in 0..<200 where state.documentSession.document.pages[0].nodes.contains(where: { $0.id == inserted }) { await Task.yield() }
        XCTAssertNil(state.documentSession.document.pages[0].nodes.first { $0.id == inserted })
        XCTAssertFalse(state.selectionState.orderedIDs.contains(inserted))
    }

    // SF-0405-002, SF-0405-003, SF-0405-006 — a visible empty-canvas action
    // is enabled from the current lifecycle boundary before any tool session
    // exists, then follows the same canonical commit/adoption path as every
    // other insertion entry point.
    func testEmptyCanvasAvailabilityEnablesHeaderActionBeforeArmingAndAdoptsFrameAndText() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        for _ in 0..<200 where state.canvasRenderPlan == nil { await Task.yield() }
        XCTAssertTrue(state.insertionAvailability(.frame).isEnabled)
        XCTAssertTrue(state.insertionAvailability(.text).isEnabled)

        let baselineRevision = state.documentSession.document.revision
        state.performDefaultInsertion(.frame, provenance: .accessibility)
        for _ in 0..<200 where state.canvasRenderPlan?.authoredObjects.count != 1 { await Task.yield() }
        let frame = try XCTUnwrap(state.selectionState.primaryID)
        XCTAssertEqual(state.documentSession.document.revision, baselineRevision + 1)
        XCTAssertEqual(state.canvasRenderPlan?.authoredObjects.map(\.id), [frame])
        XCTAssertEqual(state.canvasRenderPlan?.identity.revision, state.documentSession.document.revision)
        XCTAssertTrue(state.layerTargets.contains { $0.id == frame })
        XCTAssertTrue(state.canUndo)
        // A named empty-canvas action is a one-shot transaction. It must not
        // leave a stale insertion draft that can paint a second dashed ghost
        // rectangle on a later pointer move.
        XCTAssertEqual(state.selectedTool, .select)
        XCTAssertEqual(state.insertionSession.phase, .inactive)
        var diagnostics = await state.insertionDiagnostics.snapshot()
        for _ in 0..<200 where diagnostics.isEmpty {
            await Task.yield()
            diagnostics = await state.insertionDiagnostics.snapshot()
        }
        let diagnostic = try XCTUnwrap(diagnostics.last)
        XCTAssertEqual(diagnostic.commandType, "insert-frame")
        XCTAssertEqual(diagnostic.parentRevision, baselineRevision)
        XCTAssertEqual(diagnostic.resultRevision, baselineRevision + 1)
        XCTAssertEqual(diagnostic.result, .success)
        XCTAssertEqual(diagnostic.sanitizedIdentifiers.count, 2)
        XCTAssertTrue(diagnostic.sanitizedIdentifiers.allSatisfy { $0.count == 8 })

        state.undo()
        for _ in 0..<200 where state.canvasRenderPlan?.authoredObjects.isEmpty == false { await Task.yield() }
        XCTAssertTrue(state.canvasRenderPlan?.authoredObjects.isEmpty == true)
        state.redo()
        for _ in 0..<200 where state.canvasRenderPlan?.authoredObjects.map(\.id) != [frame] { await Task.yield() }
        XCTAssertEqual(state.canvasRenderPlan?.authoredObjects.map(\.id), [frame])

        let textState = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        textState.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        // Await the actual worker publication, not a scheduler-dependent
        // number of yields that can finish before scene preparation starts.
        let ready = expectation(description: "Text scene ready")
        let readiness = textState.$canvasRenderPlan.compactMap { $0 }.first().sink { _ in ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertTrue(textState.insertionAvailability(.text).isEnabled)
        let adopted = expectation(description: "Inserted Text selected")
        let selection = textState.$selectionState.filter { $0.primaryID != nil }.first().sink { _ in adopted.fulfill() }
        textState.performDefaultInsertion(.text, provenance: .accessibility)
        await fulfillment(of: [adopted], timeout: 5)
        withExtendedLifetime((readiness, selection)) {}
        let text = try XCTUnwrap(textState.selectionState.primaryID)
        XCTAssertEqual(textState.canvasRenderPlan?.authoredObjects.map(\.id), [text])
        XCTAssertEqual(textState.canvasRenderPlan?.identity.revision, textState.documentSession.document.revision)
        XCTAssertEqual(
            textState.documentSession.document.pages
                .flatMap(\.nodes)
                .first(where: { $0.id == text })?.kind,
            .text
        )
    }

    // SF-0405-002/003/006, SF-0502-002 — named insertion must center the
    // requested element's canonical dimensions, not dimensions inherited
    // from whichever canvas tool happened to be selected previously.
    func testNamedSectionInsertionUsesConnectedFlowAndUndoRedoPreservesCanonicalIntent() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 1_400, height: 900), pixelRatio: 2)
        let ready = expectation(description: "Initial scene ready")
        let readiness = state.$canvasRenderPlan.compactMap { $0 }.first().sink { _ in ready.fulfill() }
        await fulfillment(of: [ready], timeout: 5)

        state.selectTool(.frame)
        let sectionSize = InsertionGeometry.defaultValue(for: .section, at: .init(x: 0, y: 0)).size

        let adopted = expectation(description: "Section selected")
        let selection = state.$selectionState.filter { $0.primaryID != nil }.first().sink { _ in adopted.fulfill() }
        state.performDefaultInsertion(.section, provenance: .menu)
        await fulfillment(of: [adopted], timeout: 5)
        withExtendedLifetime((readiness, selection)) {}

        let sectionID = try XCTUnwrap(state.selectionState.primaryID)
        let inserted = try XCTUnwrap(
            state.documentSession.document.pages[0].nodes.first { $0.id == sectionID }
        )
        let geometry = try XCTUnwrap(inserted.insertionGeometry)
        XCTAssertEqual(geometry.origin.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(geometry.origin.y, 0, accuracy: 0.000_001)
        XCTAssertEqual(geometry.size, sectionSize)
        XCTAssertEqual(CanonicalPageFlow.role(inserted), .body)
        let resolved = try XCTUnwrap(state.documentSession.document.pages[0].resolvedStructuralGeometry(viewportWidth: 1440)[sectionID])
        XCTAssertEqual(resolved.origin, .init(x: 0, y: 0))
        XCTAssertEqual(resolved.size.width, 1440)

        state.undo()
        XCTAssertNil(state.documentSession.document.pages[0].nodes.first { $0.id == sectionID })
        state.redo()
        let restored = try XCTUnwrap(
            state.documentSession.document.pages[0].nodes.first { $0.id == sectionID }?.insertionGeometry
        )
        XCTAssertEqual(restored, geometry)
    }

    // SF-0405-002, SF-0502-004 — insertion-menu availability follows the
    // live canonical selected parent even while its newly committed render
    // target is crossing the immutable scene-adoption boundary.
    func testNestedInsertionParentRemainsAvailableAcrossRendererAdoption() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        for _ in 0..<200 where state.canvasRenderPlan == nil { await Task.yield() }

        state.performDefaultInsertion(.section, provenance: .accessibility)
        for _ in 0..<200 where state.canvasRenderPlan?.authoredObjects.count != 1 { await Task.yield() }
        let sectionID = try XCTUnwrap(state.selectionState.primaryID)
        XCTAssertEqual(state.documentSession.document.pages[0].nodes.first { $0.id == sectionID }?.kind, .section)

        state.performDefaultInsertion(.stack, provenance: .accessibility)
        // Command state is queried synchronously by the native Insert menu.
        // It must already accept the canonical selected Stack; waiting for a
        // later selection-scene publication would make a visible command
        // transiently and incorrectly disabled.
        let stackID = try XCTUnwrap(
            state.documentSession.document.pages[0].nodes.first(where: { $0.kind == .stack })?.id
        )
        state.selectLayer(stackID)
        for _ in 0..<200 where state.selectionState.primaryID != stackID { await Task.yield() }
        XCTAssertEqual(state.selectionState.primaryID, stackID)
        XCTAssertEqual(state.documentSession.document.pages[0].nodes.first { $0.id == stackID }?.kind, .stack)
        XCTAssertTrue(state.insertionAvailability(.frame).isEnabled)

        state.performDefaultInsertion(.frame, provenance: .menu)
        for _ in 0..<200 where state.canvasRenderPlan?.authoredObjects.count != 3 { await Task.yield() }
        let frameID = try XCTUnwrap(state.selectionState.primaryID)
        let page = state.documentSession.document.pages[0]
        XCTAssertEqual(page.nodes.first { $0.id == frameID }?.parent, .node(stackID))
        XCTAssertEqual(page.nodes.first { $0.id == stackID }?.childIDs, [frameID])
        XCTAssertEqual(state.canvasRenderPlan?.identity.revision, state.documentSession.document.revision)
    }

    // SF-0405-002, SF-0405-005 — recovery autosave writes an immutable
    // revision snapshot and must not transiently disable the native Insert
    // menu or reject the next canonical transaction.
    func testInsertionRemainsAvailableDuringBackgroundAutosave() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let backend = DocumentLifecycleBackend()
        await backend.configureForTesting(delayNanoseconds: 500_000_000)
        let recoveryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SiteForge-Insertion-Autosave-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: recoveryDirectory) }
        let lifecycle = DocumentLifecycleController(
            session: session,
            backend: backend,
            recoveryDirectory: recoveryDirectory,
            saveDestinationProvider: { _ in nil },
            autosaveDebouncer: ImmediateInsertionAutosaveDebouncer()
        )
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        for _ in 0..<200 where state.canvasRenderPlan == nil { await Task.yield() }

        state.performDefaultInsertion(.section, provenance: .accessibility)
        for _ in 0..<400 where lifecycle.phase != .autosaving { await Task.yield() }
        XCTAssertEqual(lifecycle.phase, .autosaving)
        XCTAssertTrue(state.insertionAvailability(.stack).isEnabled)

        state.performDefaultInsertion(.stack, provenance: .menu)
        for _ in 0..<400 where session.document.pages[0].nodes.filter({ $0.insertionGeometry != nil }).count != 2 {
            await Task.yield()
        }
        XCTAssertEqual(session.document.pages[0].nodes.filter { $0.insertionGeometry != nil }.count, 2)
        XCTAssertEqual(session.document.revision, 2)
        XCTAssertNil(state.insertionFailure)
    }

    // SF-0502-002, SF-0505-002: background snapshot I/O must not disable
    // native Inspector controls or reject the next revision's transaction.
    func testInspectorEditsRemainAvailableDuringBackgroundAutosave() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let backend = DocumentLifecycleBackend()
        await backend.configureForTesting(delayNanoseconds: 500_000_000)
        let fixture = try ApplicationOwnedTestFixture.create("inspector-autosave")
        defer { try? fixture.cleanup() }
        let recoveryDirectory = fixture.url.appendingPathComponent("recovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let lifecycle = DocumentLifecycleController(
            session: session, backend: backend, recoveryDirectory: recoveryDirectory,
            saveDestinationProvider: { _ in nil },
            autosaveDebouncer: ImmediateInsertionAutosaveDebouncer()
        )
        let state = WorkspaceShellState(documentSession: session, lifecycle: lifecycle)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        for _ in 0..<200 where state.canvasRenderPlan == nil { await Task.yield() }
        state.performDefaultInsertion(.stack, provenance: .accessibility)
        for _ in 0..<400 where lifecycle.phase != .autosaving || state.canvasRenderPlan?.identity.revision != 1 {
            await Task.yield()
        }
        XCTAssertEqual(lifecycle.phase, .autosaving, "\(String(describing: lifecycle.failure))")
        let selectedID = try XCTUnwrap(state.selectionState.primaryID)
        XCTAssertTrue(state.geometryInspectorAvailability(for: .y).isEnabled)
        XCTAssertTrue(state.containerLayoutAvailability(for: .alignment).isEnabled)
        XCTAssertTrue(state.commitGeometryInspectorValue(122, field: .y, provenance: .keyboard))
        XCTAssertTrue(state.commitContainerLayout(field: .alignment, value: .alignment(.center), provenance: .keyboard))
        let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == selectedID })
        XCTAssertEqual(node.insertionNumberProperty("layout.y"), 122)
        XCTAssertEqual(node.insertionStringProperty("layout.align"), "center")
        XCTAssertEqual(session.document.revision, 3)
        XCTAssertEqual(state.selectionState.primaryID, selectedID)
        try session.undo()
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == selectedID }?.insertionStringProperty("layout.align"), "start")
    }

    // SF-0405-004, SF-0405-007
    func testCommittedNodesIntegrateWithLayoutRendererHitTestingAndBoundedInvalidation() throws {
        let fixture = makeFixture()
        let prepared = try prepare(.text, fixture: fixture, nodeID: fixture.textID)
        let layout = try XCTUnwrap(InsertionLayoutAdapter.snapshot(for: prepared.node))
        let request = LayoutRequest(
            identity: .init(documentID: fixture.document.id, revision: 1, generation: 1, viewportWidth: 800),
            snapshot: layout,
            containingBlock: .init(width: 800, height: 600)
        )
        let result = try DeterministicLayoutEngine().layout(request)
        XCTAssertEqual(result.fragmentsByID[fixture.textID]?.frame.size, .init(width: 120, height: 24))

        let identity = CanvasRenderRequestIdentity(documentID: fixture.document.id, revision: 1, sceneID: .init(), sceneGeneration: 1, viewportGeneration: 1, scale: try .init(2))
        let object = CanvasRenderObject(id: fixture.textID, frame: prepared.geometry.frame, clipRect: prepared.geometry.frame, paintOrder: 1, style: .textPlaceholder, isVisible: true, accessibilityLabel: "Text", plainText: "Text")
        let scene = CanvasRenderSceneSnapshot(identity: identity, surfaceID: .init(), objects: [object])
        let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 800, height: 600), contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 900)), pixelRatio: .init(2))
        let core = CanvasRendererCore()
        let plan = try core.prepare(scene: scene, overlays: .init(identity: identity, overlays: []), viewport: viewport)
        XCTAssertEqual(core.hitTest(.init(x: 25, y: 35), in: plan), fixture.textID)
        XCTAssertEqual(core.previewSnapshot(from: scene).objects.first?.plainText, "Text")
        XCTAssertEqual(plan.authoredObjects.count, 1)
    }

    // SF-0203-006, SF-0405-004, SF-0405-006 — frame appearance is canonical;
    // selection context remains an editor-only overlay.
    func testFrameSurfaceDefaultsSurviveUndoRedoAndDeterministicRoundTripWithoutSelectionMetadata() throws {
        let fixture = makeFixture()
        let prepared = try prepare(.frame, fixture: fixture, nodeID: fixture.frameID)
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared.documentCommand)
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertTrue(String(decoding: encoded, as: UTF8.self).contains("surface"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("selection-primary"))
        let reopened = try DocumentSerializer.decode(encoded)
        XCTAssertEqual(reopened.pages[0].nodes.first { $0.id == fixture.frameID }?.insertionStringProperty("style.fill"), "surface")
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.frameID })
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == fixture.frameID }, prepared.node)
    }

    // SF-0405-008
    func testDiagnosticsAreRedactedAndNeverContainAuthoredTextOrPaths() throws {
        let fixture = makeFixture()
        let record = InsertionDiagnosticFactory.make(kind: .text, nodeID: fixture.textID, parentID: fixture.rootID, durationMilliseconds: 0.5, parentRevision: 0, resultRevision: nil, result: .failure, failure: .invalidText)
        let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertEqual(record.requirementID, "SF-0405-008")
        XCTAssertTrue(record.sanitizedIdentifiers.allSatisfy { $0.count == 8 })
        XCTAssertFalse(encoded.contains("/Users/"))
        XCTAssertFalse(encoded.contains("content.text"))
        XCTAssertEqual(record.failureCategory, "validation")
    }

    // SF-0405-007, SF-0405-008 — production implementations at representative capacities.
    func testProductionCapacityForHundredAndTenThousandObjects() throws {
        for count in [100, 10_000] {
            let capacity = makeCapacityFixture(count: count)
            let registry = InsertionCommandRegistry()
            var commandSamples: [Double] = []
            var layoutSamples: [Double] = []
            var renderSamples: [Double] = []
            for _ in 0..<5 {
                commandSamples.append(try elapsedMilliseconds {
                    _ = try registry.prepare(capacity.command, in: capacity.document, context: capacity.context)
                })
                layoutSamples.append(try elapsedMilliseconds {
                    _ = try DeterministicLayoutEngine().layout(capacity.layoutRequest)
                })
                renderSamples.append(try elapsedMilliseconds {
                    _ = try CanvasRendererCore().prepare(scene: capacity.renderScene, overlays: .init(identity: capacity.renderScene.identity, overlays: []), viewport: capacity.viewport)
                })
            }
            XCTAssertLessThan(commandSamples.max() ?? .infinity, 2_000)
            XCTAssertLessThan(layoutSamples.max() ?? .infinity, 2_000)
            XCTAssertLessThan(renderSamples.max() ?? .infinity, 2_000)
            print("INSERTION_EVIDENCE count=\(count) command=\(commandSamples) layout=\(layoutSamples) render=\(renderSamples)")
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("INSERTION_EVIDENCE maximumResidentBytes=\(max(0, usage.ru_maxrss))")
    }

    private struct Fixture {
        var document: CanonicalDocument
        let pageID: PageID
        let rootID: NodeID
        let otherPageRootID: NodeID
        let textParentID: NodeID
        let frameID: NodeID
        let textID: NodeID
        var context: InsertionValidationContext {
            .init(activePageID: pageID, activeRoute: .init(rawValue: "/"), operationGeneration: 1, availableNodeIDs: Set(document.pages[0].nodes.map(\.id)))
        }
        func with(document: CanonicalDocument) -> Self { .init(document: document, pageID: pageID, rootID: rootID, otherPageRootID: otherPageRootID, textParentID: textParentID, frameID: frameID, textID: textID) }
    }

    private func makeFixture() -> Fixture {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        let otherPageRootID = document.pages[1].rootNodeIDs[0]
        let textParentID = NodeID(UUID(uuidString: "40000000-0000-4000-8000-000000000001")!)
        document.pages[0].nodes.append(DocumentNode(id: textParentID, kind: .text, name: "Existing text", parent: .node(rootID)))
        document.pages[0].nodes[0].childIDs.append(textParentID)
        return Fixture(document: document, pageID: pageID, rootID: rootID, otherPageRootID: otherPageRootID, textParentID: textParentID, frameID: NodeID(UUID(uuidString: "50000000-0000-4000-8000-000000000001")!), textID: NodeID(UUID(uuidString: "60000000-0000-4000-8000-000000000001")!))
    }

    private func command(
        _ kind: InsertionKind,
        fixture: Fixture,
        nodeID: NodeID,
        parentID: NodeID? = nil,
        index: Int = 0,
        geometry: InsertionGeometry? = nil,
        text: String = InsertionPolicy.defaultText,
        provenance: InsertionProvenance = .pointer,
        documentID: DocumentID? = nil,
        revision: UInt64? = nil,
        generation: UInt64 = 1
    ) -> AuthoringInsertionCommand {
        let identity = InsertionOperationIdentity(documentID: documentID ?? fixture.document.id, pageID: fixture.pageID, revision: revision ?? fixture.document.revision, generation: generation)
        let geometry = geometry ?? .defaultValue(for: kind, at: .init(x: 20, y: 30))
        switch kind {
        case .frame: return .frame(.init(identity: identity, nodeID: nodeID, parentID: parentID ?? fixture.rootID, index: index, geometry: geometry, provenance: provenance))
        case .text: return .text(.init(identity: identity, nodeID: nodeID, parentID: parentID ?? fixture.rootID, index: index, geometry: geometry, text: text, provenance: provenance))
        case .section, .stack, .grid, .form:
            return .container(.init(kind: kind, identity: identity, nodeID: nodeID, parentID: parentID ?? fixture.rootID, index: index, geometry: geometry, provenance: provenance))
        case .button, .link:
            return .control(.init(kind: kind, identity: identity, nodeID: nodeID, parentID: parentID ?? fixture.rootID, index: index, geometry: geometry, provenance: provenance))
        case .image:
            return .image(.init(
                identity: identity,
                nodeID: nodeID,
                parentID: parentID ?? fixture.rootID,
                index: index,
                geometry: geometry,
                assetID: AssetID(UUID(uuidString: "70000000-0000-4000-8000-000000000001")!),
                provenance: provenance
            ))
        }
    }

    private func prepare(_ kind: InsertionKind, fixture: Fixture, nodeID: NodeID, index: Int = 0, provenance: InsertionProvenance = .pointer) throws -> PreparedInsertion {
        try InsertionCommandRegistry().prepare(command(kind, fixture: fixture, nodeID: nodeID, index: index, provenance: provenance), in: fixture.document, context: fixture.context)
    }

    private func booleanProperty(_ key: String, _ value: Bool) -> NodeProperty {
        .init(key: .init(rawValue: key), value: .boolean(value))
    }

    private func geometryProperties(_ id: NodeID, x: Double, y: Double, width: Double, height: Double) -> [NodeProperty] {
        [
            .init(key: .init(rawValue: "layout.x"), value: .number(x)),
            .init(key: .init(rawValue: "layout.y"), value: .number(y)),
            .init(key: .init(rawValue: "layout.width"), value: .number(width)),
            .init(key: .init(rawValue: "layout.height"), value: .number(height)),
        ]
    }

    private struct CapacityFixture {
        let document: CanonicalDocument
        let command: AuthoringInsertionCommand
        let context: InsertionValidationContext
        let layoutRequest: LayoutRequest
        let renderScene: CanvasRenderSceneSnapshot
        let viewport: CanvasViewportState
    }

    private func makeCapacityFixture(count: Int) -> CapacityFixture {
        let documentID = DocumentID(UUID(uuidString: "71000000-0000-4000-8000-000000000001")!)
        let pageID = PageID(UUID(uuidString: "72000000-0000-4000-8000-000000000001")!)
        let rootID = NodeID(UUID(uuidString: "73000000-0000-4000-8000-000000000001")!)
        let childIDs = (1..<count).map { NodeID(UUID(uuidString: String(format: "74000000-0000-4000-8000-%012x", $0))!) }
        let root = DocumentNode(id: rootID, kind: .frame, name: "Root", parent: .page(pageID), childIDs: childIDs)
        let children = childIDs.map { DocumentNode(id: $0, kind: .frame, name: "Frame", parent: .node(rootID)) }
        let document = CanonicalDocument(id: documentID, pages: [DocumentPage(id: pageID, name: "Capacity", route: .init(rawValue: "/"), role: .home, provenance: .authored, rootNodeIDs: [rootID], nodes: [root] + children)])
        let newID = NodeID(UUID(uuidString: "75000000-0000-4000-8000-000000000001")!)
        let identity = InsertionOperationIdentity(documentID: documentID, pageID: pageID, revision: 0, generation: 1)
        let command = AuthoringInsertionCommand.frame(.init(identity: identity, nodeID: newID, parentID: rootID, index: childIDs.count, geometry: .defaultValue(for: .frame, at: .init(x: 20, y: 20)), provenance: .automation))
        let context = InsertionValidationContext(activePageID: pageID, activeRoute: .init(rawValue: "/"), operationGeneration: 1)

        let layoutNodes = [LayoutNodeSnapshot(id: rootID, axis: .vertical, width: .fixed(1_440), height: .fixed(Double(max(1, count)) * 2), childIDs: childIDs)]
            + childIDs.map { LayoutNodeSnapshot(id: $0, width: .fixed(10), height: .fixed(1)) }
        let layoutRequest = LayoutRequest(identity: .init(documentID: documentID, revision: 0, generation: 1, viewportWidth: 1_440), snapshot: LayoutSnapshot(rootID: rootID, nodes: layoutNodes), containingBlock: .init(width: 1_440, height: Double(max(1, count)) * 2))
        let renderIdentity = CanvasRenderRequestIdentity(documentID: documentID, revision: 0, sceneID: .init(), sceneGeneration: 1, viewportGeneration: 1, scale: try! .init(2))
        let renderObjects = ([rootID] + childIDs).enumerated().map { index, id in
            CanvasRenderObject(id: id, frame: .init(origin: .init(x: Double(index % 100) * 12, y: Double(index / 100) * 12), size: .init(width: 10, height: 10)), clipRect: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 1_400)), paintOrder: index, style: .container, isVisible: true, accessibilityLabel: "Frame")
        }
        let renderScene = CanvasRenderSceneSnapshot(identity: renderIdentity, surfaceID: .init(), objects: renderObjects)
        let viewport = try! CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 1_000, height: 700), contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 1_400)), pixelRatio: .init(2))
        return .init(document: document, command: command, context: context, layoutRequest: layoutRequest, renderScene: renderScene, viewport: viewport)
    }

    private func elapsedMilliseconds(_ operation: () throws -> Void) rethrows -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        try operation()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }
}

private struct ImmediateInsertionAutosaveDebouncer: LifecycleAutosaveDebouncing {
    func wait() async throws {}
}
