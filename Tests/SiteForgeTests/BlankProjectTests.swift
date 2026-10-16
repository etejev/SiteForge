import XCTest
@testable import SiteForge

@MainActor
final class BlankProjectTests: XCTestCase {
    // SF-0401-004, SF-0203-006: a hidden real object is not a blank document.
    func testCanvasEmptyHintUsesCanonicalPresenceRatherThanRenderAvailability() throws {
        let blank = ProjectCreation.blank()
        let empty = WorkspaceShellState(documentSession: DocumentSession(document: blank))
        XCTAssertTrue(empty.isCurrentPageGenuinelyEmpty)
        var document = blank
        let rootID = document.pages[0].rootNodeIDs[0]
        let id = NodeID()
        document.pages[0].nodes[0].childIDs.append(id)
        document.pages[0].nodes.append(DocumentNode(id: id, kind: .frame, name: "Hidden real element",
            parent: .node(rootID), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(2000)),
                .init(key: .init(rawValue: "layout.y"), value: .number(40)),
                .init(key: .init(rawValue: "layout.width"), value: .number(240)),
                .init(key: .init(rawValue: "layout.height"), value: .number(160)),
                .init(key: .init(rawValue: "hidden"), value: .boolean(true), origin: .authored)
            ]))
        try document.validate()
        let state = WorkspaceShellState(documentSession: DocumentSession(document: document))
        XCTAssertFalse(state.isCurrentPageGenuinelyEmpty)
        XCTAssertEqual(state.documentSession.document, document)
        XCTAssertTrue(state.documentSession.document.pages[0].nodes.contains { $0.id == id })
    }
    // SF-0205-003/004 — recent pages are bounded scene navigation, not
    // canonical query or package history.
    func testQuickOpenRecentPagesDeduplicateBoundAndDiscardMissingIDs() {
        let home = DocumentPage(name: "Home", route: .init(rawValue: "/"), role: .home)
        let missing = DocumentPage(name: "Not Found", route: .init(rawValue: "/404"), role: .notFound)
        let extra = PageID()
        let first = QuickOpenRecentPagePolicy.recording(home.id, in: [])
        let second = QuickOpenRecentPagePolicy.recording(missing.id, in: first)
        XCTAssertEqual(QuickOpenRecentPagePolicy.recording(home.id, in: second), [home.id, missing.id])
        XCTAssertEqual(QuickOpenRecentPagePolicy.recording(extra, in: second, limit: 2), [extra, missing.id])
        XCTAssertEqual(QuickOpenRecentPagePolicy.available([extra, missing.id, home.id], in: [home, missing]).map(\.id), [missing.id, home.id])
        XCTAssertEqual(QuickOpenRecentPagePolicy.recording(extra, in: second, limit: 0), [])
    }

    // SF-0205-002/003/004: page search is a stable, scene-local projection.
    func testPagesSearchMatchesNameAndRouteWithoutChangingDocumentOrSelection() throws {
        let home = DocumentPage(name: "Home", route: .init(rawValue: "/"), role: .home)
        let missing = DocumentPage(name: "Not Found", route: .init(rawValue: "/404"), role: .notFound)
        let accented = DocumentPage(name: "Résumé", route: .init(rawValue: "/resume"))
        let document = CanonicalDocument(pages: [home, missing, accented])
        try document.validate()
        let state = WorkspaceShellState(documentSession: DocumentSession(document: document))
        XCTAssertEqual(state.filteredPages.map(\.id), [home.id, missing.id, accented.id])
        XCTAssertEqual(PageSearchPolicy.results(in: state.pages, query: " RÉSUMÉ ").map(\.id), [accented.id])
        XCTAssertEqual(PageSearchPolicy.results(in: state.pages, query: "/404").map(\.id), [missing.id])
        XCTAssertEqual(PageSearchPolicy.results(in: state.pages, query: "o").map(\.id), [home.id, missing.id])

        state.pageSearchText = "nOt"
        XCTAssertEqual(state.filteredPages.map(\.id), [missing.id])
        XCTAssertEqual(state.pageSearchSummary, "1 of 3 pages match")
        XCTAssertEqual(state.effectiveSelectedPageID, home.id)
        XCTAssertEqual(state.documentSession.document, document)
        state.openFirstMatchingPage()
        XCTAssertEqual(state.effectiveSelectedPageID, missing.id)
        XCTAssertEqual(state.documentSession.document.revision, 0)
        state.pageSearchText = "no match"
        XCTAssertTrue(state.filteredPages.isEmpty)
        state.openFirstMatchingPage()
        XCTAssertEqual(state.effectiveSelectedPageID, missing.id)
        state.clearPageSearch()
        XCTAssertEqual(state.filteredPages.map(\.id), [home.id, missing.id, accented.id])
        XCTAssertEqual(state.documentSession.document, document)
    }

    // SF-0301-001, SF-0303-001, SF-0303-003
    func testApprovedDefaultsHaveExactNamesRoutesRolesOrderAndMinimumRoots() throws {
        let document = ProjectCreation.blank()

        XCTAssertEqual(BlankProjectDefaults.requirementIDs, [
            "SF-0301-001", "SF-0301-002", "SF-0301-005", "SF-0301-006", "SF-0301-008",
            "SF-0303-001", "SF-0303-003", "SF-0303-005", "SF-0303-006", "SF-0303-008",
        ])
        XCTAssertEqual(document.creationKind, .blank)
        XCTAssertNil(document.templateID)
        XCTAssertEqual(document.pages.map(\.name), ["Home", "Not Found"])
        XCTAssertEqual(document.pages.map(\.route.rawValue), ["/", "/404"])
        XCTAssertEqual(document.pages.map(\.role), [.home, .notFound])
        XCTAssertEqual(document.pages.map(\.provenance), [.blankDefault, .blankDefault])
        XCTAssertEqual(document.pages.map(\.rootNodeIDs.count), [1, 1])
        XCTAssertEqual(document.pages.map(\.nodes.count), [1, 1])
        for page in document.pages {
            let root = try XCTUnwrap(page.nodes.first)
            XCTAssertEqual(root.id, page.rootNodeIDs[0])
            XCTAssertEqual(root.kind, .frame)
            XCTAssertEqual(root.name, "Root")
            XCTAssertEqual(root.parent, .page(page.id))
            XCTAssertTrue(root.childIDs.isEmpty)
            XCTAssertTrue(root.properties.isEmpty)
        }
        try document.validate()
    }

    // SF-0301-001, SF-0303-003
    func testEmptyDocumentsDuplicateRoutesAndRemovingLastPageAreRejected() throws {
        XCTAssertThrowsError(try CanonicalDocument(pages: []).validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .emptyPageList)
        }

        let page = DocumentPage(name: "Only", route: PageRoute(rawValue: "/only"))
        var duplicate = CanonicalDocument(pages: [page, DocumentPage(name: "Duplicate", route: page.route)])
        XCTAssertThrowsError(try duplicate.validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .duplicatePageRoute)
        }

        duplicate.pages = [page]
        let session = DocumentSession(document: duplicate)
        XCTAssertThrowsError(try session.execute(.removePage(RemovePageCommand(pageID: page.id))))
        XCTAssertEqual(session.document.pages, [page])
    }

    // SF-0301-005, SF-0303-005
    func testStableTypedIdentifiersAndDeterministicSerializationSurviveReopen() async throws {
        let document = ProjectCreation.blank()
        let pageIDs = document.pages.map(\.id)
        let rootIDs = document.pages.flatMap(\.rootNodeIDs)
        let first = try DocumentSerializer.encode(document)
        let second = try DocumentSerializer.encode(document)
        XCTAssertEqual(first, second)

        let package = ProjectPackage(
            projectID: ProjectID(UUID(uuidString: "90000000-0000-0000-0000-000000000001")!),
            createdAt: ProjectTimestamp("2026-07-19T12:00:00.000Z"),
            document: document
        )
        let store = ProjectPackageStore()
        let packageData = try await store.encode(package)
        let reopened = try await store.decode(packageData)
        XCTAssertEqual(reopened.document.pages.map(\.id), pageIDs)
        XCTAssertEqual(reopened.document.pages.flatMap(\.rootNodeIDs), rootIDs)
        XCTAssertEqual(reopened.document, document)
    }

    // SF-0301-002, SF-0303-001
    func testBlankAndTemplateCreationRemainExplicitlyDistinct() throws {
        let blank = ProjectCreation.blank()
        let templateID = TemplateID()
        let template = ProjectCreation.template(
            templateID: templateID,
            pages: [DocumentPage(name: "Template Landing", route: PageRoute(rawValue: "/"), role: .home)]
        )

        XCTAssertEqual(blank.creationKind, .blank)
        XCTAssertEqual(blank.pages.map(\.provenance), [.blankDefault, .blankDefault])
        XCTAssertEqual(template.creationKind, .template)
        XCTAssertEqual(template.templateID, templateID)
        XCTAssertEqual(template.pages.map(\.provenance), [.template])
        try template.validate()
    }

    // SF-AUTHORING-106 / SF-0204-001/002/003/005 — the approved local
    // starter is deterministic canonical content, not launch-only fixture UI.
    func testStarterSiteHasStableTemplateProvenanceSemanticStructureAndNoNotFoundPage() throws {
        let documentID = DocumentID(UUID(uuidString: "02040000-0000-4000-8000-000000000001")!)
        let first = StarterSiteTemplate.document(id: documentID)
        let second = StarterSiteTemplate.document(id: documentID)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.creationKind, .template)
        XCTAssertEqual(first.templateID, StarterSiteTemplate.id)
        XCTAssertEqual(first.pages.map(\.name), ["Home", "About"])
        XCTAssertEqual(first.pages.map(\.route.rawValue), ["/", "/about"])
        XCTAssertEqual(first.pages.map(\.role), [.home, .standard])
        XCTAssertEqual(first.pages.map(\.provenance), [.template, .template])
        XCTAssertFalse(first.pages.contains { $0.role == .notFound || $0.route.rawValue == "/404" })
        XCTAssertTrue(first.imageAssets.isEmpty)

        for page in first.pages {
            let elements = page.nodes.compactMap { node -> SemanticHTMLElement? in
                CanonicalSemanticElement.resolved(for: node)?.0
            }
            XCTAssertTrue(elements.contains(.header))
            XCTAssertTrue(elements.contains(.main))
            XCTAssertTrue(elements.contains(.footer))
            XCTAssertEqual(page.nodes.filter { $0.kind == .section }.count, 3)
            XCTAssertEqual(page.nodes.filter { $0.kind == .text }.count, 3)
            XCTAssertTrue(page.nodes.filter { $0.kind == .text }.allSatisfy {
                CanonicalTypography.resolved(for: $0)?.family == CanonicalTypography.defaultFamily
                    && $0.insertionStringProperty("content.text")?.isEmpty == false
            })
        }
        XCTAssertEqual(Set(first.pages.flatMap(\.nodes).map(\.id)).count, first.pages.flatMap(\.nodes).count)
        XCTAssertEqual(Set(first.pages.flatMap(\.nodes).flatMap(\.properties).map(\.id)).count,
                       first.pages.flatMap(\.nodes).flatMap(\.properties).count)
        try first.validate()
    }

    // SF-AUTHORING-106 / SF-0204-003/005/007 — each preset resolves every
    // authored starter surface inside its product artboard without changing
    // canonical Desktop geometry.
    func testStarterSiteResponsiveGeometryStaysInEveryProductArtboard() throws {
        let document = StarterSiteTemplate.document()
        try document.validate()
        for page in document.pages {
            for preset in ViewportPreset.allCases {
                let resolved = page.resolvedStructuralGeometry(
                    breakpoint: preset.responsiveBreakpoint,
                    viewportWidth: Double(preset.width)
                )
                for section in page.nodes.filter({ $0.kind == .section }) {
                    let frame = try XCTUnwrap(resolved[section.id])
                    XCTAssertGreaterThanOrEqual(frame.origin.x, 0)
                    XCTAssertGreaterThanOrEqual(frame.origin.y, 0)
                    XCTAssertLessThanOrEqual(frame.origin.x + frame.size.width, Double(preset.width))
                    XCTAssertLessThanOrEqual(frame.origin.y + frame.size.height, 900)
                }
            }
        }
    }

    // SF-AUTHORING-106 / SF-0204-004/005 — lifecycle adoption validates the
    // whole selection before replacement; the accepted template starts as a
    // clean baseline and its ordinary copy uses exact command history.
    func testStarterLifecycleIsAtomicCleanEditableUndoableAndRoundTrips() async throws {
        let controller = DocumentLifecycleController(session: DocumentSession())
        let starter = StarterSiteTemplate.document()
        let creation = await controller.requestNewDocument(starter)
        XCTAssertEqual(creation, .completed)
        XCTAssertEqual(controller.session.document, starter)
        XCTAssertEqual(controller.phase, .clean)
        XCTAssertFalse(controller.session.canUndo)

        let page = try XCTUnwrap(controller.session.document.pages.first)
        let text = try XCTUnwrap(page.nodes.first { $0.kind == .text })
        let old = try XCTUnwrap(text.insertionProperty("content.text"))
        let edited = NodeProperty(
            id: old.id, key: old.key, value: .string("Edited starter copy"), origin: .authored
        )
        try controller.session.execute(.setProperty(.init(pageID: page.id, nodeID: text.id, property: edited)))
        func liveText() -> DocumentNode? {
            controller.session.document.pages.first { $0.id == page.id }?.nodes.first { $0.id == text.id }
        }
        XCTAssertEqual(liveText()?.insertionStringProperty("content.text"),
                       "Edited starter copy")
        try controller.session.undo()
        XCTAssertEqual(liveText()?.insertionProperty("content.text"), old)
        try controller.session.redo()
        XCTAssertEqual(liveText()?.insertionStringProperty("content.text"),
                       "Edited starter copy")

        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(controller.session.document))
        XCTAssertEqual(reopened, controller.session.document)
        XCTAssertEqual(reopened.templateID, StarterSiteTemplate.id)
        let store = ProjectPackageStore()
        let packageData = try await store.encode(ProjectPackage(document: reopened))
        let reopenedPackage = try await store.decode(packageData)
        XCTAssertEqual(reopenedPackage.document, reopened)

        let invalidController = DocumentLifecycleController(session: DocumentSession(document: starter))
        let beforeInvalidReplacement = invalidController.stateSnapshot
        var malformed = StarterSiteTemplate.document()
        malformed.pages = []
        let rejection = await invalidController.requestNewDocument(malformed)
        XCTAssertEqual(rejection, .failed(.malformedPackage))
        XCTAssertEqual(invalidController.stateSnapshot, beforeInvalidReplacement)
    }

    // SF-0301-005, SF-0303-005
    func testInitialCreationIsOneCleanNonUndoableHistoryBaseline() async throws {
        let controller = DocumentLifecycleController(session: DocumentSession())
        let creation = await controller.requestNewDocument()
        XCTAssertEqual(creation, .completed)
        let baseline = controller.session.document

        XCTAssertEqual(baseline.revision, 0)
        XCTAssertFalse(controller.session.canUndo)
        XCTAssertFalse(controller.session.canRedo)

        let homeID = baseline.pages[0].id
        try controller.session.execute(.renamePage(RenamePageCommand(pageID: homeID, name: "Renamed")))
        try controller.session.undo()
        XCTAssertEqual(controller.session.document.pages.map(\.name), ["Home", "Not Found"])
        XCTAssertFalse(controller.session.canUndo)
    }

    // SF-0301-006, SF-0303-006
    func testNavigatorSelectionFollowsApprovedOrderForKeyboardMovement() {
        let state = WorkspaceShellState()
        let homeID = state.pages[0].id
        let notFoundID = state.pages[1].id

        XCTAssertEqual(state.effectiveSelectedPageID, homeID)
        XCTAssertEqual(state.adjacentPage(to: homeID, offset: 1), notFoundID)
        state.selectPage(notFoundID)
        XCTAssertEqual(state.effectiveSelectedPageID, notFoundID)
        XCTAssertEqual(state.adjacentPage(to: notFoundID, offset: -1), homeID)
    }

    // SF-0202-006, SF-0202-008, SF-0303-001, SF-0303-006, SF-0303-008
    func testNavigatorAccessibilityIdentityComesOnlyFromStablePageIdentity() throws {
        var document = ProjectCreation.blank()
        document.pages.append(DocumentPage(name: "Home Alternate", route: PageRoute(rawValue: "/alternate"), role: .standard))
        let before = Dictionary(uniqueKeysWithValues: document.pages.map {
            ($0.id, NavigatorPageAccessibility.identifier(for: $0.id))
        })
        XCTAssertEqual(Set(before.values).count, document.pages.count)
        XCTAssertTrue(before.values.allSatisfy { $0.hasPrefix("navigator.page.") })
        XCTAssertEqual(NavigatorPageAccessibility.roleValue(for: .home), "Home page")
        XCTAssertEqual(NavigatorPageAccessibility.roleValue(for: .notFound), "Not Found page")
        XCTAssertEqual(NavigatorPageAccessibility.roleValue(for: .standard), "Standard page")

        document.pages.reverse()
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(document))
        for page in reopened.pages {
            XCTAssertEqual(NavigatorPageAccessibility.identifier(for: page.id), before[page.id])
        }
    }
}
