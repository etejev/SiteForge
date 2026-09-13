import XCTest
@testable import SiteForge

@MainActor
final class CommandKernelTests: XCTestCase {
    private func componentTextFixture() throws -> CanonicalDocument {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Legacy/schema-v7-linked-text-document.json")
        return try DocumentSerializer.decode(Data(contentsOf: url))
    }

    private func textCommand(_ edit: ComponentEdit, document: CanonicalDocument, pageID: PageID,
                             selected: NodeID) throws -> PreparedComponentEdit {
        let scene = CanvasViewportSceneID()
        return try ComponentCommandRegistry().prepare(edit, identity: .init(documentID: document.id, pageID: pageID,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision), in: document,
            context: .init(activePageID: pageID, currentSceneID: scene, rendererGeneration: document.revision,
                selectedNodeIDs: [selected], availableNodeIDs: [selected], isLifecycleAvailable: true, lifecycleDisabledReason: nil))
    }

    private func exposedTextSession() throws -> DocumentSession {
        let document = try componentTextFixture(), definition = document.componentDefinitions[0]
        let node = definition.nodes[1]
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.exposeText(nodeID: node.id, label: "Title", defaultValue: "Original"),
            document: document, pageID: definition.id, selected: node.id).command)
        return session
    }

    func testComponentTextV7MigrationAndStrictBindingValidation() throws {
        let legacy = try componentTextFixture()
        XCTAssertTrue(CanonicalComponentText.properties(in: legacy.componentDefinitions[0]).isEmpty)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(legacy)), legacy)
        let session = try exposedTextSession(), document = session.document
        XCTAssertEqual(document.websitePages, legacy.websitePages)
        let encoded = try DocumentSerializer.encode(document)
        XCTAssertThrowsError(try DocumentSerializer.decode(Data(String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\":8", with: "\"schemaVersion\":7").utf8)))
        for (suffix, value) in [("id", "not-an-id"), ("type", "media"), ("label", " "), ("label", "Title\n")] {
            var invalid = document
            let index = invalid.pages[2].nodes[1].properties.firstIndex { $0.key.rawValue == CanonicalComponentText.namespace + suffix }!
            invalid.pages[2].nodes[1].properties[index].value = .string(value)
            XCTAssertThrowsError(try DocumentSerializer.encode(invalid))
        }
        for suffix in ["future", "type"] {
            var invalid = document
            if suffix == "future" { invalid.pages[2].nodes[1].properties.append(.init(key: .init(rawValue: CanonicalComponentText.namespace + suffix), value: .string("x"))) }
            else { invalid.pages[2].nodes[1].properties.removeAll { $0.key.rawValue == CanonicalComponentText.namespace + suffix } }
            XCTAssertThrowsError(try DocumentSerializer.encode(invalid))
        }
        var invalid = document
        invalid.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: CanonicalComponentText.overrideNamespace + "bad"), value: .string("x")))
        XCTAssertThrowsError(try DocumentSerializer.encode(invalid))
        invalid = document
        let metadata = invalid.pages[2].nodes[1].properties.firstIndex { $0.key.rawValue == CanonicalComponentText.namespace + "label" }!
        invalid.pages[2].nodes[1].properties[metadata].origin = .defaulted
        XCTAssertThrowsError(try DocumentSerializer.encode(invalid))
    }

    func testComponentTextIndependentEmptyOverridesDefaultPropagationAndExactResetHistory() throws {
        let session = try exposedTextSession()
        let definition = session.document.componentDefinitions[0], text = definition.nodes[1]
        let binding = try XCTUnwrap(CanonicalComponentText.property(on: text))
        let pageID = session.document.pages[0].id, first = session.document.pages[0].nodes[1].id
        let second = session.document.pages[0].nodes[2].id
        func apply(_ edit: ComponentEdit, _ page: PageID, _ target: NodeID) throws {
            try session.execute(textCommand(edit, document: session.document, pageID: page, selected: target).command)
        }
        let inherited = session.document.pages
        try apply(.setTextOverride(instanceID: first, propertyID: binding.id, value: ""), pageID, first)
        let overridden = session.document.pages
        XCTAssertEqual(CanonicalComponentText.overrides(on: overridden[0].nodes[1])[binding.id], "")
        try apply(.exposeText(nodeID: text.id, label: "Heading", defaultValue: "Updated"), definition.id, text.id)
        XCTAssertEqual(CanonicalComponentText.property(on: session.document.pages[2].nodes[1])?.id, binding.id)
        for breakpoint in ResponsiveBreakpoint.allCases {
            let resolved = try ComponentGraphResolver.resolvedPage(session.document.pages[0], in: session.document, breakpoint: breakpoint)
            let childID = NodeID(DocumentPage.deterministicUUID(namespace: first.rawValue, label: "component-child:" + text.id.description))
            let otherID = NodeID(DocumentPage.deterministicUUID(namespace: second.rawValue, label: "component-child:" + text.id.description))
            XCTAssertEqual(resolved.nodes.first { $0.id == childID }?.insertionStringProperty("content.text"), "")
            XCTAssertEqual(resolved.nodes.first { $0.id == otherID }?.insertionStringProperty("content.text"), "Updated")
            XCTAssertFalse(session.document.pages[0].nodes.contains { $0.id == childID })
            XCTAssertFalse(resolved.nodes.contains { $0.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentText.namespace) } })
        }
        let beforeReset = session.document.pages
        try apply(.resetTextOverride(instanceID: first, propertyID: binding.id), pageID, first)
        XCTAssertNil(session.document.pages[0].nodes[1].insertionProperty(CanonicalComponentText.overrideKey(binding.id)))
        let reset = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, beforeReset)
        try session.redo(); XCTAssertEqual(session.document.pages, reset)
        try session.undo(); try session.undo(); XCTAssertEqual(session.document.pages, overridden)
        try session.undo(); XCTAssertEqual(session.document.pages, inherited)
        try session.redo()
        try apply(.setTextOverride(instanceID: second, propertyID: binding.id, value: "Independent"), pageID, second)
        XCTAssertFalse(session.redoAvailability.isEnabled)
        try apply(.resetAllTextOverrides(first), pageID, first)
        XCTAssertTrue(CanonicalComponentText.overrides(on: session.document.pages[0].nodes[1]).isEmpty)
        XCTAssertEqual(CanonicalComponentText.overrides(on: session.document.pages[0].nodes[2])[binding.id], "Independent")
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testComponentTextStaleCancelledInvalidAndVirtualTargetsAreNeutral() throws {
        let session = try exposedTextSession(), document = session.document
        let page = document.pages[0], first = page.nodes[1], scene = CanvasViewportSceneID()
        let binding = CanonicalComponentText.properties(in: document.componentDefinitions[0])[0]
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: page.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene, rendererGeneration: document.revision,
            selectedNodeIDs: [first.id], availableNodeIDs: [first.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let edit = ComponentEdit.setTextOverride(instanceID: first.id, propertyID: binding.id, value: "Private draft")
        let registry = ComponentCommandRegistry()
        XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: document, context: context, cancelled: true))
        for stale in [
            DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: page.id, revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: PageID(), revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: page.id, revision: 0, sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: page.id, revision: document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: page.id, revision: document.revision, sceneID: scene, rendererGeneration: 0)
        ] { XCTAssertThrowsError(try registry.prepare(edit, identity: stale, in: document, context: context)) }
        for selection in [[], [first.id, page.nodes[2].id], [first.id, first.id], [NodeID()]] as [[NodeID]] {
            let changed = TransformValidationContext(activePageID: page.id, currentSceneID: scene, rendererGeneration: document.revision,
                selectedNodeIDs: selection, availableNodeIDs: [first.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
            XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: document, context: changed))
        }
        for key in ["locked", "hidden"] {
            var blocked = document
            blocked.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: key), value: .boolean(true)))
            XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: blocked, context: context))
        }
        XCTAssertThrowsError(try textCommand(.setTextOverride(instanceID: first.id, propertyID: binding.id,
            value: String(repeating: "x", count: 65_537)), document: document, pageID: page.id, selected: first.id))
        XCTAssertThrowsError(try textCommand(.setTextOverride(instanceID: first.id, propertyID: ComponentTextPropertyID(), value: "x"),
            document: document, pageID: page.id, selected: first.id))
        let virtual = NodeID(DocumentPage.deterministicUUID(namespace: first.id.rawValue, label: "component-child:" + binding.sourceNodeID.description))
        XCTAssertThrowsError(try textCommand(.setTextOverride(instanceID: virtual, propertyID: binding.id, value: "x"),
            document: document, pageID: page.id, selected: virtual))
        let before = try DocumentSerializer.encode(document)
        XCTAssertEqual(try DocumentSerializer.encode(session.document), before)
        let diagnostics = CommandDiagnostics()
        diagnostics.recordComponentOperation(pageID: page.id, nodeIDs: [first.id], succeeded: false, durationMilliseconds: 1)
        XCTAssertTrue(diagnostics.records[0].requirementIDs.contains("SF-0902-008"))
        XCTAssertFalse(String(describing: diagnostics.records).contains("Private draft"))
        XCTAssertFalse(String(describing: diagnostics.records).contains(first.id.description))
    }

    func testComponentTextSourceRemovalGuardAndUnresolvedIntentPreservation() throws {
        let session = try exposedTextSession(), definition = session.document.componentDefinitions[0]
        let text = definition.nodes[1], binding = CanonicalComponentText.properties(in: definition)[0]
        let first = session.document.pages[0].nodes[1], pageID = session.document.pages[0].id
        try session.execute(textCommand(.setTextOverride(instanceID: first.id, propertyID: binding.id, value: "Retain"),
            document: session.document, pageID: pageID, selected: first.id).command)
        let before = session.document
        XCTAssertThrowsError(try textCommand(.removeTextProperty(text.id), document: before, pageID: definition.id, selected: text.id))
        for command: DocumentCommand in [
            .removeNode(.init(pageID: definition.id, nodeID: text.id)),
            .removePage(.init(pageID: definition.id)),
            .setProperty(.init(pageID: pageID, nodeID: first.id, property: .init(
                id: first.insertionProperty(CanonicalComponentReference.key)!.id,
                key: .init(rawValue: CanonicalComponentReference.key), value: .string(PageID().description)))),
            .batch(text.properties.filter { CanonicalComponentText.metadataKeys.contains($0.key.rawValue) }.map {
                .removeProperty(.init(pageID: definition.id, nodeID: text.id, propertyID: $0.id))
            })
        ] {
            XCTAssertThrowsError(try session.execute(command))
            XCTAssertEqual(session.document, before)
        }
        var unresolved = before
        unresolved.pages[2].nodes[1].properties.removeAll { CanonicalComponentText.metadataKeys.contains($0.key.rawValue) }
        let loaded = try DocumentSerializer.decode(DocumentSerializer.encode(unresolved))
        XCTAssertEqual(CanonicalComponentText.unresolvedOverrides(on: loaded.pages[0].nodes[1], definition: loaded.pages[2]), [binding.id])
        XCTAssertNil(ComponentGraphResolver.detachedNodes(loaded.pages[0].nodes[1], definition: loaded.pages[2], page: loaded.pages[0]))
        try session.execute(textCommand(.resetAllTextOverrides(first.id), document: before, pageID: pageID, selected: first.id).command)
        try session.execute(textCommand(.removeTextProperty(text.id), document: session.document, pageID: definition.id, selected: text.id).command)
        XCTAssertTrue(CanonicalComponentText.properties(in: session.document.componentDefinitions[0]).isEmpty)
        XCTAssertEqual(session.document.pages[2].nodes[1].insertionStringProperty("content.text"), "Original")
        try session.undo(); try session.undo()
        XCTAssertEqual(session.document.pages, before.pages)
    }

    func testComponentTextMultipleBindingsResetAllAndNoOpPreserveExactPresence() throws {
        let session = try exposedTextSession(), definition = session.document.componentDefinitions[0]
        let title = CanonicalComponentText.properties(in: definition)[0]
        let subtitle = DocumentNode(kind: .text, name: "Subtitle", parent: .node(definition.rootNodeIDs[0]),
            properties: definition.nodes[1].properties.filter { !CanonicalComponentText.metadataKeys.contains($0.key.rawValue) }
                .map { .init(key: $0.key, value: $0.value, origin: $0.origin) })
        try session.execute(.insertNode(.init(pageID: definition.id, node: subtitle, index: 1)))
        try session.execute(textCommand(.exposeText(nodeID: subtitle.id, label: "Subtitle", defaultValue: "Secondary"),
            document: session.document, pageID: definition.id, selected: subtitle.id).command)
        XCTAssertThrowsError(try textCommand(.exposeText(nodeID: subtitle.id, label: "title", defaultValue: "Secondary"),
            document: session.document, pageID: definition.id, selected: subtitle.id))
        let binding = try XCTUnwrap(CanonicalComponentText.property(on: session.document.pages[2].nodes.first { $0.id == subtitle.id }!))
        let pageID = session.document.pages[0].id, instanceID = session.document.pages[0].nodes[1].id
        for (id, text) in [(title.id, ""), (binding.id, "Authored subtitle")] {
            try session.execute(textCommand(.setTextOverride(instanceID: instanceID, propertyID: id, value: text),
                document: session.document, pageID: pageID, selected: instanceID).command)
        }
        let noOp = try textCommand(.setTextOverride(instanceID: instanceID, propertyID: title.id, value: ""),
            document: session.document, pageID: pageID, selected: instanceID)
        guard case .batch(let commands) = noOp.command else { return XCTFail("Expected property transaction") }
        XCTAssertTrue(commands.isEmpty, "Unchanged authored value must not create a UI history entry")
        let before = session.document.pages
        try session.execute(textCommand(.resetTextOverride(instanceID: instanceID, propertyID: title.id),
            document: session.document, pageID: pageID, selected: instanceID).command)
        XCTAssertEqual(CanonicalComponentText.overrides(on: session.document.pages[0].nodes[1]), [binding.id: "Authored subtitle"])
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.execute(textCommand(.resetAllTextOverrides(instanceID), document: session.document, pageID: pageID, selected: instanceID).command)
        XCTAssertTrue(CanonicalComponentText.overrides(on: session.document.pages[0].nodes[1]).isEmpty)
        try session.undo(); XCTAssertEqual(session.document.pages, before)
    }

    func testComponentTextEffectiveDetachAndPageDuplicationPreserveStableIntent() throws {
        let session = try exposedTextSession(), definition = session.document.componentDefinitions[0]
        let binding = CanonicalComponentText.properties(in: definition)[0], page = session.document.pages[0]
        let first = page.nodes[1]
        try session.execute(textCommand(.setTextOverride(instanceID: first.id, propertyID: binding.id, value: "Detached value"),
            document: session.document, pageID: page.id, selected: first.id).command)
        let original = session.document.pages
        let expected = try ComponentGraphResolver.resolvedPage(session.document.pages[0], in: session.document, breakpoint: .desktop)
        try session.execute(textCommand(.detach(first.id), document: session.document, pageID: page.id, selected: first.id).command)
        let materialized = session.document.pages[0]
        let childID = NodeID(DocumentPage.deterministicUUID(namespace: first.id.rawValue, label: "component-child:" + binding.sourceNodeID.description))
        XCTAssertEqual(materialized.nodes.first { $0.id == childID }?.insertionStringProperty("content.text"), "Detached value")
        XCTAssertEqual(materialized.nodes.first { $0.id == childID }?.insertionGeometry, expected.nodes.first { $0.id == childID }?.insertionGeometry)
        XCTAssertFalse(materialized.nodes.contains { $0.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentText.namespace) } })
        try session.undo(); XCTAssertEqual(session.document.pages, original)
        let duplicated = try PageCommandRegistry().prepare(.duplicate,
            identity: .init(documentID: session.document.id, revision: session.document.revision, pageID: page.id),
            in: session.document, isAvailable: true)
        try session.execute(duplicated.command)
        let copy = try XCTUnwrap(session.document.pages.first { $0.id == duplicated.selectedPageID })
        let copied = try XCTUnwrap(copy.nodes.first { $0.name == first.name })
        XCTAssertNotEqual(copied.id, first.id)
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: copied), definition.id)
        XCTAssertEqual(CanonicalComponentText.overrides(on: copied)[binding.id], "Detached value")
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testComponentTextImmutableRendererAndAccessibilityUseEffectiveRevision() async throws {
        let session = try exposedTextSession(), definition = session.document.componentDefinitions[0]
        let binding = CanonicalComponentText.properties(in: definition)[0], page = session.document.pages[0]
        let first = page.nodes[1]
        let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 1_000, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)), pixelRatio: .init(2))
        let worker = WorkspaceScenePreparationWorker(), surface = CanvasRenderSurfaceID()
        let old = try await worker.prepare(.init(document: session.document, activePageID: page.id,
            activeContainerID: nil, viewport: viewport, surfaceID: surface))
        try session.execute(textCommand(.setTextOverride(instanceID: first.id, propertyID: binding.id, value: "Effective value"),
            document: session.document, pageID: page.id, selected: first.id).command)
        let next = try await worker.prepare(.init(document: session.document, activePageID: page.id,
            activeContainerID: nil, viewport: viewport, surfaceID: surface))
        let id = NodeID(DocumentPage.deterministicUUID(namespace: first.id.rawValue, label: "component-child:" + binding.sourceNodeID.description))
        XCTAssertEqual(old.renderScene.objects.first { $0.id == id }?.plainText, "Original")
        XCTAssertEqual(next.renderScene.objects.first { $0.id == id }?.plainText, "Effective value")
        XCTAssertEqual(next.renderScene.identity.sceneGeneration, session.document.revision)
        XCTAssertEqual(old.renderScene.objects.first { $0.id == id }?.frame, next.renderScene.objects.first { $0.id == id }?.frame)
        let plan = try CanvasRendererCore().prepare(scene: next.renderScene, overlays: next.overlays, viewport: viewport,
                                                    previous: old.renderScene)
        XCTAssertEqual(plan.accessibilityElements.first { $0.objectID == id }?.textContent, "Effective value")
        XCTAssertFalse(session.document.pages[0].nodes.contains { $0.id == id })
    }

    func testComponentTextDraftIdentityWaitsForAdoptedRevision() throws {
        let document = try componentTextFixture(), pageID = document.pages[0].id, scene = CanvasViewportSceneID()
        let oldPlan = try CanvasRenderRequestIdentity(documentID: document.id, revision: document.revision,
            sceneID: scene, sceneGeneration: document.revision, viewportGeneration: 0, scale: .init(2))
        let first = try XCTUnwrap(ComponentCommandRegistry.draftIdentity(document: document, pageID: pageID, renderer: oldPlan))
        var edited = document; edited.revision += 1
        XCTAssertNil(ComponentCommandRegistry.draftIdentity(document: edited, pageID: pageID, renderer: oldPlan),
                     "Publication before adoption must not initialize an editable draft with an obsolete renderer")
        let adopted = try CanvasRenderRequestIdentity(documentID: edited.id, revision: edited.revision,
            sceneID: scene, sceneGeneration: edited.revision, viewportGeneration: 1, scale: .init(2))
        let next = try XCTUnwrap(ComponentCommandRegistry.draftIdentity(document: edited, pageID: pageID, renderer: adopted))
        XCTAssertNotEqual(first, next)
        XCTAssertEqual(next.revision, edited.revision)
        XCTAssertEqual(next.rendererGeneration, edited.revision)
        XCTAssertNil(ComponentCommandRegistry.draftIdentity(document: edited, pageID: PageID(), renderer: adopted))
        XCTAssertNil(ComponentCommandRegistry.draftIdentity(document: edited, pageID: pageID, renderer: nil))
    }

    func testComponentInsertionPlacementUsesVisibleParentIntersectionWithoutChangingSource() throws {
        let source = InsertionGeometry(origin: .init(x: 900, y: 800), size: .init(width: 240, height: 160))
        let artboard = WorldRect(origin: .init(x: 0, y: 0), size: .init(width: 768, height: 1024))
        let parent = WorldRect(origin: .init(x: 700, y: 40), size: .init(width: 200, height: 100))
        let placed = try XCTUnwrap(ComponentGraphResolver.insertionGeometry(source: source,
            parentFrame: parent, artboard: artboard))
        XCTAssertEqual(placed.origin, .init(x: 700, y: 40))
        XCTAssertEqual(placed.size, .init(width: 68, height: 100))
        XCTAssertEqual(source.origin, .init(x: 900, y: 800))
        XCTAssertEqual(source.size, .init(width: 240, height: 160))
        XCTAssertNil(ComponentGraphResolver.insertionGeometry(source: source,
            parentFrame: .init(origin: .init(x: 800, y: 40), size: .init(width: 200, height: 100)), artboard: artboard))
        let root = try XCTUnwrap(ComponentGraphResolver.insertionGeometry(source: source, parentFrame: nil, artboard: artboard))
        XCTAssertEqual(root.origin, .init(x: 264, y: 432))
        XCTAssertEqual(root.size, source.size)
    }
    func testComponentExpansionBudgetCancellationAndCollisionAreMutationNeutral() throws {
        var document = BlankProjectDefaults.document()
        let definitionID = PageID(), rootID = NodeID()
        func geometry() -> [NodeProperty] {
            [("layout.x", 0.0), ("layout.y", 0), ("layout.width", 120), ("layout.height", 24)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            }
        }
        let child = DocumentNode(kind: .text, name: "Child", parent: .node(rootID), properties: geometry())
        let root = DocumentNode(id: rootID, kind: .frame, name: "Master", parent: .page(definitionID),
            childIDs: [child.id], properties: geometry())
        let definition = DocumentPage(id: definitionID, name: "Card", route: .init(rawValue: ""),
            role: .componentDefinition, provenance: .authored, rootNodeIDs: [rootID], nodes: [root, child])
        let parentID = document.pages[0].rootNodeIDs[0]
        let instances = (0..<100).map { _ in
            DocumentNode(kind: .component, name: "Card", parent: .node(parentID), properties: geometry() + [
                NodeProperty(key: .init(rawValue: CanonicalComponentReference.key), value: .string(definitionID.description))
            ])
        }
        document.pages[0].nodes[0].childIDs = instances.map(\.id)
        document.pages[0].nodes += instances
        document.pages.append(definition)
        let before = try DocumentSerializer.encode(document)
        let resolved = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document,
            breakpoint: .desktop, maximumNodes: 201)
        XCTAssertEqual(resolved.nodes.count, 201)
        XCTAssertEqual(Set(resolved.nodes.map(\.id)).count, 201)
        XCTAssertThrowsError(try ComponentGraphResolver.resolvedPage(document.pages[0], in: document,
            breakpoint: .desktop, maximumNodes: 200)) {
            XCTAssertEqual($0 as? ComponentResolutionError, .objectLimitExceeded(201))
        }
        XCTAssertThrowsError(try ComponentGraphResolver.resolvedPage(document.pages[0], in: document,
            breakpoint: .desktop, checkpoint: { throw CanvasRendererError.cancelled })) {
            XCTAssertEqual($0 as? CanvasRendererError, .cancelled)
        }
        XCTAssertEqual(try DocumentSerializer.encode(document), before)
        let derivedID = NodeID(DocumentPage.deterministicUUID(namespace: instances[0].id.rawValue,
            label: "component-child:" + child.id.description))
        document.pages[0].nodes[0].childIDs.append(derivedID)
        document.pages[0].nodes.append(DocumentNode(id: derivedID, kind: .frame, name: "Collision",
            parent: .node(parentID), properties: geometry()))
        XCTAssertThrowsError(try ComponentGraphResolver.resolvedPage(document.pages[0], in: document,
            breakpoint: .desktop)) { XCTAssertEqual($0 as? ComponentResolutionError, .duplicateObject(derivedID)) }
    }

    func testComponentSchemaRejectsHistoricalSmugglingCyclesAndPreservesMissingReferences() throws {
        var document = BlankProjectDefaults.document()
        let missingID = PageID(), parentID = document.pages[0].rootNodeIDs[0]
        let instance = DocumentNode(kind: .component, name: "Missing", parent: .node(parentID), properties: [
            NodeProperty(key: .init(rawValue: CanonicalComponentReference.key), value: .string(missingID.description))
        ])
        document.pages[0].nodes[0].childIDs.append(instance.id)
        document.pages[0].nodes.append(instance)
        let bytes = try DocumentSerializer.encode(document)
        XCTAssertEqual(try DocumentSerializer.decode(bytes), document)
        let old = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":8", with: "\"schemaVersion\":6")
        XCTAssertThrowsError(try DocumentSerializer.decode(Data(old.utf8)))
        let future = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":8", with: "\"schemaVersion\":9")
        XCTAssertThrowsError(try DocumentSerializer.decode(Data(future.utf8))) {
            XCTAssertEqual($0 as? DocumentSerializationError, .unsupportedSchema(9))
        }
        var invalid = document
        invalid.pages[0].nodes[1].properties[0].value = .string("invalid")
        XCTAssertThrowsError(try DocumentSerializer.encode(invalid))
        let cyclicRoot = DocumentNode(kind: .component, name: "Cycle", parent: .page(missingID),
            properties: [NodeProperty(key: .init(rawValue: CanonicalComponentReference.key),
                                      value: .string(missingID.description))])
        invalid = document
        invalid.pages.append(DocumentPage(id: missingID, name: "Cycle", route: .init(rawValue: ""),
            role: .componentDefinition, provenance: .authored, rootNodeIDs: [cyclicRoot.id], nodes: [cyclicRoot]))
        XCTAssertThrowsError(try invalid.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .incompatibleChildOwnership)
        }
        XCTAssertEqual(try DocumentSerializer.encode(document), bytes)
    }

    func testComponentDefinitionContextUsesAuthoringGraphWithoutWebsiteNavigation() throws {
        var document = BlankProjectDefaults.document()
        let definitionID = PageID()
        let root = DocumentNode(kind: .frame, name: "Card", parent: .page(definitionID), properties:
            [("layout.x", 100.0), ("layout.y", 80), ("layout.width", 240), ("layout.height", 160)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        document.pages.append(DocumentPage(id: definitionID, name: "Card", route: .init(rawValue: ""),
            role: .componentDefinition, provenance: .authored, rootNodeIDs: [root.id], nodes: [root]))
        let session = DocumentSession(document: document)
        let shell = WorkspaceShellState(documentSession: session)
        let returnPage = shell.effectiveSelectedPageID
        shell.editComponentDefinition(definitionID)
        XCTAssertEqual(shell.effectiveSelectedPageID, definitionID)
        XCTAssertFalse(shell.pages.contains { $0.id == definitionID })
        XCTAssertEqual(shell.selectionPath, "Card / No selection")
        shell.performDefaultInsertion(.text, provenance: .menu)
        let definition = try XCTUnwrap(session.document.componentDefinitions.first)
        XCTAssertEqual(definition.nodes.count, 2)
        XCTAssertEqual(definition.nodes.last?.parent, .node(root.id))
        XCTAssertEqual(session.document.websitePages, document.websitePages)
        shell.exitComponentDefinition()
        XCTAssertEqual(shell.effectiveSelectedPageID, returnPage)
        XCTAssertNil(shell.editingComponentID)
    }

    func testComponentDetachPreservesEveryBreakpointAndInstancePropertyIdentity() throws {
        var document = BlankProjectDefaults.document()
        let pageID = document.pages[0].id, parentID = document.pages[0].rootNodeIDs[0]
        var root = DocumentNode(kind: .frame, name: "Card", parent: .node(parentID), properties:
            [("layout.x", 100.0), ("layout.y", 80), ("layout.width", 240), ("layout.height", 160)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        let child = DocumentNode(kind: .text, name: "Label", parent: .node(root.id), properties:
            [("layout.x", 120.0), ("layout.y", 90), ("layout.width", 100), ("layout.height", 24)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        root.childIDs = [child.id]
        let mobileX = NodeProperty(key: .init(rawValue: ResponsiveGeometryResolver.key(.x, breakpoint: .mobile)),
            value: .number(20), origin: .authored)
        root.properties.append(mobileX)
        document.pages[0].nodes[0].childIDs = [root.id]
        document.pages[0].nodes += [root, child]
        let session = DocumentSession(document: document), scene = CanvasViewportSceneID()
        func command(_ edit: ComponentEdit) throws -> DocumentCommand {
            try ComponentCommandRegistry().prepare(edit, identity: .init(documentID: document.id, pageID: pageID,
                revision: session.document.revision, sceneID: scene, rendererGeneration: session.document.revision),
                in: session.document, context: .init(activePageID: pageID, currentSceneID: scene,
                    rendererGeneration: session.document.revision, selectedNodeIDs: [root.id],
                    availableNodeIDs: [root.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil)).command
        }
        try session.execute(command(.create(root.id)))
        let linked = session.document
        let expected = try ResponsiveBreakpoint.allCases.map {
            try ComponentGraphResolver.resolvedPage(linked.pages[0], in: linked, breakpoint: $0)
                .resolvedStructuralGeometry(breakpoint: $0)
        }
        try session.execute(command(.detach(root.id)))
        for (index, breakpoint) in ResponsiveBreakpoint.allCases.enumerated() {
            XCTAssertEqual(session.document.pages[0].resolvedStructuralGeometry(breakpoint: breakpoint), expected[index])
        }
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == root.id }?
            .properties.first { $0.key == mobileX.key }, mobileX)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        var restored = session.document; restored.revision = linked.revision
        XCTAssertEqual(restored, linked)
        try session.redo()
        XCTAssertEqual(session.document.pages[0].resolvedStructuralGeometry(breakpoint: .mobile), expected[2])
    }

    func testComponentCreateResolveDetachAndExactHistory() throws {
        var document = BlankProjectDefaults.document()
        let pageID = document.pages[0].id
        let parentID = document.pages[0].rootNodeIDs[0]
        let root = DocumentNode(kind: .frame, name: "Card", parent: .node(parentID), properties:
            [("layout.x", 100.0), ("layout.y", 80.0), ("layout.width", 240.0), ("layout.height", 160.0)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        document.pages[0].nodes[0].childIDs = [root.id]
        document.pages[0].nodes.append(root)
        let session = DocumentSession(document: document)
        let sceneID = CanvasViewportSceneID()
        func prepare(_ edit: ComponentEdit) throws -> PreparedComponentEdit {
            try ComponentCommandRegistry().prepare(edit, identity: .init(documentID: document.id, pageID: pageID,
                revision: session.document.revision, sceneID: sceneID, rendererGeneration: session.document.revision),
                in: session.document, context: .init(activePageID: pageID, currentSceneID: sceneID,
                    rendererGeneration: session.document.revision, selectedNodeIDs: [root.id],
                    availableNodeIDs: [root.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        let created = try prepare(.create(root.id))
        try session.execute(created.command)
        XCTAssertEqual(session.document.componentDefinitions.count, 1)
        XCTAssertEqual(session.document.websitePages.count, 2)
        XCTAssertEqual(session.document.pages[0].nodes.last?.id, root.id)
        XCTAssertEqual(session.document.pages[0].nodes.last?.kind, .component)
        let resolved = try ComponentGraphResolver.resolvedPage(session.document.pages[0], in: session.document, breakpoint: .desktop)
        XCTAssertEqual(resolved.nodes.last?.insertionGeometry, root.insertionGeometry)
        XCTAssertEqual(resolved.nodes.last?.kind, .frame)
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)
        try session.undo()
        var restored = session.document; restored.revision = document.revision
        XCTAssertEqual(restored, document)
        try session.redo()
        let beforeDetach = session.document
        try session.execute(prepare(.detach(root.id)).command)
        XCTAssertEqual(session.document.pages[0].nodes.last?.kind, .frame)
        XCTAssertEqual(session.document.pages[0].nodes.last?.insertionGeometry, root.insertionGeometry)
        try session.undo()
        restored = session.document; restored.revision = beforeDetach.revision
        XCTAssertEqual(restored, beforeDetach)
    }

    func testComponentInstancesPropagateAcrossPagesAndSafeDeleteRestoresExactGraphs() throws {
        var document = BlankProjectDefaults.document()
        let homeID = document.pages[0].id, otherID = document.pages[1].id
        func node(_ name: String, parent: NodeParent, x: Double, width: Double) -> DocumentNode {
            DocumentNode(kind: .frame, name: name, parent: parent, properties:
                [("layout.x", x), ("layout.y", 100), ("layout.width", width), ("layout.height", 120)].map {
                    NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
                })
        }
        var root = node("Component", parent: .node(document.pages[0].rootNodeIDs[0]), x: 100, width: 240)
        let child = node("Child", parent: .node(root.id), x: 120, width: 60)
        root.childIDs = [child.id]
        document.pages[0].nodes[0].childIDs = [root.id]
        document.pages[0].nodes += [root, child]
        let session = DocumentSession(document: document)
        let sceneID = CanvasViewportSceneID()
        func prepare(_ edit: ComponentEdit, pageID: PageID, selected: [NodeID]) throws -> PreparedComponentEdit {
            try ComponentCommandRegistry().prepare(edit, identity: .init(documentID: document.id, pageID: pageID,
                revision: session.document.revision, sceneID: sceneID, rendererGeneration: session.document.revision),
                in: session.document, context: .init(activePageID: pageID, currentSceneID: sceneID,
                    rendererGeneration: session.document.revision, selectedNodeIDs: selected,
                    availableNodeIDs: Set(selected), isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        }
        let create = try prepare(.create(root.id), pageID: homeID, selected: [root.id])
        try session.execute(create.command)
        let definitionID = try XCTUnwrap(create.definitionID)
        let inserted = try prepare(.insert(definitionID: definitionID, parentID: document.pages[1].rootNodeIDs[0],
            geometry: .init(origin: .init(x: 400, y: 300), size: .init(width: 240, height: 120))), pageID: otherID, selected: [])
        try session.execute(inserted.command)
        let secondID = try XCTUnwrap(inserted.selectedNodeID)
        let definition = try XCTUnwrap(session.document.componentDefinitions.first)
        let masterChild = try XCTUnwrap(definition.nodes.first(where: { $0.name == "Child" }))
        let width = try XCTUnwrap(masterChild.properties.first(where: { $0.key.rawValue == "layout.width" }))
        try session.execute(.setProperty(.init(pageID: definitionID, nodeID: masterChild.id,
            property: .init(id: width.id, key: width.key, value: .number(90), origin: .authored))))
        let first = try ComponentGraphResolver.resolvedPage(session.document.pages[0], in: session.document, breakpoint: .desktop)
        let second = try ComponentGraphResolver.resolvedPage(session.document.pages[1], in: session.document, breakpoint: .desktop)
        let firstChild = try XCTUnwrap(first.nodes.first(where: { $0.name == "Child" }))
        let secondChild = try XCTUnwrap(second.nodes.first(where: { $0.name == "Child" }))
        XCTAssertEqual(firstChild.insertionGeometry?.size.width, 90)
        XCTAssertEqual(secondChild.insertionGeometry?.size.width, 90)
        XCTAssertNotEqual(firstChild.id, secondChild.id)
        XCTAssertEqual(second.nodes.first(where: { $0.id == secondID })?.insertionGeometry?.origin.x, 400)
        XCTAssertEqual(secondChild.insertionGeometry?.origin.x, 420)
        XCTAssertEqual(session.document.pages[0].nodes.count, 2, "Expanded children must never serialize into the instance page")
        XCTAssertThrowsError(try prepare(.delete(definitionID: definitionID, detachUses: false), pageID: homeID, selected: [root.id]))
        let before = session.document
        try session.execute(prepare(.delete(definitionID: definitionID, detachUses: true), pageID: homeID, selected: [root.id]).command)
        XCTAssertTrue(session.document.componentDefinitions.isEmpty)
        XCTAssertEqual(session.document.pages[0].nodes.first(where: { $0.id == root.id })?.kind, .frame)
        XCTAssertEqual(session.document.pages[1].nodes.first(where: { $0.id == secondID })?.kind, .frame)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        var restored = session.document; restored.revision = before.revision
        XCTAssertEqual(restored, before)
        try session.redo()
        XCTAssertTrue(session.document.componentDefinitions.isEmpty)
    }

    func testComponentInvalidCancelledAndStaleIdentityRemainNeutral() throws {
        var document = BlankProjectDefaults.document()
        let pageID = document.pages[0].id
        let root = DocumentNode(kind: .frame, name: "Private component name", parent: .node(document.pages[0].rootNodeIDs[0]), properties:
            [("layout.x", 100.0), ("layout.y", 80), ("layout.width", 240), ("layout.height", 160)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        document.pages[0].nodes[0].childIDs = [root.id]; document.pages[0].nodes.append(root)
        let scene = CanvasViewportSceneID()
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: pageID, revision: 0, sceneID: scene, rendererGeneration: 0)
        let context = TransformValidationContext(activePageID: pageID, currentSceneID: scene, rendererGeneration: 0,
            selectedNodeIDs: [root.id], availableNodeIDs: [root.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let registry = ComponentCommandRegistry()
        XCTAssertThrowsError(try registry.prepare(.create(root.id), identity: identity, in: document, context: context, cancelled: true))
        let stale: [DesignInspectorOperationIdentity] = [
            .init(documentID: DocumentID(), pageID: pageID, revision: 0, sceneID: scene, rendererGeneration: 0),
            .init(documentID: document.id, pageID: PageID(), revision: 0, sceneID: scene, rendererGeneration: 0),
            .init(documentID: document.id, pageID: pageID, revision: 1, sceneID: scene, rendererGeneration: 0),
            .init(documentID: document.id, pageID: pageID, revision: 0, sceneID: CanvasViewportSceneID(), rendererGeneration: 0),
            .init(documentID: document.id, pageID: pageID, revision: 0, sceneID: scene, rendererGeneration: 1),
        ]
        for value in stale { XCTAssertThrowsError(try registry.prepare(.create(root.id), identity: value, in: document, context: context)) }
        for selection in [[], [root.id, root.id], [NodeID()]] as [[NodeID]] {
            let changed = TransformValidationContext(activePageID: pageID, currentSceneID: scene, rendererGeneration: 0,
                selectedNodeIDs: selection, availableNodeIDs: [root.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
            XCTAssertThrowsError(try registry.prepare(.create(root.id), identity: identity, in: document, context: changed))
        }
        for key in ["locked", "hidden"] {
            var blocked = document
            blocked.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: key), value: .boolean(true)))
            XCTAssertThrowsError(try registry.prepare(.create(root.id), identity: identity, in: blocked, context: context))
        }
        var unsupported = document; unsupported.pages[0].nodes[1].kind = .text
        XCTAssertThrowsError(try registry.prepare(.create(root.id), identity: identity, in: unsupported, context: context))
        let diagnostics = CommandDiagnostics()
        diagnostics.recordComponentOperation(pageID: pageID, nodeIDs: [root.id], succeeded: false, durationMilliseconds: 1)
        XCTAssertEqual(diagnostics.records.last?.requirementIDs.first, "SF-0901-008")
        XCTAssertFalse(String(describing: diagnostics.records).contains(root.name))
        XCTAssertFalse(String(describing: diagnostics.records).contains(root.id.description))
        XCTAssertEqual(document.revision, 0)
        XCTAssertTrue(document.componentDefinitions.isEmpty)
    }

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
        XCTAssertTrue(json.contains("\"schemaVersion\":8"))
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
        let unknown = Data(valid.replacingOccurrences(of: "\"schemaVersion\":8", with: "\"schemaVersion\":99").utf8)
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
