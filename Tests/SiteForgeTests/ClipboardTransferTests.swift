import Foundation
import XCTest
@testable import SiteForge

@MainActor
final class ClipboardTransferTests: XCTestCase {
    func testEnvelopeRoundTripIsClosedBoundedAndRejectsMalformedGraphs() throws {
        let fixture = try makeFixture()
        let identity = operationIdentity(document: fixture.document, pageID: fixture.pageID,
                                         selected: [fixture.containerID])
        let envelope = try ClipboardTransferRegistry().prepareCopy(
            identity: identity, document: fixture.document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency }
        )
        let data = try SiteForgeClipboardCodec.encode(envelope)
        XCTAssertEqual(try SiteForgeClipboardCodec.decode(data), envelope)
        XCTAssertEqual(envelope.roots, [fixture.containerID])
        XCTAssertEqual(envelope.nodes.map(\.id), [fixture.containerID, fixture.textID])
        XCTAssertThrowsError(try SiteForgeClipboardCodec.decode(Data("{}".utf8)))

        let duplicate = SiteForgeClipboardEnvelope(
            sourceDocumentID: fixture.document.id, sourcePageID: fixture.pageID,
            roots: [fixture.containerID], nodes: [envelope.nodes[0], envelope.nodes[0]]
        )
        XCTAssertThrowsError(try SiteForgeClipboardCodec.encode(duplicate))

