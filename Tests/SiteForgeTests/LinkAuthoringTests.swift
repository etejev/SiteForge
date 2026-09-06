import AppKit
import XCTest
@testable import SiteForge

@MainActor
final class LinkAuthoringTests: XCTestCase {
    private let scene = CanvasViewportSceneID()

    private func insert(_ kind: InsertionKind, in session: DocumentSession, parent: NodeID? = nil) throws -> NodeID {
        let page = session.document.pages[0], id = NodeID()
        let parentID = parent ?? page.rootNodeIDs[0]
        let identity = InsertionOperationIdentity(documentID: session.document.id, pageID: page.id, revision: session.document.revision, generation: 1)
        let index = page.nodes.first { $0.id == parentID }!.childIDs.count
        let geometry = InsertionGeometry.defaultValue(for: kind, at: .init(x: 40, y: 50))
        let command: AuthoringInsertionCommand
        if [.section, .stack, .grid].contains(kind) {
            command = .container(.init(kind: kind, identity: identity, nodeID: id, parentID: parentID, index: index, geometry: geometry, provenance: .menu))
        } else {
            command = .control(.init(kind: kind, identity: identity, nodeID: id, parentID: parentID, index: index, geometry: geometry, provenance: .menu))
        }
        let prepared = try InsertionCommandRegistry().prepare(command, in: session.document,
            context: .init(activePageID: page.id, activeRoute: .init(rawValue: "/"), operationGeneration: 1,
                availableNodeIDs: Set(page.nodes.map(\.id))))
        try session.execute(prepared.documentCommand)
        return id
    }
    private func identity(_ document: CanonicalDocument, ids: [NodeID], revision: UInt64? = nil,
                          documentID: DocumentID? = nil, pageID: PageID? = nil, generation: UInt64 = 1,
                          sceneID: CanvasViewportSceneID? = nil) -> ImageInspectorOperationIdentity {
        .init(documentID: documentID ?? document.id, pageID: pageID ?? document.pages[0].id,
            revision: revision ?? document.revision, sceneID: sceneID ?? scene,
            rendererGeneration: generation, selectedNodeIDs: ids)
    }
    private func context(_ document: CanonicalDocument, ids: [NodeID], available: Set<NodeID>? = nil) -> TransformValidationContext {
        .init(activePageID: document.pages[0].id, currentSceneID: scene, rendererGeneration: 1,
            selectedNodeIDs: ids, availableNodeIDs: available ?? Set(document.pages[0].nodes.map(\.id)),
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
    }
    @discardableResult private func edit(_ edit: LinkInspectorEdit, session: DocumentSession, ids: [NodeID]) throws -> PreparedImageInspectorEdit {
        let prepared = try LinkInspectorCommandRegistry().prepare(edit, identity: identity(session.document, ids: ids),
            in: session.document, context: context(session.document, ids: ids))
        try session.execute(prepared.command)
        return prepared
    }
    private func node(_ id: NodeID, _ session: DocumentSession) throws -> DocumentNode {
        try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == id })
    }

    // SF-0806-001/004, SF-1102-001/004: one closed versioned intent codec.
    func testStrictControlCodecDefaultsMalformedTargetsAndLegacyMigration() throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let id = try insert(.button, in: session)
        let button = try node(id, session)
        XCTAssertEqual(button.controlLabel, "Button")
        XCTAssertEqual(button.insertionGeometry?.size, .init(width: 160, height: 44))
        XCTAssertEqual(button.controlContext, .same)
        XCTAssertEqual(button.insertionProperty(CanonicalLinkTarget.labelKey)?.origin, .defaulted)
        XCTAssertEqual(try CanonicalLinkTarget.resolve(button), .none)
        for url in ["https://example.com/path?q=ok#section", "http://localhost:8080/", "HTTPS://example.com"] {
            XCTAssertTrue(CanonicalLinkTarget.validateExternal(url), url)
        }
        for url in ["", "javascript:alert(1)", "file:///tmp/private", "data:text/html,x", "//example.com", "https://", "https://u:p@example.com", "https://example.com:70000", "https://example.com/\n", " https://example.com", "https:\\example.com"] {
            XCTAssertFalse(CanonicalLinkTarget.validateExternal(url), url)
        }
        for property in [
            NodeProperty(key: .init(rawValue: "interaction.link.v2.kind"), value: .string("none")),
            .init(key: .init(rawValue: "interaction.link.v1.url"), value: .number(3)),
            .init(key: .init(rawValue: "content.control.v2.label"), value: .string("bad")),
        ] {
            var invalid = button; invalid.properties.append(property)
            XCTAssertThrowsError(try CanonicalLinkTarget.validate(invalid))
        }
        for value in [PropertyValue.number(1), .string("bad\nlabel"), .string(String(repeating: "x", count: 4097))] {
            var invalid = button
            let i = invalid.properties.firstIndex { $0.key.rawValue == CanonicalLinkTarget.labelKey }!
            invalid.properties[i] = .init(id: invalid.properties[i].id, key: .init(rawValue: CanonicalLinkTarget.labelKey), value: value)
            XCTAssertThrowsError(try CanonicalLinkTarget.validate(invalid))
        }
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)
        let oldWithNewKinds = String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":6", with: "\"schemaVersion\":5")
        XCTAssertThrowsError(try DocumentSerializer.decode(Data(oldWithNewKinds.utf8)))
        let old = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/Legacy/schema-v5-blank-document.json"))
        let migrated = try DocumentSerializer.decode(old)
        XCTAssertEqual(migrated.pages.map(\.name), ["Home", "Not Found"])
        XCTAssertFalse(migrated.pages.flatMap(\.nodes).contains { $0.kind.isLinkControl })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(migrated)), migrated)
    }

    // SF-0806-002/005, SF-1102-002/005: reset removes authored values, exact inverse retains property identity.
    func testControlAtomicHistoryResetMixedSubsetAndPackageRoundTrip() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let button = try insert(.button, in: session), link = try insert(.link, in: session)
        let root = session.document.pages[0].rootNodeIDs[0]
        let original = try node(button, session)
        let prepared = try edit(.label("Read more"), session: session, ids: [button, root, link])
        XCTAssertEqual(prepared.applicableNodeIDs, [button, link]); XCTAssertEqual(prepared.skippedNodeIDs, [root])
        XCTAssertEqual(try node(button, session).controlLabel, "Read more")
        try session.undo(); XCTAssertEqual(try node(button, session).properties, original.properties)
        try session.redo()
        let prior = try node(button, session)
        try edit(.target(.external("https://example.com/guide")), session: session, ids: [button])
        try edit(.context(.new), session: session, ids: [button])
        try session.undo(); XCTAssertEqual(try node(button, session).controlContext, .same)
        XCTAssertEqual(try CanonicalLinkTarget.resolve(node(button, session)), .external("https://example.com/guide"))
        try session.undo(); XCTAssertEqual(try node(button, session).properties, prior.properties)
        try session.redo(); try session.redo()
        let authored = try node(button, session)
        try edit(.target(nil), session: session, ids: [button])
        XCTAssertNil(try node(button, session).insertionProperty(CanonicalLinkTarget.namespace + "kind"))
        try session.undo(); XCTAssertEqual(try node(button, session).properties, authored.properties)
        try edit(.label(nil), session: session, ids: [button])
        XCTAssertFalse(session.canRedo)
        XCTAssertNil(try node(button, session).insertionProperty(CanonicalLinkTarget.labelKey))
        XCTAssertEqual(try node(button, session).controlLabel, "Button")
        let timestamp = ProjectTimestamp(date: Date(timeIntervalSince1970: 1))
        let package = ProjectPackage(createdAt: timestamp, document: session.document)
        let store = ProjectPackageStore()
        let reopened = try await store.decode(store.encode(package))
        XCTAssertEqual(reopened.document, session.document)
        XCTAssertEqual(reopened.document.pages[0].nodes.first { $0.id == button }?.controlContext, .new)
        let recovery = try await PersistedHistoryStore().package(package, with: session.historySnapshot())
        let recoveryBytes = try await store.encode(recovery)
        let repeatedRecoveryBytes = try await store.encode(recovery)
        XCTAssertEqual(recoveryBytes, repeatedRecoveryBytes)
        let restored = try await store.decode(recoveryBytes)
        let historyResult = try await PersistedHistoryStore().load(from: restored)
        guard case .restored(let history) = historyResult else {
            return XCTFail("Control history must survive recovery packaging: \(historyResult)")
        }
        let recovered = DocumentSession(document: restored.document)
        try recovered.installValidatedHistory(history)
        try recovered.undo()
        XCTAssertEqual(try node(button, recovered).properties, authored.properties)
        try recovered.redo()
        XCTAssertEqual(recovered.document.pages, session.document.pages)
    }

    // SF-0806-004, SF-1102-004: every stale/draft failure remains mutation-neutral.
    func testControlRegistryRejectsStaleCancelledLockedAndUnavailableEdits() throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let id = try insert(.link, in: session), document = session.document
        let registry = LinkInspectorCommandRegistry(), valid = identity(document, ids: [id]), ctx = context(document, ids: [id])
        let invalidIdentities = [
            identity(document, ids: [id], revision: 0), identity(document, ids: [id], documentID: DocumentID()),
            identity(document, ids: [id], pageID: document.pages[1].id), identity(document, ids: [id], generation: 2),
            identity(document, ids: [id], sceneID: CanvasViewportSceneID()), identity(document, ids: []),
            identity(document, ids: [id, id]), identity(document, ids: [NodeID()]),
        ]
        for value in invalidIdentities { XCTAssertThrowsError(try registry.prepare(.label("changed"), identity: value, in: document, context: ctx)) }
        XCTAssertThrowsError(try registry.prepare(.label("changed"), identity: valid, in: document, context: ctx, cancelled: true))
        XCTAssertThrowsError(try registry.prepare(.target(.external("javascript:bad")), identity: valid, in: document, context: ctx))
        XCTAssertThrowsError(try registry.prepare(.label("bad\nlabel"), identity: valid, in: document, context: ctx))
        XCTAssertThrowsError(try registry.prepare(.target(.page(PageID())), identity: valid, in: document, context: ctx))
        XCTAssertThrowsError(try registry.prepare(.label("changed"), identity: valid, in: document, context: context(document, ids: [id], available: [])))
        for key in ["locked", "hidden"] {
            var modified = document
            let i = modified.pages[0].nodes.firstIndex { $0.id == id }!
            modified.pages[0].nodes[i].properties.append(.init(key: .init(rawValue: key), value: .boolean(true)))
            XCTAssertThrowsError(try registry.prepare(.label("changed"), identity: valid, in: modified, context: ctx))
        }
        XCTAssertEqual(session.document, document)
    }

    // SF-1102-003/004/005: missing targets retain identity; route changes never rewrite links.
    func testInternalTargetIdentitySurvivesRenameAndMissingSectionCanDetach() throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let id = try insert(.link, in: session), targetPage = session.document.pages[1].id
        try edit(.target(.page(targetPage)), session: session, ids: [id])
        var renamed = session.document
        renamed.pages[1].name = "Renamed destination"
        XCTAssertFalse(try CanonicalLinkTarget.resolve(node(id, session)).isMissing(in: renamed))
        var missing = session.document
        missing.pages.removeLast()
        XCTAssertTrue(try CanonicalLinkTarget.resolve(node(id, session)).isMissing(in: missing))
        XCTAssertNoThrow(try missing.validate())
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(missing)), missing)
        let missingSession = DocumentSession(document: missing)
        try edit(.target(nil), session: missingSession, ids: [id])
        XCTAssertEqual(try CanonicalLinkTarget.resolve(node(id, missingSession)), .none)
        try missingSession.undo()
        XCTAssertEqual(try CanonicalLinkTarget.resolve(node(id, missingSession)), .page(targetPage))
    }

    func testSectionTargetRemovalRetainsIntentAndUndoRepairsIt() throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let section = try insert(.section, in: session)
        let button = try insert(.button, in: session, parent: section)
        let link = try insert(.link, in: session)
        let page = session.document.pages[0].id
        let target = CanonicalLinkTarget.section(pageID: page, nodeID: section)
        try edit(.target(target), session: session, ids: [link])
        XCTAssertEqual(try node(button, session).parent, .node(section))
        try session.execute(.batch([
            .removeNode(.init(pageID: page, nodeID: button)),
            .removeNode(.init(pageID: page, nodeID: section))
        ]))
        XCTAssertTrue(try CanonicalLinkTarget.resolve(node(link, session)).isMissing(in: session.document))
        XCTAssertEqual(try CanonicalLinkTarget.resolve(node(link, session)), target)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        XCTAssertFalse(try CanonicalLinkTarget.resolve(node(link, session)).isMissing(in: session.document))
        XCTAssertEqual(try node(button, session).parent, .node(section))
        XCTAssertEqual(try node(section, session).childIDs, [button])
    }

    // SF-1102-001/006, SF-0401-003: immutable scene, selection and native text share resolved bounds.
    func testButtonAndLinkAdoptCanonicalTextGeometryAndResponsiveVisibility() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let button = try insert(.button, in: session), link = try insert(.link, in: session)
        try edit(.label("Continue"), session: session, ids: [button])
        let viewport = try CanvasViewportState(viewportSize: .init(width: 900, height: 700))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: session.document,
            activePageID: session.document.pages[0].id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        for id in [button, link] {
            let authored = try node(id, session)
            let object = try XCTUnwrap(prepared.renderScene.objects.first { $0.id == id })
            XCTAssertEqual(object.frame, authored.insertionGeometry?.frame)
            XCTAssertEqual(object.plainText, authored.controlLabel)
            XCTAssertEqual(prepared.selectionScene?.targets.first { $0.id == id }?.frame, object.frame)
            let layer = try XCTUnwrap(CanvasAuthoredTextLayerFactory.makeLayer(for: object, viewport: viewport, contentsScale: 2))
            XCTAssertEqual(layer.alignmentMode, id == button ? .center : .left)
            XCTAssertTrue(GeometryInspectorCommandRegistry.supportsFixedGeometry(authored.kind))
            XCTAssertTrue(ResponsiveVisibilityResolver.supports(authored))
        }
        let plan = try CanvasRendererCore().prepare(scene: prepared.renderScene, overlays: prepared.overlays, viewport: viewport)
        XCTAssertEqual(plan.authoredObjects.map(\.id), [button, link])
        XCTAssertEqual(Set(plan.accessibilityElements.map(\.objectID)), [button, link])
    }
}
