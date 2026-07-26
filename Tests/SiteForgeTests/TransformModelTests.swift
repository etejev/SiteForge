import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class TransformModelTests: XCTestCase {
    // SF-0403-001, SF-0403-002, SF-0403-003
    func testMoveResolutionIsExactAndAxisConstrained() throws {
        let frame = WorldRect(
            origin: .init(x: 10, y: 20),
            size: .init(width: 120, height: 80)
        )
        XCTAssertEqual(
            try TransformCommandRegistry.resolve(
                frame,
                operation: .move(delta: .init(dx: 7, dy: -3), constraint: .none)
            ),
            .init(origin: .init(x: 17, y: 17), size: frame.size)
        )
        XCTAssertEqual(
            try TransformCommandRegistry.resolve(
                frame,
                operation: .move(delta: .init(dx: 7, dy: -3), constraint: .horizontal)
            ).origin,
            .init(x: 17, y: 20)
        )
        XCTAssertEqual(
            try TransformCommandRegistry.resolve(
                frame,
                operation: .move(delta: .init(dx: 7, dy: -3), constraint: .vertical)
            ).origin,
            .init(x: 10, y: 17)
        )
    }

    // SF-0403-001, SF-0403-002, SF-0403-003
    func testEveryResizeHandleProducesDeterministicPositiveGeometry() throws {
        let frame = WorldRect(
            origin: .init(x: 20, y: 30),
            size: .init(width: 100, height: 60)
        )
        let expectations: [TransformHandle: WorldRect] = [
            .topLeft: .init(origin: .init(x: 25, y: 34), size: .init(width: 95, height: 56)),
            .top: .init(origin: .init(x: 20, y: 34), size: .init(width: 100, height: 56)),
            .topRight: .init(origin: .init(x: 20, y: 34), size: .init(width: 105, height: 56)),
            .right: .init(origin: .init(x: 20, y: 30), size: .init(width: 105, height: 60)),
            .bottomRight: .init(origin: .init(x: 20, y: 30), size: .init(width: 105, height: 64)),
            .bottom: .init(origin: .init(x: 20, y: 30), size: .init(width: 100, height: 64)),
            .bottomLeft: .init(origin: .init(x: 25, y: 30), size: .init(width: 95, height: 64)),
            .left: .init(origin: .init(x: 25, y: 30), size: .init(width: 95, height: 60)),
        ]
        for handle in TransformHandle.allCases {
            XCTAssertEqual(
                try TransformCommandRegistry.resolve(
                    frame,
                    operation: .resize(
                        handle: handle,
                        delta: .init(dx: 5, dy: 4),
                        constraint: .none
                    )
                ),
                expectations[handle],
                handle.rawValue
            )
        }
    }

    // SF-0403-002, SF-0403-004
    func testInvalidGeometryAndCancellationAreStateNeutral() throws {
        let fixture = makeFixture()
        let registry = TransformCommandRegistry()
        let before = fixture.document
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(operation: .move(delta: .init(dx: .nan, dy: 0), constraint: .none)),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? TransformError, .invalidDelta) }
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(operation: .resize(
                handle: .left,
                delta: .init(dx: 500, dy: 0),
                constraint: .none
            )),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? TransformError, .invalidResult) }
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(operation: .move(delta: .init(dx: 1, dy: 1), constraint: .none)),
            in: fixture.document,
            context: fixture.context,
            cancellation: .init(isCancelled: { true })
        )) { XCTAssertEqual($0 as? TransformError, .cancelled) }
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0403-002, SF-0403-003, SF-0403-004
    func testIdentityScopeStateAndSelectionValidationRejectWithoutMutation() throws {
        var fixture = makeFixture()
        let registry = TransformCommandRegistry()
        let before = fixture.document
        let operation = TransformOperation.move(delta: .init(dx: 2, dy: 3), constraint: .none)
        let missingID = NodeID(UUID(uuidString: "91000000-0000-4000-8000-000000000099")!)
        let crossPageID = fixture.document.pages[1].rootNodeIDs[0]
        let cases: [(GeometryTransformCommand, TransformValidationContext, TransformError)] = [
            (fixture.command(operation: operation, documentID: DocumentID()), fixture.context, .staleDocument),
            (fixture.command(operation: operation, revision: fixture.document.revision + 1), fixture.context, .staleRevision),
            (fixture.command(operation: operation, rendererGeneration: 8), fixture.context, .staleRenderer),
            (fixture.command(operation: operation, orderedIDs: []), fixture.context, .emptySelection),
            (fixture.command(operation: operation, orderedIDs: [fixture.nodeID, fixture.nodeID]),
             fixture.context(selectedIDs: [fixture.nodeID, fixture.nodeID]), .duplicateTarget),
            (fixture.command(operation: operation), fixture.context(selectedIDs: []), .selectionMismatch),
            (fixture.command(operation: operation, orderedIDs: [missingID]),
             fixture.context(selectedIDs: [missingID]), .missingTarget),
            (fixture.command(operation: operation, orderedIDs: [crossPageID]),
             fixture.context(selectedIDs: [crossPageID]), .crossPageTarget),
            (fixture.command(operation: operation),
             fixture.context(selectedIDs: fixture.selectedIDs, availableIDs: []), .unavailableTarget),
            (fixture.command(operation: operation),
             fixture.context(selectedIDs: fixture.selectedIDs, lifecycleAvailable: false),
             .lifecycleUnavailable("A document transition is active.")),
        ]
        for (command, context, error) in cases {
            XCTAssertThrowsError(try registry.prepare(command, in: fixture.document, context: context)) {
                XCTAssertEqual($0 as? TransformError, error)
            }
            XCTAssertEqual(fixture.document, before)
        }
        fixture.document.pages[0].nodes[1].properties.append(booleanProperty("locked", true))
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(operation: operation),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? TransformError, .lockedTarget) }
        fixture.document.pages[0].nodes[1].properties.removeLast()
        fixture.document.pages[0].nodes[1].properties.append(booleanProperty("hidden", true))
        XCTAssertThrowsError(try registry.prepare(
            fixture.command(operation: operation),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? TransformError, .hiddenTarget) }
    }

    // SF-0403-002, SF-0403-003
    func testMultipleMovePreservesOrderAndResizeRejectsIncompatibleSelection() throws {
        let fixture = makeFixture(selectedIDs: nil)
        let ids = [fixture.nodeID, fixture.secondNodeID]
        let context = fixture.context(selectedIDs: ids)
        let move = fixture.command(
            operation: .move(delta: .init(dx: 5, dy: 6), constraint: .none),
            orderedIDs: ids
        )
        let prepared = try TransformCommandRegistry().prepare(
            move, in: fixture.document, context: context
        )
        XCTAssertEqual(prepared.geometries.map(\.nodeID), ids)
        XCTAssertEqual(prepared.geometries.map(\.preview.origin), [
            .init(x: 15, y: 26), .init(x: 205, y: 56),
        ])
        XCTAssertThrowsError(try TransformCommandRegistry().prepare(
            fixture.command(
                operation: .resize(
                    handle: .bottomRight,
                    delta: .init(dx: 5, dy: 5),
                    constraint: .none
                ),
                orderedIDs: ids
            ),
            in: fixture.document,
            context: context
        )) { XCTAssertEqual($0 as? TransformError, .incompatibleMultipleResize) }
    }

    // SF-0403-002, SF-0403-006, SF-0403-008
    func testEveryInputProvenanceUsesOneRegistryAndSpecificDisabledReasons() throws {
        let fixture = makeFixture()
        let registry = TransformCommandRegistry()
        let operation = TransformOperation.move(
            delta: .init(dx: 3, dy: -2),
            constraint: .none
        )
        let commands = try TransformProvenance.allCases.map { provenance in
            var command = fixture.command(operation: operation)
            command = GeometryTransformCommand(
                identity: command.identity,
                orderedNodeIDs: command.orderedNodeIDs,
                operation: command.operation,
                provenance: provenance
            )
            return try registry.prepare(
                command,
                in: fixture.document,
                context: fixture.context
            ).documentCommand
        }
        XCTAssertTrue(commands.dropFirst().allSatisfy { $0 == commands.first })

        let unavailable = registry.availability(
            for: fixture.command(operation: operation),
            in: fixture.document,
            context: fixture.context(
                selectedIDs: fixture.selectedIDs,
                lifecycleAvailable: false
            )
        )
        XCTAssertFalse(unavailable.isEnabled)
        XCTAssertEqual(unavailable.disabledReason, "A document transition is active.")
    }

    // SF-0403-001, SF-0403-005
    func testCommitIsOneAtomicTransactionWithExactUndoRedoAndBranchInvalidation() throws {
        let fixture = makeFixture()
        let prepared = try TransformCommandRegistry().prepare(
            fixture.command(operation: .move(
                delta: .init(dx: 14, dy: -8),
                constraint: .none
            )),
            in: fixture.document,
            context: fixture.context
        )
        let session = DocumentSession(document: fixture.document)
        let before = session.document
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.document.revision, before.revision + 1)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame, prepared.geometries[0].preview)
        try session.undo()
        XCTAssertEqual(session.document, before.withRevision(before.revision + 2))
        try session.redo()
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame, prepared.geometries[0].preview)
        try session.undo()
        let branch = try TransformCommandRegistry().prepare(
            fixture.with(document: session.document).command(operation: .move(
                delta: .init(dx: 1, dy: 0),
                constraint: .horizontal
            )),
            in: session.document,
            context: fixture.with(document: session.document).context
        )
        try session.execute(branch.documentCommand)
        XCTAssertFalse(session.canRedo)

        var exhausted = fixture.document
        exhausted.revision = UInt64.max
        let exhaustedFixture = fixture.with(document: exhausted)
        XCTAssertThrowsError(try TransformCommandRegistry().prepare(
            exhaustedFixture.command(operation: .move(
                delta: .init(dx: 1, dy: 0),
                constraint: .horizontal
            )),
            in: exhausted,
            context: exhaustedFixture.context
        )) { XCTAssertEqual($0 as? TransformError, .revisionExhausted) }
    }

    // SF-0403-001, SF-0403-004, SF-0403-005
    func testDeterministicPersistenceHistoryAndPreviewExclusion() async throws {
        let fixture = makeFixture()
        let registry = TransformCommandRegistry()
        let prepared = try registry.prepare(
            fixture.command(operation: .resize(
                handle: .bottomRight,
                delta: .init(dx: 20, dy: 10),
                constraint: .none
            )),
            in: fixture.document,
            context: fixture.context
        )
        var transformSession = TransformSession()
        let identity = transformSession.begin(
            documentID: fixture.document.id,
            pageID: fixture.pageID,
            revision: fixture.document.revision,
            sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration
        )
        transformSession.preview(.init(
            identity: identity,
            operation: prepared.operation,
            geometries: prepared.geometries
        ))
        let baselineBytes = try DocumentSerializer.encode(fixture.document)
        XCTAssertFalse(String(decoding: baselineBytes, as: UTF8.self).contains(identity.sessionID.description))

        let documentSession = DocumentSession(document: fixture.document)
        try documentSession.execute(prepared.documentCommand)
        let package = ProjectPackage(
            projectID: ProjectID(),
            createdAt: ProjectTimestamp("2026-07-26T12:00:00.000Z"),
            document: documentSession.document
        )
        let persisted = try await PersistedHistoryStore().package(
            package,
            with: documentSession.historySnapshot()
        )
        let store = ProjectPackageStore()
        let first = try await store.encode(persisted)
        let second = try await store.encode(persisted)
        XCTAssertEqual(first, second)
        let reopened = try await store.decode(first)
        XCTAssertEqual(reopened.document.nodeGeometry(fixture.nodeID)?.frame, prepared.geometries[0].preview)
        guard case .restored(let history) = try await PersistedHistoryStore().load(from: reopened) else {
            return XCTFail("Expected transform history")
        }
        let reopenedSession = DocumentSession(document: reopened.document)
        try reopenedSession.installValidatedHistory(history)
        try reopenedSession.undo()
        XCTAssertEqual(reopenedSession.document.nodeGeometry(fixture.nodeID)?.frame, prepared.geometries[0].original)
    }

    // SF-0403-002, SF-0403-004
    func testSessionStateMachineRejectsStalePreviewAndCancelsExactly() {
        let fixture = makeFixture()
        var session = TransformSession()
        let identity = session.begin(
            documentID: fixture.document.id,
            pageID: fixture.pageID,
            revision: fixture.document.revision,
            sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration
        )
        XCTAssertEqual(session.currentIdentity, identity)
        let stale = TransformOperationIdentity(
            sessionID: TransformSessionID(),
            documentID: identity.documentID,
            pageID: identity.pageID,
            revision: identity.revision,
            sceneID: identity.sceneID,
            rendererGeneration: identity.rendererGeneration
        )
        session.preview(.init(
            identity: stale,
            operation: .move(delta: .init(dx: 1, dy: 1), constraint: .none),
            geometries: []
        ))
        XCTAssertEqual(session.phase, .drafting(identity))
        session.cancel()
        XCTAssertEqual(session.phase, .cancelled)
        XCTAssertNil(session.currentIdentity)
        session.deactivate()
        XCTAssertEqual(session.phase, .inactive)
    }

    // SF-0403-001 through SF-0403-008
    func testWorkspaceTransactionKeepsSelectionAndSynchronizesLayoutRendererAndUndo() async throws {
        let state = WorkspaceShellState(
            documentSession: DocumentSession(document: ProjectCreation.blank())
        )
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        for _ in 0..<200 where state.canvasRenderPlan == nil { await Task.yield() }
        state.selectTool(.frame)
        state.performDefaultInsertion(.frame, provenance: .automation)
        for _ in 0..<200 where state.selectionState.isEmpty { await Task.yield() }

        let nodeID = try XCTUnwrap(state.selectionState.primaryID)
        for _ in 0..<200 where state.canvasRenderPlan?.authoredObjects
            .contains(where: { $0.id == nodeID }) != true {
            await Task.yield()
        }
        let original = try XCTUnwrap(
            state.documentSession.document.nodeGeometry(nodeID)?.frame
        )
        let historyCount = state.documentSession.historySnapshot().undoEntries.count
        state.selectTool(.select)
        let beforeCancelledPreview = try DocumentSerializer.encode(state.documentSession.document)
        XCTAssertTrue(state.beginPointerTransform(at: .init(
            x: original.origin.x + original.size.width / 2,
            y: original.origin.y + original.size.height / 2
        )))
        state.updatePointerTransform(delta: .init(dx: 30, dy: 20), constrainAxis: false)
        guard case .previewing(let preview) = state.transformSession.phase else {
            return XCTFail("Expected an editor-only transform preview")
        }
        XCTAssertEqual(preview.geometries[0].preview.origin, .init(
            x: original.origin.x + 30,
            y: original.origin.y + 20
        ))
        XCTAssertEqual(try DocumentSerializer.encode(state.documentSession.document), beforeCancelledPreview)
        state.performEscape()
        XCTAssertEqual(state.transformSession.phase, .cancelled)
        XCTAssertEqual(try DocumentSerializer.encode(state.documentSession.document), beforeCancelledPreview)
        XCTAssertEqual(state.selectionState.primaryID, nodeID)

        state.performTransform(
            .move(delta: .init(dx: 16, dy: 9), constraint: .none),
            provenance: .automation
        )
        for _ in 0..<200 where state.canvasRenderPlan?.identity.revision
            != state.documentSession.document.revision {
            await Task.yield()
        }

        XCTAssertEqual(state.selectionState.primaryID, nodeID)
        XCTAssertEqual(
            state.documentSession.document.nodeGeometry(nodeID)?.frame.origin,
            .init(x: original.origin.x + 16, y: original.origin.y + 9)
        )
        XCTAssertEqual(
            state.documentSession.historySnapshot().undoEntries.count,
            historyCount + 1
        )
        XCTAssertEqual(
            state.canvasRenderPlan?.authoredObjects.first(where: { $0.id == nodeID })?.frame,
            state.documentSession.document.nodeGeometry(nodeID)?.frame
        )
        XCTAssertEqual(state.transformOverlays.filter {
            $0.kind.hasPrefix("transform-handle")
        }.count, 8)

        state.undo()
        XCTAssertEqual(state.documentSession.document.nodeGeometry(nodeID)?.frame, original)
        XCTAssertEqual(state.selectionState.primaryID, nodeID)
    }

    // SF-0403-002, SF-0403-005, SF-0403-008
    func testRendererHitTestingAndDirtyRegionsFollowCommittedGeometry() throws {
        let fixture = makeFixture()
        let beforeFrame = try XCTUnwrap(fixture.document.nodeGeometry(fixture.nodeID)?.frame)
        let afterFrame = try TransformCommandRegistry.resolve(
            beforeFrame,
            operation: .move(delta: .init(dx: 50, dy: 40), constraint: .none)
        )
        let identity1 = fixture.renderIdentity(revision: 1)
        let identity2 = fixture.renderIdentity(revision: 2)
        let beforeScene = fixture.scene(identity: identity1, frame: beforeFrame)
        let afterScene = fixture.scene(identity: identity2, frame: afterFrame)
        let viewport = try CanvasViewportState(
            viewportSize: .init(width: 800, height: 600),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)),
            pixelRatio: .init(2)
        )
        let core = CanvasRendererCore()
        let plan = try core.prepare(
            scene: afterScene,
            overlays: .init(identity: identity2, overlays: []),
            viewport: viewport,
            previous: beforeScene
        )
        XCTAssertEqual(plan.invalidation, .dirtyRegions)
        XCTAssertEqual(plan.dirtyWorldRegions, [beforeFrame, afterFrame])
        XCTAssertNil(core.hitTest(.init(x: 11, y: 21), in: plan))
        XCTAssertEqual(core.hitTest(.init(x: 61, y: 61), in: plan), fixture.nodeID)
    }

    // SF-0403-007, SF-0403-008
    func testTransformCapacityEvidence() throws {
        var maximumResidentBytes: UInt64 = 0
        for count in [100, 10_000] {
            let fixture = makeCapacityFixture(count: count)
            var samples: [Double] = []
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = try TransformCommandRegistry().prepare(
                    fixture.command,
                    in: fixture.document,
                    context: fixture.context
                )
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            maximumResidentBytes = max(maximumResidentBytes, residentBytes())
            print("TRANSFORM_EVIDENCE count=\(count) prepare=\(samples)")
        }
        print("TRANSFORM_EVIDENCE maximumResidentBytes=\(maximumResidentBytes)")
    }

    // SF-0403-008
    func testDiagnosticsAreRedactedAndActionable() async {
        let fixture = makeFixture()
        let command = fixture.command(operation: .move(
            delta: .init(dx: 1, dy: 0),
            constraint: .horizontal
        ))
        let record = TransformDiagnosticFactory.make(
            command: command,
            durationMilliseconds: 0.2,
            resultRevision: fixture.document.revision + 1,
            result: .success,
            failure: nil
        )
        XCTAssertEqual(record.requirementIDs, (1...8).map { "SF-0403-00\($0)" })
        XCTAssertEqual(record.affectedObjectCount, 1)
        XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
        XCTAssertFalse(String(describing: record).contains("/Users/"))
        let diagnostics = TransformDiagnostics()
        await diagnostics.append(record)
        let records = await diagnostics.snapshot()
        XCTAssertEqual(records, [record])
    }
}