        let orphanID = NodeID()
        let orphan = DocumentNode(
            id: orphanID, kind: .frame, name: "Orphan", parent: .node(orphanID),
            childIDs: [orphanID], properties: []
        )
        let disconnected = SiteForgeClipboardEnvelope(
            sourceDocumentID: fixture.document.id, sourcePageID: fixture.pageID,
            roots: envelope.roots, nodes: envelope.nodes + [orphan]
        )
        XCTAssertThrowsError(try SiteForgeClipboardCodec.encode(disconnected))
    }

    func testSameProjectPasteAndDuplicateRemapStableIdentityAndUndoRedoExactly() throws {
        let fixture = try makeFixture()
        let registry = ClipboardTransferRegistry()
        let identity = operationIdentity(document: fixture.document, pageID: fixture.pageID,
                                         selected: [fixture.containerID])
        let envelope = try registry.prepareCopy(identity: identity, document: fixture.document,
                                                 resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        let context = validationContext(identity, activeContainerID: fixture.rootID)
        let prepared = try registry.preparePaste(
            envelope: envelope, identity: identity, document: fixture.document,
            context: context, placement: .offset
        )
        XCTAssertEqual(prepared.insertedRootIDs.count, 1)
        XCTAssertNotEqual(prepared.insertedRootIDs[0], fixture.containerID)

        let session = DocumentSession(document: fixture.document)
        let original = session.document
        try session.execute(prepared.command)
        XCTAssertEqual(session.document.pages[0].nodes.count, original.pages[0].nodes.count + 2)
        let inserted = try XCTUnwrap(session.document.pages[0].nodes.first(where: {
            $0.id == prepared.insertedRootIDs[0]
        }))
        XCTAssertEqual(inserted.insertionNumberProperty("layout.x"), 60)
        XCTAssertEqual(inserted.childIDs.count, 1)
        XCTAssertNotEqual(inserted.properties.map(\.id), fixture.document.pages[0].nodes[1].properties.map(\.id))
        try session.undo()
        XCTAssertEqual(session.document.pages, original.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.count, original.pages[0].nodes.count + 2)
    }

    func testPasteInPlacePreservesRelativeGeometryAndCutRemovalIsOneAtomicBatch() throws {
        let fixture = try makeFixture()
        let registry = ClipboardTransferRegistry()
        let identity = operationIdentity(document: fixture.document, pageID: fixture.pageID,
                                         selected: [fixture.containerID, fixture.textID])
        let envelope = try registry.prepareCopy(identity: identity, document: fixture.document,
                                                 resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(envelope.roots, [fixture.containerID])
        let prepared = try registry.preparePaste(
            envelope: envelope, identity: identity, document: fixture.document,
            context: validationContext(identity, activeContainerID: fixture.rootID), placement: .inPlace
        )
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared.command)
        let insertedID = try XCTUnwrap(prepared.insertedRootIDs.first)
        let pasted = try XCTUnwrap(session.document.pages[0].nodes.first(where: {
            $0.id == insertedID
        }))
        XCTAssertEqual(pasted.insertionNumberProperty("layout.x"), 40)

        let removal = try registry.prepareCutRemoval(
            envelope: envelope, identity: identity, document: fixture.document,
            context: validationContext(identity, activeContainerID: fixture.rootID)
        )
        let cutSession = DocumentSession(document: fixture.document)
        try cutSession.execute(removal)
        XCTAssertFalse(cutSession.document.pages[0].nodes.contains { $0.id == fixture.containerID })
        try cutSession.undo()
        XCTAssertEqual(cutSession.document.pages, fixture.document.pages)
    }

    func testCrossProjectTransferDeduplicatesAssetsImportsTokensAndPreservesReferences() throws {
        var fixture = try makeFixture()
        let bytes = Data("bounded-image-resource".utf8)
        let hash = ProjectResourceStore.digest(bytes)
        let resourceID = ResourceID(), assetID = AssetID(), tokenID = ColorTokenID()
        let asset = ImageAsset(
            id: assetID, resourceID: resourceID, displayName: "Hero", originalFilename: "hero.png",
            format: .png, pixelWidth: 10, pixelHeight: 10, byteCount: bytes.count, contentHash: hash
        )
        let token = LocalColorToken(
            id: tokenID, name: "Brand", color: .init(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        )
        fixture.document.imageAssets = [asset]
        fixture.document.colorTokens = [token]
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)),
            value: .string(tokenID.description)
        ))
        let image = DocumentNode(
            kind: .image, name: "Image", parent: .node(fixture.rootID), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(0)),
                .init(key: .init(rawValue: "layout.y"), value: .number(0)),
                .init(key: .init(rawValue: "layout.width"), value: .number(100)),
                .init(key: .init(rawValue: "layout.height"), value: .number(100)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"), value: .string(assetID.description)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string(ImageFitMode.fit.rawValue)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.5)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.5)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string("")),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(true)),
            ]
        )
        fixture.document.pages[0].nodes.append(image)
        fixture.document.pages[0].nodes[0].childIDs.append(image.id)
        try fixture.document.validate()
        let identity = operationIdentity(
            document: fixture.document, pageID: fixture.pageID,
            selected: [fixture.containerID, image.id]
        )
        let descriptor = ProjectResourceDescriptor(
            id: resourceID, filename: "hero.png", mediaType: "image/png", byteCount: bytes.count, sha256: hash
        )
        let envelope = try ClipboardTransferRegistry().prepareCopy(
            identity: identity, document: fixture.document,
            resourceData: { _ in (descriptor, bytes) }
        )

        let destination = CanonicalDocument()
        let targetPage = destination.pages[0]
        let targetIdentity = operationIdentity(document: destination, pageID: targetPage.id, selected: [])
        let prepared = try ClipboardTransferRegistry().preparePaste(
            envelope: envelope, identity: targetIdentity, document: destination,
            context: validationContext(targetIdentity, activeContainerID: targetPage.rootNodeIDs[0]),
            placement: .inPlace
        )
        XCTAssertEqual(prepared.resources.count, 1)
        let session = DocumentSession(document: destination)
        try session.execute(prepared.command)
        XCTAssertEqual(session.document.imageAssets.count, 1)
        let pasted = try XCTUnwrap(session.document.pages[0].nodes.first(where: {
            prepared.insertedRootIDs.contains($0.id) && $0.kind == .image
        }))
        XCTAssertEqual(CanonicalImageStyle.resolve(pasted)?.assetID, session.document.imageAssets[0].id)
        XCTAssertEqual(session.document.colorTokens.count, 1)
        let pastedFrame = try XCTUnwrap(session.document.pages[0].nodes.first(where: {
            prepared.insertedRootIDs.contains($0.id) && $0.kind == .frame && $0.name == "Card"
        }))
        XCTAssertEqual(LocalColorTokenBinding.id(for: pastedFrame), session.document.colorTokens[0].id)
    }

    func testStaleCancelledMalformedAndCrossProjectComponentInputsAreNeutral() throws {
        let fixture = try makeFixture()
        let registry = ClipboardTransferRegistry()
        let identity = operationIdentity(document: fixture.document, pageID: fixture.pageID,
                                         selected: [fixture.containerID])
        XCTAssertThrowsError(try registry.prepareCopy(
            identity: identity, document: fixture.document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency }, cancelled: true
        )) { XCTAssertEqual($0 as? ClipboardTransferError, .cancelled) }
        let envelope = try registry.prepareCopy(identity: identity, document: fixture.document,
                                                 resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        var stale = identity
        stale = .init(documentID: stale.documentID, pageID: stale.pageID, revision: stale.revision + 1,
                      sceneID: stale.sceneID, rendererGeneration: stale.rendererGeneration,
                      selectedNodeIDs: stale.selectedNodeIDs)
        XCTAssertThrowsError(try registry.preparePaste(
            envelope: envelope, identity: stale, document: fixture.document,
            context: validationContext(identity, activeContainerID: fixture.rootID), placement: .offset
        )) { XCTAssertEqual($0 as? ClipboardTransferError, .stale) }

        let component = DocumentNode(
            kind: .component, name: "Component", parent: .page(envelope.sourcePageID),
            properties: [.init(key: .init(rawValue: CanonicalComponentReference.key),
                               value: .string(PageID().description))]
        )
        let componentEnvelope = SiteForgeClipboardEnvelope(
            sourceDocumentID: DocumentID(), sourcePageID: envelope.sourcePageID,
            roots: [component.id], nodes: [component]
        )
        XCTAssertThrowsError(try registry.preparePaste(
            envelope: componentEnvelope, identity: identity, document: fixture.document,
            context: validationContext(identity, activeContainerID: fixture.rootID), placement: .offset
        )) { XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedComponentDependency) }

        var lockedDestination = fixture.document
        lockedDestination.pages[0].nodes[0].properties.append(.init(
            key: .init(rawValue: "locked"), value: .boolean(true)
        ))
        let lockedIdentity = operationIdentity(
            document: lockedDestination, pageID: fixture.pageID, selected: [fixture.containerID]
        )
        XCTAssertThrowsError(try registry.preparePaste(
            envelope: envelope, identity: lockedIdentity, document: lockedDestination,
            context: validationContext(lockedIdentity, activeContainerID: fixture.rootID), placement: .offset
        )) { XCTAssertEqual($0 as? ClipboardTransferError, .invalidTarget) }

        let externalNodeLink = DocumentNode(
            kind: .link, name: "External Section", parent: .page(envelope.sourcePageID), properties: [
                .init(key: .init(rawValue: CanonicalLinkTarget.namespace + "kind"), value: .string("section")),
                .init(key: .init(rawValue: CanonicalLinkTarget.namespace + "pageID"), value: .string(envelope.sourcePageID.description)),
                .init(key: .init(rawValue: CanonicalLinkTarget.namespace + "nodeID"), value: .string(NodeID().description)),
            ]
        )
        let externalLinkEnvelope = SiteForgeClipboardEnvelope(
            sourceDocumentID: DocumentID(), sourcePageID: envelope.sourcePageID,
            roots: [externalNodeLink.id], nodes: [externalNodeLink]
        )
        XCTAssertThrowsError(try registry.preparePaste(
            envelope: externalLinkEnvelope, identity: identity, document: fixture.document,
            context: validationContext(identity, activeContainerID: fixture.rootID), placement: .offset
        )) { XCTAssertEqual($0 as? ClipboardTransferError, .invalidDependency) }

        let sanitized = ClipboardDiagnosticSanitizer.identifiers(for: [fixture.containerID])
        XCTAssertEqual(sanitized.count, 1)
        XCTAssertEqual(sanitized[0].count, 16)
        XCTAssertFalse(sanitized[0].contains(fixture.containerID.description))
    }

    private struct Fixture {
        var document: CanonicalDocument
        let pageID: PageID
        let rootID: NodeID
        let containerID: NodeID
        let textID: NodeID
    }

    private func makeFixture() throws -> Fixture {
        var document = CanonicalDocument()
        let pageID = document.pages[0].id, rootID = document.pages[0].rootNodeIDs[0]
        let containerID = NodeID(), textID = NodeID()
        let geometry: (Double, Double, Double, Double) = (40, 60, 240, 160)
        let container = DocumentNode(
            id: containerID, kind: .frame, name: "Card", parent: .node(rootID), childIDs: [textID],
            properties: geometryProperties(geometry)
        )
        let text = DocumentNode(
            id: textID, kind: .text, name: "Label", parent: .node(containerID),
            properties: geometryProperties((10, 12, 120, 24)) + [
                .init(key: .init(rawValue: "content.text"), value: .string("Clipboard fixture"))
            ]
        )
        document.pages[0].nodes[0].childIDs = [containerID]
        document.pages[0].nodes.append(contentsOf: [container, text])
        try document.validate()
        return .init(document: document, pageID: pageID, rootID: rootID,
                     containerID: containerID, textID: textID)
    }

    private func geometryProperties(_ value: (Double, Double, Double, Double)) -> [NodeProperty] {
        zip(["layout.x", "layout.y", "layout.width", "layout.height"],
            [value.0, value.1, value.2, value.3]).map {
            .init(key: .init(rawValue: $0.0), value: .number($0.1))
        }
    }

    private func operationIdentity(document: CanonicalDocument, pageID: PageID,
                                   selected: [NodeID]) -> ClipboardOperationIdentity {
        .init(documentID: document.id, pageID: pageID, revision: document.revision,
              sceneID: CanvasViewportSceneID(), rendererGeneration: 1, selectedNodeIDs: selected)
    }

    private func validationContext(_ identity: ClipboardOperationIdentity,
                                   activeContainerID: NodeID?) -> ClipboardValidationContext {
        .init(liveIdentity: identity, activeContainerID: activeContainerID,
              lifecycleAvailable: true, disabledReason: nil)
    }
}
