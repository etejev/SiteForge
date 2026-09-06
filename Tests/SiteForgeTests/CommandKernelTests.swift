import XCTest
@testable import SiteForge

@MainActor
final class CommandKernelTests: XCTestCase {
    func testStaticPageRoutesValidationIdentityAndAtomicHistory() throws {
        let unicodeCopy = try StaticPagePolicy.duplicateName(String(repeating: "界", count: 85))
        XCTAssertLessThanOrEqual(unicodeCopy.utf8.count, 256)
        XCTAssertTrue(unicodeCopy.hasSuffix(" Copy"))
        XCTAssertEqual(try StaticPagePolicy.name(unicodeCopy), unicodeCopy)
        let session = DocumentSession(document: BlankProjectDefaults.document())
        let registry = PageCommandRegistry()
        func apply(_ edit: PageEdit, pageID: PageID) throws -> PageID {
            let prepared = try registry.prepare(edit, identity: .init(documentID: session.document.id,
                revision: session.document.revision, pageID: pageID), in: session.document, isAvailable: true)
            try session.execute(prepared.command)
            return prepared.selectedPageID
        }
        let home = session.document.pages[0].id
        let created = try apply(.create(name: " About ", route: " /About/Team "), pageID: home)
        let page = try XCTUnwrap(session.document.pages.last)
        XCTAssertEqual(page.id, created)
        XCTAssertEqual(page.name, "About")
        XCTAssertEqual(page.route.rawValue, "/about/team")
        XCTAssertEqual(page.nodes.count, 1)
        XCTAssertTrue(page.nodes[0].properties.isEmpty)
        XCTAssertTrue(page.nodes[0].childIDs.isEmpty)
        _ = try apply(.rename("Our Team"), pageID: created)
        _ = try apply(.route("/team"), pageID: created)
        _ = try apply(.move(0), pageID: created)
        XCTAssertEqual(session.document.pages.first?.id, created)
        try session.undo()
        XCTAssertEqual(session.document.pages.last?.id, created)
        try session.undo()
        XCTAssertEqual(session.document.pages.last?.route.rawValue, "/about/team")
        try session.redo()
        XCTAssertEqual(session.document.pages.last?.route.rawValue, "/team")
        XCTAssertEqual(session.document.pages.last?.rootNodeIDs, page.rootNodeIDs)
        XCTAssertEqual(try JSONDecoder().decode(CanonicalDocument.self,
            from: JSONEncoder().encode(session.document)), session.document)
        let before = session.document
        for invalid in ["", "/", "/404", "/a//b", "/a/", "/a?x=1", "/a#b", "/../x", "/a%2fb", "/a b", "/a\\b"] {
            XCTAssertThrowsError(try apply(.route(invalid), pageID: created), invalid)
        }
        XCTAssertThrowsError(try apply(.create(name: "Other", route: "/TEAM"), pageID: home))
        XCTAssertThrowsError(try apply(.delete, pageID: home))
        XCTAssertThrowsError(try apply(.route("/home"), pageID: home))
        for invalid in ["", "\n", "bad\u{0000}name", String(repeating: "x", count: 257)] {
            XCTAssertThrowsError(try apply(.rename(invalid), pageID: created))
        }
        XCTAssertEqual(session.document, before)
    }

    func testStaticPageDuplicateRemapsInternalLinksAndDeleteUndoPreservesIntent() throws {
        let session = DocumentSession(document: BlankProjectDefaults.document())
        let registry = PageCommandRegistry()
        func apply(_ edit: PageEdit, _ id: PageID) throws -> PageID {
            let value = try registry.prepare(edit, identity: .init(documentID: session.document.id,
                revision: session.document.revision, pageID: id), in: session.document, isAvailable: true)
            try session.execute(value.command)
            return value.selectedPageID
        }
        let home = session.document.pages[0].id
        let pageID = try apply(.create(name: "Destination", route: "/destination"), home)
        let root = try XCTUnwrap(session.document.pages.last?.rootNodeIDs.first)
        let link = DocumentNode(kind: .link, name: "Self link", parent: .node(root), properties:
            CanonicalLinkTarget.page(pageID).properties.map { .init(key: .init(rawValue: $0.0), value: $0.1) })
        try session.execute(.insertNode(.init(pageID: pageID, node: link, index: 0)))
        let copyID = try apply(.duplicate, pageID)
        let original = try XCTUnwrap(session.document.pages.first { $0.id == pageID })
        let copy = try XCTUnwrap(session.document.pages.first { $0.id == copyID })
        XCTAssertTrue(Set(original.nodes.map(\.id)).isDisjoint(with: copy.nodes.map(\.id)))
        XCTAssertEqual(try CanonicalLinkTarget.resolve(copy.nodes[1]), .page(copyID))
        XCTAssertNotEqual(original.nodes[1].properties[0].id, copy.nodes[1].properties[0].id)
        let homeRoot = session.document.pages[0].rootNodeIDs[0]
        let inbound = DocumentNode(kind: .link, name: "Inbound", parent: .node(homeRoot), properties:
            CanonicalLinkTarget.page(pageID).properties.map { .init(key: .init(rawValue: $0.0), value: $0.1) })
        try session.execute(.insertNode(.init(pageID: home, node: inbound, index: 0)))
        XCTAssertEqual(registry.inboundLinkCount(to: pageID, in: session.document), 1)
        let beforePages = session.document.pages
        _ = try apply(.delete, pageID)
        XCTAssertFalse(session.document.pages.contains { $0.id == pageID })
        XCTAssertEqual(try CanonicalLinkTarget.resolve(session.document.pages[0].nodes[1]), .page(pageID))
        try session.undo()
        XCTAssertEqual(session.document.pages, beforePages)
        try session.redo()
        XCTAssertFalse(session.document.pages.contains { $0.id == pageID })
    }

