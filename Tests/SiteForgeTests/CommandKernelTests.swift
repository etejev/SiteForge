import XCTest
@testable import SiteForge

@MainActor
final class CommandKernelTests: XCTestCase {
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
            kind: .image,
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
        XCTAssertTrue(json.contains("\"schemaVersion\":2"))
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
        let unknown = Data(valid.replacingOccurrences(of: "\"schemaVersion\":2", with: "\"schemaVersion\":99").utf8)
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
