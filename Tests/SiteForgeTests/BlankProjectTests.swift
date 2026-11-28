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

    // SF-1004-001, SF-1004-002, SF-1004-003, SF-1004-008
    func testExpressionLanguageTransformsTextNumbersDatesAndExplainsWhichRuleWon() throws {
        let schema = SiteExpressionSchema(["title": .text, "price": .number, "discount": .number, "published": .date,
                                           "featured": .boolean, "author.name": .text, "summary": .text])
        let day = try XCTUnwrap(SiteExpressionDate(year: 2026, month: 11, day: 26))
        let context = SiteExpressionContext(["title": .text("  Spring Sale "), "price": .number(19.5),
                                             "published": .date(day), "featured": .boolean(true),
                                             "author.name": .text("Ada")])
        func run(_ source: String) throws -> SiteExpressionEvaluation {
            SiteExpressionEngine.evaluate(try SiteExpressionEngine.check(source, schema: schema), context: context)
        }

        XCTAssertEqual(try run("upper(trim(title))").value, .text("SPRING SALE"))
        XCTAssertEqual(try run("\"By \" + author.name").value, .text("By Ada"))
        XCTAssertEqual(try run("format(price * 2, 2)").value, .text("39.00"))
        XCTAssertEqual(try run("round(price / 3, 2)").value, .number(6.5))
        XCTAssertEqual(try run("formatDate(published, \"long\")").value, .text("November 26, 2026"))
        XCTAssertEqual(try run("formatDate(published, \"medium\")").value, .text("Nov 26, 2026"))
        XCTAssertEqual(try run("formatDate(published, \"iso\")").value, .text("2026-11-26"))
        XCTAssertEqual(try run("year(published) + 1").value, .number(2027))
        XCTAssertEqual(try run("published > date(\"2026-01-01\") and featured").value, .boolean(true))
        XCTAssertEqual(try run("concat(\"$\", price)").value, .text("$19.5"))
        XCTAssertEqual(try run("truncate(\"Hello world\", 5)").value, .text("Hello…"))
        XCTAssertEqual(try run("replace(title, \"Sale\", \"Event\")").value, .text("  Spring Event "))
        XCTAssertEqual(try run("-price + 20").value, .number(0.5))
        XCTAssertEqual(try run("1 + 2 * 3").value, .number(7))
        XCTAssertEqual(try run("(1 + 2) * 3").value, .number(9))
        XCTAssertEqual(try run("not featured || length(\"abc\") == 3").value, .boolean(true))
        XCTAssertEqual(try run("min(price, 10) + max(price, 10) + abs(-1)").value, .number(30.5))

        let branch = try run("if(featured, \"Featured\", \"Regular\")")
        XCTAssertEqual(branch.value, .text("Featured"))
        XCTAssertEqual(branch.type, .text)
        XCTAssertEqual(branch.decisions.map(\.explanation), ["if(…): the condition is true, so the first result is used."])
        let fallback = try run("summary ?? \"No summary yet\"")
        XCTAssertEqual(fallback.value, .text("No summary yet"))
        XCTAssertEqual(fallback.decisions.map(\.explanation), [
            "The field “summary” has no value.",
            "The first value is missing or empty, so the fallback is used."
        ])
        XCTAssertEqual(try run("default(author.name, \"Staff\")").value, .text("Ada"))

        // Missing values: text reads as empty, conditions as false, numbers stay missing.
        XCTAssertEqual(try run("upper(summary)").value, .text(""))
        XCTAssertEqual(try run("summary == \"\"").value, .boolean(true))
        XCTAssertEqual(try run("isEmpty(summary)").value, .boolean(true))
        XCTAssertEqual(try run("discount * 2").value, .missing)
        XCTAssertEqual(try run("if(discount > 0, \"Sale\", \"Full price\")").value, .text("Full price"))
        XCTAssertEqual(try run("text(discount)").value, .text(""))
        XCTAssertEqual(SiteExpressionValue.missing.renderedText, "")
        XCTAssertEqual(SiteExpressionValue.number(3).renderedText, "3")

        let program = try SiteExpressionEngine.check("if(featured, upper(title), author.name)", schema: schema)
        XCTAssertEqual(program.fieldPaths, ["author.name", "featured", "title"])
        XCTAssertEqual(program.resultType, .text)
        XCTAssertEqual(SiteExpressionEngine.evaluate(program, context: context),
                       SiteExpressionEngine.evaluate(program, context: context))

        let diagnostic = SiteExpressionEngine.diagnostic("evaluate", objectIdentifiers: ["node:b", "node:a"], startedAt: Date())
        XCTAssertEqual(diagnostic.requirementID, "SF-1004-008")
        XCTAssertEqual(diagnostic.objectIdentifiers, ["node:a", "node:b"])
        XCTAssertEqual(diagnostic.failureCategory, "none")
        XCTAssertFalse(String(describing: diagnostic).contains("Spring"))
        XCTAssertEqual(SiteExpressionEngine.functionNames.count, SiteExpressionEngine.functionSignatures.count)
    }

    // SF-1004-001, SF-1004-004, SF-1004-007
    func testExpressionLanguageRejectsInvalidInputWithLocatedErrorsAndStaysBounded() throws {
        let schema = SiteExpressionSchema(["title": .text, "price": .number, "published": .date])
        func failure(_ source: String) -> SiteExpressionError? {
            do {
                _ = try SiteExpressionEngine.check(source, schema: schema)
                return nil
            } catch {
                return error as? SiteExpressionError
            }
        }

        XCTAssertEqual(failure("")?.category, .empty)
        XCTAssertEqual(failure("upper(title")?.category, .syntax)
        XCTAssertEqual(failure("\"open")?.category, .syntax)
        XCTAssertEqual(failure("title +")?.category, .syntax)
        XCTAssertEqual(failure("price $ 2")?.category, .syntax)
        XCTAssertEqual(failure("2abc")?.category, .syntax)
        XCTAssertEqual(failure("true and")?.category, .syntax)
        XCTAssertEqual(failure("subtitle")?.category, .unknownField)
        XCTAssertEqual(failure("subtitle")?.range, SiteExpressionSourceRange(start: 0, end: 8))
        XCTAssertEqual(failure("shout(title)")?.category, .unknownFunction)
        XCTAssertEqual(failure("upper(title, title)")?.category, .argumentCount)
        XCTAssertEqual(failure("title + price")?.category, .typeMismatch)
        XCTAssertEqual(failure("upper(price)")?.category, .typeMismatch)
        XCTAssertEqual(failure("upper(price)")?.range, SiteExpressionSourceRange(start: 6, end: 11))
        XCTAssertEqual(failure("if(title, 1, 2)")?.category, .typeMismatch)
        XCTAssertEqual(failure("if(price > 1, 1, \"x\")")?.category, .typeMismatch)
        XCTAssertEqual(failure("date(\"2026-02-30\")")?.category, .invalidLiteral)
        XCTAssertEqual(failure("formatDate(published, \"fancy\")")?.category, .invalidLiteral)
        XCTAssertEqual(failure("format(price, 11)")?.category, .invalidLiteral)
        XCTAssertEqual(failure("truncate(title, price)")?.category, .invalidLiteral)
        XCTAssertEqual(failure(String(repeating: "1+", count: 1_000) + "1")?.category, .tooLong)
        XCTAssertEqual(failure(String(repeating: "(", count: 40) + "1" + String(repeating: ")", count: 40))?.category, .tooComplex)
        XCTAssertEqual(failure(Array(repeating: "1", count: 200).joined(separator: "+"))?.category, .tooComplex)
        XCTAssertEqual(failure(Array(repeating: "1", count: 300).joined(separator: "+"))?.category, .tooComplex)
        XCTAssertNotNil(failure("subtitle")?.recoverySuggestion)
        XCTAssertNil(failure("upper(title) + \" and \" + title"))

        let numbers = SiteExpressionSchema(["a": .number, "b": .number, "raw": .text])
        let divide = try SiteExpressionEngine.check("a / b", schema: numbers)
        let zero = SiteExpressionEngine.evaluate(divide, context: SiteExpressionContext(["a": .number(1), "b": .number(0)]))
        XCTAssertEqual(zero.value, .missing)
        XCTAssertEqual(zero.findings.map(\.category), [.divisionByZero])
        let product = try SiteExpressionEngine.check("a * b", schema: numbers)
        let huge = SiteExpressionEngine.evaluate(product, context: SiteExpressionContext(["a": .number(1e200), "b": .number(1e200)]))
        XCTAssertEqual(huge.value, .missing)
        XCTAssertEqual(huge.findings.map(\.category), [.numberOutOfRange])
        let parse = try SiteExpressionEngine.check("number(raw)", schema: numbers)
        XCTAssertEqual(SiteExpressionEngine.evaluate(parse, context: SiteExpressionContext(["raw": .text(" 12.5 ")])).value, .number(12.5))
        for bad in ["1e5", "inf", "0x10", "1.2.3", "-"] {
            let result = SiteExpressionEngine.evaluate(parse, context: SiteExpressionContext(["raw": .text(bad)]))
            XCTAssertEqual(result.value, .missing, bad)
            XCTAssertEqual(result.findings.map(\.category), [.invalidNumber], bad)
        }
        let grow = try SiteExpressionEngine.check("replace(raw, \"a\", raw)", schema: numbers)
        let grown = SiteExpressionEngine.evaluate(grow, context: SiteExpressionContext(["raw": .text(String(repeating: "a", count: 300))]))
        XCTAssertEqual(grown.value, .missing)
        XCTAssertEqual(grown.findings.map(\.category), [.textTooLong])

        // Large fixture: 10,000 evaluations of one program, same answers every time.
        let label = try SiteExpressionEngine.check("if(a > 5000, concat(\"High \", a), concat(\"Low \", a))", schema: numbers)
        let started = Date()
        let results = (0..<10_000).map { index in
            SiteExpressionEngine.evaluate(label, context: SiteExpressionContext(["a": .number(Double(index))])).value
        }
        XCTAssertEqual(results[1], .text("Low 1"))
        XCTAssertEqual(results[9_999], .text("High 9999"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    // SF-1004-001, SF-1004-005
    func testStoredExpressionRoundTripsExactKeysAndKeepsIntentWhenAFieldIsRemoved() throws {
        let expression = try XCTUnwrap(SiteExpression(source: "upper(title) + \" · \" + author.name"))
        let data = try JSONEncoder().encode(expression)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "source"])
        XCTAssertEqual(try JSONDecoder().decode(SiteExpression.self, from: data), expression)
        XCTAssertNil(SiteExpression(source: "upper(title"))
        XCTAssertNil(SiteExpression(source: "   "))
        for forged in [#"{"version":2,"source":"title"}"#, #"{"version":1,"source":"title +"}"#,
                       #"{"version":1,"source":"title","extra":1}"#, #"{"version":1}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(SiteExpression.self, from: Data(forged.utf8)), forged)
        }

        // Removing a field keeps the stored expression; checking names the field.
        XCTAssertEqual(try expression.check(SiteExpressionSchema(["title": .text, "author.name": .text])).fieldPaths,
                       ["author.name", "title"])
        XCTAssertThrowsError(try expression.check(SiteExpressionSchema(["title": .text]))) { error in
            XCTAssertEqual((error as? SiteExpressionError)?.category, .unknownField)
            XCTAssertEqual((error as? SiteExpressionError)?.message.contains("author.name"), true)
        }

        let leapDay = try XCTUnwrap(SiteExpressionDate(iso: "2024-02-29"))
        XCTAssertEqual(String(decoding: try JSONEncoder().encode([leapDay]), as: UTF8.self), #"["2024-02-29"]"#)
        XCTAssertNil(SiteExpressionDate(iso: "2023-02-29"))
        XCTAssertNil(SiteExpressionDate(iso: "2024-2-29"))
        XCTAssertNil(SiteExpressionDate(iso: "２０２４-02-29"))
        XCTAssertThrowsError(try JSONDecoder().decode([SiteExpressionDate].self, from: Data(#"["2024-13-01"]"#.utf8)))
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
