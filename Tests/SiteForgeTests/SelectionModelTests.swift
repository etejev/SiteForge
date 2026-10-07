import XCTest
@testable import SiteForge

final class SelectionModelTests: XCTestCase {
    // SF-0205-002/003 — Quick Open composes existing authorized projections.
    func testQuickOpenResultsKeepPageThenCurrentLayerIdentityWithoutMutation() throws {
        let fixture = try makeFixture(count: 2)
        let home = DocumentPage(name: "Home", route: .init(rawValue: "/"), role: .home)
        let notFound = DocumentPage(name: "Not Found", route: .init(rawValue: "/404"), role: .notFound)
        let pages = [home, notFound]
        let targets = fixture.targets
        let pageResult = QuickOpenSearchPolicy.results(pages: pages, layers: targets, query: "/404")
        XCTAssertEqual(pageResult.pages.map(\.id), [notFound.id])
        XCTAssertTrue(pageResult.layers.isEmpty)
        let layerResult = QuickOpenSearchPolicy.results(pages: pages, layers: targets, query: "OBJECT 2")
        XCTAssertTrue(layerResult.pages.isEmpty)
        XCTAssertEqual(layerResult.layers.map(\.id), [fixture.ids[1]])
        let all = QuickOpenSearchPolicy.results(pages: pages, layers: targets, query: "")
        XCTAssertEqual(all.pages.map(\.id), pages.map(\.id))
        XCTAssertEqual(all.layers.map(\.id), targets.map(\.id))
        XCTAssertEqual(targets, fixture.targets)
    }

    // SF-0205-002/003 — only approved editor View commands are discoverable.
    func testQuickOpenViewActionsAreClosedOrderedAndQueryDeterministic() {
        XCTAssertEqual(QuickOpenViewAction.matches(""), [.fitDocument, .actualSize, .toggleGrid])
        XCTAssertEqual(QuickOpenViewAction.matches("  FIT DOCUMENT  "), [.fitDocument])
        XCTAssertEqual(QuickOpenViewAction.matches("grid"), [.toggleGrid])
        XCTAssertTrue(QuickOpenViewAction.matches("delete project").isEmpty)
        let result = QuickOpenSearchPolicy.results(pages: [], layers: [], query: "actual")
        XCTAssertTrue(result.pages.isEmpty && result.layers.isEmpty)
        XCTAssertEqual(result.actions, [.actualSize])
    }

    // SF-AUTHORING-075, SF-0205-003/006, SF-0405-002/006
    func testQuickOpenBasicInsertActionsAreClosedAndSearchable() {
        XCTAssertEqual(QuickOpenInsertAction.matches("insert frame", hasSelectedImageAsset: false), [.frame])
        XCTAssertEqual(QuickOpenInsertAction.matches(" TEXT ", hasSelectedImageAsset: false), [.text])
        XCTAssertTrue(QuickOpenInsertAction.matches("delete project", hasSelectedImageAsset: false).isEmpty)
        XCTAssertEqual(QuickOpenInsertAction.frame.insertionKind, .frame)
        XCTAssertEqual(QuickOpenInsertAction.text.insertionKind, .text)
    }

    // SF-AUTHORING-076, SF-0205-003/006, SF-0502-002, SF-0503-002
    func testQuickOpenStructuralInsertActionsPreserveCanonicalKindsAndOrder() {
        let structural: [QuickOpenInsertAction] = [.section, .stack, .grid]
        XCTAssertEqual(structural.compactMap(\.insertionKind), [.section, .stack, .grid])
        let results = QuickOpenSearchPolicy.results(pages: [], layers: [], query: "insert", scope: .actions)
        XCTAssertEqual(results.insertions.filter { structural.contains($0) }, structural)
    }

    // SF-AUTHORING-077, SF-0205-003/006, SF-0405-002/006
    func testQuickOpenSiteControlsRouteOnlyToSupportedInsertionKinds() {
        XCTAssertEqual([QuickOpenInsertAction.button, .link, .form].compactMap(\.insertionKind), [.button, .link, .form])
        XCTAssertEqual(QuickOpenInsertAction.matches("insert link", hasSelectedImageAsset: false), [.link])
        XCTAssertTrue(QuickOpenInsertAction.matches("navbar", hasSelectedImageAsset: false).isEmpty)
    }

    // SF-AUTHORING-078, SF-0205-004/006, SF-0801-002, SF-0802-002
    func testQuickOpenImageInsertionRequiresSelectedAssetButImportRemainsDiscoverable() {
        let withoutAsset = QuickOpenInsertAction.matches("image", hasSelectedImageAsset: false)
        XCTAssertEqual(withoutAsset, [.importImage])
        let withAsset = QuickOpenInsertAction.matches("image", hasSelectedImageAsset: true)
        XCTAssertEqual(withAsset, [.selectedImage, .importImage])
        XCTAssertEqual(QuickOpenInsertAction.selectedImage.insertionKind, .image)
        XCTAssertEqual(QuickOpenInsertAction.importImage.insertionKind, .image)
    }

