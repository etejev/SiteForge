import Darwin
import Combine
import XCTest
@testable import SiteForge

@MainActor
final class TransformModelTests: XCTestCase {
    // SF-0508-002/003, SF-0701-003 — selection routing must not guess a Root.
    func testPageBackgroundPolicyRequiresSingleStructuralWebsiteRoot() throws {
        var document = ProjectCreation.blank()
        var page = try XCTUnwrap(document.pages.first)
        let root = try XCTUnwrap(PageBackgroundPolicy.root(in: page))
        XCTAssertNil(root.insertionGeometry)
        XCTAssertNil(PageBackgroundPolicy.unavailableReason(in: page))
        let before = document
        XCTAssertNil(PageBackgroundPolicy.root(in: nil))
        page.rootNodeIDs.append(NodeID())
        XCTAssertNil(PageBackgroundPolicy.root(in: page), "Multiple roots must not pick an arbitrary background owner")
        page = before.pages[0]
        for (key, value) in [("layout.x", 0.0), ("layout.y", 0.0), ("layout.width", 100.0), ("layout.height", 100.0)] {
            page.nodes[0].properties.append(.init(key: .init(rawValue: key), value: .number(value)))
        }
        XCTAssertNil(PageBackgroundPolicy.root(in: page), "An authored geometric Frame is not silently promoted to page background ownership")
        page = before.pages[0]
        page.nodes[0].properties.append(.init(key: .init(rawValue: "hidden"), value: .boolean(true)))
        XCTAssertNotNil(PageBackgroundPolicy.unavailableReason(in: page))
        XCTAssertEqual(PageBackgroundPolicy.root(in: page)?.id, root.id, "Hidden intent is retained, not replaced")
        document = before
        XCTAssertEqual(document, before, "Discoverability is a read-only projection")
    }