    func testStaticPageStaleCancelledUnavailableAndNoOpAreNeutral() throws {
        let document = BlankProjectDefaults.document()
        let registry = PageCommandRegistry()
        let identity = PageEditIdentity(documentID: document.id, revision: document.revision, pageID: document.pages[0].id)
        XCTAssertThrowsError(try registry.prepare(.rename("Home"), identity: identity, in: document, isAvailable: true))
        XCTAssertThrowsError(try registry.prepare(.rename("Changed"), identity: identity, in: document, isAvailable: false))
        XCTAssertThrowsError(try registry.prepare(.rename("Changed"), identity: identity, in: document, isAvailable: true, cancelled: true))
        for stale in [PageEditIdentity(documentID: DocumentID(), revision: 0, pageID: identity.pageID),
                      .init(documentID: document.id, revision: 1, pageID: identity.pageID),
                      .init(documentID: document.id, revision: 0, pageID: PageID())] {
            XCTAssertThrowsError(try registry.prepare(.rename("Changed"), identity: stale, in: document, isAvailable: true))
        }
        let diagnostics = CommandDiagnostics()
        diagnostics.recordPagePreparationFailure(.rename("Private page name"), pageID: identity.pageID, durationMilliseconds: 1)
        XCTAssertTrue(diagnostics.records[0].requirementIDs.contains("SF-0303-008"))
        XCTAssertFalse(String(describing: diagnostics.records).contains("Private page name"))
        XCTAssertFalse(String(describing: diagnostics.records).contains(identity.pageID.description))
    }

    func testStaticPagePackageRecoveryHistoryAndLegacyRouteInverse() async throws {
        let session = DocumentSession(document: BlankProjectDefaults.document())
        let page = DocumentPage(name: "Legacy", route: .init(rawValue: "/Legacy"))
        try session.execute(.insertPage(.init(page: page, index: 2)))
        let registry = PageCommandRegistry()
        let prepared = try registry.prepare(.route("/updated"), identity: .init(documentID: session.document.id,
            revision: session.document.revision, pageID: page.id), in: session.document, isAvailable: true)
        try session.execute(prepared.command)
        try session.execute(.movePage(.init(pageID: page.id, index: 0)))
        let package = ProjectPackage(createdAt: .init(date: Date(timeIntervalSince1970: 1)), document: session.document)
        let store = ProjectPackageStore()
        let archived = try await PersistedHistoryStore().package(package, with: session.historySnapshot())
        let bytes = try await store.encode(archived)
        let sameBytes = try await store.encode(archived)
        XCTAssertEqual(bytes, sameBytes)
        let reopened = try await store.decode(bytes)
        XCTAssertEqual(reopened.document, session.document)
        guard case .restored(let history) = try await PersistedHistoryStore().load(from: reopened) else {
            return XCTFail("Page commands must retain validated package/recovery history")
        }
        let recovered = DocumentSession(document: reopened.document)
        try recovered.installValidatedHistory(history)
        try recovered.undo()
        XCTAssertEqual(recovered.document.pages.last?.id, page.id)
        try recovered.undo()
        XCTAssertEqual(recovered.document.pages.last?.route.rawValue, "/Legacy")
        try recovered.redo()
        XCTAssertEqual(recovered.document.pages.last?.route.rawValue, "/updated")
        try recovered.execute(.renamePage(.init(pageID: page.id, name: "Branch")))
        XCTAssertFalse(recovered.canRedo)
        XCTAssertFalse(String(describing: recovered.diagnostics.records).contains("/updated"))
        XCTAssertFalse(String(describing: recovered.diagnostics.records).contains("/Legacy"))
    }