    // SF-AUTHORING-079, SF-0205-002/003, SF-0303-002/006
    func testQuickOpenNewPageActionIsClosedAndQueryDeterministic() {
        XCTAssertEqual(QuickOpenPageAction.matches("new page"), [.newPage])
        XCTAssertEqual(QuickOpenPageAction.matches("  NEW PAGE  "), [.newPage])
        XCTAssertTrue(QuickOpenPageAction.matches("delete page").isEmpty)
        let actions = QuickOpenSearchPolicy.results(pages: [], layers: [], query: "new page", scope: .actions)
        XCTAssertEqual(actions.pageActions, [.newPage])
        XCTAssertTrue(actions.pages.isEmpty && actions.layers.isEmpty)
    }

    // SF-AUTHORING-080, SF-0205-003/004, SF-0901-003
    func testComponentSearchPreservesDefinitionIdentityOrderAndEmptyRecovery() {
        let first = DocumentPage(name: "Résumé Card", route: .init(rawValue: "/component-card"), role: .componentDefinition)
        let second = DocumentPage(name: "Footer", route: .init(rawValue: "/component-footer"), role: .componentDefinition)
        let definitions = [first, second]
        XCTAssertEqual(ComponentSearchPolicy.results(in: definitions, query: "resume").map(\.id), [first.id])
        XCTAssertEqual(ComponentSearchPolicy.results(in: definitions, query: "").map(\.id), definitions.map(\.id))
        XCTAssertTrue(ComponentSearchPolicy.results(in: definitions, query: "missing").isEmpty)
    }

    // SF-AUTHORING-081, SF-0205-003/004, SF-0801-003
    func testAssetUsageFilterSeparatesUsedUnusedWithoutChangingIdentity() {
        XCTAssertEqual(AssetUsageFilter.allCases, [.all, .used, .unused])
        XCTAssertTrue(AssetUsageFilter.all.includes(0))
        XCTAssertTrue(AssetUsageFilter.all.includes(3))
        XCTAssertFalse(AssetUsageFilter.used.includes(0))
        XCTAssertTrue(AssetUsageFilter.used.includes(3))
        XCTAssertTrue(AssetUsageFilter.unused.includes(0))
        XCTAssertFalse(AssetUsageFilter.unused.includes(3))
    }

    // SF-AUTHORING-082, SF-0205-003/004, SF-0801-003
    func testQuickOpenImageAssetResultsUseStableIDsAndBoundedNameProjection() {
        let first = ImageAsset(resourceID: ResourceID(), displayName: "Hero Art", originalFilename: "hero.png",
            format: .png, pixelWidth: 10, pixelHeight: 10, byteCount: 100, contentHash: String(repeating: "a", count: 64))
        let second = ImageAsset(resourceID: ResourceID(), displayName: "Footer", originalFilename: "footer.png",
            format: .png, pixelWidth: 10, pixelHeight: 10, byteCount: 100, contentHash: String(repeating: "b", count: 64))
        let assets = [first, second]
        XCTAssertEqual(QuickOpenAssetSearchPolicy.results(in: assets, query: "HERO").map(\.id), [first.id])
        XCTAssertEqual(QuickOpenAssetSearchPolicy.results(in: assets, query: "footer.png").map(\.id), [second.id])
        XCTAssertTrue(QuickOpenAssetSearchPolicy.results(in: assets, query: "missing").isEmpty)
        XCTAssertEqual(QuickOpenSearchPolicy.results(pages: [], layers: [], query: "hero", assets: assets).assets.map(\.id), [first.id])
        XCTAssertTrue(QuickOpenSearchPolicy.results(pages: [], layers: [], query: "hero", scope: .actions, assets: assets).assets.isEmpty)
    }

    // SF-AUTHORING-083, SF-0205-003/004, SF-0902-002
    func testQuickOpenComponentResultsKeepDefinitionIDsAndActionScopeSeparate() {
        let first = DocumentPage(name: "Header Card", route: .init(rawValue: "/component-header"), role: .componentDefinition)
        let second = DocumentPage(name: "Footer Card", route: .init(rawValue: "/component-footer"), role: .componentDefinition)
        let results = QuickOpenSearchPolicy.results(pages: [], layers: [], query: "footer", components: [first, second])
        XCTAssertEqual(results.components.map(\.id), [second.id])
        XCTAssertTrue(QuickOpenSearchPolicy.results(pages: [], layers: [], query: "footer", scope: .actions,
            components: [first, second]).components.isEmpty)
    }

    // SF-0205-003/004 — stale/missing NodeIDs cannot become recent targets.
    func testQuickOpenRecentLayersBoundDeduplicateAndProjectOnlyAuthorizedNodes() throws {
        let fixture = try makeFixture(count: 3)
        let first = QuickOpenRecentLayerPolicy.recording(fixture.ids[0], in: [])
        let second = QuickOpenRecentLayerPolicy.recording(fixture.ids[1], in: first)
        XCTAssertEqual(QuickOpenRecentLayerPolicy.recording(fixture.ids[0], in: second), [fixture.ids[0], fixture.ids[1]])
        XCTAssertEqual(QuickOpenRecentLayerPolicy.recording(fixture.ids[2], in: second, limit: 2), [fixture.ids[2], fixture.ids[1]])
        XCTAssertEqual(QuickOpenRecentLayerPolicy.available([NodeID(), fixture.ids[1], fixture.ids[0]], in: fixture.targets).map(\.id), [fixture.ids[1], fixture.ids[0]])
        XCTAssertEqual(QuickOpenRecentLayerPolicy.recording(fixture.ids[2], in: second, limit: 0), [])
    }

