import XCTest
@testable import SiteForge

final class SelectionModelTests: XCTestCase {
    // SF-0402-001 through SF-0402-004, SF-0402-006
    func testOrderedSelectionPrimaryAnchorAndAllInputPaths() throws {
        let fixture = try makeFixture(count: 3)
        let registry = SelectionCommandRegistry()
        for provenance in SelectionProvenance.inputCases {
            var state = try established(fixture.scene)
            try apply(.replace, fixture.ids[1], provenance, fixture, &state, registry)
            try apply(.add, fixture.ids[0], provenance, fixture, &state, registry)
            XCTAssertEqual(state.orderedIDs, [fixture.ids[1], fixture.ids[0]])
            XCTAssertEqual(state.primaryID, fixture.ids[0])
            XCTAssertEqual(state.anchorID, fixture.ids[1])
            XCTAssertEqual(state.provenance, provenance)
            try apply(.toggle, fixture.ids[1], provenance, fixture, &state, registry)
            XCTAssertEqual(state.orderedIDs, [fixture.ids[0]])
            try apply(.clear, nil, provenance, fixture, &state, registry)
            XCTAssertTrue(state.isEmpty)
        }

        var scopedState = try established(fixture.scene)
        scopedState.setContainer(fixture.ids[2])
        let scopedScene = SelectionSceneSnapshot(
            identity: fixture.identity, activePageID: fixture.pageID,
            activeContainerID: fixture.ids[2], targets: fixture.targets
        )
        try registry.apply(
            .init(.escape, expectedIdentity: fixture.identity, provenance: .keyboard),
            to: &scopedState, scene: scopedScene
        )
        XCTAssertNil(scopedState.activeContainerID)
    }

    // SF-0402-002 through SF-0402-004
    func testInvalidTargetsAndDuplicateSceneAreRejectedStateNeutrally() throws {
        var fixture = try makeFixture(count: 6)
        fixture.targets[1] = fixture.targets[1].copy(isVisible: false)
        fixture.targets[2] = fixture.targets[2].copy(clipRect: .init(origin: .init(x: 500, y: 500), size: .init(width: 10, height: 10)))
        fixture.targets[3] = fixture.targets[3].copy(isAvailable: false)
        fixture.targets[4] = fixture.targets[4].copy(pageID: PageID())
        fixture = fixture.rebuilt()
        var state = try established(fixture.scene)
        let original = state
        for id in fixture.ids[1...4] {
            XCTAssertThrowsError(try apply(.replace, id, .pointer, fixture, &state))
            XCTAssertEqual(state, original)
        }
        XCTAssertThrowsError(try apply(.replace, NodeID(), .pointer, fixture, &state))
        let duplicate = SelectionSceneSnapshot(
            identity: fixture.identity, activePageID: fixture.pageID, activeContainerID: nil,
            targets: fixture.targets + [fixture.targets[0]]
        )
        XCTAssertThrowsError(try SelectionCommandRegistry().adopt(duplicate, boundary: .rendererGeneration, state: &state))
        XCTAssertEqual(state, original)
    }

    // SF-0402-002, SF-0402-003, SF-0402-006
    func testReversePaintPointerHitTestingEmptyClearAndKeyboardTraversal() throws {
        let fixture = try makeFixture(count: 3, overlapping: true)
        let plan = try renderPlan(fixture)
        let eligible = Set(fixture.scene.orderedSelectableTargets.map(\.id))
        XCTAssertEqual(CanvasRendererCore().hitTest(.init(x: 55, y: 55), in: plan, eligibleIDs: eligible), fixture.ids[2])
        XCTAssertNil(CanvasRendererCore().hitTest(.init(x: 900, y: 600), in: plan, eligibleIDs: eligible))

        var state = try established(fixture.scene)
        try apply(.next, nil, .keyboard, fixture, &state)
        XCTAssertEqual(state.primaryID, fixture.ids[0])
        try apply(.previous, nil, .menu, fixture, &state)
        XCTAssertEqual(state.primaryID, fixture.ids[2])
        try apply(.clear, nil, .pointer, fixture, &state)
        XCTAssertTrue(state.isEmpty)
    }