    func testStaticPageDuplicateSectionTargetsGuidesAndBoundedNodeOrdering() throws {
        for count in [100, 10_000] {
            let pageID = PageID(), rootID = NodeID(), sectionID = NodeID()
            let children = (0..<count).map { index in
                DocumentNode(kind: .frame, name: "Item \(index)", parent: .node(sectionID))
            }
            let section = DocumentNode(id: sectionID, kind: .section, name: "Section", parent: .node(rootID), childIDs: children.map(\.id), properties: [
                .init(key: .init(rawValue: "layout.container.kind"), value: .string("section"), origin: .defaulted),
                .init(key: .init(rawValue: "layout.axis"), value: .string("vertical"), origin: .defaulted),
                .init(key: .init(rawValue: "layout.padding"), value: .number(48), origin: .defaulted),
            ])
            let target = DocumentNode(kind: .link, name: "Section link", parent: .node(rootID), properties:
                CanonicalLinkTarget.section(pageID: pageID, nodeID: sectionID).properties.map {
                    .init(key: .init(rawValue: $0.0), value: $0.1)
                })
            let external = DocumentNode(kind: .link, name: "External", parent: .node(rootID), properties:
                CanonicalLinkTarget.external("https://example.com").properties.map {
                    .init(key: .init(rawValue: $0.0), value: $0.1)
                })
            let root = DocumentNode(id: rootID, kind: .frame, name: "Root", parent: .page(pageID), childIDs: [sectionID, target.id, external.id])
            let page = DocumentPage(id: pageID, name: "Source", route: .init(rawValue: "/source"), rootNodeIDs: [rootID], nodes: [root, section, target, external] + children)
            var document = BlankProjectDefaults.document()
            document.pages.append(page)
            document.guides.append(.init(pageID: pageID, axis: .vertical, position: 123))
            try document.validate()
            let session = DocumentSession(document: document)
            let registry = PageCommandRegistry()
            let prepared = try registry.prepare(.duplicate, identity: .init(documentID: document.id,
                revision: document.revision, pageID: pageID), in: document, isAvailable: true)
            try session.execute(prepared.command)
            let copy = try XCTUnwrap(session.document.pages.last)
            XCTAssertEqual(copy.nodes.map(\.name), page.nodes.map(\.name))
            XCTAssertEqual(copy.nodes[1].childIDs, Array(copy.nodes.dropFirst(4)).map(\.id))
            XCTAssertEqual(try CanonicalLinkTarget.resolve(copy.nodes[2]), .section(pageID: copy.id, nodeID: copy.nodes[1].id))
            XCTAssertEqual(try CanonicalLinkTarget.resolve(copy.nodes[3]), .external("https://example.com"))
            XCTAssertEqual(session.document.imageAssets, document.imageAssets)
            XCTAssertEqual(session.document.guides.last?.pageID, copy.id)
            XCTAssertEqual(session.document.guides.last?.position, 123)
            XCTAssertNotEqual(session.document.guides.last?.id, document.guides.first?.id)
            try session.undo()
            XCTAssertEqual(session.document.pages, document.pages)
            XCTAssertEqual(session.document.guides, document.guides)
            let deletion = try registry.prepare(.delete, identity: .init(documentID: document.id,
                revision: session.document.revision, pageID: pageID), in: session.document, isAvailable: true)
            try session.execute(deletion.command)
            XCTAssertTrue(session.document.guides.isEmpty)
            try session.undo()
            XCTAssertEqual(session.document.pages, document.pages)
            XCTAssertEqual(session.document.guides, document.guides)
        }
    }
    private let documentID = DocumentID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    private let pageID = PageID(UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
    private let rootNodeID = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
    private let childNodeID = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000004")!)
    private let propertyID = PropertyID(UUID(uuidString: "00000000-0000-0000-0000-000000000005")!)

    private func populatedDocument() -> CanonicalDocument {
        let property = NodeProperty(
            id: propertyID,
            key: PropertyKey(rawValue: "text.content"),
            value: .string("Hello")
        )
        let child = DocumentNode(
            id: childNodeID,
            kind: .text,
            name: "Heading",
            parent: .node(rootNodeID),
            properties: [property]
        )
        let root = DocumentNode(
            id: rootNodeID,
            kind: .frame,
            name: "Body",
            parent: .page(pageID),
            childIDs: [childNodeID]
        )
        return CanonicalDocument(
            id: documentID,
            pages: [
                DocumentPage(
                    id: pageID,
                    name: "Home",
                    rootNodeIDs: [rootNodeID],
                    nodes: [root, child]
                )
            ]
        )
    }

    private func insertPage(_ page: DocumentPage, at index: Int = 0) -> DocumentCommand {
        .insertPage(InsertPageCommand(page: page, index: index))
    }

    // SF-0302-001, SF-0303-001, SF-0304-001, SF-0305-001
    func testStableTypedIdentityAndOwnershipSurviveValidationAndRoundTrip() throws {
        let document = populatedDocument()
        try document.validate()

        let decoded = try DocumentSerializer.decode(DocumentSerializer.encode(document))
        XCTAssertEqual(decoded.id, documentID)
        XCTAssertEqual(decoded.pages[0].id, pageID)
        XCTAssertEqual(decoded.pages[0].nodes[0].id, rootNodeID)
        XCTAssertEqual(decoded.pages[0].nodes[1].properties[0].id, propertyID)
        XCTAssertEqual(decoded.pages[0].nodes[1].properties[0].origin, .authored)
        XCTAssertEqual(decoded.pages[0].nodes[1].parent, .node(rootNodeID))
    }

    // SF-0302-004, SF-0304-004
    func testInvalidParentChildOwnershipIsRejected() {
        var document = populatedDocument()
        document.pages[0].nodes[1].parent = .page(pageID)

        XCTAssertThrowsError(try document.validate()) { error in
            XCTAssertEqual(error as? ModelValidationError, .invalidParent)
        }
    }

    // SF-0203-001, SF-0203-006
    func testCentralRegistryIsExhaustiveAndProvidesDisabledReasons() {
        let registry = CommandRegistry()
        XCTAssertEqual(Set(registry.descriptors.keys), Set(CommandName.allCases))

        let missing = PageID(UUID(uuidString: "00000000-0000-0000-0000-000000000099")!)
        let availability = registry.availability(
            for: .renamePage(RenamePageCommand(pageID: missing, name: "Missing")),
            in: populatedDocument()
        )
        XCTAssertFalse(availability.isEnabled)
        XCTAssertEqual(availability.disabledReason, "The page no longer exists.")
    }

    // SF-0203-005, SF-0306-001
    func testValidRegisteredCommandCommitsExactlyOnce() throws {
        let session = DocumentSession(document: CanonicalDocument(id: documentID))
        let page = DocumentPage(id: pageID, name: "Added Page")

        try session.execute(insertPage(page))

        XCTAssertEqual(session.document.pages.first, page)
        XCTAssertEqual(session.document.pages.count, 3)
        XCTAssertEqual(session.document.revision, 1)
        XCTAssertTrue(session.canUndo)
        XCTAssertFalse(session.canRedo)
    }

    // SF-0203-004, SF-0302-004, SF-0306-004
    func testInvalidCommandIsRejectedWithoutChangingCommittedDocument() {
        let document = populatedDocument()
        let session = DocumentSession(document: document)
        let command = DocumentCommand.renamePage(
            RenamePageCommand(pageID: pageID, name: "   ")
        )

        XCTAssertThrowsError(try session.execute(command)) { error in
            XCTAssertEqual(error as? CommandExecutionError, .disabled("Page names cannot be empty."))
        }
        XCTAssertEqual(session.document, document)
        XCTAssertFalse(session.canUndo)
    }

    // SF-0306-001, SF-0306-004, SF-0306-005
    func testFailedBatchAndCancelledCommandRollbackAtomically() {
        let document = populatedDocument()
        let missing = PageID(UUID(uuidString: "00000000-0000-0000-0000-000000000099")!)
        let session = DocumentSession(document: document)
        let batch = DocumentCommand.batch([
            .renamePage(RenamePageCommand(pageID: pageID, name: "Changed")),
            .renamePage(RenamePageCommand(pageID: missing, name: "Missing")),
        ])

        XCTAssertThrowsError(try session.execute(batch))
        XCTAssertEqual(session.document, document)

        let valid = DocumentCommand.renamePage(
            RenamePageCommand(pageID: pageID, name: "Also Changed")
        )
        XCTAssertThrowsError(
            try session.execute(valid, cancellation: CommandCancellation(isCancelled: { true }))
        ) { error in
            XCTAssertEqual(error as? CommandExecutionError, .cancelled)
        }
        XCTAssertEqual(session.document, document)
        XCTAssertFalse(session.canUndo)
    }

    // SF-0307-001, SF-0307-004, SF-0307-005
    func testInverseRestoresNodeAndPropertyOwnership() throws {
        let original = populatedDocument()
        let session = DocumentSession(document: original)
        let newProperty = NodeProperty(
            id: PropertyID(UUID(uuidString: "00000000-0000-0000-0000-000000000006")!),
            key: PropertyKey(rawValue: "accessibility.label"),
            value: .string("Hero")
        )
        try session.execute(
            .setProperty(
                SetPropertyCommand(
                    pageID: pageID,
                    nodeID: rootNodeID,
                    property: newProperty
                )
            )
        )
        XCTAssertEqual(session.document.pages[0].nodes[0].properties, [newProperty])

        try session.undo()

        XCTAssertEqual(session.document.pages, original.pages)
        XCTAssertEqual(session.document.id, original.id)
        XCTAssertEqual(session.document.revision, 2)
    }

    // SF-0304-001, SF-0306-005, SF-0307-005
    func testInsertedNodeInverseRestoresTheExactOwningPage() throws {
        let original = populatedDocument()
        let session = DocumentSession(document: original)
        let insertedID = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000007")!)
        let node = DocumentNode(
            id: insertedID,
            kind: .frame,
            name: "Artwork",
            parent: .node(rootNodeID)
        )

        try session.execute(
            .insertNode(InsertNodeCommand(pageID: pageID, node: node, index: 1))
        )
        XCTAssertEqual(session.document.pages[0].nodes[0].childIDs, [childNodeID, insertedID])

        try session.undo()
        XCTAssertEqual(session.document.pages, original.pages)

        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes[0].childIDs, [childNodeID, insertedID])
    }

