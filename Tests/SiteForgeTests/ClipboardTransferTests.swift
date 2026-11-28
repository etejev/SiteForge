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

    // OD-039 (lane V09): a definition whose objects have interactions matches a
    // structurally equal definition in another project, although every copy
    // has its own node and interaction identities; a different graph does not.
    func testComponentTransferReusesDefinitionWithEquivalentInteractions() throws {
        func addInteractiveCard(to document: inout CanonicalDocument, action kind: CanonicalInteraction.ActionKind) throws -> ComponentFixture {
            let component = try addComponent(named: "Card", text: "Hi", to: &document)
            let index = try XCTUnwrap(document.pages.firstIndex { $0.id == component.definitionID })
            let label = document.pages[index].nodes[1].id
            let graph = CanonicalEventGraph(interactions: [CanonicalInteraction(id: UUID(), trigger: .focusIn,
                actions: [CanonicalInteraction.Action(kind: kind, target: label)])])
            document.pages[index].nodes[0].properties += graph.properties.sorted { $0.key < $1.key }
                .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
            try document.validate()
            return component
        }
        var source = CanonicalDocument(), destination = CanonicalDocument(), different = CanonicalDocument()
        let sourceComponent = try addInteractiveCard(to: &source, action: .show)
        let destinationComponent = try addInteractiveCard(to: &destination, action: .show)
        _ = try addInteractiveCard(to: &different, action: .hide)
        let registry = ClipboardTransferRegistry()
        let envelope = try registry.prepareCopy(identity: operationIdentity(document: source, pageID: source.pages[0].id,
            selected: [sourceComponent.instanceID]), document: source, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        func paste(into document: CanonicalDocument) throws -> PreparedClipboardTransfer {
            let identity = operationIdentity(document: document, pageID: document.pages[0].id, selected: [])
            return try registry.preparePaste(envelope: envelope, identity: identity, document: document,
                context: validationContext(identity, activeContainerID: document.pages[0].rootNodeIDs[0]), placement: .inPlace)
        }
        let reused = try paste(into: destination)
        XCTAssertEqual(reused.componentSummary?.entries.map(\.resolution), [.reused])
        XCTAssertEqual(reused.componentSummary?.entries.first?.destinationDefinitionID, destinationComponent.definitionID)
        XCTAssertEqual(try paste(into: different).componentSummary?.entries.map(\.resolution), [.renamed])
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

    // OD-038 (ADR-0087): projects made from one template share language
    // identities. A paste into a project whose default is another of those
    // languages keeps the element's own text and drops the translation keyed
    // to the destination's default (it cannot exist there) instead of refusing.
    // SF-1106-002/004 (C6, ADR-0066): a Text bound to a page variable keeps
    // its binding through copy and paste. Pasted on its own page it still
    // shows the variable; pasted where that variable does not exist (another
    // page or project) the reference is kept, never matched by name, Check
    // Website reports it and the website shows the text's own content.
    func testPastedTextValueBindingKeepsItsVariableOnItsPageAndFallsBackElsewhere() throws {
        var fixture = try makeFixture()
        let label = CanonicalStateVariable(id: UUID(), name: "Label", type: .string, initial: .string("Ready"))
        let rootIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.rootID })
        let textIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.textID })
        fixture.document.pages[0].nodes[rootIndex].properties += CanonicalPageState.properties(variables: [label])
            .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
        fixture.document.pages[0].nodes[textIndex].properties += CanonicalTextBinding.properties(.init(variable: label.id))
            .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
        try fixture.document.validate()
        let registry = ClipboardTransferRegistry()
        let identity = operationIdentity(document: fixture.document, pageID: fixture.pageID, selected: [fixture.containerID])
        let envelope = try registry.prepareCopy(identity: identity, document: fixture.document,
                                                 resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        func pastedText(_ document: CanonicalDocument) throws -> DocumentNode {
            try XCTUnwrap(document.pages[0].nodes.first { $0.kind == .text && $0.name == "Label" && $0.id != fixture.textID })
        }

        // The same page has the variable: the copy shows it.
        let prepared = try registry.preparePaste(envelope: envelope, identity: identity, document: fixture.document,
            context: validationContext(identity, activeContainerID: fixture.rootID), placement: .offset)
        let session = DocumentSession(document: fixture.document)
        try session.execute(prepared.command)
        let copy = try pastedText(session.document)
        XCTAssertEqual(try CanonicalTextBinding.resolve(copy), CanonicalTextBinding(variable: label.id))
        XCTAssertFalse(EventGraphOutput.findings(session.document.pages[0], availablePageIDs: [fixture.pageID])
            .contains { $0.code == "state-text-binding-missing" })
        let writtenCopy = CanonicalTextBinding.outputPage(session.document.pages[0]).nodes.first { $0.id == copy.id }
        XCTAssertEqual(writtenCopy?.insertionStringProperty("content.text"), "Ready")
        try session.undo()
        XCTAssertEqual(session.document.pages, fixture.document.pages)

        // Another project's page has no such variable: kept, reported, own text shown.
        let destination = CanonicalDocument()
        let targetPage = destination.pages[0]
        let targetIdentity = operationIdentity(document: destination, pageID: targetPage.id, selected: [])
        let elsewhere = try registry.preparePaste(envelope: envelope, identity: targetIdentity, document: destination,
            context: validationContext(targetIdentity, activeContainerID: targetPage.rootNodeIDs[0]), placement: .inPlace)
        let other = DocumentSession(document: destination)
        try other.execute(elsewhere.command)
        let moved = try pastedText(other.document)
        XCTAssertEqual(try CanonicalTextBinding.resolve(moved), CanonicalTextBinding(variable: label.id))
        let findings = EventGraphOutput.findings(other.document.pages[0], availablePageIDs: [targetPage.id])
        XCTAssertEqual(findings.filter { $0.code == "state-text-binding-missing" }.map(\.affectedNodeID), [moved.id])
        let writtenMoved = CanonicalTextBinding.outputPage(other.document.pages[0]).nodes.first { $0.id == moved.id }
        XCTAssertEqual(writtenMoved?.insertionStringProperty("content.text"), "Clipboard fixture")
        let output = try EventGraphOutput.page(other.document.pages[0], staticRoutes: [:], prefix: "")
        XCTAssertFalse(output.htmlAttributes[moved.id]?.contains("data-siteforge-text-variable") ?? false)
        try other.undo()
        XCTAssertEqual(other.document.pages, destination.pages)
    }

    func testCrossProjectPasteDropsTranslationsKeyedToTheDestinationDefaultLanguage() throws {
        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "French", to: &localization)
        let german = try SiteLocalizationEditing.addLocale(code: "de", name: "German", to: &localization)
        var fixture = try makeFixture()
        fixture.document.localization = localization
        let textIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.textID })
        fixture.document.pages[0].nodes[textIndex].properties += [
            .init(key: .init(rawValue: SiteTranslationKey(localeID: french.id, field: .text).rawValue),
                  value: .string("Exemple"), origin: .authored),
            .init(key: .init(rawValue: SiteTranslationKey(localeID: german.id, field: .text).rawValue),
                  value: .string("Beispiel"), origin: .authored),
        ]
        try fixture.document.validate()
        let envelope = try ClipboardTransferRegistry().prepareCopy(
            identity: operationIdentity(document: fixture.document, pageID: fixture.pageID, selected: [fixture.containerID]),
            document: fixture.document, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        var destinationLocalization = localization
        try SiteLocalizationEditing.makeDefault(french.id, in: &destinationLocalization)
        let destination = CanonicalDocument(localization: destinationLocalization)
        try destination.validate()
        let targetPage = destination.pages[0]
        let targetIdentity = operationIdentity(document: destination, pageID: targetPage.id, selected: [])
        let prepared = try ClipboardTransferRegistry().preparePaste(
            envelope: envelope, identity: targetIdentity, document: destination,
            context: validationContext(targetIdentity, activeContainerID: targetPage.rootNodeIDs[0]), placement: .inPlace)
        let session = DocumentSession(document: destination)
        try session.execute(prepared.command)
        let pasted = try XCTUnwrap(session.document.pages[0].nodes.first { $0.kind == .text && $0.name == "Label" })
        XCTAssertEqual(pasted.insertionStringProperty("content.text"), "Clipboard fixture")
        XCTAssertEqual(CanonicalTranslations.translations(on: pasted).map { $0.key.localeID }, [german.id],
                       "Only the translation keyed to the destination's default language is dropped")
        try session.undo()
        XCTAssertEqual(session.document.pages, destination.pages)
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

    func testComponentUsageNotesTransferPreservesContentAndDistinguishesEquivalence() throws {
        let registry = ClipboardTransferRegistry()
        let privateNote = "Private author context <component> \(AssetID())"
        func fixture(_ note: String?) throws -> (CanonicalDocument, ComponentFixture) {
            var document = CanonicalDocument()
            let component = try addComponent(named: "Card", text: "Shared", to: &document)
            if let note {
                let index = try XCTUnwrap(document.pages.firstIndex { $0.id == component.definitionID })
                document.pages[index].nodes[0].properties.append(.init(
                    key: .init(rawValue: CanonicalComponentUsageNotes.key), value: .string(note), origin: .authored))
            }
            try document.validate()
            return (document, component)
        }
        for (sourceNote, existingNote, resolution) in [
            (privateNote, privateNote, ClipboardComponentTransferSummary.Entry.Resolution.reused),
            (privateNote, "Different usage note", .renamed),
            (privateNote, nil, .renamed),
            (nil, privateNote, .renamed)
        ] {
            let (source, sourceComponent) = try fixture(sourceNote)
            let (destination, destinationComponent) = try fixture(existingNote)
            let envelope = try registry.prepareCopy(identity: operationIdentity(document: source,
                pageID: source.pages[0].id, selected: [sourceComponent.instanceID]), document: source,
                resourceData: { _ in XCTFail("A note supplies no asset dependency"); throw ClipboardTransferError.invalidDependency })
            XCTAssertEqual(envelope.version, sourceNote == nil ? 2 : 3)
            XCTAssertTrue(envelope.imageDependencies.isEmpty)
            let bytes = try SiteForgeClipboardCodec.encode(envelope)
            XCTAssertEqual(try SiteForgeClipboardCodec.decode(bytes), envelope)
            if sourceNote != nil {
                var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                historical["version"] = 2
                XCTAssertThrowsError(try SiteForgeClipboardCodec.decode(JSONSerialization.data(withJSONObject: historical))) {
                    XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedVersion)
                }
            }

            let target = destination.pages[0]
            let identity = operationIdentity(document: destination, pageID: target.id, selected: [])
            let context = validationContext(identity, activeContainerID: target.rootNodeIDs[0])
            let paste = try registry.preparePaste(envelope: envelope, identity: identity, document: destination,
                context: context, placement: .inPlace)
            let entry = try XCTUnwrap(paste.componentSummary?.entries.first)
            XCTAssertEqual(entry.resolution, resolution)
            XCTAssertFalse(String(describing: paste.componentSummary).contains(privateNote))
            let session = DocumentSession(document: destination)
            try session.execute(paste.command)
            let imported = try XCTUnwrap(session.document.componentDefinitions.first { $0.id == entry.destinationDefinitionID })
            XCTAssertEqual(CanonicalComponentUsageNotes.text(in: imported), sourceNote)
            let existing = try XCTUnwrap(session.document.componentDefinitions.first { $0.id == destinationComponent.definitionID })
            XCTAssertEqual(CanonicalComponentUsageNotes.text(in: existing), existingNote)
            XCTAssertEqual(imported.id == existing.id, resolution == .reused)
            XCTAssertEqual(try XCTUnwrap(session.document.pages[0].nodes.last)
                .insertionStringProperty(CanonicalComponentReference.key), imported.id.description)
            let committed = session.document.pages
            try session.undo(); XCTAssertEqual(session.document.pages, destination.pages)
            try session.redo(); XCTAssertEqual(session.document.pages, committed)
        }
    }

    func testComponentUsageNotesClipboardRejectsNonRootAndInstanceNotes() throws {
        var document = CanonicalDocument()
        let component = try addComponent(named: "Card", text: "Shared", to: &document)
        let registry = ClipboardTransferRegistry()
        let identity = operationIdentity(document: document, pageID: document.pages[0].id,
                                         selected: [component.instanceID])
        let original = try registry.prepareCopy(identity: identity, document: document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        let note = NodeProperty(key: .init(rawValue: CanonicalComponentUsageNotes.key),
            value: .string("Private draft"), origin: .authored)
        var definition = try XCTUnwrap(original.componentDefinitions.first)
        definition.nodes[1].properties.append(note)
        var nodes = original.nodes
        nodes[0].properties.append(note)
        for (copiedNodes, definitions) in [(original.nodes, [definition]), (nodes, original.componentDefinitions)] {
            let malformed = SiteForgeClipboardEnvelope(version: 3,
                sourceDocumentID: original.sourceDocumentID, sourcePageID: original.sourcePageID,
                roots: original.roots, nodes: copiedNodes, componentDefinitions: definitions)
            XCTAssertThrowsError(try SiteForgeClipboardCodec.encode(malformed)) {
                XCTAssertEqual($0 as? ClipboardTransferError, .invalidEnvelope)
            }
            let unvalidated = try JSONEncoder().encode(malformed)
            XCTAssertThrowsError(try SiteForgeClipboardCodec.decode(unvalidated)) {
                XCTAssertEqual($0 as? ClipboardTransferError, .invalidEnvelope)
            }
        }
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

    // SF-0308-003/004, SF-0901-005, SF-0905-005, OD-034: copying a Card whose
    // definition contains a Button instance carries both definitions as v5.
    // Pasting into another project imports Button before Card, relinks Card's
    // inner instance and its value to the imported Button, and a second paste
    // reuses both; one older-version header or an inner action value is
    // refused before any change.
    func testNestedComponentCopyImportsInnerDefinitionsFirstAndReusesThemOnRepeatPaste() throws {
        var source = CanonicalDocument()
        let button = try addComponent(named: "Button", text: "Go", to: &source)
        let cardID = PageID(), cardRoot = NodeID(), innerID = NodeID(), cardInstanceID = NodeID()
        let inner = DocumentNode(id: innerID, kind: .component, name: "Button", parent: .node(cardRoot),
            properties: geometryProperties((16, 100, 200, 48)) + [
                .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(button.definitionID.description)),
                .init(key: .init(rawValue: CanonicalComponentText.overrideKey(button.textPropertyID)),
                      value: .string("Buy"), origin: .authored),
            ])
        let root = DocumentNode(id: cardRoot, kind: .frame, name: "Root", parent: .page(cardID),
                                childIDs: [innerID], properties: geometryProperties((0, 0, 320, 200)))
        source.pages.append(DocumentPage(id: cardID, name: "Card", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [cardRoot], nodes: [root, inner]))
        let pageRoot = source.pages[0].rootNodeIDs[0]
        source.pages[0].nodes[0].childIDs.append(cardInstanceID)
        source.pages[0].nodes.append(DocumentNode(id: cardInstanceID, kind: .component, name: "Card", parent: .node(pageRoot),
            properties: geometryProperties((300, 60, 320, 200)) + [
                .init(key: .init(rawValue: CanonicalComponentReference.key), value: .string(cardID.description))]))
        try source.validate()

        let registry = ClipboardTransferRegistry()
        let envelope = try registry.prepareCopy(identity: operationIdentity(document: source, pageID: source.pages[0].id,
            selected: [cardInstanceID]), document: source, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(envelope.version, SiteForgeClipboardEnvelope.versionWithLinkedBoxStyles,
                       "Nested definitions need a v5 reader; nothing here needs v6")
        XCTAssertEqual(Set(envelope.componentDefinitions.map(\.id)), [cardID, button.definitionID])
        let bytes = try SiteForgeClipboardCodec.encode(envelope)
        XCTAssertEqual(try SiteForgeClipboardCodec.decode(bytes), envelope)
        var older = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        older["version"] = 4
        XCTAssertThrowsError(try SiteForgeClipboardCodec.decode(JSONSerialization.data(withJSONObject: older))) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedVersion)
        }

        let destination = CanonicalDocument()
        let session = DocumentSession(document: destination)
        func paste() throws -> PreparedClipboardTransfer {
            let page = session.document.pages[0]
            let identity = operationIdentity(document: session.document, pageID: page.id, selected: [])
            let prepared = try registry.preparePaste(envelope: envelope, identity: identity, document: session.document,
                context: validationContext(identity, activeContainerID: page.rootNodeIDs[0]), placement: .inPlace)
            try session.execute(prepared.command)
            return prepared
        }
        let first = try paste()
        XCTAssertEqual(first.componentSummary?.entries.map(\.displayName), ["Button", "Card"], "Inner definition first")
        XCTAssertEqual(first.componentSummary?.entries.map(\.resolution), [.imported, .imported])
        let imported = session.document
        let importedButton = try XCTUnwrap(imported.componentDefinitions.first { $0.name == "Button" })
        let importedCard = try XCTUnwrap(imported.componentDefinitions.first { $0.name == "Card" })
        XCTAssertNotEqual(importedButton.id, button.definitionID)
        let importedProperty = try XCTUnwrap(CanonicalComponentText.properties(in: importedButton).first)
        XCTAssertNotEqual(importedProperty.id, button.textPropertyID)
        let relinked = try XCTUnwrap(importedCard.nodes.first { $0.kind == .component })
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: relinked), importedButton.id)
        XCTAssertEqual(CanonicalComponentText.overrides(on: relinked), [importedProperty.id: "Buy"])
        XCTAssertEqual(CanonicalComponentGraph(document: imported).dependencies[importedCard.id], [importedButton.id])
        let resolved = try ComponentGraphResolver.resolvedPage(imported.pages[0], in: imported, breakpoint: .desktop)
        XCTAssertTrue(resolved.nodes.contains { $0.insertionStringProperty("content.text") == "Buy" })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(imported)), imported)

        let second = try paste()
        XCTAssertEqual(second.componentSummary?.entries.map(\.resolution), [.reused, .reused],
                       "Structural identity compares the inner link in destination terms")
        XCTAssertEqual(session.document.componentDefinitions.count, 2)
        try session.undo()
        try session.undo()
        XCTAssertEqual(session.document.pages, destination.pages)

        // A destination stored on an inner instance cannot move between projects yet.
        var actionSource = source
        let actionID = ComponentActionPropertyID()
        let cardIndex = try XCTUnwrap(actionSource.pages.firstIndex { $0.id == cardID })
        actionSource.pages[cardIndex].nodes[1].properties.append(.init(
            key: .init(rawValue: CanonicalComponentAction.overrideKey(actionID)),
            value: .string(CanonicalComponentAction.encode(.external("https://example.com/inner"))), origin: .authored))
        let actionEnvelope = try registry.prepareCopy(identity: operationIdentity(document: actionSource,
            pageID: actionSource.pages[0].id, selected: [cardInstanceID]), document: actionSource,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        let page = destination.pages[0]
        let identity = operationIdentity(document: destination, pageID: page.id, selected: [])
        XCTAssertThrowsError(try registry.preparePaste(envelope: actionEnvelope, identity: identity, document: destination,
            context: validationContext(identity, activeContainerID: page.rootNodeIDs[0]), placement: .inPlace)) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedComponentDependency)
        }
    }

    // SF-0308-003/004, SF-0901-002/004, OD-034: while a definition is open,
    // copied content (here a page instance of Button) pastes into it as one
    // undoable step; pasting an instance of the open definition itself is
    // refused with the chain and changes nothing. Content copied out of a
    // definition is ordinary content: its exposed-property metadata stays in
    // the definition and only the current value travels.
    func testPasteIntoAnOpenDefinitionNestsCopiesAndRefusesTheDefinitionItself() throws {
        var document = CanonicalDocument()
        let button = try addComponent(named: "Button", text: "Go", to: &document)
        let card = try addComponent(named: "Card", text: "Card title", to: &document)
        let registry = ClipboardTransferRegistry()
        let home = document.pages[0]
        let copyButton = try registry.prepareCopy(identity: operationIdentity(document: document, pageID: home.id,
            selected: [button.instanceID]), document: document, resourceData: { _ in throw ClipboardTransferError.invalidDependency })

        let cardPage = try XCTUnwrap(document.pages.first { $0.id == card.definitionID })
        let cardRoot = cardPage.rootNodeIDs[0]
        let identity = operationIdentity(document: document, pageID: cardPage.id, selected: [])
        let prepared = try registry.preparePaste(envelope: copyButton, identity: identity, document: document,
            context: validationContext(identity, activeContainerID: cardRoot), placement: .inPlace)
        let session = DocumentSession(document: document)
        try session.execute(prepared.command)
        let pasted = session.document
        let nested = try XCTUnwrap(pasted.pages.first { $0.id == card.definitionID }?.nodes.first {
            prepared.insertedRootIDs.contains($0.id)
        })
        XCTAssertEqual(nested.kind, .component)
        XCTAssertEqual(nested.parent, .node(cardRoot))
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: nested), button.definitionID)
        XCTAssertEqual(CanonicalComponentText.overrides(on: nested)[button.textPropertyID], "Instance value",
                       "The copied instance keeps its own value inside Card")
        XCTAssertEqual(CanonicalComponentGraph(document: pasted).dependencies[card.definitionID], [button.definitionID])
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(pasted)), pasted)
        try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, pasted.pages)

        let copyCard = try registry.prepareCopy(identity: operationIdentity(document: pasted, pageID: home.id,
            selected: [card.instanceID]), document: pasted, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        let selfIdentity = operationIdentity(document: pasted, pageID: card.definitionID, selected: [])
        XCTAssertThrowsError(try registry.preparePaste(envelope: copyCard, identity: selfIdentity, document: pasted,
            context: validationContext(selfIdentity, activeContainerID: cardRoot), placement: .inPlace)) { error in
            guard case .componentNesting(let violation) = error as? ClipboardTransferError else {
                return XCTFail("Expected a nesting refusal, got \(error)")
            }
            XCTAssertEqual(violation.kind, .cycle)
            XCTAssertEqual(violation.names, ["Card", "Card"])
            XCTAssertEqual((error as? ClipboardTransferError)?.diagnosticCategory, "component-cycle")
            XCTAssertTrue(error.localizedDescription.contains("Nothing was pasted."))
        }
        let buttonPage = try XCTUnwrap(pasted.pages.first { $0.id == button.definitionID })
        let buttonIdentity = operationIdentity(document: pasted, pageID: buttonPage.id, selected: [])
        XCTAssertThrowsError(try registry.preparePaste(envelope: copyCard, identity: buttonIdentity, document: pasted,
            context: validationContext(buttonIdentity, activeContainerID: buttonPage.rootNodeIDs[0]), placement: .inPlace)) {
            XCTAssertEqual(($0 as? ClipboardTransferError)?.diagnosticCategory, "component-cycle",
                           "Card already contains Button, so Button cannot contain Card")
        }
        XCTAssertEqual(session.document.pages, pasted.pages)

        // Copy the bound title out of Card's definition and paste it on the page.
        let title = try XCTUnwrap(cardPage.nodes.first { $0.kind == .text })
        let copyTitle = try registry.prepareCopy(identity: operationIdentity(document: pasted, pageID: cardPage.id,
            selected: [title.id]), document: pasted, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        let copied = try XCTUnwrap(copyTitle.nodes.first)
        XCTAssertFalse(copied.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentText.namespace) })
        XCTAssertEqual(copied.insertionStringProperty("content.text"), "Card title")
        XCTAssertTrue(pasted.pages.first { $0.id == card.definitionID }?.nodes.first { $0.id == title.id }?
            .properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentText.namespace) } == true,
            "Copying never changes the definition")
        let pageIdentity = operationIdentity(document: pasted, pageID: home.id, selected: [])
        let onPage = try registry.preparePaste(envelope: copyTitle, identity: pageIdentity, document: pasted,
            context: validationContext(pageIdentity, activeContainerID: home.rootNodeIDs[0]), placement: .inPlace)
        try session.execute(onPage.command)
        try session.document.validate()
    }

    // SF-0308-003/005, SF-0903-005, OD-018: a copy that owns slot contents
    // (one slot supplied, the reference instance's state kept) travels as v6:
    // pasting in the same project creates a new copy whose own new objects
    // keep slot membership and slot-local geometry, so they move with it;
    // one Undo removes everything. A v5 header with slot contents is refused,
    // as are inconsistent forged contents.
    func testCopyOwningSlotContentsPastesWithItsOwnObjectsAndRequiresVersionSix() throws {
        var source = CanonicalDocument()
        let (component, slotID) = try addFallbackSlot(to: &source)
        let supplied = try supplySlot(slotID, on: component.instanceID, in: &source, items: [(.text, 8, 4), (.frame, 0, 40)])
        let registry = ClipboardTransferRegistry()
        let envelope = try registry.prepareCopy(identity: operationIdentity(document: source, pageID: source.pages[0].id,
            selected: [component.instanceID]), document: source, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(envelope.version, SiteForgeClipboardEnvelope.versionWithSlotContent)
        XCTAssertEqual(SiteForgeClipboardEnvelope.versionWithSlotContent, 6)
        XCTAssertEqual(envelope.nodes.map(\.id), [component.instanceID] + supplied)
        XCTAssertEqual(envelope.nodes[1].insertionGeometry?.origin, WorldPoint(x: 8, y: 4), "Slot-local; the owner travels too")
        let bytes = try SiteForgeClipboardCodec.encode(envelope)
        XCTAssertEqual(try SiteForgeClipboardCodec.decode(bytes), envelope)
        var older = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        older["version"] = 5
        XCTAssertThrowsError(try SiteForgeClipboardCodec.decode(JSONSerialization.data(withJSONObject: older))) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedVersion)
        }
        var forged = envelope.nodes
        forged[0].properties.removeAll { CanonicalComponentSlot.overrideID($0.key.rawValue) != nil }
        XCTAssertThrowsError(try SiteForgeClipboardEnvelope(sourceDocumentID: envelope.sourceDocumentID,
            sourcePageID: envelope.sourcePageID, roots: envelope.roots, nodes: forged,
            componentDefinitions: envelope.componentDefinitions).validate()) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedSlotContent)
        }

        let identity = operationIdentity(document: source, pageID: source.pages[0].id, selected: [])
        let prepared = try registry.preparePaste(envelope: envelope, identity: identity, document: source,
            context: validationContext(identity, activeContainerID: source.pages[0].rootNodeIDs[0]), placement: .offset)
        let session = DocumentSession(document: source)
        try session.execute(prepared.command)
        let pasted = session.document
        let copy = try XCTUnwrap(pasted.pages[0].nodes.first { prepared.insertedRootIDs.contains($0.id) })
        let byID = Dictionary(uniqueKeysWithValues: pasted.pages[0].nodes.map { ($0.id, $0) })
        let roots = try XCTUnwrap(CanonicalComponentSlot.suppliedRoots(of: copy, nodesByID: byID)[slotID])
        XCTAssertEqual(roots.count, 2)
        XCTAssertTrue(Set(roots.map(\.id)).isDisjoint(with: Set(supplied)), "New identities")
        XCTAssertEqual(roots.map { $0.insertionGeometry?.origin }, [WorldPoint(x: 8, y: 4), WorldPoint(x: 0, y: 40)])
        XCTAssertEqual(CanonicalComponentSlot.markers(on: copy)[slotID]?.value, .string(CanonicalComponentSlot.suppliedValue))
        try pasted.validate()
        let resolved = try ComponentGraphResolver.resolvedPage(pasted.pages[0], in: pasted, breakpoint: .desktop)
        // Original at (40, 60), slot at (12, 12): Text drawn at (60, 76). The paste is offset by 20.
        XCTAssertEqual(resolved.nodes.first { $0.id == supplied[0] }?.insertionGeometry?.origin, WorldPoint(x: 60, y: 76))
        XCTAssertEqual(resolved.nodes.first { $0.id == roots[0].id }?.insertionGeometry?.origin, WorldPoint(x: 80, y: 96))
        try session.undo()
        XCTAssertEqual(session.document.pages, source.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, pasted.pages)
    }

    // SF-0308-004, SF-0903-001, OD-018: pasting into another project imports
    // the definition (new slot identity), maps the copy's slot state and its
    // objects' membership to it, carries the slot rules, and a second paste
    // reuses the imported definition with the same mapping.
    func testCrossProjectPasteMapsSlotStateAndMembershipToTheImportedSlot() throws {
        var source = CanonicalDocument()
        let (component, slotID) = try addFallbackSlot(to: &source)
        let definitionIndex = try XCTUnwrap(source.pages.firstIndex { $0.id == component.definitionID })
        let slotNodeIndex = try XCTUnwrap(source.pages[definitionIndex].nodes.firstIndex { $0.name == "Slot Container" })
        source.pages[definitionIndex].nodes[slotNodeIndex].properties += [
            .init(key: .init(rawValue: CanonicalComponentSlot.allowedKindsKey), value: .string("frame,text"), origin: .authored),
            .init(key: .init(rawValue: CanonicalComponentSlot.maximumRootsKey), value: .number(4), origin: .authored)]
        _ = try supplySlot(slotID, on: component.instanceID, in: &source, items: [(.text, 8, 4)])
        let registry = ClipboardTransferRegistry()
        let envelope = try registry.prepareCopy(identity: operationIdentity(document: source, pageID: source.pages[0].id,
            selected: [component.instanceID]), document: source, resourceData: { _ in throw ClipboardTransferError.invalidDependency })

        let destination = CanonicalDocument()
        let session = DocumentSession(document: destination)
        func paste() throws -> PreparedClipboardTransfer {
            let page = session.document.pages[0]
            let identity = operationIdentity(document: session.document, pageID: page.id, selected: [])
            let prepared = try registry.preparePaste(envelope: envelope, identity: identity, document: session.document,
                context: validationContext(identity, activeContainerID: page.rootNodeIDs[0]), placement: .inPlace)
            try session.execute(prepared.command)
            return prepared
        }
        let first = try paste()
        XCTAssertEqual(first.componentSummary?.entries.map(\.resolution), [.imported])
        let imported = try XCTUnwrap(session.document.componentDefinitions.first)
        let newSlot = try XCTUnwrap(CanonicalComponentSlot.properties(in: imported).first)
        XCTAssertNotEqual(newSlot.id, slotID)
        XCTAssertEqual(newSlot.rules, .init(allowedKinds: [.frame, .text], maximumRoots: 4), "Rules travel with the definition")
        func check(_ prepared: PreparedClipboardTransfer) throws {
            let page = session.document.pages[0]
            let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
            let copy = try XCTUnwrap(page.nodes.first { prepared.insertedRootIDs.contains($0.id) })
            XCTAssertEqual(CanonicalComponentReference.definitionID(for: copy), imported.id)
            XCTAssertEqual(Set(CanonicalComponentSlot.markers(on: copy).keys), [newSlot.id])
            XCTAssertEqual(CanonicalComponentSlot.suppliedRoots(of: copy, nodesByID: byID)[newSlot.id]?.count, 1)
            XCTAssertFalse(page.nodes.contains { CanonicalComponentSlot.suppliedSlotID($0) == slotID }, "No source slot identity remains")
        }
        try check(first)
        let second = try paste()
        XCTAssertEqual(second.componentSummary?.entries.map(\.resolution), [.reused])
        XCTAssertEqual(session.document.componentDefinitions.count, 1)
        try check(second)
        try session.document.validate()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    // SF-0903-002/003/004, OD-018: Paste into a slot makes the pasted objects
    // top-level items of the selected copy's slot, after its existing items,
    // stored slot-local so they appear where they were copied, within the
    // slot rules; a copy that still uses the default contents is refused
    // with the next step. One Undo restores the copy.
    func testPasteIntoASlotAddsTopLevelItemsWithinTheRulesAtTheirCopiedPosition() throws {
        var document = try makeFixture().document
        let (component, slotID) = try addFallbackSlot(to: &document)
        let fixtureText = try XCTUnwrap(document.pages[0].nodes.first { $0.kind == .text && $0.name == "Label" })
        let registry = ClipboardTransferRegistry()
        let envelope = try registry.prepareCopy(identity: operationIdentity(document: document, pageID: document.pages[0].id,
            selected: [fixtureText.id]), document: document, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        func paste(into document: CanonicalDocument) throws -> PreparedClipboardTransfer {
            let identity = operationIdentity(document: document, pageID: document.pages[0].id, selected: [])
            var context = validationContext(identity, activeContainerID: component.instanceID)
            context.slotID = slotID
            return try registry.preparePaste(envelope: envelope, identity: identity, document: document,
                context: context, placement: .inPlace)
        }
        XCTAssertThrowsError(try paste(into: document)) {
            XCTAssertTrue($0.localizedDescription.contains("Choose Customize or Make Empty first"), $0.localizedDescription)
        }
        _ = try supplySlot(slotID, on: component.instanceID, in: &document, items: [(.frame, 0, 0)])
        let prepared = try paste(into: document)
        let session = DocumentSession(document: document)
        try session.execute(prepared.command)
        let page = session.document.pages[0]
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let owner = try XCTUnwrap(byID[component.instanceID])
        let roots = try XCTUnwrap(CanonicalComponentSlot.suppliedRoots(of: owner, nodesByID: byID)[slotID])
        XCTAssertEqual(roots.count, 2)
        XCTAssertEqual(roots.last?.id, prepared.insertedRootIDs.first, "After the existing item")
        // The Label is drawn at world (10, 12); the copy at (40, 60) has its slot at (12, 12),
        // so the slot origin is (52, 72) and the stored position is (10 − 52, 12 − 72).
        XCTAssertEqual(roots.last?.insertionGeometry?.origin, WorldPoint(x: -42, y: -60))
        let resolved = try ComponentGraphResolver.resolvedPage(page, in: session.document, breakpoint: .desktop)
        XCTAssertEqual(resolved.nodes.first { $0.id == roots.last?.id }?.insertionGeometry?.origin, fixtureText.insertionGeometry?.origin)
        try session.document.validate()
        try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)

        var limited = document
        let definitionIndex = try XCTUnwrap(limited.pages.firstIndex { $0.id == component.definitionID })
        let slotNodeIndex = try XCTUnwrap(limited.pages[definitionIndex].nodes.firstIndex { $0.name == "Slot Container" })
        let retainedSlotID = limited.pages[definitionIndex].nodes[slotNodeIndex].id
        limited.pages[definitionIndex].nodes[slotNodeIndex].properties.append(.init(
            key: .init(rawValue: CanonicalComponentSlot.allowedKindsKey), value: .string("frame"), origin: .authored))
        limited.pages[definitionIndex].nodes.removeAll { $0.kind == .text }
        let retainedSlotIndex = try XCTUnwrap(limited.pages[definitionIndex].nodes.firstIndex { $0.id == retainedSlotID })
        limited.pages[definitionIndex].nodes[retainedSlotIndex].childIDs = []
        limited.pages[definitionIndex].nodes = limited.pages[definitionIndex].nodes.map { node in
            var copy = node; copy.properties.removeAll { $0.key.rawValue.hasPrefix(CanonicalComponentText.namespace) }; return copy
        }
        let instanceIndex = try XCTUnwrap(limited.pages[0].nodes.firstIndex { $0.id == component.instanceID })
        limited.pages[0].nodes[instanceIndex].properties.removeAll { CanonicalComponentText.overrideID($0.key.rawValue) != nil }
        try limited.validate()
        XCTAssertThrowsError(try paste(into: limited)) {
            XCTAssertTrue($0.localizedDescription.contains("Text is not allowed; this slot accepts Frame"), $0.localizedDescription)
            XCTAssertTrue($0.localizedDescription.contains("Nothing was pasted."))
        }
    }

    /// SF-0308-003, SF-0903-003, OD-018 regression: pasting into a slot converts
    /// every pasted object to slot-local storage, not only the top-level ones,
    /// while a pasted copy's own slot contents keep their slot-local storage.
    func testPasteIntoASlotConvertsNestedObjectsButKeepsAPastedCopysOwnContents() throws {
        var document = try makeFixture().document
        let (component, slotID) = try addFallbackSlot(to: &document)
        let supplied = try supplySlot(slotID, on: component.instanceID, in: &document, items: [(.frame, 0, 0)])
        let frameID = try XCTUnwrap(supplied.first)
        let card = try XCTUnwrap(document.pages[0].nodes.first { $0.kind == .frame && $0.name == "Card" })
        let label = try XCTUnwrap(document.pages[0].nodes.first { $0.kind == .text && $0.name == "Label" })
        let registry = ClipboardTransferRegistry()
        let session = DocumentSession(document: document)
        func copy(_ id: NodeID) throws -> SiteForgeClipboardEnvelope {
            try registry.prepareCopy(identity: operationIdentity(document: session.document, pageID: session.document.pages[0].id,
                selected: [id]), document: session.document, resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        }
        func paste(_ envelope: SiteForgeClipboardEnvelope, into container: NodeID, slot: ComponentSlotPropertyID?) throws -> NodeID {
            let identity = operationIdentity(document: session.document, pageID: session.document.pages[0].id, selected: [])
            var context = validationContext(identity, activeContainerID: container)
            context.slotID = slot
            let prepared = try registry.preparePaste(envelope: envelope, identity: identity, document: session.document,
                context: context, placement: .inPlace)
            try session.execute(prepared.command)
            return try XCTUnwrap(prepared.insertedRootIDs.first)
        }
        func nodes() -> [NodeID: DocumentNode] {
            Dictionary(uniqueKeysWithValues: session.document.pages[0].nodes.map { ($0.id, $0) })
        }
        func drawn() throws -> [NodeID: DocumentNode] {
            let resolved = try ComponentGraphResolver.resolvedPage(session.document.pages[0], in: session.document, breakpoint: .desktop)
            return Dictionary(uniqueKeysWithValues: resolved.nodes.map { ($0.id, $0) })
        }

        // The copy at (40, 60) has its slot at (12, 12): slot-local (0, 0) draws at (52, 72).
        let cardCopy = try paste(try copy(card.id), into: component.instanceID, slot: slotID)
        let labelCopy = try XCTUnwrap(nodes()[cardCopy]?.childIDs.first)
        XCTAssertEqual(nodes()[cardCopy]?.insertionGeometry?.origin, WorldPoint(x: 40 - 52, y: 60 - 72))
        XCTAssertEqual(nodes()[labelCopy]?.insertionGeometry?.origin, WorldPoint(x: 10 - 52, y: 12 - 72),
                       "A pasted object's contents are slot-local too")
        XCTAssertEqual(try drawn()[labelCopy]?.insertionGeometry?.origin, label.insertionGeometry?.origin,
                       "Drawn where it was copied")

        // A copy that owns slot contents, pasted into the supplied Frame: only
        // the copy itself converts; its own items keep their slot-local values.
        let original = try XCTUnwrap(nodes()[component.instanceID])
        let owned = try XCTUnwrap(CanonicalComponentSlot.suppliedRoots(of: original, nodesByID: nodes())[slotID])
        let pastedOwner = try paste(try copy(component.instanceID), into: frameID, slot: nil)
        let owner = try XCTUnwrap(nodes()[pastedOwner])
        XCTAssertEqual(owner.insertionGeometry?.origin, WorldPoint(x: 40 - 52, y: 60 - 72))
        let ownItems = try XCTUnwrap(CanonicalComponentSlot.suppliedRoots(of: owner, nodesByID: nodes())[slotID])
        XCTAssertEqual(ownItems.map { $0.insertionGeometry?.origin }, owned.map { $0.insertionGeometry?.origin })
        let shown = try drawn()
        XCTAssertEqual(shown[pastedOwner]?.insertionGeometry?.origin, WorldPoint(x: 40, y: 60))
        XCTAssertEqual(shown[ownItems[0].id]?.insertionGeometry?.origin, shown[frameID]?.insertionGeometry?.origin,
                       "The pasted copy's Frame draws where the original copy's Frame does")
        try session.document.validate()
    }

    /// OD-033 source: a Button definition with Size (Small default, Large;
    /// Large shows "Buy now") on a blank project, and one copy choosing Large.
    private func variantSourceDocument() throws
        -> (document: CanonicalDocument, definitionID: PageID, copyID: NodeID, labelID: NodeID, size: ComponentVariantAxisID, large: ComponentVariantValueID) {
        typealias V = CanonicalComponentVariants
        func string(_ key: String, _ value: String) -> NodeProperty { .init(key: .init(rawValue: key), value: .string(value)) }
        var document = CanonicalDocument()
        let definitionID = PageID(), rootID = NodeID(), labelID = NodeID()
        let size = ComponentVariantAxisID(), small = ComponentVariantValueID(), large = ComponentVariantValueID()
        document.pages.append(DocumentPage(id: definitionID, name: "Button", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [rootID], nodes: [
                DocumentNode(id: rootID, kind: .frame, name: "Button", parent: .page(definitionID), childIDs: [labelID],
                             properties: geometryProperties((0, 0, 200, 48)) + [
                                string(V.axesKey, size.description), string(V.axisKey(size, "name"), "Size"),
                                string(V.axisKey(size, "values"), "\(small),\(large)"), string(V.axisKey(size, "default"), small.description),
                                string(V.valueNameKey(small), "Small"), string(V.valueNameKey(large), "Large")]),
                DocumentNode(id: labelID, kind: .text, name: "Label", parent: .node(rootID),
                             properties: geometryProperties((12, 12, 120, 24)) + [string("content.text", "Buy"),
                                string(V.overrideKey(.value(large), "content.text"), "Buy now")]),
            ]))
        let pageRoot = document.pages[0].rootNodeIDs[0]
        let copy = DocumentNode(kind: .component, name: "Button", parent: .node(pageRoot),
            properties: geometryProperties((40, 60, 200, 48)) + [string(CanonicalComponentReference.key, definitionID.description),
                                                                  string(V.choiceKey(size), large.description)])
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
        document.pages[0].nodes[rootIndex].childIDs.append(copy.id)
        document.pages[0].nodes.append(copy)
        try document.validate()
        return (document, definitionID, copy.id, labelID, size, large)
    }

    private func shownLabelText(of copyID: NodeID, labelID: NodeID, in document: CanonicalDocument) throws -> String? {
        let page = try XCTUnwrap(document.pages.first { page in page.nodes.contains { $0.id == copyID } })
        let copy = try XCTUnwrap(page.nodes.first { $0.id == copyID })
        let resolved = try ComponentGraphResolver.resolvedPage(page, in: document, breakpoint: .desktop)
        return resolved.nodes.first { $0.id == ComponentGraphResolver.derivedID(labelID, in: copy) }?.insertionStringProperty("content.text")
    }

    // SF-0308-003/004, SF-0904-005, OD-033: a copy and its definition's
    // variants travel as clipboard version 7 (older readers refuse); the
    // pasted copy keeps its choice and shows the same variant, in the same
    // project and in another project, where a second paste reuses the
    // imported definition. Objects copied out of a definition carry no
    // variant storage.
    func testComponentVariantsTravelThroughClipboardAsVersionSevenAndCopiesKeepTheirChoice() throws {
        typealias V = CanonicalComponentVariants
        let source = try variantSourceDocument()
        let registry = ClipboardTransferRegistry()
        let envelope = try registry.prepareCopy(identity: operationIdentity(document: source.document,
            pageID: source.document.pages[0].id, selected: [source.copyID]), document: source.document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(envelope.version, SiteForgeClipboardEnvelope.versionWithVariants)
        XCTAssertEqual(SiteForgeClipboardEnvelope.versionWithVariants, 7)
        XCTAssertEqual(envelope.componentDefinitions.map(\.id), [source.definitionID])
        let bytes = try SiteForgeClipboardCodec.encode(envelope)
        XCTAssertEqual(try SiteForgeClipboardCodec.decode(bytes), envelope)
        var older = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        older["version"] = 6
        XCTAssertThrowsError(try SiteForgeClipboardCodec.decode(JSONSerialization.data(withJSONObject: older))) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedVersion)
        }

        func paste(_ envelope: SiteForgeClipboardEnvelope, into document: CanonicalDocument) throws -> (CanonicalDocument, NodeID) {
            let identity = operationIdentity(document: document, pageID: document.pages[0].id, selected: [])
            let prepared = try registry.preparePaste(envelope: envelope, identity: identity, document: document,
                context: validationContext(identity, activeContainerID: document.pages[0].rootNodeIDs[0]), placement: .offset)
            let session = DocumentSession(document: document)
            try session.execute(prepared.command)
            return (session.document, try XCTUnwrap(prepared.insertedRootIDs.first))
        }
        let (sameProject, sameCopy) = try paste(envelope, into: source.document)
        XCTAssertEqual(sameProject.componentDefinitions.count, 1, "Same project: the definition is reused")
        XCTAssertEqual(try shownLabelText(of: sameCopy, labelID: source.labelID, in: sameProject), "Buy now")

        let (other, otherCopy) = try paste(envelope, into: CanonicalDocument())
        let imported = try XCTUnwrap(other.componentDefinitions.first)
        XCTAssertNotNil(try V.variantSet(in: imported), "The imported definition keeps its variants")
        let otherNode = try XCTUnwrap(other.pages[0].nodes.first { $0.id == otherCopy })
        XCTAssertEqual(otherNode.insertionStringProperty(V.choiceKey(source.size)), source.large.description)
        let importedLabel = try XCTUnwrap(imported.nodes.first { $0.kind == .text })
        let resolved = try ComponentGraphResolver.resolvedPage(other.pages[0], in: other, breakpoint: .desktop)
        XCTAssertEqual(resolved.nodes.first { $0.id == ComponentGraphResolver.derivedID(importedLabel.id, in: otherNode) }?
            .insertionStringProperty("content.text"), "Buy now")
        let (twice, _) = try paste(envelope, into: other)
        XCTAssertEqual(twice.componentDefinitions.count, 1, "A second paste reuses the imported definition")
        try twice.validate()

        // Copying the label out of the definition copies what it shows, not variant storage.
        let definitionCopy = try registry.prepareCopy(identity: operationIdentity(document: source.document,
            pageID: source.definitionID, selected: [source.labelID]), document: source.document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertFalse(definitionCopy.nodes.flatMap(\.properties).contains { $0.key.rawValue.hasPrefix(V.namespace) })
        XCTAssertLessThan(definitionCopy.version, SiteForgeClipboardEnvelope.versionWithVariants)
    }

    /// Supplies `items` (kind, slot-local x, y; 100 × 24) to an instance on the
    /// first page and marks the slot as supplied.
    @discardableResult
    private func supplySlot(_ slotID: ComponentSlotPropertyID, on instanceID: NodeID, in document: inout CanonicalDocument,
                            items: [(NodeKind, Double, Double)]) throws -> [NodeID] {
        let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == instanceID })
        let nodes = items.enumerated().map { offset, item in
            DocumentNode(kind: item.0, name: "Supplied \(offset + 1)", parent: .node(instanceID),
                properties: geometryProperties((item.1, item.2, 100, 24)) + [
                    .init(key: .init(rawValue: CanonicalComponentSlot.supplyKey), value: .string(slotID.description), origin: .authored)]
                + (item.0 == .text ? [.init(key: .init(rawValue: "content.text"), value: .string("Supplied"))] : []))
        }
        document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: CanonicalComponentSlot.overrideKey(slotID)),
            value: .string(CanonicalComponentSlot.suppliedValue), origin: .authored))
        document.pages[0].nodes[index].childIDs += nodes.map(\.id)
        document.pages[0].nodes += nodes
        try document.validate()
        return nodes.map(\.id)
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

    // SF-0510-002/005, SF-0308: a style's linked border, corners and shadow
    // travel with copied objects. The clipboard declares version 5 so older
    // readers refuse it instead of dropping the values, and style
    // equivalence on paste includes them.
    func testLinkedBoxStylesTravelThroughClipboardAsVersionFive() throws {
        var fixture = try makeFixture()
        let registry = ClipboardTransferRegistry()
        let plainCopy = try registry.prepareCopy(identity: operationIdentity(document: fixture.document,
            pageID: fixture.pageID, selected: [fixture.containerID]), document: fixture.document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(plainCopy.version, 2, "Content without linked box styles keeps the older version")

        let styleID = ReusableStyleID()
        let border = CanonicalBorder(color: try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#336699FF")),
                                     width: 2, style: .solid)
        let box = CanonicalReusableBoxAppearance(border: border, cornerRadius: 10)
        func definition(_ id: ReusableStyleID, name: String, box: CanonicalReusableBoxAppearance) -> [NodeProperty] {
            let prefix = CanonicalReusableStyleIndex.namespace + "definition.\(id.description)."
            return [NodeProperty(key: .init(rawValue: prefix + "name"), value: .string(name), origin: .authored)]
                + box.fieldValues.map { NodeProperty(key: .init(rawValue: prefix + $0.field), value: $0.value, origin: .authored) }
        }
        fixture.document.pages[0].nodes[0].properties += definition(styleID, name: "Card", box: box)
        let containerIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.containerID })
        fixture.document.pages[0].nodes[containerIndex].properties.append(.init(
            key: .init(rawValue: CanonicalReusableStyleIndex.appliedKey), value: .string(styleID.description)))
        try fixture.document.validate()

        let envelope = try registry.prepareCopy(identity: operationIdentity(document: fixture.document,
            pageID: fixture.pageID, selected: [fixture.containerID]), document: fixture.document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(SiteForgeClipboardEnvelope.versionWithLinkedBoxStyles, 5)
        XCTAssertGreaterThanOrEqual(SiteForgeClipboardEnvelope.currentVersion, 5)
        XCTAssertEqual(envelope.version, 5, "The oldest format that keeps linked box styles")
        XCTAssertEqual(envelope.reusableStyleDependencies.map(\.box), [box])
        let bytes = try SiteForgeClipboardCodec.encode(envelope)
        XCTAssertEqual(try SiteForgeClipboardCodec.decode(bytes), envelope)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        historical["version"] = 4
        XCTAssertThrowsError(try SiteForgeClipboardCodec.decode(JSONSerialization.data(withJSONObject: historical))) {
            XCTAssertEqual($0 as? ClipboardTransferError, .unsupportedVersion)
        }
        var emptyBox = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var dependencies = try XCTUnwrap(emptyBox["reusableStyleDependencies"] as? [[String: Any]])
        dependencies[0]["box"] = [String: Any]()
        emptyBox["reusableStyleDependencies"] = dependencies
        XCTAssertThrowsError(try SiteForgeClipboardCodec.decode(JSONSerialization.data(withJSONObject: emptyBox)),
                             "An explicit empty box is not a canonical encoding")
        let offGrid = SiteForgeClipboardEnvelope(sourceDocumentID: envelope.sourceDocumentID,
            sourcePageID: envelope.sourcePageID, roots: envelope.roots, nodes: envelope.nodes,
            reusableStyleDependencies: [.init(id: styleID, name: "Card", fill: nil, opacity: nil,
                box: .init(border: CanonicalBorder(color: CanonicalSolidColor(red: 0.1234, green: 0.5, blue: 0.75, alpha: 1),
                                                   width: 2, style: .solid)))])
        XCTAssertThrowsError(try offGrid.validate()) {
            XCTAssertEqual($0 as? ClipboardTransferError, .invalidDependency)
        }

        func paste(into destination: CanonicalDocument) throws -> DocumentSession {
            let identity = operationIdentity(document: destination, pageID: destination.pages[0].id, selected: [])
            let prepared = try registry.preparePaste(envelope: envelope, identity: identity, document: destination,
                context: validationContext(identity, activeContainerID: destination.pages[0].rootNodeIDs[0]),
                placement: .inPlace)
            let session = DocumentSession(document: destination)
            try session.execute(prepared.command)
            return session
        }

        // Into an empty project: the style arrives with its box values and the
        // pasted card resolves the linked border.
        let empty = CanonicalDocument()
        let pasted = try paste(into: empty)
        let index = try CanonicalReusableStyleIndex(document: pasted.document)
        let imported = try XCTUnwrap(index.orderedDefinitions.first)
        XCTAssertEqual(index.orderedDefinitions.count, 1)
        XCTAssertEqual(imported.name, "Card")
        XCTAssertEqual(imported.box, box)
        let card = try XCTUnwrap(pasted.document.pages[0].nodes.first {
            CanonicalReusableStyleIndex.appliedIDs($0) == [imported.id]
        })
        let resolved = try XCTUnwrap(CanonicalLinkedBoxStyleResolver.resolve(node: card, tokens: [], index: index))
        XCTAssertEqual(resolved.style.border, border)
        XCTAssertEqual(resolved.borderSource, .linked(imported.id))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(pasted.document)), pasted.document)
        try pasted.undo()
        XCTAssertEqual(pasted.document.pages, empty.pages)

        // A same-name style with different box values is not equivalent: the
        // pasted object gets a renamed copy that keeps the border.
        let lookalikeID = ReusableStyleID()
        var lookalike = CanonicalDocument()
        lookalike.pages[0].nodes[0].properties += definition(lookalikeID, name: "Card", box: .init(cornerRadius: 10))
        try lookalike.validate()
        let renamed = try CanonicalReusableStyleIndex(document: paste(into: lookalike).document)
        XCTAssertEqual(renamed.orderedDefinitions.count, 2)
        let copy = try XCTUnwrap(renamed.orderedDefinitions.first { $0.id != lookalikeID })
        XCTAssertEqual(copy.name, "Card Copy 2")
        XCTAssertEqual(copy.box, box)
        XCTAssertEqual(renamed.byID[lookalikeID]?.box, .init(cornerRadius: 10))

        // An identical style (same name and values) is reused, not duplicated.
        let identicalID = ReusableStyleID()
        var identical = CanonicalDocument()
        identical.pages[0].nodes[0].properties += definition(identicalID, name: "Card", box: box)
        try identical.validate()
        let reusedSession = try paste(into: identical)
        let reused = try CanonicalReusableStyleIndex(document: reusedSession.document)
        XCTAssertEqual(reused.orderedDefinitions.map(\.id), [identicalID])
        XCTAssertTrue(reusedSession.document.pages[0].nodes.contains {
            CanonicalReusableStyleIndex.appliedIDs($0) == [identicalID]
        })
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
