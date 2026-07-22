import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class InsertionModelTests: XCTestCase {
    // SF-0405-001, SF-0405-002, SF-0405-004, SF-0405-005
    func testFrameAndTextDefaultsHaveStableIdentityOwnershipOrderAndOrigins() throws {
        let fixture = makeFixture()
        let frame = try prepare(.frame, fixture: fixture, nodeID: fixture.frameID, index: 0)
        let text = try prepare(.text, fixture: fixture, nodeID: fixture.textID, index: 1)

        XCTAssertEqual(frame.node.kind, .frame)
        XCTAssertEqual(frame.node.parent, .node(fixture.rootID))
        XCTAssertEqual(frame.geometry.size, .init(width: 240, height: 160))
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
        }
    }

    private func prepare(_ kind: InsertionKind, fixture: Fixture, nodeID: NodeID, index: Int = 0, provenance: InsertionProvenance = .pointer) throws -> PreparedInsertion {
        try InsertionCommandRegistry().prepare(command(kind, fixture: fixture, nodeID: nodeID, index: index, provenance: provenance), in: fixture.document, context: fixture.context)
    }

    private func booleanProperty(_ key: String, _ value: Bool) -> NodeProperty {
        .init(key: .init(rawValue: key), value: .boolean(value))
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
