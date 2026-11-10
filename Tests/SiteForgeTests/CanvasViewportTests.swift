import XCTest
import Combine
@testable import SiteForge

final class CanvasViewportTests: XCTestCase {
    // SF-LOCAL-BUILDER-014 / SF-0202-003, SF-0701-003.
    @MainActor
    func testInspectorPanePresentationPreservesDraftSelectionHistoryAndCanonicalBytes() async throws {
        let fixture = try customWidthDocument()
        let state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        await awaitCustomWidthScene(state)
        state.selectLayer(fixture.fluid)
        let bytes = try DocumentSerializer.encode(state.documentSession.document)
        let history = state.documentSession.historySnapshot(), selection = state.selectionState
        let scope = state.layoutInspectorDraftScope
        var draft = LayoutInspectorNumericDraft(text: "1e", committed: "120", scope: scope)
        let original = draft
        for width in [CGFloat(1100), 1280, 1710] {
            _ = WorkspaceMetrics.sidePaneAllocation(windowWidth: width, navigatorRequired: 324, inspectorRequired: 356)
            for tab in InspectorTab.allCases { _ = state.selectInspectorTab(tab) }
            for tab in NavigatorTab.allCases { state.navigatorTab = tab }
            // A resized pane is not an editor context/revision change.
            draft.adopt(committed: "120", scope: state.layoutInspectorDraftScope)
            XCTAssertEqual(draft, original)
            XCTAssertEqual(state.selectionState, selection)
            XCTAssertEqual(state.documentSession.historySnapshot(), history)
            XCTAssertEqual(try DocumentSerializer.encode(state.documentSession.document), bytes)
        }
        XCTAssertEqual(InspectorDraftAccessibility.value(draft: draft.text, committed: "120"), "1e; uncommitted draft")
        XCTAssertFalse(draft.hasUnchangedNumericValue)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
    }