    // SF-0205-003/004 — scope removes result classes without reordering or
    // changing the underlying page/NodeID/action projections.
    func testQuickOpenScopesFilterResultClassesDeterministically() throws {
        let fixture = try makeFixture(count: 1)
        let home = DocumentPage(name: "Home", route: .init(rawValue: "/"), role: .home)
        let pages = [home]
        let layers = fixture.targets
        let all = QuickOpenSearchPolicy.results(pages: pages, layers: layers, query: "", scope: .all)
        XCTAssertEqual(all.pages.map(\.id), [home.id])
        XCTAssertEqual(all.layers.map(\.id), [fixture.ids[0]])
        XCTAssertEqual(all.actions, QuickOpenViewAction.allCases)
        let pageOnly = QuickOpenSearchPolicy.results(pages: pages, layers: layers, query: "", scope: .pages)
        XCTAssertEqual(pageOnly.pages.map(\.id), [home.id])
        XCTAssertTrue(pageOnly.layers.isEmpty && pageOnly.actions.isEmpty)
        let layerOnly = QuickOpenSearchPolicy.results(pages: pages, layers: layers, query: "", scope: .layers)
        XCTAssertEqual(layerOnly.layers.map(\.id), [fixture.ids[0]])
        XCTAssertTrue(layerOnly.pages.isEmpty && layerOnly.actions.isEmpty)
        let actionsOnly = QuickOpenSearchPolicy.results(pages: pages, layers: layers, query: "grid", scope: .actions)
        XCTAssertEqual(actionsOnly.actions, [.toggleGrid])
        XCTAssertTrue(actionsOnly.pages.isEmpty && actionsOnly.layers.isEmpty)
    }

    // SF-0205-002/003/004 — filtering is a stable view of authorized targets.
    func testLayerSearchPreservesTargetIdentityPaintOrderAndSelectionSnapshot() throws {
        let fixture = try makeFixture(count: 3)
        let first = SelectionTargetSnapshot(
            id: fixture.ids[0], pageID: fixture.pageID, parentID: nil, name: "Résumé Frame",
            frame: fixture.targets[0].frame, clipRect: nil, paintOrder: 0,
            isVisible: true, isLocked: false, isAvailable: true
        )
        let second = SelectionTargetSnapshot(
            id: fixture.ids[1], pageID: fixture.pageID, parentID: nil, name: "Frame Card",
            frame: fixture.targets[1].frame, clipRect: nil, paintOrder: 1,
            isVisible: true, isLocked: false, isAvailable: true
        )
        let third = SelectionTargetSnapshot(
            id: fixture.ids[2], pageID: fixture.pageID, parentID: nil, name: "Text",
            frame: fixture.targets[2].frame, clipRect: nil, paintOrder: 2,
            isVisible: true, isLocked: false, isAvailable: true
        )
        let targets = [first, second, third]
        let original = targets
        XCTAssertEqual(LayerSearchPolicy.results(in: targets, query: " FRAME ").map(\.id), [first.id, second.id])
        XCTAssertEqual(LayerSearchPolicy.results(in: targets, query: "RÉSUMÉ").map(\.id), [first.id])
        XCTAssertTrue(LayerSearchPolicy.results(in: targets, query: "no matching layer").isEmpty)
        XCTAssertEqual(LayerSearchPolicy.results(in: targets, query: " \n ").map(\.id), targets.map(\.id))
        XCTAssertEqual(targets, original)
    }

    // SF-0205-003/004 — type and name predicates compose without broadening
    // the authorized target set or changing canonical target identity.
    func testLayerTypeFilterComposesWithNameAndRetainsCanonicalOrder() throws {
        let fixture = try makeFixture(count: 3)
        let frame = SelectionTargetSnapshot(
            id: fixture.ids[0], pageID: fixture.pageID, parentID: nil, name: "Hero",
            kind: .frame, frame: fixture.targets[0].frame, clipRect: nil, paintOrder: 0,
            isVisible: true, isLocked: false, isAvailable: true
        )
        let text = SelectionTargetSnapshot(
            id: fixture.ids[1], pageID: fixture.pageID, parentID: nil, name: "Hero Text",
            kind: .text, frame: fixture.targets[1].frame, clipRect: nil, paintOrder: 1,
            isVisible: true, isLocked: false, isAvailable: true
        )
        let frame2 = SelectionTargetSnapshot(
            id: fixture.ids[2], pageID: fixture.pageID, parentID: nil, name: "Card",
            kind: .frame, frame: fixture.targets[2].frame, clipRect: nil, paintOrder: 2,
            isVisible: true, isLocked: false, isAvailable: true
        )
        let targets = [frame, text, frame2]
        XCTAssertEqual(LayerSearchPolicy.results(in: targets, query: "", kind: .frame).map(\.id), [frame.id, frame2.id])
        XCTAssertEqual(LayerSearchPolicy.results(in: targets, query: "hero", kind: .text).map(\.id), [text.id])
        XCTAssertTrue(LayerSearchPolicy.results(in: targets, query: "card", kind: .text).isEmpty)
        XCTAssertEqual(LayerSearchPolicy.results(in: targets, query: "", kind: nil).map(\.id), targets.map(\.id))
    }

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

