import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class InsertionModelTests: XCTestCase {
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
        XCTAssertTrue(String(decoding: bytes, as: UTF8.self).contains("\"schemaVersion\":5"))
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
        for _ in 0..<200 where textState.canvasRenderPlan == nil { await Task.yield() }
        textState.performDefaultInsertion(.text, provenance: .accessibility)
        for _ in 0..<200 where textState.canvasRenderPlan?.authoredObjects.count != 1 { await Task.yield() }
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
        case .section, .stack, .grid:
            return .container(.init(kind: kind, identity: identity, nodeID: nodeID, parentID: parentID ?? fixture.rootID, index: index, geometry: geometry, provenance: provenance))
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