private struct TransformFixture {
    var document: CanonicalDocument
    let pageID: PageID
    let rootID: NodeID
    let nodeID: NodeID
    let secondNodeID: NodeID
    let sceneID: CanvasViewportSceneID
    let rendererGeneration: UInt64
    var selectedIDs: [NodeID]

    var context: TransformValidationContext { context(selectedIDs: selectedIDs) }

    func context(
        selectedIDs: [NodeID],
        availableIDs: Set<NodeID>? = nil,
        lifecycleAvailable: Bool = true
    ) -> TransformValidationContext {
        TransformValidationContext(
            activePageID: pageID,
            currentSceneID: sceneID,
            rendererGeneration: rendererGeneration,
            selectedNodeIDs: selectedIDs,
            availableNodeIDs: availableIDs ?? Set(document.pages[0].nodes.map(\.id)),
            isLifecycleAvailable: lifecycleAvailable,
            lifecycleDisabledReason: lifecycleAvailable ? nil : "A document transition is active."
        )
    }

    func command(
        operation: TransformOperation,
        orderedIDs: [NodeID]? = nil,
        documentID: DocumentID? = nil,
        revision: UInt64? = nil,
        rendererGeneration: UInt64? = nil
    ) -> GeometryTransformCommand {
        GeometryTransformCommand(
            identity: TransformOperationIdentity(
                sessionID: TransformSessionID(UUID(uuidString: "94000000-0000-4000-8000-000000000001")!),
                documentID: documentID ?? document.id,
                pageID: pageID,
                revision: revision ?? document.revision,
                sceneID: sceneID,
                rendererGeneration: rendererGeneration ?? self.rendererGeneration
            ),
            orderedNodeIDs: orderedIDs ?? selectedIDs,
            operation: operation,
            provenance: .automation
        )
    }