    // SF-0402-003 through SF-0402-005
    func testLifecycleRetainsValidIdentityAndRepairsRemovalPageAndDocumentBoundaries() throws {
        var fixture = try makeFixture(count: 3)
        var state = try established(fixture.scene)
        try apply(.replace, fixture.ids[0], .keyboard, fixture, &state)
        let registry = SelectionCommandRegistry()
        for boundary in [SelectionLifecycleBoundary.save, .reopen, .autosave, .recovery, .undo, .redo, .rendererGeneration] {
            XCTAssertEqual(try registry.adopt(fixture.scene, boundary: boundary, state: &state), .none)
            XCTAssertEqual(state.primaryID, fixture.ids[0])
        }
        fixture.targets.removeFirst()
        fixture = fixture.rebuilt(generationDelta: 1)
        XCTAssertEqual(try registry.adopt(fixture.scene, boundary: .undo, state: &state), .removed)
        XCTAssertTrue(state.isEmpty)

        let otherPage = SelectionSceneSnapshot(identity: fixture.identity, activePageID: PageID(), activeContainerID: nil, targets: fixture.targets)
        XCTAssertEqual(try registry.adopt(otherPage, boundary: .pageSwitch, state: &state), .pageChanged)
        let otherDocument = SelectionSceneSnapshot(
            identity: fixture.identity.copy(documentID: DocumentID()), activePageID: otherPage.activePageID,
            activeContainerID: nil, targets: otherPage.targets
        )
        XCTAssertEqual(try registry.adopt(otherDocument, boundary: .documentAdoption, state: &state), .documentChanged)
    }

    // SF-0402-004
    func testStaleAndCancelledCommandsPreserveLastValidSelection() throws {
        let fixture = try makeFixture(count: 2)
        var state = try established(fixture.scene)
        try apply(.replace, fixture.ids[0], .pointer, fixture, &state)
        let original = state
        let stale = fixture.identity.copy(sceneGeneration: fixture.identity.sceneGeneration + 1)
        XCTAssertThrowsError(try SelectionCommandRegistry().apply(
            .init(.replace, targetID: fixture.ids[1], expectedIdentity: stale, provenance: .pointer),
            to: &state, scene: fixture.scene
        ))
        XCTAssertThrowsError(try SelectionCommandRegistry().apply(
            .init(.replace, targetID: fixture.ids[1], expectedIdentity: fixture.identity, provenance: .pointer),
            to: &state, scene: fixture.scene, cancellation: .init(isCancelled: { true })
        ))
        XCTAssertEqual(state, original)
    }

    // SF-0402-001, SF-0402-005
    @MainActor
    func testSelectionIsUndoNeutralAndExcludedFromCanonicalSerializationHistoryPreviewAndExportBoundary() throws {
        let document = ProjectCreation.blank()
        let session = DocumentSession(document: document)
        let canonicalBefore = try DocumentSerializer.encode(session.document)
        let fixture = try makeFixture(count: 2, documentID: document.id)
        let previewBefore = CanvasRendererCore().previewSnapshot(from: fixture.renderScene)
        var state = try established(fixture.scene)
        try apply(.replace, fixture.ids[0], .layersNavigator, fixture, &state)

        XCTAssertEqual(try DocumentSerializer.encode(session.document), canonicalBefore)
        XCTAssertFalse(session.canUndo)
        XCTAssertEqual(CanvasRendererCore().previewSnapshot(from: fixture.renderScene), previewBefore)
        XCTAssertFalse(String(decoding: canonicalBefore, as: UTF8.self).contains("selection-primary"))
    }

    // SF-0402-003, SF-0402-005, SF-0402-007
    func testOverlayPlanningIsSeparateAndInvalidatesOnlyOldAndNewRegionsAtScale() throws {
        for count in [100, 10_000] {
            let fixture = try makeFixture(count: count)
            let plan = try renderPlan(fixture)
            var state = try established(fixture.scene)
            try apply(.replace, fixture.ids[count - 1], .pointer, fixture, &state)
            let first = try SelectionOverlayPlanner().plan(selection: state, scene: fixture.scene, renderPlan: plan)
            try apply(.next, nil, .keyboard, fixture, &state)
            let second = try SelectionOverlayPlanner().plan(selection: state, scene: fixture.scene, renderPlan: plan, previous: first)
            XCTAssertFalse(second.authoredContentInvalidated)
            XCTAssertEqual(state.primaryID, fixture.ids[0])
            XCTAssertEqual(second.overlays.map(\.objectID), [fixture.ids[0]])
            XCTAssertEqual(second.dirtyWorldRegions, [fixture.targets[count - 1].frame, fixture.targets[0].frame])
            XCTAssertEqual(plan.deterministicDigest, try renderPlan(fixture).deterministicDigest)
            XCTAssertFalse(String(describing: CanvasRendererCore().previewSnapshot(from: fixture.renderScene)).contains("selection-primary"))
        }
    }

