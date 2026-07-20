import XCTest
@testable import SiteForge

@MainActor
final class BlankProjectTests: XCTestCase {
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
