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
        state.setSnappingSuppressed(true)
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

    // Shared resolved-frame contract: authored tile pixels, hit testing,
    // selection, accessibility, and Inspector all begin with one world frame.
    // A centered overlay stroke may extend half a device pixel; its path never
    // applies a separate logical inset.
    func testResolvedGeometryIsSharedAcrossRendererSelectionAccessibilityAndStyles() throws {
        let fixture = makeFixture()
        let core = CanvasRendererCore()
        let kinds: [NodeKind] = [.frame, .text, .section, .stack, .grid]
        for scale in [1.0, 2.0] {
            for zoom in [0.25, 1.0, 8.0] {
                for origin in [WorldPoint(x: 512, y: 512), WorldPoint(x: -80, y: 40)] {
                    // Keep the object visible at every zoom while placing its device
                    // raster near a tile boundary as the transform changes.
                    let frame = WorldRect(origin: .init(x: origin.x + 31, y: origin.y + 29), size: .init(width: 96, height: 48))
                    let identity = fixture.renderIdentity(revision: fixture.document.revision)
                    let objects = kinds.enumerated().map { index, kind in CanvasRenderObject(id: NodeID(), frame: frame, clipRect: nil, paintOrder: index, style: kind == .text ? .textPlaceholder : .frameSurface, isVisible: true, accessibilityLabel: kind.rawValue, plainText: kind == .text ? "Text" : nil, fillRGBA: [0.2, 0.4, 0.6, 0.5], opacity: 0.4) }
                    let viewport = try CanvasViewportState(worldOrigin: origin, viewportSize: .init(width: 800, height: 600), contentBounds: .init(origin: .init(x: -2_000, y: -2_000), size: .init(width: 8_000, height: 8_000)), zoom: try .init(zoom), pixelRatio: .init(scale))
                    let scene = CanvasRenderSceneSnapshot(identity: identity, surfaceID: CanvasRenderSurfaceID(), objects: objects)
                    let plan = try core.prepare(scene: scene, overlays: .init(identity: identity, overlays: []), viewport: viewport)
                    for object in plan.authoredObjects {
                        XCTAssertEqual(object.frame, frame)
                        XCTAssertEqual(core.hitTest(.init(x: frame.origin.x + 10, y: frame.origin.y + 10), in: plan), objects.last?.id)
                        let accessible = try XCTUnwrap(plan.accessibilityElements.first(where: { $0.objectID == object.id }))
                        // Accessibility virtualizes only the visible authored
                        // intersection. At 800% this object intentionally
                        // crosses the viewport edge, while canonical/render/
                        // selection geometry remains the complete world rect.
                        let visible = viewport.visibleWorldRect
                        let visibleFrame = WorldRect(
                            origin: .init(
                                x: max(frame.minX, visible.minX),
                                y: max(frame.minY, visible.minY)
                            ),
                            size: .init(
                                width: max(0, min(frame.maxX, visible.maxX) - max(frame.minX, visible.minX)),
                                height: max(0, min(frame.maxY, visible.maxY) - max(frame.minY, visible.minY))
                            )
                        )
                        let expected = try viewport.transform.worldToViewport(visibleFrame.origin)
                        XCTAssertEqual(accessible.frame.origin, expected)
                        XCTAssertEqual(accessible.frame.size.width, visibleFrame.size.width * zoom, accuracy: 1 / scale)
                    }
                    let targets = plan.authoredObjects.enumerated().map { index, object in SelectionTargetSnapshot(id: object.id, pageID: fixture.pageID, parentID: nil, name: "node", kind: kinds[index], frame: object.frame, clipRect: nil, paintOrder: index, isVisible: true, isLocked: false, isAvailable: true) }
                    let selectionScene = SelectionSceneSnapshot(identity: identity, activePageID: fixture.pageID, activeContainerID: nil, targets: targets)
                    var selection = SelectionState(); selection.establishScene(selectionScene); selection.setSelection([objects[0].id], primary: objects[0].id, anchor: objects[0].id, provenance: .pointer)
                    let overlay = try SelectionOverlayPlanner().plan(selection: selection, scene: selectionScene, renderPlan: plan)
                    XCTAssertEqual(overlay.overlays.first?.frame, frame)
                }
            }
        }
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

    // SF-0403-001, SF-0403-002, SF-0403-004, SF-0403-005, SF-0403-008
    func testGeometryInspectorCommitsApplicableSubsetAtomicallyWithUndoAndPersistence() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let registry = GeometryInspectorCommandRegistry()

        XCTAssertEqual(registry.value(for: .x, in: fixture.document, context: fixture.context), .mixed)
        let prepared = try registry.prepare(
            fixture.inspectorCommand(field: .x, value: 42),
            in: fixture.document,
            context: fixture.context
        )
        XCTAssertEqual(prepared.skippedNodeIDs, [])
        guard case let .batch(children) = prepared.documentCommand else {
            return XCTFail("Inspector edit must be one atomic property batch")
        }
        XCTAssertEqual(children.count, 2)

        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 42)
        XCTAssertEqual(session.document.nodeGeometry(fixture.secondNodeID)?.frame.origin.x, 42)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        _ = try session.undo()
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 10)
        XCTAssertEqual(session.document.nodeGeometry(fixture.secondNodeID)?.frame.origin.x, 200)
        _ = try session.redo()
        XCTAssertEqual(session.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 42)
        XCTAssertEqual(session.document.nodeGeometry(fixture.secondNodeID)?.frame.origin.x, 42)
    }

    // SF-0403-003, SF-0403-004, SF-0403-006, SF-0403-008
    func testGeometryInspectorRejectsInvalidStaleAndUnavailableValuesWithoutMutation() throws {
        let fixture = makeFixture()
        let registry = GeometryInspectorCommandRegistry()
        let original = try DocumentSerializer.encode(fixture.document)

        for value in [Double.nan, Double.infinity, -1, LayoutPolicy.maximumDimension + 1] {
            XCTAssertThrowsError(try registry.prepare(
                fixture.inspectorCommand(field: .width, value: value),
                in: fixture.document,
                context: fixture.context
            ))
        }
        XCTAssertThrowsError(try registry.prepare(
            fixture.inspectorCommand(field: .x, value: 33, revision: fixture.document.revision + 1),
            in: fixture.document,
            context: fixture.context
        )) { XCTAssertEqual($0 as? GeometryInspectorError, .staleRevision) }
        XCTAssertThrowsError(try registry.prepare(
            fixture.inspectorCommand(field: .x, value: 33),
            in: fixture.document,
            context: fixture.context(selectedIDs: fixture.selectedIDs, availableIDs: [])
        )) { XCTAssertEqual($0 as? GeometryInspectorError, .unavailableTarget) }
        XCTAssertEqual(try DocumentSerializer.encode(fixture.document), original)

        XCTAssertEqual(GeometryInspectorNumberParser.parse("", locale: Locale(identifier: "en_US")), .failure(.invalidValue))
        XCTAssertEqual(GeometryInspectorNumberParser.parse("-", locale: Locale(identifier: "en_US")), .failure(.invalidValue))
        XCTAssertEqual(GeometryInspectorNumberParser.parse("12.", locale: Locale(identifier: "en_US")), .failure(.invalidValue))
        XCTAssertEqual(GeometryInspectorNumberParser.parse("12abc", locale: Locale(identifier: "en_US")), .failure(.invalidValue))
        XCTAssertEqual(GeometryInspectorNumberParser.parse("12,5", locale: Locale(identifier: "fr_FR")), .success(12.5))
    }

    // SF-0403-001, SF-0403-004, SF-0403-008
    func testGeometryInspectorSupportsOnlyDeclaredNodeKindsAndRedactsDiagnostics() throws {
        let registry = GeometryInspectorCommandRegistry()
        for kind in [NodeKind.frame, .text, .section, .stack, .grid] {
            var fixture = makeFixture()
            fixture.document.pages[0].nodes[1].kind = kind
            applyStructuralDefaults(for: kind, to: &fixture.document.pages[0].nodes[1])
            let prepared = try registry.prepare(
                fixture.inspectorCommand(field: .height, value: 88),
                in: fixture.document,
                context: fixture.context
            )
            XCTAssertEqual(prepared.skippedNodeIDs, [], "\(kind) must use fixed geometry when declared applicable")
        }

        var unsupported = makeFixture()
        unsupported.document.pages[0].nodes[1].kind = .image
        XCTAssertThrowsError(try registry.prepare(
            unsupported.inspectorCommand(field: .x, value: 20),
            in: unsupported.document,
            context: unsupported.context
        )) { XCTAssertEqual($0 as? GeometryInspectorError, .noApplicableTargets) }

        var subset = makeFixture(selectedIDs: [])
        subset.document.pages[0].nodes[2].kind = .image
        subset.selectedIDs = [subset.nodeID, subset.secondNodeID]
        let partial = try registry.prepare(
            subset.inspectorCommand(field: .y, value: 55),
            in: subset.document,
            context: subset.context
        )
        XCTAssertEqual(partial.skippedNodeIDs, [subset.secondNodeID])
        guard case let .batch(commands) = partial.documentCommand else {
            return XCTFail("Applicable subset must still be one atomic batch")
        }
        XCTAssertEqual(commands.count, 1)

        let fixture = makeFixture()
        let command = fixture.inspectorCommand(field: .width, value: 222)
        let record = GeometryInspectorDiagnosticFactory.make(
            command: command,
            durationMilliseconds: 0.2,
            resultRevision: fixture.document.revision + 1,
            result: .success,
            failure: nil
        )
        XCTAssertEqual(record.operationType, "geometry-inspector.width")
        XCTAssertEqual(record.requirementIDs, (1...8).map { "SF-0403-00\($0)" })
        XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
        XCTAssertFalse(String(describing: record).contains("/Users/"))
    }
    // SF-0508-001...006, SF-0508-008 — canonical RGBA channels preserve
    // legacy defaults and never store a display hexadecimal string.
    func testDesignSolidFillAndOpacityResolveCommitUndoAndPersist() throws {
        var fixture = makeFixture()
        var node = fixture.document.pages[0].nodes[1]
        node.kind = .frame
        node.properties.append(NodeProperty(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted))
        fixture.document.pages[0].nodes[1] = node
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: node).0, .legacySurface)
        XCTAssertEqual(CanonicalSolidColor.parse(hexadecimal: "#20406080")?.hexadecimalRGBA, "#20406080")
        XCTAssertNil(CanonicalSolidColor.parse(hexadecimal: "#zzzzzz"))

        let color = CanonicalSolidColor(red: 0.125, green: 0.25, blue: 0.375, alpha: 0.5)
        let keys = ["style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"]
        let values = [color.red, color.green, color.blue, color.alpha]
        let commands = zip(keys, values).map { key, value in
            DocumentCommand.setProperty(SetPropertyCommand(pageID: fixture.pageID, nodeID: fixture.nodeID, property: NodeProperty(key: .init(rawValue: key), value: .number(value), origin: .authored)))
        } + [.setProperty(SetPropertyCommand(pageID: fixture.pageID, nodeID: fixture.nodeID, property: NodeProperty(key: .init(rawValue: "style.opacity"), value: .number(0.4), origin: .authored)))]
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(.batch(commands))
        let committed = session.document.pages[0].nodes[1]
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: committed).0, color)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedOpacity(for: committed)?.0, 0.4)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: session.document.pages[0].nodes[1]).0, .legacySurface)
        try session.redo()
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: session.document.pages[0].nodes[1]).0, color)
    }

    // SF-0402-001, SF-0508-004 — a selection replacement clears feedback
    // from a prior mixed Design transaction instead of exposing it for the
    // new, potentially inapplicable target.
    func testDesignInspectorSelectionContextAnnouncementIsSelectionScoped() {
        XCTAssertEqual(
            DesignInspectorSelectionPresentation.contextAnnouncement(selectionCount: 2),
            "Design Inspector updated for current selection."
        )
        XCTAssertEqual(
            DesignInspectorSelectionPresentation.contextAnnouncement(selectionCount: 1),
            "Design Inspector updated for current selection."
        )
        XCTAssertEqual(
            DesignInspectorSelectionPresentation.contextAnnouncement(selectionCount: 0),
            "Design Inspector requires a selection."
        )
    }

    // SF-0508-001...008 — registry is the single pre-mutation gate.
    func testDesignInspectorRegistryAdversarialIdentitySubsetAndHistoryMatrix() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.document.pages[0].nodes[1].properties.append(
            NodeProperty(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted)
        )
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let registry = DesignInspectorCommandRegistry()
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: " #20406080 "))
        XCTAssertEqual(color.hexadecimalRGBA, "#20406080")
        XCTAssertEqual(CanonicalSolidColor.parse(hexadecimal: "20406080"), color)
        XCTAssertEqual(CanonicalSolidColor.parse(hexadecimal: "#204060")?.alpha, 1)
        for source in ["#20406", "#204060800", "#20GG60", "#"] { XCTAssertNil(CanonicalSolidColor.parse(hexadecimal: source)) }
        func command(_ edit: DesignInspectorEdit, identity: DesignInspectorOperationIdentity? = nil, ids: [NodeID]? = nil, cancelled: Bool = false) -> DesignInspectorCommand {
            .init(identity: identity ?? .init(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: ids ?? fixture.selectedIDs, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let prepared = try registry.prepare(command(.fill(color)), in: fixture.document, context: fixture.context)
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID]); XCTAssertEqual(prepared.skippedNodeIDs, [fixture.secondNodeID])
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        let opacity = try registry.prepare(command(.opacity(0.4), identity: .init(documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), ids: [fixture.nodeID]), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
        _ = try session.execute(opacity.documentCommand)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 2)
        try session.undo(); XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty("style.opacity")); try session.redo()
        for value in [0.0, 1.0, 0.4] { XCTAssertNoThrow(try registry.prepare(command(.opacity(value)), in: fixture.document, context: fixture.context)) }
        for value in [Double.nan, Double.infinity, -0.01, 1.01] { XCTAssertThrowsError(try registry.prepare(command(.opacity(value)), in: fixture.document, context: fixture.context)) }
        let stale = DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration)
        XCTAssertThrowsError(try registry.prepare(command(.fill(color), identity: stale), in: fixture.document, context: fixture.context))
        XCTAssertThrowsError(try registry.prepare(command(.fill(color), ids: [fixture.nodeID, fixture.nodeID]), in: fixture.document, context: fixture.context))
        XCTAssertThrowsError(try registry.prepare(command(.fill(color), cancelled: true), in: fixture.document, context: fixture.context))
    }

    // SF-0508-001...006, SF-0508-008 — each view entry path uses exactly the
    // same strict normalizer and one registry-owned transaction boundary.
    func testDesignInspectorRegistryNormalizesValuesAndKeepsNoOpsNeutral() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .frame
        let registry = DesignInspectorCommandRegistry()
        let lowercase = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: " #20406080 "))
        let picker = CanonicalSolidColor(red: 32 / 255, green: 64 / 255, blue: 96 / 255, alpha: 128 / 255)
        XCTAssertEqual(lowercase, picker)
        XCTAssertEqual(lowercase.hexadecimalRGBA, "#20406080")
        for invalid in ["", "#2040608", "#204060800", "#20406G", "#20406080 \\n"] {
            XCTAssertNil(CanonicalSolidColor.parse(hexadecimal: invalid))
        }
        let command = DesignInspectorCommand(
            identity: .init(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .fill(lowercase), provenance: .hexadecimal, cancelled: false
        )
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(registry.prepare(command, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])).documentCommand)
        let authored = try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID }))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: authored).0, picker)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: authored).1, .authored)
        let authoredIDs = authored.properties
            .filter { $0.key.rawValue.hasPrefix("\(CanonicalFillLayerCodec.namespaceRoot).") }
            .map(\.id)
        XCTAssertFalse(authoredIDs.isEmpty)
        for legacyKey in ["style.fill", "style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"] {
            XCTAssertNil(authored.insertionProperty(legacyKey), "Compatibility fill commands must not write legacy key \(legacyKey).")
        }

        let noOp = DesignInspectorCommand(
            identity: .init(documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .fill(picker), provenance: .picker, cancelled: false
        )
        XCTAssertThrowsError(try registry.prepare(noOp, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? DesignInspectorError, .noChanges)
        }
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        let unchanged = try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID }))
        XCTAssertEqual(
            authoredIDs,
            unchanged.properties
                .filter { $0.key.rawValue.hasPrefix("\(CanonicalFillLayerCodec.namespaceRoot).") }
                .map(\.id)
        )

        for value in [0.0, 0.4, 1.0] {
            let opacity = DesignInspectorCommand(
                identity: .init(documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], edit: .opacity(value), provenance: .keyboard, cancelled: false
            )
            _ = try session.execute(registry.prepare(opacity, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])).documentCommand)
        }
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedOpacity(for: try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID })))?.0, 1)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 4, "Fill and each completed opacity edit retain separate exact history entries.")
        try session.undo(); try session.undo(); try session.undo()
        XCTAssertNil(try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID })).insertionProperty("style.opacity"))
        try session.redo(); try session.redo(); try session.redo()
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedOpacity(for: try XCTUnwrap(session.document.pages[0].nodes.first(where: { $0.id == fixture.nodeID })))?.0, 1)
        _ = try session.execute(registry.prepare(
            .init(identity: .init(documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: [fixture.nodeID], edit: .opacity(0.25), provenance: .automation, cancelled: false),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        ).documentCommand)
        XCTAssertTrue(session.historySnapshot().redoEntries.isEmpty, "A later opacity commit invalidates only its redo branch.")
    }

    // SF-0508-002...006 — stale and invalid inputs must be entirely neutral;
    // mixed valid selection edits name unsupported skips instead of coercing.
    func testDesignInspectorRegistryRejectsAllBoundariesAndReportsMixedApplicableSubset() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.document.pages[0].nodes[1].properties.append(
            NodeProperty(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted)
        )
        let registry = DesignInspectorCommandRegistry()
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#10203040"))
        func command(
            identity: DesignInspectorOperationIdentity? = nil,
            ids: [NodeID] = [fixture.nodeID, fixture.secondNodeID],
            edit: DesignInspectorEdit = .fill(color),
            cancelled: Bool = false
        ) -> DesignInspectorCommand {
            .init(identity: identity ?? .init(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let before = fixture.document
        let mixed = try registry.prepare(command(), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID]))
        XCTAssertEqual(mixed.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(mixed.skippedNodeIDs, [fixture.secondNodeID])
        XCTAssertEqual(mixed.skippedReasons[fixture.secondNodeID], "This object kind does not support background fill layers.")
        XCTAssertEqual(DesignInspectorCommandRegistry.fillValue(nodes: [fixture.document.pages[0].nodes[1], fixture.document.pages[0].nodes[2]]), .mixed)

        let staleIdentities = [
            DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: PageID(), revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision + 1, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration + 1),
        ]
        for identity in staleIdentities {
            XCTAssertThrowsError(try registry.prepare(command(identity: identity), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID]))) { XCTAssertEqual($0 as? DesignInspectorError, .stale) }
        }
        let invalidOpacityEdits: [DesignInspectorEdit] = [.opacity(.nan), .opacity(.infinity), .opacity(-0.01), .opacity(1.01)]
        for edit in invalidOpacityEdits {
            XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID], edit: edit), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        }
        XCTAssertThrowsError(try registry.prepare(command(ids: [], edit: .fill(color)), in: fixture.document, context: fixture.context(selectedIDs: [])))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID, fixture.nodeID]), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(ids: [NodeID()], edit: .fill(color)), in: fixture.document, context: fixture.context(selectedIDs: [NodeID()])))
        XCTAssertThrowsError(try registry.prepare(command(cancelled: true), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])))

        var locked = fixture.document
        locked.pages[0].nodes[1].properties.append(booleanProperty("locked", true))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID]), in: locked, context: fixture.context(selectedIDs: [fixture.nodeID])))
        var hidden = fixture.document
        hidden.pages[0].nodes[1].properties.append(booleanProperty("hidden", true))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID]), in: hidden, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID]), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID], availableIDs: [])))
        fixture.document.pages[0].nodes[1].kind = .image
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID]), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) { XCTAssertEqual($0 as? DesignInspectorError, .noApplicableTargets) }
        XCTAssertEqual(before.revision, 0)
    }
    func testCanonicalFillLayerFoundationValidatesStableOrderAndGradientDefaults() {
        let start = CanonicalGradientStop(id: GradientStopID(UUID(uuidString: "A0000000-0000-4000-8000-000000000001")!), position: 0, color: .legacySurface)
        let end = CanonicalGradientStop(id: GradientStopID(UUID(uuidString: "A0000000-0000-4000-8000-000000000002")!), position: 1, color: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4))
        let layerID = FillLayerID(UUID(uuidString: "A0000000-0000-4000-8000-000000000003")!)
        let gradient = CanonicalFillLayer.linearGradient(id: layerID, angleDegrees: -180, stops: [start, end])
        XCTAssertTrue(gradient.isValid)
        XCTAssertEqual(gradient.normalizedAngleDegrees, 180)
        XCTAssertTrue(CanonicalFillLayer.solid(color: .legacySurface).isValid)
        XCTAssertTrue(CanonicalFillLayer.linearGradient(stops: [end, start]).isValid, "Stable stop order is distinct from interpolation position.")
        XCTAssertFalse(CanonicalFillLayer.linearGradient(stops: [start, start]).isValid)
        let replacement = CanonicalSolidColor(red: 0.1, green: 0.3, blue: 0.5, alpha: 0.7)
        let migrated = try? [CanonicalFillLayer.solid(color: .legacySurface)].applying(.replaceSolid(replacement))
        XCTAssertEqual(migrated?.count, 1)
        XCTAssertEqual(migrated?.first?.solidColor, replacement)
        XCTAssertEqual(try? migrated?.applying(.replaceSolid(nil)), [])
    }

    // SF-0301-004...006, SF-0303-005, SF-0508-001...008 — namespace
    // absence is legacy-compatible and distinct from an explicitly authored
    // empty layer order. Complete generated stacks decode exactly.
    func testCanonicalFillLayerStrictDecoderDistinguishesAbsentEmptyLegacyAndValidStacks() throws {
        var node = makeGeometryNode(id: NodeID(), parent: NodeID(), x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: node), .absent)

        node.properties.append(NodeProperty(
            key: .init(rawValue: CanonicalFillLayerCodec.orderKey),
            value: .string("")
        ))
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: node), .layers([]))

        var legacy = makeGeometryNode(id: NodeID(), parent: NodeID(), x: 0, y: 0, width: 100, height: 100)
        legacy.properties.append(NodeProperty(
            key: .init(rawValue: "style.fill"),
            value: .string("surface"),
            origin: .defaulted
        ))
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: legacy), .absent)
        XCTAssertEqual(CanonicalFillLayerCodec.legacySolidLayer(for: legacy)?.solidColor, .legacySurface)

        let layer = CanonicalFillLayer.solid(
            id: FillLayerID(UUID(uuidString: "A0600000-0000-4000-8000-000000000001")!),
            color: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4)
        )
        node.properties.removeAll { $0.key.rawValue.hasPrefix("\(CanonicalFillLayerCodec.namespaceRoot).") }
        node.properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: [layer]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value)
        })
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: node), .layers([layer]))

        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: [layer]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value)
        })
        XCTAssertNoThrow(try fixture.document.validate())
    }

    // SF-0301-004...006, SF-0303-005, SF-0508-001...008 — every owned
    // namespace field must be reachable, complete, typed, canonical, and
    // valid. Corruption may not collapse into the same state as authored
    // "no fill" or be adopted by the canonical document.
    func testCanonicalFillLayerStrictDecoderRejectsMalformedNamespaceMatrix() throws {
        let fixture = makeFixture()
        let layerID = FillLayerID(UUID(uuidString: "A0610000-0000-4000-8000-000000000001")!)
        let startID = GradientStopID(UUID(uuidString: "A0610000-0000-4000-8000-000000000002")!)
        let endID = GradientStopID(UUID(uuidString: "A0610000-0000-4000-8000-000000000003")!)
        let gradient = CanonicalFillLayer.linearGradient(
            id: layerID,
            angleDegrees: 45,
            stops: [
                .init(id: startID, position: 0, color: .legacySurface),
                .init(id: endID, position: 1, color: .init(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)),
            ]
        )
        var valid = fixture.document.pages[0].nodes[1]
        valid.properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: [gradient]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value)
        })
        XCTAssertEqual(try CanonicalFillLayerCodec.decodeLayers(for: valid), .layers([gradient]))

        let layerPrefix = "\(CanonicalFillLayerCodec.namespaceRoot).\(layerID.description)"
        let startPrefix = "\(layerPrefix).stop.\(startID.description)"
        func replacing(_ key: String, with value: PropertyValue?, in input: DocumentNode) -> DocumentNode {
            var node = input
            node.properties.removeAll { $0.key.rawValue == key }
            if let value {
                node.properties.append(NodeProperty(key: .init(rawValue: key), value: value))
            }
            return node
        }
        func assertMalformed(
            _ label: String,
            _ candidate: DocumentNode,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            XCTAssertThrowsError(
                try CanonicalFillLayerCodec.decodeLayers(for: candidate),
                label,
                file: file,
                line: line
            )
            var document = fixture.document
            document.pages[0].nodes[1] = candidate
            XCTAssertThrowsError(try document.validate(), label, file: file, line: line) { error in
                XCTAssertEqual(error as? ModelValidationError, .invalidFillLayerState, file: file, line: line)
            }
        }

        assertMalformed("namespace properties without order", replacing(CanonicalFillLayerCodec.orderKey, with: nil, in: valid))
        assertMalformed("wrong order type", replacing(CanonicalFillLayerCodec.orderKey, with: .boolean(true), in: valid))
        assertMalformed("trailing empty layer token", replacing(CanonicalFillLayerCodec.orderKey, with: .string("\(layerID.description),"), in: valid))
        assertMalformed("duplicate layer identity", replacing(CanonicalFillLayerCodec.orderKey, with: .string("\(layerID.description),\(layerID.description)"), in: valid))
        assertMalformed("unknown layer kind", replacing("\(layerPrefix).kind", with: .string("radialGradient"), in: valid))
        assertMalformed("missing enabled field", replacing("\(layerPrefix).enabled", with: nil, in: valid))
        assertMalformed("noncanonical angle", replacing("\(layerPrefix).angle", with: .number(360), in: valid))
        assertMalformed("trailing empty stop token", replacing("\(layerPrefix).stops", with: .string("\(startID.description),\(endID.description),"), in: valid))
        assertMalformed("duplicate stop identity", replacing("\(layerPrefix).stops", with: .string("\(startID.description),\(startID.description)"), in: valid))
        assertMalformed("insufficient gradient stops", replacing("\(layerPrefix).stops", with: .string(startID.description), in: valid))
        assertMalformed("missing stop field", replacing("\(startPrefix).position", with: nil, in: valid))
        assertMalformed("invalid stop position", replacing("\(startPrefix).position", with: .number(1.1), in: valid))
        assertMalformed("invalid stop color", replacing("\(startPrefix).alpha", with: .number(-0.1), in: valid))
        assertMalformed("orphaned namespace property", replacing("\(layerPrefix).unused", with: .number(1), in: valid))

        var unsupported = valid
        unsupported.kind = .text
        assertMalformed("unsupported node kind", unsupported)

        let solid = CanonicalFillLayer.solid(id: layerID, color: .legacySurface)
        var invalidSolid = fixture.document.pages[0].nodes[1]
        invalidSolid.properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: [solid]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value)
        })
        invalidSolid = replacing("\(layerPrefix).red", with: .number(1.1), in: invalidSolid)
        assertMalformed("invalid solid color", invalidSolid)
    }

    // SF-0508-002, SF-0508-004, SF-0508-006 — ordered rows are shared across
    // a multiple selection only when every applicable object owns the exact
    // same stable layer/stop identities and values. Differing stacks remain a
    // truthful non-editable mixed state; unsupported objects are counted and
    // left unchanged by the same registry command.
    func testFillLayerMultipleSelectionDistinguishesSharedMixedAndSkippedStacks() throws {
        var fixture = makeFixture(selectedIDs: [])
        let selected = [fixture.nodeID, fixture.secondNodeID]
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .frame
        let layerID = FillLayerID(UUID(uuidString: "A0500000-0000-4000-8000-000000000001")!)
        let sharedLayers = [CanonicalFillLayer.solid(
            id: layerID,
            color: .init(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        )]
        func install(_ layers: [CanonicalFillLayer], on node: inout DocumentNode) {
            node.properties.removeAll {
                $0.key.rawValue.hasPrefix("style.fill.layers.v1.")
                    || ["style.fill", "style.fill.red", "style.fill.green", "style.fill.blue", "style.fill.alpha"].contains($0.key.rawValue)
            }
            node.properties.append(contentsOf: CanonicalFillLayerCodec.propertyValues(for: layers)
                .sorted(by: { $0.key < $1.key })
                .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored) })
        }
        install(sharedLayers, on: &fixture.document.pages[0].nodes[1])
        install(sharedLayers, on: &fixture.document.pages[0].nodes[2])
        let frame = fixture.document.pages[0].nodes[1]
        let secondFrame = fixture.document.pages[0].nodes[2]
        XCTAssertEqual(
            DesignInspectorCommandRegistry.fillLayerSelectionValue(nodes: [frame, secondFrame]),
            .shared(layers: sharedLayers, applicableCount: 2, skippedCount: 0)
        )

        var text = secondFrame
        text.kind = .text
        XCTAssertEqual(
            DesignInspectorCommandRegistry.fillLayerSelectionValue(nodes: [frame, text]),
            .shared(layers: sharedLayers, applicableCount: 1, skippedCount: 1)
        )
        var different = secondFrame
        install([.solid(id: layerID, color: .legacySurface)], on: &different)
        XCTAssertEqual(
            DesignInspectorCommandRegistry.fillLayerSelectionValue(nodes: [frame, different]),
            .mixed(applicableCount: 2, skippedCount: 0)
        )

        let registry = DesignInspectorCommandRegistry()
        let prepared = try registry.prepare(
            .init(
                identity: .init(
                    documentID: fixture.document.id,
                    pageID: fixture.pageID,
                    revision: fixture.document.revision,
                    sceneID: fixture.sceneID,
                    rendererGeneration: fixture.rendererGeneration
                ),
                orderedNodeIDs: selected,
                edit: .setEnabled(layerID, false),
                provenance: .accessibility,
                cancelled: false
            ),
            in: fixture.document,
            context: fixture.context(selectedIDs: selected)
        )
        XCTAssertEqual(prepared.applicableNodeIDs, selected)
        XCTAssertTrue(prepared.skippedNodeIDs.isEmpty)
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        let edited = session.document.pages[0].nodes.filter { selected.contains($0.id) }
        XCTAssertEqual(edited.count, 2)
        XCTAssertTrue(edited.allSatisfy {
            DesignInspectorCommandRegistry.resolvedLayers(for: $0).first?.isEnabled == false
        })
    }

    // SF-0508-001...008 — each layer reducer result is compiled by the
    // central registry into one identity-gated, invertible property batch.
    func testDesignFillLayerRegistryCommitsOrderedLayersWithExactHistoryAndPersistence() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.document.pages[0].nodes[1].properties.append(
            .init(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted)
        )
        let registry = DesignInspectorCommandRegistry()
        let solidID = FillLayerID(UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!)
        let gradientID = FillLayerID(UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!)
        let startID = GradientStopID(UUID(uuidString: "A1000000-0000-4000-8000-000000000003")!)
        let endID = GradientStopID(UUID(uuidString: "A1000000-0000-4000-8000-000000000004")!)
        let middleID = GradientStopID(UUID(uuidString: "A1000000-0000-4000-8000-000000000005")!)
        let red = CanonicalSolidColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = CanonicalSolidColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        let stops = [
            CanonicalGradientStop(id: startID, position: 0, color: red),
            CanonicalGradientStop(id: endID, position: 1, color: blue),
        ]
        func command(
            _ document: CanonicalDocument,
            ids: [NodeID],
            _ edit: DesignFillLayerEdit,
            cancelled: Bool = false,
            identity: DesignInspectorOperationIdentity? = nil
        ) -> DesignFillLayerCommand {
            .init(
                identity: identity ?? .init(documentID: document.id, pageID: fixture.pageID, revision: document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids,
                edit: edit,
                provenance: .automation,
                cancelled: cancelled
            )
        }
        func context(_ ids: [NodeID]) -> TransformValidationContext {
            fixture.context(selectedIDs: ids)
        }

        let addSolid = try registry.prepare(
            command(fixture.document, ids: [fixture.nodeID, fixture.secondNodeID], .addSolid(id: solidID, color: red)),
            in: fixture.document,
            context: context([fixture.nodeID, fixture.secondNodeID])
        )
        XCTAssertEqual(addSolid.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(addSolid.skippedNodeIDs, [fixture.secondNodeID])
        XCTAssertEqual(addSolid.skippedReasons[fixture.secondNodeID], "This object kind does not support background fill layers.")
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(addSolid.documentCommand)
        func currentFrame(in document: CanonicalDocument) throws -> DocumentNode {
            try XCTUnwrap(document.pages[0].nodes.first(where: { $0.id == fixture.nodeID }))
        }
        var frame = try currentFrame(in: session.document)
        let legacyLayerID = try XCTUnwrap(DesignInspectorCommandRegistry.resolvedLayers(for: frame).first?.id)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: frame), [
            .solid(id: legacyLayerID, color: .legacySurface),
            .solid(id: solidID, color: red),
        ])
        XCTAssertNil(frame.insertionProperty("style.fill"), "Legacy fallback is consumed and removed atomically on the first v1 write.")
        XCTAssertNotNil(frame.insertionProperty(CanonicalFillLayerCodec.orderKey))
        let solidPropertyIDs = frame.properties.filter { $0.key.rawValue.contains(solidID.description) }.map { $0.id }

        let replacement = CanonicalSolidColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let replaceSolid = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .setSolidColor(solidID, replacement)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(replaceSolid.documentCommand)

        let addGradient = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .addLinearGradient(id: gradientID, angleDegrees: 90, stops: stops)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(addGradient.documentCommand)
        let reorder = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .reorder(gradientID, to: 0)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(reorder.documentCommand)
        let addStop = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .addStop(gradientID, .init(id: middleID, position: 0.5, color: .legacySurface), at: 1)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(addStop.documentCommand)
        let changeAngle = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .setGradientAngle(gradientID, 495)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(changeAngle.documentCommand)
        let editStop = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .setStop(gradientID, middleID, position: 0.75, color: replacement)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(editStop.documentCommand)
        let reorderStop = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .reorderStop(gradientID, middleID, to: 2)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(reorderStop.documentCommand)
        let removeStop = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .removeStop(gradientID, middleID)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(removeStop.documentCommand)
        let disable = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .setEnabled(solidID, false)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(disable.documentCommand)

        frame = try currentFrame(in: session.document)
        let layers = DesignInspectorCommandRegistry.resolvedLayers(for: frame)
        XCTAssertEqual(layers.map { $0.id }, [gradientID, legacyLayerID, solidID])
        XCTAssertEqual(layers[0].normalizedAngleDegrees, 135)
        XCTAssertEqual(layers[0].stops.map { $0.id }, [startID, endID])
        XCTAssertEqual(layers[2].solidColor, replacement)
        XCTAssertFalse(layers[2].isEnabled)
        XCTAssertEqual(frame.properties.filter { $0.key.rawValue.hasPrefix("style.fill.layers.v1.") && $0.key.rawValue.contains(solidID.description) }.map { $0.id }.filter { solidPropertyIDs.contains($0) }.count, solidPropertyIDs.count)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        let removeGradient = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], .remove(gradientID)),
            in: session.document,
            context: context([fixture.nodeID])
        )
        _ = try session.execute(removeGradient.documentCommand)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: try currentFrame(in: session.document)).map { $0.id }, [legacyLayerID, solidID])
        let snapshot = session.document
        try session.undo()
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: try currentFrame(in: session.document)).first?.id, gradientID)
        try session.redo()
        XCTAssertEqual(try currentFrame(in: session.document).properties, try currentFrame(in: snapshot).properties, "Redo restores the complete ordered v1 layer representation exactly.")
        while session.historySnapshot().undoEntries.count > 0 { try session.undo() }
        frame = try currentFrame(in: session.document)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedFill(for: frame).0, .legacySurface)
        XCTAssertNil(frame.insertionProperty(CanonicalFillLayerCodec.orderKey))
    }

    // SF-0508-002...006 — invalid/stale/cancelled layer inputs remain fully
    // neutral and diagnostics disclose category only, never stable IDs.
    func testDesignFillLayerRegistryRejectsInvalidStaleCancelAndAllInapplicableEdits() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        let registry = DesignInspectorCommandRegistry()
        let layerID = FillLayerID(UUID(uuidString: "A2000000-0000-4000-8000-000000000001")!)
        let invalidColor = CanonicalSolidColor(red: .nan, green: 0, blue: 0, alpha: 1)
        func command(
            ids: [NodeID],
            edit: DesignFillLayerEdit,
            cancelled: Bool = false,
            identity: DesignInspectorOperationIdentity? = nil
        ) -> DesignFillLayerCommand {
            .init(
                identity: identity ?? .init(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids, edit: edit, provenance: .accessibility, cancelled: cancelled
            )
        }
        let before = fixture.document
        let base = command(ids: [fixture.nodeID], edit: .addSolid(id: layerID, color: .legacySurface))
        for identity in [
            DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: PageID(), revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision + 1, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: fixture.rendererGeneration),
            DesignInspectorOperationIdentity(documentID: fixture.document.id, pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration + 1),
        ] {
            XCTAssertThrowsError(try registry.prepare(.init(identity: identity, orderedNodeIDs: base.orderedNodeIDs, edit: base.edit, provenance: base.provenance, cancelled: false), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) { XCTAssertEqual($0 as? DesignInspectorError, .stale) }
        }
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID], edit: .addSolid(id: layerID, color: invalidColor)), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) { error in
            XCTAssertFalse(error.localizedDescription.contains(layerID.description))
        }
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID], edit: .addSolid(id: layerID, color: .legacySurface), cancelled: true), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.secondNodeID], edit: .addSolid(id: layerID, color: .legacySurface)), in: fixture.document, context: fixture.context(selectedIDs: [fixture.secondNodeID]))) { XCTAssertEqual($0 as? DesignInspectorError, .noApplicableTargets) }
        XCTAssertThrowsError(try registry.prepare(command(ids: [fixture.nodeID, fixture.nodeID], edit: .addSolid(id: layerID, color: .legacySurface)), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.nodeID])))
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0508-004/005 — Inspector numeric drafts must fail visibly instead of
    // silently disappearing on Return or focus loss, while valid values are
    // normalized before the transactional command is prepared.
    func testFillLayerNumericDraftValidationIsExplicitAndCanonical() throws {
        XCTAssertEqual(try FillLayerNumericDraftValidator.angle(" 495 ").get(), 135)
        XCTAssertEqual(try FillLayerNumericDraftValidator.angle("-180").get(), 180)
        XCTAssertEqual(FillLayerNumericDraftValidator.angle(" "), .failure(.empty))
        XCTAssertEqual(FillLayerNumericDraftValidator.angle("nan"), .failure(.notFinite))

        XCTAssertEqual(try FillLayerNumericDraftValidator.percentage("25").get(), 0.25)
        XCTAssertEqual(try FillLayerNumericDraftValidator.percentage("100").get(), 1)
        XCTAssertEqual(FillLayerNumericDraftValidator.percentage("-1"), .failure(.outsidePercentageRange))
        XCTAssertEqual(FillLayerNumericDraftValidator.percentage("101"), .failure(.outsidePercentageRange))
        XCTAssertEqual(FillLayerNumericDraftValidator.percentage("invalid"), .failure(.notFinite))
    }

    // SF-0506-001...006/008 — the bounded box appearance uses one typed,
    // identity-gated property transaction and exact CommandRegistry inverse.
    func testDesignBoxStyleRegistryCommitsValidatesMixesPersistsAndUndoRedo() throws {
        var fixture = makeFixture(selectedIDs: [NodeID]())
        fixture.document.pages[0].nodes[2].kind = .text
        let registry = DesignBoxStyleCommandRegistry()
        let border = CanonicalBorder(
            color: .init(red: 0.2, green: 0.4, blue: 0.8, alpha: 1),
            width: 3, style: .dashed
        )
        let shadow = CanonicalShadow(
            color: .init(red: 0, green: 0, blue: 0, alpha: 0.3),
            offsetX: 2, offsetY: 8, blur: 16, spread: 1
        )
        func command(_ document: CanonicalDocument, ids: [NodeID], edit: DesignBoxStyleEdit, cancelled: Bool = false) -> DesignBoxStyleCommand {
            .init(
                identity: .init(
                    documentID: document.id, pageID: fixture.pageID,
                    revision: document.revision, sceneID: fixture.sceneID,
                    rendererGeneration: fixture.rendererGeneration
                ), orderedNodeIDs: ids, edit: edit, provenance: .automation,
                cancelled: cancelled
            )
        }
        let mixed = try registry.prepare(
            command(fixture.document, ids: [fixture.nodeID, fixture.secondNodeID], edit: .border(border)),
            in: fixture.document,
            context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])
        )
        XCTAssertEqual(mixed.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(mixed.skippedNodeIDs, [fixture.secondNodeID])
        XCTAssertFalse(mixed.skippedReasons.values.joined().contains(fixture.nodeID.description))

        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(mixed.documentCommand)
        let radius = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .cornerRadius(14)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        _ = try session.execute(radius.documentCommand)
        let shadowEdit = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .shadow(shadow)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        _ = try session.execute(shadowEdit.documentCommand)

        func currentStyle() throws -> CanonicalBoxStyle {
            let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
            return try XCTUnwrap(DesignBoxStyleCommandRegistry.resolvedStyle(for: node))
        }
        XCTAssertEqual(try currentStyle(), .init(border: border, cornerRadius: 14, shadow: shadow))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let propertyIDs = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(DesignBoxStyleCommandRegistry.namespace) }.map(\.id)
        try session.undo()
        XCTAssertNil(try currentStyle().shadow)
        try session.redo()
        XCTAssertEqual(try currentStyle().shadow, shadow)
        let reopenedIDs = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(DesignBoxStyleCommandRegistry.namespace) }.map(\.id)
        XCTAssertEqual(propertyIDs, reopenedIDs)

        let invalid = CanonicalShadow(color: shadow.color, offsetX: 0, offsetY: 0, blur: -.infinity, spread: 0)
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .shadow(invalid)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        let zeroBorder = CanonicalBorder(color: border.color, width: 0, style: .solid)
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .border(zeroBorder)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .cornerRadius(8), cancelled: true),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .cancelled) }
        let stale = DesignBoxStyleCommand(
            identity: .init(documentID: DocumentID(), pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .border(nil), provenance: .automation, cancelled: false
        )
        XCTAssertThrowsError(try registry.prepare(stale, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? DesignBoxStyleError, .stale)
        }
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

    func inspectorCommand(
        field: GeometryInspectorField,
        value: Double,
        revision: UInt64? = nil
    ) -> GeometryInspectorCommand {
        GeometryInspectorCommand(
            identity: .init(
                editID: GeometryInspectorEditID(UUID(uuidString: "94000000-0000-4000-8000-000000000099")!),
                documentID: document.id,
                pageID: pageID,
                revision: revision ?? document.revision,
                sceneID: sceneID,
                rendererGeneration: rendererGeneration
            ),
            orderedNodeIDs: selectedIDs,
            field: field,
            value: value,
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

private func applyStructuralDefaults(for kind: NodeKind, to node: inout DocumentNode) {
    let values: [(String, PropertyValue)]
    switch kind {
    case .section:
        values = [("layout.container.kind", .string("section")), ("layout.padding", .number(48)), ("layout.axis", .string("vertical"))]
    case .stack:
        values = [("layout.container.kind", .string("stack")), ("layout.axis", .string("vertical")), ("layout.padding", .number(24)), ("layout.gap", .number(24)), ("layout.align", .string("start"))]
    case .grid:
        values = [("layout.container.kind", .string("grid")), ("layout.padding", .number(24)), ("layout.gap", .number(24)), ("layout.grid.columns", .number(2)), ("layout.grid.placement", .string("row-major"))]
    case .frame, .text, .image, .component:
        values = []
    }
    node.properties.append(contentsOf: values.map { key, value in
        NodeProperty(key: PropertyKey(rawValue: key), value: value, origin: .defaulted)
    })
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