    func with(document: CanonicalDocument) -> Self {
        Self(
            document: document, pageID: pageID, rootID: rootID,
            nodeID: nodeID, secondNodeID: secondNodeID, sceneID: sceneID,
            rendererGeneration: rendererGeneration, selectedIDs: selectedIDs
        )
    }

    func renderIdentity(revision: UInt64) -> CanvasRenderRequestIdentity {
        CanvasRenderRequestIdentity(
            documentID: document.id,
            revision: revision,
            sceneID: sceneID,
            sceneGeneration: revision,
            viewportGeneration: 1,
            scale: try! .init(2)
        )
    }

    func scene(identity: CanvasRenderRequestIdentity, frame: WorldRect) -> CanvasRenderSceneSnapshot {
        CanvasRenderSceneSnapshot(
            identity: identity,
            surfaceID: CanvasRenderSurfaceID(UUID(uuidString: "95000000-0000-4000-8000-000000000001")!),
            objects: [
                CanvasRenderObject(
                    id: nodeID, frame: frame, clipRect: nil, paintOrder: 0,
                    style: .container, isVisible: true, accessibilityLabel: "Frame"
                ),
            ]
        )
    }
}

private func makeFixture(selectedIDs: [NodeID]? = nil) -> TransformFixture {
    var document = ProjectCreation.blank()
    let pageID = document.pages[0].id
    let rootID = document.pages[0].rootNodeIDs[0]
    let nodeID = NodeID(UUID(uuidString: "91000000-0000-4000-8000-000000000001")!)
    let secondNodeID = NodeID(UUID(uuidString: "91000000-0000-4000-8000-000000000002")!)
    document.pages[0].nodes[0].childIDs = [nodeID, secondNodeID]
    document.pages[0].nodes.append(makeGeometryNode(
        id: nodeID, parent: rootID, x: 10, y: 20, width: 120, height: 80
    ))
    document.pages[0].nodes.append(makeGeometryNode(
        id: secondNodeID, parent: rootID, x: 200, y: 50, width: 90, height: 70
    ))
    return TransformFixture(
        document: document,
        pageID: pageID,
        rootID: rootID,
        nodeID: nodeID,
        secondNodeID: secondNodeID,
        sceneID: CanvasViewportSceneID(UUID(uuidString: "93000000-0000-4000-8000-000000000001")!),
        rendererGeneration: document.revision,
        selectedIDs: selectedIDs ?? [nodeID]
    )
}

