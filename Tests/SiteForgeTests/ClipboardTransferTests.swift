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
        let resourceID = ResourceID(), assetID = AssetID(), tokenID = ColorTokenID(), styleID = ReusableStyleID()
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
        fixture.document.pages[0].nodes[1].properties.append(.init(
            key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description)
        ))
        let stylePrefix = CanonicalReusableStyleIndex.namespace + "definition.\(styleID.description)."
        fixture.document.pages[0].nodes[0].properties += [
            .init(key: .init(rawValue: stylePrefix + "name"), value: .string("Card Surface"), origin: .authored),
            .init(key: .init(rawValue: stylePrefix + "fill"), value: .string("#336699FF"), origin: .authored),
        ]
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
        let styleIndex = try CanonicalReusableStyleIndex(document: session.document)
        let appliedStyle = try XCTUnwrap(CanonicalReusableStyleIndex.appliedIDs(pastedFrame).first)
        XCTAssertEqual(styleIndex.byID[appliedStyle]?.name, "Card Surface")
    }

    func testCrossProjectComponentDefinitionImportsAtomicallyAndPreservesExactHistory() throws {
        var source = CanonicalDocument()
        let component = try addComponent(named: "Feature Card", text: "Source value", to: &source)
        let identity = operationIdentity(document: source, pageID: source.pages[0].id,
                                         selected: [component.instanceID])
        let envelope = try ClipboardTransferRegistry().prepareCopy(
            identity: identity, document: source,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency }
        )
        XCTAssertEqual(envelope.componentDefinitions.map(\.id), [component.definitionID])

        let destination = CanonicalDocument()
        let target = destination.pages[0]
        let targetIdentity = operationIdentity(document: destination, pageID: target.id, selected: [])
        let prepared = try ClipboardTransferRegistry().preparePaste(
            envelope: envelope, identity: targetIdentity, document: destination,
            context: validationContext(targetIdentity, activeContainerID: target.rootNodeIDs[0]),
            placement: .inPlace
        )
        XCTAssertEqual(prepared.componentSummary?.entries.map(\.resolution), [.imported])
        let session = DocumentSession(document: destination)
        try session.execute(prepared.command)
        let imported = try XCTUnwrap(session.document.componentDefinitions.first)
        let pasted = try XCTUnwrap(session.document.pages[0].nodes.first(where: {
            prepared.insertedRootIDs.contains($0.id)
        }))
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: pasted), imported.id)
        XCTAssertNotEqual(imported.id, component.definitionID)
        XCTAssertEqual(CanonicalComponentText.overrides(on: pasted).values.first, "Instance value")
        let committed = session.document
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(committed)), committed)
        try session.undo()
        XCTAssertTrue(session.document.componentDefinitions.isEmpty)
        XCTAssertEqual(session.document.pages, destination.pages)
        try session.redo()
        var expectedCommitted = committed
        expectedCommitted.revision = session.document.revision
        XCTAssertEqual(session.document, expectedCommitted)
    }

    private func addActionComponent(to document: inout CanonicalDocument,
                                    defaultTarget: CanonicalLinkTarget = .none,
                                    overrideTarget: CanonicalLinkTarget = .external("https://example.com/instance")) throws -> (ComponentFixture, ComponentActionPropertyID) {
        let component = try addComponent(named: "Action Card", text: "Action", to: &document)
        let definitionIndex = try XCTUnwrap(document.pages.firstIndex { $0.id == component.definitionID })
        let id = ComponentActionPropertyID()
        document.pages[definitionIndex].nodes[1].kind = .link
        document.pages[definitionIndex].nodes[1].properties.removeAll {
            $0.key.rawValue == "content.text" || CanonicalComponentText.metadataKeys.contains($0.key.rawValue)
        }
        document.pages[definitionIndex].nodes[1].properties += [
            .init(key: .init(rawValue: CanonicalComponentAction.namespace + "id"), value: .string(id.description), origin: .authored),
            .init(key: .init(rawValue: CanonicalComponentAction.namespace + "label"), value: .string("Destination"), origin: .authored),
            .init(key: .init(rawValue: CanonicalComponentAction.namespace + "type"), value: .string("link-target"), origin: .authored),
        ] + defaultTarget.properties.map { .init(key: .init(rawValue: $0.0), value: $0.1, origin: .authored) }
        let instanceIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == component.instanceID })
        document.pages[0].nodes[instanceIndex].properties.removeAll { CanonicalComponentText.overrideID($0.key.rawValue) != nil }
        document.pages[0].nodes[instanceIndex].properties.append(.init(key: .init(rawValue: CanonicalComponentAction.overrideKey(id)),
            value: .string(CanonicalComponentAction.encode(overrideTarget)), origin: .authored))
        try document.validate()
        return (component, id)
    }

    func testComponentActionTransferReusesEquivalentBindingAndKeepsExactOverrideHistory() throws {
        var source = CanonicalDocument(), destination = CanonicalDocument()
        let (sourceComponent, sourceBinding) = try addActionComponent(to: &source)
        let (destinationComponent, destinationBinding) = try addActionComponent(to: &destination)
        let registry = ClipboardTransferRegistry()
        let sourceIdentity = operationIdentity(document: source, pageID: source.pages[0].id, selected: [sourceComponent.instanceID])
        let envelope = try registry.prepareCopy(identity: sourceIdentity, document: source, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(try SiteForgeClipboardCodec.decode(SiteForgeClipboardCodec.encode(envelope)), envelope)
        let identity = operationIdentity(document: destination, pageID: destination.pages[0].id, selected: [])
        let prepared = try registry.preparePaste(envelope: envelope, identity: identity, document: destination,
            context: validationContext(identity, activeContainerID: destination.pages[0].rootNodeIDs[0]), placement: .inPlace)
        XCTAssertEqual(prepared.componentSummary?.entries.map(\.resolution), [.reused])
        let session = DocumentSession(document: destination)
        try session.execute(prepared.command)
        let instance = try XCTUnwrap(session.document.pages[0].nodes.first { prepared.insertedRootIDs.contains($0.id) })
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: instance), destinationComponent.definitionID)
        XCTAssertNotEqual(sourceBinding, destinationBinding)
        XCTAssertEqual(CanonicalComponentAction.overrides(on: instance)[destinationBinding], .external("https://example.com/instance"))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let properties = instance.properties
        try session.undo(); XCTAssertEqual(session.document.pages, destination.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == instance.id }?.properties, properties)
    }

    func testComponentActionTransferRejectsUnmappedPageIntentWithoutMutationOrDiagnosticsDisclosure() throws {
        var source = CanonicalDocument()
        // A valid source target outside the copied page tests remapping. A
        // fabricated missing PageID is correctly rejected earlier at Copy.
        let targetPageID = source.pages[1].id
        let (component, _) = try addActionComponent(to: &source, overrideTarget: .page(targetPageID))
        let registry = ClipboardTransferRegistry()
        let sourceIdentity = operationIdentity(document: source, pageID: source.pages[0].id, selected: [component.instanceID])
        let envelope = try registry.prepareCopy(identity: sourceIdentity, document: source, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        let destination = CanonicalDocument()
        let identity = operationIdentity(document: destination, pageID: destination.pages[0].id, selected: [])
        XCTAssertThrowsError(try registry.preparePaste(envelope: envelope, identity: identity, document: destination,
            context: validationContext(identity, activeContainerID: destination.pages[0].rootNodeIDs[0]), placement: .inPlace)) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unmappedActionDestination)
        }
        XCTAssertTrue(destination.componentDefinitions.isEmpty)
        XCTAssertEqual(ClipboardTransferError.unmappedActionDestination.diagnosticCategory, "unmapped-action-destination")
        XCTAssertFalse(ClipboardTransferError.unmappedActionDestination.localizedDescription.contains(source.id.description))
    }

    func testComponentActionTransferRemapsCopiedSectionAndNeverReusesDifferentDefault() throws {
        var source = CanonicalDocument()
        let sectionID = NodeID(), pageID = source.pages[0].id, rootID = source.pages[0].rootNodeIDs[0]
        let section = DocumentNode(id: sectionID, kind: .section, name: "Destination", parent: .node(rootID),
            properties: geometryProperties((0, 0, 960, 320)) + [
                .init(key: .init(rawValue: "layout.container.kind"), value: .string("section"), origin: .defaulted),
                .init(key: .init(rawValue: "layout.padding"), value: .number(48), origin: .defaulted),
                .init(key: .init(rawValue: "layout.axis"), value: .string("vertical"), origin: .defaulted)])
        source.pages[0].nodes.append(section); source.pages[0].nodes[0].childIDs.append(sectionID)
        let (component, _) = try addActionComponent(to: &source, overrideTarget: .section(pageID: pageID, nodeID: sectionID))
        let registry = ClipboardTransferRegistry()
        let sourceIdentity = operationIdentity(document: source, pageID: pageID, selected: [component.instanceID, sectionID])
        let envelope = try registry.prepareCopy(identity: sourceIdentity, document: source, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        var destination = CanonicalDocument()
        _ = try addActionComponent(to: &destination, defaultTarget: .external("https://example.com/different-default"))
        let identity = operationIdentity(document: destination, pageID: destination.pages[0].id, selected: [])
        let prepared = try registry.preparePaste(envelope: envelope, identity: identity, document: destination,
            context: validationContext(identity, activeContainerID: destination.pages[0].rootNodeIDs[0]), placement: .inPlace)
        XCTAssertEqual(prepared.componentSummary?.entries.map(\.resolution), [.renamed])
        let session = DocumentSession(document: destination)
        try session.execute(prepared.command)
        let importedInstance = try XCTUnwrap(session.document.pages[0].nodes.first { prepared.insertedRootIDs.contains($0.id) && $0.kind == .component })
        let importedSection = try XCTUnwrap(session.document.pages[0].nodes.first { prepared.insertedRootIDs.contains($0.id) && $0.kind == .section })
        XCTAssertEqual(CanonicalComponentAction.overrides(on: importedInstance).values.first,
                       .section(pageID: destination.pages[0].id, nodeID: importedSection.id))
        XCTAssertNotEqual(importedSection.id, sectionID)
    }

    private func addFallbackSlot(to document: inout CanonicalDocument) throws -> (ComponentFixture, ComponentSlotPropertyID) {
        let component = try addComponent(named: "Slot Card", text: "Fallback", to: &document)
        let definitionIndex = try XCTUnwrap(document.pages.firstIndex { $0.id == component.definitionID })
        let containerID = NodeID(), slotID = ComponentSlotPropertyID()
        let fallbackID = document.pages[definitionIndex].nodes[1].id
        document.pages[definitionIndex].nodes[0].childIDs = [containerID]
        document.pages[definitionIndex].nodes[1].parent = .node(containerID)
        let slot = DocumentNode(id: containerID, kind: .frame, name: "Slot Container",
            parent: .node(document.pages[definitionIndex].rootNodeIDs[0]), childIDs: [fallbackID],
            properties: geometryProperties((12, 12, 160, 96)) + [
                .init(key: .init(rawValue: CanonicalComponentSlot.namespace + "id"), value: .string(slotID.description), origin: .authored),
                .init(key: .init(rawValue: CanonicalComponentSlot.namespace + "label"), value: .string("Content"), origin: .authored),
                .init(key: .init(rawValue: CanonicalComponentSlot.namespace + "type"), value: .string("ordered-fallback-children"), origin: .authored)])
        document.pages[definitionIndex].nodes.append(slot)
        try document.validate()
        return (component, slotID)
    }

    func testComponentSlotFallbackTransferImportsAndReusesOwnedOrderedGraph() throws {
        var source = CanonicalDocument()
        let (component, slotID) = try addFallbackSlot(to: &source)
        let registry = ClipboardTransferRegistry()
        let identity = operationIdentity(document: source, pageID: source.pages[0].id, selected: [component.instanceID])
        let envelope = try registry.prepareCopy(identity: identity, document: source,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(try SiteForgeClipboardCodec.decode(SiteForgeClipboardCodec.encode(envelope)), envelope)
        let destination = CanonicalDocument()
        let target = operationIdentity(document: destination, pageID: destination.pages[0].id, selected: [])
        let importPlan = try registry.preparePaste(envelope: envelope, identity: target, document: destination,
            context: validationContext(target, activeContainerID: destination.pages[0].rootNodeIDs[0]), placement: .inPlace)
        let session = DocumentSession(document: destination)
        try session.execute(importPlan.command)
        let definition = try XCTUnwrap(session.document.componentDefinitions.first)
        let slot = try XCTUnwrap(CanonicalComponentSlot.properties(in: definition).first)
        XCTAssertNotEqual(slot.id, slotID)
        XCTAssertEqual(slot.defaultChildIDs.count, 1)
        XCTAssertEqual(definition.nodes.first { $0.id == slot.defaultChildIDs[0] }?.parent, .node(slot.sourceNodeID))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let committed = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, destination.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, committed)
        var equivalent = CanonicalDocument()
        let (_, equivalentSlotID) = try addFallbackSlot(to: &equivalent)
        let equivalentIdentity = operationIdentity(document: equivalent, pageID: equivalent.pages[0].id, selected: [])
        let reused = try registry.preparePaste(envelope: envelope, identity: equivalentIdentity, document: equivalent,
            context: validationContext(equivalentIdentity, activeContainerID: equivalent.pages[0].rootNodeIDs[0]), placement: .inPlace)
        XCTAssertEqual(reused.componentSummary?.entries.map(\.resolution), [.reused])
        let reusedSession = DocumentSession(document: equivalent)
        try reusedSession.execute(reused.command)
        XCTAssertEqual(CanonicalComponentSlot.properties(in: reusedSession.document.componentDefinitions[0]).first?.id, equivalentSlotID)
    }

    func testComponentPropertyOrganizationTransferRemapsBindingsAndPreservesGroupsOrder() throws {
        var source = CanonicalDocument()
        let (component, _) = try addFallbackSlot(to: &source)
        let di = try XCTUnwrap(source.pages.firstIndex { $0.id == component.definitionID })
        let entries = CanonicalComponentOrganization.entries(in: source.pages[di])
        for (rank, entry) in entries.enumerated() {
            let ni = try XCTUnwrap(source.pages[di].nodes.firstIndex { $0.id == entry.sourceNodeID })
            source.pages[di].nodes[ni].properties += [
                .init(key: .init(rawValue: CanonicalComponentOrganization.key(entry.id.organizationKind, "binding")), value: .string(entry.id.stableDescription), origin: .authored),
                .init(key: .init(rawValue: CanonicalComponentOrganization.key(entry.id.organizationKind, "group")), value: .string("Content"), origin: .authored),
                .init(key: .init(rawValue: CanonicalComponentOrganization.key(entry.id.organizationKind, "order")), value: .number(Double(rank)), origin: .authored)]
        }
        try source.validate()
        let registry = ClipboardTransferRegistry()
        let envelope = try registry.prepareCopy(identity: operationIdentity(document: source, pageID: source.pages[0].id,
            selected: [component.instanceID]), document: source, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        let destination = CanonicalDocument()
        let target = operationIdentity(document: destination, pageID: destination.pages[0].id, selected: [])
        let plan = try registry.preparePaste(envelope: envelope, identity: target, document: destination,
            context: validationContext(target, activeContainerID: destination.pages[0].rootNodeIDs[0]), placement: .inPlace)
        let session = DocumentSession(document: destination)
        try session.execute(plan.command)
        let imported = CanonicalComponentOrganization.entries(in: session.document.componentDefinitions[0])
        XCTAssertEqual(imported.map(\.label), entries.map(\.label))
        XCTAssertEqual(imported.compactMap(\.rank), Array(entries.indices))
        XCTAssertTrue(imported.allSatisfy { $0.group == "Content" })
        XCTAssertTrue(Set(imported.map(\.id)).isDisjoint(with: entries.map(\.id)))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo(); XCTAssertEqual(session.document.pages, destination.pages)
        try session.redo(); XCTAssertEqual(CanonicalComponentOrganization.entries(in: session.document.componentDefinitions[0]), imported)
    }

    func testRetainedComponentConflictCopyPastePreflightIsRedactedAndNeutral() throws {
        var document = CanonicalDocument()
        let fixture = try addComponent(named: "Card", text: "Retained private transfer intent", to: &document)
        let registry = ClipboardTransferRegistry()
        let selected = operationIdentity(document: document, pageID: document.pages[0].id, selected: [fixture.instanceID])
        let valid = try registry.prepareCopy(identity: selected, document: document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        let di = try XCTUnwrap(document.pages.firstIndex { $0.id == fixture.definitionID })
        for ni in document.pages[di].nodes.indices {
            document.pages[di].nodes[ni].properties.removeAll { CanonicalComponentText.metadataKeys.contains($0.key.rawValue) }
        }
        try document.validate()
        let unchanged = document
        let sameProject = operationIdentity(document: document, pageID: document.pages[0].id, selected: [])
        XCTAssertThrowsError(try registry.preparePaste(envelope: valid, identity: sameProject, document: document,
            context: validationContext(sameProject, activeContainerID: document.pages[0].rootNodeIDs[0]), placement: .inPlace)) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unresolvedComponentOverride,
                "An old valid clipboard snapshot cannot bypass a now-unavailable live same-project binding")
        }
        XCTAssertThrowsError(try registry.prepareCopy(identity: operationIdentity(document: document,
            pageID: document.pages[0].id, selected: [fixture.instanceID]), document: document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })) { error in
            XCTAssertEqual(error as? ClipboardTransferError, .unresolvedComponentOverride)
            XCTAssertEqual((error as? ClipboardTransferError)?.diagnosticCategory, "component-override-conflict")
            XCTAssertFalse(error.localizedDescription.contains(fixture.instanceID.description))
        }
        // A foreign envelope must not bypass the same retained-binding finding.
        // Rebuild through the public immutable envelope initializer below.
        let envelope = SiteForgeClipboardEnvelope(sourceDocumentID: valid.sourceDocumentID, sourcePageID: valid.sourcePageID,
            roots: valid.roots, nodes: valid.nodes,
            imageDependencies: valid.imageDependencies, colorTokenDependencies: valid.colorTokenDependencies,
            reusableStyleDependencies: valid.reusableStyleDependencies, componentDefinitions: document.componentDefinitions)
        let target = CanonicalDocument()
        let targetID = operationIdentity(document: target, pageID: target.pages[0].id, selected: [])
        XCTAssertThrowsError(try registry.preparePaste(envelope: envelope, identity: targetID, document: target,
            context: validationContext(targetID, activeContainerID: target.pages[0].rootNodeIDs[0]), placement: .inPlace)) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unresolvedComponentOverride)
        }
        XCTAssertEqual(document, unchanged)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
    }

    func testComponentSlotTransferRejectsUnsupportedSupplyBeforeMutation() throws {
        var source = CanonicalDocument()
        let (component, slotID) = try addFallbackSlot(to: &source)
        let index = try XCTUnwrap(source.pages[0].nodes.firstIndex { $0.id == component.instanceID })
        var supplied = source.pages[0].nodes[index]
        supplied.parent = .page(source.pages[0].id)
        supplied.properties.append(.init(key: .init(rawValue: CanonicalComponentSlot.unsupportedOverrideNamespace + slotID.description),
            value: .string("unsupported subtree intent"), origin: .authored))
        let envelope = SiteForgeClipboardEnvelope(sourceDocumentID: source.id, sourcePageID: source.pages[0].id,
            roots: [component.instanceID], nodes: [supplied], componentDefinitions: source.componentDefinitions)
        XCTAssertThrowsError(try SiteForgeClipboardCodec.encode(envelope)) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedSlotContent)
        }
        XCTAssertEqual(ClipboardTransferError.unsupportedSlotContent.diagnosticCategory, "unsupported-slot-content")
        XCTAssertFalse(ClipboardTransferError.unsupportedSlotContent.localizedDescription.contains("unsupported subtree intent"))
        XCTAssertEqual(source.pages[0].nodes[index].properties.count + 1, supplied.properties.count)
    }

    func testCrossProjectComponentReuseAndSameNameConflictUseStructuralIdentity() throws {
        var source = CanonicalDocument()
        let sourceComponent = try addComponent(named: "Card", text: "Shared", to: &source)
        let identity = operationIdentity(document: source, pageID: source.pages[0].id,
                                         selected: [sourceComponent.instanceID])
        let envelope = try ClipboardTransferRegistry().prepareCopy(
            identity: identity, document: source,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency }
        )

        var equivalent = CanonicalDocument()
        let destinationComponent = try addComponent(named: "Card", text: "Shared", to: &equivalent)
        equivalent.pages[0].nodes.removeAll { $0.id == destinationComponent.instanceID }
        equivalent.pages[0].nodes[0].childIDs.removeAll { $0 == destinationComponent.instanceID }
        try equivalent.validate()
        let equivalentIdentity = operationIdentity(document: equivalent, pageID: equivalent.pages[0].id, selected: [])
        let reused = try ClipboardTransferRegistry().preparePaste(
            envelope: envelope, identity: equivalentIdentity, document: equivalent,
            context: validationContext(equivalentIdentity, activeContainerID: equivalent.pages[0].rootNodeIDs[0]),
            placement: .inPlace
        )
        XCTAssertEqual(reused.componentSummary?.entries.map(\.resolution), [.reused])
        let reusedSession = DocumentSession(document: equivalent)
        try reusedSession.execute(reused.command)
        XCTAssertEqual(reusedSession.document.componentDefinitions.count, 1)
        let reusedInstance = try XCTUnwrap(reusedSession.document.pages[0].nodes.first(where: {
            reused.insertedRootIDs.contains($0.id)
        }))
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: reusedInstance), destinationComponent.definitionID)
        XCTAssertEqual(CanonicalComponentText.overrides(on: reusedInstance).keys.first,
                       destinationComponent.textPropertyID)

        var conflicting = CanonicalDocument()
        let conflict = try addComponent(named: "Card", text: "Different", to: &conflicting)
        conflicting.pages[0].nodes.removeAll { $0.id == conflict.instanceID }
        conflicting.pages[0].nodes[0].childIDs.removeAll { $0 == conflict.instanceID }
        try conflicting.validate()
        let conflictIdentity = operationIdentity(document: conflicting, pageID: conflicting.pages[0].id, selected: [])
        let renamed = try ClipboardTransferRegistry().preparePaste(
            envelope: envelope, identity: conflictIdentity, document: conflicting,
            context: validationContext(conflictIdentity, activeContainerID: conflicting.pages[0].rootNodeIDs[0]),
            placement: .inPlace
        )
        XCTAssertEqual(renamed.componentSummary?.entries.map(\.resolution), [.renamed])
        let renamedDefinition = try XCTUnwrap(renamed.componentSummary?.entries.first)
        XCTAssertEqual(renamedDefinition.displayName, "Card Copy 2")
        XCTAssertNotEqual(renamedDefinition.destinationDefinitionID, conflict.definitionID)
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
        )) { XCTAssertEqual($0 as? ClipboardTransferError, .invalidDependency) }

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

    func testComponentTransferRejectsCyclicDanglingAndUnsupportedVersionEnvelopes() throws {
        let sourcePageID = PageID(), firstID = PageID(), secondID = PageID()
        func definition(id: PageID, dependency: PageID) -> DocumentPage {
            let rootID = NodeID(), childID = NodeID()
            return DocumentPage(
                id: id, name: "Dependency", route: .init(rawValue: ""), role: .componentDefinition,
                provenance: .authored, rootNodeIDs: [rootID], nodes: [
                    DocumentNode(id: rootID, kind: .frame, name: "Root", parent: .page(id),
                                 childIDs: [childID], properties: geometryProperties((0, 0, 100, 100))),
                    DocumentNode(id: childID, kind: .component, name: "Nested", parent: .node(rootID),
                                 properties: geometryProperties((0, 0, 50, 50)) + [
                                    .init(key: .init(rawValue: CanonicalComponentReference.key),
                                          value: .string(dependency.description))
                                 ]),
                ]
            )
        }
        let instance = DocumentNode(kind: .component, name: "Cycle", parent: .page(sourcePageID),
            properties: geometryProperties((0, 0, 100, 100)) + [
                .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(firstID.description))
            ])
        let cycle = SiteForgeClipboardEnvelope(
            sourceDocumentID: DocumentID(), sourcePageID: sourcePageID,
            roots: [instance.id], nodes: [instance],
            componentDefinitions: [definition(id: firstID, dependency: secondID),
                                   definition(id: secondID, dependency: firstID)]
        )
        XCTAssertThrowsError(try cycle.validate()) {
            XCTAssertEqual($0 as? ClipboardTransferError, .componentCycle)
        }
        let dangling = SiteForgeClipboardEnvelope(
            sourceDocumentID: DocumentID(), sourcePageID: sourcePageID,
            roots: [instance.id], nodes: [instance]
        )
        XCTAssertThrowsError(try dangling.validate()) {
            XCTAssertEqual($0 as? ClipboardTransferError, .invalidDependency)
        }
        let unsupported = SiteForgeClipboardEnvelope(
            version: SiteForgeClipboardEnvelope.currentVersion + 1,
            sourceDocumentID: DocumentID(), sourcePageID: sourcePageID,
            roots: [instance.id], nodes: [instance], componentDefinitions: [definition(id: firstID, dependency: firstID)]
        )
        XCTAssertThrowsError(try unsupported.validate()) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedVersion)
        }
    }

    private struct Fixture {
        var document: CanonicalDocument
        let pageID: PageID
        let rootID: NodeID
        let containerID: NodeID
        let textID: NodeID
    }

    private struct ComponentFixture {
        let definitionID: PageID
        let textPropertyID: ComponentTextPropertyID
        let instanceID: NodeID
    }

    private func addComponent(named name: String, text: String,
                              to document: inout CanonicalDocument) throws -> ComponentFixture {
        let definitionID = PageID(), definitionRootID = NodeID(), definitionTextID = NodeID()
        let textPropertyID = ComponentTextPropertyID(), instanceID = NodeID()
        let definitionRoot = DocumentNode(
            id: definitionRootID, kind: .frame, name: "Root", parent: .page(definitionID),
            childIDs: [definitionTextID], properties: geometryProperties((0, 0, 240, 160))
        )
        let definitionText = DocumentNode(
            id: definitionTextID, kind: .text, name: "Label", parent: .node(definitionRootID),
            properties: geometryProperties((12, 12, 120, 24)) + [
                .init(key: .init(rawValue: "content.text"), value: .string(text)),
                .init(key: .init(rawValue: CanonicalComponentText.namespace + "id"), value: .string(textPropertyID.description), origin: .authored),
                .init(key: .init(rawValue: CanonicalComponentText.namespace + "label"), value: .string("Label"), origin: .authored),
                .init(key: .init(rawValue: CanonicalComponentText.namespace + "type"), value: .string("plain-text"), origin: .authored),
            ]
        )
        let definition = DocumentPage(
            id: definitionID, name: name, route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [definitionRootID], nodes: [definitionRoot, definitionText]
        )
        let pageID = document.pages[0].id, rootID = document.pages[0].rootNodeIDs[0]
        let instance = DocumentNode(
            id: instanceID, kind: .component, name: name, parent: .node(rootID),
            properties: geometryProperties((40, 60, 240, 160)) + [
                .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(definitionID.description)),
                .init(key: .init(rawValue: CanonicalComponentText.overrideKey(textPropertyID)),
                      value: .string("Instance value"), origin: .authored),
            ]
        )
        document.pages[0].nodes[0].childIDs.append(instanceID)
        document.pages[0].nodes.append(instance)
        document.pages.append(definition)
        try document.validate()
        XCTAssertEqual(pageID, document.pages[0].id)
        return .init(definitionID: definitionID, textPropertyID: textPropertyID, instanceID: instanceID)
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