    // SF-LOCAL-BUILDER-008; SF-0606-002/003/004/006/007/008.
    // New acceptance source only: DO NOT execute during the renewed owner hold.
    private func responsiveReviewFixture() throws -> (document: CanonicalDocument, target: NodeID) {
        var fixture = try customWidthDocument()
        let node = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.fluid })
        let x = try XCTUnwrap(fixture.document.pages[0].nodes[node].properties.firstIndex { $0.key.rawValue == "layout.x" })
        fixture.document.pages[0].nodes[node].properties[x].value = .number(400)
        try fixture.document.validate()
        return (fixture.document, fixture.fluid)
    }

    @MainActor private func awaitResponsiveLayoutReviews(_ state: WorkspaceShellState) async throws -> [ResponsiveBreakpointReview] {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if !state.isPreparingResponsiveComparison, state.responsiveBreakpointReviews.count == 4 {
                return state.responsiveBreakpointReviews
            }
            await Task.yield()
        }
        XCTFail("Current identity-tagged responsive review did not adopt: \(state.responsiveComparisonFailureCategory)")
        return []
    }

    func testResponsiveLayoutReviewDeterministicWidthMatrixAndScope() async throws {
        let fixture = try responsiveReviewFixture()
        let page = fixture.document.pages[0]
        let worker = ResponsiveBreakpointReviewWorker()
        for width in [320.0, 430, 599.5, 600, 900, 1023.5, 1024, 1440] {
            let first = try await worker.prepare(document: fixture.document, pageID: page.id, selectedNodeIDs: [], width: width)
            let repeated = try await worker.prepare(document: fixture.document, pageID: page.id, selectedNodeIDs: [], width: width)
            XCTAssertEqual(first, repeated)
            XCTAssertEqual(first.count, 4)
            let current = try XCTUnwrap(first.first { $0.isCurrentWidthSample })
            XCTAssertEqual(current.viewportWidth, width)
            XCTAssertEqual(current.breakpoint, .resolving(width: width))
            XCTAssertTrue(first.flatMap(\.layoutFindings).allSatisfy {
                $0.id.origin.documentID == fixture.document.id && $0.id.origin.pageID == page.id
                    && $0.id.origin.revision == fixture.document.revision
                    && !page.rootNodeIDs.contains($0.id.nodeID) && $0.overflow > 0 && $0.classification == .review
            })
            let selected = try await worker.prepare(document: fixture.document, pageID: page.id,
                selectedNodeIDs: [fixture.target], width: width)
            XCTAssertTrue(selected.flatMap(\.layoutFindings).allSatisfy { $0.id.nodeID == fixture.target })
            let mobile = try XCTUnwrap(selected.first { $0.breakpoint == .mobile })
            XCTAssertTrue(mobile.layoutFindings.contains { $0.id.nodeID == fixture.target && $0.widthSource.contains("Smooth scaling") })
            XCTAssertEqual(Set(first.map(\.id)).count, 4, "Current and preset samples remain distinct even at an anchor")
        }
    }

    func testResponsiveLayoutReviewUsesCanvasClipsAndAllowsVisibleOverflow() async throws {
        var document = ProjectCreation.blank()
        let root = document.pages[0].rootNodeIDs[0]
        func frame(_ name: String, parent: NodeID, x: Double, width: Double) -> DocumentNode {
            .init(kind: .frame, name: name, parent: .node(parent), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(x)),
                .init(key: .init(rawValue: "layout.y"), value: .number(80)),
                .init(key: .init(rawValue: "layout.width"), value: .number(width)),
                .init(key: .init(rawValue: "layout.height"), value: .number(120))])
        }
        var parent = frame("Parent", parent: root, x: 80, width: 200)
        let child = frame("Child", parent: parent.id, x: 260, width: 80)
        parent.childIDs = [child.id]
        parent.properties.append(.init(key: .init(rawValue: DesignBoxStyleCommandRegistry.namespace + "clip.content"), value: .boolean(true)))
        document.pages[0].nodes[0].childIDs = [parent.id]
        document.pages[0].nodes += [parent, child]
        try document.validate()
        let worker = ResponsiveBreakpointReviewWorker()
        let clipped = try await worker.prepare(document: document, pageID: document.pages[0].id,
            selectedNodeIDs: [child.id], width: 900)
        let finding = try XCTUnwrap(clipped.last?.layoutFindings.first)
        XCTAssertEqual(finding.id.boundary, .clippedContainer)
        XCTAssertEqual(finding.containingNodeID, parent.id)
        XCTAssertEqual(finding.objectBounds.minX, 260)
        XCTAssertEqual(finding.containingBounds.maxX, 280)
        XCTAssertEqual(finding.overflow, 60)
        document.pages[0].nodes[1].properties.removeAll { $0.key.rawValue == DesignBoxStyleCommandRegistry.namespace + "clip.content" }
        let allowed = try await worker.prepare(document: document, pageID: document.pages[0].id,
            selectedNodeIDs: [child.id], width: 900)
        XCTAssertEqual(allowed.last?.totalLayoutFindingCount, 0, "Overflow-visible is not an implicit parent clip")
        document.pages[0].nodes[2].properties.append(.init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.tablet)), value: .boolean(false)))
        let hidden = try await worker.prepare(document: document, pageID: document.pages[0].id, selectedNodeIDs: [], width: 900)
        XCTAssertFalse(hidden.last?.layoutFindings.contains { $0.id.nodeID == child.id } == true)
        document.pages[0].nodes[2].properties.removeAll { $0.key.rawValue == ResponsiveVisibilityResolver.key(.tablet) }
        document.pages[0].nodes[2].properties.append(.init(key: .init(rawValue: CanonicalPositioning.namespace + "mode"), value: .string("fixed")))
        let viewportFixed = try await worker.prepare(document: document, pageID: document.pages[0].id,
            selectedNodeIDs: [child.id], width: 430)
        XCTAssertTrue(viewportFixed.allSatisfy { $0.layoutFindings.isEmpty }, "Viewport-dependent positioning is explicitly outside this review slice")
    }

    func testResponsiveLayoutReviewConnectedChromeUsesSharedScene() async throws {
        let document = StarterSiteTemplate.document()
        let page = try XCTUnwrap(document.pages.first)
        let worker = ResponsiveBreakpointReviewWorker()
        for width in [320.0, 430, 599.5, 600, 900, 1023.5, 1024, 1440] {
            let reviews = try await worker.prepare(document: document, pageID: page.id, selectedNodeIDs: [], width: width)
            let bounds = WorldRect(origin: .init(x: 0, y: 0), size: .init(width: width,
                height: CanonicalPageFlow.contentHeight(page, breakpoint: .resolving(width: width), width: width)))
            let scene = try await WorkspaceScenePreparationWorker().prepare(.init(document: document, activePageID: page.id,
                activeContainerID: nil, viewport: try .init(viewportSize: .init(width: width, height: 900), contentBounds: bounds),
                surfaceID: .init(), breakpoint: .resolving(width: width), viewportWidth: width))
            for finding in try XCTUnwrap(reviews.last).layoutFindings {
                let object = try XCTUnwrap(scene.renderScene.objects.first { $0.id == finding.id.nodeID })
                XCTAssertEqual(finding.objectBounds, object.frame)
                XCTAssertEqual(finding.containingBounds, finding.id.boundary == .artboard ? bounds : object.clipRect)
            }
            XCTAssertFalse(reviews.flatMap(\.layoutFindings).contains { page.rootNodeIDs.contains($0.id.nodeID) })
        }
    }

    func testResponsiveLayoutReviewReportsFixedFluidAndOverrideWinnersWithoutAuthoredChanges() async throws {
        var fixture = try responsiveReviewFixture()
        let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.target })
        let worker = ResponsiveBreakpointReviewWorker()
        let fluid = try await worker.prepare(document: fixture.document, pageID: fixture.document.pages[0].id,
            selectedNodeIDs: [fixture.target], width: 430)
        XCTAssertTrue(try XCTUnwrap(fluid.last?.layoutFindings.first).widthSource.contains("Smooth scaling"))
        fixture.document.pages[0].nodes[index].properties.removeAll { $0.key.rawValue == CanonicalFluidValueCodec.key(.width) }
        let fixed = try await worker.prepare(document: fixture.document, pageID: fixture.document.pages[0].id,
            selectedNodeIDs: [fixture.target], width: 430)
        XCTAssertTrue(try XCTUnwrap(fixed.last?.layoutFindings.first).widthSource.contains("Fixed"))
        fixture.document.pages[0].nodes[index].properties.append(.init(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .tablet)), value: .number(800)))
        let before = try DocumentSerializer.encode(fixture.document)
        let override = try await worker.prepare(document: fixture.document, pageID: fixture.document.pages[0].id,
            selectedNodeIDs: [fixture.target], width: 900)
        let finding = try XCTUnwrap(override.last?.layoutFindings.first)
        XCTAssertTrue(finding.widthSource.contains("Set here · Tablet"))
        XCTAssertEqual(finding.objectBounds.size.width, 800)
        XCTAssertEqual(try DocumentSerializer.encode(fixture.document), before)
    }

    func testResponsiveLayoutReviewStandardAndLargeSnapshotsHaveBoundedRows() async throws {
        for count in [100, 10_000] {
            var document = ProjectCreation.blank()
            let root = document.pages[0].rootNodeIDs[0]
            let nodes = (0..<count).map { index in DocumentNode(kind: .frame, name: "Item \(index)", parent: .node(root), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(450)),
                .init(key: .init(rawValue: "layout.y"), value: .number(Double(index))),
                .init(key: .init(rawValue: "layout.width"), value: .number(40)),
                .init(key: .init(rawValue: "layout.height"), value: .number(24))]) }
            document.pages[0].nodes[0].childIDs = nodes.map(\.id)
            document.pages[0].nodes += nodes
            try document.validate()
            let result = try await ResponsiveBreakpointReviewWorker().prepare(document: document,
                pageID: document.pages[0].id, selectedNodeIDs: [], width: 430)
            XCTAssertEqual(result.last?.totalLayoutFindingCount, count)
            XCTAssertEqual(result.last?.layoutFindings.count, min(count, ResponsiveLayoutReviewPolicy.maximumPresentedFindings))
            XCTAssertEqual(Set(result.last?.layoutFindings.map(\.id) ?? []).count, min(count, ResponsiveLayoutReviewPolicy.maximumPresentedFindings))
        }
        // No unmeasured duration or release-performance claim is made.
    }

    @MainActor
    func testResponsiveLayoutReviewCancellationAndBoundedPresentation() async throws {
        var document = ProjectCreation.blank()
        let root = document.pages[0].rootNodeIDs[0]
        let nodes = (0..<250).map { index in DocumentNode(kind: .frame, name: "Card \(index)", parent: .node(root), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(450)),
            .init(key: .init(rawValue: "layout.y"), value: .number(Double(index))),
            .init(key: .init(rawValue: "layout.width"), value: .number(40)),
            .init(key: .init(rawValue: "layout.height"), value: .number(24))]) }
        document.pages[0].nodes[0].childIDs = nodes.map(\.id)
        document.pages[0].nodes += nodes
        try document.validate()
        let worker = ResponsiveBreakpointReviewWorker()
        let result = try await worker.prepare(document: document, pageID: document.pages[0].id, selectedNodeIDs: [], width: 430)
        XCTAssertEqual(result.last?.totalLayoutFindingCount, 250)
        XCTAssertEqual(result.last?.layoutFindings.count, ResponsiveLayoutReviewPolicy.maximumPresentedFindings)
        let cancelled = Task { @MainActor in
            try Task.checkCancellation()
            return try await worker.prepare(document: document, pageID: document.pages[0].id, selectedNodeIDs: [], width: 430)
        }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled comparison must not adopt") }
        catch is CancellationError {}
        let state = WorkspaceShellState(documentSession: .init(document: document))
        state.showResponsiveComparison(); state.cancelResponsiveComparison()
        await Task.yield()
        XCTAssertTrue(state.responsiveBreakpointReviews.isEmpty)
        XCTAssertFalse(state.isPreparingResponsiveComparison)
        XCTAssertEqual(state.responsiveComparisonFailureCategory, "cancelled")
    }

    @MainActor
    func testResponsiveLayoutReviewNavigatesExactNodeWidthWithoutHistoryOrPackageMutation() async throws {
        let fixture = try responsiveReviewFixture()
        let state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.resizeViewport(to: .init(width: 1200, height: 800), pixelRatio: 2)
        XCTAssertTrue(state.commitViewportWidth(900)); await awaitCustomWidthScene(state)
        let before = try DocumentSerializer.encode(state.documentSession.document)
        let history = state.documentSession.historySnapshot()
        state.showResponsiveComparison()
        let reviews = try await awaitResponsiveLayoutReviews(state)
        let finding = try XCTUnwrap(reviews.first { $0.breakpoint == .mobile && !$0.isCurrentWidthSample }?.layoutFindings.first { $0.id.nodeID == fixture.target })
        XCTAssertTrue(state.reviewResponsiveLayoutFinding(finding))
        await awaitCustomWidthScene(state)
        XCTAssertEqual(state.viewportLayoutWidth, 390)
        XCTAssertEqual(state.selectionState.primaryID, fixture.target)
        XCTAssertEqual(state.navigatorTab, .layers); XCTAssertEqual(state.inspectorTab, .layout)
        XCTAssertFalse(state.isResponsiveComparisonPresented)
        XCTAssertTrue(state.responsiveLayoutReviewStatus.contains("390"))
        XCTAssertNotNil(state.responsiveLayoutInspectorRequestID)
        XCTAssertTrue(state.commitViewportWidth(430)); await awaitCustomWidthScene(state)
        state.showResponsiveComparison()
        let customReviews = try await awaitResponsiveLayoutReviews(state)
        let currentFinding = try XCTUnwrap(customReviews.last?.layoutFindings.first)
        XCTAssertTrue(state.reviewResponsiveLayoutFinding(currentFinding))
        await awaitCustomWidthScene(state)
        XCTAssertEqual(state.viewportLayoutWidth, 430)
        XCTAssertEqual(state.selectionState.primaryID, fixture.target)
        XCTAssertEqual(try DocumentSerializer.encode(state.documentSession.document), before)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
        let package = ProjectPackage(document: fixture.document)
        let store = ProjectPackageStore()
        let data = try await store.encode(package)
        let opened = try await store.decode(data)
        XCTAssertEqual(opened.document, state.documentSession.document)
    }

    @MainActor
    func testResponsiveLayoutReviewRejectsStaleDraftIMEAndReplacement() async throws {
        var fixture = try responsiveReviewFixture()
        let nodeIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.target })
        fixture.document.pages[0].nodes[nodeIndex].kind = .text
        fixture.document.pages[0].nodes[nodeIndex].properties.append(.init(key: .init(rawValue: "content.text"), value: .string("Review text")))
        try fixture.document.validate()
        let state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.resizeViewport(to: .init(width: 1200, height: 800), pixelRatio: 2)
        XCTAssertTrue(state.commitViewportWidth(430)); await awaitCustomWidthScene(state)
        state.selectLayer(fixture.target); state.showResponsiveComparison()
        let reviews = try await awaitResponsiveLayoutReviews(state)
        let finding = try XCTUnwrap(reviews.last?.layoutFindings.first)
        let before = state.documentSession.document
        let opening = state.selectionState
        let openingHistory = state.documentSession.historySnapshot()
        var commitRequests = 0
        let blocker = state.editCommitRequests.sink { request in
            if request.requiresCleanEditors { request.reject() }
            else { commitRequests += 1 }
        }
        XCTAssertFalse(state.reviewResponsiveLayoutFinding(finding)); blocker.cancel()
        XCTAssertEqual(commitRequests, 0, "Review must preflight clean editors rather than commit a draft and then reject its stale finding")
        XCTAssertEqual(state.documentSession.historySnapshot(), openingHistory)
        XCTAssertEqual(state.selectionState, opening); XCTAssertEqual(state.viewportLayoutWidth, 430)
        XCTAssertTrue(state.beginTextEditing(nodeID: fixture.target, provenance: .keyboard))
        state.updateTextEditingDraft(text: "A", selection: .init(location: 1, length: 0), markedRange: .init(location: 0, length: 1))
        XCTAssertFalse(state.reviewResponsiveLayoutFinding(finding))
        XCTAssertEqual(state.documentSession.document, before)
        state.cancelTextEditing()
        let retainedReviews = try await awaitResponsiveLayoutReviews(state)
        let mobile = try XCTUnwrap(retainedReviews.first { $0.breakpoint == .mobile && !$0.isCurrentWidthSample }?.layoutFindings.first)
        XCTAssertTrue(state.reviewResponsiveLayoutFinding(mobile))
        var replacement = ProjectCreation.blank()
        let newRoot = replacement.pages[0].rootNodeIDs[0]
        replacement.pages[0].nodes[0].childIDs = [fixture.target]
        replacement.pages[0].nodes.append(.init(id: fixture.target, kind: .text, name: "Unrelated coincidental ID", parent: .node(newRoot), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(20)),
            .init(key: .init(rawValue: "layout.y"), value: .number(20)),
            .init(key: .init(rawValue: "layout.width"), value: .number(120)),
            .init(key: .init(rawValue: "layout.height"), value: .number(24)),
            .init(key: .init(rawValue: "content.text"), value: .string("New document"))]))
        try replacement.validate()
        try state.documentSession.establishBaseline(replacement)
        XCTAssertFalse(state.reviewResponsiveLayoutFinding(finding))
        await Task.yield(); await awaitCustomWidthScene(state)
        XCTAssertNotEqual(state.selectionState.primaryID, fixture.target)
    }

    @MainActor
    func testResponsiveLayoutReviewRefreshesAfterAtomicEditUndoRedo() async throws {
        let fixture = try responsiveReviewFixture()
        let state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.resizeViewport(to: .init(width: 1200, height: 800), pixelRatio: 2)
        XCTAssertTrue(state.commitViewportWidth(430)); await awaitCustomWidthScene(state)
        state.selectLayer(fixture.target); state.showResponsiveComparison()
        let openingReviews = try await awaitResponsiveLayoutReviews(state)
        let old = try XCTUnwrap(openingReviews.last?.layoutFindings.first)
        XCTAssertTrue(state.commitGeometryInspectorValue(20, field: .x, provenance: .keyboard,
            draftScope: state.layoutInspectorDraftScope))
        await awaitCustomWidthScene(state)
        let fixed = try await awaitResponsiveLayoutReviews(state)
        XCTAssertFalse(fixed.last?.layoutFindings.contains { $0.id.nodeID == fixture.target } == true)
        XCTAssertFalse(state.reviewResponsiveLayoutFinding(old))
        try state.documentSession.undo(); await Task.yield(); await awaitCustomWidthScene(state)
        let undone = try await awaitResponsiveLayoutReviews(state)
        let restored = try XCTUnwrap(undone.last?.layoutFindings.first)
        XCTAssertEqual(restored.id.nodeID, fixture.target)
        XCTAssertEqual(restored.id.origin.revision, state.documentSession.document.revision)
        XCTAssertNotEqual(restored.id.origin.revision, old.id.origin.revision)
        try state.documentSession.redo(); await Task.yield(); await awaitCustomWidthScene(state)
        let redone = try await awaitResponsiveLayoutReviews(state)
        XCTAssertTrue(redone.last?.layoutFindings.isEmpty == true)
    }

    @MainActor
    func testResponsiveLayoutReviewRedactsDiagnosticsAndRejectsForeignOrigin() async throws {
        let fixture = try responsiveReviewFixture()
        let state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.resizeViewport(to: .init(width: 1200, height: 800), pixelRatio: 2)
        XCTAssertTrue(state.commitViewportWidth(430)); state.showResponsiveComparison()
        let reviews = try await awaitResponsiveLayoutReviews(state)
        let finding = try XCTUnwrap(reviews.last?.layoutFindings.first)
        let foreign = ResponsiveLayoutFinding(id: .init(origin: .init(documentID: DocumentID(), revision: finding.id.origin.revision,
            pageID: finding.id.origin.pageID), nodeID: finding.id.nodeID, width: finding.id.width,
            isCurrentSample: finding.id.isCurrentSample, boundary: finding.id.boundary, edge: finding.id.edge),
            breakpoint: finding.breakpoint, containingNodeID: finding.containingNodeID,
            objectBounds: finding.objectBounds, containingBounds: finding.containingBounds, widthSource: finding.widthSource)
        XCTAssertFalse(state.reviewResponsiveLayoutFinding(foreign))
        let diagnostic = String(describing: state.lastResponsiveLayoutReviewDiagnostic)
        XCTAssertFalse(diagnostic.contains(fixture.document.id.description))
        XCTAssertFalse(diagnostic.contains(finding.id.origin.pageID.description))
        XCTAssertFalse(diagnostic.contains(fixture.target.description))
        XCTAssertFalse(diagnostic.contains("Fluid"))
        XCTAssertEqual(state.lastResponsiveLayoutReviewDiagnostic?.failureCategory, "stale-context")
    }

    // SF-LOCAL-BUILDER-007 / SF-0602-002/003/004/006/008.
    // Historical partial focused execution is recorded in007 evidence. Latest
    // fixture/008 integration edits remain unverified under the renewed hold.
    func testCustomViewportWidthValidationLocaleAndHalfOpenRanges() {
        let locale = Locale(identifier: "en_US")
        for text in ["", "-", "12.", "NaN", "inf", "1e9", "0", "-1", "1000000001", "430px"] {
            XCTAssertNil(ViewportWidthPolicy.parse(text, locale: locale), text)
        }
        XCTAssertEqual(ViewportWidthPolicy.parse(" 430.5 ", locale: locale), 430.5)
        XCTAssertEqual(ViewportWidthPolicy.parse("430,5", locale: Locale(identifier: "de_DE")), 430.5)
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1, LayoutPolicy.maximumDimension + 1] {
            XCTAssertFalse(ViewportWidthPolicy.isValid(invalid))
        }
        for width in [1.0, 320, 430, 599, 599.5, 600, 601, 900, 1023, 1023.5, 1024, 1025, 1440] {
            XCTAssertTrue(ViewportWidthPolicy.isValid(width))
            XCTAssertEqual(ViewportWidthPolicy.preset(for: width).responsiveBreakpoint, ResponsiveBreakpoint.resolving(width: width))
        }
        XCTAssertEqual(ResponsiveBreakpoint.mobile.cssMediaCondition, "(width < 600px)")
        XCTAssertEqual(ResponsiveBreakpoint.tablet.cssMediaCondition, "(min-width: 600px) and (width < 1024px)")
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 599.5), .mobile)
        XCTAssertEqual(ResponsiveBreakpoint.resolving(width: 1023.5), .tablet)
    }

    private func customWidthDocument() throws -> (document: CanonicalDocument, fixed: NodeID, fluid: NodeID, text: NodeID) {
        var document = ProjectCreation.blank()
        let root = document.pages[0].rootNodeIDs[0]
        func node(_ kind: NodeKind, _ name: String, _ parent: NodeID, _ x: Double, _ y: Double,
                  _ width: Double, _ height: Double, _ extras: [NodeProperty] = []) -> DocumentNode {
            .init(kind: kind, name: name, parent: .node(parent), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(x)),
                .init(key: .init(rawValue: "layout.y"), value: .number(y)),
                .init(key: .init(rawValue: "layout.width"), value: .number(width)),
                .init(key: .init(rawValue: "layout.height"), value: .number(height))] + extras)
        }
        let fixed = node(.frame, "Fixed", root, 20, 20, 80, 40, [
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .tablet)), value: .number(160), origin: .authored),
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(44), origin: .authored),
            .init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(false), origin: .authored)])
        let fluid = node(.frame, "Fluid", root, 20, 100, 120, 40, [
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.width)), value: .string(try CanonicalFluidValueCodec.encode(
                .init(minimum: 50, preferred: 120, maximum: 200), target: .width)), origin: .authored)])
        var stack = node(.stack, "Stack", root, 20, 200, 280, 180, [
            .init(key: .init(rawValue: "layout.container.kind"), value: .string("stack")),
            .init(key: .init(rawValue: "layout.axis"), value: .string("vertical")),
            .init(key: .init(rawValue: "layout.align"), value: .string("start")),
            .init(key: .init(rawValue: "layout.padding"), value: .number(8)),
            .init(key: .init(rawValue: "layout.gap"), value: .number(12)),
            .init(key: .init(rawValue: ResponsiveContainerLayoutResolver.key(.axis, breakpoint: .mobile)), value: .string("horizontal"), origin: .authored)])
        let text = node(.text, "Paragraph", stack.id, 0, 0, 120, 24, [
            .init(key: .init(rawValue: "content.text"), value: .string("Upright responsive text")),
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.fontSize)), value: .string(try CanonicalFluidValueCodec.encode(
                .init(minimum: 12, preferred: 16, maximum: 20), target: .fontSize)), origin: .authored)])
        let child = node(.frame, "Stack child", stack.id, 0, 0, 80, 40)
        stack.childIDs = [text.id, child.id]
        var grid = node(.grid, "Grid", root, 350, 20, 280, 180, [
            .init(key: .init(rawValue: "layout.container.kind"), value: .string("grid")),
            .init(key: .init(rawValue: "layout.padding"), value: .number(8)),
            .init(key: .init(rawValue: "layout.gap"), value: .number(12)),
            .init(key: .init(rawValue: "layout.grid.columns"), value: .number(2)),
            .init(key: .init(rawValue: "layout.grid.placement"), value: .string("row-major")),
            .init(key: .init(rawValue: ResponsiveContainerLayoutResolver.key(.columns, breakpoint: .mobile)), value: .number(1), origin: .authored)])
        let cell = node(.frame, "Grid child", grid.id, 0, 0, 80, 40)
        grid.childIDs = [cell.id]
        var section = node(.section, "Section", root, 20, 440, 280, 180, [
            .init(key: .init(rawValue: "layout.container.kind"), value: .string("section")),
            .init(key: .init(rawValue: "layout.padding"), value: .number(8)),
            .init(key: .init(rawValue: "layout.axis"), value: .string("vertical")),
            .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.padding)), value: .string(try CanonicalFluidValueCodec.encode(
                .init(minimum: 4, preferred: 8, maximum: 16), target: .padding)), origin: .authored)])
        let sectionChild = node(.frame, "Section child", section.id, 0, 0, 80, 40)
        section.childIDs = [sectionChild.id]
        document.pages[0].nodes[0].childIDs = [fixed.id, fluid.id, stack.id, grid.id, section.id]
        document.pages[0].nodes += [fixed, fluid, stack, text, child, grid, cell, section, sectionChild]
        try document.validate()
        return (document, fixed.id, fluid.id, text.id)
    }

    @MainActor private func awaitCustomWidthScene(_ state: WorkspaceShellState) async {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if let plan = state.canvasRenderPlan,
               plan.identity.documentID == state.documentSession.document.id,
               plan.identity.revision == state.documentSession.document.revision,
               plan.identity.viewportGeneration == state.viewportState.generation { return }
            await Task.yield()
        }
        XCTFail("Latest width/document scene did not adopt")
    }

    @MainActor
    func testCustomViewportWidthIsSceneLocalAcrossZoomWindowScaleAndPresetActions() async throws {
        let fixture = try customWidthDocument()
        let state = WorkspaceShellState(documentSession: DocumentSession(document: fixture.document))
        let encoded = try DocumentSerializer.encode(state.documentSession.document)
        let history = state.documentSession.historySnapshot()
        for width in [320.0, 430, 599, 600, 601, 900, 1023, 1024, 1025, 1440] {
            XCTAssertTrue(state.commitViewportWidth(width))
            await awaitCustomWidthScene(state)
            XCTAssertEqual(state.viewportLayoutWidth, width)
            XCTAssertEqual(state.viewportPreset.responsiveBreakpoint, ResponsiveBreakpoint.resolving(width: width))
            XCTAssertEqual(state.layoutInspectorDraftScope.viewportWidth, width)
            state.performViewportCommand(.init(.actualSize))
            state.resizeViewport(to: .init(width: 940, height: 610), pixelRatio: 1)
            XCTAssertEqual(state.viewportLayoutWidth, width)
            state.resizeViewport(to: .init(width: 1200, height: 760), pixelRatio: 2)
            XCTAssertEqual(state.viewportLayoutWidth, width)
        }
        XCTAssertTrue(state.commitViewportWidth(430))
        state.viewportPreset = .mobile
        XCTAssertEqual(state.viewportLayoutWidth, 390, "Reselecting the effective preset is still an exact reference action")
        XCTAssertEqual(try DocumentSerializer.encode(state.documentSession.document), encoded)
        XCTAssertEqual(state.documentSession.historySnapshot(), history)
    }

    @MainActor
    func testCustomWidthSharedLayoutRenderInspectorHitSelectionAndTextMatrix() async throws {
        let fixture = try customWidthDocument()
        let state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.resizeViewport(to: .init(width: 1200, height: 800), pixelRatio: 2)
        await awaitCustomWidthScene(state); state.selectLayer(fixture.fluid)
        for width in [320.0, 430, 599, 600, 601, 900, 1023, 1024, 1025, 1440] {
            XCTAssertTrue(state.commitViewportWidth(width)); await awaitCustomWidthScene(state)
            let plan = try XCTUnwrap(state.canvasRenderPlan)
            let page = state.documentSession.document.pages[0]
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let geometry = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
            let visible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
            for object in plan.authoredObjects {
                XCTAssertEqual(object.frame, geometry[object.id]?.frame, "The same layout owns container/text and renderer geometry")
            }
            let object = try XCTUnwrap(plan.authoredObjects.first { $0.id == fixture.fluid })
            XCTAssertEqual(state.selectionState.primaryID, fixture.fluid)
            XCTAssertEqual(state.selectionOverlayPlan?.overlays.first?.frame, object.frame)
            XCTAssertEqual(CanvasRendererCore().hitTest(.init(x: object.frame.minX + 2, y: object.frame.minY + 2), in: plan), fixture.fluid)
            let accessibility = try XCTUnwrap(plan.accessibilityElements.first { $0.objectID == fixture.fluid })
            let origin = try plan.viewport.transform.worldToViewport(object.frame.origin)
            XCTAssertEqual(accessibility.frame.origin.x, origin.x, accuracy: 1 / plan.viewport.pixelRatio.value)
            XCTAssertEqual(accessibility.frame.size.width, object.frame.size.width * plan.viewport.zoom.value, accuracy: 1 / plan.viewport.pixelRatio.value)
            XCTAssertEqual(plan.authoredObjects.contains { $0.id == fixture.fixed }, visible.contains(fixture.fixed))
            XCTAssertEqual(plan.accessibilityElements.contains { $0.objectID == fixture.fixed }, visible.contains(fixture.fixed))
            let text = try XCTUnwrap(plan.authoredObjects.first { $0.id == fixture.text })
            let textNode = try XCTUnwrap(page.nodes.first { $0.id == fixture.text })
            XCTAssertEqual(text.typography?.size, TypographyCommandRegistry.resolvedTypography(for: textNode, viewportWidth: width)?.size)
        }
        XCTAssertEqual(state.documentSession.document, fixture.document)
    }

    @MainActor
    func testCustomWidthRejectsInvalidStaleAndPendingContextsWithoutMutation() async throws {
        let state = WorkspaceShellState()
        let before = state.viewportState
        let context = state.responsiveInspectorEditContext
        for width in [Double.nan, .infinity, 0, -1, LayoutPolicy.maximumDimension + 1] {
            XCTAssertFalse(state.commitViewportWidth(width))
            XCTAssertEqual(state.viewportState, before)
        }
        let scope = context.scope
        let staleScopes = [
            LayoutInspectorDraftScope(documentID: DocumentID(), pageID: scope.pageID, sceneID: scope.sceneID, orderedNodeIDs: [], breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth),
            LayoutInspectorDraftScope(documentID: scope.documentID, pageID: PageID(), sceneID: scope.sceneID, orderedNodeIDs: [], breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth),
            LayoutInspectorDraftScope(documentID: scope.documentID, pageID: scope.pageID, sceneID: CanvasViewportSceneID(), orderedNodeIDs: [], breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth),
            LayoutInspectorDraftScope(documentID: scope.documentID, pageID: scope.pageID, sceneID: scope.sceneID, orderedNodeIDs: [NodeID()], breakpoint: scope.breakpoint, viewportWidth: scope.viewportWidth),
            LayoutInspectorDraftScope(documentID: scope.documentID, pageID: scope.pageID, sceneID: scope.sceneID, orderedNodeIDs: [], breakpoint: .mobile, viewportWidth: 430)]
        for stale in staleScopes {
            XCTAssertFalse(state.commitViewportWidth(900, expectedContext: .init(scope: stale, revision: context.revision)))
        }
        XCTAssertFalse(state.commitViewportWidth(900, expectedContext: .init(scope: scope, revision: context.revision + 1)))
        let blocker = state.editCommitRequests.sink { $0.reject() }
        XCTAssertFalse(state.commitViewportWidth(900)); blocker.cancel()
        XCTAssertEqual(state.viewportState, before)
        XCTAssertFalse(state.commitViewportWidthDraft("secret-invalid-input", expectedContext: context))
        XCTAssertFalse(String(describing: state.lastViewportWidthDiagnostic).contains("secret-invalid-input"))
        XCTAssertEqual(state.lastViewportWidthDiagnostic?.failureCategory, "invalid-width")
    }

    @MainActor
    func testCustomWidthPendingIMERejectsThenAllowsExplicitRetry() async throws {
        let fixture = try customWidthDocument()
        let state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.resizeViewport(to: .init(width: 1200, height: 800), pixelRatio: 2)
        await awaitCustomWidthScene(state)
        XCTAssertTrue(state.beginTextEditing(nodeID: fixture.text, provenance: .keyboard))
        state.updateTextEditingDraft(text: "A", selection: .init(location: 1, length: 0), markedRange: .init(location: 0, length: 1))
        XCTAssertEqual(state.selectionState.orderedIDs, [fixture.text])
        XCTAssertEqual(state.textEditingSession.draft?.markedRange, .init(location: 0, length: 1))
        let before = state.viewportState
        XCTAssertFalse(state.commitViewportWidth(430))
        XCTAssertEqual(state.viewportState, before)
        XCTAssertEqual(state.documentSession.document, fixture.document)
        state.cancelTextEditing()
        XCTAssertTrue(state.commitViewportWidth(430))
    }

    @MainActor
    func testCustomWidthTargetsEffectiveOverrideAndKeepsExactUndoRedo() async throws {
        let fixture = try customWidthDocument()
        let state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.resizeViewport(to: .init(width: 1200, height: 800), pixelRatio: 2)
        await awaitCustomWidthScene(state); state.selectLayer(fixture.fluid)
        XCTAssertTrue(state.commitViewportWidth(900)); await awaitCustomWidthScene(state)
        let before = state.documentSession.document.pages
        XCTAssertTrue(state.commitGeometryInspectorValue(27, field: .x, provenance: .keyboard, draftScope: state.layoutInspectorDraftScope))
        let node = try XCTUnwrap(state.documentSession.document.pages[0].nodes.first { $0.id == fixture.fluid })
        XCTAssertEqual(node.insertionNumberProperty(ResponsiveGeometryResolver.key(.x, breakpoint: .tablet)), 27)
        XCTAssertEqual(node.insertionNumberProperty("layout.x"), 20)
        let after = state.documentSession.document.pages
        XCTAssertTrue(state.commitViewportWidth(430))
        try state.documentSession.undo(); XCTAssertEqual(state.documentSession.document.pages, before)
        try state.documentSession.redo(); XCTAssertEqual(state.documentSession.document.pages, after)
        XCTAssertEqual(state.viewportLayoutWidth, 430)
    }

    @MainActor
    func testCustomWidthComparisonCoalescesRapidChangesAndRejectsReplacement() async throws {
        let fixture = try customWidthDocument()
        let state = WorkspaceShellState(documentSession: .init(document: fixture.document))
        state.showResponsiveComparison()
        for width in [900.0, 430, 1023] { XCTAssertTrue(state.commitViewportWidth(width)) }
        let deadline = ContinuousClock.now + .seconds(3)
        while (state.responsiveBreakpointReviews.isEmpty || state.isPreparingResponsiveComparison), ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(state.responsiveBreakpointReviews.count, 4)
        XCTAssertEqual(state.responsiveBreakpointReviews.first { $0.isCurrentWidthSample }?.viewportWidth, 1023)
        XCTAssertEqual(state.responsiveBreakpointReviews.filter { !$0.isCurrentWidthSample }.map(\.viewportWidth), [1440, 768, 390])
        let prior = state.responsiveInspectorEditContext
        state.selectLayer(fixture.fluid)
        XCTAssertFalse(state.commitViewportWidth(900, expectedContext: prior))
        let selectedContext = state.responsiveInspectorEditContext
        let otherPage = try XCTUnwrap(state.documentSession.document.pages.last?.id)
        XCTAssertNotEqual(otherPage, selectedContext.scope.pageID)
        state.selectPage(otherPage)
        XCTAssertFalse(state.commitViewportWidth(900, expectedContext: selectedContext))
        let replacement = ProjectCreation.blank()
        try state.documentSession.establishBaseline(replacement)
        await Task.yield(); await Task.yield(); await awaitCustomWidthScene(state)
        let nextDeadline = ContinuousClock.now + .seconds(3)
        while (state.responsiveBreakpointReviews.isEmpty || state.isPreparingResponsiveComparison), ContinuousClock.now < nextDeadline { await Task.yield() }
        XCTAssertFalse(state.commitViewportWidth(430, expectedContext: prior))
        XCTAssertEqual(state.responsiveBreakpointReviews.count, 4)
        XCTAssertTrue(state.responsiveBreakpointReviews.allSatisfy { $0.objectCount == 0 })
    }

    @MainActor
    func testCustomWidthInsertionPreviewPackageAndStaticOutputRemainTruthful() async throws {
        let state = WorkspaceShellState()
        XCTAssertTrue(state.commitViewportWidth(430)); await awaitCustomWidthScene(state)
        state.performDefaultInsertion(.frame, provenance: .keyboard)
        await awaitCustomWidthScene(state)
        let object = try XCTUnwrap(state.canvasRenderPlan?.authoredObjects.first)
        XCTAssertGreaterThanOrEqual(object.frame.minX, 0); XCTAssertLessThanOrEqual(object.frame.maxX, 430)
        let canonical = state.documentSession.document
        let store = ProjectPackageStore()
        let package = ProjectPackage(document: canonical)
        let encoded = try await store.encode(package)
        let before = StaticBuildCompiler.compile(document: canonical, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertNotNil(before.plan)
        for width in [320.0, 900, 1024] { XCTAssertTrue(state.commitViewportWidth(width)) }
        let afterWidthPackage = ProjectPackage(projectID: package.projectID,
            createdAt: package.createdAt, modifiedAt: package.modifiedAt,
            document: state.documentSession.document, optionalMembers: package.optionalMembers,
            compatibility: package.compatibility)
        let afterWidthBytes = try await store.encode(afterWidthPackage)
        XCTAssertEqual(afterWidthBytes, encoded)
        let reopened = try await store.decode(encoded)
        XCTAssertEqual(reopened.document, canonical)
        let fresh = WorkspaceShellState(documentSession: .init(document: reopened.document))
        XCTAssertEqual(fresh.viewportLayoutWidth, 1440, "Inspection width is not package state")
        let after = StaticBuildCompiler.compile(document: canonical, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        XCTAssertEqual(before.plan, after.plan)
        XCTAssertEqual(state.documentSession.document, canonical)
        let recoveryFixture = try ApplicationOwnedTestFixture.create("custom-width")
        defer { try? recoveryFixture.cleanup() }
        let recoveryDirectory = recoveryFixture.url.appendingPathComponent("recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(recoveryDirectory)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: package.projectID, in: recoveryDirectory)
        try await store.write(afterWidthPackage, to: recoveryURL, policy: .recovery(package.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(from: recoveryURL, expectedProjectID: package.projectID).package
        XCTAssertEqual(recovered, package)
    }

    func testCustomWidthConnectedFlowAndReferenceComparisonShareActualSample() async throws {
        let document = StarterSiteTemplate.document()
        let page = try XCTUnwrap(document.pages.first)
        let worker = WorkspaceScenePreparationWorker()
        for width in [320.0, 430, 599, 600, 601, 900, 1023, 1024, 1025, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let bounds = WorldRect(origin: .init(x: 0, y: 0), size: .init(width: width,
                height: CanonicalPageFlow.contentHeight(page, breakpoint: breakpoint, width: width)))
            let viewport = try CanvasViewportState(contentBounds: bounds)
            let prepared = try await worker.prepare(.init(document: document, activePageID: page.id,
                activeContainerID: nil, viewport: viewport, surfaceID: .init(), breakpoint: breakpoint, viewportWidth: width))
            let geometry = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
            for object in prepared.renderScene.objects { XCTAssertEqual(object.frame, geometry[object.id]?.frame) }
            let reviews = ResponsiveBreakpointReviewPolicy.reviews(page: page, selectedNodeIDs: [], currentViewportWidth: width)
            XCTAssertEqual(reviews.count, 4); XCTAssertEqual(Set(reviews.map(\.id)).count, 4)
            XCTAssertEqual(reviews.last?.viewportWidth, width)
            let preview = try await LocalPreviewRuntimeCompiler().compile(document: document, imageResourceData: [:], pixelRatio: .init(2), viewportWidth: width)
            XCTAssertEqual(preview.pages.first?.viewportBounds, bounds)
            XCTAssertEqual(preview.pages.first?.objects, prepared.renderScene.objects)
        }
        for invalid in [Double.nan, .infinity, 0, -1, LayoutPolicy.maximumDimension + 1] {
            do {
                _ = try await LocalPreviewRuntimeCompiler().compile(document: document,
                    imageResourceData: [:], pixelRatio: .init(1), viewportWidth: invalid)
                XCTFail("Invalid inspection width must not create a Preview snapshot")
            } catch let error as LocalPreviewRuntimeError {
                XCTAssertEqual(error, .invalidViewportWidth)
            }
        }
    }
    // SF-0401-001, SF-0401-003, SF-0401-005 — a new/adopted workspace fits
    // the noncanonical pasteboard after the real canvas has a usable size.
    @MainActor
    func testFreshWorkspaceFitsPasteboardWithoutMutatingAuthoredCoordinates() throws {
        let state = WorkspaceShellState()
        let document = state.documentSession.document
        state.resizeViewport(to: .init(width: 1_000, height: 700), pixelRatio: 2)

        // A fresh workspace uses the editor-only Fit Document presentation so
        // the artboard boundary and surrounding pasteboard remain visible.
        // The fit must not alter canonical authored coordinates.
        XCTAssertEqual(state.viewportState.fitPolicy, .fitDocument)
        let origin = try state.viewportState.transform.worldToViewport(
            state.viewportState.contentBounds.origin
        )
        let width = state.viewportState.contentBounds.size.width * state.viewportState.zoom.value
        let height = state.viewportState.contentBounds.size.height * state.viewportState.zoom.value
        XCTAssertEqual(origin.x + width / 2, state.viewportState.viewportSize.width / 2, accuracy: 0.000_001)
        XCTAssertEqual(origin.y + height / 2, state.viewportState.viewportSize.height / 2, accuracy: 0.000_001)
        XCTAssertEqual(state.documentSession.document, document)
    }

    // SF-0401-001, SF-0401-004, SF-0401-008
    func testWorldViewportDeviceRoundTripsAcrossRepresentativeScales() throws {
        for scale in [1.0, 1.5, 2.0, 3.0, 4.0] {
            let transform = try CanvasCoordinateTransform(
                worldOrigin: WorldPoint(x: -98_765.4321, y: 45_678.9876),
                zoom: CanvasZoom(3.125),
                pixelRatio: CanvasPixelRatio(scale)
            )
            for point in [
                WorldPoint(x: -999_999.25, y: -0.125),
                WorldPoint(x: 0, y: 0),
                WorldPoint(x: 847_293_011.75, y: -125_000_000.5),
            ] {
                let viewport = try transform.worldToViewport(point)
                let world = try transform.viewportToWorld(viewport)
                XCTAssertEqual(world.x, point.x, accuracy: CanvasCoordinateTransform.reversibleTolerance)
                XCTAssertEqual(world.y, point.y, accuracy: CanvasCoordinateTransform.reversibleTolerance)
                let device = try transform.worldToDevice(point)
                let fromDevice = try transform.deviceToWorld(device)
                XCTAssertEqual(fromDevice.x, point.x, accuracy: CanvasCoordinateTransform.reversibleTolerance)
                XCTAssertEqual(fromDevice.y, point.y, accuracy: CanvasCoordinateTransform.reversibleTolerance)
            }
        }
    }

    // SF-0401-001, SF-0401-004
    func testInvalidNonfiniteOverflowSizeZoomAndPixelRatioAreRejected() throws {
        XCTAssertThrowsError(try CanvasZoom(.nan))
        XCTAssertThrowsError(try CanvasZoom(0.1))
        XCTAssertThrowsError(try CanvasPixelRatio(0))
        XCTAssertThrowsError(try CanvasPixelRatio(.infinity))
        XCTAssertThrowsError(try CanvasCoordinateTransform(
            worldOrigin: WorldPoint(x: 1e13, y: 0),
            zoom: .actualSize,
            pixelRatio: CanvasPixelRatio(2)
        ))
        XCTAssertThrowsError(try CanvasViewportState(
            viewportSize: ViewportSize(width: 0, height: 700)
        ))
        let transform = try CanvasCoordinateTransform(
            worldOrigin: WorldPoint(x: 0, y: 0),
            zoom: .actualSize,
            pixelRatio: CanvasPixelRatio(2)
        )
        XCTAssertThrowsError(try transform.worldToViewport(WorldPoint(x: .nan, y: 0)))
    }

    // SF-0401-001, SF-0401-002, SF-0401-005
    func testCursorAnchoredZoomClampsAtMinimumNormalAndMaximum() throws {
        var state = try CanvasViewportState(worldOrigin: WorldPoint(x: -400, y: 250))
        let cursor = ViewportPoint(x: 317.25, y: 211.75)
        let anchor = try state.transform.viewportToWorld(cursor)

        try state.zoom(to: 2.75, around: cursor)
        assertWorld(try state.transform.viewportToWorld(cursor), equals: anchor)
        try state.zoom(to: 0.001, around: cursor)
        XCTAssertEqual(state.zoom, .minimum)
        assertWorld(try state.transform.viewportToWorld(cursor), equals: anchor)
        try state.zoom(to: 100, around: cursor)
        XCTAssertEqual(state.zoom, .maximum)
        assertWorld(try state.transform.viewportToWorld(cursor), equals: anchor)
    }

    // SF-0401-002, SF-0401-003, SF-0401-004
    func testPanBoundsResizeResetAndFitPoliciesAreDeterministic() throws {
        var state = try CanvasViewportState(
            viewportSize: ViewportSize(width: 800, height: 600),
            contentBounds: WorldRect(
                origin: WorldPoint(x: -1_000, y: -500),
                size: WorldSize(width: 2_000, height: 1_000)
            )
        )
        let center = try state.transform.viewportToWorld(ViewportPoint(x: 400, y: 300))
        try state.resize(to: ViewportSize(width: 1_000, height: 700), pixelRatio: 1.5)
        assertWorld(try state.transform.viewportToWorld(ViewportPoint(x: 500, y: 350)), equals: center)

        try state.pan(by: ViewportVector(dx: 1e9, dy: -1e9))
        XCTAssertGreaterThanOrEqual(state.worldOrigin.x, state.contentBounds.minX - CanvasViewportState.panPadding)
        XCTAssertLessThanOrEqual(state.visibleWorldRect.maxY, state.contentBounds.maxY + CanvasViewportState.panPadding + 1e-9)

        try state.fit(.fitDocument)
        XCTAssertEqual(state.fitPolicy, .fitDocument)
        XCTAssertLessThanOrEqual(state.visibleWorldRect.minX, state.contentBounds.minX)
        XCTAssertGreaterThanOrEqual(state.visibleWorldRect.maxX, state.contentBounds.maxX)
        try state.fit(.fitWidth)
        XCTAssertEqual(state.fitPolicy, .fitWidth)
        XCTAssertEqual(
            state.contentBounds.size.width * state.zoom.value,
            state.viewportSize.width - 96,
            accuracy: 1e-8
        )
        try state.reset()
        XCTAssertEqual(state.zoom, .actualSize)
        XCTAssertEqual(state.fitPolicy, .none)
    }

    // SF-0401-001, SF-0401-007
    func testRepeatedConversionsDoNotAccumulateDrift() throws {
        let transform = try CanvasCoordinateTransform(
            worldOrigin: WorldPoint(x: -123_456.789, y: 987_654.321),
            zoom: CanvasZoom(7.875),
            pixelRatio: CanvasPixelRatio(2)
        )
        let original = WorldPoint(x: -42_424.2424, y: 81_818.1818)
        var value = original
        for _ in 0..<10_000 {
            value = try transform.deviceToWorld(transform.worldToDevice(value))
        }
        assertWorld(value, equals: original)
        let aligned = try transform.pixelAligned(ViewportPoint(x: 10.26, y: 20.74))
        XCTAssertEqual(aligned.x * 2, (10.26 * 2).rounded(.toNearestOrEven))
        XCTAssertEqual(aligned.y * 2, (20.74 * 2).rounded(.toNearestOrEven))
    }

    // SF-0401-004, SF-0401-007, SF-0401-008
    func testPreparationCancellationAndStaleIdentityAreStateNeutral() async throws {
        let document = ProjectCreation.blank()
        let state = try CanvasViewportState()
        let identity = CanvasViewportOperationIdentity(
            documentID: document.id,
            revision: document.revision,
            sceneID: state.sceneID,
            generation: state.generation
        )
        let objects = fixtureObjects(count: 10_000)
        let request = CanvasViewportPreparationRequest(identity: identity, viewport: state, objects: objects)
        let preparer = CanvasViewportScenePreparer()
        let counter = CancellationCounter()
        do {
            _ = try await preparer.prepare(request, cancellation: CanvasViewportCancellation {
                counter.incrementAndReached(4)
            })
            XCTFail("Expected cancellation")
        } catch {
            XCTAssertEqual(error as? CanvasViewportError, .cancelled)
        }

        let valid = try await preparer.prepare(request)
        let stale = CanvasViewportOperationIdentity(
            documentID: identity.documentID,
            revision: identity.revision + 1,
            sceneID: identity.sceneID,
            generation: identity.generation
        )
        XCTAssertThrowsError(try CanvasViewportAdoptionGate().validate(valid, expected: stale)) {
            XCTAssertEqual($0 as? CanvasViewportError, .staleResult)
        }
    }

    // SF-0401-007, SF-0401-008
    @MainActor
    func testHundredAndTenThousandObjectPreparationIsDeterministicAndYieldsMainActor() async throws {
        let context = WorkspaceDocumentContext()
        var mainActorProgressed = false
        let marker = Task { @MainActor in
            await Task.yield()
            mainActorProgressed = true
        }
        let hundred = try await context.shellState.prepareViewportScene(objects: fixtureObjects(count: 100))
        let tenThousand = try await context.shellState.prepareViewportScene(objects: fixtureObjects(count: 10_000))
        _ = await marker.value
        XCTAssertTrue(mainActorProgressed)
        XCTAssertEqual(hundred.objectCount, 100)
        XCTAssertEqual(tenThousand.objectCount, 10_000)
        let repeatResult = try await context.shellState.prepareViewportScene(objects: fixtureObjects(count: 10_000))
        XCTAssertEqual(repeatResult.deterministicDigest, tenThousand.deterministicDigest)
    }

    // SF-0401-001, SF-0401-005, SF-0401-008
    @MainActor
    func testViewportIsIndependentPerWindowAndNeverMutatesCanonicalDocument() throws {
        let first = WorkspaceDocumentContext()
        let second = WorkspaceDocumentContext()
        let firstDocument = first.shellState.documentSession.document
        let secondDocument = second.shellState.documentSession.document
        first.shellState.performViewportCommand(CanvasViewportCommand(.zoomIn))
        first.shellState.performViewportCommand(CanvasViewportCommand(.panRight))

        XCTAssertNotEqual(first.shellState.viewportState, second.shellState.viewportState)
        XCTAssertEqual(first.shellState.documentSession.document, firstDocument)
        XCTAssertEqual(second.shellState.documentSession.document, secondDocument)
        XCTAssertEqual(second.shellState.zoomPercent, 100)
        XCTAssertNotEqual(first.shellState.viewportState.sceneID, second.shellState.viewportState.sceneID)
    }

    // SF-0401-004, SF-0401-005, SF-0401-008
    @MainActor
    func testOperationIdentityTracksDocumentRevisionSceneAndViewportGeneration() async throws {
        let state = WorkspaceShellState()
        let initial = state.currentViewportOperationIdentity

        state.performViewportCommand(CanvasViewportCommand(.zoomIn))
        let zoomed = state.currentViewportOperationIdentity
        XCTAssertEqual(zoomed.documentID, initial.documentID)
        XCTAssertEqual(zoomed.revision, initial.revision)
        XCTAssertEqual(zoomed.sceneID, initial.sceneID)
        XCTAssertGreaterThan(zoomed.generation, initial.generation)

        let replacement = ProjectCreation.blank()
        try state.documentSession.establishBaseline(replacement)
        await Task.yield()
        await Task.yield()
        let adopted = state.currentViewportOperationIdentity
        XCTAssertEqual(adopted.documentID, replacement.id)
        XCTAssertEqual(adopted.revision, replacement.revision)
        XCTAssertNotEqual(adopted.sceneID, initial.sceneID)
        XCTAssertEqual(adopted.generation, 0)
    }

    // SF-0203-004, SF-0401-004, SF-0407-004 — canonical publication is
    // forwarded to the shell on an event boundary. If two transactions arrive
    // in one run-loop turn, only the newest document identity may prepare or
    // adopt derived viewport/render state.
    @MainActor
    func testRapidDocumentPublicationsAdoptOnlyTheNewestRevision() async throws {
        let state = WorkspaceShellState()
        let pageID = try XCTUnwrap(state.documentSession.document.pages.first?.id)
        try state.documentSession.execute(.renamePage(.init(pageID: pageID, name: "First")))
        try state.documentSession.execute(.renamePage(.init(pageID: pageID, name: "Second")))
        let expectedRevision = state.documentSession.document.revision

        for _ in 0..<200 {
            if state.canvasRenderPlan?.identity.revision == expectedRevision { break }
            await Task.yield()
        }
        XCTAssertEqual(state.documentSession.document.revision, expectedRevision)
        XCTAssertEqual(state.canvasRenderPlan?.identity.revision, expectedRevision)
        XCTAssertEqual(state.canvasRenderPlan?.identity.documentID, state.documentSession.document.id)
    }

    // SF-0401-006, SF-0401-008
    @MainActor
    func testCentralViewportCommandsAnnounceAndDiagnosticsRemainRedacted() async {
        var announcements: [String] = []
        let diagnostics = CanvasViewportDiagnostics()
        let state = WorkspaceShellState(
            viewportDiagnostics: diagnostics,
            announcementPoster: AccessibilityAnnouncementPoster { announcements.append($0) }
        )
        state.performViewportCommand(CanvasViewportCommand(.zoomIn))
        state.performViewportCommand(CanvasViewportCommand(.panLeft))
        await Task.yield()

        XCTAssertEqual(announcements, ["Canvas zoom 125 percent", "Canvas panned panLeft"])
        let records = await diagnostics.snapshot()
        XCTAssertEqual(records.count, 2)
        XCTAssertTrue(records.allSatisfy { $0.requirementID == "SF-0401-008" })
        XCTAssertTrue(records.allSatisfy { $0.sceneIdentifier.count == "scene-".count + 24 })
        XCTAssertTrue(records.allSatisfy { !$0.sceneIdentifier.contains(state.viewportState.sceneID.description) })
        let encoded = String(data: try! JSONEncoder().encode(records), encoding: .utf8)!
        XCTAssertFalse(encoded.contains(state.documentSession.document.id.description))
        XCTAssertFalse(encoded.contains("/Users/"))
    }

    // SF-0401-006, SF-0401-008
    func testViewportCommandRegistryDefinesIntentionalEnablement() throws {
        let registry = CanvasViewportCommandRegistry()
        var state = try CanvasViewportState()
        XCTAssertTrue(registry.isEnabled(CanvasViewportCommand(.zoomIn), in: state))
        try state.zoom(to: CanvasZoom.maximum.value, around: ViewportPoint(x: 0, y: 0))
        XCTAssertFalse(registry.isEnabled(CanvasViewportCommand(.zoomIn), in: state))
        XCTAssertThrowsError(try registry.apply(CanvasViewportCommand(.zoomIn), to: &state))
        XCTAssertTrue(registry.isEnabled(CanvasViewportCommand(.actualSize), in: state))
    }

    private func fixtureObjects(count: Int) -> [CanvasViewportSceneObject] {
        (0..<count).map { index in
            let uuid = UUID(uuidString: String(
                format: "51000000-0000-0000-0000-%012llx",
                UInt64(index + 1)
            ))!
            return CanvasViewportSceneObject(
                id: NodeID(uuid),
                bounds: WorldRect(
                    origin: WorldPoint(x: Double(index % 100) * 120 - 4_000, y: Double(index / 100) * 80 - 2_000),
                    size: WorldSize(width: 100, height: 60)
                )
            )
        }
    }

    func testWorldGridPolicyIsZoomAdaptiveWorldAnchoredAndDeviceCrisp() throws {
        XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 0.25), 64)
        XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 1), 16)
        XCTAssertEqual(CanvasWorldGridPolicy.minorInterval(for: 8), 8)
        XCTAssertEqual(CanvasWorldGridPolicy.majorInterval(for: 1), 64)
        for scale in [1.0, 2.0] {
            let aligned = CanvasWorldGridPolicy.deviceAligned(17.33, scale: scale)
            XCTAssertEqual((aligned * scale).rounded(), aligned * scale, accuracy: 0.000_001)
        }
        for origin in [WorldPoint(x: -320, y: 160), WorldPoint(x: 480, y: -240)] {
            let transform = try CanvasCoordinateTransform(worldOrigin: origin, zoom: .actualSize, pixelRatio: .init(2))
            let worldLine = floor(origin.x / 16) * 16
            XCTAssertEqual(try transform.viewportToWorld(transform.worldToViewport(.init(x: worldLine, y: 0))).x, worldLine, accuracy: 0.000_001)
        }
    }

    // SF-0401-001 — initial/preset fitting is presentation-only and leaves
    // a visible editor gutter around the real content bounds.
    func testFitDocumentLeavesArtboardGutterAndRevealDoesNotMutateBounds() throws {
        var state = try CanvasViewportState(
            worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 1_200, height: 800),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)),
            pixelRatio: .init(2)
        )
        try state.fit(.fitDocument)
        XCTAssertEqual(state.fitPolicy, .fitDocument)
        XCTAssertGreaterThan(state.contentBounds.minX - state.visibleWorldRect.minX, 0)
        XCTAssertGreaterThan(state.visibleWorldRect.maxX - state.contentBounds.maxX, 0)
        let bounds = state.contentBounds
        try state.reveal(.init(origin: .init(x: 1_800, y: 300), size: .init(width: 120, height: 80)))
        XCTAssertEqual(state.contentBounds, bounds)
        XCTAssertEqual(state.fitPolicy, .none)
    }

    // SF-0401-001, SF-0402-005 — AppKit can transiently reconcile a zero
    // canvas size. Editor overlay insets must become neutral rather than
    // creating negative layer geometry during that transition.
    func testCanvasDrawingInsetsRejectTransientNegativeGeometry() {
        XCTAssertNil(CanvasViewportDrawGeometry.inset(.zero, dx: 2, dy: 2))
        XCTAssertNil(CanvasViewportDrawGeometry.inset(
            CGRect(x: 0, y: 0, width: 3, height: 4), dx: 2, dy: 2
        ))
        XCTAssertNil(CanvasViewportDrawGeometry.inset(
            CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10), dx: 1, dy: 1
        ))
        XCTAssertEqual(
            CanvasViewportDrawGeometry.inset(
                CGRect(x: 4, y: 8, width: 20, height: 12), dx: 2, dy: 3
            ),
            CGRect(x: 6, y: 11, width: 16, height: 6)
        )
    }

    // SF-0401-001, SF-0402-005 — object-context badges are editor chrome,
    // not pasteboard decorations. Every edge relocates the complete badge
    // inside the visible artboard intersection.
    func testSelectionBadgePlacementRemainsInsideAllArtboardEdges() throws {
        let artboard = CGRect(x: 100, y: 100, width: 400, height: 300)
        let full = "Frame · 240 × 160 · Root"
        let compact = "Frame · 240 × 160"
        let rects = [
            CGRect(x: 100, y: 180, width: 60, height: 80), // left
            CGRect(x: 440, y: 180, width: 60, height: 80), // right
            CGRect(x: 250, y: 100, width: 80, height: 50), // top
            CGRect(x: 250, y: 350, width: 80, height: 50), // bottom
        ]
        for rect in rects {
            let placement = try XCTUnwrap(CanvasSelectionChromeLayout.badgePlacement(
                selectionRect: rect, artboardRect: artboard,
                fullText: full, fullWidth: 180,
                compactText: compact, compactWidth: 140
            ))
            XCTAssertTrue(artboard.contains(placement.frame), "\(rect)")
            XCTAssertFalse(placement.usesCompactText)
        }
    }

    // SF-0401-001, SF-0402-005 — narrow visible intersections receive a
    // readable compact badge; entirely off-artboard selection is represented
    // only through semantic status/accessibility, never a visual badge.
    func testSelectionBadgePlacementUsesCompactFallbackAndSuppressesOffArtboard() throws {
        let full = "Frame · 240 × 160 · Root"
        let compact = "Frame · 240 × 160"
        let narrowArtboard = CGRect(x: 0, y: 0, width: 156, height: 120)
        let compactPlacement = try XCTUnwrap(CanvasSelectionChromeLayout.badgePlacement(
            selectionRect: CGRect(x: 120, y: 12, width: 36, height: 60), artboardRect: narrowArtboard,
            fullText: full, fullWidth: 180, compactText: compact, compactWidth: 140
        ))
        XCTAssertTrue(compactPlacement.usesCompactText)
        XCTAssertEqual(compactPlacement.text, compact)
        XCTAssertTrue(narrowArtboard.contains(compactPlacement.frame))
        XCTAssertNil(CanvasSelectionChromeLayout.badgePlacement(
            selectionRect: CGRect(x: 200, y: 10, width: 20, height: 20), artboardRect: narrowArtboard,
            fullText: full, fullWidth: 180, compactText: compact, compactWidth: 140
        ))
    }

    private func assertWorld(
        _ actual: WorldPoint,
        equals expected: WorldPoint,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.x, expected.x, accuracy: CanvasCoordinateTransform.reversibleTolerance, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: CanvasCoordinateTransform.reversibleTolerance, file: file, line: line)
    }
}

private final class CancellationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func incrementAndReached(_ limit: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value >= limit
    }
}