private func makeGeometryNode(
    id: NodeID,
    parent: NodeID,
    x: Double,
    y: Double,
    width: Double,
    height: Double
) -> DocumentNode {
    let keys: [(String, Double)] = [
        ("layout.x", x), ("layout.y", y),
        ("layout.width", width), ("layout.height", height),
    ]
    return DocumentNode(
        id: id,
        kind: .frame,
        name: "Frame",
        parent: .node(parent),
        properties: keys.enumerated().map { index, item in
            NodeProperty(
                id: PropertyID(UUID(uuidString: String(
                    format: "92000000-0000-4000-8000-%012d",
                    index + (id.rawValue.uuidString.hasSuffix("2") ? 10 : 0) + 1
                ))!),
                key: PropertyKey(rawValue: item.0),
                value: .number(item.1),
                origin: .authored
            )
        }
    )
}

private func booleanProperty(_ key: String, _ value: Bool) -> NodeProperty {
    NodeProperty(key: .init(rawValue: key), value: .boolean(value))
}

private extension CanonicalDocument {
    func nodeGeometry(_ id: NodeID) -> InsertionGeometry? {
        pages.flatMap(\.nodes).first(where: { $0.id == id })?.insertionGeometry
    }

    func withRevision(_ value: UInt64) -> CanonicalDocument {
        var copy = self
        copy.revision = value
        return copy
    }
}