    // SF-0402-001 through SF-0402-004, SF-0508-002 — additive Layers
    // selection is ordered, remains valid through renderer adoption, and
    // exposes mixed Design applicability without changing either identity.
    func testSiblingFrameAndTextLayerAdditiveSelectionPreservesSemanticState() throws {
        let fixture = try makeFixture(count: 2)
        let frameID = fixture.ids[0]
        let textID = fixture.ids[1]
        let targets = [
            SelectionTargetSnapshot(
                id: frameID, pageID: fixture.pageID, parentID: nil, name: "Frame",
                frame: fixture.targets[0].frame, clipRect: nil, paintOrder: 0,
                isVisible: true, isLocked: false, isAvailable: true, participatesInCanvasTraversal: true
            ),
            SelectionTargetSnapshot(
                id: textID, pageID: fixture.pageID, parentID: nil, name: "Text",
                frame: fixture.targets[1].frame, clipRect: nil, paintOrder: 1,
                isVisible: true, isLocked: false, isAvailable: true, participatesInCanvasTraversal: true
            ),
        ]
        let scene = SelectionSceneSnapshot(
            identity: fixture.identity, activePageID: fixture.pageID,
            activeContainerID: nil, targets: targets
        )
        let registry = SelectionCommandRegistry()
        var state = SelectionState()
        _ = try registry.adopt(scene, boundary: .documentAdoption, state: &state)
        try registry.apply(
            .init(.replace, targetID: frameID, expectedIdentity: fixture.identity, provenance: .layersNavigator),
            to: &state, scene: scene
        )
        try registry.apply(
            .init(.add, targetID: textID, expectedIdentity: fixture.identity, provenance: .layersNavigator),
            to: &state, scene: scene
        )
        XCTAssertEqual(state.orderedIDs, [frameID, textID])
        XCTAssertEqual(state.primaryID, textID)
        XCTAssertEqual(state.anchorID, frameID)
        XCTAssertEqual(try registry.adopt(scene, boundary: .rendererGeneration, state: &state), .none)
        XCTAssertEqual(state.orderedIDs, [frameID, textID])

        let frame = DocumentNode(
            id: frameID, kind: .frame, name: "Frame", parent: .page(fixture.pageID),
            properties: [NodeProperty(key: .init(rawValue: "style.fill"), value: .string("surface"), origin: .defaulted)]
        )
        let text = DocumentNode(id: textID, kind: .text, name: "Text", parent: .page(fixture.pageID))
        XCTAssertEqual(DesignInspectorCommandRegistry.fillValue(nodes: [frame, text]), .mixed)
    }