    // SF-0306-005, SF-0307-005, SF-0408-005 — indexes are pre-removal positions.
    func testSameParentBackwardMoveInverseRestoresOriginalOrdering() throws {
        let first = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000010")!)
        let second = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000011")!)
        let third = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000012")!)
        let root = DocumentNode(
            id: rootNodeID,
            kind: .frame,
            name: "Root",
            parent: .page(pageID),
            childIDs: [first, second, third]
        )
        let document = CanonicalDocument(
            id: documentID,
            pages: [DocumentPage(
                id: pageID,
                name: "Home",
                rootNodeIDs: [rootNodeID],
                nodes: [
                    root,
                    DocumentNode(id: first, kind: .frame, name: "First", parent: .node(rootNodeID)),
                    DocumentNode(id: second, kind: .frame, name: "Second", parent: .node(rootNodeID)),
                    DocumentNode(id: third, kind: .frame, name: "Third", parent: .node(rootNodeID)),
                ]
            )]
        )
        let session = DocumentSession(document: document)

        try session.execute(.moveNode(MoveNodeCommand(
            pageID: pageID,
            nodeID: third,
            destination: .node(rootNodeID),
            index: 0
        )))
        XCTAssertEqual(session.document.pages[0].nodes[0].childIDs, [third, first, second])

        try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)

        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes[0].childIDs, [third, first, second])
    }

    // SF-0305-001, SF-0306-005, SF-0307-005
    func testPropertyRemovalInverseRestoresOriginalOrder() throws {
        let session = DocumentSession(document: populatedDocument())
        let second = NodeProperty(
            id: PropertyID(UUID(uuidString: "00000000-0000-0000-0000-000000000008")!),
            key: PropertyKey(rawValue: "text.role"),
            value: .string("heading"),
            origin: .defaulted
        )
        try session.execute(
            .setProperty(SetPropertyCommand(pageID: pageID, nodeID: childNodeID, property: second))
        )
        try session.execute(
            .removeProperty(
                RemovePropertyCommand(pageID: pageID, nodeID: childNodeID, propertyID: propertyID)
            )
        )

        try session.undo()

        XCTAssertEqual(
            session.document.pages[0].nodes[1].properties.map(\.id),
            [propertyID, second.id]
        )
        XCTAssertEqual(session.document.pages[0].nodes[1].properties[1].origin, .defaulted)
    }

    // SF-0307-005, SF-0307-006
    func testUndoAndRedoPreserveCommandOrdering() throws {
        let session = DocumentSession(document: populatedDocument())
        try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "First")))
        try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Second")))

        try session.undo()
        XCTAssertEqual(session.document.pages[0].name, "First")
        try session.undo()
        XCTAssertEqual(session.document.pages[0].name, "Home")

        try session.redo()
        XCTAssertEqual(session.document.pages[0].name, "First")
        try session.redo()
        XCTAssertEqual(session.document.pages[0].name, "Second")
        XCTAssertFalse(session.canRedo)
    }

    // SF-0307-005
    func testNewEditAfterUndoInvalidatesRedoBranch() throws {
        let session = DocumentSession(document: populatedDocument())
        try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "First")))
        try session.undo()
        XCTAssertTrue(session.canRedo)

        try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Branch")))

        XCTAssertEqual(session.document.pages[0].name, "Branch")
        XCTAssertFalse(session.canRedo)
    }

    // SF-0302-001, SF-1702-001
    func testSerializationIsDeterministicAndVersioned() throws {
        let document = populatedDocument()
        let first = try DocumentSerializer.encode(document)
        let second = try DocumentSerializer.encode(document)

        XCTAssertEqual(first, second)
        let json = String(decoding: first, as: UTF8.self)
        XCTAssertTrue(json.contains("\"schemaVersion\":6"))
        XCTAssertTrue(json.contains("\"origin\":\"authored\""))
    }

    // SF-0302-001, SF-1702-001, SF-1702-008
    func testSerializationRoundTripPreservesCanonicalModel() throws {
        let document = populatedDocument()
        let roundTrip = try DocumentSerializer.decode(DocumentSerializer.encode(document))
        XCTAssertEqual(roundTrip, document)
    }

    // SF-0302-004, SF-1702-004, SF-1702-008
    func testUnknownMalformedAndInvalidSchemaInputsAreRejected() throws {
        let valid = String(decoding: try DocumentSerializer.encode(populatedDocument()), as: UTF8.self)
        let unknown = Data(valid.replacingOccurrences(of: "\"schemaVersion\":6", with: "\"schemaVersion\":99").utf8)
        XCTAssertThrowsError(try DocumentSerializer.decode(unknown)) { error in
            XCTAssertEqual(error as? DocumentSerializationError, .unsupportedSchema(99))
        }

        XCTAssertThrowsError(try DocumentSerializer.decode(Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? DocumentSerializationError, .malformedInput)
        }

        let invalid = Data(valid.replacingOccurrences(of: "\"name\":\"Home\"", with: "\"name\":\"\"").utf8)
        XCTAssertThrowsError(try DocumentSerializer.decode(invalid)) { error in
            XCTAssertEqual(
                error as? DocumentSerializationError,
                .invalidModel(.invalidPageName)
            )
        }
    }

    // SF-0301-004, SF-0303-005, SF-1702-004
    func testCurrentSchemaRequiresEveryCurrentDocumentAndPageField() throws {
        let encoded = try DocumentSerializer.encode(populatedDocument())
        let topLevelFields = ["creationKind", "templateID", "pages"]
        for field in topLevelFields {
            let candidate = try editingCurrentDocument(encoded) { $0.removeValue(forKey: field) }
            XCTAssertThrowsError(try DocumentSerializer.decode(candidate), "Missing \(field)") { error in
                XCTAssertEqual(error as? DocumentSerializationError, .malformedInput)
            }
        }

        let pageFields = ["route", "role", "provenance", "rootNodeIDs", "nodes"]
        for field in pageFields {
            let candidate = try editingCurrentDocument(encoded) { document in
                var pages = document["pages"] as! [[String: Any]]
                pages[0].removeValue(forKey: field)
                document["pages"] = pages
            }
            XCTAssertThrowsError(try DocumentSerializer.decode(candidate), "Missing \(field)") { error in
                XCTAssertEqual(error as? DocumentSerializationError, .malformedInput)
            }
        }

        let empty = try editingCurrentDocument(encoded) { $0["pages"] = [] }
        XCTAssertThrowsError(try DocumentSerializer.decode(empty)) { error in
            XCTAssertEqual(error as? DocumentSerializationError, .invalidModel(.emptyPageList))
        }

        let rootless = try editingCurrentDocument(encoded) { document in
            var pages = document["pages"] as! [[String: Any]]
            pages[0]["rootNodeIDs"] = []
            pages[0]["nodes"] = []
            document["pages"] = pages
        }
        XCTAssertThrowsError(try DocumentSerializer.decode(rootless)) { error in
            XCTAssertEqual(error as? DocumentSerializationError, .invalidModel(.missingPageRoot))
        }
    }

    // SF-0302-004, SF-0303-005, SF-1702-004 — current schemas are closed;
    // accepting a future field and rewriting without it would silently lose data.
    func testCurrentSchemaRejectsUnknownCanonicalFieldsAtEveryOwnedLevel() throws {
        let encoded = try DocumentSerializer.encode(populatedDocument())
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("envelope", { $0["futureEnvelopeField"] = true }),
            ("document", { envelope in
                var document = envelope["document"] as! [String: Any]
                document["futureDocumentField"] = true
                envelope["document"] = document
            }),
            ("page", { envelope in
                var document = envelope["document"] as! [String: Any]
                var pages = document["pages"] as! [[String: Any]]
                pages[0]["futurePageField"] = true
                document["pages"] = pages
                envelope["document"] = document
            }),
            ("node", { envelope in
                var document = envelope["document"] as! [String: Any]
                var pages = document["pages"] as! [[String: Any]]
                var nodes = pages[0]["nodes"] as! [[String: Any]]
                nodes[0]["futureNodeField"] = true
                pages[0]["nodes"] = nodes
                document["pages"] = pages
                envelope["document"] = document
            }),
            ("property", { envelope in
                var document = envelope["document"] as! [String: Any]
                var pages = document["pages"] as! [[String: Any]]
                var nodes = pages[0]["nodes"] as! [[String: Any]]
                var properties = nodes[1]["properties"] as! [[String: Any]]
                properties[0]["futurePropertyField"] = true
                nodes[1]["properties"] = properties
                pages[0]["nodes"] = nodes
                document["pages"] = pages
                envelope["document"] = document
            }),
        ]
        for (name, edit) in cases {
            let candidate = try editingEnvelope(encoded, edit: edit)
            XCTAssertThrowsError(try DocumentSerializer.decode(candidate), "Unknown \(name) field") { error in
                XCTAssertEqual(error as? DocumentSerializationError, .malformedInput)
            }
        }
    }

    // SF-0302-004, SF-0303-005, SF-1702-004 — closed current-schema enum
    // envelopes and nested payloads must not be silently rewritten without
    // future semantics that the current model cannot preserve.
    func testCurrentSchemaRejectsUnknownEnumAndNestedValueFields() throws {
        var document = populatedDocument()
        document.guides = [AuthoredGuide(
            id: GuideID(UUID(uuidString: "00000000-0000-0000-0000-000000000013")!),
            pageID: pageID,
            axis: .vertical,
            position: 12
        )]
        let encoded = try DocumentSerializer.encode(document)
        let cases: [(String, (inout [String: Any]) -> Void)] = [
            ("node parent case", { envelope in
                var document = envelope["document"] as! [String: Any]
                var pages = document["pages"] as! [[String: Any]]
                var nodes = pages[0]["nodes"] as! [[String: Any]]
                var parent = nodes[1]["parent"] as! [String: Any]
                parent["futureParent"] = ["_0": "not-a-node"]
                nodes[1]["parent"] = parent
                pages[0]["nodes"] = nodes
                document["pages"] = pages
                envelope["document"] = document
            }),
            ("node parent payload", { envelope in
                var document = envelope["document"] as! [String: Any]
                var pages = document["pages"] as! [[String: Any]]
                var nodes = pages[0]["nodes"] as! [[String: Any]]
                var parent = nodes[1]["parent"] as! [String: Any]
                var payload = parent["node"] as! [String: Any]
                payload["futurePayload"] = true
                parent["node"] = payload
                nodes[1]["parent"] = parent
                pages[0]["nodes"] = nodes
                document["pages"] = pages
                envelope["document"] = document
            }),
            ("property value case", { envelope in
                var document = envelope["document"] as! [String: Any]
                var pages = document["pages"] as! [[String: Any]]
                var nodes = pages[0]["nodes"] as! [[String: Any]]
                var properties = nodes[1]["properties"] as! [[String: Any]]
                var value = properties[0]["value"] as! [String: Any]
                value["futureValue"] = ["_0": true]
                properties[0]["value"] = value
                nodes[1]["properties"] = properties
                pages[0]["nodes"] = nodes
                document["pages"] = pages
                envelope["document"] = document
            }),
            ("property value payload", { envelope in
                var document = envelope["document"] as! [String: Any]
                var pages = document["pages"] as! [[String: Any]]
                var nodes = pages[0]["nodes"] as! [[String: Any]]
                var properties = nodes[1]["properties"] as! [[String: Any]]
                var value = properties[0]["value"] as! [String: Any]
                var payload = value["string"] as! [String: Any]
                payload["futurePayload"] = true
                value["string"] = payload
                properties[0]["value"] = value
                nodes[1]["properties"] = properties
                pages[0]["nodes"] = nodes
                document["pages"] = pages
                envelope["document"] = document
            }),
            ("guide", { envelope in
                var document = envelope["document"] as! [String: Any]
                var guides = document["guides"] as! [[String: Any]]
                guides[0]["futureGuide"] = true
                document["guides"] = guides
                envelope["document"] = document
            }),
        ]
        for (name, edit) in cases {
            let candidate = try editingEnvelope(encoded, edit: edit)
            XCTAssertThrowsError(try DocumentSerializer.decode(candidate), "Unknown \(name) field") { error in
                XCTAssertEqual(error as? DocumentSerializationError, .malformedInput)
            }
        }
    }

    // SF-0307-004, SF-1702-004
    func testTerminalRevisionIsRejectedWithoutOverflowOrMutation() throws {
        let valid = try DocumentSerializer.encode(populatedDocument())
        let terminal = try editingCurrentDocument(valid) { $0["revision"] = NSNumber(value: UInt64.max) }
        XCTAssertThrowsError(try DocumentSerializer.decode(terminal)) { error in
            XCTAssertEqual(error as? DocumentSerializationError, .invalidModel(.revisionNotIncrementable))
        }

        var exhausted = populatedDocument()
        exhausted.revision = UInt64.max - 1
        let session = DocumentSession(document: exhausted)
        XCTAssertThrowsError(
            try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Must Not Commit")))
        ) { error in
            XCTAssertEqual(error as? CommandExecutionError, .revisionExhausted)
        }
        XCTAssertEqual(session.document, exhausted)
        XCTAssertFalse(session.canUndo)
        XCTAssertFalse(session.canRedo)

        var finalCommit = populatedDocument()
        finalCommit.revision = UInt64.max - 2
        let boundary = DocumentSession(document: finalCommit)
        try boundary.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Last Commit")))
        XCTAssertEqual(boundary.document.revision, UInt64.max - 1)
        let committed = boundary.document
        XCTAssertThrowsError(
            try boundary.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Overflow")))
        ) { error in
            XCTAssertEqual(error as? CommandExecutionError, .revisionExhausted)
        }
        XCTAssertEqual(boundary.document, committed)
        XCTAssertTrue(boundary.canUndo)
        XCTAssertFalse(boundary.canRedo)
    }

    // SF-0203-008, SF-0306-008, SF-1607-008
    func testDiagnosticsRedactContentAndRawIdentifiers() throws {
        let diagnostics = CommandDiagnostics()
        let session = DocumentSession(document: populatedDocument(), diagnostics: diagnostics)
        try session.execute(
            .renamePage(RenamePageCommand(pageID: pageID, name: "Confidential Launch Page"))
        )
        XCTAssertThrowsError(
            try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "")))
        )

        XCTAssertEqual(diagnostics.records.count, 2)
        XCTAssertEqual(diagnostics.records[0].result, .success)
        XCTAssertEqual(diagnostics.records[1].failureCategory, .validation)
        let description = String(describing: diagnostics.records)
        XCTAssertFalse(description.contains("Confidential Launch Page"))
        XCTAssertFalse(description.lowercased().contains(pageID.description))
        XCTAssertTrue(diagnostics.records.allSatisfy {
            $0.sanitizedIdentifiers.allSatisfy { $0.hasPrefix("page-") }
        })
    }

    // SF-0203-006, SF-0307-006, SF-1902-006
    func testToolbarCommandEnablementTracksRealHistory() throws {
        let session = DocumentSession(document: CanonicalDocument(id: documentID))
        let shell = WorkspaceShellState(documentSession: session)
        XCTAssertFalse(shell.canUndo)
        XCTAssertFalse(shell.canRedo)
        XCTAssertEqual(shell.undoDisabledReason, "There are no document changes to undo.")

        try session.execute(insertPage(DocumentPage(id: pageID, name: "Added Page")))
        XCTAssertTrue(shell.canUndo)
        XCTAssertFalse(shell.canRedo)

        shell.undo()
        XCTAssertFalse(shell.canUndo)
        XCTAssertTrue(shell.canRedo)

        shell.redo()
        XCTAssertTrue(shell.canUndo)
        XCTAssertFalse(shell.canRedo)
    }

    // SF-1902-008
    func testFoundationCommandRequirementTraceabilityIsComplete() {
        XCTAssertEqual(
            DocumentSession.requirementIDs,
            [
                "SF-0203-001", "SF-0203-004", "SF-0203-005", "SF-0203-006", "SF-0203-008",
                "SF-0302-001", "SF-0302-004", "SF-0302-005", "SF-0302-008",
                "SF-0303-001", "SF-0304-001", "SF-0304-004", "SF-0305-001",
                "SF-0306-001", "SF-0306-004", "SF-0306-005", "SF-0306-008",
                "SF-0307-001", "SF-0307-004", "SF-0307-005", "SF-0307-006", "SF-0307-008",
                "SF-1607-008", "SF-1702-001", "SF-1702-004", "SF-1702-008",
                "SF-1902-001", "SF-1902-004", "SF-1902-005", "SF-1902-006", "SF-1902-008",
            ]
        )
    }
}

private func editingCurrentDocument(
    _ data: Data,
    edit: (inout [String: Any]) -> Void
) throws -> Data {
    var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    var document = try XCTUnwrap(envelope["document"] as? [String: Any])
    edit(&document)
    envelope["document"] = document
    return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
}

private func editingEnvelope(
    _ data: Data,
    edit: (inout [String: Any]) -> Void
) throws -> Data {
    var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    edit(&envelope)
    return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
}
