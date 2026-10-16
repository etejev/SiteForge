import Combine
import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class InsertionModelTests: XCTestCase {
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
        let old = Data(String(decoding: bytes, as: UTF8.self).replacingOccurrences(
            of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":16").utf8)
        XCTAssertEqual(try DocumentSerializer.decode(old), legacy)
        let (session, _, _, _) = try connectedPageSession()
        let authored = try DocumentSerializer.encode(session.document)
        let forged = Data(String(decoding: authored, as: UTF8.self).replacingOccurrences(
            of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":16").utf8)
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