    func testRootOverlaySuppression() throws {
        var fixture = try makeFixture(count: 1)
        fixture.targets[0] = fixture.targets[0].copy(participatesInCanvasTraversal: false)
        fixture = fixture.rebuilt()
        let structuralID = fixture.ids[0]
        let registry = SelectionCommandRegistry()
        var state = SelectionState()
        _ = try registry.adopt(fixture.scene, boundary: .documentAdoption, state: &state)

        let result = try registry.apply(
            .init(.replace, targetID: structuralID, expectedIdentity: fixture.identity, provenance: .layersNavigator),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(result, .changed)
        XCTAssertEqual(state.orderedIDs, [structuralID])
        XCTAssertEqual(state.primaryID, structuralID)
        XCTAssertEqual(state.anchorID, structuralID)
        let overlay = try SelectionOverlayPlanner().plan(selection: state, scene: fixture.scene, renderPlan: try renderPlan(fixture))
        XCTAssertTrue(overlay.overlays.isEmpty)
    }

    // SF-0603-003/006 — hidden-at-breakpoint nodes remain inspectable only
    // through Layers. They never become canvas hit/overlay targets.
    func testHiddenBreakpointSelectionIsLayersInspectableWithoutCanvasChrome() throws {
        var fixture = try makeFixture(count: 1)
        fixture.targets[0] = fixture.targets[0].copy(isVisible: false, participatesInCanvasTraversal: false)
        fixture = fixture.rebuilt()
        let hiddenID = fixture.ids[0]
        let registry = SelectionCommandRegistry()
        var state = SelectionState()
        _ = try registry.adopt(fixture.scene, boundary: .documentAdoption, state: &state)

        XCTAssertThrowsError(try registry.apply(
            .init(.replace, targetID: hiddenID, expectedIdentity: fixture.identity, provenance: .pointer),
            to: &state, scene: fixture.scene
        )) {
            XCTAssertEqual($0 as? SelectionCommandError, .disabled(
                "Hidden objects cannot be selected from the canvas; use Layers to inspect or restore them."
            ))
        }

        XCTAssertEqual(try registry.apply(
            .init(.replace, targetID: hiddenID, expectedIdentity: fixture.identity, provenance: .layersNavigator),
            to: &state, scene: fixture.scene
        ), .changed)
        XCTAssertEqual(state.orderedIDs, [hiddenID])
        XCTAssertEqual(try registry.adopt(fixture.scene, boundary: .rendererGeneration, state: &state), .none)
        XCTAssertEqual(state.orderedIDs, [hiddenID])
        let overlay = try SelectionOverlayPlanner().plan(
            selection: state, scene: fixture.scene, renderPlan: try renderPlan(fixture)
        )
        XCTAssertTrue(overlay.overlays.isEmpty)
        XCTAssertFalse(try renderPlan(fixture).accessibilityElements.contains { $0.objectID == hiddenID })
    }

    func testAuthoredOverlay() throws {
        var fixture = try makeFixture(count: 1)
        let authoredID = fixture.ids[0]
        let registry = SelectionCommandRegistry()
        var state = SelectionState()
        _ = try registry.adopt(fixture.scene, boundary: .documentAdoption, state: &state)

        let result = try registry.apply(
            .init(.replace, targetID: authoredID, expectedIdentity: fixture.identity, provenance: .pointer),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(result, .changed)
        XCTAssertEqual(state.orderedIDs, [authoredID])
        XCTAssertEqual(state.primaryID, authoredID)
        XCTAssertEqual(state.anchorID, authoredID)
        let overlay = try SelectionOverlayPlanner().plan(selection: state, scene: fixture.scene, renderPlan: try renderPlan(fixture))
        XCTAssertEqual(overlay.overlays.map(\.objectID), [authoredID])
    }

    func testTraversal() throws {
        var fixture = try makeFixture(count: 3)
        fixture.targets[0] = fixture.targets[0].copy(participatesInCanvasTraversal: false)
        fixture = fixture.rebuilt()
        let authoredID1 = fixture.ids[1]
        let authoredID2 = fixture.ids[2]
        let registry = SelectionCommandRegistry()
        var state = SelectionState()
        _ = try registry.adopt(fixture.scene, boundary: .documentAdoption, state: &state)

        let selectResult = try registry.apply(
            .init(.replace, targetID: authoredID1, expectedIdentity: fixture.identity, provenance: .layersNavigator),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(selectResult, .changed)
        XCTAssertEqual(state.orderedIDs, [authoredID1])
        XCTAssertEqual(state.primaryID, authoredID1)
        XCTAssertEqual(state.anchorID, authoredID1)

        let nextResult1 = try registry.apply(
            .init(.next, targetID: nil, expectedIdentity: fixture.identity, provenance: .keyboard),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(nextResult1, .changed)
        XCTAssertEqual(state.orderedIDs, [authoredID2])
        XCTAssertEqual(state.primaryID, authoredID2)
        XCTAssertEqual(state.anchorID, authoredID2)

        let nextResult2 = try registry.apply(
            .init(.next, targetID: nil, expectedIdentity: fixture.identity, provenance: .keyboard),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(nextResult2, .changed)
        XCTAssertEqual(state.orderedIDs, [authoredID1])
        XCTAssertEqual(state.primaryID, authoredID1)
        XCTAssertEqual(state.anchorID, authoredID1)

        let previousResult1 = try registry.apply(
            .init(.previous, targetID: nil, expectedIdentity: fixture.identity, provenance: .keyboard),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(previousResult1, .changed)
        XCTAssertEqual(state.orderedIDs, [authoredID2])
        XCTAssertEqual(state.primaryID, authoredID2)
        XCTAssertEqual(state.anchorID, authoredID2)

        let previousResult2 = try registry.apply(
            .init(.previous, targetID: nil, expectedIdentity: fixture.identity, provenance: .keyboard),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(previousResult2, .changed)
        XCTAssertEqual(state.orderedIDs, [authoredID1])
        XCTAssertEqual(state.primaryID, authoredID1)
        XCTAssertEqual(state.anchorID, authoredID1)
    }

    func testZeroEligible() throws {
        var fixture = try makeFixture(count: 1)
        fixture.targets[0] = fixture.targets[0].copy(participatesInCanvasTraversal: false)
        fixture = fixture.rebuilt()
        let structuralID = fixture.ids[0]
        let registry = SelectionCommandRegistry()
        var state = SelectionState()
        _ = try registry.adopt(fixture.scene, boundary: .documentAdoption, state: &state)

        let selectResult = try registry.apply(
            .init(.replace, targetID: structuralID, expectedIdentity: fixture.identity, provenance: .layersNavigator),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(selectResult, .changed)
        XCTAssertEqual(state.orderedIDs, [structuralID])
        XCTAssertEqual(state.primaryID, structuralID)
        XCTAssertEqual(state.anchorID, structuralID)

        let nextResult = try registry.apply(
            .init(.next, targetID: nil, expectedIdentity: fixture.identity, provenance: .keyboard),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(nextResult, .unchanged)
        XCTAssertEqual(state.orderedIDs, [structuralID])
        XCTAssertEqual(state.primaryID, structuralID)
        XCTAssertEqual(state.anchorID, structuralID)

        let previousResult = try registry.apply(
            .init(.previous, targetID: nil, expectedIdentity: fixture.identity, provenance: .keyboard),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(previousResult, .unchanged)
        XCTAssertEqual(state.orderedIDs, [structuralID])
        XCTAssertEqual(state.primaryID, structuralID)
        XCTAssertEqual(state.anchorID, structuralID)
    }

    func testOneEligible() throws {
        var fixture = try makeFixture(count: 1)
        let authoredID = fixture.ids[0]
        let registry = SelectionCommandRegistry()
        var state = SelectionState()
        _ = try registry.adopt(fixture.scene, boundary: .documentAdoption, state: &state)

        let selectResult = try registry.apply(
            .init(.replace, targetID: authoredID, expectedIdentity: fixture.identity, provenance: .pointer),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(selectResult, .changed)
        XCTAssertEqual(state.orderedIDs, [authoredID])
        XCTAssertEqual(state.primaryID, authoredID)
        XCTAssertEqual(state.anchorID, authoredID)

        let nextResult = try registry.apply(
            .init(.next, targetID: nil, expectedIdentity: fixture.identity, provenance: .keyboard),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(nextResult, .unchanged)
        XCTAssertEqual(state.orderedIDs, [authoredID])
        XCTAssertEqual(state.primaryID, authoredID)
        XCTAssertEqual(state.anchorID, authoredID)

        let previousResult = try registry.apply(
            .init(.previous, targetID: nil, expectedIdentity: fixture.identity, provenance: .keyboard),
            to: &state, scene: fixture.scene
        )
        XCTAssertEqual(previousResult, .unchanged)
        XCTAssertEqual(state.orderedIDs, [authoredID])
        XCTAssertEqual(state.primaryID, authoredID)
        XCTAssertEqual(state.anchorID, authoredID)
    }

    func testCopyPreservation() throws {
        var fixture = try makeFixture(count: 1)
        fixture.targets[0] = fixture.targets[0].copy(participatesInCanvasTraversal: false)
        let copiedTarget = fixture.targets[0].copy(isVisible: false)
        XCTAssertEqual(copiedTarget.participatesInCanvasTraversal, false)
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

    // SF-AUTHORING-097, SF-0402-002/003 — directional marquee selection
    // evaluates the visible clipped geometry in stable paint order. A
    // left-to-right gesture contains; a right-to-left gesture intersects.
    func testMarqueeSelectionUsesDirectionalContainmentClippingAndPaintOrder() throws {
        let fixture = try makeFixture(count: 3)
        let targets = [
            SelectionTargetSnapshot(
                id: fixture.ids[0], pageID: fixture.pageID, parentID: nil, name: "First",
                frame: .init(origin: .init(x: 10, y: 10), size: .init(width: 20, height: 20)),
                clipRect: nil, paintOrder: 2, isVisible: true, isLocked: false, isAvailable: true
            ),
            SelectionTargetSnapshot(
                id: fixture.ids[1], pageID: fixture.pageID, parentID: nil, name: "Second",
                frame: .init(origin: .init(x: 35, y: 10), size: .init(width: 20, height: 20)),
                clipRect: nil, paintOrder: 1, isVisible: true, isLocked: false, isAvailable: true
            ),
            SelectionTargetSnapshot(
                id: fixture.ids[2], pageID: fixture.pageID, parentID: nil, name: "Clipped",
                frame: .init(origin: .init(x: 65, y: 10), size: .init(width: 20, height: 20)),
                clipRect: .init(origin: .init(x: 70, y: 10), size: .init(width: 10, height: 20)),
                paintOrder: 3, isVisible: true, isLocked: false, isAvailable: true
            ),
        ]
        let scene = SelectionSceneSnapshot(
            identity: fixture.identity, activePageID: fixture.pageID,
            activeContainerID: nil, targets: targets
        )
        let contained = SelectionMarqueeCommand(
            identity: fixture.identity,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 60, height: 40)),
            rule: .contains, modifier: .replace, cancelled: false
        )
        XCTAssertEqual(try SelectionMarqueeResolver.targetIDs(for: contained, in: scene),
                       [fixture.ids[1], fixture.ids[0]])

        let intersected = SelectionMarqueeCommand(
            identity: fixture.identity,
            frame: .init(origin: .init(x: 0, y: 0), size: .init(width: 75, height: 40)),
            rule: .intersects, modifier: .replace, cancelled: false
        )
        XCTAssertEqual(try SelectionMarqueeResolver.targetIDs(for: intersected, in: scene),
                       [fixture.ids[1], fixture.ids[0], fixture.ids[2]])

        let forward = SelectionMarqueeDraft(
            identity: fixture.identity, start: .init(x: 0, y: 0),
            current: .init(x: 75, y: 40), modifier: .replace
        )
        let reverse = SelectionMarqueeDraft(
            identity: fixture.identity, start: .init(x: 75, y: 40),
            current: .init(x: 0, y: 0), modifier: .replace
        )
        XCTAssertEqual(forward.rule, .contains)
        XCTAssertEqual(reverse.rule, .intersects)
        XCTAssertEqual(forward.frame, reverse.frame)
    }

    // SF-AUTHORING-097, SF-0402-004/006/008 — modifier behavior is applied
    // only after a valid live gesture commits. Cancellation, stale identity,
    // and invalid geometry leave the last valid scene-owned selection intact.
    func testMarqueeSelectionModifiersAndRejectedGesturesAreStateNeutral() throws {
        let fixture = try makeFixture(count: 3)
        let registry = SelectionCommandRegistry()
        var state = try established(fixture.scene)
        try apply(.replace, fixture.ids[0], .pointer, fixture, &state, registry)

        let secondOnly = WorldRect(
            origin: .init(x: 11, y: 0), size: .init(width: 11, height: 11)
        )
        XCTAssertEqual(try registry.applyMarquee(
            .init(identity: fixture.identity, frame: secondOnly, rule: .intersects,
                  modifier: .add, cancelled: false),
            to: &state, scene: fixture.scene
        ), .changed)
        XCTAssertEqual(state.orderedIDs, [fixture.ids[0], fixture.ids[1]])
        XCTAssertEqual(state.primaryID, fixture.ids[1])
        XCTAssertEqual(state.anchorID, fixture.ids[0])

        XCTAssertEqual(try registry.applyMarquee(
            .init(identity: fixture.identity, frame: secondOnly, rule: .intersects,
                  modifier: .toggle, cancelled: false),
            to: &state, scene: fixture.scene
        ), .changed)
        XCTAssertEqual(state.orderedIDs, [fixture.ids[0]])
        let valid = state

        XCTAssertThrowsError(try registry.applyMarquee(
            .init(identity: fixture.identity, frame: secondOnly, rule: .contains,
                  modifier: .replace, cancelled: true),
            to: &state, scene: fixture.scene
        )) { XCTAssertEqual($0 as? SelectionCommandError, .cancelled) }
        XCTAssertThrowsError(try registry.applyMarquee(
            .init(identity: fixture.identity.copy(sceneGeneration: 99), frame: secondOnly,
                  rule: .contains, modifier: .replace, cancelled: false),
            to: &state, scene: fixture.scene
        )) { XCTAssertEqual($0 as? SelectionCommandError, .staleScene) }
        XCTAssertThrowsError(try registry.applyMarquee(
            .init(identity: fixture.identity,
                  frame: .init(origin: .init(x: .nan, y: 0), size: .init(width: 10, height: 10)),
                  rule: .contains, modifier: .replace, cancelled: false),
            to: &state, scene: fixture.scene
        )) { XCTAssertEqual($0 as? SelectionCommandError, .invalidMarquee) }
        XCTAssertEqual(state, valid)
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

    // SF-0401-001, SF-0402-005 — viewport/preset clipping does not repair a
    // canonical selection, but an entirely off-artboard object must not leave
    // a ghost editor overlay on the pasteboard.
    func testOffArtboardSelectionRetainsIdentityAndSuppressesGhostOverlay() throws {
        let fixture = try makeFixture(count: 1)
        let offArtboardFrame = WorldRect(
            origin: WorldPoint(x: 500, y: 0),
            size: WorldSize(width: 10, height: 10)
        )
        let offArtboardTarget = SelectionTargetSnapshot(
            id: fixture.ids[0], pageID: fixture.pageID, parentID: nil,
            name: "Object 1", frame: offArtboardFrame, clipRect: nil,
            paintOrder: 0, isVisible: true, isLocked: false, isAvailable: true
        )
        let selectionScene = SelectionSceneSnapshot(
            identity: fixture.identity, activePageID: fixture.pageID,
            activeContainerID: nil, targets: [offArtboardTarget]
        )
        var state = try established(selectionScene)
        _ = try SelectionCommandRegistry().apply(
            .init(.replace, targetID: fixture.ids[0], expectedIdentity: fixture.identity, provenance: .pointer),
            to: &state, scene: selectionScene
        )
        let offArtboardObject = CanvasRenderObject(
            id: fixture.ids[0],
            frame: offArtboardFrame,
            clipRect: .init(origin: .init(x: 0, y: 0), size: .init(width: 400, height: 100)),
            paintOrder: 0,
            style: .container,
            isVisible: true,
            accessibilityLabel: "Object 1"
        )
        let scene = CanvasRenderSceneSnapshot(
            identity: fixture.renderScene.identity,
            surfaceID: fixture.renderScene.surfaceID,
            objects: [offArtboardObject]
        )
        var viewport = fixture.viewport
        try viewport.setContentBounds(.init(origin: .init(x: 0, y: 0), size: .init(width: 400, height: 100)))
        let plan = try CanvasRendererCore().prepare(
            scene: scene,
            overlays: .init(identity: fixture.identity, overlays: []),
            viewport: viewport
        )
        let overlay = try SelectionOverlayPlanner().plan(
            selection: state, scene: selectionScene, renderPlan: plan
        )
        XCTAssertEqual(state.primaryID, fixture.ids[0])
        XCTAssertTrue(overlay.overlays.isEmpty)
        XCTAssertFalse(overlay.authoredContentInvalidated)
    }

    // SF-0402-005, SF-0601-003, SF-0602-003 — preset clipping is not a
    // lifecycle removal. The real artboard clip is present on the selection
    // target, unlike the older overlay-only regression above.
    func testBreakpointClipRetainsExistingSelectionButRejectsNewCanvasHit() throws {
        let fixture = try makeFixture(count: 1)
        let id = fixture.ids[0]
        let frame = WorldRect(origin: .init(x: 600, y: 370),
                              size: .init(width: 240, height: 160))
        let registry = SelectionCommandRegistry()
        var state = SelectionState()

        func scene(width: Double, generation: UInt64) -> SelectionSceneSnapshot {
            let identity = fixture.identity.copy(sceneGeneration: generation)
            let target = SelectionTargetSnapshot(
                id: id, pageID: fixture.pageID, parentID: nil, name: "Frame",
                frame: frame,
                clipRect: .init(origin: .init(x: 0, y: 0),
                                size: .init(width: width, height: 900)),
                paintOrder: 0, isVisible: true, isLocked: false,
                isAvailable: true
            )
            return .init(identity: identity, activePageID: fixture.pageID,
                         activeContainerID: nil, targets: [target])
        }

        let desktop = scene(width: 1_440, generation: 5)
        _ = try registry.adopt(desktop, boundary: .documentAdoption, state: &state)
        try registry.apply(.init(.replace, targetID: id,
                                 expectedIdentity: desktop.identity, provenance: .pointer),
                           to: &state, scene: desktop)

        for (width, generation) in [(768.0, UInt64(6)), (390.0, 7), (1_440.0, 8)] {
            let current = scene(width: width, generation: generation)
            XCTAssertEqual(try registry.adopt(current, boundary: .rendererGeneration,
                                              state: &state), .none)
            XCTAssertEqual(state.orderedIDs, [id])
            XCTAssertEqual(state.primaryID, id)
            XCTAssertEqual(state.provenance, .pointer)
            if width == 390 {
                XCTAssertTrue(current.orderedSelectableTargets.isEmpty)
                var viewport = fixture.viewport
                try viewport.setContentBounds(.init(origin: .init(x: 0, y: 0),
                                                    size: .init(width: width, height: 900)))
                let renderScene = CanvasRenderSceneSnapshot(
                    identity: current.identity, surfaceID: fixture.renderScene.surfaceID,
                    objects: [CanvasRenderObject(
                        id: id, frame: frame, clipRect: current.targets[0].clipRect,
                        paintOrder: 0, style: .container, isVisible: true,
                        accessibilityLabel: "Frame"
                    )]
                )
                let plan = try CanvasRendererCore().prepare(
                    scene: renderScene,
                    overlays: .init(identity: current.identity, overlays: []),
                    viewport: viewport
                )
                let overlay = try SelectionOverlayPlanner().plan(
                    selection: state, scene: current, renderPlan: plan
                )
                XCTAssertTrue(overlay.overlays.isEmpty)
                XCTAssertFalse(plan.accessibilityElements.contains { $0.objectID == id })
                var fresh = try established(current)
                XCTAssertThrowsError(try registry.apply(
                    .init(.replace, targetID: id, expectedIdentity: current.identity,
                          provenance: .pointer), to: &fresh, scene: current
                )) { XCTAssertEqual($0 as? SelectionCommandError,
                                   .disabled("The object is outside the selectable clipped region.")) }
                XCTAssertTrue(fresh.isEmpty)
            }
        }
    }

    // SF-0401-001, SF-0403-003 — transform chrome has the same artboard
    // intersection as the authored raster and selection outline.  A partial
    // breakpoint clip must not leave resize handles over pasteboard space.
    func testPartialArtboardClipLimitsTransformChromeToVisibleAuthoredGeometry() throws {
        let fixture = try makeFixture(count: 1)
        let frame = WorldRect(
            origin: WorldPoint(x: 350, y: 20),
            size: WorldSize(width: 100, height: 80)
        )
        let target = SelectionTargetSnapshot(
            id: fixture.ids[0], pageID: fixture.pageID, parentID: nil,
            name: "Object 1", frame: frame, clipRect: nil,
            paintOrder: 0, isVisible: true, isLocked: false, isAvailable: true
        )
        let selectionScene = SelectionSceneSnapshot(
            identity: fixture.identity, activePageID: fixture.pageID,
            activeContainerID: nil, targets: [target]
        )
        var selection = try established(selectionScene)
        _ = try SelectionCommandRegistry().apply(
            .init(.replace, targetID: fixture.ids[0], expectedIdentity: fixture.identity, provenance: .pointer),
            to: &selection, scene: selectionScene
        )
        var viewport = fixture.viewport
        try viewport.setContentBounds(.init(origin: .init(x: 0, y: 0), size: .init(width: 400, height: 100)))
        let scene = CanvasRenderSceneSnapshot(
            identity: fixture.renderScene.identity,
            surfaceID: fixture.renderScene.surfaceID,
            objects: [.init(
                id: fixture.ids[0], frame: frame,
                clipRect: viewport.contentBounds, paintOrder: 0,
                style: .frameSurface, isVisible: true, accessibilityLabel: "Object 1"
            )]
        )
        let plan = try CanvasRendererCore().prepare(
            scene: scene, overlays: .init(identity: fixture.identity, overlays: []), viewport: viewport
        )
        let overlays = TransformOverlayPlanner.overlays(
            selection: selection, renderPlan: plan, preview: nil, handleWorldSize: 8
        )
        let transformSelection = try XCTUnwrap(overlays.first(where: { $0.kind == "transform-selection" }))
        XCTAssertEqual(transformSelection.frame, .init(
            origin: .init(x: 350, y: 20), size: .init(width: 50, height: 80)
        ))
        XCTAssertTrue(overlays.filter { $0.kind.hasPrefix("transform-handle-") }.allSatisfy {
            $0.frame.maxX <= viewport.contentBounds.maxX && $0.frame.maxY <= viewport.contentBounds.maxY
        })
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
        XCTAssertTrue(record.sanitizedIdentifiers.allSatisfy { $0.count == "node-".count + 24 })
        XCTAssertTrue(record.sanitizedIdentifiers.allSatisfy { identifier in
            !state.orderedIDs.contains { identifier.contains($0.description) }
        })
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
    func copy(
        pageID: PageID? = nil,
        clipRect: WorldRect? = nil,
        isVisible: Bool? = nil,
        isAvailable: Bool? = nil,
        participatesInCanvasTraversal: Bool? = nil
    ) -> Self {
        .init(id: id, pageID: pageID ?? self.pageID, parentID: parentID, name: name, frame: frame,
            clipRect: clipRect ?? self.clipRect, paintOrder: paintOrder, isVisible: isVisible ?? self.isVisible,
            isLocked: isLocked, isAvailable: isAvailable ?? self.isAvailable,
            participatesInCanvasTraversal: participatesInCanvasTraversal ?? self.participatesInCanvasTraversal)
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