    // SF-0508-002/005 — None clears gradient/solid/token state in one existing
    // property transaction; exact inverse restores IDs, origins and bindings.
    func testPageBackgroundTransparentNonePreservesTokenHistoryAndPersistence() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        let color = CanonicalSolidColor(red: 0.2, green: 0.1, blue: 0.4, alpha: 1)
        let token = LocalColorToken(name: "Page Ink", color: color)
        document.colorTokens = [token]
        let layer = CanonicalFillLayer.solid(color: color)
        document.pages[0].nodes[0].properties += CanonicalFillLayerCodec.propertyValues(for: [layer]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored)
        }
        document.pages[0].nodes[0].properties.append(.init(
            key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
            value: .string(token.id.description), origin: .authored))
        let original = document.pages[0].nodes[0]
        let scene = CanvasViewportSceneID()
        func context(_ value: CanonicalDocument) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: scene, rendererGeneration: value.revision,
                  selectedNodeIDs: [rootID], availableNodeIDs: [rootID],
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        func request(_ value: CanonicalDocument, cancelled: Bool = false) -> DesignFillLayerCommand {
            .init(identity: .init(documentID: value.id, pageID: pageID, revision: value.revision,
                                 sceneID: scene, rendererGeneration: value.revision),
                  orderedNodeIDs: [rootID], edit: .clearAll, provenance: .keyboard, cancelled: cancelled)
        }
        let registry = DesignInspectorCommandRegistry()
        let prepared = try registry.prepare(request(document), in: document, context: context(document))
        let session = DocumentSession(document: document)
        _ = try session.execute(prepared.documentCommand)
        let cleared = session.document.pages[0].nodes[0]
        XCTAssertEqual(cleared.id, original.id)
        XCTAssertEqual(CanonicalFillLayerCodec.layers(for: cleared), [])
        XCTAssertNil(LocalColorTokenBinding.id(for: cleared))
        XCTAssertEqual(session.document.colorTokens, [token], "None unbinds; it does not delete the shared token")
        XCTAssertNil(cleared.insertionGeometry)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try registry.prepare(request(session.document), in: session.document, context: context(session.document))) {
            XCTAssertEqual($0 as? DesignInspectorError, .noChanges)
        }
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes[0], original)
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes[0], cleared)
        let beforeRejected = session.document
        XCTAssertThrowsError(try registry.prepare(request(beforeRejected, cancelled: true), in: beforeRejected, context: context(beforeRejected)))
        XCTAssertThrowsError(try registry.prepare(request(document), in: beforeRejected, context: context(beforeRejected)))
        var changedPage = context(beforeRejected)
        changedPage = .init(activePageID: PageID(), currentSceneID: scene, rendererGeneration: beforeRejected.revision,
                            selectedNodeIDs: [rootID], availableNodeIDs: [rootID], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try registry.prepare(request(beforeRejected), in: beforeRejected, context: changedPage))
        let changedSelection = TransformValidationContext(activePageID: pageID, currentSceneID: scene,
            rendererGeneration: beforeRejected.revision, selectedNodeIDs: [], availableNodeIDs: [rootID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try registry.prepare(request(beforeRejected), in: beforeRejected, context: changedSelection))
        let changedScene = TransformValidationContext(activePageID: pageID, currentSceneID: CanvasViewportSceneID(),
            rendererGeneration: beforeRejected.revision, selectedNodeIDs: [rootID], availableNodeIDs: [rootID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try registry.prepare(request(beforeRejected), in: beforeRejected, context: changedScene))
        XCTAssertEqual(session.document, beforeRejected)
        var omitted = document
        omitted.pages[0].nodes[0].properties.removeAll()
        XCTAssertThrowsError(try registry.prepare(request(omitted), in: omitted, context: context(omitted))) {
            XCTAssertEqual($0 as? DesignInspectorError, .noChanges)
        }
        let styleID = ReusableStyleID()
        let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description)."
        omitted.pages[0].nodes[0].properties = [
            .init(key: .init(rawValue: prefix + "name"), value: .string("Page Style")),
            .init(key: .init(rawValue: prefix + "fill"), value: .string(color.hexadecimalRGBA)),
            .init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description))
        ]
        let inherited = omitted.pages[0].nodes[0]
        let styledSession = DocumentSession(document: omitted)
        let none = try registry.prepare(request(omitted), in: omitted, context: context(omitted))
        try styledSession.execute(none.documentCommand)
        let styledRoot = styledSession.document.pages[0].nodes[0]
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(styledRoot), [styleID])
        XCTAssertNil(try CanonicalResolvedAppearance.resolve(node: styledRoot,
            index: CanonicalReusableStyleIndex(document: styledSession.document)).fill)
        try styledSession.undo()
        XCTAssertEqual(styledSession.document.pages[0].nodes[0], inherited)
    }

    // SF-0508-003/005 — renderer/output inputs remain immutable canonical data.
    func testPageBackgroundGradientProjectsThroughSharedCompilerWithoutMutation() throws {
        var document = ProjectCreation.blank()
        let rootID = document.pages[0].rootNodeIDs[0]
        let layers = [CanonicalFillLayer.linearGradient(angleDegrees: 45, stops: [
            .init(id: GradientStopID(), position: 0, color: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
            .init(id: GradientStopID(), position: 1, color: .init(red: 0.8, green: 0.4, blue: 0.2, alpha: 1))
        ])]
        document.pages[0].nodes[0].properties += CanonicalFillLayerCodec.propertyValues(for: layers).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored)
        }
        let before = document
        let snapshot = try InternalDocumentRenderTreeCompiler.compile(page: document.pages[0], documentID: document.id, revision: document.revision)
        XCTAssertEqual(try XCTUnwrap(snapshot.nodes.first { $0.id == rootID }).fillLayers, layers)
        document.pages[0].nodes[0].properties.removeAll()
        XCTAssertEqual(try XCTUnwrap(snapshot.nodes.first { $0.id == rootID }).fillLayers, layers, "Adopted output cannot mix a later draft")
        XCTAssertEqual(PageBackgroundPolicy.root(in: before.pages[0])?.id, rootID)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(before)), before)
    }

    func testPageBackgroundEntrySelectsStructuralRootWithoutCanvasGhostOrMutation() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while state.canvasRenderPlan == nil || state.layerTargets.isEmpty {
            if ContinuousClock.now >= deadline { XCTFail("Initial scene was not adopted"); return }
            await Task.yield()
        }
        let before = session.document
        let pageID = before.pages[0].id
        let rootID = before.pages[0].rootNodeIDs[0]
        state.revealPageBackground(pageID: pageID)
        XCTAssertEqual(state.selectionState.orderedIDs, [rootID])
        XCTAssertTrue(state.isInspectingPageBackground)
        XCTAssertTrue(state.canEditDesignSolidFill, "An omitted Root fill remains editable without creating a default")
        XCTAssertEqual(state.inspectorTab, .design)
        let root = try XCTUnwrap(state.layerTargets.first { $0.id == rootID })
        XCTAssertTrue(root.isVisible)
        XCTAssertTrue(root.isStructuralRoot)
        XCTAssertFalse(root.participatesInCanvasTraversal)
        XCTAssertEqual(root.layerVisibilityDescription, "Page structure")
        state.revealPageBackground(pageID: PageID())
        XCTAssertEqual(state.selectionState.orderedIDs, [rootID], "An obsolete page action must not retarget")
        XCTAssertEqual(session.document, before)
        XCTAssertTrue(session.historySnapshot().undoEntries.isEmpty)
    }

    func testDuplicateInlineDraftNotificationsDoNotRepublishOrMutateCanonicalState() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != session.document.revision
                    || state.selectionState.sceneIdentity?.revision != session.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle(); state.performDefaultInsertion(.text, provenance: .menu); try await settle()
        XCTAssertTrue(state.beginTextEditing(nodeID: try XCTUnwrap(state.selectionState.primaryID), provenance: .menu))
        let before = session.document, history = session.historySnapshot()
        let initial = try XCTUnwrap(state.textEditingSession.draft)
        var publications = 0
        let subscription = state.objectWillChange.sink { publications += 1 }
        defer { subscription.cancel() }
        for _ in 0..<100 {
            state.updateTextEditingDraft(text: initial.text, selection: initial.selection, markedRange: initial.markedRange)
        }
        XCTAssertEqual(publications, 0)
        let text = "An actual draft", range = TextEditRange(location: 15, length: 0)
        state.updateTextEditingDraft(text: text, selection: range, markedRange: nil)
        XCTAssertGreaterThan(publications, 0, "Changed native input still publishes immediately")
        publications = 0
        state.updateTextEditingDraft(text: text, selection: range, markedRange: nil)
        XCTAssertEqual(publications, 0)
        state.updateTextEditingDraft(text: text, selection: .init(location: 0, length: 2), markedRange: .init(location: 0, length: 2))
        XCTAssertGreaterThan(publications, 0, "Selection and IME composition remain distinct draft changes")
        XCTAssertEqual(state.textEditingSession.draft?.markedRange, .init(location: 0, length: 2))
        XCTAssertEqual(session.document, before); XCTAssertEqual(session.historySnapshot(), history)
    }

    func testWorkspaceAvailabilityMemoKeepsOperationsDistinctAndStorageBounded() {
        var cache = WorkspaceAvailabilityCache<Int, Int, Int>(), evaluations = 0
        func prepare(_ value: Int) -> Int { evaluations += 1; return value }
        XCTAssertEqual(cache.resolve(1, key: 0) { prepare(10) }, 10)
        XCTAssertEqual(cache.resolve(2, key: 0) { prepare(20) }, 20)
        for _ in 0..<1000 {
            XCTAssertEqual(cache.resolve(1, key: 0) { prepare(-1) }, 10)
            XCTAssertEqual(cache.resolve(2, key: 0) { prepare(-1) }, 20)
        }
        XCTAssertEqual(evaluations, 2)
        for operation in 3...40 { _ = cache.resolve(operation, key: 0) { prepare(operation) } }
        let beforeEviction = evaluations
        XCTAssertEqual(cache.resolve(1, key: 0) { prepare(11) }, 11)
        XCTAssertEqual(evaluations, beforeEviction + 1, "Arbitrary transform deltas cannot grow a permanent cache")
        XCTAssertEqual(cache.resolve(1, key: 1) { prepare(12) }, 12)
        XCTAssertEqual(evaluations, beforeEviction + 2, "Any context change requires fresh central validation")
        var rows = WorkspaceAvailabilityCache<Int, Int, Int>(capacity: 256)
        var rowPreparations = 0
        for _ in 0..<3 {
            for action in 0..<200 {
                XCTAssertEqual(rows.resolve(action, key: 1) { rowPreparations += 1; return action }, action)
            }
        }
        XCTAssertEqual(rowPreparations, 200, "Visible Layers context actions must not evict each other every redraw")
    }

    func testLayersMoveAvailabilityInvalidatesAfterLockAndUndo() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != session.document.revision
                    || state.selectionState.sceneIdentity?.revision != session.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        let rootID = try XCTUnwrap(session.document.pages[0].rootNodeIDs.first)
        state.performDefaultInsertion(.frame, provenance: .menu); try await settle()
        let sourceID = try XCTUnwrap(state.selectionState.primaryID)
        state.selectLayer(rootID); state.performDefaultInsertion(.frame, provenance: .menu); try await settle()
        state.selectLayer(sourceID)
        let destination = DragDestination.container(rootID, index: 2)
        for _ in 0..<100 { XCTAssertTrue(state.dragDropAvailability(sourceID: sourceID, destination: destination).isEnabled) }
        try session.execute(.setProperty(.init(pageID: session.document.pages[0].id, nodeID: sourceID,
            property: .init(key: .init(rawValue: "locked"), value: .boolean(true)))))
        try await settle(); state.selectLayer(sourceID)
        XCTAssertFalse(state.dragDropAvailability(sourceID: sourceID, destination: destination).isEnabled)
        state.undo(); try await settle(); state.selectLayer(sourceID)
        XCTAssertTrue(state.dragDropAvailability(sourceID: sourceID, destination: destination).isEnabled)
    }

    func testWorkspaceInsertionAndTransformAvailabilityInvalidateAfterLockAndUndo() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != session.document.revision
                    || state.selectionState.sceneIdentity?.revision != session.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        state.performDefaultInsertion(.frame, provenance: .menu)
        try await settle()
        let frameID = try XCTUnwrap(state.selectionState.primaryID)
        let pageID = try XCTUnwrap(state.effectiveSelectedPageID)
        let operation = TransformOperation.move(delta: .init(dx: 1, dy: 0), constraint: .none)
        let unchanged = session.document
        for _ in 0..<100 {
            XCTAssertTrue(state.insertionAvailability(.text).isEnabled)
            XCTAssertTrue(state.transformAvailability(operation).isEnabled)
        }
        XCTAssertEqual(session.document, unchanged)
        try session.execute(.setProperty(.init(pageID: pageID, nodeID: frameID,
            property: .init(key: .init(rawValue: "locked"), value: .boolean(true)))))
        try await settle()
        state.selectLayer(frameID)
        XCTAssertFalse(state.insertionAvailability(.text).isEnabled)
        XCTAssertFalse(state.transformAvailability(operation).isEnabled)
        state.undo(); try await settle(); state.selectLayer(frameID)
        XCTAssertTrue(state.insertionAvailability(.text).isEnabled)
        XCTAssertTrue(state.transformAvailability(operation).isEnabled)
        state.selectLayer(try XCTUnwrap(session.document.pages[0].rootNodeIDs.first))
        XCTAssertTrue(state.insertionAvailability(.text).isEnabled)
        XCTAssertFalse(state.transformAvailability(operation).isEnabled, "A prior frame cannot remain the menu target")
        XCTAssertEqual(session.document.pages, unchanged.pages)
    }

    // SF-0507-002/003, SF-0403-003: typing a scene-local draft must not
    // revalidate the entire canonical document for each Inspector field render.
    func testGeometryAvailabilityReusesOnlyIdenticalCommandContext() throws {
        let fixture = makeFixture()
        let scope = LayoutInspectorDraftScope(documentID: fixture.document.id, pageID: fixture.pageID,
            sceneID: fixture.sceneID, orderedNodeIDs: [fixture.nodeID], breakpoint: .desktop, viewportWidth: 1440)
        let renderer = CanvasRenderRequestIdentity(documentID: fixture.document.id, revision: fixture.document.revision,
            sceneID: fixture.sceneID, sceneGeneration: fixture.rendererGeneration,
            viewportGeneration: 0, scale: try .init(1))
        func key(_ newScope: LayoutInspectorDraftScope? = nil, revision: UInt64? = nil,
                 renderer newRenderer: CanvasRenderRequestIdentity? = nil,
                 context: TransformValidationContext? = nil) -> GeometryInspectorAvailabilityCache.Key {
            .init(scope: newScope ?? scope, revision: revision ?? fixture.document.revision,
                renderer: newRenderer ?? renderer, context: context ?? fixture.context)
        }
        var cache = GeometryInspectorAvailabilityCache(), evaluations = 0
        let before = fixture.document
        for _ in 0..<1000 {
            XCTAssertEqual(cache.resolve(.width, key: key()) { evaluations += 1; return .enabled }, .enabled)
        }
        XCTAssertEqual(evaluations, 1)
        XCTAssertEqual(cache.resolve(.height, key: key()) { evaluations += 1; return .disabled("Computed by Hug") }, .disabled("Computed by Hug"))
        XCTAssertEqual(evaluations, 2, "Fields have independent availability")
        let variants: [GeometryInspectorAvailabilityCache.Key] = [
            key(revision: fixture.document.revision + 1),
            key(.init(documentID: DocumentID(), pageID: scope.pageID, sceneID: scope.sceneID,
                orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth)),
            key(.init(documentID: scope.documentID, pageID: PageID(), sceneID: scope.sceneID,
                orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth)),
            key(.init(documentID: scope.documentID, pageID: scope.pageID, sceneID: CanvasViewportSceneID(),
                orderedNodeIDs: scope.orderedNodeIDs, breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth)),
            key(.init(documentID: scope.documentID, pageID: scope.pageID, sceneID: scope.sceneID,
                orderedNodeIDs: [NodeID()], breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth)),
            key(.init(documentID: scope.documentID, pageID: scope.pageID, sceneID: scope.sceneID,
                orderedNodeIDs: scope.orderedNodeIDs, breakpoint: .mobile, viewportWidth: 390)),
            key(renderer: .init(documentID: renderer.documentID, revision: renderer.revision, sceneID: renderer.sceneID,
                sceneGeneration: renderer.sceneGeneration + 1, viewportGeneration: 1, scale: try .init(2))),
            key(context: .init(activePageID: fixture.pageID, currentSceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration, selectedNodeIDs: [fixture.nodeID], availableNodeIDs: [],
                isLifecycleAvailable: true, lifecycleDisabledReason: nil)),
            key(context: .init(activePageID: fixture.pageID, currentSceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration, selectedNodeIDs: [fixture.nodeID], availableNodeIDs: [fixture.nodeID],
                isLifecycleAvailable: false, lifecycleDisabledReason: "Resolve conflict")),
        ]
        for variant in variants {
            let previous = evaluations
            XCTAssertEqual(cache.resolve(.width, key: variant) { evaluations += 1; return .disabled("Changed context") }, .disabled("Changed context"))
            XCTAssertEqual(evaluations, previous + 1, "No stale enabled result may survive a context change")
        }
        XCTAssertEqual(fixture.document, before, "Availability is never an authored mutation")
    }

    func testInspectorAccessibilityAnnouncesRetainedDraftInsteadOfCommittedValue() {
        let committed = "75; Computed by responsive layout"
        XCTAssertEqual(InspectorDraftAccessibility.value(draft: nil, committed: committed), committed)
        for draft in ["-", "1e", "nan", "22", "Missing Family"] {
            XCTAssertEqual(InspectorDraftAccessibility.value(draft: draft, committed: committed), "\(draft); uncommitted draft")
            XCTAssertFalse(InspectorDraftAccessibility.value(draft: draft, committed: committed).contains("75"))
        }
        XCTAssertEqual(InspectorDraftAccessibility.value(draft: "", committed: committed), "Empty; uncommitted draft")
        XCTAssertEqual(InspectorDraftAccessibility.value(draft: nil, committed: "Mixed values"), "Mixed values")
    }

    func testRetainedNumericNoOpRecognizesEquivalentInputWithoutDiscardingConflict() {
        let scope = LayoutInspectorDraftScope(documentID: DocumentID(), pageID: PageID(), sceneID: CanvasViewportSceneID(),
            orderedNodeIDs: [NodeID()], breakpoint: .desktop, viewportWidth: 1440)
        for text in ["160", "160.0", " 160 "] {
            let draft = LayoutInspectorNumericDraft(text: text, committed: "160", scope: scope)
            XCTAssertTrue(draft.hasUnchangedNumericValue)
        }
        for text in ["-", "nan", "infinity", "161"] {
            XCTAssertFalse(LayoutInspectorNumericDraft(text: text, committed: "160", scope: scope).hasUnchangedNumericValue)
        }
        var stale = LayoutInspectorNumericDraft(text: "160", committed: "160", scope: scope)
        stale.adopt(committed: "160", scope: .init(documentID: scope.documentID, pageID: scope.pageID,
            sceneID: scope.sceneID, orderedNodeIDs: [NodeID()], breakpoint: .desktop, viewportWidth: 1440))
        XCTAssertFalse(stale.hasUnchangedNumericValue)
        XCTAssertEqual(stale.conflict, .contextChanged)
        XCTAssertEqual(stale.text, "160")
    }
    func testSizingDimensionWinnerAndExactResetPreserveOtherOverridesAndHistory() throws {
        var fixture = makeFixture()
        let widthKey = ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)
        let heightKey = ResponsiveGeometryResolver.key(.height, breakpoint: .mobile)
        let fluid = CanonicalFluidValue(minimum: 180, preferred: 280, maximum: 480)
        fixture.document.pages[0].nodes[1].properties += [
            .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "widthMode"), value: .string("fill")),
            .init(key: .init(rawValue: widthKey), value: .number(240)),
            .init(key: .init(rawValue: heightKey), value: .number(160)),
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.width)), value: .string(try CanonicalFluidValueCodec.encode(fluid, target: .width)))
        ]
        let session = DocumentSession(document: fixture.document), registry = SizingConstraintCommandRegistry()
        func resolution() -> SizingDimensionResolution {
            CanonicalSizingConstraints.dimensionResolution(.width, node: session.document.pages[0].nodes[1], breakpoint: .mobile, width: 390)
        }
        func reset(_ source: ResponsiveGeometrySource) throws -> DocumentCommand {
            try registry.prepareDimensionReset(.width, source: source,
                identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: fixture.pageID,
                    revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], breakpoint: .mobile, in: session.document, context: fixture.context)
        }
        XCTAssertEqual(resolution().declaredMode, .fill)
        XCTAssertEqual(resolution().effectiveMode, .fixed)
        XCTAssertEqual(resolution().numericSource, .override(.mobile))
        XCTAssertThrowsError(try reset(.fluid), "Do not remove a concealed lower-priority source")
        try session.execute(reset(.override(.mobile)))
        XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty(widthKey))
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty(heightKey), fixture.document.pages[0].nodes[1].insertionProperty(heightKey))
        XCTAssertEqual(resolution().numericSource, .fluid)
        let inheritedFluid = session.document.pages
        try session.execute(reset(.fluid))
        XCTAssertEqual(resolution().effectiveMode, .fill)
        XCTAssertNil(resolution().numericSource)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionGeometry, fixture.document.pages[0].nodes[1].insertionGeometry)
        try session.undo(); XCTAssertEqual(session.document.pages, inheritedFluid)
        try session.undo(); XCTAssertEqual(session.document.pages, fixture.document.pages)
        try session.redo(); try session.redo()
        let beforeHeightReset = session.document.pages
        try session.execute(registry.prepareDimensionReset(.height, source: .override(.mobile),
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], breakpoint: .mobile, in: session.document, context: fixture.context))
        XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty(heightKey))
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: session.document.pages[0].nodes[1]).widthMode, .fill)
        try session.undo(); XCTAssertEqual(session.document.pages, beforeHeightReset)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testSizingExactDimensionResetRejectsStaleLockedMixedAndCancelledWithoutMutation() throws {
        var fixture = makeFixture()
        let key = ResponsiveGeometryResolver.key(.width, breakpoint: .tablet)
        fixture.document.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: key), value: .number(360)))
        let registry = SizingConstraintCommandRegistry(), document = fixture.document
        func prepare(_ candidate: CanonicalDocument, selected: [NodeID], revision: UInt64? = nil, cancelled: Bool = false) throws {
            _ = try registry.prepareDimensionReset(.width, source: .override(.tablet),
                identity: .init(editID: GeometryInspectorEditID(), documentID: document.id, pageID: fixture.pageID,
                    revision: revision ?? document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: selected, breakpoint: .tablet, in: candidate,
                context: fixture.context(selectedIDs: selected), cancelled: cancelled)
        }
        XCTAssertThrowsError(try prepare(document, selected: [fixture.nodeID], cancelled: true))
        XCTAssertThrowsError(try prepare(document, selected: [fixture.nodeID], revision: document.revision + 1))
        XCTAssertThrowsError(try prepare(document, selected: [fixture.nodeID, fixture.secondNodeID]))
        var locked = document
        locked.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: "locked"), value: .boolean(true)))
        XCTAssertThrowsError(try prepare(locked, selected: [fixture.nodeID]))
        XCTAssertEqual(fixture.document, document)
    }

    func testSizingModeEligibilityAndConversionScopeUseTheSameSupportedSubset() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .stack
        fixture.document.pages[0].nodes[1].childIDs = [fixture.secondNodeID]
        fixture.document.pages[0].nodes[0].childIDs = [fixture.nodeID]
        applyStructuralDefaults(for: .stack, to: &fixture.document.pages[0].nodes[1])
        fixture.document.pages[0].nodes[2].parent = .node(fixture.nodeID)
        let page = fixture.document.pages[0]
        var image = page.nodes[2]; image.kind = .image
        XCTAssertFalse(SizingConstraintCommandRegistry.supportsMode(.height, .hug, node: image, page: page))
        XCTAssertFalse(SizingConstraintCommandRegistry.supportsMode(.width, .hug, node: page.nodes[1], page: page))
        XCTAssertTrue(SizingConstraintCommandRegistry.supportsMode(.width, .fill, node: page.nodes[1], page: page))
        let context = fixture.context
        let scope = SizingConstraintCommandRegistry.conversionScope(page: page, context: context)
        XCTAssertEqual(scope.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(scope.skippedNodeIDs, [fixture.secondNodeID])
        let prepared = try SizingConstraintCommandRegistry().prepare(.init(identity:
            .init(editID: GeometryInspectorEditID(), documentID: fixture.document.id, pageID: fixture.pageID,
                revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .convertContent, cancelled: false), in: fixture.document, context: context)
        XCTAssertEqual(prepared.applicableNodeIDs, scope.applicableNodeIDs)
        XCTAssertEqual(prepared.skippedNodeIDs, scope.skippedNodeIDs)
        let cancelled = SizingConstraintCommand(identity: .init(editID: GeometryInspectorEditID(), documentID: fixture.document.id,
            pageID: fixture.pageID, revision: fixture.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .convertContent, cancelled: true)
        XCTAssertThrowsError(try SizingConstraintCommandRegistry().prepare(cancelled, in: fixture.document, context: context))
        var locked = fixture.document
        locked.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: "locked"), value: .boolean(true)))
        XCTAssertTrue(SizingConstraintCommandRegistry.conversionScope(page: locked.pages[0], context: context).applicableNodeIDs.isEmpty)
    }

    func testLayoutNumericDraftRetainsInvalidInputAndRejectsContextChanges() {
        let fixture = makeFixture()
        let scope = LayoutInspectorDraftScope(documentID: fixture.document.id, pageID: fixture.pageID,
            sceneID: fixture.sceneID, orderedNodeIDs: [fixture.nodeID], breakpoint: .desktop, viewportWidth: 1440)
        for text in ["320", "-", "1e", ""] {
            var draft = LayoutInspectorNumericDraft(text: text, committed: "120", scope: scope)
            draft.adopt(committed: "120", scope: scope)
            draft.adopt(committed: nil, scope: scope)
            XCTAssertEqual(draft.text, text)
            XCTAssertTrue(draft.canCommit(in: scope), "Parsing remains the existing registry/locale parser's responsibility")
            let other = LayoutInspectorDraftScope(documentID: fixture.document.id, pageID: fixture.pageID,
                sceneID: fixture.sceneID, orderedNodeIDs: [fixture.nodeID], breakpoint: .mobile, viewportWidth: 390)
            draft.adopt(committed: "120", scope: other)
            XCTAssertEqual(draft.conflict, .contextChanged)
            XCTAssertEqual(draft.text, text)
            XCTAssertFalse(draft.canCommit(in: other))
            XCTAssertFalse(draft.canCommit(in: scope), "Switching back cannot silently rearm a conflicted edit")
        }
        var changed = LayoutInspectorNumericDraft(text: "320", committed: "120", scope: scope)
        changed.adopt(committed: "240", scope: scope)
        XCTAssertEqual(changed.conflict, .valueChanged)
        XCTAssertFalse(changed.canCommit(in: scope))
        for (selected, width) in [([fixture.secondNodeID], 1440.0), ([fixture.nodeID], 1200.0)] {
            let other = LayoutInspectorDraftScope(documentID: fixture.document.id, pageID: fixture.pageID,
                sceneID: fixture.sceneID, orderedNodeIDs: selected, breakpoint: .desktop, viewportWidth: width)
            var retained = LayoutInspectorNumericDraft(text: "1e", committed: "120", scope: scope)
            retained.adopt(committed: nil, scope: other)
            XCTAssertEqual(retained.conflict, .contextChanged)
            XCTAssertEqual(retained.text, "1e")
            XCTAssertFalse(retained.canCommit(in: other))
        }
    }

    func testSizingDiagnosticsRemainBoundedAndExcludeRawObjectIdentity() {
        let fixture = makeFixture(), diagnostics = CommandDiagnostics(capacity: 2)
        for succeeded in [false, true, false] {
            diagnostics.recordSizingOperation(pageID: fixture.pageID, nodeIDs: [fixture.nodeID], succeeded: succeeded, durationMilliseconds: 1)
        }
        XCTAssertEqual(diagnostics.records.count, 2)
        XCTAssertEqual(diagnostics.droppedRecordCount, 1)
        for record in diagnostics.records {
            XCTAssertTrue(record.requirementIDs.contains("SF-0505-003"))
            XCTAssertTrue(record.requirementIDs.contains("SF-0604-005"))
            XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
            XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.pageID.description))
        }
    }

    func testHugFlowContainerRejectsFillHeightCycleWithoutChangingCanonicalIntent() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[0].childIDs = [fixture.nodeID]
        fixture.document.pages[0].nodes[1].kind = .stack
        fixture.document.pages[0].nodes[1].childIDs = [fixture.secondNodeID]
        applyStructuralDefaults(for: .stack, to: &fixture.document.pages[0].nodes[1])
        fixture.document.pages[0].nodes[2].parent = .node(fixture.nodeID)
        fixture.document.pages[0].nodes[2].properties.append(.init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "heightMode"), value: .string("fill")))
        try fixture.document.validate()
        let before = fixture.document
        let command = SizingConstraintCommand(identity: .init(editID: GeometryInspectorEditID(), documentID: before.id,
            pageID: fixture.pageID, revision: before.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .setMode(.height, .hug), cancelled: false)
        XCTAssertThrowsError(try SizingConstraintCommandRegistry().prepare(command, in: before, context: fixture.context)) {
            XCTAssertTrue($0.localizedDescription.contains("hug a fill-height child"))
        }
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0508-002/005: native Return of an unchanged angle clears its draft
    // without inventing history or displaying an error; invalid input remains rejected.
    func testWorkspaceFillLayerUnchangedAngleIsSuccessfulAndHistoryNeutral() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != state.documentSession.document.revision
                    || state.selectionState.sceneIdentity?.revision != state.documentSession.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        state.performDefaultInsertion(.frame, provenance: .menu)
        try await settle()
        let id = FillLayerID()
        XCTAssertTrue(state.commitDesignFillLayer(.addLinearGradient(id: id, angleDegrees: 45, stops: [
            .init(id: GradientStopID(), position: 0, color: .legacySurface),
            .init(id: GradientStopID(), position: 1, color: .init(red: 0.4, green: 0.2, blue: 0.8, alpha: 1)),
        ]), operation: "add gradient"))
        try await settle()
        let before = state.documentSession.document
        let history = state.documentSession.historySnapshot()
        XCTAssertTrue(state.commitDesignFillLayer(.setGradientAngle(id, 45), operation: "angle", provenance: .keyboard))
        XCTAssertNil(state.designInspectorFailure)
        XCTAssertEqual(state.lastDesignInspectorAnnouncement, "Design appearance is unchanged.")
        XCTAssertEqual(state.documentSession.document, before)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
        XCTAssertFalse(state.commitDesignFillLayer(.setGradientAngle(id, .nan), operation: "angle", provenance: .keyboard))
        XCTAssertNotNil(state.designInspectorFailure)
        XCTAssertEqual(state.documentSession.document, before)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
    }

    // SF-0505-002/004/005: unchanged valid drafts finish without a false error
    // or history entry; invalid and stale attempts remain rejected.
    func testWorkspaceSizingUnchangedDraftIsSuccessfulAndHistoryNeutral() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != state.documentSession.document.revision
                    || state.selectionState.sceneIdentity?.revision != state.documentSession.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        state.performDefaultInsertion(.frame, provenance: .menu)
        try await settle()
        XCTAssertTrue(state.commitSizingConstraint(.set(.minWidth, 80)))
        try await settle()
        let before = state.documentSession.document
        let history = state.documentSession.historySnapshot()
        let selection = state.selectionState.orderedIDs
        XCTAssertTrue(state.commitSizingConstraint(.set(.minWidth, 80)))
        XCTAssertEqual(state.lastSizingConstraintAnnouncement, "Sizing is unchanged.")
        XCTAssertEqual(state.documentSession.document, before)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
        XCTAssertEqual(state.selectionState.orderedIDs, selection)
        XCTAssertFalse(state.commitSizingConstraint(.set(.minWidth, -.infinity)))
        XCTAssertFalse(state.commitSizingConstraint(.set(.minWidth, 80), expectedContext: "stale"))
        XCTAssertEqual(state.documentSession.document, before)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
    }

    // SF-SOURCE-BATCH-20261027-01: new source only, not executed.
    func testSiteSetupOpeningPageIdentityCannotCommitAfterPageSwitch() async throws {
        let session = DocumentSession()
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while state.websiteSettingsIdentity == nil {
            if ContinuousClock.now >= deadline { XCTFail("Opening scene did not become available"); return }
            await Task.yield()
        }
        let opening = try XCTUnwrap(state.websiteSettingsIdentity)
        let destination = try XCTUnwrap(session.document.websitePages.first { $0.id != opening.pageID })
        state.presentWebsiteSettings()
        state.selectPage(destination.id)
        let nextDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while state.websiteSettingsIdentity?.pageID != destination.id {
            if ContinuousClock.now >= nextDeadline { XCTFail("Destination scene did not adopt"); return }
            await Task.yield()
        }
        let before = session.document, history = session.historySnapshot()
        XCTAssertFalse(state.commitWebsiteSettings(.init(siteName: "Stale draft", pages: [
            .init(pageID: opening.pageID, title: "Old page title", allowsIndexing: false)
        ]), identity: opening))
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.historySnapshot(), history)
        XCTAssertEqual(state.effectiveSelectedPageID, destination.id)
    }

    func testWebsiteSettingsNoChangeIsNeutralAndStillRejectsStaleIdentity() async throws {
        var document = ProjectCreation.blank()
        document.websiteMetadata = .init(siteName: "Aurora")
        let session = DocumentSession(document: document)
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while state.websiteSettingsIdentity == nil {
            guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
            await Task.yield()
        }
        let identity = try XCTUnwrap(state.websiteSettingsIdentity)
        let before = session.document
        XCTAssertTrue(state.commitWebsiteSettings(before.websiteMetadata, identity: identity))
        XCTAssertEqual(state.websiteSettingsStatus, "Site Settings are unchanged.")
        XCTAssertEqual(session.document, before)
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(state.lifecycle.isModified)
        let stale = DesignInspectorOperationIdentity(documentID: identity.documentID,
            pageID: identity.pageID, revision: identity.revision + 1,
            sceneID: identity.sceneID, rendererGeneration: identity.rendererGeneration)
        XCTAssertFalse(state.commitWebsiteSettings(before.websiteMetadata, identity: stale))
        XCTAssertEqual(session.document, before)
        XCTAssertFalse(session.canUndo)
    }
    // SF-0402-003/005, SF-0403-003, SF-0701-003: ordinary edits must not
    // mistake a Layers-selected nested parent for an isolation transition.
    func testNestedLayersSelectionSurvivesTextGeometryAndRendererAdoptionWithoutIsolation() async throws {
        let state = WorkspaceShellState(documentSession: DocumentSession(document: ProjectCreation.blank()))
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        enum AdoptionFailure: Error { case timeout }
        func settle() async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while state.canvasRenderPlan?.identity.revision != state.documentSession.document.revision
                    || state.selectionState.sceneIdentity?.revision != state.documentSession.document.revision {
                guard ContinuousClock.now < deadline else { throw AdoptionFailure.timeout }
                await Task.yield()
            }
        }
        try await settle()
        state.performDefaultInsertion(.section, provenance: .menu)
        try await settle()
        let section = try XCTUnwrap(state.selectionState.primaryID)
        state.selectLayer(section)
        state.performDefaultInsertion(.text, provenance: .menu)
        try await settle()
        let text = try XCTUnwrap(state.selectionState.primaryID)
        state.selectLayer(text)
        XCTAssertEqual(state.selectionState.activeContainerID, section)
        XCTAssertNil(state.isolationRootID)
        XCTAssertTrue(state.beginTextEditing(nodeID: text, provenance: .menu))
        state.updateTextEditingDraft(text: "The Journal", selection: .init(location: 11, length: 0), markedRange: nil)
        state.commitTextEditing()
        XCTAssertEqual(state.selectionState.primaryID, text)
        try await settle()
        XCTAssertEqual(state.selectionState.activeContainerID, section)
        XCTAssertEqual(state.selectionState.primaryID, text)
        XCTAssertTrue(state.commitGeometryInspectorValue(600, field: .width, provenance: .keyboard))
        XCTAssertEqual(state.selectionState.primaryID, text)
        try await settle()
        XCTAssertEqual(state.selectionState.primaryID, text)
        XCTAssertEqual(state.selectionState.activeContainerID, section)
        state.undo(); try await settle()
        XCTAssertEqual(state.selectionState.primaryID, text)
        state.redo(); try await settle()
        XCTAssertEqual(state.selectionState.primaryID, text)
        XCTAssertNil(state.isolationRootID)
    }

    func testFrameSectionImageFillIsAtomicScopedAndMissingSafe() throws {
        var fixture = makeFixture(selectedIDs: [NodeID]())
        fixture.document.pages[0].nodes[2].kind = .section
        applyStructuralDefaults(for: .section, to: &fixture.document.pages[0].nodes[2])
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Card",
            originalFilename: "card.png", format: .png, pixelWidth: 4, pixelHeight: 3,
            byteCount: 16, contentHash: String(repeating: "a", count: 64))
        fixture.document.imageAssets = [asset]
        let session = DocumentSession(document: fixture.document)
        let ids = [fixture.nodeID, fixture.secondNodeID]
        func node(_ id: NodeID) -> DocumentNode {
            session.document.pages[0].nodes.first { $0.id == id }!
        }
        func prepare(_ edit: ImageFillEdit, ids: [NodeID] = []) throws -> PreparedImageInspectorEdit {
            let selected = ids.isEmpty ? [fixture.nodeID, fixture.secondNodeID] : ids
            return try ImageFillCommandRegistry().prepare(edit, identity: .init(
                documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration, selectedNodeIDs: selected),
                in: session.document, context: fixture.context(selectedIDs: selected))
        }
        let applied = try prepare(.setAsset(asset.id))
        XCTAssertEqual(applied.applicableNodeIDs, ids)
        try session.execute(applied.command)
        XCTAssertEqual(CanonicalImageFill.resolve(node(fixture.nodeID))?.mode, .fill)
        let propertyID = try XCTUnwrap(node(fixture.nodeID).insertionProperty(CanonicalImageFill.assetKey)?.id)
        XCTAssertFalse(CommandRegistry().availability(for: .removeImageAsset(.init(assetID: asset.id)),
            in: session.document).isEnabled)
        let mode = try prepare(.setMode(.fit))
        try session.execute(mode.command)
        XCTAssertEqual(CanonicalImageFill.resolve(node(fixture.secondNodeID))?.mode, .fit)
        try session.undo()
        XCTAssertEqual(CanonicalImageFill.resolve(node(fixture.nodeID))?.mode, .fill)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let staticTree = try InternalDocumentRenderTreeCompiler.compile(page: session.document.pages[0],
            documentID: session.document.id, revision: session.document.revision)
        XCTAssertEqual(staticTree.nodes.first { $0.id == fixture.nodeID }?.imageFill?.assetID, asset.id)
        let plannedTree = try InternalDocumentRenderTreeCompiler.compile(page: session.document.pages[0],
            documentID: session.document.id, revision: session.document.revision,
            imageOutputPaths: [asset.id: "assets/\(asset.contentHash).png"],
            imageAssets: [asset.id: asset])
        let style = StaticFillLayerStyleOutputEmitter.emit(nodes: plannedTree.nodes)
        XCTAssertTrue(style.contains("url(\"assets/\(asset.contentHash).png\")"), style)
        XCTAssertTrue(style.contains("background-size: contain;"), style)
        XCTAssertFalse(style.contains("/Users/"))
        var missing = session.document
        missing.imageAssets = []
        XCTAssertNoThrow(try missing.validate())
        XCTAssertEqual(CanonicalImageFill.resolve(missing.pages[0].nodes[1])?.assetID, asset.id)
        XCTAssertThrowsError(try prepare(.setMode(.stretch)))
        XCTAssertThrowsError(try ImageFillCommandRegistry().prepare(.remove, identity: .init(
            documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration,
            selectedNodeIDs: ids), in: session.document,
            context: fixture.context(selectedIDs: ids), cancelled: true))
        try session.execute(prepare(.remove).command)
        XCTAssertNil(CanonicalImageFill.resolve(node(fixture.nodeID)))
        try session.undo()
        XCTAssertEqual(node(fixture.nodeID).insertionProperty(CanonicalImageFill.assetKey)?.id, propertyID)
        let detachedProperties: [DocumentCommand] = ids.flatMap { id in
            [CanonicalImageFill.assetKey, CanonicalImageFill.modeKey].compactMap { key in
                node(id).insertionProperty(key).map {
                    .removeProperty(.init(pageID: fixture.pageID, nodeID: id, propertyID: $0.id))
                }
            }
        }
        try session.execute(.batch(detachedProperties + [.removeImageAsset(.init(assetID: asset.id))]))
        XCTAssertTrue(session.document.imageAssets.isEmpty)
        XCTAssertTrue(ids.allSatisfy { CanonicalImageFill.resolve(node($0)) == nil })
        try session.undo()
        XCTAssertEqual(node(fixture.nodeID).insertionProperty(CanonicalImageFill.assetKey)?.id, propertyID)
        XCTAssertEqual(session.document.imageAssets.first?.id, asset.id)
        var malformed = session.document
        let malformedIndex = try XCTUnwrap(malformed.pages[0].nodes[1].properties.firstIndex {
            $0.key.rawValue == CanonicalImageFill.modeKey
        })
        malformed.pages[0].nodes[1].properties[malformedIndex].value = .string("stretch")
        XCTAssertThrowsError(try malformed.validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .invalidImageReference)
        }
    }

    func testTextForegroundLiteralTokenFallbackHistoryAndValidation() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .text
        fixture.document.pages[0].nodes[2].kind = .button
        let token = LocalColorToken(name: "Ink", color: .init(red: 0.8, green: 0.1, blue: 0.2, alpha: 1))
        fixture.document.colorTokens = [token]
        let literal = CanonicalSolidColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        let session = DocumentSession(document: fixture.document)
        let ids = [fixture.nodeID, fixture.secondNodeID]
        func node() -> DocumentNode { session.document.pages[0].nodes[1] }
        func typography(_ edit: TypographyEdit) throws {
            let command = TypographyCommand(identity: .init(documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: false)
            let prepared = try TypographyCommandRegistry().prepare(command, in: session.document,
                context: fixture.context(selectedIDs: ids))
            XCTAssertEqual(prepared.applicableNodeIDs, ids)
            try session.execute(prepared.documentCommand)
        }
        func tokenEdit(_ edit: LocalColorTokenEdit) throws {
            try session.execute(LocalColorTokenCommandRegistry.prepare(edit, in: session.document,
                expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
                pageID: fixture.pageID, selectedNodeIDs: ids))
        }
        XCTAssertNil(CanonicalTextForeground.literal(for: node()))
        try typography(.foreground(literal))
        let channelIDs = CanonicalTextForeground.channels.compactMap {
            node().insertionProperty(CanonicalTextForeground.prefix + $0)?.id
        }
        XCTAssertEqual(channelIDs.count, 4)
        XCTAssertEqual(CanonicalTextForeground.literal(for: node()), literal)
        XCTAssertEqual(CanonicalTextForeground.literal(for: session.document.pages[0].nodes[2]), literal)
        let literalCSS = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: session.document)
            .files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(literalCSS.contains("color: rgba(51.0, 76.5, 102.0, 1.0)"), literalCSS)
        try tokenEdit(.bindTarget(token.id, .textForeground))
        XCTAssertEqual(LocalColorTokenResolver.textForeground(for: node(), tokens: session.document.colorTokens), token.color)
        XCTAssertEqual(CanonicalTextForeground.literal(for: node()), literal)
        let tokenCSS = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: session.document)
            .files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(tokenCSS.contains("color: rgba(204.0, 25.5, 51.0, 1.0)"), tokenCSS)
        XCTAssertThrowsError(try tokenEdit(.delete(token.id)))
        try tokenEdit(.recolor(token.id, .init(red: 0.1, green: 0.7, blue: 0.2, alpha: 1)))
        XCTAssertEqual(LocalColorTokenResolver.textForeground(for: node(), tokens: session.document.colorTokens)?.green, 0.7)
        try session.undo()
        XCTAssertEqual(LocalColorTokenResolver.textForeground(for: node(), tokens: session.document.colorTokens), token.color)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        var missing = session.document
        missing.colorTokens = []
        XCTAssertNoThrow(try missing.validate())
        XCTAssertEqual(LocalColorTokenResolver.textForeground(for: missing.pages[0].nodes[1], tokens: []), literal)
        try tokenEdit(.unbindTarget(.textForeground))
        XCTAssertNil(LocalColorTokenBinding.id(for: node(), target: .textForeground))
        XCTAssertEqual(CanonicalTextForeground.literal(for: node())?.green, 0.7)
        try session.undo()
        XCTAssertEqual(CanonicalTextForeground.literal(for: node()), literal)
        XCTAssertEqual(CanonicalTextForeground.channels.compactMap {
            node().insertionProperty(CanonicalTextForeground.prefix + $0)?.id
        }, channelIDs)
        try session.redo()
        try typography(.foreground(nil))
        XCTAssertNil(CanonicalTextForeground.literal(for: node()))
        try session.undo()
        XCTAssertEqual(CanonicalTextForeground.literal(for: node())?.green, 0.7)
        XCTAssertThrowsError(try typography(.foreground(.init(red: .nan, green: 0, blue: 0, alpha: 1))))
        var malformed = session.document
        malformed.pages[0].nodes[1].properties.removeAll { $0.key.rawValue == CanonicalTextForeground.prefix + "alpha" }
        XCTAssertThrowsError(try malformed.validate())
        malformed = session.document
        malformed.pages[0].nodes[1].kind = .frame
        XCTAssertThrowsError(try malformed.validate())
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testLocalColorTokenBorderShadowBindingHistoryAndStaticResolution() throws {
        var fixture = makeFixture()
        let literalBorder = CanonicalSolidColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        let literalShadow = CanonicalSolidColor(red: 0, green: 0, blue: 0, alpha: 0.3)
        let tokenColor = CanonicalSolidColor(red: 0.8, green: 0.1, blue: 0.2, alpha: 1)
        let token = LocalColorToken(name: "Accent", color: tokenColor)
        fixture.document.colorTokens = [token]
        let box = CanonicalBoxStyle(border: .init(color: literalBorder, width: 2, style: .solid),
            cornerRadius: 8, shadow: .init(color: literalShadow, offsetX: 2, offsetY: 4,
                blur: 8, spread: 0))
        fixture.document.pages[0].nodes[1].properties += DesignBoxStyleCommandRegistry.propertyValues(for: box)
            .sorted { $0.key < $1.key }.map { .init(key: .init(rawValue: $0.key), value: $0.value, origin: .authored) }
        let session = DocumentSession(document: fixture.document)
        func node() -> DocumentNode { session.document.pages[0].nodes[1] }
        func edit(_ value: LocalColorTokenEdit) throws {
            let command = try LocalColorTokenCommandRegistry.prepare(value, in: session.document,
                expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
                pageID: fixture.pageID, selectedNodeIDs: [fixture.nodeID])
            try session.execute(command)
        }
        try edit(.bindTarget(token.id, .border))
        try edit(.bindTarget(token.id, .outerShadow))
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: node(), tokens: session.document.colorTokens)?.border?.color, tokenColor)
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: node(), tokens: session.document.colorTokens)?.shadow?.color, tokenColor)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node())?.border?.color, literalBorder)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node())?.shadow?.color, literalShadow)
        let blockedRemoval = DesignBoxStyleCommand(identity: .init(documentID: session.document.id,
            pageID: fixture.pageID, revision: session.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .border(nil),
            provenance: .automation, cancelled: false)
        XCTAssertThrowsError(try DesignBoxStyleCommandRegistry().prepare(blockedRemoval,
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        let staticPlan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let css = try XCTUnwrap(staticPlan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("border: 2.0px solid rgba(204.0, 25.5, 51.0, 1.0)"), css)
        XCTAssertTrue(css.contains("box-shadow: 2.0px 4.0px 8.0px 0.0px rgba(204.0, 25.5, 51.0, 1.0)"), css)
        XCTAssertThrowsError(try edit(.delete(token.id)))
        let borderID = try XCTUnwrap(node().insertionProperty(LocalColorTokenBinding.key(for: .border))?.id)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened, session.document)
        try edit(.recolor(token.id, .init(red: 0.1, green: 0.7, blue: 0.3, alpha: 0.6)))
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: node(), tokens: session.document.colorTokens)?.border?.color.green, 0.7)
        try session.undo()
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: node(), tokens: session.document.colorTokens)?.border?.color, tokenColor)
        try session.redo()
        try edit(.unbindTarget(.border))
        XCTAssertNil(LocalColorTokenBinding.id(for: node(), target: .border))
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node())?.border?.color.green, 0.7)
        try session.undo()
        XCTAssertEqual(node().insertionProperty(LocalColorTokenBinding.key(for: .border))?.id, borderID)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node())?.border?.color, literalBorder)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testLocalColorTokenSchemaNineFillBindingMigratesToTargetKeyedIdentity() throws {
        var fixture = makeFixture()
        let token = LocalColorToken(name: "Accent", color: .legacySurface)
        fixture.document.colorTokens = [token]
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted))
        let binding = NodeProperty(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
            value: .string(token.id.description), origin: .authored)
        fixture.document.pages[0].nodes[1].properties.append(binding)
        let current = try DocumentSerializer.encode(fixture.document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        var body = try XCTUnwrap(envelope["document"] as? [String: Any])
        var pages = try XCTUnwrap(body["pages"] as? [[String: Any]])
        var nodes = try XCTUnwrap(pages[0]["nodes"] as? [[String: Any]])
        let nodeIndex = try XCTUnwrap(nodes.firstIndex { ($0["id"] as? String) == fixture.nodeID.description })
        var properties = try XCTUnwrap(nodes[nodeIndex]["properties"] as? [[String: Any]])
        let propertyIndex = try XCTUnwrap(properties.firstIndex { ($0["key"] as? String) == LocalColorTokenBinding.key(for: .fill) })
        properties[propertyIndex]["key"] = LocalColorTokenBinding.legacyKey
        nodes[nodeIndex]["properties"] = properties
        pages[0]["nodes"] = nodes; body["pages"] = pages
        body.removeValue(forKey: "websiteMetadata") // Historical schema 9 has no metadata field.
        envelope["document"] = body
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)))
        envelope["schemaVersion"] = 9
        let migrated = try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope))
        let migratedNode = try XCTUnwrap(migrated.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(migratedNode.insertionProperty(LocalColorTokenBinding.key(for: .fill))?.id, binding.id)
        XCTAssertNil(migratedNode.insertionProperty(LocalColorTokenBinding.legacyKey))
        XCTAssertEqual(LocalColorTokenBinding.id(for: migratedNode), token.id)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(migrated)), migrated)
    }

    func testLocalColorTokenTargetValidationFallbackMixedAndNeutralFailures() throws {
        var fixture = makeFixture()
        let literal = CanonicalSolidColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let token = LocalColorToken(name: "Accent", color: .legacySurface)
        fixture.document.colorTokens = [token]
        let box = CanonicalBoxStyle(border: .init(color: literal, width: 2, style: .solid),
            cornerRadius: nil, shadow: nil)
        fixture.document.pages[0].nodes[1].properties += DesignBoxStyleCommandRegistry.propertyValues(for: box)
            .sorted { $0.key < $1.key }.map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        fixture.document.pages[0].nodes[2].kind = .text
        let selected = [fixture.nodeID, fixture.secondNodeID]
        let prepared = try LocalColorTokenCommandRegistry.prepare(.bindTarget(token.id, .border),
            in: fixture.document, expectedDocumentID: fixture.document.id,
            expectedRevision: fixture.document.revision, pageID: fixture.pageID,
            selectedNodeIDs: selected)
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared)
        let bound = session.document.pages[0].nodes[1]
        XCTAssertEqual(LocalColorTokenBinding.id(for: bound, target: .border), token.id)
        XCTAssertEqual(session.document.pages[0].nodes[2], fixture.document.pages[0].nodes[2])
        var missing = session.document
        missing.colorTokens = []
        XCTAssertNoThrow(try missing.validate())
        XCTAssertEqual(LocalColorTokenResolver.resolvedBoxStyle(for: missing.pages[0].nodes[1], tokens: [])?.border?.color, literal)
        let original = try DocumentSerializer.encode(session.document)
        XCTAssertThrowsError(try LocalColorTokenCommandRegistry.prepare(.bindTarget(token.id, .outerShadow),
            in: session.document, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision, pageID: fixture.pageID,
            selectedNodeIDs: [fixture.nodeID]))
        XCTAssertThrowsError(try LocalColorTokenCommandRegistry.prepare(.unbindTarget(.border),
            in: session.document, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision + 1, pageID: fixture.pageID,
            selectedNodeIDs: [fixture.nodeID]))
        XCTAssertThrowsError(try LocalColorTokenCommandRegistry.prepare(.unbindTarget(.border),
            in: session.document, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision, pageID: fixture.pageID,
            selectedNodeIDs: [fixture.nodeID], cancelled: true))
        XCTAssertEqual(try DocumentSerializer.encode(session.document), original)
        var invalid = session.document
        invalid.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: LocalColorTokenBinding.key(for: .outerShadow)),
            value: .string(token.id.description)))
        XCTAssertThrowsError(try invalid.validate())
        invalid = session.document
        invalid.pages[0].nodes[2].properties.append(.init(
            key: .init(rawValue: LocalColorTokenBinding.key(for: .border)),
            value: .string(token.id.description)))
        XCTAssertThrowsError(try invalid.validate())
    }

    func testSizingNamespaceRejectsMalformedUnsupportedAndContradictoryProperties() throws {
        let fixture = makeFixture()
        func expectInvalid(_ properties: [NodeProperty], kind: NodeKind = .frame,
                           expected: ModelValidationError = .invalidSizingConstraints) {
            var document = fixture.document
            document.pages[0].nodes[1].kind = kind
            document.pages[0].nodes[1].properties.append(contentsOf: properties)
            XCTAssertThrowsError(try document.validate()) { error in
                XCTAssertEqual(error as? ModelValidationError, expected)
            }
        }
        func property(_ suffix: String, _ value: PropertyValue) -> NodeProperty {
            .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + suffix),
                value: value, origin: .authored)
        }
        expectInvalid([property("minWidth", .number(.nan))])
        expectInvalid([property("minWidth", .string("10"))])
        expectInvalid([property("minWidth", .number(300)), property("maxWidth", .number(100))])
        expectInvalid([property("maxWidth", .number(0))])
        expectInvalid([property("aspectEnabled", .boolean(true))])
        expectInvalid([property("aspectRatio", .number(0))])
        expectInvalid([property("minWidth", .number(100)), property("maxHeight", .number(2)),
            property("aspectRatio", .number(1)), property("aspectEnabled", .boolean(true))])
        expectInvalid([property("minWidth", .number(100)), property("minWidth", .number(100))],
            expected: .duplicatePropertyKey)
        expectInvalid([property("minWidth", .number(10))], kind: .text)
    }

    func testResponsiveContentConversionIsExplicitAtomicAndRestoresOverridesAndIDs() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[0].childIDs = [fixture.nodeID]
        fixture.document.pages[0].nodes[1].kind = .stack
        fixture.document.pages[0].nodes[1].childIDs = [fixture.secondNodeID]
        applyStructuralDefaults(for: .stack, to: &fixture.document.pages[0].nodes[1])
        fixture.document.pages[0].nodes[2].kind = .text
        fixture.document.pages[0].nodes[2].parent = .node(fixture.nodeID)
        let override = NodeProperty(key: .init(rawValue: ResponsiveGeometryResolver.key(.height, breakpoint: .mobile)),
            value: .number(280), origin: .authored)
        fixture.document.pages[0].nodes[2].properties.append(override)
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        let selected = [fixture.nodeID, fixture.secondNodeID]
        let context = fixture.context(selectedIDs: selected)
        let command = SizingConstraintCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: selected, edit: .convertContent, cancelled: false)
        let prepared = try SizingConstraintCommandRegistry().prepare(command, in: session.document, context: context)
        XCTAssertEqual(prepared.applicableNodeIDs, selected, "An ancestor and child selection converts each node exactly once")
        try session.execute(prepared.documentCommand)
        let committed = session.document
        for node in committed.pages[0].nodes.dropFirst() {
            let sizing = CanonicalSizingConstraints.resolved(for: node)
            XCTAssertEqual(sizing.widthMode, .fill)
            XCTAssertEqual(sizing.heightMode, .hug)
            XCTAssertNil(node.insertionProperty(override.key.rawValue))
        }
        XCTAssertEqual(committed.pages[0].nodes.map(\.id), fixture.document.pages[0].nodes.map(\.id))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(committed)), committed)
        XCTAssertThrowsError(try SizingConstraintCommandRegistry().prepare(command, in: committed, context: context))
        try session.undo()
        XCTAssertEqual(session.document.pages, fixture.document.pages)
        XCTAssertEqual(session.document.pages[0].nodes[2].insertionProperty(override.key.rawValue), override)
        try session.redo()
        XCTAssertEqual(session.document.pages, committed.pages)
    }

    func testSizingModesCommitSeparatelyPreserveFallbackAndExactInverse() throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let context = fixture.context(selectedIDs: [fixture.nodeID])
        let original = session.document.pages
        func prepared(_ edit: SizingConstraintEdit, cancelled: Bool = false, revision: UInt64? = nil) throws -> SizingConstraintCommandRegistry.Prepared {
            try SizingConstraintCommandRegistry().prepare(.init(identity: .init(editID: GeometryInspectorEditID(),
                documentID: session.document.id, pageID: fixture.pageID,
                revision: revision ?? session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: [fixture.nodeID],
                edit: edit, cancelled: cancelled), in: session.document, context: context)
        }
        try session.execute(prepared(.setMode(.width, .fill)).documentCommand)
        let widthState = session.document.pages
        let widthID = try XCTUnwrap(widthState[0].nodes[1].insertionProperty(CanonicalSizingConstraints.prefix + "widthMode")?.id)
        try session.execute(prepared(.setMode(.height, .hug)).documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionGeometry, original[0].nodes[1].insertionGeometry)
        XCTAssertEqual(session.document.pages[0].nodes[1].id, fixture.nodeID)
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: session.document.pages[0].nodes[1]).heightMode, .hug)
        let committed = session.document
        XCTAssertThrowsError(try prepared(.setMode(.width, .hug)))
        XCTAssertThrowsError(try prepared(.setMode(.height, .fixed), cancelled: true))
        XCTAssertThrowsError(try prepared(.reset, revision: 0))
        XCTAssertEqual(session.document, committed)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(committed)), committed)
        try session.undo()
        XCTAssertEqual(session.document.pages, widthState)
        try session.undo()
        XCTAssertEqual(session.document.pages, original)
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty(CanonicalSizingConstraints.prefix + "widthMode")?.id, widthID)
        try session.redo()
        XCTAssertEqual(session.document.pages, committed.pages)
        try session.execute(prepared(.reset).documentCommand)
        XCTAssertEqual(session.document.pages, original)
        try session.undo()
        XCTAssertEqual(session.document.pages, committed.pages)
    }

    func testSizingConstraintsSetClampAspectResetAndExactHistory() throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let registry = SizingConstraintCommandRegistry()
        func node() -> DocumentNode { session.document.pages[0].nodes[1] }
        func command(_ edit: SizingConstraintEdit, cancelled: Bool = false,
                     revision: UInt64? = nil) -> SizingConstraintCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: revision ?? session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], edit: edit, cancelled: cancelled)
        }
        func execute(_ edit: SizingConstraintEdit) throws {
            let prepared = try registry.prepare(command(edit), in: session.document,
                context: fixture.context(selectedIDs: [fixture.nodeID]))
            XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID])
            try session.execute(prepared.documentCommand)
        }
        try execute(.set(.minWidth, 150))
        XCTAssertEqual(node().insertionGeometry?.frame.size.width, 150)
        let minID = try XCTUnwrap(node().insertionProperty(CanonicalSizingConstraints.prefix + "minWidth")?.id)
        try execute(.setAspectEnabled(true))
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: node()).aspectRatio, 150.0 / 80.0)
        let geometry = GeometryInspectorCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: session.document.id, pageID: fixture.pageID, revision: session.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], field: .width, value: 200, provenance: .automation)
        let numeric = try GeometryInspectorCommandRegistry().prepare(geometry, in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID]))
        try session.execute(numeric.documentCommand)
        XCTAssertEqual(node().insertionGeometry?.frame.size.width, 200)
        XCTAssertEqual(node().insertionGeometry?.frame.size.height ?? 0, 200 / (150.0 / 80.0), accuracy: 0.0001)
        try execute(.set(.maxWidth, 160))
        XCTAssertEqual(node().insertionGeometry?.frame.size.width, 160)
        let resize = GeometryTransformCommand(identity: .init(sessionID: TransformSessionID(),
            documentID: session.document.id, pageID: fixture.pageID,
            revision: session.document.revision, sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: [fixture.nodeID],
            operation: .resize(handle: .left, delta: .init(dx: 40, dy: 0), constraint: .none),
            provenance: .automation)
        let resized = try TransformCommandRegistry().prepare(resize, in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID]))
        XCTAssertEqual(resized.geometries[0].preview.size.width, 150)
        XCTAssertEqual(resized.geometries[0].preview.origin.x, 20)
        try session.execute(resized.documentCommand)
        XCTAssertEqual(node().insertionGeometry?.frame.size.width, 150)
        XCTAssertThrowsError(try registry.prepare(command(.set(.minWidth, 500)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(.set(.minHeight, .nan)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(.reset, cancelled: true),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try registry.prepare(command(.reset, revision: 0),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        let beforeReset = session.document
        try execute(.reset)
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: node()), .unconstrained)
        try session.undo()
        XCTAssertEqual(session.document.pages, beforeReset.pages)
        XCTAssertEqual(node().insertionProperty(CanonicalSizingConstraints.prefix + "minWidth")?.id, minID)
        try session.redo()
        XCTAssertEqual(CanonicalSizingConstraints.resolved(for: node()), .unconstrained)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testSizingConstraintMixedSelectionSkipsTextAndPreservesIdentity() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[2].kind = .text
        let originalText = fixture.document.pages[0].nodes[2]
        let session = DocumentSession(document: fixture.document)
        let selected = [fixture.nodeID, originalText.id]
        let context = fixture.context(selectedIDs: selected)
        let command = SizingConstraintCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: session.document.id, pageID: fixture.pageID,
            revision: session.document.revision, sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: selected,
            edit: .set(.maxWidth, 180), cancelled: false)
        let prepared = try SizingConstraintCommandRegistry().prepare(command,
            in: session.document, context: context)
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(prepared.skippedNodeIDs, [originalText.id])
        try session.execute(prepared.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[2], originalText)
        XCTAssertEqual(session.document.pages[0].nodes[1].id, fixture.nodeID)
        try session.undo()
        XCTAssertEqual(session.document.pages, fixture.document.pages)
    }

    // SF-0509-001...005 — one stable local token propagates to bound solid
    // fills while exact history and the literal fallback remain intact.
    func testLocalColorTokenCreateBindRecolorUnbindHistoryAndPersistence() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted))
        let session = DocumentSession(document: fixture.document)
        let registry = LocalColorTokenCommandRegistry.self
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#204060FF"))
        func prepare(_ edit: LocalColorTokenEdit, ids: [NodeID] = []) throws -> DocumentCommand {
            try registry.prepare(edit, in: session.document, expectedDocumentID: session.document.id,
                expectedRevision: session.document.revision, pageID: fixture.pageID, selectedNodeIDs: ids)
        }
        try session.execute(prepare(.create(name: "Brand", color: blue)))
        let token = try XCTUnwrap(session.document.colorTokens.first)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try prepare(.create(name: "brand", color: blue)))
        XCTAssertThrowsError(try prepare(.create(name: " ", color: blue)))
        try session.execute(prepare(.bind(token.id), ids: [fixture.nodeID]))
        func node() -> DocumentNode { session.document.pages[0].nodes[1] }
        XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node(), in: session.document).last?.solidColor, blue)
        XCTAssertEqual(LocalColorTokenResolver.fillValue(nodes: [node()], in: session.document), .single(blue, .authored))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: node()).last?.solidColor, .legacySurface)
        let literalEdit = DesignFillLayerCommand(
            identity: .init(documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .replaceSolid(blue),
            provenance: .automation, cancelled: false)
        XCTAssertThrowsError(try DesignInspectorCommandRegistry().prepare(literalEdit,
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])))
        XCTAssertThrowsError(try prepare(.delete(token.id)))
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#C02030E0"))
        try session.execute(prepare(.update(token.id, name: "Accent", color: red)))
        XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node(), in: session.document).last?.solidColor, red)
        XCTAssertTrue(LocalColorTokenResolver.status(for: node(), in: session.document)?.contains("Accent") == true)
        try session.undo()
        XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node(), in: session.document).last?.solidColor, blue)
        try session.redo()
        XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node(), in: session.document).last?.solidColor, red)
        try session.execute(prepare(.unbind, ids: [fixture.nodeID]))
        XCTAssertNil(LocalColorTokenBinding.id(for: node()))
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: node()).last?.solidColor, red)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened, session.document)
        try session.undo()
        XCTAssertEqual(LocalColorTokenBinding.id(for: node()), token.id)
        try session.redo()
        try session.execute(prepare(.delete(token.id)))
        XCTAssertTrue(session.document.colorTokens.isEmpty)
    }

    func testLocalColorTokenSchemaEightMigrationAndStrictCurrentDecode() throws {
        let fixture = makeFixture()
        let encoded = try DocumentSerializer.encode(fixture.document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var document = try XCTUnwrap(envelope["document"] as? [String: Any])
        document.removeValue(forKey: "colorTokens")
        document.removeValue(forKey: "websiteMetadata")
        envelope["schemaVersion"] = 8
        envelope["document"] = document
        let historical = try JSONSerialization.data(withJSONObject: envelope)
        let migrated = try DocumentSerializer.decode(historical)
        XCTAssertEqual(migrated.id, fixture.document.id)
        XCTAssertEqual(migrated.pages, fixture.document.pages)
        XCTAssertTrue(migrated.colorTokens.isEmpty)
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#204060FF"))
        let session = DocumentSession(document: migrated)
        try session.execute(LocalColorTokenCommandRegistry.prepare(.create(name: "Brand", color: color),
            in: session.document, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision, pageID: fixture.pageID))
        let roundTrip = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(roundTrip, session.document)
        XCTAssertEqual(roundTrip.colorTokens.first?.name, "Brand")
        var current = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(session.document)) as? [String: Any])
        var currentDocument = try XCTUnwrap(current["document"] as? [String: Any])
        var tokens = try XCTUnwrap(currentDocument["colorTokens"] as? [[String: Any]])
        tokens[0]["unexpected"] = true
        currentDocument["colorTokens"] = tokens
        current["document"] = currentDocument
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: current)))
    }

    func testLocalColorTokenRegistryRejectsStaleCancelledAndInapplicableEditsWithoutMutation() throws {
        let fixture = makeFixture()
        let document = fixture.document
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#204060FF"))
        let registry = LocalColorTokenCommandRegistry.self
        let original = try DocumentSerializer.encode(document)
        XCTAssertThrowsError(try registry.prepare(.create(name: "Brand", color: color), in: document,
            expectedDocumentID: DocumentID(), expectedRevision: document.revision, pageID: fixture.pageID))
        XCTAssertThrowsError(try registry.prepare(.create(name: "Brand", color: color), in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision + 1, pageID: fixture.pageID))
        XCTAssertThrowsError(try registry.prepare(.create(name: "Brand", color: color), in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision,
            pageID: fixture.pageID, cancelled: true))
        XCTAssertThrowsError(try registry.prepare(.bind(ColorTokenID()), in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision,
            pageID: fixture.pageID, selectedNodeIDs: [fixture.nodeID]))
        XCTAssertThrowsError(try registry.prepare(.unbind, in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision,
            pageID: fixture.pageID, selectedNodeIDs: [fixture.nodeID, fixture.nodeID]))
        XCTAssertEqual(try DocumentSerializer.encode(document), original)
    }

    func testLocalColorTokenResolvesAllSupportedStructuralKindsAndMissingFallback() throws {
        let fixture = makeFixture()
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#204060FF"))
        let token = LocalColorToken(name: "Brand", color: color)
        var document = fixture.document
        document.colorTokens = [token]
        for kind in [NodeKind.frame, .section, .stack, .grid] {
            let node = DocumentNode(kind: kind, name: "Structure", parent: .page(fixture.pageID), properties: [
                .init(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted),
                .init(key: .init(rawValue: LocalColorTokenBinding.key), value: .string(token.id.description), origin: .authored),
            ])
            XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node, in: document).last?.solidColor, color)
            document.colorTokens = []
            XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: node, in: document).last?.solidColor, .legacySurface)
            XCTAssertTrue(LocalColorTokenResolver.status(for: node, in: document)?.contains("Missing") == true)
            document.colorTokens = [token]
        }
    }
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
        let clampedResize = try registry.prepare(
            fixture.command(operation: .resize(
                handle: .left,
                delta: .init(dx: 500, dy: 0),
                constraint: .none
            )),
            in: fixture.document,
            context: fixture.context
        )
        XCTAssertEqual(clampedResize.geometries[0].preview.size.width, TransformPolicy.minimumDimension)
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
    func testInspectorPropertyClipboardStrictTypedRoundTripAndInvalidNeutrality() throws {
        for field in GeometryInspectorField.allCases {
            let value = InspectorGeometryTransfer(field: field, value: field.requiresPositiveValue ? 120 : -24)
            XCTAssertEqual(try InspectorGeometryTransfer.decode(value.encoded()), value)
        }
        for text in ["{}", "[]", "{\"version\":2,\"field\":\"width\",\"value\":120}",
                     "{\"version\":1,\"field\":\"script\",\"value\":120}",
                     "{\"field\":\"width\",\"value\":true,\"version\":1}",
                     "{\"field\":\"width\",\"value\":0,\"version\":1}",
                     "{\"field\":\"width\",\"value\":120,\"value\":200,\"version\":1}",
                     "{\"field\":\"width\",\"value\":120,\"version\":1,\"command\":\"execute\"}"] {
            XCTAssertThrowsError(try InspectorGeometryTransfer.decode(Data(text.utf8)))
        }
        XCTAssertThrowsError(try InspectorGeometryTransfer.decode(Data(repeating: 32, count: 2049)))
        for invalid in [Double.nan, Double.infinity, -1, LayoutPolicy.maximumDimension + 1] {
            XCTAssertThrowsError(try InspectorGeometryTransfer(field: .width, value: invalid).encoded())
        }
    }

    func testInspectorPropertyPasteAtomicHistoryPersistenceAndResponsiveIsolation() throws {
        var fixture = makeFixture()
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let live = DocumentSession(document: fixture.document)
        let copied = InspectorGeometryTransfer(field: .x, value: 42)
        let prepared = try copied.prepare(identity: fixture.inspectorCommand(field: .x, value: 42).identity,
            orderedNodeIDs: fixture.selectedIDs, document: fixture.document, context: fixture.context, breakpoint: .desktop)
        try live.execute(prepared.documentCommand)
        XCTAssertEqual(live.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 42)
        XCTAssertEqual(live.document.nodeGeometry(fixture.secondNodeID)?.frame.origin.x, 42)
        XCTAssertEqual(live.historySnapshot().undoEntries.count, 1)
        let authored = live.document
        try live.undo(); XCTAssertEqual(live.document.pages, fixture.document.pages)
        try live.redo(); XCTAssertEqual(live.document.pages, authored.pages)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(live.document)), live.document)
        let tablet = try copied.prepare(identity: fixture.inspectorCommand(field: .x, value: 42).identity,
            orderedNodeIDs: fixture.selectedIDs, document: fixture.document, context: fixture.context, breakpoint: .tablet)
        let responsive = DocumentSession(document: fixture.document)
        try responsive.execute(tablet.documentCommand)
        XCTAssertEqual(responsive.document.nodeGeometry(fixture.nodeID)?.frame.origin.x, 10)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: try XCTUnwrap(responsive.document.pages.first?.nodes.first { $0.id == fixture.nodeID }), breakpoint: .tablet)?.0, 42)
    }

    func testInspectorPropertyPasteRejectsStaleCancelledAndSelectionMismatch() throws {
        var fixture = makeFixture()
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let copied = InspectorGeometryTransfer(field: .x, value: 42)
        let identity = fixture.inspectorCommand(field: .x, value: 42).identity
        XCTAssertThrowsError(try copied.prepare(identity: identity, orderedNodeIDs: fixture.selectedIDs,
            document: fixture.document, context: fixture.context, breakpoint: .desktop,
            cancellation: .init(isCancelled: { true })))
        XCTAssertThrowsError(try copied.prepare(identity: fixture.inspectorCommand(field: .x, value: 42, revision: fixture.document.revision + 1).identity,
            orderedNodeIDs: fixture.selectedIDs, document: fixture.document, context: fixture.context, breakpoint: .desktop))
        XCTAssertThrowsError(try copied.prepare(identity: identity, orderedNodeIDs: [fixture.nodeID],
            document: fixture.document, context: fixture.context, breakpoint: .desktop))
        XCTAssertEqual(GeometryInspectorCommandRegistry().value(for: .x, in: fixture.document, context: fixture.context), .mixed)
        var subset = makeFixture(selectedIDs: [])
        subset.document.pages[0].nodes[2].kind = .form
        subset.document.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == "layout.y" }
        subset.selectedIDs = [subset.nodeID, subset.secondNodeID]
        let partial = try InspectorGeometryTransfer(field: .y, value: 55).prepare(
            identity: subset.inspectorCommand(field: .y, value: 55).identity,
            orderedNodeIDs: subset.selectedIDs, document: subset.document, context: subset.context, breakpoint: .desktop)
        XCTAssertEqual(partial.skippedNodeIDs, [subset.secondNodeID])
        let session = DocumentSession(document: subset.document)
        let untouched = subset.document.pages[0].nodes[2]
        try session.execute(partial.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[2], untouched)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
    }

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
        for kind in [NodeKind.frame, .text, .section, .stack, .grid, .component] {
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
        XCTAssertTrue(GeometryInspectorCommandRegistry.supportsFixedGeometry(.image))

        var unsupported = makeFixture()
        unsupported.document.pages[0].nodes[1].kind = .component
        // Components now support fixed geometry. An omitted requested property
        // still has no base value to edit and must remain mutation-neutral.
        unsupported.document.pages[0].nodes[1].properties.removeAll { $0.key.rawValue == "layout.x" }
        XCTAssertThrowsError(try registry.prepare(
            unsupported.inspectorCommand(field: .x, value: 20),
            in: unsupported.document,
            context: unsupported.context
        )) { XCTAssertEqual($0 as? GeometryInspectorError, .noApplicableTargets) }

        var subset = makeFixture(selectedIDs: [])
        subset.document.pages[0].nodes[2].kind = .component
        subset.document.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == "layout.y" }
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

    // SF-0601-001...006, SF-0601-008; SF-0602-001...006, SF-0602-008
    func testResponsiveGeometryOverridesResolveAtomicallyResetAndRoundTrip() throws {
        var fixture = makeFixture()
        let registry = GeometryInspectorCommandRegistry()
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 1_440), .desktop)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 768), .tablet)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 390), .mobile)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 1_023.9), .tablet)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 599.9), .mobile)
        XCTAssertEqual(Set(ResponsiveBreakpoint.allCases.map(\.id)).count, 3)

        var tablet = fixture.inspectorCommand(field: .x, value: 84, breakpoint: .tablet)
        let prepared = try registry.prepare(tablet, in: fixture.document, context: fixture.context)
        XCTAssertEqual(prepared.breakpoint, .tablet)
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        fixture.document = session.document
        let node = fixture.document.pages[0].nodes.first { $0.id == fixture.nodeID }!
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: node, breakpoint: .desktop)?.0, 10)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: node, breakpoint: .tablet)?.0, 84)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: node, breakpoint: .mobile)?.0, 10)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: node, breakpoint: .tablet)?.2, .override(.tablet))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(fixture.document)), fixture.document)

        _ = try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.nodeID }?
            .insertionProperty(ResponsiveGeometryResolver.key(.x, breakpoint: .tablet)))
        _ = try session.redo()
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x,
            node: session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!, breakpoint: .tablet)?.0, 84)

        fixture.document = session.document
        tablet = fixture.inspectorCommand(field: .x, value: 0, breakpoint: .tablet, removesOverride: true)
        let reset = try registry.prepare(tablet, in: fixture.document, context: fixture.context)
        _ = try session.execute(reset.documentCommand)
        let resetNode = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: resetNode, breakpoint: .tablet)?.0, 10)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .x, node: resetNode, breakpoint: .tablet)?.2, .baseDesktop)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 2)
    }

    func testResponsiveGeometryRejectsStaleCancelledAndPreservesIndependentBreakpoints() throws {
        var fixture = makeFixture()
        let registry = GeometryInspectorCommandRegistry()
        var mobile = fixture.inspectorCommand(field: .width, value: 180, breakpoint: .mobile)
        XCTAssertThrowsError(try registry.prepare(
            fixture.inspectorCommand(field: .width, value: 180, revision: fixture.document.revision + 1,
                breakpoint: .mobile), in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? GeometryInspectorError, .staleRevision) }
        XCTAssertThrowsError(try registry.prepare(mobile, in: fixture.document, context: fixture.context,
            cancellation: .init { true })) { XCTAssertEqual($0 as? GeometryInspectorError, .cancelled) }
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(try registry.prepare(mobile, in: fixture.document, context: fixture.context).documentCommand)
        fixture.document = session.document
        let tablet = fixture.inspectorCommand(field: .width, value: 300, breakpoint: .tablet)
        _ = try session.execute(try registry.prepare(tablet, in: fixture.document, context: fixture.context).documentCommand)
        let node = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .desktop)?.0, 120)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .tablet)?.0, 300)
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .mobile)?.0, 180)

        var malformed = session.document
        malformed.pages[0].nodes[1].properties.append(NodeProperty(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.height, breakpoint: .mobile)),
            value: .string("not-a-number"), origin: .authored
        ))
        XCTAssertThrowsError(try malformed.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidResponsiveGeometryState)
        }

        mobile = fixture.inspectorCommand(field: .width, value: 200, breakpoint: .mobile)
        let record = GeometryInspectorDiagnosticFactory.make(
            command: mobile, durationMilliseconds: 0.1,
            resultRevision: nil, result: .stale, failure: .staleRevision
        )
        XCTAssertEqual(record.requirementIDs, GeometryInspectorCommandRegistry.responsiveRequirementIDs.sorted())
        XCTAssertFalse(String(describing: record).contains(fixture.nodeID.description))
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
        let disabledShadow = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .shadowEnabled(false)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        _ = try session.execute(disabledShadow.documentCommand)

        func currentStyle() throws -> CanonicalBoxStyle {
            let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
            return try XCTUnwrap(DesignBoxStyleCommandRegistry.resolvedStyle(for: node))
        }
        XCTAssertEqual(try currentStyle(), .init(border: border, cornerRadius: 14, shadow: shadow, shadowEnabled: false))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let propertyIDs = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(DesignBoxStyleCommandRegistry.namespace) }.map(\.id)
        try session.undo()
        XCTAssertNil(try currentStyle().shadowEnabled)
        try session.redo()
        XCTAssertEqual(try currentStyle().shadowEnabled, false)
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
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .shadowEnabled(true), cancelled: true),
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

    // SF-0506-001...005/008 — Frame/Section content padding and clipping
    // share the existing box-style transaction; unsupported structural kinds
    // cannot inherit a primary Frame's content-box value.
    func testDesignBoxStyleContentPaddingAndClipAreTypedReversibleAndScoped() throws {
        var fixture = makeFixture(selectedIDs: [NodeID]())
        let frameIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.nodeID })
        fixture.document.pages[0].nodes[frameIndex].kind = .frame
        let registry = DesignBoxStyleCommandRegistry()
        func command(_ document: CanonicalDocument, ids: [NodeID], edit: DesignBoxStyleEdit, cancelled: Bool = false) -> DesignBoxStyleCommand {
            .init(identity: .init(documentID: document.id, pageID: fixture.pageID, revision: document.revision,
                                  sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                  orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let session = DocumentSession(document: fixture.document)
        let padding = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .padding(32)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        XCTAssertEqual(padding.applicableNodeIDs, [fixture.nodeID])
        XCTAssertTrue(padding.skippedNodeIDs.isEmpty)
        XCTAssertFalse(DesignBoxStyleCommandRegistry.supports(.padding(12), kind: .stack))
        XCTAssertFalse(DesignBoxStyleCommandRegistry.supports(.clipsContent(true), kind: .grid))
        _ = try session.execute(padding.documentCommand)
        let clipped = try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .clipsContent(true)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )
        _ = try session.execute(clipped.documentCommand)
        let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.padding, 32)
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: node)?.clipsContent, true)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        let afterUndo = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertNil(DesignBoxStyleCommandRegistry.resolvedStyle(for: afterUndo)?.clipsContent)
        try session.redo()
        let afterRedo = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(DesignBoxStyleCommandRegistry.resolvedStyle(for: afterRedo)?.clipsContent, true)
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .padding(.infinity)),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
        XCTAssertThrowsError(try registry.prepare(
            command(session.document, ids: [fixture.nodeID], edit: .clipsContent(false), cancelled: true),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .cancelled) }
        var malformed = session.document
        let propertyIndex = try XCTUnwrap(malformed.pages[0].nodes[frameIndex].properties.firstIndex {
            $0.key.rawValue == "style.box.v1.padding.uniform"
        })
        malformed.pages[0].nodes[frameIndex].properties[propertyIndex].value = .string("not-a-number")
        XCTAssertEqual(DesignBoxStyleCommandRegistry.selectionValue(nodes: [malformed.pages[0].nodes[frameIndex]]),
                       .unavailable("A selected object has invalid persisted content-box data and cannot be edited safely."))
        XCTAssertThrowsError(try registry.prepare(
            command(malformed, ids: [fixture.nodeID], edit: .padding(12)), in: malformed,
            context: fixture.context(selectedIDs: [fixture.nodeID])
        )) { XCTAssertEqual($0 as? DesignBoxStyleError, .invalidValue) }
    }

    // SF-0507-002/003/005: installed family+weight is one authored
    // choice, preserving semantics, per-node metrics, fluid intent and exact IDs.
    func testFontFamilyWeightChoiceIsAtomicForMixedTextAndPreservesExactHistory() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .text
        fixture.document.pages[0].nodes[2].kind = .button
        let family = NodeProperty(key: .init(rawValue: CanonicalTypography.namespace + "family"),
            value: .string("Missing prior family"), origin: .defaulted)
        let weight = NodeProperty(key: .init(rawValue: CanonicalTypography.namespace + "weight"),
            value: .string("bold"), origin: .defaulted)
        let fluid = NodeProperty(key: .init(rawValue: CanonicalFluidValueCodec.key(.fontSize)),
            value: .string(try CanonicalFluidValueCodec.encode(.init(minimum: 10, preferred: 14, maximum: 18), target: .fontSize)))
        fixture.document.pages[0].nodes[1].properties += [family, weight, fluid,
            .init(key: .init(rawValue: CanonicalSemanticElement.key), value: .string("h2")),
            .init(key: .init(rawValue: "content.text"), value: .string("Heading\nSecond line"))]
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID, fixture.rootID]
        let session = DocumentSession(document: fixture.document), registry = TypographyCommandRegistry()
        func request(_ choice: CanonicalFontWeight) -> TypographyCommand {
            .init(identity: .init(documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: fixture.selectedIDs, edit: .fontFace(family: "System", weight: choice), provenance: .picker, cancelled: false)
        }
        let original = session.document.pages
        let edit = try registry.prepare(request(.medium), in: session.document, context: fixture.context)
        XCTAssertEqual(edit.applicableNodeIDs, [fixture.nodeID, fixture.secondNodeID])
        XCTAssertEqual(edit.skippedNodeIDs, [fixture.rootID])
        try session.execute(edit.documentCommand)
        let authored = session.document.pages
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        for node in authored[0].nodes[1...2] {
            let style = try XCTUnwrap(TypographyCommandRegistry.resolvedTypography(for: node))
            XCTAssertEqual(style.family, "System"); XCTAssertEqual(style.weight, .medium)
            XCTAssertEqual(style.size, 14); XCTAssertEqual(style.lineHeight, 17); XCTAssertEqual(style.tracking, 0)
        }
        XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: authored[0].nodes[1])?.alignment, .leading)
        XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: authored[0].nodes[2])?.alignment, .center)
        XCTAssertEqual(authored[0].nodes[1].insertionProperty(family.key.rawValue)?.id, family.id)
        XCTAssertEqual(authored[0].nodes[1].insertionProperty(weight.key.rawValue)?.id, weight.id)
        XCTAssertEqual(authored[0].nodes[1].insertionProperty(family.key.rawValue)?.origin, .authored)
        XCTAssertEqual(authored[0].nodes[1].insertionProperty(fluid.key.rawValue), fluid)
        XCTAssertEqual(authored[0].nodes[1].insertionStringProperty(CanonicalSemanticElement.key), "h2")
        XCTAssertEqual(authored[0].nodes.map(\.id), original[0].nodes.map(\.id))
        XCTAssertEqual(authored[0].nodes[1].insertionGeometry, original[0].nodes[1].insertionGeometry)
        XCTAssertEqual(authored[0].nodes[0], original[0].nodes[0])
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try registry.prepare(request(.medium), in: session.document,
            context: fixture.with(document: session.document).context)) { XCTAssertEqual($0 as? TypographyCommandError, .noChanges) }
        try session.undo(); XCTAssertEqual(session.document.pages, original)
        try session.redo(); XCTAssertEqual(session.document.pages, authored)
        try session.undo()
        try session.execute(try registry.prepare(request(.bold), in: session.document,
            context: fixture.with(document: session.document).context).documentCommand)
        XCTAssertTrue(session.historySnapshot().redoEntries.isEmpty)
    }

    // SF-0507-004/005: syntax/stale/cancel/unavailable failures never
    // leave a new family with the previous weight or mutate a partial subset.
    func testFontFamilyWeightChoiceRejectsInvalidStaleCancelledAndUnavailableTargets() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .text
        let registry = TypographyCommandRegistry(), before = fixture.document
        func request(_ family: String = "System", cancelled: Bool = false,
                     revision: UInt64? = nil, ids: [NodeID]? = nil) -> TypographyCommand {
            .init(identity: .init(documentID: before.id, pageID: fixture.pageID,
                revision: revision ?? before.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids ?? fixture.selectedIDs, edit: .fontFace(family: family, weight: .semibold),
                provenance: .keyboard, cancelled: cancelled)
        }
        for invalid in ["", " System", "System ", "Bad\nFamily", String(repeating: "x", count: 129)] {
            XCTAssertThrowsError(try registry.prepare(request(invalid), in: before, context: fixture.context)) {
                XCTAssertEqual($0 as? TypographyCommandError, .invalidValue)
            }
        }
        XCTAssertThrowsError(try registry.prepare(request(cancelled: true), in: before, context: fixture.context)) {
            XCTAssertEqual($0 as? TypographyCommandError, .cancelled)
        }
        XCTAssertThrowsError(try registry.prepare(request(revision: before.revision + 1), in: before, context: fixture.context)) {
            XCTAssertEqual($0 as? TypographyCommandError, .stale)
        }
        XCTAssertThrowsError(try registry.prepare(request(ids: [fixture.secondNodeID]), in: before, context: fixture.context)) {
            XCTAssertEqual($0 as? TypographyCommandError, .stale)
        }
        XCTAssertThrowsError(try registry.prepare(request(), in: before,
            context: fixture.context(selectedIDs: fixture.selectedIDs, availableIDs: [])))
        for key in ["locked", "hidden"] {
            var blocked = fixture
            blocked.document.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: key), value: .boolean(true)))
            XCTAssertThrowsError(try registry.prepare(request(), in: blocked.document, context: blocked.context))
        }
        let unsupported = fixture.context(selectedIDs: [fixture.secondNodeID])
        XCTAssertThrowsError(try registry.prepare(request(ids: [fixture.secondNodeID]), in: before, context: unsupported)) {
            XCTAssertEqual($0 as? TypographyCommandError, .noApplicableTargets)
        }
        XCTAssertNil(CanonicalFontWeight(rawValue: "unlisted-weight"))
        XCTAssertEqual(fixture.document, before)
    }

    func testTypographyRegistryValidatesMixesResetsPersistsAndUndoRedo() throws {
        var fixture = makeFixture(selectedIDs: [NodeID]())
        fixture.document.pages[0].nodes[1].kind = .text
        fixture.document.pages[0].nodes[2].kind = .frame
        let registry = TypographyCommandRegistry()
        func command(
            _ document: CanonicalDocument,
            ids: [NodeID],
            edit: TypographyEdit,
            cancelled: Bool = false,
            documentID: DocumentID? = nil
        ) -> TypographyCommand {
            .init(identity: .init(
                documentID: documentID ?? document.id, pageID: fixture.pageID,
                revision: document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration
            ), orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let mixed = try registry.prepare(
            command(fixture.document, ids: [fixture.nodeID, fixture.secondNodeID], edit: .family("Menlo")),
            in: fixture.document,
            context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])
        )
        XCTAssertEqual(mixed.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(mixed.skippedNodeIDs, [fixture.secondNodeID])
        XCTAssertFalse(mixed.skippedReasons.values.joined().contains(fixture.nodeID.description))

        var compatibleDocument = fixture.document
        compatibleDocument.pages[0].nodes[2].kind = .text
        let compatibleFixture = fixture.with(document: compatibleDocument)
        let compatible = try registry.prepare(
            command(compatibleDocument, ids: [fixture.nodeID, fixture.secondNodeID], edit: .size(19)),
            in: compatibleDocument,
            context: compatibleFixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])
        )
        XCTAssertEqual(compatible.applicableNodeIDs, [fixture.nodeID, fixture.secondNodeID])
        XCTAssertTrue(compatible.skippedNodeIDs.isEmpty)
        let compatibleSession = DocumentSession(document: compatibleDocument)
        _ = try compatibleSession.execute(compatible.documentCommand)
        XCTAssertEqual(
            compatibleSession.document.pages[0].nodes.filter { $0.id == fixture.nodeID || $0.id == fixture.secondNodeID }
                .compactMap { TypographyCommandRegistry.resolvedTypography(for: $0) }.map(\.size),
            [19, 19]
        )
        try compatibleSession.undo()
        XCTAssertEqual(
            compatibleSession.document.pages[0].nodes.filter { $0.id == fixture.nodeID || $0.id == fixture.secondNodeID }
                .compactMap { TypographyCommandRegistry.resolvedTypography(for: $0) }.map(\.size),
            [14, 14]
        )
        try compatibleSession.redo()

        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(mixed.documentCommand)
        for (edit, expected) in [
            (TypographyEdit.weight(.bold), CanonicalTypography(family: "Menlo", weight: .bold, size: 14, lineHeight: 17, tracking: 0, alignment: .leading)),
            (.size(24), CanonicalTypography(family: "Menlo", weight: .bold, size: 24, lineHeight: 17, tracking: 0, alignment: .leading)),
            (.lineHeight(30), CanonicalTypography(family: "Menlo", weight: .bold, size: 24, lineHeight: 30, tracking: 0, alignment: .leading)),
            (.tracking(1.5), CanonicalTypography(family: "Menlo", weight: .bold, size: 24, lineHeight: 30, tracking: 1.5, alignment: .leading)),
            (.alignment(.center), CanonicalTypography(family: "Menlo", weight: .bold, size: 24, lineHeight: 30, tracking: 1.5, alignment: .center)),
        ] {
            let prepared = try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: edit), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
            _ = try session.execute(prepared.documentCommand)
            let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
            XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: node), expected)
        }
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)
        let propertyIDs = session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(TypographyCommandRegistry.namespace) }.map(\.id)
        try session.undo(); try session.redo()
        XCTAssertEqual(propertyIDs, session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(TypographyCommandRegistry.namespace) }.map(\.id))

        let reset = try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .reset), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
        _ = try session.execute(reset.documentCommand)
        XCTAssertEqual(TypographyCommandRegistry.resolvedTypography(for: session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!), .defaultValue)
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == fixture.nodeID }!.properties
            .filter { $0.key.rawValue.hasPrefix(TypographyCommandRegistry.namespace) }.map(\.id), propertyIDs)

        for edit in [TypographyEdit.size(.nan), .size(0), .lineHeight(.infinity), .tracking(101), .family(" bad "), .family("Bad\nFamily")] {
            XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: edit), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
                XCTAssertEqual($0 as? TypographyCommandError, .invalidValue)
            }
        }
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .size(18), cancelled: true), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? TypographyCommandError, .cancelled)
        }
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .size(18), documentID: DocumentID()), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? TypographyCommandError, .stale)
        }
    }

    // SF-1203-001...006 — semantic tags are provenance-aware canonical
    // metadata and use the same identity-gated history boundary as Inspector
    // appearance and typography edits.
    func testSemanticElementRegistryValidatesMixedSelectionAndExactHistory() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .text
        let registry = SemanticElementCommandRegistry()
        func command(_ document: CanonicalDocument, ids: [NodeID], edit: SemanticElementEdit, cancelled: Bool = false) -> SemanticElementCommand {
            .init(identity: .init(documentID: document.id, pageID: fixture.pageID, revision: document.revision,
                                  sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                  orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        let initial = fixture.document.pages[0].nodes[1]
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: initial)?.0, .div)
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: initial)?.1, .defaulted)

        let mixed = try registry.prepare(command(fixture.document, ids: [fixture.nodeID, fixture.secondNodeID], edit: .set(.article)), in: fixture.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID]))
        XCTAssertEqual(mixed.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(mixed.skippedNodeIDs, [fixture.secondNodeID])
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(mixed.documentCommand)
        var node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        let property = try XCTUnwrap(node.insertionProperty(CanonicalSemanticElement.key))
        XCTAssertEqual(property.origin, .authored)
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: node)?.0, .article)
        let propertyID = property.id
        try session.undo()
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertNil(node.insertionProperty(CanonicalSemanticElement.key))
        try session.redo()
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(node.insertionProperty(CanonicalSemanticElement.key)?.id, propertyID)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        let reset = try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .reset), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
        _ = try session.execute(reset.documentCommand)
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertNil(node.insertionProperty(CanonicalSemanticElement.key))
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: node)?.0, .div)

        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .set(.h1)), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? SemanticElementCommandError, .noApplicableTargets)
        }
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .set(.article), cancelled: true), in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? SemanticElementCommandError, .cancelled)
        }
        let stale = SemanticElementCommand(identity: .init(documentID: DocumentID(), pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: [fixture.nodeID], edit: .set(.article), provenance: .automation, cancelled: false)
        XCTAssertThrowsError(try registry.prepare(stale, in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? SemanticElementCommandError, .stale)
        }
    }

    // SF-AUTHORING-098, SF-0701-002/004, SF-0702-002/004 — general
    // accessibility metadata shares the identity-gated atomic Inspector path,
    // preserves PropertyID through exact history, and skips dedicated schemas.
    func testAccessibilityMetadataRegistryCommitsMixedSubsetAndExactHistory() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[1].kind = .frame
        fixture.document.pages[0].nodes[2].kind = .form
        let registry = AccessibilityMetadataCommandRegistry()
        func command(_ document: CanonicalDocument, ids: [NodeID], edit: AccessibilityMetadataEdit,
                     cancelled: Bool = false) -> AccessibilityMetadataCommand {
            .init(identity: .init(documentID: document.id, pageID: fixture.pageID,
                                  revision: document.revision, sceneID: fixture.sceneID,
                                  rendererGeneration: fixture.rendererGeneration),
                  orderedNodeIDs: ids, edit: edit, provenance: .automation, cancelled: cancelled)
        }
        XCTAssertEqual(AccessibilityMetadataCommandRegistry.selectionValue(
            field: .name, nodes: [fixture.document.pages[0].nodes[1]]), .single(nil, .defaulted))
        let prepared = try registry.prepare(command(fixture.document,
            ids: [fixture.nodeID, fixture.secondNodeID], edit: .set(.name, "Hero region")),
            in: fixture.document,
            context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID]))
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(prepared.skippedNodeIDs, [fixture.secondNodeID])
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(prepared.documentCommand)
        var node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        let property = try XCTUnwrap(node.insertionProperty(CanonicalAccessibilityMetadata.Field.name.key))
        XCTAssertEqual(property.value, .string("Hero region"))
        XCTAssertEqual(property.origin, .authored)
        try session.undo(); try session.redo()
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.nodeID })
        XCTAssertEqual(node.insertionProperty(CanonicalAccessibilityMetadata.Field.name.key)?.id, property.id)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        let reset = try registry.prepare(command(session.document, ids: [fixture.nodeID], edit: .reset),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID]))
        _ = try session.execute(reset.documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.nodeID }?
            .insertionProperty(CanonicalAccessibilityMetadata.Field.name.key))
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID],
            edit: .set(.help, String(repeating: "x", count: 513))), in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? AccessibilityMetadataCommandError, .invalid)
        }
        XCTAssertThrowsError(try registry.prepare(command(session.document, ids: [fixture.nodeID],
            edit: .set(.name, "Name"), cancelled: true), in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID]))) {
            XCTAssertEqual($0 as? AccessibilityMetadataCommandError, .cancelled)
        }
    }

    // SF-0502-003/006, SF-0503-003/006: inspection uses the same
    // viewport-dependent winner as layout, including partially applicable sets.
    func testContainerFluidSpacingInspectionUsesViewportAndReportsMixedValues() throws {
        var fixture = makeFixture()
        for (index, kind) in [(1, NodeKind.stack), (2, NodeKind.grid)] {
            fixture.document.pages[0].nodes[index].kind = kind
            applyStructuralDefaults(for: kind, to: &fixture.document.pages[0].nodes[index])
            let fluid = CanonicalFluidValue(minimum: 8, preferred: 16, maximum: 32)
            fixture.document.pages[0].nodes[index].properties.append(.init(
                key: .init(rawValue: CanonicalFluidValueCodec.key(.gap)),
                value: .string(try CanonicalFluidValueCodec.encode(fluid, target: .gap)), origin: .authored))
        }
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID, fixture.rootID]
        let before = fixture.document
        let registry = ContainerLayoutCommandRegistry()
        for width in [320.0, 390, 574, 768, 1024, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let fluid = try XCTUnwrap(CanonicalFluidValueCodec.value(for: .gap, node: fixture.document.pages[0].nodes[1]))
            let expected = try XCTUnwrap(fluid.0.resolved(viewportWidth: width))
            XCTAssertEqual(registry.value(for: .gap, in: fixture.document, context: fixture.context,
                breakpoint: breakpoint, viewportWidth: width),
                .single(.number(expected), .authored, applicableCount: 2, skippedCount: 1))
            for node in fixture.document.pages[0].nodes[1...2] {
                let resolved = try XCTUnwrap(ResponsiveContainerLayoutResolver.value(
                    for: .gap, node: node, breakpoint: breakpoint, viewportWidth: width))
                XCTAssertEqual(resolved.0, .number(expected))
                XCTAssertEqual(resolved.2, .fluid)
            }
        }
        XCTAssertEqual(fixture.document, before, "Inspection must not write sampled fluid values")
        fixture.document.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == CanonicalFluidValueCodec.key(.gap) }
        XCTAssertEqual(registry.value(for: .gap, in: fixture.document, context: fixture.context,
            breakpoint: .desktop, viewportWidth: 1440), .mixed(applicableCount: 2, skippedCount: 1))
        let key = ResponsiveContainerLayoutResolver.key(.gap, breakpoint: .tablet)
        for index in 1...2 {
            fixture.document.pages[0].nodes[index].properties.append(.init(
                key: .init(rawValue: key), value: .number(4), origin: .authored))
        }
        XCTAssertEqual(registry.value(for: .gap, in: fixture.document, context: fixture.context,
            breakpoint: .tablet, viewportWidth: 768),
            .single(.number(4), .authored, applicableCount: 2, skippedCount: 1))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .gap,
            node: fixture.document.pages[0].nodes[1], breakpoint: .tablet, viewportWidth: 768)?.2, .override(.tablet))
    }

    // SF-0502-003/005, SF-0503-003/005: fixed fallback edits cannot
    // silently replace fluid intent. Override/remove/fixed are separate history.
    func testContainerFluidSpacingCommandsPreserveOverridesAndExactHistory() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .stack
        applyStructuralDefaults(for: .stack, to: &fixture.document.pages[0].nodes[1])
        let fluid = CanonicalFluidValue(minimum: 8, preferred: 16, maximum: 32)
        let fluidProperty = NodeProperty(key: .init(rawValue: CanonicalFluidValueCodec.key(.gap)),
            value: .string(try CanonicalFluidValueCodec.encode(fluid, target: .gap)), origin: .authored)
        fixture.document.pages[0].nodes[1].properties.append(fluidProperty)
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let session = DocumentSession(document: fixture.document), registry = ContainerLayoutCommandRegistry()
        func command(_ value: ContainerLayoutValue?, breakpoint: ResponsiveBreakpoint = .desktop,
                     reset: Bool = false, cancelled: Bool = false,
                     revision: UInt64? = nil) -> ContainerLayoutCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: fixture.pageID,
                revision: revision ?? session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: fixture.selectedIDs,
                field: .gap, value: value, provenance: .keyboard, cancelled: cancelled,
                breakpoint: breakpoint, removesOverride: reset)
        }
        func prepare(_ value: ContainerLayoutCommand) throws -> PreparedContainerLayoutEdit {
            try registry.prepare(value, in: session.document, context: fixture.with(document: session.document).context)
        }
        let ignoredEdits: [ContainerLayoutValue?] = [.number(7), nil]
        for value in ignoredEdits {
            XCTAssertThrowsError(try prepare(command(value))) {
                XCTAssertEqual($0 as? ContainerLayoutError, .fluidValueWins)
            }
        }
        XCTAssertTrue(session.historySnapshot().undoEntries.isEmpty)
        XCTAssertThrowsError(try prepare(command(.number(7), cancelled: true))) {
            XCTAssertEqual($0 as? ContainerLayoutError, .cancelled)
        }
        XCTAssertThrowsError(try prepare(command(.number(.nan)))) {
            XCTAssertEqual($0 as? ContainerLayoutError, .invalidValue)
        }
        let oldRevision = session.document.revision
        let original = session.document.pages[0].nodes
        let edit = try prepare(command(.number(6), breakpoint: .tablet))
        XCTAssertEqual(edit.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(edit.skippedNodeIDs, [fixture.secondNodeID])
        try session.execute(edit.documentCommand)
        let authored = session.document.pages[0].nodes
        XCTAssertEqual(authored[1].insertionProperty(fluidProperty.key.rawValue), fluidProperty)
        XCTAssertEqual(authored[1].insertionNumberProperty("layout.gap"), 24)
        XCTAssertEqual(registry.value(for: .gap, in: session.document,
            context: fixture.with(document: session.document).context, breakpoint: .tablet, viewportWidth: 768),
            .single(.number(6), .authored, applicableCount: 1, skippedCount: 1))
        XCTAssertThrowsError(try prepare(command(.number(5), breakpoint: .tablet, revision: oldRevision))) {
            XCTAssertEqual($0 as? ContainerLayoutError, .staleRevision)
        }
        try session.undo(); XCTAssertEqual(session.document.pages[0].nodes, original)
        try session.redo(); XCTAssertEqual(session.document.pages[0].nodes, authored)
        try session.execute(try prepare(command(nil, breakpoint: .tablet, reset: true)).documentCommand)
        XCTAssertEqual(registry.value(for: .gap, in: session.document,
            context: fixture.with(document: session.document).context, breakpoint: .tablet, viewportWidth: 768),
            .single(.number(16), .authored, applicableCount: 1, skippedCount: 1))
        let identity = GeometryInspectorOperationIdentity(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: fixture.pageID,
            revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration)
        let remove = try FluidValueCommandRegistry().prepare(.init(identity: identity,
            orderedNodeIDs: fixture.selectedIDs, target: .gap, value: nil, provenance: .keyboard, cancelled: false),
            in: session.document, context: fixture.with(document: session.document).context)
        try session.execute(remove.documentCommand)
        try session.execute(try prepare(command(.number(7))).documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionNumberProperty("layout.gap"), 7)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo(); try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty(fluidProperty.key.rawValue), fluidProperty)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionNumberProperty("layout.gap"), 24)
    }

    // SF-0502-005, SF-0503-005: one fluid member rejects an ignored
    // multi-edit atomically, without leaking authored text into diagnostics.
    func testContainerFluidSpacingMixedRejectionIsAtomicAndRedacted() throws {
        var fixture = makeFixture()
        for (index, kind) in [(1, NodeKind.stack), (2, NodeKind.grid)] {
            fixture.document.pages[0].nodes[index].kind = kind
            applyStructuralDefaults(for: kind, to: &fixture.document.pages[0].nodes[index])
        }
        fixture.document.pages[0].nodes[2].properties.append(.init(
            key: .init(rawValue: CanonicalFluidValueCodec.key(.padding)),
            value: .string(try CanonicalFluidValueCodec.encode(.init(minimum: 4, preferred: 8, maximum: 16), target: .padding))))
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        let before = fixture.document
        let command = ContainerLayoutCommand(identity: .init(editID: GeometryInspectorEditID(), documentID: before.id, pageID: fixture.pageID,
            revision: before.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: fixture.selectedIDs, field: .padding, value: .number(12), provenance: .keyboard, cancelled: false)
        XCTAssertThrowsError(try ContainerLayoutCommandRegistry().prepare(command, in: before, context: fixture.context)) {
            XCTAssertEqual($0 as? ContainerLayoutError, .fluidValueWins)
        }
        XCTAssertEqual(fixture.document, before)
        let record = ContainerLayoutDiagnosticFactory.make(command: command, durationMilliseconds: 0,
            resultRevision: nil, result: .failure, failure: .fluidValueWins)
        XCTAssertEqual(record.failureCategory, "fluid-value-wins")
        XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
        XCTAssertTrue(ContainerLayoutError.fluidValueWins.localizedDescription.contains("Fluid Value"))
    }

    // SF-0501-003, SF-0505-003/005: empty Hug containers use fluid
    // padding and explicit bounds, not a placeholder child or rewritten height.
    func testEmptyFluidContainersResolveHugWithinBoundsWithoutRewritingFallbacks() throws {
        var fixture = makeFixture()
        let padding = CanonicalFluidValue(minimum: 0, preferred: 8, maximum: 16)
        for (index, kind) in [(1, NodeKind.stack), (2, NodeKind.grid)] {
            fixture.document.pages[0].nodes[index].kind = kind
            applyStructuralDefaults(for: kind, to: &fixture.document.pages[0].nodes[index])
            let record = CanonicalFluidValue(minimum: padding.minimum, preferred: padding.preferred, maximum: padding.maximum)
            fixture.document.pages[0].nodes[index].properties += [
                .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.padding)),
                    value: .string(try CanonicalFluidValueCodec.encode(record, target: .padding))),
                .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "heightMode"), value: .string("hug")),
                .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "minHeight"), value: .number(12)),
                .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "maxHeight"), value: .number(24))
            ]
        }
        try fixture.document.validate()
        let before = fixture.document
        for width in [320.0, 390, 574, 768, 1024, 1440] {
            let frames = before.pages[0].resolvedStructuralGeometry(breakpoint: .resolving(width: width), viewportWidth: width)
            let expected = max(12, min(24, 2 * (try XCTUnwrap(padding.resolved(viewportWidth: width)))))
            for node in before.pages[0].nodes[1...2] {
                XCTAssertTrue(node.childIDs.isEmpty)
                let frame = try XCTUnwrap(frames[node.id])
                XCTAssertEqual(frame.size.height, expected, accuracy: 0.001)
                XCTAssertTrue(frame.size.width.isFinite)
                XCTAssertGreaterThan(frame.size.width, 0)
            }
        }
        XCTAssertEqual(fixture.document, before)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(before)), before)
    }

    // SF-0502-001...006 / SF-0503-001...006 / SF-0506-001...006
    func testContainerLayoutRegistryValidatesMixesResetsAndPreservesExactHistory() throws {
        var fixture = makeFixture(selectedIDs: [])
        var stack = fixture.document.pages[0].nodes[1]
        stack.kind = .stack
        applyStructuralDefaults(for: .stack, to: &stack)
        var grid = fixture.document.pages[0].nodes[2]
        grid.kind = .grid
        applyStructuralDefaults(for: .grid, to: &grid)
        fixture.document.pages[0].nodes[1] = stack
        fixture.document.pages[0].nodes[2] = grid
        fixture.selectedIDs = [stack.id, grid.id]
        let registry = ContainerLayoutCommandRegistry()

        func command(
            _ document: CanonicalDocument,
            field: ContainerLayoutField,
            value: ContainerLayoutValue?,
            ids: [NodeID]? = nil,
            cancelled: Bool = false,
            revision: UInt64? = nil,
            documentID: DocumentID? = nil,
            pageID: PageID? = nil,
            sceneID: CanvasViewportSceneID? = nil,
            rendererGeneration: UInt64? = nil
        ) -> ContainerLayoutCommand {
            .init(identity: .init(
                editID: GeometryInspectorEditID(), documentID: documentID ?? document.id,
                pageID: pageID ?? fixture.pageID, revision: revision ?? document.revision,
                sceneID: sceneID ?? fixture.sceneID,
                rendererGeneration: rendererGeneration ?? fixture.rendererGeneration
            ), orderedNodeIDs: ids ?? fixture.selectedIDs, field: field,
            value: value, provenance: .automation, cancelled: cancelled)
        }

        XCTAssertEqual(
            registry.value(for: .padding, in: fixture.document, context: fixture.context),
            .single(.number(24), .defaulted, applicableCount: 2, skippedCount: 0)
        )
        XCTAssertEqual(
            registry.value(for: .axis, in: fixture.document, context: fixture.context),
            .single(.axis(.vertical), .defaulted, applicableCount: 1, skippedCount: 1)
        )

        let padding = try registry.prepare(
            command(fixture.document, field: .padding, value: .number(36)),
            in: fixture.document, context: fixture.context
        )
        XCTAssertEqual(padding.applicableNodeIDs, fixture.selectedIDs)
        XCTAssertTrue(padding.skippedNodeIDs.isEmpty)
        let originalIDs = fixture.document.pages[0].nodes[1...2].compactMap {
            $0.insertionProperty("layout.padding")?.id
        }
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(padding.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionNumberProperty("layout.padding")
        }, [36, 36])
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionProperty("layout.padding")?.origin
        }, [.authored, .authored])
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionNumberProperty("layout.padding")
        }, [24, 24])
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionProperty("layout.padding")?.id
        }, originalIDs)
        try session.redo()

        let currentFixture = fixture.with(document: session.document)
        let axis = try registry.prepare(
            command(session.document, field: .axis, value: .axis(.horizontal), ids: fixture.selectedIDs),
            in: session.document, context: currentFixture.context(selectedIDs: fixture.selectedIDs)
        )
        XCTAssertEqual(axis.applicableNodeIDs, [stack.id])
        XCTAssertEqual(axis.skippedNodeIDs, [grid.id])
        _ = try session.execute(axis.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionStringProperty("layout.axis"), "horizontal")

        let resetFixture = fixture.with(document: session.document)
        let reset = try registry.prepare(
            command(session.document, field: .padding, value: nil, ids: fixture.selectedIDs),
            in: session.document, context: resetFixture.context(selectedIDs: fixture.selectedIDs)
        )
        _ = try session.execute(reset.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionNumberProperty("layout.padding")
        }, [24, 24])
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            $0.insertionProperty("layout.padding")?.origin
        }, [.defaulted, .defaulted])
        XCTAssertNoThrow(try session.document.validate())
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .columns, value: .number(0)),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .invalidValue) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .gap, value: .number(.nan)),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .invalidValue) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), cancelled: true),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .cancelled) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), revision: fixture.document.revision + 1),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .staleRevision) }

        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12),
                    documentID: DocumentID()),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .staleDocument) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12),
                    sceneID: CanvasViewportSceneID()),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .staleRenderer) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12),
                    rendererGeneration: fixture.rendererGeneration + 1),
            in: fixture.document, context: fixture.context
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .staleRenderer) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), ids: [stack.id, stack.id]),
            in: fixture.document, context: fixture.context(selectedIDs: [stack.id, stack.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .duplicateTarget) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), ids: [stack.id]),
            in: fixture.document, context: fixture.context(selectedIDs: [grid.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .selectionMismatch) }
        XCTAssertThrowsError(try registry.prepare(
            command(fixture.document, field: .padding, value: .number(12), ids: [stack.id]),
            in: fixture.document,
            context: fixture.context(selectedIDs: [stack.id], availableIDs: [grid.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .unavailableTarget) }

        var lockedDocument = fixture.document
        lockedDocument.pages[0].nodes[1].properties.append(booleanProperty("locked", true))
        XCTAssertThrowsError(try registry.prepare(
            command(lockedDocument, field: .padding, value: .number(12), ids: [stack.id]),
            in: lockedDocument,
            context: fixture.with(document: lockedDocument).context(selectedIDs: [stack.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .lockedTarget) }

        var hiddenDocument = fixture.document
        hiddenDocument.pages[0].nodes[1].properties.append(booleanProperty("hidden", true))
        XCTAssertThrowsError(try registry.prepare(
            command(hiddenDocument, field: .padding, value: .number(12), ids: [stack.id]),
            in: hiddenDocument,
            context: fixture.with(document: hiddenDocument).context(selectedIDs: [stack.id])
        )) { XCTAssertEqual($0 as? ContainerLayoutError, .hiddenTarget) }

        let diagnosticCommand = command(fixture.document, field: .padding, value: .number(72))
        let record = ContainerLayoutDiagnosticFactory.make(
            command: diagnosticCommand,
            durationMilliseconds: 0.25,
            resultRevision: fixture.document.revision + 1,
            result: .success,
            failure: nil
        )
        XCTAssertEqual(record.operationType, "container-layout.padding")
        XCTAssertEqual(record.requirementIDs, ContainerLayoutCommandRegistry.requirementIDs.sorted())
        XCTAssertFalse(String(describing: record).contains(stack.id.description))
        XCTAssertFalse(String(describing: record).contains("/Users/"))
    }

    // SF-0601-001...006 / SF-0603-001...006
    func testResponsiveContainerAndVisibilityRegistriesSetResetValidateAndPreserveExactHistory() throws {
        var fixture = makeFixture(selectedIDs: [])
        var stack = fixture.document.pages[0].nodes[1]
        stack.kind = .stack
        applyStructuralDefaults(for: .stack, to: &stack)
        fixture.document.pages[0].nodes[1] = stack
        fixture.selectedIDs = [stack.id]
        let context = fixture.context(selectedIDs: [stack.id])
        let identity = GeometryInspectorOperationIdentity(
            editID: GeometryInspectorEditID(), documentID: fixture.document.id,
            pageID: fixture.pageID, revision: fixture.document.revision,
            sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration
        )
        let layoutRegistry = ContainerLayoutCommandRegistry()
        let rootID = fixture.document.pages[0].nodes[0].id
        let partial = try layoutRegistry.prepare(.init(
            identity: identity, orderedNodeIDs: [stack.id, rootID], field: .gap,
            value: .number(11), provenance: .accessibility, cancelled: false,
            breakpoint: .mobile
        ), in: fixture.document, context: fixture.context(selectedIDs: [stack.id, rootID]))
        XCTAssertEqual(partial.applicableNodeIDs, [stack.id])
        XCTAssertEqual(partial.skippedNodeIDs, [rootID])

        let layout = try layoutRegistry.prepare(.init(
            identity: identity, orderedNodeIDs: [stack.id], field: .axis,
            value: .axis(.horizontal), provenance: .automation, cancelled: false,
            breakpoint: .tablet
        ), in: fixture.document, context: context)
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(layout.documentCommand)
        var node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == stack.id })
        let key = ResponsiveContainerLayoutResolver.key(.axis, breakpoint: .tablet)
        let authoredProperty = try XCTUnwrap(node.insertionProperty(key))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .axis, node: node, breakpoint: .tablet)?.0, .axis(.horizontal))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .axis, node: node, breakpoint: .mobile)?.0, .axis(.vertical))
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 768), .tablet)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 390), .mobile)
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(key))
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(key)?.id, authoredProperty.id)

        let current = fixture.with(document: session.document)
        let reset = try layoutRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], field: .axis, value: nil,
            provenance: .automation, cancelled: false, breakpoint: .tablet,
            removesOverride: true
        ), in: session.document, context: current.context(selectedIDs: [stack.id]))
        _ = try session.execute(reset.documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(key))

        let visibilityRegistry = ResponsiveVisibilityCommandRegistry()
        var partialDocument = session.document
        partialDocument.pages[0].nodes[2].kind = .component
        // A linked instance is applicable; a non-rendering node without a
        // complete geometry is not. Preserve explicit subset rejection proof.
        partialDocument.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == "layout.width" }
        let partialFixture = fixture.with(document: partialDocument)
        let partialVisibility = try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: partialDocument.id,
                pageID: fixture.pageID, revision: partialDocument.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id, fixture.secondNodeID], breakpoint: .mobile, visible: false,
            provenance: .accessibility, cancelled: false
        ), in: partialDocument, context: partialFixture.context(selectedIDs: [stack.id, fixture.secondNodeID]))
        XCTAssertEqual(partialVisibility.applicableNodeIDs, [stack.id])
        XCTAssertEqual(partialVisibility.skippedNodeIDs, [fixture.secondNodeID])

        var mixedDocument = session.document
        mixedDocument.pages[0].nodes[2].properties.append(.init(
            key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)),
            value: .boolean(false), origin: .authored
        ))
        let mixedFixture = fixture.with(document: mixedDocument)
        XCTAssertEqual(visibilityRegistry.value(in: mixedDocument,
            context: mixedFixture.context(selectedIDs: [stack.id, fixture.secondNodeID]), breakpoint: .mobile),
            .mixed(applicableCount: 2, skippedCount: 0))

        let visibility = try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: false,
            provenance: .automation, cancelled: false
        ), in: session.document, context: fixture.with(document: session.document).context(selectedIDs: [stack.id]))
        _ = try session.execute(visibility.documentCommand)
        node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == stack.id })
        let visibilityKey = ResponsiveVisibilityResolver.key(.mobile)
        let visibilityProperty = try XCTUnwrap(node.insertionProperty(visibilityKey))
        XCTAssertFalse(ResponsiveVisibilityResolver.isVisible(node, breakpoint: .mobile))
        XCTAssertTrue(ResponsiveVisibilityResolver.isVisible(node, breakpoint: .tablet))
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(visibilityKey))
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(visibilityKey)?.id,
                       visibilityProperty.id)

        let visibilityCurrent = fixture.with(document: session.document)
        let visibilityReset = try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: nil,
            provenance: .keyboard, cancelled: false
        ), in: session.document, context: visibilityCurrent.context(selectedIDs: [stack.id]))
        _ = try session.execute(visibilityReset.documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(visibilityKey))
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(visibilityKey)?.id,
                       visibilityProperty.id)
        try session.redo()

        XCTAssertNoThrow(try session.document.validate())
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        XCTAssertThrowsError(try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision + 1,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: true,
            provenance: .automation, cancelled: false
        ), in: session.document, context: fixture.with(document: session.document).context(selectedIDs: [stack.id]))) {
            XCTAssertEqual($0 as? ResponsiveVisibilityError, .staleRevision)
        }
        XCTAssertThrowsError(try visibilityRegistry.prepare(.init(
            identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: true,
            provenance: .automation, cancelled: true
        ), in: session.document, context: fixture.with(document: session.document).context(selectedIDs: [stack.id]))) {
            XCTAssertEqual($0 as? ResponsiveVisibilityError, .cancelled)
        }

        let diagnostic = ResponsiveVisibilityDiagnosticFactory.make(
            command: .init(
                identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                    pageID: fixture.pageID, revision: session.document.revision,
                    sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [stack.id], breakpoint: .mobile, visible: false,
                provenance: .accessibility, cancelled: false
            ),
            durationMilliseconds: 1.5, resultRevision: session.document.revision + 1,
            result: .success, failure: nil
        )
        XCTAssertEqual(diagnostic.requirementIDs, ResponsiveVisibilityCommandRegistry.requirementIDs.sorted())
        XCTAssertEqual(diagnostic.provenance, "accessibility")
        XCTAssertFalse(String(describing: diagnostic).contains(stack.id.description))
        XCTAssertFalse(String(describing: diagnostic).contains("/Users/"))

        var malformedContainer = session.document
        malformedContainer.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: ResponsiveContainerLayoutResolver.key(.axis, breakpoint: .tablet)),
            value: .string("diagonal"), origin: .authored
        ))
        XCTAssertThrowsError(try malformedContainer.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidResponsiveContainerState)
        }
        var malformedVisibility = session.document
        malformedVisibility.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: ResponsiveVisibilityResolver.key(.tablet)),
            value: .number(1), origin: .authored
        ))
        XCTAssertThrowsError(try malformedVisibility.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidResponsiveVisibilityState)
        }
    }

    // SF-0502/SF-0503/SF-0601 — every bounded structural kind uses the same
    // breakpoint override representation and reset semantics.
    func testResponsiveSectionAndGridOverridesResolveAndResetIndependently() throws {
        let registry = ContainerLayoutCommandRegistry()

        func prepared(
            _ field: ContainerLayoutField,
            _ value: ContainerLayoutValue?,
            breakpoint: ResponsiveBreakpoint,
            removesOverride: Bool = false,
            fixture: TransformFixture
        ) throws -> PreparedContainerLayoutEdit {
            try registry.prepare(.init(
                identity: .init(editID: GeometryInspectorEditID(), documentID: fixture.document.id,
                    pageID: fixture.pageID, revision: fixture.document.revision,
                    sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: fixture.selectedIDs, field: field, value: value,
                provenance: .keyboard, cancelled: false, breakpoint: breakpoint,
                removesOverride: removesOverride
            ), in: fixture.document, context: fixture.context)
        }

        var sectionFixture = makeFixture()
        sectionFixture.document.pages[0].nodes[1].kind = .section
        applyStructuralDefaults(for: .section, to: &sectionFixture.document.pages[0].nodes[1])
        let sectionSession = DocumentSession(document: sectionFixture.document)
        _ = try sectionSession.execute(try prepared(.padding, .number(72), breakpoint: .tablet,
            fixture: sectionFixture).documentCommand)
        var section = try XCTUnwrap(sectionSession.document.pages[0].nodes.first { $0.id == sectionFixture.nodeID })
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .padding, node: section, breakpoint: .tablet)?.0, .number(72))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .padding, node: section, breakpoint: .mobile)?.0, .number(48))
        sectionFixture.document = sectionSession.document
        _ = try sectionSession.execute(try prepared(.padding, nil, breakpoint: .tablet,
            removesOverride: true, fixture: sectionFixture).documentCommand)
        section = try XCTUnwrap(sectionSession.document.pages[0].nodes.first { $0.id == sectionFixture.nodeID })
        XCTAssertNil(section.insertionProperty(ResponsiveContainerLayoutResolver.key(.padding, breakpoint: .tablet)))

        var gridFixture = makeFixture()
        gridFixture.document.pages[0].nodes[1].kind = .grid
        applyStructuralDefaults(for: .grid, to: &gridFixture.document.pages[0].nodes[1])
        let gridSession = DocumentSession(document: gridFixture.document)
        for (field, value) in [
            (ContainerLayoutField.columns, ContainerLayoutValue.number(3)),
            (.gap, .number(12)),
            (.padding, .number(16)),
        ] {
            gridFixture.document = gridSession.document
            _ = try gridSession.execute(try prepared(field, value, breakpoint: .mobile,
                fixture: gridFixture).documentCommand)
        }
        let grid = try XCTUnwrap(gridSession.document.pages[0].nodes.first { $0.id == gridFixture.nodeID })
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .columns, node: grid, breakpoint: .mobile)?.0, .number(3))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .gap, node: grid, breakpoint: .mobile)?.0, .number(12))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .padding, node: grid, breakpoint: .mobile)?.0, .number(16))
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .columns, node: grid, breakpoint: .tablet)?.0, .number(2))
    }

    // SF-1006-001...008 — one Inspector transaction configures only Text
    // children of Form, preserving option/property identities through history.
    func testFormInspectorRegistryCommitsExactMetadataHistoryAndMixedSubset() throws {
        let formID = NodeID(UUID(uuidString: "A6100000-0000-4000-8000-000000000001")!)
        let fieldID = NodeID(UUID(uuidString: "A6100000-0000-4000-8000-000000000002")!)
        let frameID = NodeID(UUID(uuidString: "A6100000-0000-4000-8000-000000000003")!)
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID, frameID]
        document.pages[0].nodes += [
            .init(id: formID, kind: .form, name: "Contact", parent: .node(rootID), childIDs: [fieldID]),
            .init(id: fieldID, kind: .text, name: "Plan", parent: .node(formID)),
            .init(id: frameID, kind: .frame, name: "Not a field", parent: .node(rootID)),
        ]
        try document.validate()

        let sceneID = CanvasViewportSceneID(UUID(uuidString: "A6100000-0000-4000-8000-000000000004")!)
        let registry = FormInspectorCommandRegistry()
        let configuration = FormFieldConfiguration(
            kind: .select, label: "Plan", name: "plan", help: "Choose a plan.", required: true,
            options: [
                .init(id: FormOptionID(UUID(uuidString: "A6100000-0000-4000-8000-000000000005")!), label: "Starter", value: "starter"),
                .init(id: FormOptionID(UUID(uuidString: "A6100000-0000-4000-8000-000000000006")!), label: "Pro", value: "pro"),
            ]
        )
        func context(_ current: CanonicalDocument, _ selected: [NodeID]) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 17,
                  selectedNodeIDs: selected, availableNodeIDs: Set(current.pages[0].nodes.map(\.id)),
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        func command(_ current: CanonicalDocument, _ selected: [NodeID], edit: FormInspectorEdit, cancelled: Bool = false) -> FormInspectorCommand {
            .init(identity: .init(documentID: current.id, pageID: pageID, revision: current.revision,
                                 sceneID: sceneID, rendererGeneration: 17, selectedNodeIDs: selected),
                  edit: edit, cancelled: cancelled)
        }

        let prepared = try registry.prepare(command(document, [fieldID, frameID], edit: .configure(configuration)),
                                            in: document, context: context(document, [fieldID, frameID]))
        XCTAssertEqual(prepared.applicableNodeIDs, [fieldID])
        XCTAssertEqual(prepared.skippedNodeIDs, [frameID])
        let session = DocumentSession(document: document)
        try session.execute(prepared.command)
        let configured = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID })
        XCTAssertEqual(configured.insertionStringProperty(CanonicalFormField.kindKey), "select")
        XCTAssertEqual(configured.insertionStringProperty(CanonicalFormField.nameKey), "plan")
        XCTAssertEqual(try CanonicalFormSelectOptions.decode(try XCTUnwrap(configured.insertionStringProperty(CanonicalFormField.optionsKey))), configuration.options)
        let propertyIDs = configured.properties.filter { $0.key.rawValue.hasPrefix("form.field.v1.") }.map(\.id)
        XCTAssertFalse(propertyIDs.isEmpty)
        XCTAssertTrue(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == frameID }).properties.isEmpty)

        try session.undo()
        XCTAssertTrue(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).properties.isEmpty)
        try session.redo()
        XCTAssertEqual(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).properties.filter { $0.key.rawValue.hasPrefix("form.field.v1.") }.map(\.id), propertyIDs)

        let reordered = FormFieldConfiguration(kind: .select, label: "Plan", name: "plan",
            help: "Choose a plan.", required: true, options: Array(configuration.options.reversed()))
        let reorder = try registry.prepare(command(session.document, [fieldID], edit: .configure(reordered)),
            in: session.document, context: context(session.document, [fieldID]))
        try session.execute(reorder.command)
        let reorderedOptions = try CanonicalFormSelectOptions.decode(try XCTUnwrap(
            session.document.pages[0].nodes.first { $0.id == fieldID }?.insertionStringProperty(CanonicalFormField.optionsKey)
        ))
        XCTAssertEqual(reorderedOptions.map(\.id), configuration.options.reversed().map(\.id))

        let removal = try registry.prepare(command(session.document, [fieldID], edit: .removeConfiguration),
                                           in: session.document, context: context(session.document, [fieldID]))
        try session.execute(removal.command)
        XCTAssertTrue(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).properties.isEmpty)
        try session.undo()
        XCTAssertEqual(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).properties.filter { $0.key.rawValue.hasPrefix("form.field.v1.") }.map(\.id), propertyIDs)
    }

    // SF-1006-002, SF-1006-005, SF-1006-008 — invalid drafts, cancellation,
    // and stale identity have no command and leave canonical content untouched.
    func testFormInspectorRegistryRejectsInvalidCancelledAndStaleEdits() throws {
        let formID = NodeID(), fieldID = NodeID()
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID]
        document.pages[0].nodes += [
            .init(id: formID, kind: .form, name: "Form", parent: .node(rootID), childIDs: [fieldID]),
            .init(id: fieldID, kind: .text, name: "Field", parent: .node(formID)),
        ]
        let sceneID = CanvasViewportSceneID()
        let context = TransformValidationContext(activePageID: pageID, currentSceneID: sceneID,
            rendererGeneration: 9, selectedNodeIDs: [fieldID], availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let identity = FormInspectorOperationIdentity(documentID: document.id, pageID: pageID,
            revision: document.revision, sceneID: sceneID, rendererGeneration: 9, selectedNodeIDs: [fieldID])
        let registry = FormInspectorCommandRegistry()
        let invalid = FormFieldConfiguration(kind: .select, label: " ", name: "1 bad", help: nil,
                                             required: false, options: [])
        XCTAssertThrowsError(try registry.prepare(.init(identity: identity, edit: .configure(invalid), cancelled: false), in: document, context: context)) {
            XCTAssertEqual($0 as? FormInspectorError, .invalidConfiguration)
        }
        XCTAssertThrowsError(try registry.prepare(.init(identity: identity, edit: .removeConfiguration, cancelled: true), in: document, context: context)) {
            XCTAssertEqual($0 as? FormInspectorError, .cancelled)
        }
        let stale = FormInspectorOperationIdentity(documentID: document.id, pageID: pageID,
            revision: document.revision + 1, sceneID: sceneID, rendererGeneration: 9, selectedNodeIDs: [fieldID])
        XCTAssertThrowsError(try registry.prepare(.init(identity: stale, edit: .removeConfiguration, cancelled: false), in: document, context: context)) {
            XCTAssertEqual($0 as? FormInspectorError, .stale)
        }
        XCTAssertEqual(document.pages[0].nodes.first { $0.id == fieldID }?.properties, [])
    }

    // SF-1006-001/002/003/004/005/008 — authored bounded validation remains
    // an optional canonical rule, is transactional, and never accepts an
    // inapplicable kind or out-of-range draft.
    func testFormInspectorValidationBoundCommitsAndRejectsInvalidKinds() throws {
        let formID = NodeID(), fieldID = NodeID()
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id, rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID]
        document.pages[0].nodes += [.init(id: formID, kind: .form, name: "Form", parent: .node(rootID), childIDs: [fieldID]),
                                   .init(id: fieldID, kind: .text, name: "Email", parent: .node(formID))]
        try document.validate()
        let sceneID = CanvasViewportSceneID()
        func context(_ current: CanonicalDocument) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 3, selectedNodeIDs: [fieldID], availableNodeIDs: Set(current.pages[0].nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        func input(_ current: CanonicalDocument, _ configuration: FormFieldConfiguration) -> FormInspectorCommand {
            .init(identity: .init(documentID: current.id, pageID: pageID, revision: current.revision, sceneID: sceneID, rendererGeneration: 3, selectedNodeIDs: [fieldID]), edit: .configure(configuration), cancelled: false)
        }
        let registry = FormInspectorCommandRegistry()
        let bounded = FormFieldConfiguration(kind: .email, label: "Email", name: "email", help: nil, required: true, options: [], maximumLength: 128)
        let prepared = try registry.prepare(input(document, bounded), in: document, context: context(document))
        let session = DocumentSession(document: document)
        try session.execute(prepared.command)
        let field = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID })
        XCTAssertEqual(field.insertionNumberProperty(CanonicalFormField.maximumLengthKey), 128)
        let propertyID = try XCTUnwrap(field.insertionProperty(CanonicalFormField.maximumLengthKey)).id
        try session.undo(); XCTAssertNil(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).insertionProperty(CanonicalFormField.maximumLengthKey))
        try session.redo(); XCTAssertEqual(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fieldID }).insertionProperty(CanonicalFormField.maximumLengthKey)?.id, propertyID)
        let invalid = FormFieldConfiguration(kind: .checkbox, label: "Consent", name: "consent", help: nil, required: true, options: [], maximumLength: 2)
        XCTAssertThrowsError(try registry.prepare(input(session.document, invalid), in: session.document, context: context(session.document))) { XCTAssertEqual($0 as? FormInspectorError, .invalidConfiguration) }
    }

    // SF-0701-003/004/006, SF-0702-003/004/006, SF-0705-003/004/006,
    // SF-1006-003/004/006 — Content and Accessibility consume one truthful,
    // read-only projection without borrowing the primary field's mixed value.
    func testFormInspectorAccessibilityPresentationPreservesMixedValuesAndProvenance() throws {
        let formID = NodeID(), emailID = NodeID(), selectID = NodeID(), frameID = NodeID()
        var document = ProjectCreation.blank()
        let rootID = document.pages[0].rootNodeIDs[0]
        let options = try CanonicalFormSelectOptions.encode([
            .init(label: "Starter", value: "starter"), .init(label: "Pro", value: "pro"),
        ])
        func property(_ key: String, _ value: PropertyValue, _ origin: PropertyOrigin) -> NodeProperty {
            .init(key: .init(rawValue: key), value: value, origin: origin)
        }
        let email = DocumentNode(id: emailID, kind: .text, name: "Email", parent: .node(formID), properties: [
            property(CanonicalFormField.kindKey, .string("email"), .defaulted),
            property(CanonicalFormField.labelKey, .string("Email"), .defaulted),
            property(CanonicalFormField.nameKey, .string("email"), .defaulted),
            property(CanonicalFormField.requiredKey, .boolean(true), .authored),
        ])
        let select = DocumentNode(id: selectID, kind: .text, name: "Plan", parent: .node(formID), properties: [
            property(CanonicalFormField.kindKey, .string("select"), .authored),
            property(CanonicalFormField.labelKey, .string("Plan"), .authored),
            property(CanonicalFormField.nameKey, .string("plan"), .authored),
            property(CanonicalFormField.requiredKey, .boolean(true), .authored),
            property(CanonicalFormField.optionsKey, .string(options), .authored),
        ])
        let form = DocumentNode(id: formID, kind: .form, name: "Contact", parent: .node(rootID),
                                childIDs: [emailID, selectID])
        document.pages[0].nodes[0].childIDs = [formID, frameID]
        document.pages[0].nodes += [form, email, select,
            .init(id: frameID, kind: .frame, name: "Incompatible", parent: .node(rootID))]
        try document.validate()

        let presentation = FormFieldInspectorPresentation.resolve(
            fields: [email, select], totalSelectionCount: 3)
        XCTAssertEqual(presentation.applicableCount, 2)
        XCTAssertEqual(presentation.skippedCount, 1)
        XCTAssertEqual(presentation.kind, .mixed)
        XCTAssertEqual(presentation.accessibleName, .mixed)
        XCTAssertEqual(presentation.required, .value("Required", provenance: "Authored"))
        XCTAssertTrue(presentation.configurationStatus.contains("incompatible"))

        let formPresentation = FormContainerAccessibilityPresentation.resolve(
            form: form, page: document.pages[0])
        XCTAssertEqual(formPresentation.fieldCount, 2)
        XCTAssertEqual(formPresentation.configuredCount, 2)
        XCTAssertEqual(formPresentation.requiredCount, 2)
        XCTAssertEqual(formPresentation.submitCount, 0)
        XCTAssertTrue(formPresentation.status.contains("canonical accessible labels"))
    }

    // SF-1006-001/003/004/008 — visitor input has one local, noncanonical
    // resolver. Required, email, select membership, checkbox and text bounds
    // return only stable identities and categories, never entered values.
    func testLocalFormValidationResolvesValidInvalidControlsAndRedactsValues() throws {
        let formID = NodeID(), textID = NodeID(), emailID = NodeID(), checkboxID = NodeID(), selectID = NodeID()
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID]
        document.pages[0].nodes += [
            .init(id: formID, kind: .form, name: "Form", parent: .node(rootID), childIDs: [textID, emailID, checkboxID, selectID]),
            .init(id: textID, kind: .text, name: "Text", parent: .node(formID)),
            .init(id: emailID, kind: .text, name: "Email", parent: .node(formID)),
            .init(id: checkboxID, kind: .text, name: "Consent", parent: .node(formID)),
            .init(id: selectID, kind: .text, name: "Plan", parent: .node(formID)),
        ]
        let sceneID = CanvasViewportSceneID()
        func context(_ current: CanonicalDocument, selected: [NodeID] = [textID]) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 4,
                  selectedNodeIDs: selected, availableNodeIDs: Set(current.pages[0].nodes.map(\.id)),
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        let session = DocumentSession(document: document)
        let registry = FormInspectorCommandRegistry()
        for (id, configuration) in [
            (textID, FormFieldConfiguration(kind: .text, label: "Name", name: "name", help: nil, required: true, options: [])),
            (emailID, FormFieldConfiguration(kind: .email, label: "Email", name: "email", help: nil, required: true, options: [])),
            (checkboxID, FormFieldConfiguration(kind: .checkbox, label: "Consent", name: "consent", help: nil, required: true, options: [])),
            (selectID, FormFieldConfiguration(kind: .select, label: "Plan", name: "plan", help: nil, required: true,
                options: [.init(label: "Basic", value: "basic"), .init(label: "Pro", value: "pro")])),
        ] {
            let command = FormInspectorCommand(identity: .init(documentID: session.document.id, pageID: pageID,
                revision: session.document.revision, sceneID: sceneID, rendererGeneration: 4, selectedNodeIDs: [id]),
                edit: .configure(configuration), cancelled: false)
            try session.execute(registry.prepare(command, in: session.document, context: context(session.document, selected: [id])).command)
        }
        let before = session.document
        let engine = LocalFormValidationEngine()
        let valid = try engine.validate(.init(documentID: before.id, pageID: pageID, formID: formID,
            revision: before.revision, sceneID: sceneID, rendererGeneration: 4,
            values: [textID: .text("Ada"), emailID: .text("ada@example.test"), checkboxID: .checkbox(true), selectID: .select("pro")]),
            in: before, context: context(before))
        XCTAssertTrue(valid.isValid)
        XCTAssertEqual(valid.staticOutputCompatibility, .unavailableSubmission)
        XCTAssertEqual(valid.fields.map(\.identity.fieldID), [textID, emailID, checkboxID, selectID])

        let invalid = try engine.validate(.init(documentID: before.id, pageID: pageID, formID: formID,
            revision: before.revision, sceneID: sceneID, rendererGeneration: 4,
            values: [textID: .text(""), emailID: .text("visitor-secret"), checkboxID: .checkbox(false), selectID: .select("unknown")]),
            in: before, context: context(before))
        XCTAssertEqual(invalid.fields.map(\.failures), [[.required], [.invalidEmail], [.required], [.invalidSelection]])
        XCTAssertFalse(String(describing: invalid).contains("visitor-secret"))
        let malformedValues = try engine.validate(.init(documentID: before.id, pageID: pageID, formID: formID,
            revision: before.revision, sceneID: sceneID, rendererGeneration: 4,
            values: [textID: .text(String(repeating: "x", count: LocalFormValidationEngine.maximumTextLength + 1)),
                     emailID: .checkbox(true), checkboxID: .text("yes"), selectID: .checkbox(true)]),
            in: before, context: context(before))
        XCTAssertEqual(malformedValues.fields.map(\.failures), [[.textTooLong], [.invalidValueType], [.invalidValueType], [.invalidValueType]])
        XCTAssertEqual(session.document, before, "Validation must not mutate canonical state.")
    }

    // SF-1006-001/004/005/008 — cancellation, stale scene/revision and an
    // invalid schema are neutral; recovery/reopen can validate the same local
    // input without serializing any visitor value.
    func testLocalFormValidationRejectsCancelledStaleAndInvalidSchemasWithoutMutation() throws {
        let formID = NodeID(), fieldID = NodeID()
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        document.pages[0].nodes[0].childIDs = [formID]
        document.pages[0].nodes += [
            .init(id: formID, kind: .form, name: "Form", parent: .node(rootID), childIDs: [fieldID]),
            .init(id: fieldID, kind: .text, name: "Email", parent: .node(formID)),
        ]
        let sceneID = CanvasViewportSceneID()
        let formRegistry = FormInspectorCommandRegistry()
        func context(_ current: CanonicalDocument) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 8,
                  selectedNodeIDs: [fieldID], availableNodeIDs: Set(current.pages[0].nodes.map(\.id)),
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        let session = DocumentSession(document: document)
        let configure = FormInspectorCommand(identity: .init(documentID: document.id, pageID: pageID,
            revision: document.revision, sceneID: sceneID, rendererGeneration: 8, selectedNodeIDs: [fieldID]),
            edit: .configure(.init(kind: .email, label: "Email", name: "email", help: nil, required: true, options: [])), cancelled: false)
        try session.execute(formRegistry.prepare(configure, in: document, context: context(document)).command)
        let persisted = try DocumentSerializer.decode(try DocumentSerializer.encode(session.document))
        let before = persisted
        let input = FormVisitorValueSnapshot(documentID: persisted.id, pageID: pageID, formID: formID,
            revision: persisted.revision, sceneID: sceneID, rendererGeneration: 8, values: [fieldID: .text("visitor@example.test")])
        let engine = LocalFormValidationEngine()
        XCTAssertTrue(try engine.validate(input, in: persisted, context: context(persisted)).isValid)
        XCTAssertThrowsError(try engine.validate(input, in: persisted, context: context(persisted), cancelled: true)) {
            XCTAssertEqual($0 as? FormValidationError, .cancelled)
        }
        var stale = input
        stale = .init(documentID: stale.documentID, pageID: stale.pageID, formID: stale.formID,
            revision: stale.revision + 1, sceneID: stale.sceneID, rendererGeneration: stale.rendererGeneration, values: stale.values)
        XCTAssertThrowsError(try engine.validate(stale, in: persisted, context: context(persisted))) {
            XCTAssertEqual($0 as? FormValidationError, .stale)
        }
        var malformed = persisted
        let index = try XCTUnwrap(malformed.pages[0].nodes.firstIndex { $0.id == fieldID })
        malformed.pages[0].nodes[index].properties.removeAll { $0.key.rawValue == CanonicalFormField.requiredKey }
        XCTAssertThrowsError(try engine.validate(input, in: malformed, context: context(malformed))) {
            XCTAssertEqual($0 as? FormValidationError, .invalidSchema)
        }
        let emptyFormID = NodeID()
        var empty = persisted
        empty.pages[0].nodes[0].childIDs.append(emptyFormID)
        empty.pages[0].nodes.append(.init(id: emptyFormID, kind: .form, name: "Empty", parent: .node(rootID)))
        let emptyInput = FormVisitorValueSnapshot(documentID: empty.id, pageID: pageID, formID: emptyFormID,
            revision: empty.revision, sceneID: sceneID, rendererGeneration: 8, values: [:])
        XCTAssertThrowsError(try engine.validate(emptyInput, in: empty, context: context(empty))) {
            XCTAssertEqual($0 as? FormValidationError, .invalidSchema)
        }
        XCTAssertEqual(persisted, before)
        XCTAssertFalse(try DocumentSerializer.encode(persisted).contains(Data("visitor@example.test".utf8)))
    }

    // SF-AUTHORING-101, SF-0601-003/006, SF-0602-002/003/004/006/008,
    // SF-0603-002/003/006 — review is a pure projection of the established
    // responsive resolvers and cannot mutate canonical content.
    func testResponsiveBreakpointReviewProjectsResolvedDifferencesWithoutMutation() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id
        let rootID = document.pages[0].rootNodeIDs[0]
        let stackID = NodeID()
        let stack = DocumentNode(id: stackID, kind: .stack, name: "Feature Stack", parent: .node(rootID), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(120), origin: .authored),
            .init(key: .init(rawValue: "layout.y"), value: .number(80), origin: .authored),
            .init(key: .init(rawValue: "layout.width"), value: .number(480), origin: .authored),
            .init(key: .init(rawValue: "layout.height"), value: .number(320), origin: .authored),
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.x, breakpoint: .tablet)), value: .number(40), origin: .authored),
            .init(key: .init(rawValue: ResponsiveContainerLayoutResolver.key(.gap, breakpoint: .tablet)), value: .number(12), origin: .authored),
            .init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(false), origin: .authored),
        ])
        document.pages[0].nodes[0].childIDs = [stackID]
        document.pages[0].nodes.append(stack)
        let before = document

        let reviews = ResponsiveBreakpointReviewPolicy.reviews(
            page: try XCTUnwrap(document.pages.first { $0.id == pageID }),
            selectedNodeIDs: [stackID]
        )
        XCTAssertEqual(reviews.map(\.breakpoint), [.desktop, .tablet, .mobile])
        XCTAssertEqual(reviews.map(\.viewportWidth), [1_440, 768, 390])
        XCTAssertEqual(reviews[0].visibleCount, 1)
        XCTAssertEqual(reviews[0].changedFromDesktopCount, 0)
        XCTAssertEqual(reviews[1].geometryOverrideCount, 1)
        XCTAssertEqual(reviews[1].containerOverrideCount, 1)
        XCTAssertEqual(reviews[1].primaryGeometry?.origin.x, 40)
        XCTAssertEqual(reviews[1].primaryProvenance, "authored geometry, inherited visibility")
        XCTAssertEqual(reviews[2].visibilityOverrideCount, 1)
        XCTAssertEqual(reviews[2].visibleCount, 0)
        XCTAssertEqual(reviews[2].changedFromDesktopCount, 1)
        XCTAssertEqual(reviews[2].primaryIsVisible, false)
        XCTAssertEqual(document, before, "Responsive review must remain scene-local and mutation-neutral.")
    }

    // SF-AUTHORING-102, SF-0604-001/003/004/005/008 — the closed v1 payload
    // round-trips stable identity and resolves one monotonic value at the
    // product reference widths; malformed and inverted payloads are rejected.
    // SF-0602-003, SF-0604-003: inspection and rendering resolve the
    // same continuous range; a device literal is never mistaken for fluid.
    func testEffectiveFluidTypographyAndGeometryResolveAtBreakpointBoundaries() throws {
        var fixture = makeFixture()
        let fontSize = CanonicalFluidValue(minimum: 12, preferred: 16, maximum: 20)
        let lineHeight = CanonicalFluidValue(minimum: 18, preferred: 24, maximum: 30)
        let widthRange = CanonicalFluidValue(minimum: 100, preferred: 150, maximum: 200)
        for index in 1...2 {
            fixture.document.pages[0].nodes[index].kind = .text
            for (target, value) in [(FluidValueTarget.fontSize, fontSize), (.lineHeight, lineHeight), (.width, widthRange)] {
                let record = CanonicalFluidValue(minimum: value.minimum, preferred: value.preferred, maximum: value.maximum)
                fixture.document.pages[0].nodes[index].properties.append(.init(
                    key: .init(rawValue: CanonicalFluidValueCodec.key(target)),
                    value: .string(try CanonicalFluidValueCodec.encode(record, target: target)), origin: .authored))
            }
        }
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)),
            value: .number(180), origin: .authored))
        fixture.selectedIDs = [fixture.nodeID, fixture.secondNodeID]
        try fixture.document.validate()
        let before = fixture.document
        let nodes = Array(before.pages[0].nodes[1...2])
        let ranges = try nodes.map { try XCTUnwrap(CanonicalFluidValueCodec.value(for: .fontSize, node: $0)?.0) }
        XCTAssertNotEqual(ranges[0].id, ranges[1].id)
        XCTAssertEqual(FluidValueCommandRegistry().value(for: .fontSize, in: before, context: fixture.context),
            .single(ranges[0], .authored, applicableCount: 2, skippedCount: 0),
            "Separate stable identities do not make identical authored ranges Mixed")
        for width in [320.0, 390, 599, 600, 767, 768, 1023, 1024, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let size = try XCTUnwrap(fontSize.resolved(viewportWidth: width))
            let height = try XCTUnwrap(lineHeight.resolved(viewportWidth: width))
            let typography = try XCTUnwrap(TypographyCommandRegistry.resolvedTypography(for: nodes[0], viewportWidth: width))
            XCTAssertEqual(typography.size, size, accuracy: 0.0001)
            XCTAssertEqual(typography.lineHeight, height, accuracy: 0.0001)
            XCTAssertEqual(TypographyCommandRegistry.selectionValue(nodes: nodes, viewportWidth: width), .single(typography, .authored))
            let resolved = try XCTUnwrap(FluidValueCommandRegistry.effectiveValue(for: .fontSize,
                node: nodes[0], breakpoint: breakpoint, viewportWidth: width))
            XCTAssertEqual(resolved.0, size, accuracy: 0.0001)
            XCTAssertEqual(resolved.1, .fluid)
            let geometry = try XCTUnwrap(FluidValueCommandRegistry.effectiveValue(for: .width,
                node: nodes[0], breakpoint: breakpoint, viewportWidth: width))
            XCTAssertEqual(geometry.0, breakpoint == .mobile ? 180 : try XCTUnwrap(widthRange.resolved(viewportWidth: width)), accuracy: 0.0001)
            XCTAssertEqual(geometry.1, breakpoint == .mobile ? .override(.mobile) : .fluid)
        }
        for width in [Double.nan, .infinity, 0, -1] {
            XCTAssertNil(FluidValueCommandRegistry.effectiveValue(for: .fontSize,
                node: nodes[0], breakpoint: .desktop, viewportWidth: width))
        }
        XCTAssertNil(FluidValueCommandRegistry.effectiveValue(for: .gap, node: nodes[0], breakpoint: .desktop, viewportWidth: 1440))
        XCTAssertEqual(TypographyCommandRegistry.selectionValue(nodes: nodes), .single(.defaultValue, .defaulted),
            "Fixed fallback inspection stays separate from effective fluid typography")
        var mixed = fixture
        let propertyIndex = try XCTUnwrap(mixed.document.pages[0].nodes[2].properties.firstIndex {
            $0.key.rawValue == CanonicalFluidValueCodec.key(.fontSize)
        })
        mixed.document.pages[0].nodes[2].properties[propertyIndex].value = .string(try CanonicalFluidValueCodec.encode(
            .init(id: ranges[1].id, minimum: 13, preferred: 17, maximum: 21), target: .fontSize))
        XCTAssertEqual(FluidValueCommandRegistry().value(for: .fontSize, in: mixed.document, context: mixed.context),
            .mixed(applicableCount: 2, skippedCount: 0))
        XCTAssertEqual(TypographyCommandRegistry.selectionValue(nodes: mixed.document.pages[0].nodes, viewportWidth: 390),
            .mixed(applicableCount: 2, skippedCount: 1))
        let session = DocumentSession(document: before)
        let unified = FluidValueCommand(identity: .init(editID: GeometryInspectorEditID(), documentID: before.id,
            pageID: fixture.pageID, revision: before.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: fixture.selectedIDs, target: .fontSize,
            value: .init(minimum: 13, preferred: 17, maximum: 21), provenance: .keyboard, cancelled: false)
        try session.execute(try FluidValueCommandRegistry().prepare(unified, in: before, context: fixture.context).documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes[1...2].compactMap {
            CanonicalFluidValueCodec.value(for: .fontSize, node: $0)?.0.id
        }, ranges.map(\.id))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        let committed = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, committed)
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0604-002/005: invalid/cancel/stale ranges cannot replace
    // authored IDs, device overrides, fallback typography or exact inverses.
    func testFluidTypographyInvalidStaleAndCancelledRangesPreserveCanonicalIntent() throws {
        var fixture = makeFixture()
        fixture.document.pages[0].nodes[1].kind = .text
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(180)))
        let session = DocumentSession(document: fixture.document), registry = FluidValueCommandRegistry()
        func request(_ value: CanonicalFluidValue?, cancelled: Bool = false, revision: UInt64? = nil) -> FluidValueCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: session.document.id,
                pageID: fixture.pageID, revision: revision ?? session.document.revision,
                sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], target: .fontSize, value: value, provenance: .keyboard, cancelled: cancelled)
        }
        func prepare(_ value: FluidValueCommand) throws -> PreparedFluidValueEdit {
            try registry.prepare(value, in: session.document, context: fixture.with(document: session.document).context)
        }
        let before = session.document.pages
        for invalid in [CanonicalFluidValue(minimum: 20, preferred: 10, maximum: 30),
                        .init(minimum: .nan, preferred: 10, maximum: 20),
                        .init(minimum: 10, preferred: 20, maximum: .infinity),
                        .init(minimum: 0, preferred: 12, maximum: 20)] {
            XCTAssertThrowsError(try prepare(request(invalid))) { XCTAssertEqual($0 as? FluidValueCommandError, .invalidValue) }
        }
        XCTAssertThrowsError(try prepare(request(.init(minimum: 10, preferred: 14, maximum: 18), cancelled: true))) {
            XCTAssertEqual($0 as? FluidValueCommandError, .cancelled)
        }
        let oldRevision = session.document.revision
        try session.execute(try prepare(request(.init(minimum: 10, preferred: 14, maximum: 18))).documentCommand)
        let authored = session.document.pages
        XCTAssertThrowsError(try prepare(request(nil, revision: oldRevision))) { XCTAssertEqual($0 as? FluidValueCommandError, .stale) }
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionNumberProperty(ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), 180)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, authored)
    }

    func testFluidValueCodecResolutionValidationAndRoundTrip() throws {
        let value = CanonicalFluidValue(minimum: 24, preferred: 36, maximum: 60)
        let encoded = try CanonicalFluidValueCodec.encode(value, target: .padding)
        let decoded = try CanonicalFluidValueCodec.decode(encoded, target: .padding)
        XCTAssertEqual(decoded, value)
        XCTAssertEqual(decoded.resolved(viewportWidth: 390), 24)
        XCTAssertEqual(decoded.resolved(viewportWidth: 768), 36)
        XCTAssertEqual(decoded.resolved(viewportWidth: 1_440), 60)
        XCTAssertEqual(try XCTUnwrap(decoded.resolved(viewportWidth: 579)), 30, accuracy: 0.001)
        XCTAssertThrowsError(try CanonicalFluidValueCodec.encode(
            .init(minimum: 40, preferred: 20, maximum: 60), target: .padding))
        XCTAssertThrowsError(try CanonicalFluidValueCodec.decode("{}", target: .padding))
        var malformed = ProjectCreation.blank()
        malformed.pages[0].nodes[0].properties.append(.init(
            key: .init(rawValue: CanonicalFluidValueCodec.key(.width)),
            value: .string("{\"schemaVersion\":1}"), origin: .authored))
        XCTAssertThrowsError(try DocumentSerializer.encode(malformed)) {
            XCTAssertEqual($0 as? DocumentSerializationError, .invalidModel(.invalidFluidValueState))
        }
        let legacyOmitted = ProjectCreation.blank()
        let reopened = try DocumentSerializer.decode(try DocumentSerializer.encode(legacyOmitted))
        XCTAssertFalse(reopened.pages.flatMap(\.nodes).flatMap(\.properties).contains {
            $0.key.rawValue.hasPrefix(CanonicalFluidValueCodec.namespace)
        }, "Existing fixed packages remain omitted rather than acquiring synthetic fluid values.")
    }

    // SF-0604-001...006/008 — one identity-gated transaction owns creation,
    // exact history restoration, persistence, subset reporting, reset, and
    // fixed-value fallback without rewriting the fallback literal.
    func testFluidValueRegistryCommitsApplicableSubsetPersistsAndRestoresExactInverse() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id, rootID = document.pages[0].rootNodeIDs[0]
        let frameID = NodeID(), unsupportedID = NodeID(), sceneID = CanvasViewportSceneID()
        document.pages[0].nodes[0].childIDs = [frameID, unsupportedID]
        document.pages[0].nodes += [
            .init(id: frameID, kind: .frame, name: "Fluid Frame", parent: .node(rootID), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.width"), value: .number(240), origin: .defaulted),
                .init(key: .init(rawValue: "layout.height"), value: .number(160), origin: .defaulted),
            ]),
            .init(id: unsupportedID, kind: .form, name: "Form", parent: .node(rootID)),
        ]
        let selected = [frameID, unsupportedID]
        func context(_ value: CanonicalDocument) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: sceneID, rendererGeneration: 7,
                  selectedNodeIDs: selected, availableNodeIDs: Set(value.pages[0].nodes.map(\.id)),
                  isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        func command(_ value: CanonicalFluidValue?) -> FluidValueCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: document.id,
                pageID: pageID, revision: document.revision, sceneID: sceneID, rendererGeneration: 7),
                orderedNodeIDs: selected, target: .width, value: value,
                provenance: .keyboard, cancelled: false)
        }
        let registry = FluidValueCommandRegistry()
        let fluid = CanonicalFluidValue(minimum: 180, preferred: 240, maximum: 360)
        let prepared = try registry.prepare(command(fluid), in: document, context: context(document))
        XCTAssertEqual(prepared.applicableNodeIDs, [frameID]); XCTAssertEqual(prepared.skippedNodeIDs, [unsupportedID])
        let diagnostic = FluidValueDiagnosticFactory.make(
            command: command(fluid), durationMilliseconds: 1, resultRevision: 1,
            result: .success, failure: nil)
        XCTAssertEqual(diagnostic.requirementIDs, FluidValueCommandRegistry.requirementIDs.sorted())
        XCTAssertFalse(String(describing: diagnostic).contains(frameID.description))
        // Sanitized identity hashes can coincidentally contain a decimal value.
        // Prove content independence instead of inspecting arbitrary hash digits.
        let differentContentDiagnostic = FluidValueDiagnosticFactory.make(
            command: command(.init(minimum: 120, preferred: 300, maximum: 480)),
            durationMilliseconds: 1, resultRevision: 1, result: .success, failure: nil)
        XCTAssertEqual(diagnostic, differentContentDiagnostic,
                       "Authored fluid values must not affect support diagnostics.")
        let cancelled = FluidValueCommand(identity: command(fluid).identity, orderedNodeIDs: selected,
            target: .width, value: fluid, provenance: .keyboard, cancelled: true)
        XCTAssertThrowsError(try registry.prepare(cancelled, in: document, context: context(document))) {
            XCTAssertEqual($0 as? FluidValueCommandError, .cancelled)
        }
        let stale = FluidValueCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: document.id, pageID: pageID, revision: document.revision + 1,
            sceneID: sceneID, rendererGeneration: 7), orderedNodeIDs: selected,
            target: .width, value: fluid, provenance: .automation, cancelled: false)
        XCTAssertThrowsError(try registry.prepare(stale, in: document, context: context(document))) {
            XCTAssertEqual($0 as? FluidValueCommandError, .stale)
        }
        let session = DocumentSession(document: document)
        try session.execute(prepared.documentCommand)
        let property = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width)))
        let propertyID = property.id
        let reopened = try DocumentSerializer.decode(try DocumentSerializer.encode(session.document))
        XCTAssertEqual(try CanonicalFluidValueCodec.decode(try XCTUnwrap(reopened.pages[0].nodes.first {
            $0.id == frameID
        }?.insertionStringProperty(CanonicalFluidValueCodec.key(.width))), target: .width), fluid)
        try session.undo()
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width)))
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width))?.id, propertyID)
        let reviews = ResponsiveBreakpointReviewPolicy.reviews(
            page: session.document.pages[0], selectedNodeIDs: [frameID])
        XCTAssertEqual(reviews.map(\.fluidValueCount), [1, 1, 1])
        XCTAssertTrue(reviews[0].primaryFluidSummary?.contains("Width 360") == true)
        XCTAssertTrue(reviews[2].primaryFluidSummary?.contains("Width 180") == true)
        let remove = FluidValueCommand(identity: .init(editID: GeometryInspectorEditID(),
            documentID: session.document.id, pageID: pageID, revision: session.document.revision,
            sceneID: sceneID, rendererGeneration: 7), orderedNodeIDs: selected,
            target: .width, value: nil, provenance: .pointer, cancelled: false)
        try session.execute(try registry.prepare(remove, in: session.document,
            context: context(session.document)).documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width)))
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionNumberProperty("layout.width"), 240)
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == frameID }?
            .insertionProperty(CanonicalFluidValueCodec.key(.width))?.id, propertyID)
    }

    // SF-0604-002/003/006/008 — renderer/layout and safe static output consume
    // the same canonical clamp, while a breakpoint literal remains the winner.
    func testFluidValueFeedsLayoutTypographyContainerAndSafeStaticOutputWithOverridePrecedence() throws {
        let width = CanonicalFluidValue(minimum: 160, preferred: 240, maximum: 400)
        let padding = CanonicalFluidValue(minimum: 12, preferred: 24, maximum: 48)
        let encodedWidth = try CanonicalFluidValueCodec.encode(width, target: .width)
        let encodedPadding = try CanonicalFluidValueCodec.encode(padding, target: .padding)
        var node = DocumentNode(kind: .section, name: "Fluid Section", parent: .page(PageID()), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .defaulted),
            .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .defaulted),
            .init(key: .init(rawValue: "layout.width"), value: .number(240), origin: .defaulted),
            .init(key: .init(rawValue: "layout.height"), value: .number(160), origin: .defaulted),
            .init(key: .init(rawValue: "layout.padding"), value: .number(24), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.width)), value: .string(encodedWidth), origin: .authored),
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.padding)), value: .string(encodedPadding), origin: .authored),
        ])
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .tablet,
                                                        viewportWidth: 768)?.0, 240)
        XCTAssertEqual(ResponsiveContainerLayoutResolver.value(for: .padding, node: node, breakpoint: .mobile,
                                                               viewportWidth: 390)?.0, .number(12))
        node.properties.append(.init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .tablet)),
                                     value: .number(222), origin: .authored))
        XCTAssertEqual(ResponsiveGeometryResolver.value(for: .width, node: node, breakpoint: .tablet,
                                                        viewportWidth: 768)?.0, 222)
        let css = StaticFluidValueOutputEmitter.emit(nodes: [node])
        XCTAssertTrue(css.contains("width: clamp(160px")); XCTAssertTrue(css.contains("padding: clamp(12px"))
        XCTAssertTrue(css.contains("@media (min-width: 768px)"))
    }

    // SF-0504/SF-0510/SF-0511 — positioning, reusable appearance, and the
    // bounded state vocabulary share one identity-gated transactional path.
    private func preparedReusableEdit(_ edit: AdvancedStyleEdit, session: DocumentSession,
                                     fixture: TransformFixture, ids: [NodeID]? = nil,
                                     cancelled: Bool = false) throws -> PreparedDesignInspectorEdit {
        let current = fixture.with(document: session.document), selected = ids ?? [fixture.nodeID]
        return try AdvancedStyleCommandRegistry().prepare(.init(identity: .init(documentID: session.document.id,
            pageID: fixture.pageID, revision: session.document.revision, sceneID: fixture.sceneID,
            rendererGeneration: fixture.rendererGeneration), orderedNodeIDs: selected, edit: edit,
            provenance: .keyboard, cancelled: cancelled), in: session.document,
            context: current.context(selectedIDs: selected))
    }

    // SF-0510-002/003/005: link/reorder/unlink preserve other links
    // independently on mixed selections, with one exact reversible transaction.
    func testReusableStyleLinksPreserveMixedOrderingAndExactHistory() throws {
        var fixture = makeFixture()
        let text = DocumentNode(kind: .text, name: "Caption", parent: .node(fixture.rootID), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(0)), .init(key: .init(rawValue: "layout.y"), value: .number(0)),
            .init(key: .init(rawValue: "layout.width"), value: .number(120)), .init(key: .init(rawValue: "layout.height"), value: .number(24))])
        fixture.document.pages[0].nodes[0].childIDs.append(text.id); fixture.document.pages[0].nodes.append(text)
        let session = DocumentSession(document: fixture.document), a = ReusableStyleID(), b = ReusableStyleID()
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF"))
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#0000FFFF"))
        for (id, name, color) in [(a, "First", red), (b, "Second", blue)] {
            try session.execute(try preparedReusableEdit(.createReusableStyle(id: id, name: name, fill: color, opacity: nil),
                session: session, fixture: fixture).documentCommand)
        }
        try session.execute(try preparedReusableEdit(.linkReusableStyle(a), session: session, fixture: fixture).documentCommand)
        try session.execute(try preparedReusableEdit(.linkReusableStyle(b), session: session, fixture: fixture,
            ids: [fixture.secondNodeID]).documentCommand)
        let before = session.document.pages
        let propertyID = try XCTUnwrap(before[0].nodes[1].insertionProperty(CanonicalReusableStyleIndex.appliedKey)?.id)
        let ids = [fixture.nodeID, fixture.secondNodeID, text.id]
        let edit = try preparedReusableEdit(.linkReusableStyle(b), session: session, fixture: fixture, ids: ids)
        XCTAssertEqual(edit.skippedNodeIDs, [text.id])
        try session.execute(edit.documentCommand)
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(session.document.pages[0].nodes[1]), [a, b])
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(session.document.pages[0].nodes[2]), [b])
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty(CanonicalReusableStyleIndex.appliedKey)?.id, propertyID)
        let linked = session.document.pages
        XCTAssertThrowsError(try preparedReusableEdit(.linkReusableStyle(b), session: session, fixture: fixture, ids: ids)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .noChanges)
        }
        try session.execute(try preparedReusableEdit(.moveReusableStyle(b, offset: -1), session: session, fixture: fixture, ids: ids).documentCommand)
        let reordered = session.document.pages
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(reordered[0].nodes[1]), [b, a])
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(reordered[0].nodes[2]), [b])
        let index = try CanonicalReusableStyleIndex(document: session.document)
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: reordered[0].nodes[1], index: index).fill, red)
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: reordered[0].nodes[2], index: index).fill, blue)
        try session.undo(); XCTAssertEqual(session.document.pages, linked)
        try session.redo(); XCTAssertEqual(session.document.pages, reordered)
        try session.execute(try preparedReusableEdit(.unlinkReusableStyle(b), session: session, fixture: fixture, ids: ids).documentCommand)
        XCTAssertEqual(CanonicalReusableStyleIndex.appliedIDs(session.document.pages[0].nodes[1]), [a])
        XCTAssertNil(session.document.pages[0].nodes[2].insertionProperty(CanonicalReusableStyleIndex.appliedKey))
        try session.undo(); XCTAssertEqual(session.document.pages, reordered)
        try session.undo(); try session.undo(); XCTAssertEqual(session.document.pages, before)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try preparedReusableEdit(.moveReusableStyle(a, offset: 99), session: session, fixture: fixture))
        XCTAssertThrowsError(try preparedReusableEdit(.linkReusableStyle(ReusableStyleID()), session: session, fixture: fixture))
        XCTAssertThrowsError(try preparedReusableEdit(.linkReusableStyle(b), session: session, fixture: fixture, cancelled: true)) {
            XCTAssertEqual($0 as? AdvancedStyleCommandError, .cancelled)
        }
        func diagnostic(_ styleID: ReusableStyleID) -> AdvancedStyleDiagnosticRecord {
            let command = AdvancedStyleCommand(identity: .init(documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: ids, edit: .linkReusableStyle(styleID), provenance: .keyboard, cancelled: false)
            return AdvancedStyleDiagnosticFactory.make(command: command, resultRevision: nil, result: .stale, failure: .stale)
        }
        XCTAssertEqual(diagnostic(a), diagnostic(b), "Style values/names/targets must not enter diagnostic payloads")
        XCTAssertEqual(diagnostic(a).operationType, "reusable.link")
    }

    // SF-0508-003/005, SF-0509-003/005, SF-0510-003/005: reset is
    // explicit inheritance, not None, token detach, or a baked equivalent fill.
    func testReusableResetProtectsNoneAndTokensAndRestoresGradientIdentities() throws {
        var fixture = makeFixture()
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF"))
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#0000FFFF"))
        let token = LocalColorToken(name: "Retained", color: blue)
        fixture.document.colorTokens = [token]
        let gradient = CanonicalFillLayer.linearGradient(angleDegrees: 45, stops: [
            .init(id: GradientStopID(), position: 0, color: red), .init(id: GradientStopID(), position: 1, color: blue)])
        let layers = [gradient, CanonicalFillLayer.solid(color: blue)]
        for (key, value) in CanonicalFillLayerCodec.propertyValues(for: layers).sorted(by: { $0.key < $1.key }) {
            fixture.document.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: key), value: value))
        }
        let opacity = NodeProperty(key: .init(rawValue: "style.opacity"), value: .number(0.9))
        fixture.document.pages[0].nodes[1].properties.append(opacity)
        fixture.document.pages[0].nodes[2].properties.append(.init(key: .init(rawValue: CanonicalFillLayerCodec.orderKey), value: .string("")))
        let session = DocumentSession(document: fixture.document), styleID = ReusableStyleID()
        try session.execute(try preparedReusableEdit(.createReusableStyle(id: styleID, name: "Linked", fill: red, opacity: 0.4),
            session: session, fixture: fixture).documentCommand)
        try session.execute(try preparedReusableEdit(.linkReusableStyle(styleID), session: session, fixture: fixture,
            ids: [fixture.nodeID, fixture.secondNodeID]).documentCommand)
        let original = session.document
        XCTAssertThrowsError(try preparedReusableEdit(.useLinkedAppearance(.fill), session: session, fixture: fixture,
            ids: [fixture.nodeID, fixture.secondNodeID]))
        XCTAssertEqual(session.document, original, "A protected None member rejects the entire reset, not just the later object")
        try session.execute(try preparedReusableEdit(.useLinkedAppearance(.fill), session: session, fixture: fixture).documentCommand)
        XCTAssertNil(CanonicalFillLayerCodec.layers(for: session.document.pages[0].nodes[1]))
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty("style.opacity"), opacity)
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: session.document.pages[0].nodes[1],
            index: CanonicalReusableStyleIndex(document: session.document)).fill, red)
        let resetFill = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, original.pages)
        XCTAssertEqual(CanonicalFillLayerCodec.layers(for: session.document.pages[0].nodes[1]), layers)
        try session.redo(); XCTAssertEqual(session.document.pages, resetFill)
        try session.execute(try preparedReusableEdit(.useLinkedAppearance(.opacity), session: session, fixture: fixture).documentCommand)
        XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty("style.opacity"))
        let current = session.document
        XCTAssertEqual(DesignInspectorCommandRegistry.opacityValue(nodes: [current.pages[0].nodes[1]],
            reusableStyles: try CanonicalReusableStyleIndex(document: current)), .single(0.4, .authored))
        let unchangedOpacity = DesignInspectorCommand(identity: .init(documentID: current.id, pageID: fixture.pageID,
            revision: current.revision, sceneID: fixture.sceneID, rendererGeneration: fixture.rendererGeneration),
            orderedNodeIDs: [fixture.nodeID], edit: .opacity(0.4), provenance: .keyboard, cancelled: false)
        XCTAssertThrowsError(try DesignInspectorCommandRegistry().prepare(unchangedOpacity, in: current,
            context: fixture.with(document: current).context)) { XCTAssertEqual($0 as? DesignInspectorError, .noChanges) }
        try session.undo(); XCTAssertEqual(session.document.pages[0].nodes[1].insertionProperty("style.opacity"), opacity)
        XCTAssertThrowsError(try preparedReusableEdit(.useLinkedAppearance(.fill), session: session, fixture: fixture,
            ids: [fixture.secondNodeID]))
        try session.execute(try preparedReusableEdit(.updateReusableStyle(id: styleID, name: "Linked", fill: blue, opacity: 0.6),
            session: session, fixture: fixture).documentCommand)
        let index = try CanonicalReusableStyleIndex(document: session.document)
        XCTAssertNil(try CanonicalResolvedAppearance.resolve(node: session.document.pages[0].nodes[2], index: index).fill)
        XCTAssertEqual(CanonicalFillLayerCodec.layers(for: session.document.pages[0].nodes[2]), [])
        XCTAssertEqual(session.document.colorTokens, [token])
        var bound = original
        bound.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
            value: .string(token.id.description)))
        try bound.validate()
        let boundSession = DocumentSession(document: bound)
        XCTAssertThrowsError(try preparedReusableEdit(.useLinkedAppearance(.fill), session: boundSession, fixture: fixture))
        XCTAssertEqual(boundSession.document, bound)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    // SF-0510-002/003, SF-0509-003: snapshots are explicit solid/opacity
    // values, never accidental gradient flattening or source-token detachment.
    func testReusableCaptureRejectsMixedComplexAndNoneWithoutDetachingTokens() throws {
        var fixture = makeFixture()
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#CC2233FF"))
        let token = LocalColorToken(name: "Source", color: red)
        fixture.document.colorTokens = [token]
        for index in 1...2 {
            for (key, value) in CanonicalFillLayerCodec.propertyValues(for: [.solid(color: red)]).sorted(by: { $0.key < $1.key }) {
                fixture.document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: key), value: value))
            }
            fixture.document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: "style.opacity"), value: .number(0.5)))
        }
        fixture.document.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
            value: .string(token.id.description)))
        try fixture.document.validate()
        let before = fixture.document
        let capture = try AdvancedStyleCommandRegistry.captureSelection(Array(before.pages[0].nodes[1...2]), in: before)
        XCTAssertEqual(capture.fill, red); XCTAssertEqual(capture.opacity, 0.5); XCTAssertEqual(capture.boundFillCount, 1)
        var mixed = before
        let opacityIndex = try XCTUnwrap(mixed.pages[0].nodes[2].properties.firstIndex { $0.key.rawValue == "style.opacity" })
        mixed.pages[0].nodes[2].properties[opacityIndex].value = .number(0.6)
        XCTAssertThrowsError(try AdvancedStyleCommandRegistry.captureSelection(Array(mixed.pages[0].nodes[1...2]), in: mixed))
        for layers in [[CanonicalFillLayer](), [.linearGradient(angleDegrees: 45, stops: [
            .init(id: GradientStopID(), position: 0, color: red), .init(id: GradientStopID(), position: 1, color: red)])]] {
            var unsupported = before
            unsupported.pages[0].nodes[1].properties.removeAll {
                $0.key.rawValue.hasPrefix("style.fill.layers.v1.") || $0.key.rawValue == LocalColorTokenBinding.key(for: .fill)
            }
            unsupported.pages[0].nodes[1].properties += CanonicalFillLayerCodec.propertyValues(for: layers).map {
                .init(key: .init(rawValue: $0.key), value: $0.value)
            }
            XCTAssertThrowsError(try AdvancedStyleCommandRegistry.captureSelection([unsupported.pages[0].nodes[1]], in: unsupported))
        }
        XCTAssertEqual(fixture.document, before)
    }

    // SF-0510-003/005/006, SF-0508-003, SF-0509-003: immutable native
    // adoption, effective Inspector and compiler agree without recoloring None
    // or breaking a different page's/token-bound local override.
    func testReusableLinksAdoptSharedAppearanceWithoutRevivingNoneOrTokenOverrides() async throws {
        var fixture = makeFixture()
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF0000FF"))
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#0000FFFF"))
        let orange = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#FF8800FF"))
        let green = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#00FF00FF"))
        let token = LocalColorToken(name: "Local green", color: green)
        fixture.document.colorTokens = [token]
        fixture.document.pages[0].nodes[2].properties.append(.init(key: .init(rawValue: CanonicalFillLayerCodec.orderKey), value: .string("")))
        func frame(parent: NodeID, name: String) -> DocumentNode {
            .init(kind: .frame, name: name, parent: .node(parent), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(400)), .init(key: .init(rawValue: "layout.y"), value: .number(40)),
                .init(key: .init(rawValue: "layout.width"), value: .number(120)), .init(key: .init(rawValue: "layout.height"), value: .number(80))])
        }
        var tokenNode = frame(parent: fixture.rootID, name: "Token local")
        tokenNode.properties += CanonicalFillLayerCodec.propertyValues(for: [.solid(color: blue)]).map {
            .init(key: .init(rawValue: $0.key), value: $0.value)
        }
        tokenNode.properties.append(.init(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)), value: .string(token.id.description)))
        fixture.document.pages[0].nodes[0].childIDs.append(tokenNode.id); fixture.document.pages[0].nodes.append(tokenNode)
        let setup = DocumentSession(document: fixture.document), a = ReusableStyleID(), b = ReusableStyleID()
        for (id, name, color, opacity) in [(a, "First", red, 0.4), (b, "Second", blue, 0.7)] {
            try setup.execute(try preparedReusableEdit(.createReusableStyle(id: id, name: name, fill: color, opacity: opacity),
                session: setup, fixture: fixture).documentCommand)
        }
        try setup.execute(try preparedReusableEdit(.applyReusableStyles([a, b]), session: setup, fixture: fixture).documentCommand)
        try setup.execute(try preparedReusableEdit(.linkReusableStyle(a), session: setup, fixture: fixture,
            ids: [fixture.secondNodeID, tokenNode.id]).documentCommand)
        var document = setup.document, peerPage = DocumentPage(name: "Peer style page")
        var peer = frame(parent: peerPage.rootNodeIDs[0], name: "Peer linked")
        peer.properties.append(.init(key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(a.description)))
        peerPage.nodes[0].childIDs.append(peer.id); peerPage.nodes.append(peer); document.pages.append(peerPage)
        try document.validate()
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
        await adopt(); state.selectLayer(fixture.nodeID)
        XCTAssertEqual(state.designInspectorFillValue(), .single(blue, .authored))
        XCTAssertEqual(state.designInspectorOpacityValue(), .single(0.7, .authored))
        let initialObject = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == fixture.nodeID })
        let opening = state.responsiveInspectorEditContext
        XCTAssertEqual(state.reusableStyleUsage[a]?.objects, 4)
        XCTAssertEqual(state.reusableStyleUsage[a]?.pages, 2)
        XCTAssertTrue(state.commitAdvancedStyle(.updateReusableStyle(id: a, name: "First", fill: orange, opacity: 0.6),
            operation: "confirmed shared update", expectedContext: opening))
        await adopt()
        XCTAssertEqual(state.designInspectorFillValue(), .single(blue, .authored), "Later linked values still win")
        let none = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == fixture.secondNodeID })
        XCTAssertEqual(none.fillRGBA, [0, 0, 0, 0])
        let bound = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first { $0.id == tokenNode.id })
        XCTAssertEqual(bound.fillLayers.first?.rgba, [green.red, green.green, green.blue, green.alpha])
        XCTAssertEqual(live.document.colorTokens, document.colorTokens)
        XCTAssertEqual(live.document.pages[0].nodes.first { $0.id == tokenNode.id }?.properties,
            document.pages[0].nodes.first { $0.id == tokenNode.id }?.properties)
        let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 1000, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1440, height: 900)), pixelRatio: .init(2))
        let peerScene = try await WorkspaceScenePreparationWorker().prepare(.init(document: live.document, activePageID: peerPage.id,
            activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID(), breakpoint: .desktop, viewportWidth: 1440))
        XCTAssertEqual(peerScene.renderScene.objects.first { $0.id == peer.id }?.fillRGBA, [orange.red, orange.green, orange.blue, orange.alpha])
        XCTAssertEqual(peerScene.renderScene.objects.first { $0.id == peer.id }?.opacity, 0.6)
        XCTAssertTrue(state.commitAdvancedStyle(.moveReusableStyle(b, offset: -1), operation: "earlier link",
            expectedContext: state.responsiveInspectorEditContext))
        await adopt()
        XCTAssertEqual(state.designInspectorFillValue(), .single(orange, .authored))
        XCTAssertEqual(state.designInspectorOpacityValue(), .single(0.6, .authored))
        XCTAssertTrue(state.reusableAppearanceSource(.opacity).contains("First"))
        let count = live.historySnapshot().undoEntries.count
        XCTAssertTrue(state.commitDesignOpacity(percent: 60, provenance: .focusLoss))
        XCTAssertNil(live.document.pages[0].nodes[1].insertionProperty("style.opacity"))
        XCTAssertEqual(live.historySnapshot().undoEntries.count, count)
        let current = live.document
        XCTAssertFalse(state.commitDesignOpacity(percent: 70, provenance: .focusLoss, expectedContext: opening),
            "A queued field from the prior shared-style revision must not create a local opacity override")
        XCTAssertEqual(live.document, current)
        XCTAssertEqual(live.historySnapshot().undoEntries.count, count)
        XCTAssertFalse(state.commitAdvancedStyle(.unlinkReusableStyle(a), operation: "stale dialog", expectedContext: opening))
        XCTAssertEqual(live.document, current)
        XCTAssertEqual(initialObject.fillRGBA, [blue.red, blue.green, blue.blue, blue.alpha], "Earlier immutable snapshots do not mix with current style order")
        let plan = try MultiPageStaticBuildPlanner.plan(document: current)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let selectedRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: fixture.nodeID) + " {") }.joined()
        XCTAssertTrue(selectedRules.contains("background-color: rgba(255.0, 136.0, 0.0, 1.0)"))
        let noneRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: fixture.secondNodeID) + " {") }.joined()
        XCTAssertFalse(noneRules.contains("background-color: rgba("))
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: DocumentSerializer.decode(DocumentSerializer.encode(current))).files, plan.files)
    }

    func testAdvancedStyleRegistryHistoryPersistenceAndSafeStaticProjection() throws {
        let fixture = makeFixture()
        let session = DocumentSession(document: fixture.document)
        let styleID = ReusableStyleID(UUID(uuidString: "97000000-0000-4000-8000-000000000001")!)
        let stateID = UUID(uuidString: "97000000-0000-4000-8000-000000000002")!
        let red = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#CC1A33FF"))
        let blue = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#1A33CCFF"))
        let registry = AdvancedStyleCommandRegistry()
        func node() -> DocumentNode { session.document.pages[0].nodes.first { $0.id == fixture.nodeID }! }
        func prepare(_ edit: AdvancedStyleEdit, cancelled: Bool = false) throws -> PreparedDesignInspectorEdit {
            let command = AdvancedStyleCommand(identity: .init(
                documentID: session.document.id, pageID: fixture.pageID,
                revision: session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID], edit: edit,
                provenance: .automation, cancelled: cancelled)
            return try registry.prepare(command, in: session.document,
                context: fixture.context(selectedIDs: [fixture.nodeID]))
        }

        try session.execute(try prepare(.createReusableStyle(
            id: styleID, name: "Card", fill: red, opacity: 0.75)).documentCommand)
        try session.execute(try prepare(.applyReusableStyles([styleID])).documentCommand)
        let appliedID = try XCTUnwrap(node().insertionProperty(CanonicalReusableStyleIndex.appliedKey)?.id)
        try session.execute(try prepare(.positionMode(.absolute)).documentCommand)
        try session.execute(try prepare(.positionInset(.top, 24)).documentCommand)
        try session.execute(try prepare(.zIndex(7)).documentCommand)
        try session.execute(try prepare(.setState(
            state: .hover, id: stateID, fill: blue, opacity: 0.5)).documentCommand)

        let index = try CanonicalReusableStyleIndex(document: session.document)
        XCTAssertEqual(index.byID[styleID]?.name, "Card")
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: node(), index: index).fill, red)
        XCTAssertEqual(try CanonicalResolvedAppearance.resolve(node: node(), index: index, state: .hover).fill, blue)
        XCTAssertEqual(CanonicalPositioning.resolve(node())?.top, 24)
        XCTAssertEqual(CanonicalPositioning.resolve(node())?.zIndex, 7)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        let css = try XCTUnwrap(MultiPageStaticBuildPlanner.plan(document: session.document)
            .files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("position: absolute"), css)
        XCTAssertTrue(css.contains("top: 24.0px"), css)
        XCTAssertTrue(css.contains("z-index: 7"), css)
        XCTAssertTrue(css.contains(":hover"), css)
        XCTAssertTrue(css.contains("background-color: rgba(26.0, 51.0, 204.0, 1.0)"), css)
        XCTAssertFalse(css.contains("Card"), css)

        try session.undo()
        XCTAssertNil(node().insertionProperty(CanonicalReusableStyleIndex.stateNamespace + "hover.id"))
        try session.redo()
        XCTAssertEqual(node().insertionStringProperty(CanonicalReusableStyleIndex.stateNamespace + "hover.id"),
                       stateID.uuidString.lowercased())
        XCTAssertEqual(node().insertionProperty(CanonicalReusableStyleIndex.appliedKey)?.id, appliedID)
        XCTAssertThrowsError(try prepare(.positionInset(.left, .infinity)))
        XCTAssertThrowsError(try prepare(.applyReusableStyles([styleID]), cancelled: true))
    }

    func testAdvancedStyleMixedSelectionStaleValidationAndRedactedDiagnostics() throws {
        var fixture = makeFixture(selectedIDs: [])
        fixture.document.pages[0].nodes[2].kind = .text
        let styleID = ReusableStyleID(UUID(uuidString: "97000000-0000-4000-8000-000000000003")!)
        let session = DocumentSession(document: fixture.document)
        let registry = AdvancedStyleCommandRegistry()
        func command(_ edit: AdvancedStyleEdit, revision: UInt64? = nil) -> AdvancedStyleCommand {
            .init(identity: .init(documentID: session.document.id, pageID: fixture.pageID,
                revision: revision ?? session.document.revision, sceneID: fixture.sceneID,
                rendererGeneration: fixture.rendererGeneration),
                orderedNodeIDs: [fixture.nodeID, fixture.secondNodeID], edit: edit,
                provenance: .automation, cancelled: false)
        }
        let create = AdvancedStyleCommand(identity: command(.zIndex(0)).identity,
            orderedNodeIDs: [fixture.nodeID], edit: .createReusableStyle(
                id: styleID, name: "Surface", fill: .legacySurface, opacity: 1),
            provenance: .automation, cancelled: false)
        try session.execute(try registry.prepare(create, in: session.document,
            context: fixture.context(selectedIDs: [fixture.nodeID])).documentCommand)
        let mixed = command(.applyReusableStyles([styleID]))
        let prepared = try registry.prepare(mixed, in: session.document,
            context: fixture.context(selectedIDs: mixed.orderedNodeIDs))
        XCTAssertEqual(prepared.applicableNodeIDs, [fixture.nodeID])
        XCTAssertEqual(prepared.skippedNodeIDs, [fixture.secondNodeID])
        try session.execute(prepared.documentCommand)
        XCTAssertNil(session.document.pages[0].nodes.first { $0.id == fixture.secondNodeID }?
            .insertionProperty(CanonicalReusableStyleIndex.appliedKey))
        XCTAssertThrowsError(try registry.prepare(command(.zIndex(1), revision: 0),
            in: session.document, context: fixture.context(selectedIDs: [fixture.nodeID, fixture.secondNodeID])))

        var malformed = session.document
        let rootIndex = try XCTUnwrap(malformed.pages[0].nodes.firstIndex { $0.id == fixture.rootID })
        malformed.pages[0].nodes[rootIndex].properties.append(.init(
            key: .init(rawValue: CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description).fill"),
            value: .string("not-a-color"), origin: .authored))
        XCTAssertThrowsError(try malformed.validate())

        let record = AdvancedStyleDiagnosticFactory.make(
            command: mixed, resultRevision: session.document.revision,
            result: .success, failure: nil)
        XCTAssertEqual(record.sanitizedIdentifiers.count, 2)
        XCTAssertFalse(record.sanitizedIdentifiers.joined().contains(fixture.nodeID.description))
        XCTAssertTrue(record.requirementIDs.contains("SF-0511-008"))
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
        revision: UInt64? = nil,
        breakpoint: ResponsiveBreakpoint = .desktop,
        removesOverride: Bool = false
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
            provenance: .automation,
            breakpoint: breakpoint,
            removesOverride: removesOverride
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
    case .frame, .text, .image, .button, .link, .form, .component:
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
