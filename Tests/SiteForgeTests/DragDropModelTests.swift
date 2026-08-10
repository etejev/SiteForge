import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class DragDropModelTests: XCTestCase {
    // SF-0408-001, SF-0408-002, SF-0408-003, SF-0408-004
    func testSameParentReorderCrossParentNestAndAdjustedPreviewMatchCommit() throws {
        let fixture = makeFixture()
        let registry = DragDropCommandRegistry()
        let sameParent = try registry.prepare(fixture.command(source: fixture.a, destination: .container(fixture.root, index: 3)), in: fixture.document, context: fixture.context)
        XCTAssertEqual(sameParent.preview.committedDestination, .container(fixture.root, index: 2))
        let session = DocumentSession(document: fixture.document)
        try session.execute(sameParent.command)
        XCTAssertEqual(node(fixture.root, in: session.document).childIDs, [fixture.b, fixture.c, fixture.a])
        XCTAssertEqual(node(fixture.a, in: session.document).parent, .node(fixture.root))

        let nested = try registry.prepare(fixture.command(source: fixture.b, destination: .container(fixture.a, index: 0)), in: fixture.document, context: fixture.context)
        let nestedSession = DocumentSession(document: fixture.document)
        try nestedSession.execute(nested.command)
        XCTAssertEqual(node(fixture.root, in: nestedSession.document).childIDs, [fixture.a, fixture.c])
        XCTAssertEqual(node(fixture.a, in: nestedSession.document).childIDs, [fixture.b, fixture.child])
        XCTAssertEqual(node(fixture.b, in: nestedSession.document).parent, .node(fixture.a))
    }

    // SF-0408-001, SF-0408-005, SF-0408-008 — hierarchy ownership, rather
    // than incidental serialized-node storage order, drives every visual order.
    func testCanonicalHierarchyOrderAdoptsThroughLayersRendererAndReverseHitTesting() async throws {
        let fixture = makeFixture(overlappingGeometry: true)
        let session = DocumentSession(document: fixture.document)
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        try await waitForRenderPlan(in: state, revision: fixture.document.revision)
        XCTAssertEqual(state.layerTargets.map(\.id), [fixture.root, fixture.a, fixture.child, fixture.b, fixture.c])
        XCTAssertEqual(
            CanvasRendererCore().hitTest(.init(x: 80, y: 80), in: try requirePlan(state)),
            fixture.c
        )
        state.selectLayer(fixture.c)

        state.performDragDrop(
            sourceID: fixture.c,
            destination: .container(fixture.root, index: 0),
            provenance: .automation
        )
        try await waitForRenderPlan(in: state, revision: session.document.revision)
        XCTAssertEqual(session.document.pages[0].canonicalDepthFirstNodes().map(\.id), [fixture.root, fixture.c, fixture.a, fixture.child, fixture.b])
        XCTAssertEqual(state.layerTargets.map(\.id), [fixture.root, fixture.c, fixture.a, fixture.child, fixture.b])
        XCTAssertEqual(
            CanvasRendererCore().hitTest(.init(x: 80, y: 80), in: try requirePlan(state)),
            fixture.b
        )
    }

    // SF-0408-001, SF-0408-003, SF-0408-004, SF-0408-005 — an asynchronous
    // native provider callback cannot revive a cancelled, forged, or stale drag.
    func testPointerTransferCapabilityRejectsCancelledForgedAndStaleCallbacks() async throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        try await waitForRenderPlan(in: state, revision: fixture.document.revision)
        let destination = try XCTUnwrap(state.dragDestination(before: fixture.c))
        let before = session.document
        state.selectLayer(fixture.a)

        let cancelled = try XCTUnwrap(state.beginPointerDrag(sourceID: fixture.a))
        XCTAssertTrue(state.previewPointerDrag(cancelled, destination: destination))
        state.cancelDragDrop()
        XCTAssertFalse(state.commitPointerDrag(cancelled, destination: destination))
        XCTAssertEqual(session.document, before)
        XCTAssertFalse(session.canUndo)

        let active = try XCTUnwrap(state.beginPointerDrag(sourceID: fixture.a))
        let forged = LocalLayerDragTransfer(sessionID: DragSessionID(), sourceNodeID: fixture.a)
        XCTAssertFalse(state.previewPointerDrag(forged, destination: destination))
        XCTAssertTrue(state.previewPointerDrag(active, destination: destination))
        try session.execute(.renamePage(.init(pageID: fixture.page, name: "Changed while dragging")))
        await Task.yield()
        XCTAssertFalse(state.commitPointerDrag(active, destination: destination))
        XCTAssertEqual(node(fixture.root, in: session.document).childIDs, [fixture.a, fixture.b, fixture.c])
        XCTAssertEqual(session.document.pages[0].name, "Changed while dragging")
        try await waitForRenderPlan(in: state, revision: session.document.revision)

        let fresh = try XCTUnwrap(state.beginPointerDrag(sourceID: fixture.a))
        let delayed = try XCTUnwrap(state.beginPointerDropCallback())
        let current = try XCTUnwrap(state.beginPointerDropCallback())
        XCTAssertFalse(state.previewPointerDrag(fresh, destination: destination, callback: delayed))
        XCTAssertTrue(state.previewPointerDrag(fresh, destination: destination, callback: current))
        XCTAssertTrue(state.isDragInsertionPreview(before: fixture.c))
        XCTAssertFalse(state.isDragInsertionPreview(before: fixture.b))

        state.selectTool(.frame)
        XCTAssertFalse(state.commitPointerDrag(fresh, destination: destination, callback: current))
        XCTAssertEqual(session.document.pages[0].name, "Changed while dragging")

        let viewportBound = try XCTUnwrap(state.beginPointerDrag(sourceID: fixture.a))
        let viewportCallback = try XCTUnwrap(state.beginPointerDropCallback())
        state.panViewport(by: .init(dx: 12, dy: 0))
        XCTAssertFalse(state.previewPointerDrag(viewportBound, destination: destination, callback: viewportCallback))
        XCTAssertEqual(session.document.pages[0].name, "Changed while dragging")
    }

    // SF-0408-001, SF-0408-002, SF-0408-004 — the scene-level pointer
    // capability is a row-boundary placement, not merely a same-parent
    // reorder. Moving a child before a root sibling uses the same capability,
    // preview, and transaction path without inventing a second hierarchy
    // representation. This is not an XCTest-synthesized native drag gesture.
    func testPointerRowPlacementMovesAcrossCompatibleParents() async throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        try await waitForRenderPlan(in: state, revision: fixture.document.revision)
        state.selectLayer(fixture.child)

        let transfer = try XCTUnwrap(state.beginPointerDrag(sourceID: fixture.child))
        let destination = try XCTUnwrap(state.dragDestination(before: fixture.b))
        XCTAssertEqual(destination, .container(fixture.root, index: 1))
        XCTAssertTrue(state.previewPointerDrag(transfer, destination: destination))
        XCTAssertTrue(state.commitPointerDrag(transfer, destination: destination))

        XCTAssertEqual(node(fixture.root, in: session.document).childIDs, [fixture.a, fixture.child, fixture.b, fixture.c])
        XCTAssertEqual(node(fixture.a, in: session.document).childIDs, [])
        XCTAssertEqual(node(fixture.child, in: session.document).parent, .node(fixture.root))
        XCTAssertTrue(session.canUndo)
        try await waitForRenderPlan(in: state, revision: session.document.revision)
    }

    // SF-0408-003, SF-0408-004, SF-0408-006 — one invalid hovered row must
    // not revoke the source capability before a later valid row is previewed
    // and committed during the same native pointer drag.
    func testRejectedPointerHoverRepairsToDraftingBeforeValidHover() async throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        try await waitForRenderPlan(in: state, revision: fixture.document.revision)
        state.selectLayer(fixture.a)

        let transfer = try XCTUnwrap(state.beginPointerDrag(sourceID: fixture.a))
        XCTAssertFalse(state.previewPointerDrag(transfer, destination: .container(fixture.a, index: 0)))
        XCTAssertNotNil(state.dragDropSession.identity)
        state.clearPointerDragPreview()
        guard case .drafting = state.dragDropSession.phase else {
            return XCTFail("Invalid hover should repair to drafting, not revoke the active drag")
        }
        let destination = try XCTUnwrap(state.dragDestination(before: fixture.c))
        XCTAssertTrue(state.previewPointerDrag(transfer, destination: destination))
        XCTAssertTrue(state.commitPointerDrag(transfer, destination: destination))
        XCTAssertEqual(node(fixture.root, in: session.document).childIDs, [fixture.b, fixture.a, fixture.c])
        XCTAssertTrue(session.canUndo)
        try session.undo()
        XCTAssertEqual(node(fixture.root, in: session.document).childIDs, [fixture.a, fixture.b, fixture.c])
    }

    // SF-0408-001, SF-0408-003, SF-0408-005 — an attempted drop at the
    // source's existing post-removal position is neutral: no revision,
    // history entry, autosave trigger, or selection mutation is created.
    func testNoOpAndUnselectedPointerDragAreRejectedWithoutMutation() async throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        try await waitForRenderPlan(in: state, revision: fixture.document.revision)
        let originalSelection = state.selectionState
        let originalDocument = session.document

        XCTAssertNil(state.beginPointerDrag(sourceID: fixture.a))
        XCTAssertEqual(state.dragDropFailure, .sourceNotSelected)
        XCTAssertEqual(state.selectionState, originalSelection)
        XCTAssertEqual(session.document, originalDocument)
        XCTAssertFalse(session.canUndo)

        state.selectLayer(fixture.a)
        let selected = state.selectionState
        let transfer = try XCTUnwrap(state.beginPointerDrag(sourceID: fixture.a))
        let noOpDestination = try XCTUnwrap(state.dragDestination(before: fixture.b))
        XCTAssertFalse(state.previewPointerDrag(transfer, destination: noOpDestination))
        XCTAssertEqual(state.dragDropFailure, .noOp)
        XCTAssertEqual(state.selectionState, selected)
        XCTAssertEqual(session.document, originalDocument)
        XCTAssertFalse(session.canUndo)

        state.cancelDragDrop()
        state.selectLayer(fixture.b, modifier: .add)
        XCTAssertNil(state.beginPointerDrag(sourceID: fixture.a))
        XCTAssertEqual(state.dragDropFailure, .multipleSelectionUnsupported)
        XCTAssertEqual(session.document, originalDocument)
        XCTAssertFalse(session.canUndo)
    }

    // SF-0408-003, SF-0408-004
    func testCyclesDepthStaleLockedHiddenUnavailableAndCancellationAreNeutral() throws {
        let fixture = makeFixture()
        let registry = DragDropCommandRegistry()
        let before = fixture.document
        let checks: [(DragDropCommand, DragDropValidationContext, DragDropError)] = [
            (fixture.command(source: fixture.a, destination: .container(fixture.a, index: 0)), fixture.context, .cycle),
            (fixture.command(source: fixture.a, destination: .container(fixture.child, index: 0)), fixture.context, .cycle),
            (fixture.command(source: fixture.a, destination: .container(fixture.root, index: 9), revision: fixture.document.revision + 1), fixture.context, .staleRevision),
        ]
        for (command, context, error) in checks {
            XCTAssertThrowsError(try registry.prepare(command, in: fixture.document, context: context)) { XCTAssertEqual($0 as? DragDropError, error) }
            XCTAssertEqual(fixture.document, before)
        }
        XCTAssertThrowsError(try registry.prepare(fixture.command(source: fixture.a, destination: .container(fixture.root, index: 0)), in: fixture.document, context: fixture.context, cancellation: .init(isCancelled: { true }))) { XCTAssertEqual($0 as? DragDropError, .cancelled) }
        var locked = fixture.document
        setBoolean("locked", true, nodeID: fixture.a, document: &locked)
        XCTAssertThrowsError(try registry.prepare(fixture.command(source: fixture.a, destination: .container(fixture.root, index: 0)), in: locked, context: fixture.context)) { XCTAssertEqual($0 as? DragDropError, .lockedSource) }
        let unavailable = DragDropValidationContext(activePageID: fixture.page, sceneID: fixture.scene, rendererGeneration: 1, availableNodeIDs: [fixture.root], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try registry.prepare(fixture.command(source: fixture.a, destination: .container(fixture.root, index: 0)), in: fixture.document, context: unavailable)) { XCTAssertEqual($0 as? DragDropError, .unavailableSource) }
    }

    // SF-0408-003, SF-0408-004
    func testDepthAndLifecycleRejectionAreTypedAndStateNeutral() throws {
        let fixture = makeDeepFixture(depth: DragDropPolicy.maximumDepth)
        let registry = DragDropCommandRegistry()
        let before = fixture.document
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(source: fixture.source, destination: .container(fixture.destination, index: 0)),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? DragDropError, .depthLimit) }
        let unavailable = DragDropValidationContext(
            activePageID: fixture.page, sceneID: fixture.scene, rendererGeneration: 1,
            availableNodeIDs: fixture.available, isLifecycleAvailable: false,
            lifecycleDisabledReason: "Wait for the current save operation to finish."
        )
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(source: fixture.source, destination: .container(fixture.destination, index: 0)),
            in: fixture.document,
            context: unavailable
        )) { XCTAssertEqual($0 as? DragDropError, .lifecycleUnavailable("Wait for the current save operation to finish.")) }
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0408-004, SF-0408-007 — drag validation must not recurse through a
    // valid deep project or continue preparing after cancellation.
    func testDeepHierarchyValidationIsIterativeAndCancellationIsNeutral() throws {
        let fixture = makeDeepFixture(depth: 10_000)
        let registry = DragDropCommandRegistry()
        let before = fixture.document
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(source: fixture.source, destination: .container(fixture.destination, index: 0)),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? DragDropError, .depthLimit) }
        XCTAssertEqual(fixture.document, before)

        let probe = DragCancellationProbe()
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(source: fixture.source, destination: .container(fixture.destination, index: 0)),
            in: fixture.document,
            context: fixture.context,
            // The bounded depth check stops at 33 nodes; make cancellation
            // observable inside that iterative traversal rather than after a
            // depth-limit result has correctly already been decided.
            cancellation: .init(isCancelled: { probe.shouldCancel(after: 2) })
        )) { XCTAssertEqual($0 as? DragDropError, .cancelled) }
        XCTAssertEqual(fixture.document, before)
    }

    func testMalformedDuplicateNodeInputIsRejectedWithoutIndexingTrap() throws {
        let fixture = makeFixture()
        var malformed = fixture.document
        malformed.pages[0].nodes.append(malformed.pages[0].nodes[1])
        XCTAssertThrowsError(try DragDropCommandRegistry().prepare(
            fixture.command(source: fixture.a, destination: .container(fixture.root, index: 0)),
            in: malformed,
            context: fixture.context
        )) { XCTAssertEqual($0 as? DragDropError, .invalidIndex) }
        XCTAssertEqual(malformed.pages[0].nodes.count, fixture.document.pages[0].nodes.count + 1)
    }

    // SF-0408-003, SF-0408-004, SF-0408-007 — malformed live state can have
    // a parent cycle even when child arrays do not express that cycle. Drag
    // validation must reject it deterministically rather than looping before
    // its transaction boundary.
    func testMalformedParentCycleIsRejectedWithoutTraversalLoop() throws {
        let fixture = makeFixture()
        var malformed = fixture.document
        let rootIndex = try XCTUnwrap(malformed.pages[0].nodes.firstIndex(where: { $0.id == fixture.root }))
        let childIndex = try XCTUnwrap(malformed.pages[0].nodes.firstIndex(where: { $0.id == fixture.child }))
        malformed.pages[0].nodes[rootIndex].parent = .node(fixture.child)
        malformed.pages[0].nodes[childIndex].parent = .node(fixture.root)

        XCTAssertThrowsError(try DragDropCommandRegistry().prepare(
            fixture.command(source: fixture.a, destination: .container(fixture.root, index: 0)),
            in: malformed,
            context: fixture.context
        )) { XCTAssertEqual($0 as? DragDropError, .cycle) }
        XCTAssertEqual(malformed.pages[0].nodes[rootIndex].parent, .node(fixture.child))
        XCTAssertEqual(malformed.pages[0].nodes[childIndex].parent, .node(fixture.root))
    }

    // SF-0408-005, SF-0408-008
    func testExactInverseHistorySerializationAndEditorOnlySession() throws {
        let fixture = makeFixture()
        let prepared = try DragDropCommandRegistry().prepare(fixture.command(source: fixture.c, destination: .container(fixture.a, index: 0)), in: fixture.document, context: fixture.context)
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared.command)
        let moved = session.document
        try session.undo()
        XCTAssertEqual(session.document.pages, fixture.document.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, moved.pages)
        let first = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(first, try DocumentSerializer.encode(session.document))
        XCTAssertEqual(try DocumentSerializer.decode(first), session.document)
        var drag = DragDropSession()
        _ = drag.begin(documentID: fixture.document.id, pageID: fixture.page, revision: fixture.document.revision, sceneID: fixture.scene, rendererGeneration: 1)
        XCTAssertFalse(String(decoding: try DocumentSerializer.encode(fixture.document), as: UTF8.self).contains("drag-session"))
        drag.cancel()
        XCTAssertEqual(fixture.document, makeFixture().document)
    }

    // SF-0408-006, SF-0408-008
    func testEveryProvenanceSharesPreparedCommandAndDiagnosticsAreRedacted() async throws {
        let fixture = makeFixture()
        for provenance in DragDropProvenance.allCases {
            let prepared = try DragDropCommandRegistry().prepare(fixture.command(source: fixture.a, destination: .container(fixture.root, index: 2), provenance: provenance), in: fixture.document, context: fixture.context)
            XCTAssertEqual(prepared.command.name, .moveNode)
        }
        let command = fixture.command(source: fixture.a, destination: .container(fixture.root, index: 2))
        let record = DragDropDiagnosticFactory.make(command: command, durationMilliseconds: 1, result: .success, failure: nil)
        XCTAssertEqual(record.requirementIDs, DragDropPolicy.requirementIDs.sorted())
        XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(command.sourceNodeID.description))

        let privateReason = "private-value-should-not-enter-diagnostics"
        let redacted = DragDropDiagnosticFactory.make(
            command: command,
            durationMilliseconds: 1,
            result: .failure,
            failure: .lifecycleUnavailable(privateReason)
        )
        XCTAssertEqual(redacted.failureCategory, "lifecycle-unavailable")
        XCTAssertFalse(redacted.failureCategory?.contains(privateReason) == true)
    }

    // SF-0408-006 — assistive actions surface a concrete unavailable reason
    // through the scene-local announcement channel rather than silently
    // returning when no source selection exists.
    func testUnavailableAccessibilityDragActionAnnouncementIsStateNeutral() async throws {
        let fixture = makeFixture()
        let state = WorkspaceShellState(documentSession: DocumentSession(document: fixture.document))
        state.announceDragDropUnavailable("Select an available layer before moving it.")
        XCTAssertEqual(state.lastDragDropAnnouncement, "Select an available layer before moving it.")
        XCTAssertEqual(state.documentSession.document, fixture.document)
    }

    // SF-0408-007, SF-0408-008 — production registry preparation only; this is
    // capacity evidence, not an interactive rendering or frame-pacing budget.
    func testDragDropCapacityEvidence() throws {
        for count in [100, 10_000] {
            let fixture = makeCapacityFixture(count: count)
            let registry = DragDropCommandRegistry()
            var samples: [Double] = []
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = try registry.prepare(fixture.command, in: fixture.document, context: fixture.context)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            print("DRAG_EVIDENCE count=\(count) prepare=\(samples)")
        }
        print("DRAG_EVIDENCE maximumResidentBytes=\(residentBytes())")
    }

    private struct Fixture {
        let document: CanonicalDocument; let page: PageID; let root: NodeID; let a: NodeID; let b: NodeID; let c: NodeID; let child: NodeID; let scene = CanvasViewportSceneID()
        var context: DragDropValidationContext { .init(activePageID: page, sceneID: scene, rendererGeneration: 1, availableNodeIDs: [root, a, b, c, child], isLifecycleAvailable: true, lifecycleDisabledReason: nil) }
        func command(source: NodeID, destination: DragDestination, revision: UInt64? = nil, provenance: DragDropProvenance = .automation) -> DragDropCommand { .init(identity: .init(sessionID: DragSessionID(), documentID: document.id, pageID: page, revision: revision ?? document.revision, sceneID: scene, rendererGeneration: 1), sourceNodeID: source, destination: destination, provenance: provenance) }
    }

    private func makeFixture(overlappingGeometry: Bool = false) -> Fixture {
        let pageID = PageID(UUID(uuidString: "10000000-0000-4000-8000-000000000001")!); let root = NodeID(UUID(uuidString: "10000000-0000-4000-8000-000000000002")!); let a = NodeID(UUID(uuidString: "10000000-0000-4000-8000-000000000003")!); let b = NodeID(UUID(uuidString: "10000000-0000-4000-8000-000000000004")!); let c = NodeID(UUID(uuidString: "10000000-0000-4000-8000-000000000005")!); let child = NodeID(UUID(uuidString: "10000000-0000-4000-8000-000000000006")!)
        func geometryProperties() -> [NodeProperty] {
            guard overlappingGeometry else { return [] }
            return [
                .init(key: .init(rawValue: "layout.x"), value: .number(48), origin: .authored),
                .init(key: .init(rawValue: "layout.y"), value: .number(48), origin: .authored),
                .init(key: .init(rawValue: "layout.width"), value: .number(120), origin: .authored),
                .init(key: .init(rawValue: "layout.height"), value: .number(80), origin: .authored),
            ]
        }
        let nodes = [
            DocumentNode(id: root, kind: .frame, name: "Root", parent: .page(pageID), childIDs: [a,b,c], properties: geometryProperties()),
            DocumentNode(id: a, kind: .frame, name: "A", parent: .node(root), childIDs: [child], properties: geometryProperties()),
            DocumentNode(id: b, kind: .frame, name: "B", parent: .node(root), properties: geometryProperties()),
            DocumentNode(id: c, kind: .text, name: "C", parent: .node(root), properties: geometryProperties()),
            DocumentNode(id: child, kind: .frame, name: "Child", parent: .node(a), properties: geometryProperties()),
        ]
        return Fixture(document: CanonicalDocument(id: DocumentID(UUID(uuidString: "10000000-0000-4000-8000-000000000007")!), pages: [DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home, rootNodeIDs: [root], nodes: nodes)]), page: pageID, root: root, a: a, b: b, c: c, child: child)
    }

    private struct DeepFixture {
        let document: CanonicalDocument; let page: PageID; let source: NodeID; let destination: NodeID; let scene = CanvasViewportSceneID(); let available: Set<NodeID>
        var context: DragDropValidationContext { .init(activePageID: page, sceneID: scene, rendererGeneration: 1, availableNodeIDs: available, isLifecycleAvailable: true, lifecycleDisabledReason: nil) }
        func command(source: NodeID, destination: DragDestination) -> DragDropCommand { .init(identity: .init(sessionID: DragSessionID(), documentID: document.id, pageID: page, revision: document.revision, sceneID: scene, rendererGeneration: 1), sourceNodeID: source, destination: destination, provenance: .automation) }
    }

    private func makeDeepFixture(depth: Int) -> DeepFixture {
        let page = PageID(); let source = NodeID(); let root = NodeID()
        var nodes = [DocumentNode(id: source, kind: .frame, name: "Source", parent: .page(page))]
        let chain = [root] + (1..<depth).map { _ in NodeID() }
        for (index, id) in chain.enumerated() {
            nodes.append(DocumentNode(
                id: id, kind: .frame, name: "Frame",
                parent: index == 0 ? .page(page) : .node(chain[index - 1]),
                childIDs: index + 1 < chain.count ? [chain[index + 1]] : []
            ))
        }
        let destination = chain.last!
        let document = CanonicalDocument(id: DocumentID(), pages: [DocumentPage(id: page, name: "Home", route: .init(rawValue: "/"), role: .home, rootNodeIDs: [source, root], nodes: nodes)])
        return .init(document: document, page: page, source: source, destination: destination, available: Set(nodes.map(\.id)))
    }

    private struct CapacityFixture {
        let document: CanonicalDocument; let command: DragDropCommand; let context: DragDropValidationContext
    }

    private func makeCapacityFixture(count: Int) -> CapacityFixture {
        let page = PageID(); let root = NodeID(); let children = (0..<count).map { _ in NodeID() }
        let rootNode = DocumentNode(id: root, kind: .frame, name: "Root", parent: .page(page), childIDs: children)
        let nodes = [rootNode] + children.map { DocumentNode(id: $0, kind: .frame, name: "Layer", parent: .node(root)) }
        let document = CanonicalDocument(id: DocumentID(), pages: [DocumentPage(id: page, name: "Home", route: .init(rawValue: "/"), role: .home, rootNodeIDs: [root], nodes: nodes)])
        let scene = CanvasViewportSceneID()
        let command = DragDropCommand(identity: .init(sessionID: DragSessionID(), documentID: document.id, pageID: page, revision: document.revision, sceneID: scene, rendererGeneration: 1), sourceNodeID: children[0], destination: .container(root, index: count), provenance: .automation)
        return .init(document: document, command: command, context: .init(activePageID: page, sceneID: scene, rendererGeneration: 1, availableNodeIDs: Set(nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil))
    }

    private func residentBytes() -> UInt64 {
        var info = mach_task_basic_info(); var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
    }
    private func waitForRenderPlan(in state: WorkspaceShellState, revision: UInt64) async throws {
        for _ in 0..<400 {
            if state.canvasRenderPlan?.identity.revision == revision { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for canonical hierarchy adoption")
    }
    private func requirePlan(_ state: WorkspaceShellState) throws -> CanvasRenderPlan {
        try XCTUnwrap(state.canvasRenderPlan)
    }
    private func node(_ id: NodeID, in document: CanonicalDocument) -> DocumentNode { document.pages[0].nodes.first { $0.id == id }! }
    private func setBoolean(_ key: String, _ value: Bool, nodeID: NodeID, document: inout CanonicalDocument) { let index = document.pages[0].nodes.firstIndex { $0.id == nodeID }!; document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: key), value: .boolean(value))) }

    private final class DragCancellationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var checks = 0

        func shouldCancel(after count: Int) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            checks += 1
            return checks > count
        }
    }
}
