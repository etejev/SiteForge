import Combine
import AppKit
import Darwin
import CryptoKit
import XCTest
@testable import SiteForge

@MainActor
final class InsertionModelTests: XCTestCase {
    // SF-LOCAL-BUILDER-016 / SF-0702-003/004.
    func testLegacyDesignEquivalentBoxCommitIsSuccessfulAndHistoryNeutral() async throws {
        let (session, _, _, _) = try outputRepairFixture()
        let header = try XCTUnwrap(session.document.pages[0].nodes.first { CanonicalPageFlow.role($0) == .header })
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1100, height: 700), pixelRatio: 2)
        await awaitOutputRepairScene(state)
        state.selectLayer(header.id)
        XCTAssertTrue(state.commitDesignBoxStyle(.cornerRadius(8), operation: "corner radius"))
        await awaitOutputRepairScene(state)
        let document = session.document, history = session.historySnapshot(), selection = state.selectionState
        XCTAssertTrue(state.commitDesignBoxStyle(.cornerRadius(try XCTUnwrap(Double("8.0"))), operation: "corner radius"))
        XCTAssertEqual(state.lastDesignInspectorAnnouncement, "Appearance unchanged")
        XCTAssertEqual(session.document, document); XCTAssertEqual(session.historySnapshot(), history)
        XCTAssertEqual(state.selectionState, selection)
    }

    // SF-LOCAL-BUILDER-016 / SF-1203-004, SF-1211-004.
    func testCheckWebsiteEntryDoesNotCancelOrRetargetAnActiveStaticWrite() async throws {
        let owned = try ApplicationOwnedTestFixture.create("check-while-writing")
        defer { try? owned.cleanup() }
        let session = DocumentSession(document: ProjectCreation.blank())
        let state = WorkspaceShellState(documentSession: session)
        state.openBuildDiagnostics()
        await awaitOutputRepair(state) { state.staticBuildPhase == .ready }
        let compilation = try XCTUnwrap(state.staticBuildCompilation)
        let history = session.historySnapshot(), document = session.document
        let destination = owned.url.appendingPathComponent("website")
        state.writeStaticBuild(to: destination, replacingExisting: false, expectedCompilation: compilation)
        XCTAssertEqual(state.staticBuildPhase, .writing)
        state.runStaticBuildPreflight()
        XCTAssertEqual(state.staticBuildPhase, .writing)
        state.openBuildDiagnostics()
        XCTAssertEqual(state.staticBuildPhase, .writing)
        XCTAssertEqual(state.staticBuildCompilation, compilation)
        XCTAssertTrue(state.isBuildDiagnosticsPresented)
        XCTAssertTrue(state.buildFindingRevealStatus.contains("Wait"))
        await awaitOutputRepair(state) { state.staticBuildPhase != .writing }
        XCTAssertEqual(state.staticBuildPhase, .succeeded(destination))
        XCTAssertTrue(state.buildFindingRevealStatus.isEmpty, "Completed output must not retain a contradictory Wait message")
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("index.html").path))
        XCTAssertEqual(session.document, document); XCTAssertEqual(session.historySnapshot(), history)
        state.runStaticBuildPreflight()
        await awaitOutputRepair(state) { state.staticBuildPhase == .ready }
        state.writeStaticBuild(to: owned.url.appendingPathComponent("cancelled"), replacingExisting: false)
        state.cancelStaticBuild(silent: true)
        XCTAssertEqual(state.staticBuildPhase, .cancelled, "Silent dismissal must not leave a taskless writing phase")
        state.openBuildDiagnostics()
        await awaitOutputRepair(state) { state.staticBuildPhase == .ready }
        XCTAssertEqual(session.document, document); XCTAssertEqual(session.historySnapshot(), history)
    }

    // SF-LOCAL-BUILDER-015; execution is recorded in the bounded focused receipt.
    private func outputRepairFixture() throws -> (DocumentSession, NodeID, PageID, NodeID) {
        let fixture = try chromeReuseFixture(), session = DocumentSession(document: fixture.document)
        try setConnectedFixtureProperty(DesignBoxStyleCommandRegistry.namespace + "clip.content",
            value: .boolean(true), nodeID: fixture.header, session: session)
        try session.execute(PageChromeCopyRegistry().prepare(chromeReuseRequest(fixture, document: session.document,
            roles: [.header], targets: [fixture.targets[0]]), document: session.document).command)
        let page = try XCTUnwrap(session.document.pages.first { $0.id == fixture.targets[0] })
        let copied = try XCTUnwrap(page.nodes.first { CanonicalPageFlow.role($0) == .header })
        let sourcePage = session.document.pages[0]
        let source = try XCTUnwrap(sourcePage.nodes.first { $0.id == fixture.header })
        return (session, copied.id, page.id, try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.titleKey, on: source)))
    }
    private func awaitOutputRepair(_ state: WorkspaceShellState,
                                   until ready: @MainActor () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(4)
        while ContinuousClock.now < deadline {
            if ready() { return }
            await Task.yield()
        }
        XCTFail("Expected receipt/scene adoption did not finish: \(state.buildFindingRevealStatus)")
    }
    private func openOutputRepairReceipt(_ state: WorkspaceShellState, source: StaticBuildFindingSource,
                                        excluding oldID: UUID? = nil) async throws -> StaticBuildFindingReceipt {
        switch source {
        case .browserPreview: state.openBrowserPreview()
        case .checkWebsite: state.openBuildDiagnostics(); if oldID != nil { state.runStaticBuildPreflight() }
        }
        await awaitOutputRepair(state) {
            let receipt = source == .browserPreview ? state.browserPreview.findingReceipt : state.staticBuildFindingReceipt
            return receipt != nil && receipt?.id != oldID && !state.browserPreview.isBuilding && state.staticBuildPhase != .preflighting
        }
        return try XCTUnwrap(source == .browserPreview ? state.browserPreview.findingReceipt : state.staticBuildFindingReceipt)
    }
    private func revealOutputRepair(_ state: WorkspaceShellState, finding: StaticBuildFinding,
                                    receipt: StaticBuildFindingReceipt, source: StaticBuildFindingSource) -> Task<Void, Never>? {
        source == .browserPreview ? state.revealBrowserBuildFinding(finding, receipt: receipt)
            : state.revealStaticBuildFinding(finding, receipt: receipt)
    }
    private func awaitOutputRepairScene(_ state: WorkspaceShellState) async {
        await awaitOutputRepair(state) {
            guard let plan = state.canvasRenderPlan else { return false }
            return plan.identity.documentID == state.documentSession.document.id
                && plan.identity.revision == state.documentSession.document.revision
                && plan.identity.viewportGeneration == state.viewportState.generation
        }
    }

    func testOutputFindingTargetUsesExactReceiptMembershipTypedEditorsAndReadOnlyIdentity() throws {
        let (session, target, _, _) = try outputRepairFixture()
        let document = session.document
        let result = connectedFluidCompilation(document), receipt = StaticBuildFindingReceipt(compilation: result)
        let finding = try XCTUnwrap(result.findings.first { $0.affectedNodeID == target && $0.code == "page-flow-navigation-clipped" })
        let prepared = try StaticBuildFindingTarget.prepare(finding, receipt: receipt, document: document, breakpoint: .desktop)
        XCTAssertEqual(prepared.nodeID, target); XCTAssertEqual(prepared.destination, .designBox)
        let bytes = try DocumentSerializer.encode(document), history = session.historySnapshot()
        func member(_ item: StaticBuildFinding) -> StaticBuildFindingReceipt {
            .init(compilation: .init(documentID: document.id, revision: document.revision,
                profile: .development, plan: nil, report: nil, findings: [item]))
        }
        func failure(_ finding: StaticBuildFinding, _ receipt: StaticBuildFindingReceipt, _ doc: CanonicalDocument,
                     _ expected: StaticBuildFindingTarget.Failure) {
            XCTAssertThrowsError(try StaticBuildFindingTarget.prepare(finding, receipt: receipt, document: doc, breakpoint: .desktop)) {
                XCTAssertEqual($0 as? StaticBuildFindingTarget.Failure, expected)
            }
        }
        let foreign = StaticBuildFinding(severity: finding.severity, code: finding.code,
            requirementID: finding.requirementID, affectedNodeID: target, explanation: "Different result body", repair: finding.repair)
        XCTAssertEqual(foreign.id, finding.id)
        failure(foreign, receipt, document, .foreignFinding)
        failure(finding, receipt, ProjectCreation.blank(), .staleDocument)
        var stale = document; stale.revision += 1
        failure(finding, receipt, stale, .staleRevision)
        for flag in ["locked", "hidden"] {
            var protected = document
            let p = try XCTUnwrap(protected.pages.firstIndex { $0.id == prepared.pageID })
            let n = try XCTUnwrap(protected.pages[p].nodes.firstIndex { $0.id == target })
            protected.pages[p].nodes[n].properties.removeAll { $0.key.rawValue == flag }
            protected.pages[p].nodes[n].properties.append(.init(key: .init(rawValue: flag), value: .boolean(true), origin: .authored))
            failure(finding, receipt, protected, .lockedOrHidden)
        }
        for (id, expected) in [(NodeID?.none, StaticBuildFindingTarget.Failure.noObject), (Optional(NodeID()), .missingObject)] {
            let item = StaticBuildFinding(severity: .unsupported, code: "future-unsupported", requirementID: "SF-1211-004",
                affectedNodeID: id, explanation: "Unsupported content", repair: "Keep the authored value.")
            failure(item, member(item), document, expected)
        }
        for code in ["future-code", "page-flow-navigation-room", "page-flow-positioning"] {
            let item = StaticBuildFinding(severity: .warning, code: code, requirementID: "SF-1204-004",
                affectedNodeID: target, explanation: "The wording must not choose an editor", repair: "Open Design, Layout, Contents or any other words")
            let resolved = try StaticBuildFindingTarget.prepare(item, receipt: member(item), document: document, breakpoint: .desktop)
            XCTAssertEqual(resolved.destination, code == "page-flow-navigation-room" ? .pageContents : code == "page-flow-positioning" ? .layout : .object)
        }
        var withDefinition = document
        var definition = DocumentPage.minimum(name: "Exact original", route: "", role: .componentDefinition, provenance: .authored)
        let root = definition.rootNodeIDs[0]
        let text = DocumentNode(kind: .text, name: "Do not guess by name", parent: .node(root), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(0)), .init(key: .init(rawValue: "layout.y"), value: .number(0)),
            .init(key: .init(rawValue: "layout.width"), value: .number(120)), .init(key: .init(rawValue: "layout.height"), value: .number(24)),
            .init(key: .init(rawValue: "content.text"), value: .string("Original"))])
        definition.nodes[0].childIDs.append(text.id); definition.nodes.append(text); withDefinition.pages.append(definition)
        try withDefinition.validate()
        let item = StaticBuildFinding(severity: .policyBlocked, code: "future-policy", requirementID: "SF-1211-004",
            affectedNodeID: text.id, explanation: "Retained intent", repair: "Use the existing original editor.")
        let original = try StaticBuildFindingTarget.prepare(item, receipt: member(item), document: withDefinition, breakpoint: .desktop)
        XCTAssertEqual(original.pageID, definition.id); XCTAssertEqual(original.nodeID, text.id); XCTAssertEqual(original.destination, .object)
        XCTAssertEqual(try DocumentSerializer.encode(session.document), bytes); XCTAssertEqual(session.historySnapshot(), history)
    }

    func testPreviewAndCheckWebsiteRevealExactCrossPageObjectAfterSceneAdoptionWithoutHistoryOrPackageMutation() async throws {
        for source in [StaticBuildFindingSource.checkWebsite, .browserPreview] {
            let (session, target, pageID, _) = try outputRepairFixture()
            let state = WorkspaceShellState(documentSession: session)
            defer { state.browserPreview.stop() }
            state.resizeViewport(to: .init(width: 1100, height: 700), pixelRatio: 2)
            await awaitOutputRepairScene(state)
            let bytes = try DocumentSerializer.encode(session.document), history = session.historySnapshot()
            let receipt = try await openOutputRepairReceipt(state, source: source)
            let finding = try XCTUnwrap(receipt.findings.first { $0.affectedNodeID == target && $0.code == "page-flow-navigation-clipped" })
            XCTAssertEqual(state.buildFindingRevealAvailability(finding, receipt: receipt, source: source), .action("Open Design"))
            var unrelatedCommitRequests = 0
            let monitor = state.editCommitRequests.sink { if !$0.requiresCleanEditors { unrelatedCommitRequests += 1 } }
            let work = try XCTUnwrap(revealOutputRepair(state, finding: finding, receipt: receipt, source: source))
            await work.value
            await awaitOutputRepair(state) { state.hasCurrentBuildFindingEditorRequest }
            XCTAssertEqual(state.effectiveSelectedPageID, pageID); XCTAssertEqual(state.selectionState.primaryID, target)
            XCTAssertEqual(state.inspectorTab, .design); XCTAssertEqual(state.navigatorTab, .layers)
            XCTAssertEqual(state.buildFindingInspectorAnchor, "inspector.design.boxStyle")
            XCTAssertEqual(unrelatedCommitRequests, 0, "Reveal must never ask unrelated editors to commit")
            monitor.cancel()
            XCTAssertFalse(state.isBuildDiagnosticsPresented); XCTAssertFalse(state.isBrowserPreviewPresented)
            XCTAssertNotNil(state.canvasRenderPlan?.authoredObjects.first { $0.id == target })
            XCTAssertEqual(try DocumentSerializer.encode(session.document), bytes); XCTAssertEqual(session.historySnapshot(), history)
            let store = ProjectPackageStore(), package = ProjectPackage(document: session.document)
            let encoded = try await store.encode(package)
            let reopened = try await store.decode(encoded)
            XCTAssertEqual(reopened.document, session.document)
            XCTAssertNil(state.browserPreview.plan, "This blocked fixture must not launch Safari or fabricate successful output")
        }
    }

    func testOutputRepairRejectsOldForeignPageChangedAndProjectReplacedReceiptsWithoutPartialNavigation() async throws {
        for source in [StaticBuildFindingSource.checkWebsite, .browserPreview] {
            let (session, target, pageID, _) = try outputRepairFixture()
            let state = WorkspaceShellState(documentSession: session)
            defer { state.browserPreview.stop() }
            state.resizeViewport(to: .init(width: 1100, height: 700), pixelRatio: 2)
            await awaitOutputRepairScene(state)
            let receipt = try await openOutputRepairReceipt(state, source: source)
            let finding = try XCTUnwrap(receipt.findings.first { $0.affectedNodeID == target })
            let origin = state.effectiveSelectedPageID, selection = state.selectionState, history = session.historySnapshot()
            let foreign = StaticBuildFinding(severity: finding.severity, code: finding.code, requirementID: finding.requirementID,
                affectedNodeID: target, explanation: "Not a member of this exact receipt", repair: finding.repair)
            XCTAssertNil(revealOutputRepair(state, finding: foreign, receipt: receipt, source: source))
            let current = try await openOutputRepairReceipt(state, source: source, excluding: receipt.id)
            XCTAssertNotEqual(current.id, receipt.id)
            XCTAssertNil(revealOutputRepair(state, finding: finding, receipt: receipt, source: source))
            XCTAssertEqual(state.effectiveSelectedPageID, origin); XCTAssertEqual(state.selectionState, selection)
            XCTAssertEqual(session.historySnapshot(), history)
            state.selectPage(pageID); await awaitOutputRepairScene(state)
            let changedPageSelection = state.selectionState
            XCTAssertNil(revealOutputRepair(state, finding: finding, receipt: current, source: source))
            XCTAssertEqual(state.effectiveSelectedPageID, pageID); XCTAssertEqual(state.selectionState, changedPageSelection)
            var replacement = ProjectCreation.blank()
            let root = replacement.pages[0].rootNodeIDs[0]
            replacement.pages[0].nodes[0].childIDs = [target]
            replacement.pages[0].nodes.append(.init(id: target, kind: .frame, name: "Same name is not identity", parent: .node(root), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(0)), .init(key: .init(rawValue: "layout.y"), value: .number(0)),
                .init(key: .init(rawValue: "layout.width"), value: .number(120)), .init(key: .init(rawValue: "layout.height"), value: .number(80))]))
            try state.documentSession.establishBaseline(replacement)
            let replacementBytes = try DocumentSerializer.encode(session.document)
            XCTAssertNil(revealOutputRepair(state, finding: finding, receipt: current, source: source))
            XCTAssertEqual(try DocumentSerializer.encode(session.document), replacementBytes)
        }
    }

    func testOutputRepairCleanEditorIMEAndCancellationGuardsNeverCommitUnrelatedDrafts() async throws {
        for source in [StaticBuildFindingSource.checkWebsite, .browserPreview] {
            let (session, target, _, textID) = try outputRepairFixture()
            let state = WorkspaceShellState(documentSession: session)
            defer { state.browserPreview.stop() }
            state.resizeViewport(to: .init(width: 1100, height: 700), pixelRatio: 2)
            await awaitOutputRepairScene(state)
            let receipt = try await openOutputRepairReceipt(state, source: source)
            let finding = try XCTUnwrap(receipt.findings.first { $0.affectedNodeID == target })
            let before = session.document, history = session.historySnapshot(), openingPage = state.effectiveSelectedPageID
            var commits = 0
            let blocker = state.editCommitRequests.sink { request in
                if request.requiresCleanEditors { request.reject() } else { commits += 1 }
            }
            XCTAssertNil(revealOutputRepair(state, finding: finding, receipt: receipt, source: source)); blocker.cancel()
            XCTAssertEqual(commits, 0); XCTAssertEqual(session.document, before); XCTAssertEqual(session.historySnapshot(), history)
            XCTAssertTrue(state.beginTextEditing(nodeID: textID, provenance: .keyboard))
            state.updateTextEditingDraft(text: "Composing", selection: .init(location: 1, length: 0), markedRange: .init(location: 0, length: 1))
            XCTAssertNil(revealOutputRepair(state, finding: finding, receipt: receipt, source: source))
            XCTAssertTrue(state.textEditingSession.isActive); XCTAssertEqual(session.document, before)
            state.cancelTextEditing(); await awaitOutputRepairScene(state)
            let selection = state.selectionState
            let work = try XCTUnwrap(revealOutputRepair(state, finding: finding, receipt: receipt, source: source))
            state.cancelBuildFindingReveal(); await work.value
            XCTAssertEqual(state.effectiveSelectedPageID, openingPage); XCTAssertEqual(state.selectionState, selection)
            XCTAssertNil(state.buildFindingEditorRequest); XCTAssertEqual(session.document, before); XCTAssertEqual(session.historySnapshot(), history)
            XCTAssertFalse(state.isOpeningBuildFinding)
        }
    }

    // SF-LOCAL-BUILDER-013; execution is recorded in the bounded focused receipt.
    private func narrowChromeNodes(_ page: DocumentPage, _ id: NodeID) throws
        -> (owner: DocumentNode, content: DocumentNode, title: DocumentNode, navigation: DocumentNode) {
        let owner = try XCTUnwrap(page.nodes.first { $0.id == id })
        func role(_ key: String) throws -> DocumentNode {
            let target = try XCTUnwrap(CanonicalPageChrome.reference(key, on: owner))
            return try XCTUnwrap(page.nodes.first { $0.id == target })
        }
        return try (owner, role(CanonicalPageChrome.contentKey), role(CanonicalPageChrome.titleKey), role(CanonicalPageChrome.navigationKey))
    }

    func testAutomaticChromeMenuFirstAllocationAtPhoneFractionalAndLargerWidthsIsReadOnly() throws {
        let (session, header, _, footer) = try connectedPageSession()
        let before = try DocumentSerializer.encode(session.document), history = session.historySnapshot()
        for width in [263.25, 320, 360, 390, 430, 517.5, 599.5, 600, 768, 1024, 1440] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let page = session.document.pages[0]
            let frames = page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width)
            for ownerID in [header, footer] {
                let nodes = try narrowChromeNodes(page, ownerID)
                let snapshot = try XCTUnwrap(CanonicalPageFlow.navigation(owner: nodes.owner, page: page,
                    document: session.document, breakpoint: breakpoint, width: width))
                XCTAssertEqual(snapshot.usesHamburger, width < 600)
                if width < 600 {
                    let row = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: nodes.owner, page: page, breakpoint: breakpoint, width: width))
                    let content = try XCTUnwrap(frames[nodes.content.id]?.frame)
                    let allocation = try XCTUnwrap(row.allocate(innerWidth: content.size.width - 2 * row.padding))
                    let title = try XCTUnwrap(frames[nodes.title.id]?.frame)
                    let navigation = try XCTUnwrap(frames[nodes.navigation.id]?.frame)
                    XCTAssertGreaterThanOrEqual(navigation.size.width, CanonicalPageChrome.menuControlWidth)
                    XCTAssertLessThanOrEqual(title.maxX + allocation.gap, navigation.minX + 0.000001)
                    XCTAssertEqual(navigation.maxX, content.maxX - row.padding, accuracy: 0.000001)
                    XCTAssertEqual(title.size.width, try XCTUnwrap(allocation.widths[nodes.title.id]), accuracy: 0.000001)
                    XCTAssertLessThanOrEqual(title.size.width, nodes.title.insertionNumberProperty("layout.width")!)
                    XCTAssertGreaterThanOrEqual(title.minY, content.minY)
                    XCTAssertLessThanOrEqual(title.maxY, content.maxY)
                } else {
                    XCTAssertNil(CanonicalPageChrome.automaticMenuRow(owner: nodes.owner, page: page, breakpoint: breakpoint, width: width))
                }
            }
        }
        XCTAssertEqual(try DocumentSerializer.encode(session.document), before)
        XCTAssertEqual(session.historySnapshot(), history)
    }

    func testAutomaticChromeHiddenEmptyLongAndMultilineTitleRetainsIdentityAndLinePolicy() throws {
        let (session, header, _, _) = try connectedPageSession()
        let original = try narrowChromeNodes(session.document.pages[0], header)
        let widthProperty = try XCTUnwrap(original.title.insertionProperty("layout.width"))
        for text in ["", "Site", String(repeating: "Unbroken", count: 30), "First line\nSecond line"] {
            // Inline Text editing can author hard breaks; the dedicated
            // single-line Header title field intentionally cannot.
            try setConnectedFixtureProperty("content.text", value: .string(text), nodeID: original.title.id, session: session)
            let document = session.document, page = document.pages[0]
            let tree = try InternalDocumentRenderTreeCompiler.compile(page: page, documentID: document.id,
                revision: document.revision, staticRoutes: [page.id: "index.html"], breakpoint: .mobile, viewportWidth: 320)
            let title = try XCTUnwrap(tree.nodes.first { $0.id == original.title.id })
            XCTAssertEqual(title.textContent, text)
            XCTAssertTrue(title.isManagedChromeTitle)
            XCTAssertEqual(title.frame, page.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 320)[original.title.id]?.frame)
            XCTAssertEqual(CanvasTextLayoutPolicy.visibleLineCapacity(height: title.frame.size.height,
                lineHeight: try XCTUnwrap(title.typography).lineHeight), 1)
            XCTAssertEqual(page.nodes.first { $0.id == original.title.id }?.insertionProperty("layout.width"), widthProperty)
            XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
        }
        try session.execute(pageStructureCommand(.showTitle(header, false), document: session.document, selected: header))
        let page = session.document.pages[0], nodes = try narrowChromeNodes(page, header)
        let row = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: nodes.owner, page: page, breakpoint: .mobile, width: 320))
        XCTAssertNil(row.titleID)
        let frames = page.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 320)
        XCTAssertEqual(frames[nodes.navigation.id]?.size.width, frames[nodes.content.id]?.size.width)
        XCTAssertFalse(page.effectiveVisibleNodeIDs(breakpoint: .mobile).contains(nodes.title.id))
        XCTAssertTrue(ConnectedPageOutput.css(pages: session.document.pages).contains("\(CanonicalCSSRule.selector(for: nodes.title.id))[data-siteforge-node] { display:none; }"))
    }

    func testAutomaticChromeMenuCardinalityVisibilityAndOffPreferenceRemainTruthful() throws {
        let (session, header, _, _) = try connectedPageSession()
        for _ in 0..<4 {
            try session.execute(pageStructureCommand(.addLink(owner: header, pageID: session.document.pages[0].id), document: session.document, selected: header))
        }
        var page = session.document.pages[0]
        var owner = try narrowChromeNodes(page, header).owner
        let many = try XCTUnwrap(CanonicalPageFlow.navigation(owner: owner, page: page, document: session.document, breakpoint: .mobile, width: 320))
        XCTAssertGreaterThanOrEqual(many.links.count, 5)
        XCTAssertEqual(many.currentPageID, page.id)
        XCTAssertTrue(many.usesHamburger)
        XCTAssertEqual(Set(many.links.map(\.id)).count, many.links.count)
        try session.execute(pageStructureCommand(.hamburger(header, false), document: session.document, selected: header))
        page = session.document.pages[0]; owner = try narrowChromeNodes(page, header).owner
        let off = try XCTUnwrap(CanonicalPageFlow.navigation(owner: owner, page: page, document: session.document, breakpoint: .mobile, width: 320))
        XCTAssertFalse(off.usesHamburger); XCTAssertFalse(off.hamburgerEnabled)
        XCTAssertEqual(off.links, many.links)
        XCTAssertNil(CanonicalPageChrome.automaticMenuRow(owner: owner, page: page, breakpoint: .mobile, width: 320))
        for destination in session.document.websitePages where destination.role != .notFound {
            try session.execute(pageStructureCommand(.includePage(header, destination.id, false), document: session.document, selected: header))
        }
        page = session.document.pages[0]; owner = try narrowChromeNodes(page, header).owner
        XCTAssertNil(CanonicalPageFlow.navigation(owner: owner, page: page, document: session.document, breakpoint: .mobile, width: 320))
        let emptyOff = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: owner, page: page, breakpoint: .mobile, width: 320))
        XCTAssertEqual(emptyOff.navigationMinimum, 0)
        XCTAssertFalse(emptyOff.reservesMenu)
        XCTAssertFalse(emptyOff.orderedIDs.contains(emptyOff.navigationID))
        XCTAssertEqual(CanonicalPageChrome.links(owner: owner, page: page).map(\.id), many.links.map(\.id))
        try session.execute(pageStructureCommand(.hamburger(header, true), document: session.document, selected: header))
        page = session.document.pages[0]; owner = try narrowChromeNodes(page, header).owner
        let empty = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: owner, page: page,
            breakpoint: .mobile, width: 320, availablePageIDs: Set(session.document.websitePages.map(\.id))))
        XCTAssertFalse(empty.reservesMenu)
        XCTAssertEqual(empty.navigationMinimum, 0)
        XCTAssertFalse(empty.orderedIDs.contains(empty.navigationID))
        let allocation = try XCTUnwrap(empty.allocate(innerWidth: 224))
        XCTAssertEqual(allocation.widths[try XCTUnwrap(empty.titleID)], 200)
        XCTAssertNil(allocation.widths[empty.navigationID])
        let noLinksCSS = ConnectedPageOutput.automaticMenuRules(page, usesWrapper: false,
            availablePageIDs: Set(session.document.websitePages.map(\.id))).joined(separator: "\n")
        XCTAssertFalse(noLinksCSS.components(separatedBy: "\n").contains {
            $0.hasPrefix(CanonicalCSSRule.selector(for: empty.navigationID) + " {") && $0.contains("flex:1 0 90.0px")
        }, "Only the emptied Header loses its Menu budget; the fixture's independent Footer remains usable")
        XCTAssertTrue(noLinksCSS.contains("\(CanonicalCSSRule.selector(for: empty.navigationID)) { display:none; }"))
    }

    func testAutomaticChromeMissingDestinationsDoNotCreateDecorativeMenu() throws {
        let (session, header, _, _) = try connectedPageSession()
        try session.execute(pageStructureCommand(.addLink(owner: header, pageID: session.document.pages[0].id),
            document: session.document, selected: header))
        var document = session.document
        let nodes = try narrowChromeNodes(document.pages[0], header)
        let ids = Set(CanonicalPageChrome.links(owner: nodes.owner, page: document.pages[0]).map(\.id))
        for index in document.pages[0].nodes.indices where ids.contains(document.pages[0].nodes[index].id) {
            let property = try XCTUnwrap(document.pages[0].nodes[index].properties.firstIndex { $0.key.rawValue == CanonicalLinkTarget.namespace + "pageID" })
            document.pages[0].nodes[index].properties[property].value = .string(PageID().description)
        }
        let page = document.pages[0], owner = try narrowChromeNodes(page, header).owner
        let snapshot = try XCTUnwrap(CanonicalPageFlow.navigation(owner: owner, page: page, document: document, breakpoint: .mobile, width: 320))
        XCTAssertTrue(snapshot.hamburgerEnabled, "Authored preference must not be rewritten")
        XCTAssertFalse(snapshot.usesHamburger)
        XCTAssertTrue(snapshot.links.allSatisfy { !$0.isAvailable })
        let available = Set(document.websitePages.map(\.id))
        let brokenRow = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: owner, page: page,
            breakpoint: .mobile, width: 320, availablePageIDs: available))
        XCTAssertFalse(brokenRow.reservesMenu)
        XCTAssertEqual(brokenRow.navigationMinimum, 1, "Retain unavailable link intent, not a Menu budget")
        for fluid in [false, true] {
            let css = ConnectedPageOutput.automaticMenuRules(page, usesWrapper: fluid,
                availablePageIDs: available).joined(separator: "\n")
            XCTAssertFalse(css.components(separatedBy: "\n").contains {
                $0.hasPrefix(CanonicalCSSRule.selector(for: nodes.navigation.id) + " {") && $0.contains("flex:1 0 90.0px")
            })
            XCTAssertTrue(css.contains("flex:1 0 1.0px"))
        }
        let tree = try InternalDocumentRenderTreeCompiler.compile(page: page, documentID: document.id,
            revision: document.revision, breakpoint: .mobile, viewportWidth: 320)
        let html = try SafeHTMLEmitter.emit(tree)
        XCTAssertFalse(html.contains("data-siteforge-navigation=\"\(nodes.navigation.id)\""))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)

        // A valid but hidden link must not make the remaining broken links
        // acquire a decorative Menu in either connected CSS adapter.
        let validID = try XCTUnwrap(ids.sorted { $0.description < $1.description }.first)
        let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == validID })
        let targetIndex = try XCTUnwrap(document.pages[0].nodes[index].properties.firstIndex {
            $0.key.rawValue == CanonicalLinkTarget.namespace + "pageID"
        })
        document.pages[0].nodes[index].properties[targetIndex].value = .string(page.id.description)
        document.pages[0].nodes[index].properties.removeAll { $0.key.rawValue == "hidden" }
        document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: "hidden"),
            value: .boolean(true), origin: .authored))
        let mixedPage = document.pages[0]
        XCTAssertFalse(CanonicalPageChrome.hasUsableNavigation(owner: owner, page: mixedPage,
            availablePageIDs: Set(document.websitePages.map(\.id)), breakpoint: .mobile))
        let mixed = try XCTUnwrap(CanonicalPageFlow.navigation(owner: owner, page: mixedPage,
            document: document, breakpoint: .mobile, width: 320))
        XCTAssertFalse(mixed.usesHamburger)
        let mixedRow = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: owner, page: mixedPage,
            breakpoint: .mobile, width: 320, availablePageIDs: available))
        XCTAssertFalse(mixedRow.reservesMenu)
        XCTAssertEqual(mixedRow.navigationMinimum, 1)
        let mixedFrames = mixedPage.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 320,
            availablePageIDs: available)
        XCTAssertEqual(mixed.itemFrames.first?.width, mixedFrames[mixed.links[0].id]?.size.width)
        for fluid in [false, true] {
            XCTAssertFalse(ConnectedPageOutput.automaticMenuRules(mixedPage, usesWrapper: fluid,
                availablePageIDs: available).joined(separator: "\n").components(separatedBy: "\n").contains {
                    $0.hasPrefix(CanonicalCSSRule.selector(for: nodes.navigation.id) + " {") && $0.contains("flex:1 0 90.0px")
                })
        }
        let rules = ConnectedPageOutput.navigationMenuRules(surface: nodes.navigation, settings: owner,
            page: mixedPage, breakpoint: .mobile, availablePageIDs: Set(document.websitePages.map(\.id)))
        XCTAssertTrue(rules.contains(".sf-page-navigation-\(nodes.navigation.id) .sf-nav-menu { display:none; }"))
        XCTAssertNil(CanonicalPageChrome.mobileOutputRoomFailure(owner: owner, page: mixedPage,
            availablePageIDs: available), "Do not report an absent Menu as a constrained Menu")
        for fluid in [false, true] {
            var outputDocument = document
            if fluid {
                let ownerIndex = try XCTUnwrap(outputDocument.pages[0].nodes.firstIndex { $0.id == header })
                outputDocument.pages[0].nodes[ownerIndex].properties.append(.init(
                    key: .init(rawValue: CanonicalFluidValueCodec.key(.height)),
                    value: .string(try CanonicalFluidValueCodec.encode(.init(minimum: 120, preferred: 180, maximum: 240), target: .height)),
                    origin: .authored))
            }
            let css = ConnectedPageOutput.css(pages: outputDocument.pages)
            XCTAssertTrue(css.contains(".sf-page-navigation-\(nodes.navigation.id) .sf-nav-menu { display:none; }"))
            XCTAssertFalse(css.contains("\(CanonicalCSSRule.selector(for: nodes.navigation.id)) { position:relative;left:auto;top:auto;width:90.0px;flex:1 0 90.0px"))
        }
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
    }

    func testNarrowChromeCustomSizingSpacingFontsAndFluidIntentAreNeverRewritten() throws {
        for mode in ["custom", "title-width", "font", "fluid-title"] {
            let (session, header, _, _) = try connectedPageSession()
            let nodes = try narrowChromeNodes(session.document.pages[0], header)
            switch mode {
            case "custom":
                try session.execute(pageStructureCommand(.contentLayout(header, axis: .horizontal, gap: 80, alignment: .end), document: session.document, selected: header))
            case "title-width":
                try setConnectedFixtureProperty("layout.width", value: .number(250), nodeID: nodes.title.id, session: session)
            case "font":
                let link = try XCTUnwrap(CanonicalPageChrome.links(owner: nodes.owner, page: session.document.pages[0]).first)
                try setConnectedFixtureProperty(CanonicalTypography.namespace + "lineHeight", value: .number(40), nodeID: link.id, session: session)
                try setConnectedFixtureProperty(CanonicalTypography.namespace + "size", value: .number(32), nodeID: link.id, session: session)
            default:
                try setConnectedFixtureProperty(CanonicalFluidValueCodec.key(.width), value: .string(CanonicalFluidValueCodec.encode(.init(minimum: 100, preferred: 200, maximum: 260), target: .width)), nodeID: nodes.title.id, session: session)
            }
            let before = try DocumentSerializer.encode(session.document), history = session.historySnapshot()
            for width in [320.0, 430, 599.5] {
                let page = session.document.pages[0], owner = try narrowChromeNodes(page, header).owner
                XCTAssertNil(CanonicalPageChrome.automaticMenuRow(owner: owner, page: page, breakpoint: .mobile, width: width), mode)
                _ = page.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: width)
            }
            XCTAssertEqual(try DocumentSerializer.encode(session.document), before)
            XCTAssertEqual(session.historySnapshot(), history)
        }
    }

    func testAutomaticChromeFixedLogoAndAuthoredGapUseSameInnerBudget() throws {
        let (session, header, _, _) = try connectedPageSession()
        let nodes = try narrowChromeNodes(session.document.pages[0], header)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Private test logo", originalFilename: "logo.png", format: .png,
            pixelWidth: 2, pixelHeight: 2, byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes))
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        let image = DocumentNode(kind: .image, name: "Logo", parent: .node(nodes.content.id), properties: [
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"), value: .string(asset.id.description)),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string("fit")),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string("Brand")),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(false)),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.5)),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.5)),
            .init(key: .init(rawValue: "layout.x"), value: .number(0)), .init(key: .init(rawValue: "layout.y"), value: .number(0)),
            .init(key: .init(rawValue: "layout.width"), value: .number(32)), .init(key: .init(rawValue: "layout.height"), value: .number(16))])
        try session.execute(.insertNode(.init(pageID: session.document.pages[0].id, node: image, index: 0)))
        try setConnectedFixtureProperty("layout.gap", value: .number(37), nodeID: nodes.content.id, session: session)
        let before = session.document
        for width in [320.0, 360, 430, 599.5] {
            let page = session.document.pages[0], owner = try narrowChromeNodes(page, header).owner
            let row = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: owner, page: page, breakpoint: .mobile, width: width))
            let frames = page.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: width)
            let content = try XCTUnwrap(frames[nodes.content.id]?.frame)
            let allocation = try XCTUnwrap(row.allocate(innerWidth: content.size.width - 2 * row.padding))
            XCTAssertEqual(allocation.gap, 37)
            XCTAssertEqual(frames[image.id]?.size.width, 32)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(frames[nodes.navigation.id]?.size.width), 90)
            XCTAssertLessThanOrEqual(try XCTUnwrap(frames[image.id]?.frame.maxX), try XCTUnwrap(frames[nodes.title.id]?.frame.minX))
        }
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.document.imageAssets, [asset])
        try setConnectedFixtureProperty("layout.width", value: .number(500), nodeID: image.id, session: session)
        let page = session.document.pages[0], owner = try narrowChromeNodes(page, header).owner
        let navigationBounds = try XCTUnwrap(page.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 320)[nodes.navigation.id]?.frame)
        XCTAssertNotNil(CanonicalPageChrome.narrowMenuGuidance(owner: owner, page: page, document: session.document, width: 320, navigationBounds: navigationBounds))
        XCTAssertEqual(page.nodes.first { $0.id == image.id }?.insertionNumberProperty("layout.width"), 500)
        XCTAssertEqual(CanonicalPageChrome.mobileOutputRoomFailure(owner: owner, page: page)?.code, "page-flow-navigation-room")
        let blocked = connectedFluidCompilation(session.document)
        XCTAssertNil(blocked.plan)
        XCTAssertTrue(blocked.findings.contains { $0.code == "page-flow-navigation-room" && $0.affectedNodeID == header })
    }

    func testAutomaticChromeStaticAndFluidAdaptersKeepSharedContinuousAllocationAndBlockers() throws {
        let (session, header, _, _) = try connectedPageSession()
        let nodes = try narrowChromeNodes(session.document.pages[0], header)
        for fluid in [false, true] {
            if fluid {
                try setConnectedFixtureProperty(CanonicalFluidValueCodec.key(.height), value: .string(CanonicalFluidValueCodec.encode(.init(minimum: 120, preferred: 180, maximum: 240), target: .height)), nodeID: header, session: session)
            }
            let before = session.document
            let row = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: try narrowChromeNodes(before.pages[0], header).owner,
                page: before.pages[0], breakpoint: .mobile, width: 320))
            let rules = ConnectedPageOutput.automaticMenuRules(before.pages[0], usesWrapper: fluid).joined(separator: "\n")
            XCTAssertTrue(rules.contains("gap:" + row.cssGap))
            XCTAssertTrue(rules.contains("flex:1 0 90.0px;min-width:90.0px"))
            XCTAssertTrue(rules.contains("flex:0 1 200.0px;min-width:1.0px"))
            XCTAssertTrue(rules.contains("left:auto;top:auto"))
            XCTAssertEqual(rules.contains("." + ConnectedFluidOutputPolicy.wrapperClass(nodes.content.id)), fluid)
            let plan = try XCTUnwrap(connectedFluidCompilation(before).plan)
            let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
            XCTAssertTrue(css.contains(row.cssGap))
            let html = plan.files.filter { $0.path.hasSuffix(".html") }.map(\.contents).joined()
            XCTAssertTrue(html.contains("data-siteforge-text"))
            XCTAssertTrue(html.contains("sf-nav-panel-\(nodes.navigation.id)"))
            XCTAssertEqual(session.document, before)
        }
        try setConnectedFixtureProperty(DesignBoxStyleCommandRegistry.namespace + "clip.content", value: .boolean(true), nodeID: header, session: session)
        let blocked = connectedFluidCompilation(session.document)
        XCTAssertNil(blocked.plan)
        XCTAssertTrue(blocked.findings.contains { $0.code == "page-flow-navigation-clipped" && $0.affectedNodeID == header })
    }

    func testAutomaticChromeNativeSceneSelectionHitAndPreviewShareFinalMenuFrame() async throws {
        let (session, header, _, _) = try connectedPageSession()
        let document = session.document, page = document.pages[0], nodes = try narrowChromeNodes(page, header)
        for width in [320.0, 430, 599.5] {
            let viewport = try CanvasViewportState(worldOrigin: .init(x: -20, y: -20), viewportSize: .init(width: 680, height: 440),
                contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: width, height: 960)), pixelRatio: .init(2))
            let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: document,
                activePageID: page.id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID(), breakpoint: .mobile, viewportWidth: width))
            let expected = page.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: width)
            for id in [nodes.title.id, nodes.navigation.id] {
                XCTAssertEqual(prepared.renderScene.objects.first { $0.id == id }?.frame, expected[id]?.frame)
                XCTAssertEqual(prepared.selectionScene?.targets.first { $0.id == id }?.frame, expected[id]?.frame)
            }
            let core = CanvasRendererCore()
            let plan = try core.prepare(scene: prepared.renderScene,
                overlays: .init(identity: prepared.renderScene.identity, overlays: []), viewport: viewport)
            let rect = try XCTUnwrap(expected[nodes.navigation.id]?.frame)
            XCTAssertEqual(core.hitTest(.init(x: rect.minX + rect.size.width / 2, y: rect.minY + rect.size.height / 2), in: plan), nodes.navigation.id)
            XCTAssertEqual(core.previewSnapshot(from: prepared.renderScene).objects.first { $0.id == nodes.navigation.id }?.frame, rect)
            let accessible = try XCTUnwrap(plan.accessibilityElements.first { $0.objectID == nodes.navigation.id })
            let origin = try viewport.transform.worldToViewport(rect.origin)
            XCTAssertEqual(accessible.frame.origin.x, origin.x, accuracy: 0.5)
        }
        var unavailable = document
        let linkIDs = Set(CanonicalPageChrome.links(owner: nodes.owner, page: page).map(\.id))
        for index in unavailable.pages[0].nodes.indices where linkIDs.contains(unavailable.pages[0].nodes[index].id) {
            let property = try XCTUnwrap(unavailable.pages[0].nodes[index].properties.firstIndex {
                $0.key.rawValue == CanonicalLinkTarget.namespace + "pageID"
            })
            unavailable.pages[0].nodes[index].properties[property].value = .string(PageID().description)
        }
        let unavailableBytes = try DocumentSerializer.encode(unavailable)
        let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0), viewportSize: .init(width: 680, height: 440),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 320, height: 960)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: unavailable,
            activePageID: page.id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID(), breakpoint: .mobile, viewportWidth: 320))
        let expected = unavailable.pages[0].resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: 320,
            availablePageIDs: Set(unavailable.websitePages.map(\.id)))
        for id in [nodes.title.id, nodes.navigation.id] {
            XCTAssertEqual(prepared.renderScene.objects.first { $0.id == id }?.frame, expected[id]?.frame)
            XCTAssertEqual(prepared.selectionScene?.targets.first { $0.id == id }?.frame, expected[id]?.frame)
        }
        let snapshot = try XCTUnwrap(CanonicalPageFlow.navigation(owner: nodes.owner, page: unavailable.pages[0],
            document: unavailable, breakpoint: .mobile, width: 320))
        XCTAssertFalse(snapshot.usesHamburger)
        XCTAssertEqual(try DocumentSerializer.encode(unavailable), unavailableBytes)
        XCTAssertEqual(session.document, document)
    }

    func testAutomaticChromeEditsCopiesUndoPackageAndRecoveryKeepAllocationNoncanonical() async throws {
        let fixture = try chromeReuseFixture(), session = DocumentSession(document: fixture.document)
        try session.execute(PageChromeCopyRegistry().prepare(chromeReuseRequest(fixture), document: session.document).command)
        let copiedPage = try XCTUnwrap(session.document.pages.first { $0.id == fixture.targets[0] })
        let copiedOwner = try XCTUnwrap(copiedPage.nodes.first { CanonicalPageFlow.role($0) == .header })
        XCTAssertNotEqual(copiedOwner.id, fixture.header)
        let before = session.document, history = session.historySnapshot()
        for width in [320.0, 457.25, 599.5] {
            for page in session.document.websitePages {
                _ = page.resolvedStructuralGeometry(breakpoint: .mobile, viewportWidth: width,
                    availablePageIDs: Set(session.document.websitePages.map(\.id)))
            }
        }
        XCTAssertEqual(session.document, before); XCTAssertEqual(session.historySnapshot(), history)
        let copiedRow = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: copiedOwner, page: copiedPage,
            breakpoint: .mobile, width: 320, availablePageIDs: Set(session.document.websitePages.map(\.id))))
        XCTAssertTrue(copiedRow.reservesMenu, "Independent copies retain valid destinations on other pages")
        try session.execute(pageStructureCommand(.contentLayout(fixture.header, axis: .horizontal, gap: 37, alignment: .end), document: session.document, selected: fixture.header))
        let after = session.document.pages
        XCTAssertEqual(session.document.pages.first { $0.id == copiedPage.id }, copiedPage)
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, after)
        let store = ProjectPackageStore(), historyStore = PersistedHistoryStore()
        let package = try await historyStore.package(ProjectPackage(document: session.document), with: session.historySnapshot())
        let encoded = try await store.encode(package), reopened = try await store.decode(encoded)
        XCTAssertEqual(reopened.document, session.document)
        let owned = try ApplicationOwnedTestFixture.create("automatic-chrome-menu-recovery")
        defer { try? owned.cleanup() }
        let directory = owned.url.appendingPathComponent("recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(directory)
        let url = DocumentLifecycleBackend.recoveryURL(for: package.projectID, in: directory)
        try await store.write(package, to: url, policy: .recovery(package.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(from: url, expectedProjectID: package.projectID).package
        XCTAssertEqual(recovered, package)
    }

    // SF-LOCAL-BUILDER-011 / SF-0604/1202/1204/1206/1211. UNRUN source.
    private struct ConnectedFluidFixture {
        let document: CanonicalDocument
        let header: NodeID, body: NodeID, footer: NodeID, stack: NodeID, grid: NodeID, frame: NodeID
        let stackChildren: [NodeID], gridChildren: [NodeID]
    }
    private func connectedFluidFixture() throws -> ConnectedFluidFixture {
        let (session, header, bodies, footer) = try connectedPageSession()
        try session.execute(pageStructureCommand(.height(bodies[0], 2000, .desktop), document: session.document, selected: bodies[0]))
        let stack = try insertConnectedChild(.stack, parent: bodies[0], size: .init(width: 600, height: 240), session: session)
        let grid = try insertConnectedChild(.grid, parent: bodies[0], size: .init(width: 600, height: 240), session: session)
        let frame = try insertConnectedChild(.frame, parent: bodies[0], size: .init(width: 400, height: 160), session: session)
        try setConnectedFixtureProperty(DesignBoxStyleCommandRegistry.namespace + "padding.uniform", value: .number(8), nodeID: frame, session: session)
        var stackChildren: [NodeID] = [], gridChildren: [NodeID] = []
        for _ in 0..<2 { stackChildren.append(try insertConnectedChild(.text, parent: stack, size: .init(width: 120, height: 24), session: session)) }
        for _ in 0..<3 { gridChildren.append(try insertConnectedChild(.text, parent: grid, size: .init(width: 120, height: 24), session: session)) }
        _ = try insertConnectedChild(.text, parent: frame, size: .init(width: 120, height: 24), session: session)
        let entries: [(NodeID, FluidValueTarget, Double, Double, Double)] = [
            (header, .height, 120, 160, 200), (header, .padding, 8, 12, 16),
            (footer, .height, 200, 240, 280), (footer, .padding, 16, 24, 32),
            (stack, .padding, 12, 20, 28), (stack, .gap, 8, 16, 24), (stack, .height, 200, 240, 300),
            (grid, .padding, 8, 16, 24), (grid, .gap, 8, 12, 16), (grid, .width, 160, 320, 600),
            (frame, .width, 160, 240, 320), (frame, .height, 120, 160, 200)]
        for (id, target, low, preferred, high) in entries {
            try setConnectedFixtureProperty(CanonicalFluidValueCodec.key(target), value: .string(
                CanonicalFluidValueCodec.encode(.init(minimum: low, preferred: preferred, maximum: high), target: target)), nodeID: id, session: session)
        }
        try session.document.validate()
        return .init(document: session.document, header: header, body: bodies[0], footer: footer,
            stack: stack, grid: grid, frame: frame, stackChildren: stackChildren, gridChildren: gridChildren)
    }
    private func connectedFluidCompilation(_ document: CanonicalDocument, cancelled: Bool = false) -> StaticBuildCompilation {
        StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:], cancelled: cancelled)
    }

    func testConnectedFluidClampCoefficientsMatchAnchorsFractionalWidthsAndClamping() throws {
        let value = CanonicalFluidValue(minimum: 7, preferred: 23, maximum: 61)
        let css = try XCTUnwrap(StaticFluidValueOutputEmitter.expression(for: value, precision: 9))
        let regex = try NSRegularExpression(pattern: #"clamp\(([-0-9.]+)px, calc\(([-0-9.]+)vw ([+-]) ([-0-9.]+)px\), ([-0-9.]+)px\)"#)
        let matches = regex.matches(in: css, range: NSRange(css.startIndex..., in: css))
        XCTAssertEqual(matches.count, 2)
        func segment(_ match: NSTextCheckingResult, _ width: Double) throws -> Double {
            func token(_ index: Int) throws -> String { String(css[try XCTUnwrap(Range(match.range(at: index), in: css))]) }
            let lower = try XCTUnwrap(Double(token(1))), slope = try XCTUnwrap(Double(token(2)))
            let offset = try XCTUnwrap(Double(token(4))), upper = try XCTUnwrap(Double(token(5)))
            return min(upper, max(lower, width * slope / 100 + (try token(3) == "-" ? -offset : offset)))
        }
        for width in [1.0, 320, 389.9999, 390, 390.0001, 430, 599.5, 599.9999, 600, 767.9999, 768, 768.0001, 900, 1023.5, 1023.9999, 1024, 1439.9999, 1440, 1440.0001, 2000] {
            let emitted = try segment(matches[0], width) + segment(matches[1], width) - value.preferred
            XCTAssertEqual(emitted, try XCTUnwrap(value.resolved(viewportWidth: width)), accuracy: 0.000001)
            let bounds = ConnectedOutputLength.fluid(value).bounds(in: .resolving(width: width))
            XCTAssertGreaterThanOrEqual(emitted + 0.000001, bounds.minimum)
            XCTAssertLessThanOrEqual(emitted - 0.000001, bounds.maximum)
        }
        XCTAssertNil(StaticFluidValueOutputEmitter.expression(for: .init(minimum: .nan, preferred: 20, maximum: 30)))
    }

    func testConnectedFluidContainersCompileSemanticHierarchyWithoutSampledOffsets() throws {
        let fixture = try connectedFluidFixture(), original = try DocumentSerializer.encode(fixture.document)
        let result = connectedFluidCompilation(fixture.document)
        let plan = try XCTUnwrap(result.plan, String(describing: result.findings))
        XCTAssertFalse(result.findings.contains { $0.code == "page-flow-fluid-containing-layout" })
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("<header")); XCTAssertTrue(html.contains("<footer"))
        for id in [fixture.header, fixture.body, fixture.footer, fixture.stack, fixture.grid, fixture.frame] {
            XCTAssertTrue(html.contains("class=\"" + ConnectedFluidOutputPolicy.wrapperClass(id) + "\""))
            XCTAssertTrue(html.contains("data-siteforge-node=\"\(id)\""))
        }
        XCTAssertTrue(css.contains("flex-direction:column")); XCTAssertTrue(css.contains("grid-template-columns:repeat(2,"))
        XCTAssertTrue(css.contains("grid-template-rows:max(1px,24.0px,24.0px) max(1px,24.0px)"))
        XCTAssertTrue(css.contains("width:max(1px,calc(100% - 2 * var("))
        XCTAssertTrue(css.contains("margin-block:var(")); XCTAssertTrue(css.contains("clamp("))
        let headerRules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: fixture.header) + " {") }
        let flowHeaderRules = headerRules.filter { $0.contains("--sf-\(fixture.header)-w:") }
        XCTAssertEqual(flowHeaderRules.count, ResponsiveBreakpoint.allCases.count)
        XCTAssertTrue(flowHeaderRules.allSatisfy { $0.contains("position:relative") && $0.contains("top:auto") && $0.contains("width:100%") }, flowHeaderRules.joined(separator: "\n"))
        XCTAssertEqual(try DocumentSerializer.encode(fixture.document), original)
        XCTAssertEqual(connectedFluidCompilation(fixture.document).plan?.files, plan.files)
        let keys = Set(ConnectedFluidOutputPolicy.targets.map(CanonicalFluidValueCodec.key))
        for source in fixture.document.pages[0].nodes {
            for property in source.properties where keys.contains(property.key.rawValue) {
                var isolated = fixture.document
                for index in isolated.pages[0].nodes.indices { isolated.pages[0].nodes[index].properties.removeAll { keys.contains($0.key.rawValue) } }
                let index = try XCTUnwrap(isolated.pages[0].nodes.firstIndex { $0.id == source.id })
                isolated.pages[0].nodes[index].properties.append(property)
                try isolated.validate()
                XCTAssertNotNil(connectedFluidCompilation(isolated).plan, "Each supported binding must work independently as well as combined")
            }
        }
    }

    func testConnectedFluidCascadeCustomWidthsResetAndHiddenGridParticipation() throws {
        let fixture = try connectedFluidFixture(), session = DocumentSession(document: fixture.document)
        let pageID = session.document.pages[0].id
        try setConnectedFixtureProperty(ResponsiveContainerLayoutResolver.key(.gap, breakpoint: .mobile), value: .number(3), nodeID: fixture.stack, session: session)
        try setConnectedFixtureProperty(ResponsiveContainerLayoutResolver.key(.columns, breakpoint: .mobile), value: .number(1), nodeID: fixture.grid, session: session)
        try setConnectedFixtureProperty(ResponsiveVisibilityResolver.key(.mobile), value: .boolean(false), nodeID: fixture.gridChildren[1], session: session)
        let stack = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.stack })
        for width in [320.0, 390, 430, 599.5, 600, 768, 900, 1023.5, 1024, 1440, 1800] {
            let bp = ResponsiveBreakpoint.resolving(width: width)
            let policy = ResolvedContainerLayoutPolicy.resolve(stack, children: [], breakpoint: bp, viewportWidth: width)
            let scalar = ConnectedFluidOutputPolicy.spacing(stack, field: .gap, policy: policy, breakpoint: bp)
            XCTAssertEqual(scalar.resolved(at: width), policy.gap, accuracy: 0.000001)
            if width < 600 { XCTAssertEqual(scalar, .fixed(3)) }
        }
        let css = try XCTUnwrap(connectedFluidCompilation(session.document).plan?.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("--sf-\(fixture.stack)-g:3.0px"))
        XCTAssertTrue(css.contains("grid-template-columns:repeat(1,"))
        let hiddenChild = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.gridChildren[1] })
        XCTAssertEqual(hiddenChild.kind, .text)
        XCTAssertTrue(css.contains(CanonicalCSSRule.selector(for: hiddenChild.id) + "[data-siteforge-node] { display:none; }"),
                      "Visibility must hide the authored Text box, not merely its inner typography span")
        let override = try XCTUnwrap(stack.insertionProperty(ResponsiveContainerLayoutResolver.key(.gap, breakpoint: .mobile)))
        try session.execute(.removeProperty(.init(pageID: pageID, nodeID: stack.id, propertyID: override.id)))
        let reset = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == stack.id })
        let policy = ResolvedContainerLayoutPolicy.resolve(reset, children: [], breakpoint: .mobile, viewportWidth: 430)
        XCTAssertNotEqual(ConnectedFluidOutputPolicy.spacing(reset, field: .gap, policy: policy, breakpoint: .mobile), .fixed(3))
        let fluid = try XCTUnwrap(reset.insertionProperty(CanonicalFluidValueCodec.key(.gap)))
        try session.execute(.removeProperty(.init(pageID: pageID, nodeID: stack.id, propertyID: fluid.id)))
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionNumberProperty("layout.gap"), 24)
        try session.undo(); try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == stack.id }?.insertionProperty(override.key.rawValue)?.id, override.id)
        try setConnectedFixtureProperty(ResponsiveGeometryResolver.key(.width, breakpoint: .tablet), value: .number(222), nodeID: fixture.frame, session: session)
        let frame = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.frame })
        for width in [430.0, 599.5, 600, 900, 1023.5, 1024, 1440] {
            let bp = ResponsiveBreakpoint.resolving(width: width)
            let scalar = ConnectedFluidOutputPolicy.dimension(frame, .width, breakpoint: bp)
            XCTAssertEqual(scalar.resolved(at: width), try XCTUnwrap(ResponsiveGeometryResolver.value(for: .width, node: frame, breakpoint: bp, viewportWidth: width)?.0), accuracy: 0.000001)
            if bp == .tablet { XCTAssertEqual(scalar, .fixed(222)) }
            else { XCTAssertNotEqual(scalar, .fixed(222), "Sibling breakpoints do not inherit each other's overrides") }
        }
    }

    func testConnectedFluidManagedRoleWidthAndBoxPaddingPrecedenceRemainTruthful() throws {
        let fixture = try connectedFluidFixture(), session = DocumentSession(document: fixture.document)
        try setConnectedFixtureProperty(CanonicalFluidValueCodec.key(.width), value: .string(CanonicalFluidValueCodec.encode(.init(minimum: 100, preferred: 200, maximum: 300), target: .width)), nodeID: fixture.header, session: session)
        try setConnectedFixtureProperty(DesignBoxStyleCommandRegistry.namespace + "padding.uniform", value: .number(6), nodeID: fixture.header, session: session)
        let header = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.header })
        for width in [320.0, 430, 768, 900, 1440] {
            let bp = ResponsiveBreakpoint.resolving(width: width)
            let snapshot = ConnectedPageLayoutSnapshot(page: session.document.pages[0], breakpoint: bp, width: width)
            XCTAssertEqual(snapshot.frames[header.id]?.size.width, width)
            let policy = try XCTUnwrap(snapshot.policies[header.id])
            XCTAssertEqual(ConnectedFluidOutputPolicy.spacing(header, field: .padding, policy: policy, breakpoint: bp), .fixed(6))
        }
        let css = try XCTUnwrap(connectedFluidCompilation(session.document).plan?.files.first { $0.path == "styles.css" }?.contents)
        let rules = css.components(separatedBy: "\n").filter { $0.hasPrefix(CanonicalCSSRule.selector(for: header.id) + " {") }
        let flowRules = rules.filter { $0.contains("--sf-\(header.id)-w:") }
        XCTAssertEqual(flowRules.count, ResponsiveBreakpoint.allCases.count)
        XCTAssertTrue(flowRules.allSatisfy { $0.contains("width:100%") && !$0.contains("width:var(") }, flowRules.joined(separator: "\n"))
        XCTAssertNotNil(header.insertionProperty(CanonicalFluidValueCodec.key(.width)))
        XCTAssertNotNil(header.insertionProperty(CanonicalFluidValueCodec.key(.padding)))
    }

    func testConnectedFluidHugFillAndBoundedSizingUseSharedScopeWithoutMutation() throws {
        let fixture = try connectedFluidFixture(), session = DocumentSession(document: fixture.document)
        let oldHeight = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.stack }?.insertionProperty(CanonicalFluidValueCodec.key(.height)))
        try session.execute(.removeProperty(.init(pageID: session.document.pages[0].id, nodeID: fixture.stack, propertyID: oldHeight.id)))
        try setConnectedFixtureProperty(CanonicalSizingConstraints.prefix + "heightMode", value: .string("hug"), nodeID: fixture.stack, session: session)
        try setConnectedFixtureProperty(CanonicalSizingConstraints.prefix + "widthMode", value: .string("fill"), nodeID: fixture.frame, session: session)
        // The fluid width wins over the retained Fill declaration until removed.
        let width = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.frame }?.insertionProperty(CanonicalFluidValueCodec.key(.width)))
        try session.execute(.removeProperty(.init(pageID: session.document.pages[0].id, nodeID: fixture.frame, propertyID: width.id)))
        try setConnectedFixtureProperty(CanonicalSizingConstraints.prefix + "maxWidth", value: .number(500), nodeID: fixture.frame, session: session)
        let before = try DocumentSerializer.encode(session.document)
        let plan = try XCTUnwrap(connectedFluidCompilation(session.document).plan)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("flex:0 0 auto")); XCTAssertTrue(css.contains("max-width:500.0px"))
        let page = session.document.pages[0]
        for width in [320.0, 430, 600, 768, 900, 1023.5, 1440] {
            let bp = ResponsiveBreakpoint.resolving(width: width)
            let scope = ResponsiveSizingLayout.scope(page: page, breakpoint: bp, width: width)
            XCTAssertTrue(scope.affected.contains(fixture.body)); XCTAssertTrue(scope.descendants.contains(fixture.stack))
            let node = try XCTUnwrap(page.nodes.first { $0.id == fixture.stack })
            let policy = ResolvedContainerLayoutPolicy.resolve(node, children: [], breakpoint: bp, viewportWidth: width)
            XCTAssertEqual(try XCTUnwrap(page.resolvedStructuralGeometry(breakpoint: bp, viewportWidth: width)[node.id]?.size.height),
                48 + 2 * policy.padding + policy.gap, accuracy: 0.001)
        }
        XCTAssertEqual(try DocumentSerializer.encode(session.document), before)
    }

    func testConnectedFluidUnsupportedCasesRetainPreciseCompleteMultipageFindings() throws {
        let fixture = try connectedFluidFixture(), session = DocumentSession(document: fixture.document)
        try setConnectedFixtureProperty("layout.height", value: .number(30), nodeID: fixture.grid, session: session)
        try setConnectedFixtureProperty(DesignBoxStyleCommandRegistry.namespace + "clip.content", value: .boolean(true), nodeID: fixture.header, session: session)
        try setConnectedFixtureProperty(CanonicalPositioning.namespace + "mode", value: .string("fixed"), nodeID: fixture.frame, session: session)
        let result = connectedFluidCompilation(session.document)
        XCTAssertNil(result.plan)
        for (code, id) in [("page-flow-fluid-grid-row-compression", fixture.grid), ("page-flow-navigation-clipped", fixture.header), ("page-flow-positioning", fixture.frame)] {
            XCTAssertTrue(result.findings.contains { $0.code == code && $0.affectedNodeID == id && !$0.repair.isEmpty })
        }
        XCTAssertThrowsError(try MultiPageStaticBuildPlanner.plan(document: session.document))
        let cancelled = connectedFluidCompilation(fixture.document, cancelled: true)
        XCTAssertNil(cancelled.plan); XCTAssertTrue(cancelled.findings.contains { $0.code == "cancelled" })
        XCTAssertEqual(session.document.pages.count, fixture.document.pages.count)
        var invalid = fixture.document
        invalid.pages[0].nodes.append(invalid.pages[0].nodes[0])
        let invalidResult = connectedFluidCompilation(invalid)
        XCTAssertNil(invalidResult.plan)
        XCTAssertTrue(invalidResult.findings.contains { $0.code == "plan-invalid" })
    }

    func testConnectedFluidLegacyAndFixedOutputRemainDeterministicWithoutWrappers() throws {
        let (session, _, _, _) = try connectedPageSession()
        let page = session.document.pages[0]
        XCTAssertFalse(ConnectedFluidOutputPolicy.needsAdapter(page))
        XCTAssertTrue(ConnectedFluidOutputPolicy.wrapperIDs(page).isEmpty)
        let plan = try XCTUnwrap(connectedFluidCompilation(session.document).plan)
        XCTAssertFalse(plan.files.contains { $0.contents.contains("class=\"sf-layout-") })
        let baseline = try MultiPageStaticBuildPlanner.plan(document: session.document)
        XCTAssertEqual(LocalBuildProfileCompiler.compile(baseline, profile: .development).0.files, plan.files)
        let id = NodeID(), rect = WorldRect(origin: .init(x: 0, y: 0), size: .init(width: 100, height: 40))
        let tree = InternalRenderTreeSnapshot(documentID: DocumentID(), revision: 0, nodes: [
            .init(id: id, sourceNodeID: id, paintOrder: 0, frame: rect, semanticElement: "section", cssSelector: CanonicalCSSRule.selector(for: id), formField: nil)])
        XCTAssertEqual(try SafeHTMLEmitter.emit(tree), "<section data-siteforge-node=\"\(id)\" class=\"sf-node-\(id)\"></section>")
        XCTAssertEqual(try SafeHTMLEmitter.emit(tree), try SafeHTMLEmitter.emit(tree, layoutContainers: []))
        XCTAssertThrowsError(try SafeHTMLEmitter.emit(tree, layoutContainers: [NodeID()]))
    }

    func testConnectedFluidFreeRootsLegacyNavigationAspectAndFillStayExplicitlyBlocked() throws {
        let fixture = try connectedFluidFixture()
        let free = DocumentSession(document: fixture.document)
        let padding = try XCTUnwrap(free.document.pages[0].nodes.first { $0.id == fixture.frame }?.insertionProperty(DesignBoxStyleCommandRegistry.namespace + "padding.uniform"))
        try free.execute(.removeProperty(.init(pageID: free.document.pages[0].id, nodeID: fixture.frame, propertyID: padding.id)))
        XCTAssertTrue(connectedFluidCompilation(free.document).findings.contains { $0.code == "page-flow-fluid-free-containing-layout" && $0.affectedNodeID == fixture.frame })
        var independent = fixture.document
        let extra = DocumentNode(kind: .frame, name: "Independent root", parent: .page(independent.pages[0].id))
        independent.pages[0].rootNodeIDs.append(extra.id); independent.pages[0].nodes.append(extra)
        XCTAssertTrue(connectedFluidCompilation(independent).findings.contains { $0.code == "page-flow-containing-block" })
        var aspect = fixture.document
        let frameIndex = try XCTUnwrap(aspect.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        aspect.pages[0].nodes[frameIndex].properties += [
            .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "aspectRatio"), value: .number(2.5)),
            .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + "aspectEnabled"), value: .boolean(true))]
        XCTAssertEqual(ConnectedFluidOutputPolicy.failures(aspect.pages[0])[fixture.frame]?.code, "page-flow-fluid-aspect-coupling")
        let fill = DocumentSession(document: fixture.document)
        let height = try XCTUnwrap(fill.document.pages[0].nodes.first { $0.id == fixture.frame }?.insertionProperty(CanonicalFluidValueCodec.key(.height)))
        try fill.execute(.removeProperty(.init(pageID: fill.document.pages[0].id, nodeID: fixture.frame, propertyID: height.id)))
        try setConnectedFixtureProperty(CanonicalSizingConstraints.prefix + "heightMode", value: .string("fill"), nodeID: fixture.frame, session: fill)
        XCTAssertTrue(connectedFluidCompilation(fill.document).findings.contains { $0.code == "page-flow-fluid-fill-height" && $0.affectedNodeID == fixture.frame })
        let legacy = DocumentSession(document: fixture.document), page = legacy.document.pages[0]
        let owner = try XCTUnwrap(page.nodes.first { $0.id == fixture.header })
        let content = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: owner))
        let links = CanonicalPageChrome.links(owner: owner, page: page)
        var changes = try removeConnectedFixtureSubtree(content, pageID: page.id, document: legacy.document)
        changes += owner.properties.filter { $0.key.rawValue.hasPrefix(CanonicalPageChrome.namespace) }.map { .removeProperty(.init(pageID: page.id, nodeID: owner.id, propertyID: $0.id)) }
        changes += links.enumerated().map { index, original in
            var link = original; link.parent = .node(owner.id)
            return .insertNode(.init(pageID: page.id, node: link, index: index))
        }
        try legacy.execute(.batch(changes))
        XCTAssertTrue(connectedFluidCompilation(legacy.document).findings.contains { $0.code == "page-flow-fluid-legacy-navigation" && $0.affectedNodeID == owner.id })
    }

    func testConnectedFluidCompileCloneHistoryPackageRecoveryAndSanitizedContentStayNeutral() async throws {
        let fixture = try connectedFluidFixture(), session = DocumentSession(document: fixture.document)
        let target = DocumentPage.minimum(name: "Copy target", route: "/copy-target", role: .standard, provenance: .authored)
        try session.execute(.insertPage(.init(page: target, index: session.document.pages.count)))
        let source = session.document.pages[0]
        let request = PageChromeCopyRequest(documentID: session.document.id, revision: session.document.revision,
            sourcePageID: source.id, sourceRoles: PageChromeCopyRegistry.sourceRoles(source), roles: [.header, .footer], targetPageIDs: [target.id])
        try session.execute(PageChromeCopyRegistry().prepare(request, document: session.document).command)
        let title = try XCTUnwrap(source.nodes.first { $0.kind == .text && CanonicalPageChrome.owner(of: $0, in: source) != nil })
        try setConnectedFixtureProperty("content.text", value: .string("<script>not executable</script> & content"), nodeID: title.id, session: session)
        let package = ProjectPackage(document: session.document), store = ProjectPackageStore()
        let before = try await store.encode(package), history = session.historySnapshot()
        let plan = try XCTUnwrap(connectedFluidCompilation(session.document).plan)
        XCTAssertTrue(plan.files.contains { $0.contents.contains("&lt;script&gt;not executable&lt;/script&gt;") })
        XCTAssertFalse(plan.files.contains { $0.contents.contains("<script>not executable") })
        XCTAssertEqual(session.historySnapshot(), history)
        let after = try await store.encode(package); XCTAssertEqual(before, after)
        let reopened = try await store.decode(after)
        XCTAssertEqual(reopened.document, session.document)
        let owned = try ApplicationOwnedTestFixture.create("fluid-output-recovery")
        defer { try? owned.cleanup() }
        let directory = owned.url.appendingPathComponent("recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(directory)
        let url = DocumentLifecycleBackend.recoveryURL(for: package.projectID, in: directory)
        try await store.write(package, to: url, policy: .recovery(package.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(from: url, expectedProjectID: package.projectID).package
        XCTAssertEqual(recovered.document, session.document)
        XCTAssertEqual(connectedFluidCompilation(recovered.document).plan?.files, plan.files)
    }

    func testConnectedFluidOriginalImageBytesAndMissingResourcesBlockWholePlan() throws {
        let fixture = try connectedFluidFixture()
        var document = fixture.document
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<2 { for x in 0..<2 { bitmap.setColor(.purple, atX: x, y: y) } }
        let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Fluid image", originalFilename: "fluid.png", format: .png,
            pixelWidth: 2, pixelHeight: 2, byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes))
        document.imageAssets.append(asset)
        let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == fixture.frame })
        document.pages[0].nodes[index].properties += [
            .init(key: .init(rawValue: CanonicalImageFill.assetKey), value: .string(asset.id.description)),
            .init(key: .init(rawValue: CanonicalImageFill.modeKey), value: .string("fill"))]
        let descriptor = ProjectResourceDescriptor(id: asset.resourceID, filename: asset.originalFilename,
            mediaType: "image/png", byteCount: bytes.count, sha256: asset.contentHash)
        let before = try DocumentSerializer.encode(document)
        let compilation = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
            resourceDescriptors: [asset.resourceID: descriptor], resourceData: [asset.resourceID: bytes])
        XCTAssertEqual(try XCTUnwrap(compilation.plan).binaryFiles.first?.contents, bytes)
        let missing = connectedFluidCompilation(document)
        XCTAssertNil(missing.plan)
        XCTAssertTrue(missing.findings.contains { $0.code == "asset-missing" && $0.affectedNodeID == fixture.frame })
        let corrupt = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
            resourceDescriptors: [asset.resourceID: descriptor], resourceData: [asset.resourceID: Data([0])])
        XCTAssertNil(corrupt.plan); XCTAssertTrue(corrupt.findings.contains { $0.severity == .error })
        XCTAssertEqual(try DocumentSerializer.encode(document), before)
    }

    func testConnectedFluidBrowserExportSnapshotStaleCancelAndDestinationSafety() async throws {
        let fixture = try connectedFluidFixture(), owned = try ApplicationOwnedTestFixture.create("fluid-browser-export")
        defer { try? owned.cleanup() }
        let controller = BrowserPreviewController { _ in .opened }
        let document = fixture.document
        let stale = controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: document), isCurrent: { _, _ in false })
        await stale.value
        XCTAssertNil(controller.plan)
        let build = controller.build(document: document, pageID: document.pages[0].id,
            package: .init(document: document), isCurrent: { _, _ in true })
        await build.value
        let plan = try XCTUnwrap(controller.plan)
        XCTAssertEqual(plan.files, connectedFluidCompilation(document).plan?.files)
        let destination = owned.url.appendingPathComponent("website")
        let export = try XCTUnwrap(controller.export(to: destination)); await export.value
        let http = try WebsitePreviewHTTPContent(plan: plan)
        for file in plan.files {
            let bytes = try Data(contentsOf: destination.appendingPathComponent(file.path))
            XCTAssertEqual(bytes, Data(file.contents.utf8)); XCTAssertEqual(http.files[file.path], bytes)
        }
        let cancelledDestination = owned.url.appendingPathComponent("cancelled-output")
        let cancelled = try XCTUnwrap(controller.export(to: cancelledDestination))
        controller.stop(); await cancelled.value
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelledDestination.path))
        XCTAssertEqual(controller.status, "Website preview stopped.")
        let oldFile = try Data(contentsOf: destination.appendingPathComponent("index.html"))
        XCTAssertThrowsError(try LocalStaticBuildWriter.write(plan, to: destination, expectedRevision: plan.revision + 1))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("index.html")), oldFile)
    }

    // SF-LOCAL-BUILDER-010 / SF-0303/0304/0308/0806. SOURCE ONLY, UNRUN.
    private struct ChromeReuseFixture {
        var document: CanonicalDocument
        let source: PageID, targets: [PageID], header: NodeID, footer: NodeID
    }
    private func chromeReuseFixture() throws -> ChromeReuseFixture {
        let (session, header, bodies, footer) = try connectedPageSession()
        var document = session.document
        let source = document.pages[0]
        var targets: [PageID] = []
        for index in 0..<2 {
            var page = DocumentPage.minimum(name: "Chrome destination \(index)", route: "/chrome-\(index)", role: .standard, provenance: .authored)
            let closure = try PageChromeCopyRegistry.subtree([bodies[0]], page: source)
            let clone = try CanonicalPageGraphClone.prepare(page: source, included: closure, destinationPageID: page.id,
                destinationParent: page.rootNodeIDs[0], preservePageLinks: true)
            page.nodes[0].childIDs = [try XCTUnwrap(clone.nodeIDs[bodies[0]])]
            page.nodes += clone.nodes
            document.pages.append(page); targets.append(page.id)
        }
        try document.validate()
        return .init(document: document, source: source.id, targets: targets, header: header, footer: footer)
    }
    private func chromeReuseRequest(_ fixture: ChromeReuseFixture, document: CanonicalDocument? = nil,
                                    roles: Set<PageFlowRole> = [.header, .footer], targets: [PageID]? = nil) throws -> PageChromeCopyRequest {
        let document = document ?? fixture.document
        let page = try XCTUnwrap(document.pages.first { $0.id == fixture.source })
        return .init(documentID: document.id, revision: document.revision, sourcePageID: page.id,
            sourceRoles: PageChromeCopyRegistry.sourceRoles(page), roles: roles, targetPageIDs: targets ?? fixture.targets)
    }

    func testPageChromeReuseHeaderFooterBothMissingRoleAndEmptyTargets() throws {
        let fixture = try chromeReuseFixture(), registry = PageChromeCopyRegistry()
        let choices: [Set<PageFlowRole>] = [[.header], [.footer], [.header, .footer]]
        for roles in choices {
            let session = DocumentSession(document: fixture.document)
            let request = try chromeReuseRequest(fixture, roles: roles, targets: [fixture.targets[0]])
            let prepared = try registry.prepare(request, document: session.document)
            try session.execute(prepared.command)
            let page = try XCTUnwrap(session.document.pages.first { $0.id == fixture.targets[0] })
            XCTAssertEqual(Set(PageChromeCopyRegistry.sourceRoles(page).keys), roles)
            XCTAssertEqual(prepared.copiedRoleCount, roles.count)
            XCTAssertEqual(session.document.pages.first { $0.id == fixture.source }, fixture.document.pages.first { $0.id == fixture.source })
        }
        XCTAssertThrowsError(try registry.prepare(chromeReuseRequest(fixture, targets: []), document: fixture.document))
        XCTAssertThrowsError(try registry.prepare(chromeReuseRequest(fixture, roles: []), document: fixture.document))
        let removed = DocumentSession(document: fixture.document)
        try removed.execute(.batch(removeConnectedFixtureSubtree(fixture.footer, pageID: fixture.source, document: removed.document)))
        XCTAssertThrowsError(try registry.prepare(chromeReuseRequest(fixture, document: removed.document, roles: [.footer]), document: removed.document)) {
            XCTAssertEqual($0 as? PageChromeCopyError, .missingSource)
        }
    }

    func testPageChromeReuseSkipsExistingProtectedAndComponentPagesWithoutReplacement() throws {
        var fixture = try chromeReuseFixture()
        let definition = DocumentPage.minimum(name: "Definition", route: "", role: .componentDefinition, provenance: .authored)
        fixture.document.pages.append(definition)
        let session = DocumentSession(document: fixture.document), registry = PageChromeCopyRegistry()
        try session.execute(registry.prepare(chromeReuseRequest(fixture, roles: [.header], targets: [fixture.targets[0]]), document: session.document).command)
        let existingPage = try XCTUnwrap(session.document.pages.first { $0.id == fixture.targets[0] })
        let existingHeader = try XCTUnwrap(PageChromeCopyRegistry.sourceRoles(existingPage)[.header])
        let existingSubtree = try PageChromeCopyRegistry.subtree([existingHeader], page: existingPage)
        let referringPage = try XCTUnwrap(session.document.pages.first { $0.id == fixture.targets[1] })
        let referringRoot = try XCTUnwrap(referringPage.nodes.first { $0.id == referringPage.rootNodeIDs[0] })
        let inbound = DocumentNode(kind: .link, name: "Inbound section reference", parent: .node(referringRoot.id),
            properties: CanonicalLinkTarget.section(pageID: existingPage.id, nodeID: existingHeader).properties.map {
                .init(key: .init(rawValue: $0.0), value: $0.1)
            })
        try session.execute(.insertNode(.init(pageID: referringPage.id, node: inbound, index: referringRoot.childIDs.count)))
        let notFound = try XCTUnwrap(session.document.pages.first { $0.role == .notFound }?.id)
        let targets = fixture.targets + [fixture.source, notFound, definition.id]
        let prepared = try registry.prepare(chromeReuseRequest(fixture, document: session.document, targets: targets), document: session.document)
        XCTAssertEqual(prepared.copiedRoleCount, 3)
        XCTAssertEqual(prepared.skipped.count, 7)
        try session.execute(prepared.command)
        let after = try XCTUnwrap(session.document.pages.first { $0.id == existingPage.id })
        XCTAssertEqual(after.nodes.filter { existingSubtree.contains($0.id) }, existingPage.nodes.filter { existingSubtree.contains($0.id) })
        XCTAssertEqual(PageChromeCopyRegistry.sourceRoles(after)[.header], existingHeader)
        XCTAssertEqual(session.document.pages.first { $0.id == referringPage.id }?.nodes.first { $0.id == inbound.id }, inbound)
        XCTAssertThrowsError(try registry.prepare(chromeReuseRequest(fixture, document: session.document), document: session.document)) {
            XCTAssertEqual($0 as? PageChromeCopyError, .noChanges)
        }
    }

    func testPageChromeReuseClonesFreshOwnedIDsAndPreservesConnectedBodyAndRoutes() throws {
        var fixture = try chromeReuseFixture()
        let headerIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.header })
        fixture.document.pages[0].nodes[headerIndex].properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalFillLayerCodec.namespaceRoot) || FormattingFamily.retiredFillKeys.contains($0.key.rawValue) }
        let layer = CanonicalFillLayer.linearGradient(angleDegrees: 45, stops: [
            .init(id: .init(), position: 0, color: .init(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
            .init(id: .init(), position: 1, color: .init(red: 0.6, green: 0.4, blue: 0.2, alpha: 1))])
        fixture.document.pages[0].nodes[headerIndex].properties += CanonicalFillLayerCodec.propertyValues(for: [layer]).map { .init(key: .init(rawValue: $0.key), value: $0.value) }
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        let prepared = try PageChromeCopyRegistry().prepare(chromeReuseRequest(fixture), document: session.document)
        try session.execute(prepared.command)
        let oldIDs = Set(fixture.document.pages.flatMap(\.nodes).map(\.id))
        let oldProperties = Set(fixture.document.pages.flatMap(\.nodes).flatMap(\.properties).map(\.id))
        for targetID in fixture.targets {
            let before = try XCTUnwrap(fixture.document.pages.first { $0.id == targetID })
            let after = try XCTUnwrap(session.document.pages.first { $0.id == targetID })
            XCTAssertEqual(after.id, before.id); XCTAssertEqual(after.route, before.route)
            let added = after.nodes.filter { !oldIDs.contains($0.id) }
            XCTAssertTrue(Set(added.flatMap(\.properties).map(\.id)).isDisjoint(with: oldProperties))
            for old in before.nodes where !before.rootNodeIDs.contains(old.id) { XCTAssertEqual(after.nodes.first { $0.id == old.id }, old) }
            let root = try XCTUnwrap(after.nodes.first { $0.id == after.rootNodeIDs[0] })
            let header = try XCTUnwrap(after.nodes.first { $0.id == root.childIDs.first })
            XCTAssertEqual(CanonicalPageFlow.role(header), .header)
            XCTAssertEqual(root.childIDs.dropFirst().dropLast(), before.nodes[0].childIDs[...])
            XCTAssertEqual(after.nodes.first { $0.id == root.childIDs.last }.flatMap(CanonicalPageFlow.role), .footer)
            let copiedLayer = try XCTUnwrap(CanonicalFillLayerCodec.layers(for: header)?.first)
            XCTAssertNotEqual(copiedLayer.id, layer.id)
            XCTAssertTrue(Set(copiedLayer.stops.map(\.id)).isDisjoint(with: Set(layer.stops.map(\.id))))
            XCTAssertEqual(copiedLayer.angleDegrees, layer.angleDegrees)
        }
        let duplicated = try PageCommandRegistry().prepare(.duplicate,
            identity: .init(documentID: session.document.id, revision: session.document.revision, pageID: fixture.source),
            in: session.document, isAvailable: true)
        try session.execute(duplicated.command)
        let copiedPage = try XCTUnwrap(session.document.pages.first { $0.id == duplicated.selectedPageID })
        let copiedHeader = try XCTUnwrap(copiedPage.nodes.first { CanonicalPageFlow.role($0) == .header })
        let copiedLayer = try XCTUnwrap(CanonicalFillLayerCodec.layers(for: copiedHeader)?.first)
        XCTAssertNotEqual(copiedLayer.id, layer.id)
        XCTAssertEqual(copiedLayer.stops.map(\.color), layer.stops.map(\.color))
        XCTAssertEqual(copiedLayer.angleDegrees, layer.angleDegrees)
    }

    func testPageChromeReuseInternalAndExternalSectionDestinationsRemainTruthful() throws {
        let (session, header, bodies, footer) = try connectedPageSession()
        let source = session.document.pages[0], content = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: source.nodes.first { $0.id == header }!))
        var links: [NodeID] = []
        for target in [header, bodies[0]] {
            let link = try insertConnectedChild(.link, parent: content, size: .init(width: 120, height: 32), session: session)
            let node = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == link })
            let values: [(String, PropertyValue)] = [("kind", .string("section")), ("pageID", .string(source.id.description)), ("nodeID", .string(target.description))]
            try session.execute(.batch(values.map { suffix, value in
                let key = CanonicalLinkTarget.namespace + suffix
                return .setProperty(.init(pageID: source.id, nodeID: link, property: .init(id: node.insertionProperty(key)?.id ?? PropertyID(), key: .init(rawValue: key), value: value)))
            }))
            links.append(link)
        }
        let target = DocumentPage.minimum(name: "Destination", route: "/destination", role: .standard, provenance: .authored)
        try session.execute(.insertPage(.init(page: target, index: session.document.pages.count)))
        let fixture = ChromeReuseFixture(document: session.document, source: source.id, targets: [target.id], header: header, footer: footer)
        let prepared = try PageChromeCopyRegistry().prepare(chromeReuseRequest(fixture, roles: [.header]), document: session.document)
        try session.execute(prepared.command)
        let copied = try XCTUnwrap(session.document.pages.first { $0.id == target.id })
        let newHeader = try XCTUnwrap(PageChromeCopyRegistry.sourceRoles(copied)[.header])
        let sectionLinks = copied.nodes.filter { $0.insertionStringProperty(CanonicalLinkTarget.namespace + "kind") == "section" }
        XCTAssertEqual(sectionLinks.count, 2)
        XCTAssertTrue(sectionLinks.contains { $0.insertionStringProperty(CanonicalLinkTarget.namespace + "nodeID") == newHeader.description && $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == target.id.description })
        XCTAssertTrue(sectionLinks.contains { $0.insertionStringProperty(CanonicalLinkTarget.namespace + "nodeID") == bodies[0].description && $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == source.id.description })
        let navigation = copied.nodes.filter(CanonicalPageFlow.isNavigationLink)
        XCTAssertTrue(navigation.contains { $0.insertionStringProperty(CanonicalLinkTarget.namespace + "pageID") == source.id.description })
        XCTAssertTrue(Set(links).isDisjoint(with: Set(sectionLinks.map(\.id))))
    }

    func testPageChromeReuseAtomicUndoRedoCancellationBranchAndRepeatNoOp() throws {
        let fixture = try chromeReuseFixture(), session = DocumentSession(document: fixture.document)
        let prepared = try PageChromeCopyRegistry().prepare(chromeReuseRequest(fixture), document: session.document)
        XCTAssertThrowsError(try session.execute(prepared.command, cancellation: .init(isCancelled: { true })))
        XCTAssertEqual(session.document, fixture.document); XCTAssertTrue(session.historySnapshot().undoEntries.isEmpty)
        try session.execute(prepared.command)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        let after = session.document.pages
        XCTAssertThrowsError(try PageChromeCopyRegistry().prepare(chromeReuseRequest(fixture, document: session.document), document: session.document))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertEqual(session.document.pages, fixture.document.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, after)
        try session.undo()
        try session.execute(.renamePage(.init(pageID: fixture.targets[0], name: "Independent branch")))
        XCTAssertFalse(session.canRedo)
    }

    func testPageChromeReuseRejectsStaleDeletedRoleInvalidTargetAndCancelWithoutPartialWrites() throws {
        let fixture = try chromeReuseFixture(), registry = PageChromeCopyRegistry()
        let request = try chromeReuseRequest(fixture)
        let session = DocumentSession(document: fixture.document)
        try session.execute(.renamePage(.init(pageID: fixture.targets[0], name: "Changed while sheet open")))
        let before = session.document
        XCTAssertThrowsError(try registry.prepare(request, document: session.document)) { XCTAssertEqual($0 as? PageChromeCopyError, .stale) }
        XCTAssertThrowsError(try registry.prepare(chromeReuseRequest(fixture, document: before, targets: [fixture.targets[0], PageID()]), document: before))
        XCTAssertThrowsError(try registry.prepare(chromeReuseRequest(fixture, document: before, targets: [fixture.targets[0], fixture.targets[0]]), document: before))
        XCTAssertThrowsError(try registry.prepare(chromeReuseRequest(fixture, document: before), document: before, cancelled: true))
        XCTAssertEqual(session.document, before)
        try session.execute(.batch(removeConnectedFixtureSubtree(fixture.header, pageID: fixture.source, document: session.document)))
        XCTAssertThrowsError(try registry.prepare(request, document: session.document))
        XCTAssertEqual(session.document.pages.first { $0.id == fixture.targets[0] }?.nodes.count, before.pages.first { $0.id == fixture.targets[0] }?.nodes.count)
    }

    func testPageChromeReuseIndependentTargetEditDoesNotPropagateOrChangeSource() throws {
        let fixture = try chromeReuseFixture(), session = DocumentSession(document: fixture.document)
        let prepared = try PageChromeCopyRegistry().prepare(chromeReuseRequest(fixture), document: session.document)
        try session.execute(prepared.command)
        let page = try XCTUnwrap(session.document.pages.first { $0.id == fixture.targets[0] })
        let owner = try XCTUnwrap(page.nodes.first { CanonicalPageFlow.role($0) == .header })
        let title = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.titleKey, on: owner))
        let old = try XCTUnwrap(page.nodes.first { $0.id == title }?.insertionProperty("content.text"))
        let sourceBefore = session.document.pages.first { $0.id == fixture.source }
        let otherBefore = session.document.pages.first { $0.id == fixture.targets[1] }
        try session.execute(.setProperty(.init(pageID: page.id, nodeID: title,
            property: .init(id: old.id, key: old.key, value: .string("Independent title"), origin: .authored))))
        XCTAssertEqual(session.document.pages.first { $0.id == fixture.source }, sourceBefore)
        XCTAssertEqual(session.document.pages.first { $0.id == fixture.targets[1] }, otherBefore)
        XCTAssertEqual(session.document.pages.first { $0.id == page.id }?.nodes.first { $0.id == title }?.insertionStringProperty("content.text"), "Independent title")
    }

    func testPageChromeReusePackageRecoveryAndOrdinaryHistoryRoundTrip() async throws {
        let fixture = try chromeReuseFixture(), session = DocumentSession(document: fixture.document)
        try session.execute(PageChromeCopyRegistry().prepare(chromeReuseRequest(fixture), document: session.document).command)
        let store = ProjectPackageStore(), historyStore = PersistedHistoryStore()
        let package = try await historyStore.package(ProjectPackage(document: session.document), with: session.historySnapshot())
        let encoded = try await store.encode(package), reopened = try await store.decode(encoded)
        XCTAssertEqual(reopened.document, session.document)
        let owned = try ApplicationOwnedTestFixture.create("chrome-reuse-recovery")
        defer { try? owned.cleanup() }
        let directory = owned.url.appendingPathComponent("recovery", isDirectory: true)
        try await store.prepareRecoveryDirectory(directory)
        let url = DocumentLifecycleBackend.recoveryURL(for: package.projectID, in: directory)
        try await store.write(package, to: url, policy: .recovery(package.projectID))
        let recovered = try await store.readOwnedRecoverySnapshot(from: url, expectedProjectID: package.projectID).package
        XCTAssertEqual(recovered, package)
        let restored = DocumentSession(document: reopened.document)
        guard case .restored(let history) = try await historyStore.load(from: reopened) else {
            return XCTFail("Ordinary copied chrome must retain exact validated history")
        }
        try restored.installValidatedHistory(history)
        try restored.undo(); XCTAssertEqual(restored.document.pages, fixture.document.pages)
        try restored.redo(); XCTAssertEqual(restored.document.pages, session.document.pages)
    }

    func testPageChromeReuseResourceTokenComponentIdentityAndMissingDependencyRejection() async throws {
        var fixture = try chromeReuseFixture()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        for y in 0..<2 { for x in 0..<2 { bitmap.setColor(.purple, atX: x, y: y) } }
        let bytes = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Chrome image", originalFilename: "chrome.png",
            format: .png, pixelWidth: 2, pixelHeight: 2, byteCount: bytes.count, contentHash: ProjectResourceStore.digest(bytes))
        let token = LocalColorToken(name: "Chrome color", color: .init(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
        fixture.document.imageAssets = [asset]; fixture.document.colorTokens = [token]
        let index = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.header })
        fixture.document.pages[0].nodes[index].properties += [
            .init(key: .init(rawValue: CanonicalImageFill.assetKey), value: .string(asset.id.description)),
            .init(key: .init(rawValue: CanonicalImageFill.modeKey), value: .string("fill")),
            .init(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)), value: .string(token.id.description))]
        let definition = DocumentPage.minimum(name: "Chrome component", route: "", role: .componentDefinition, provenance: .authored)
        fixture.document.pages.append(definition)
        let content = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.contentKey, on: fixture.document.pages[0].nodes[index]))
        let instance = DocumentNode(kind: .component, name: "Logo instance", parent: .node(content), properties: [
            .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(definition.id.description))]
            + [("layout.x", 0.0), ("layout.y", 0), ("layout.width", 64), ("layout.height", 32)].map { .init(key: .init(rawValue: $0.0), value: .number($0.1)) })
        fixture.document.pages[0].nodes.append(instance)
        let contentIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == content })
        fixture.document.pages[0].nodes[contentIndex].childIDs.append(instance.id)
        try fixture.document.validate()
        let descriptor = ProjectResourceDescriptor(id: asset.resourceID, filename: asset.originalFilename, mediaType: "image/png", byteCount: bytes.count, sha256: asset.contentHash)
        let package = try ProjectPackage(document: fixture.document).withResource(descriptor, data: bytes)
        let request = try chromeReuseRequest(fixture), worker = PageChromeCopyWorker()
        let prepared = try await worker.prepare(request, document: fixture.document, package: package)
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared.command)
        XCTAssertEqual(session.document.imageAssets, fixture.document.imageAssets)
        XCTAssertEqual(session.document.colorTokens, fixture.document.colorTokens)
        XCTAssertEqual(session.document.componentDefinitions, fixture.document.componentDefinitions)
        XCTAssertEqual(try package.resourceData(for: descriptor), bytes)
        for target in fixture.targets {
            let page = try XCTUnwrap(session.document.pages.first { $0.id == target })
            let header = try XCTUnwrap(page.nodes.first { CanonicalPageFlow.role($0) == .header })
            XCTAssertEqual(CanonicalImageFill.resolve(header)?.assetID, asset.id)
            XCTAssertEqual(LocalColorTokenBinding.id(for: header, target: .fill), token.id)
            XCTAssertTrue(page.nodes.contains { CanonicalComponentReference.definitionID(for: $0) == definition.id && $0.id != instance.id })
        }
        do {
            _ = try await worker.prepare(request, document: fixture.document, package: ProjectPackage(document: fixture.document))
            XCTFail("Missing original bytes must reject before mutation")
        } catch { XCTAssertEqual(error as? PageChromeCopyError, .dependency) }
        var missing = fixture.document; missing.colorTokens = []
        XCTAssertThrowsError(try PageChromeCopyRegistry().prepare(request, document: missing, availableImageIDs: [asset.id]))
        missing = fixture.document; missing.pages.removeAll { $0.id == definition.id }
        XCTAssertThrowsError(try PageChromeCopyRegistry().prepare(request, document: missing, availableImageIDs: [asset.id]))
        XCTAssertFalse(PageChromeCopyError.dependency.localizedDescription.contains(asset.originalFilename))
    }

    func testPageChromeReuseSheetSelectionRaceAndPreparationCancellationAreNeutral() async throws {
        let fixture = try chromeReuseFixture(), session = DocumentSession(document: fixture.document)
        let state = WorkspaceShellState(documentSession: session)
        state.resizeViewport(to: .init(width: 1100, height: 700), pixelRatio: 2)
        let deadline = ContinuousClock.now + .seconds(3)
        while state.formattingActionCapture == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(state.canCopyPageChrome)
        state.presentPageChromeCopy()
        let sheet = try XCTUnwrap(state.pageChromeCopySheet)
        state.selectLayer(fixture.header)
        state.preparePageChromeCopy(sheet: sheet, roles: [.header, .footer], targets: fixture.targets)
        XCTAssertTrue(state.pageChromeCopyStatus.contains("changed"))
        XCTAssertEqual(session.document, fixture.document)
        state.pageChromeCopySheet = nil
        state.presentPageChromeCopy()
        let current = try XCTUnwrap(state.pageChromeCopySheet)
        state.preparePageChromeCopy(sheet: current, roles: [.header, .footer], targets: fixture.targets)
        XCTAssertTrue(state.isPreparingPageChromeCopy)
        state.cancelPageChromeCopyPreparation()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertFalse(state.isPreparingPageChromeCopy)
        XCTAssertEqual(session.document, fixture.document); XCTAssertTrue(session.historySnapshot().undoEntries.isEmpty)
        XCTAssertEqual(state.lastPageChromeCopyDiagnostic?.failureCategory, "cancelled")
        XCTAssertFalse(String(describing: state.lastPageChromeCopyDiagnostic).contains(fixture.source.description))
    }

    func testPageChromeReuseResponsiveSharedLayoutRendererAndCompilerGraph() async throws {
        var fixture = try chromeReuseFixture()
        let headerIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.header })
        fixture.document.pages[0].nodes[headerIndex].properties.append(.init(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.height, breakpoint: .mobile)), value: .number(200)))
        let navigation = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: fixture.document.pages[0].nodes[headerIndex]))
        let navigationIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == navigation })
        let fluid = CanonicalFluidValue(minimum: 8, preferred: 16, maximum: 24)
        fixture.document.pages[0].nodes[navigationIndex].properties.append(.init(key: .init(rawValue: CanonicalFluidValueCodec.key(.gap)),
            value: .string(try CanonicalFluidValueCodec.encode(fluid, target: .gap))))
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        try session.execute(PageChromeCopyRegistry().prepare(chromeReuseRequest(fixture), document: session.document).command)
        let page = try XCTUnwrap(session.document.pages.first { $0.id == fixture.targets[0] })
        let roles = PageChromeCopyRegistry.sourceRoles(page)
        for width in [390.0, 520, 768, 1100, 1440] {
            let snapshot = ConnectedPageLayoutSnapshot(page: page, breakpoint: .resolving(width: width), width: width)
            for role in PageChromeCopyRegistry.roles {
                let id = try XCTUnwrap(roles[role]), frame = try XCTUnwrap(snapshot.frames[id])
                XCTAssertEqual(frame.size.width, width, accuracy: 0.001)
                XCTAssertEqual(frame.origin.x, 0, accuracy: 0.001)
                if role == .header && width < 600 { XCTAssertEqual(frame.size.height, 200, accuracy: 0.001) }
            }
            let viewport = try CanvasViewportState()
            let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: session.document, activePageID: page.id,
                activeContainerID: nil, viewport: viewport, surfaceID: .init(), breakpoint: .resolving(width: width), viewportWidth: width))
            for id in roles.values {
                let object = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == id })
                XCTAssertEqual(object.frame, snapshot.frames[id]?.frame)
            }
        }
        let copiedHeader = try XCTUnwrap(page.nodes.first { $0.id == roles[.header] })
        let copiedNavigation = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.navigationKey, on: copiedHeader))
        let navigationNode = try XCTUnwrap(page.nodes.first { $0.id == copiedNavigation })
        let copiedFluid = try XCTUnwrap(CanonicalFluidValueCodec.value(for: .gap, node: navigationNode)?.0)
        XCTAssertNotEqual(copiedFluid.id, fluid.id)
        XCTAssertEqual(copiedFluid.minimum, fluid.minimum); XCTAssertEqual(copiedFluid.maximum, fluid.maximum)
        let output = StaticBuildCompiler.compile(document: session.document, profileSelection: .init(profile: .development), resourceDescriptors: [:], resourceData: [:])
        let plan = try XCTUnwrap(output.plan)
        XCTAssertTrue(plan.files.contains { $0.path.hasSuffix(".html") && $0.contents.contains("<header") && $0.contents.contains("<footer") })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

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
        XCTAssertEqual(state.containerLayoutResponsiveSource(for: .padding), "Smooth scaling")
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
        XCTAssertEqual(state.containerLayoutResponsiveSource(for: .padding), "Set here · Tablet")
        XCTAssertTrue(state.commitContainerLayout(field: .padding, value: nil, provenance: .keyboard,
            draftScope: state.layoutInspectorDraftScope))
        await adopt()
        XCTAssertEqual(session.document.pages, baseline)
        XCTAssertEqual(state.containerLayoutResponsiveSource(for: .padding), "Smooth scaling")
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
        XCTAssertTrue(state.fluidValueEffectiveSummary(for: .fontSize).contains("Smooth scaling"))
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
        XCTAssertTrue(state.sizingModeSource(for: .width).contains("Fill available space"))
        let desktopScope = state.layoutInspectorDraftScope
        state.reviewBreakpoint(.mobile)
        await waitForAdoption()
        XCTAssertTrue(state.sizingModeSource(for: .width).contains("Exact size"))
        XCTAssertTrue(state.sizingModeSource(for: .width).contains("Mobile"))
        let before = session.document
        XCTAssertFalse(state.commitGeometryInspectorValue(999, field: .width, provenance: .keyboard, draftScope: desktopScope))
        XCTAssertFalse(state.commitSizingConstraint(.setMode(.width, .fixed), draftScope: desktopScope))
        XCTAssertEqual(session.document, before)
        XCTAssertTrue(state.resetSizingDimensionOverride(.width, expectedScope: state.layoutInspectorDraftScope))
        await waitForAdoption()
        XCTAssertTrue(state.sizingModeSource(for: .width).contains("Fill available space"))
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
                $0.hasPrefix(CanonicalCSSRule.selector(for: contentID) + " {") && $0.contains("box-sizing:border-box")
            }
            XCTAssertEqual(contentRules.count, ResponsiveBreakpoint.allCases.count)
            XCTAssertTrue(contentRules.allSatisfy { $0.contains("width:max(1px,calc(100% - ") },
                          "Managed chrome content must fill the same padded owner width as native layout")
            XCTAssertEqual(CanonicalPageChrome.navigationAlignment(surface: navigation, settings: owner), "end")
            for breakpoint in ResponsiveBreakpoint.allCases {
                let snapshot = try XCTUnwrap(CanonicalPageFlow.navigation(owner: owner, page: page,
                    document: document, breakpoint: breakpoint))
                XCTAssertEqual(snapshot.alignment, "end")
            }
            let selector = CanonicalCSSRule.selector(for: navigationID)
            let navigationRules = css.components(separatedBy: "\n").filter {
                $0.hasPrefix(selector + " {") && $0.contains("box-sizing:border-box")
            }
            XCTAssertEqual(navigationRules.count, ResponsiveBreakpoint.allCases.count)
            XCTAssertTrue(navigationRules.allSatisfy { $0.contains("width:auto;") && $0.contains("flex:1 1 0px;") })
            let mobile = try XCTUnwrap(CanonicalPageChrome.automaticMenuRow(owner: owner, page: page,
                breakpoint: .mobile, width: nil, availablePageIDs: Set(document.websitePages.map(\.id))))
            XCTAssertTrue(mobile.reservesMenu)
            XCTAssertEqual(mobile.navigationMinimum, 90)
            let mobileRules = ConnectedPageOutput.automaticMenuRules(page, usesWrapper: false,
                availablePageIDs: Set(document.websitePages.map(\.id))).joined(separator: "\n")
            XCTAssertTrue(mobileRules.contains(selector + " { position:relative;left:auto;top:auto;width:90.0px;flex:1 0 90.0px;min-width:90.0px;max-width:none; }"),
                          "The narrow override must reserve the real Menu before distributing the remaining row")
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

    private func connectedPageSession(includeAbout: Bool = false) throws -> (DocumentSession, NodeID, [NodeID], NodeID) {
        var fixture = makeFixture()
        if includeAbout {
            var document = fixture.document
            document.pages.append(DocumentPage.minimum(name: "About", route: "/about", role: .standard, provenance: .authored))
            fixture = fixture.with(document: document)
        }
        let session = DocumentSession(document: fixture.document)
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

    // SF-0806-006, SF-1203-003/006, SF-1211-004: retain a small actual
    // compiler artifact for independent browser diagnosis, not a second emitter.
    func testMinimalManagedMenuCompilerReproductionPreservesRuntimeAndDocument() throws {
        let (session, header, _, _) = try connectedPageSession()
        let original = session.document
        var document = original
        let root = try XCTUnwrap(document.pages[0].nodes.first)
        var retained: Set<NodeID> = [root.id, header]
        var pending = [header]
        while let id = pending.popLast() {
            let node = try XCTUnwrap(document.pages[0].nodes.first { $0.id == id })
            for child in node.childIDs where retained.insert(child).inserted { pending.append(child) }
        }
        document.pages[0].nodes.removeAll { !retained.contains($0.id) }
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root.id })
        document.pages[0].nodes[rootIndex].childIDs = [header]
        let before = try DocumentSerializer.encode(document)
        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertEqual(html.components(separatedBy: "<details ").count - 1, 1)
        XCTAssertTrue(html.contains("<header"))
        XCTAssertFalse(html.contains("<footer"))
        XCTAssertEqual(plan.files.first { $0.path == "siteforge-navigation.js" }?.contents, ConnectedPageOutput.menuScript)
        XCTAssertEqual(try DocumentSerializer.encode(document), before)
        XCTAssertEqual(session.document, original)
        let artifact = FileManager.default.temporaryDirectory.appendingPathComponent("SiteForgeMenuReproduction-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: false)
        for file in plan.files {
            let target = artifact.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: target, options: .atomic)
        }
        let receipt = XCTAttachment(string: artifact.path)
        receipt.name = "SF-MENU private compiler reproduction location"; receipt.lifetime = .keepAlways; add(receipt)
        print("SF_MENU_REPRODUCTION " + artifact.path)
    }

    // SF-0806-006, SF-1203-003/006, SF-1211-004: real shared output
    // retains both chrome roles and real destination routes for browser proof.
    func testManagedHeaderFooterMenuReproductionUsesRealRoutesAndUnchangedRuntime() throws {
        let (session, _, _, _) = try connectedPageSession(includeAbout: true)
        let before = try DocumentSerializer.encode(session.document)
        let plan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertEqual(html.components(separatedBy: "<details ").count - 1, 2)
        XCTAssertTrue(html.contains("Header navigation menu")); XCTAssertTrue(html.contains("Footer navigation menu"))
        XCTAssertTrue(html.contains("href=\"about.html\""))
        XCTAssertTrue(plan.files.contains { $0.path == "about.html" })
        XCTAssertEqual(plan.files.first { $0.path == "siteforge-navigation.js" }?.contents, ConnectedPageOutput.menuScript)
        XCTAssertEqual(try DocumentSerializer.encode(session.document), before)
        let artifact = FileManager.default.temporaryDirectory.appendingPathComponent("SiteForgeMenuOverlay-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: false)
        for file in plan.files {
            let target = artifact.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(file.contents.utf8).write(to: target, options: .atomic)
        }
        let receipt = XCTAttachment(string: artifact.path)
        receipt.name = "SF-MENU private Header Footer output location"; receipt.lifetime = .keepAlways; add(receipt)
        print("SF_MENU_OVERLAY " + artifact.path)
    }

    // SF-0806-006, SF-1203-003/006, SF-1211-004: shared output uses
    // intrinsic details content for both roles, without mutating authored data.
    func testManagedMenuOverlayUsesIntrinsicContentAndCanonicalAlignment() throws {
        let (session, _, _, _) = try connectedPageSession(includeAbout: true)
        let before = try DocumentSerializer.encode(session.document)
        let plan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("@supports selector(details::details-content)"))
        XCTAssertTrue(css.contains("grid-template-rows:1lh;height:1lh;"))
        XCTAssertTrue(css.contains("justify-self:var(--sf-menu-panel-alignment,start)"))
        XCTAssertTrue(css.contains(".sf-nav-menu[open] nav { position:static; }"))
        XCTAssertTrue(css.contains("footer .sf-nav-menu[open]::details-content { align-self:end;margin-block-start:0;margin-block-end:1lh; }"))
        XCTAssertTrue(css.contains("--sf-menu-panel-alignment:end;"))
        XCTAssertTrue(css.contains("@supports not selector(details::details-content)"))
        XCTAssertFalse(css.contains("translateZ")); XCTAssertFalse(css.contains("visibility:hidden"))
        XCTAssertEqual(plan.files.first { $0.path == "siteforge-navigation.js" }?.contents, ConnectedPageOutput.menuScript)
        XCTAssertEqual(try DocumentSerializer.encode(session.document), before)
    }

    // SF-0806-006, SF-1203-003/006, SF-1206-003: managed menus and
    // nested routes consume exactly the shared external runtime, not a
    // Preview-only script or differently encoded resource.
    func testManagedNavigationRuntimeReferenceAndHTTPBytesMatchRootAndNestedOutput() throws {
        let (session, _, _, _) = try connectedPageSession()
        for (route, output, prefix) in [("/", "index.html", ""), ("/nested/contact", "nested/contact.html", "../")] {
            var document = session.document
            document.pages[0].route = PageRoute(rawValue: route)
            document.pages[0].role = route == "/" ? .home : .standard
            let before = try DocumentSerializer.encode(document)
            let plan = try MultiPageStaticBuildPlanner.plan(document: document)
            let html = try XCTUnwrap(plan.files.first { $0.path == output }?.contents)
            XCTAssertTrue(html.contains("<script src=\"\(prefix)siteforge-navigation.js\" defer></script>"))
            XCTAssertTrue(html.contains("data-siteforge-navigation"))
            let scripts = plan.files.filter { $0.path == "siteforge-navigation.js" }
            XCTAssertEqual(scripts.count, 1)
            let expected = Data(ConnectedPageOutput.menuScript.utf8)
            XCTAssertEqual(Data(try XCTUnwrap(scripts.first).contents.utf8), expected)
            let http = try WebsitePreviewHTTPContent(plan: plan)
            let response = http.response(to: Data("GET /siteforge-navigation.js HTTP/1.1\r\nHost: 127.0.0.1:4321\r\n\r\n".utf8), port: 4321)
            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(response.type, "text/javascript; charset=utf-8")
            XCTAssertEqual(response.body, expected)
            XCTAssertEqual(plan.revision, document.revision)
            XCTAssertEqual(try DocumentSerializer.encode(document), before)
            let digest = SHA256.hash(data: response.body).map { String(format: "%02x", $0) }.joined()
            let receipt = XCTAttachment(string: "route=\(route);revision=\(document.revision);bytes=\(response.body.count);sha256=\(digest)")
            receipt.name = "SF-NAV shared compiler HTTP bytes"; receipt.lifetime = .keepAlways; add(receipt)
        }
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

    private func removeConnectedFixtureSubtree(_ root: NodeID, pageID: PageID, document: CanonicalDocument) throws -> [DocumentCommand] {
        let page = try XCTUnwrap(document.pages.first { $0.id == pageID })
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        func commands(_ id: NodeID) throws -> [DocumentCommand] {
            let node = try XCTUnwrap(byID[id])
            return try node.childIDs.flatMap { try commands($0) } + [.removeNode(.init(pageID: pageID, nodeID: id))]
        }
        return try commands(root)
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

    // SF-0507-003/004, SF-0604-003, SF-1202-003/004, SF-1204-003/004.
    func testManagedChromeTitleStaticOverflowRetainsSemanticIdentityAndResponsiveHeight() throws {
        let (session, headerID, _, _) = try connectedPageSession()
        let original = session.document
        XCTAssertThrowsError(try pageStructureCommand(.title(headerID, text: "Line\nbreak"),
            document: original, selected: headerID))
        XCTAssertEqual(session.document, original)
        try session.execute(pageStructureCommand(.title(headerID, text: "Long  title keeps <complete> intent"),
            document: session.document, selected: headerID))
        let document = session.document, page = document.pages[0]
        let routes = try Dictionary(uniqueKeysWithValues: document.websitePages.map {
            ($0.id, try MultiPageStaticBuildPlanner.outputPath(for: $0))
        })
        let owner = try XCTUnwrap(page.nodes.first { $0.id == headerID })
        let titleID = try XCTUnwrap(CanonicalPageChrome.reference(CanonicalPageChrome.titleKey, on: owner))
        for width in [1440.0, 430, 320] {
            let breakpoint = ResponsiveBreakpoint.resolving(width: width)
            let tree = try InternalDocumentRenderTreeCompiler.compile(page: page,
                documentID: document.id, revision: document.revision, staticRoutes: routes,
                breakpoint: breakpoint, viewportWidth: width)
            let title = try XCTUnwrap(tree.nodes.first { $0.id == titleID })
            XCTAssertTrue(title.isManagedChromeTitle)
            XCTAssertEqual(title.sourceNodeID, titleID)
            XCTAssertEqual(title.frame, page.resolvedStructuralGeometry(breakpoint: breakpoint, viewportWidth: width,
                availablePageIDs: Set(routes.keys))[titleID]?.frame)
            XCTAssertEqual(title.textContent, "Long  title keeps <complete> intent")
            XCTAssertEqual(CanvasTextLayoutPolicy.visibleLineCapacity(height: title.frame.size.height,
                lineHeight: try XCTUnwrap(title.typography).lineHeight), 1)
            let html = try SafeHTMLEmitter.emit(tree)
            XCTAssertTrue(html.contains("<span data-siteforge-text>Long  title keeps &lt;complete&gt; intent</span>"))
            XCTAssertFalse(html.contains("aria-hidden=\"true\">Long"))
            let css = StaticTypographyOutputEmitter.emit(nodes: tree.nodes)
            XCTAssertTrue(css.contains("-webkit-line-clamp:max(1,round(down,calc(var(--sf-text-height) / 1lh),1))"))
            XCTAssertTrue(css.contains("padding-inline:4.0px"))
            XCTAssertTrue(css.contains("white-space: pre-wrap;"))
            XCTAssertFalse(css.contains("white-space:nowrap"))
        }
        let output = try MultiPageStaticBuildPlanner.plan(document: document)
        let css = try XCTUnwrap(output.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("--sf-text-height:24.0px") || css.contains("--sf-text-height:24px"))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
        XCTAssertEqual(session.document, document)
        try session.execute(pageStructureCommand(.showTitle(headerID, false), document: document, selected: headerID))
        let hiddenCSS = ConnectedPageOutput.css(pages: session.document.pages)
        XCTAssertTrue(hiddenCSS.contains("\(CanonicalCSSRule.selector(for: titleID))[data-siteforge-node] { display:none; }"))
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