    // SF-0402-008
    func testDiagnosticsAreBoundedAndRedacted() throws {
        let fixture = try makeFixture(count: 2)
        var state = try established(fixture.scene)
        try apply(.replace, fixture.ids[0], .pointer, fixture, &state)
        let record = SelectionDiagnosticFactory.make(
            operation: .replace, state: state, durationMilliseconds: 0.25, result: .failure,
            repair: .removed, failure: "/Users/private/Project.siteforge authored private value " + String(repeating: "x", count: 100)
        )
        let text = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        XCTAssertEqual(record.requirementID, "SF-0402-008")
        XCTAssertTrue(record.sanitizedIdentifiers.allSatisfy { $0.count == 8 })
        XCTAssertLessThanOrEqual(record.failureCategory?.count ?? 0, 64)
        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("authored private value"))
    }

    private struct Fixture {
        var ids: [NodeID]
        var pageID: PageID
        var targets: [SelectionTargetSnapshot]
        var identity: CanvasRenderRequestIdentity
        var renderScene: CanvasRenderSceneSnapshot
        var viewport: CanvasViewportState
        var scene: SelectionSceneSnapshot { .init(identity: identity, activePageID: pageID, activeContainerID: nil, targets: targets) }
        func rebuilt(generationDelta: UInt64 = 0) -> Self {
            let next = identity.copy(sceneGeneration: identity.sceneGeneration + generationDelta)
            let objects = targets.map { CanvasRenderObject(id: $0.id, frame: $0.frame, clipRect: $0.clipRect, paintOrder: $0.paintOrder, style: .container, isVisible: $0.isVisible, accessibilityLabel: $0.name) }
            return .init(ids: ids, pageID: pageID, targets: targets, identity: next,
                renderScene: .init(identity: next, surfaceID: renderScene.surfaceID, objects: objects), viewport: viewport)
        }
    }

    private func makeFixture(count: Int, overlapping: Bool = false, documentID: DocumentID = DocumentID(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)) throws -> Fixture {
        let pageID = PageID(UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let identity = CanvasRenderRequestIdentity(documentID: documentID, revision: 3,
            sceneID: CanvasViewportSceneID(UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
            sceneGeneration: 5, viewportGeneration: 7, scale: try CanvasPixelRatio(2))
        let ids = (0..<count).map { NodeID(UUID(uuidString: "44444444-4444-4444-8444-\(String(format: "%012x", $0 + 1))")!) }
        let targets = ids.enumerated().map { index, id in
            SelectionTargetSnapshot(id: id, pageID: pageID, parentID: nil, name: "Object \(index + 1)",
                frame: .init(origin: overlapping ? .init(x: 50, y: 50) : .init(x: Double(index % 100) * 12, y: Double(index / 100) * 12), size: .init(width: 10, height: 10)),
                clipRect: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 1_400)),
                paintOrder: index, isVisible: true, isLocked: index == 1, isAvailable: true)
        }
        let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 1_000, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 1_400)), pixelRatio: .init(2))
        let objects = targets.map { CanvasRenderObject(id: $0.id, frame: $0.frame, clipRect: $0.clipRect, paintOrder: $0.paintOrder, style: .container, isVisible: $0.isVisible, accessibilityLabel: $0.name) }
        return .init(ids: ids, pageID: pageID, targets: targets, identity: identity,
            renderScene: .init(identity: identity, surfaceID: CanvasRenderSurfaceID(UUID(uuidString: "55555555-5555-5555-5555-555555555555")!), objects: objects), viewport: viewport)
    }

    private func established(_ scene: SelectionSceneSnapshot) throws -> SelectionState {
        var state = SelectionState()
        _ = try SelectionCommandRegistry().adopt(scene, boundary: .documentAdoption, state: &state)
        return state
    }

    private func apply(_ name: SelectionCommandName, _ id: NodeID?, _ provenance: SelectionProvenance, _ fixture: Fixture, _ state: inout SelectionState, _ registry: SelectionCommandRegistry = .init()) throws {
        try registry.apply(.init(name, targetID: id, expectedIdentity: fixture.identity, provenance: provenance), to: &state, scene: fixture.scene)
    }

    private func renderPlan(_ fixture: Fixture) throws -> CanvasRenderPlan {
        try CanvasRendererCore().prepare(scene: fixture.renderScene, overlays: .init(identity: fixture.identity, overlays: []), viewport: fixture.viewport)
    }
}

private extension SelectionTargetSnapshot {
    func copy(pageID: PageID? = nil, clipRect: WorldRect? = nil, isVisible: Bool? = nil, isAvailable: Bool? = nil) -> Self {
        .init(id: id, pageID: pageID ?? self.pageID, parentID: parentID, name: name, frame: frame,
            clipRect: clipRect ?? self.clipRect, paintOrder: paintOrder, isVisible: isVisible ?? self.isVisible,
            isLocked: isLocked, isAvailable: isAvailable ?? self.isAvailable)
    }
}

private extension SelectionProvenance {
    static let inputCases: [Self] = [.pointer, .keyboard, .menu, .contextualMenu, .layersNavigator, .accessibility]
}

private extension CanvasRenderRequestIdentity {
    func copy(documentID: DocumentID? = nil, sceneGeneration: UInt64? = nil) -> Self {
        .init(documentID: documentID ?? self.documentID, revision: revision, sceneID: sceneID,
            sceneGeneration: sceneGeneration ?? self.sceneGeneration, viewportGeneration: viewportGeneration, scale: scale)
    }
}