private struct TransformCapacityFixture {
    let document: CanonicalDocument
    let command: GeometryTransformCommand
    let context: TransformValidationContext
}

private func makeCapacityFixture(count: Int) -> TransformCapacityFixture {
    var document = ProjectCreation.blank()
    let pageID = document.pages[0].id
    let rootID = document.pages[0].rootNodeIDs[0]
    let selectedID = NodeID(UUID(uuidString: "96000000-0000-4000-8000-000000000001")!)
    document.pages[0].nodes[0].childIDs = [selectedID]
    document.pages[0].nodes.append(makeGeometryNode(
        id: selectedID, parent: rootID, x: 10, y: 10, width: 100, height: 100
    ))
    if count > 1 {
        for index in 1..<count {
            let value = String(format: "96000000-0000-4000-8001-%012d", index)
            let id = NodeID(UUID(uuidString: value)!)
            document.pages[0].nodes[0].childIDs.append(id)
            document.pages[0].nodes.append(DocumentNode(
                id: id, kind: .frame, name: "Capacity \(index)", parent: .node(rootID)
            ))
        }
    }
    let sceneID = CanvasViewportSceneID()
    let context = TransformValidationContext(
        activePageID: pageID,
        currentSceneID: sceneID,
        rendererGeneration: document.revision,
        selectedNodeIDs: [selectedID],
        availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
        isLifecycleAvailable: true,
        lifecycleDisabledReason: nil
    )
    let command = GeometryTransformCommand(
        identity: .init(
            sessionID: TransformSessionID(),
            documentID: document.id,
            pageID: pageID,
            revision: document.revision,
            sceneID: sceneID,
            rendererGeneration: document.revision
        ),
        orderedNodeIDs: [selectedID],
        operation: .move(delta: .init(dx: 1, dy: 1), constraint: .none),
        provenance: .automation
    )
    return TransformCapacityFixture(document: document, command: command, context: context)
}

private func residentBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}
