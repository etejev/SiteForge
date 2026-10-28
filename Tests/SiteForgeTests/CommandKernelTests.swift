import Combine
import XCTest
@testable import SiteForge

@MainActor
final class CommandKernelTests: XCTestCase {
    // SF-0902-003/005, SF-0905-003/004: a shared default draft is not
    // discarded by renderer adoption, nor retargeted to a replacement binding.
    func testComponentDefinitionTextDraftRetainsPairedEditsAndDetectsBindingReplacement() {
        let document = DocumentID(), page = PageID(), scene = CanvasViewportSceneID(), node = NodeID()
        let binding = ComponentTextPropertyID()
        func identity(_ revision: UInt64) -> DesignInspectorOperationIdentity {
            .init(documentID: document, pageID: page, revision: revision, sceneID: scene, rendererGeneration: revision)
        }
        var draft = ComponentDefinitionTextDraft(label: "Title", content: "Original", bindingID: binding,
            identity: identity(1), selectionIDs: [node])
        draft.label.value = "Heading"; draft.content.value = "Unfinished default"
        draft.adopt(label: "Title", content: "Original", bindingID: binding, identity: nil, selectionIDs: [node])
        XCTAssertTrue(draft.isDirty); XCTAssertNil(draft.identity); XCTAssertFalse(draft.hasConflict)
        draft.adopt(label: "Title", content: "Original", bindingID: binding, identity: identity(2), selectionIDs: [node])
        XCTAssertEqual(draft.label.value, "Heading"); XCTAssertEqual(draft.content.value, "Unfinished default")
        XCTAssertEqual(draft.identity, identity(2))
        draft.adopt(label: "Title", content: "Original", bindingID: ComponentTextPropertyID(), identity: identity(3), selectionIDs: [node])
        XCTAssertTrue(draft.bindingConflict); XCTAssertNil(draft.identity)
        XCTAssertEqual(draft.bindingID, binding, "Retain the original draft binding, never retarget by label")
        draft = .init(label: "Title", content: "Current", bindingID: binding, identity: identity(4), selectionIDs: [node])
        XCTAssertFalse(draft.isDirty); XCTAssertFalse(draft.hasConflict)
        draft.content.value = "Local"
        draft.adopt(label: "Title", content: "External", bindingID: binding, identity: identity(5), selectionIDs: [node])
        XCTAssertTrue(draft.hasConflict); XCTAssertEqual(draft.content.value, "Local")
    }

    // SF-0901-003/006, SF-0902-003/006: source navigation uses typed stable
    // property identity across all six existing types, not names/virtual IDs.
    func testComponentPropertySourceDestinationsCoverExistingTypesAndRejectMissingDefinitions() throws {
        let document = try organizedComponentFixture(), definition = document.componentDefinitions[0]
        let page = document.websitePages[0]
        let instance = try XCTUnwrap(page.nodes.first { $0.kind == .component })
        let entries = CanonicalComponentOrganization.entries(in: definition)
        XCTAssertEqual(Set(entries.map { $0.id.organizationKind }), Set(CanonicalComponentOrganization.kinds))
        for entry in entries {
            let destination = try XCTUnwrap(ComponentPropertySourceDestination(document: document, pageID: page.id,
                instanceID: instance.id, property: entry.id))
            XCTAssertEqual(destination.definitionID, definition.id); XCTAssertEqual(destination.sourceNodeID, entry.sourceNodeID)
        }
        let property = try XCTUnwrap(entries.first?.id)
        XCTAssertNil(ComponentPropertySourceDestination(document: document, pageID: definition.id, instanceID: instance.id, property: property))
        XCTAssertNil(ComponentPropertySourceDestination(document: document, pageID: page.id, instanceID: NodeID(), property: property))
        XCTAssertNil(ComponentPropertySourceDestination(document: document, pageID: page.id, instanceID: instance.id,
            property: .text(ComponentTextPropertyID())))
        var missing = document; missing.pages.removeAll { $0.id == definition.id }
        XCTAssertNil(ComponentPropertySourceDestination(document: missing, pageID: page.id, instanceID: instance.id, property: property))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
    }

    private func awaitComponentSelection(_ state: WorkspaceShellState, page: PageID, ids: [NodeID]) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while state.effectiveSelectedPageID != page || state.selectionState.orderedIDs != ids
            || state.componentTextDraftIdentity == nil
            || state.canvasRenderPlan?.identity.viewportGeneration != state.viewportState.generation {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderReadCorrupt) }
            await Task.yield()
        }
    }

    // SF-0901-002/003/005/006, SF-0905-003/004/006: one edit boundary per
    // transition, exact return, rejected navigation and pinned Rename.
    func testComponentPropertySourceTransitionReturnsExactInstanceAndGuardsRenameContext() async throws {
        let session = try exposedTextSession(), document = session.document
        let definition = document.componentDefinitions[0], text = definition.nodes[1], page = document.websitePages[0]
        let binding = try XCTUnwrap(CanonicalComponentText.property(on: text))
        let instance = try XCTUnwrap(page.nodes.first { $0.kind == .component })
        let fixture = try ApplicationOwnedTestFixture.create("component-source-navigation")
        defer { try? fixture.cleanup() }
        let state = WorkspaceShellState(documentSession: session, lifecycle: .init(session: session,
            recoveryDirectory: fixture.url.appendingPathComponent("recovery"), autosaveDebouncer: ManualLifecycleAutosaveDebouncer()))
        state.resizeViewport(to: .init(width: 1000, height: 700), pixelRatio: 2)
        let deadline = ContinuousClock.now + .seconds(3)
        while state.componentTextDraftIdentity == nil {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderReadCorrupt) }; await Task.yield()
        }
        state.selectLayer(instance.id)
        try await awaitComponentSelection(state, page: page.id, ids: [instance.id])
        let origin = state.selectionState, history = session.historySnapshot().undoEntries.count
        var boundaries = 0, reject = false
        let subscription = state.editCommitRequests.sink { request in boundaries += 1; if reject { request.reject() } }
        defer { subscription.cancel() }
        let sourceContext = state.responsiveInspectorEditContext
        XCTAssertTrue(state.revealComponentPropertySource(instanceID: instance.id, property: .text(binding.id), expectedContext: sourceContext))
        XCTAssertEqual(boundaries, 1)
        try await awaitComponentSelection(state, page: definition.id, ids: [text.id])
        XCTAssertEqual(state.componentReturnActionTitle, "Return to Instance")
        XCTAssertEqual(state.inspectorTab, .content)
        state.exitComponentDefinition()
        XCTAssertEqual(boundaries, 2)
        try await awaitComponentSelection(state, page: page.id, ids: [instance.id])
        XCTAssertEqual(state.selectionState.orderedIDs, origin.orderedIDs)
        XCTAssertEqual(state.selectionState.primaryID, origin.primaryID)
        XCTAssertEqual(session.document, document); XCTAssertEqual(session.historySnapshot().undoEntries.count, history)
        reject = true
        XCTAssertFalse(state.revealComponentPropertySource(instanceID: instance.id, property: .text(binding.id), expectedContext: state.responsiveInspectorEditContext))
        state.revealComponentRecoverySource(instanceID: instance.id, property: .text(binding.id), identity: try XCTUnwrap(state.componentTextDraftIdentity))
        XCTAssertNil(state.editingComponentID); XCTAssertEqual(state.selectionState.orderedIDs, [instance.id])
        reject = false
        let renameContext = state.responsiveInspectorEditContext
        try session.execute(.renamePage(.init(pageID: page.id, name: "Unrelated website rename")))
        try await awaitComponentSelection(state, page: page.id, ids: [instance.id])
        let before = session.document
        XCTAssertFalse(state.renameComponent(definition.id, to: "Stale rename", expectedContext: renameContext))
        XCTAssertEqual(session.document, before)
        XCTAssertTrue(state.renameComponent(definition.id, to: "Renamed component", expectedContext: state.responsiveInspectorEditContext))
        XCTAssertEqual(session.document.componentDefinitions[0].id, definition.id)
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: try XCTUnwrap(session.document.websitePages[0].nodes.first { $0.id == instance.id })), definition.id)
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
    }

    // SF-0901-005, SF-0902-003/005, SF-0905-003/005: repeated definition
    // edits preserve overrides, existing appearance states and immutable output.
    // This is not variant-axis support (SF-0904 remains deferred).
    func testComponentSourceDefaultEditsKeepOverridesAppearanceStatesAndCompilerParity() async throws {
        let session = try exposedTextSession(), definition = session.document.componentDefinitions[0]
        let text = definition.nodes[1], binding = try XCTUnwrap(CanonicalComponentText.property(on: text))
        let page = session.document.websitePages[0]
        let instances = page.nodes.filter { $0.kind == .component }
        XCTAssertEqual(instances.count, 2)
        let first = instances[0].id, second = instances[1].id
        try session.execute(textCommand(.setTextOverride(instanceID: first, propertyID: binding.id, value: "Independent"),
            document: session.document, pageID: page.id, selected: first).command)
        let root = definition.rootNodeIDs[0], scene = CanvasViewportSceneID()
        let color = try XCTUnwrap(CanonicalSolidColor.parse(hexadecimal: "#224466FF"))
        let stateEdit = AdvancedStyleCommand(identity: .init(documentID: session.document.id, pageID: definition.id,
            revision: session.document.revision, sceneID: scene, rendererGeneration: session.document.revision),
            orderedNodeIDs: [root], edit: .setState(state: .hover, id: UUID(), fill: color, opacity: 0.6),
            provenance: .keyboard, cancelled: false)
        let prepared = try AdvancedStyleCommandRegistry().prepare(stateEdit, in: session.document,
            context: .init(activePageID: definition.id, currentSceneID: scene, rendererGeneration: session.document.revision,
                selectedNodeIDs: [root], availableNodeIDs: [root], isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        try session.execute(prepared.documentCommand)
        let before = session.document
        let previous = try await LocalPreviewRuntimeCompiler().compile(document: before, imageResourceData: [:], pixelRatio: .init(2))
        try session.execute(textCommand(.exposeText(nodeID: text.id, label: "Heading", defaultValue: "Shared first edit"),
            document: session.document, pageID: definition.id, selected: text.id).command)
        try session.execute(textCommand(.exposeText(nodeID: text.id, label: "Heading", defaultValue: "Shared second edit"),
            document: session.document, pageID: definition.id, selected: text.id).command)
        let committed = session.document
        let source = try XCTUnwrap(committed.componentDefinitions[0].nodes.first { $0.id == text.id })
        XCTAssertEqual(CanonicalComponentText.property(on: source)?.id, binding.id)
        XCTAssertEqual(source.insertionProperty(CanonicalComponentText.namespace + "id")?.id,
            text.insertionProperty(CanonicalComponentText.namespace + "id")?.id)
        XCTAssertEqual(committed.websitePages, before.websitePages)
        XCTAssertEqual(CanonicalComponentText.overrides(on: committed.websitePages[0].nodes.first { $0.id == first }!)[binding.id], "Independent")
        let rootAfter = try XCTUnwrap(committed.componentDefinitions[0].nodes.first { $0.id == root })
        let appearance = try CanonicalResolvedAppearance.resolve(node: rootAfter,
            index: CanonicalReusableStyleIndex(document: committed), state: .hover)
        XCTAssertEqual(appearance.fill, color); XCTAssertEqual(appearance.opacity, 0.6)
        func virtual(_ instance: NodeID) -> NodeID {
            NodeID(DocumentPage.deterministicUUID(namespace: instance.rawValue, label: "component-child:" + text.id.description))
        }
        let current = try await LocalPreviewRuntimeCompiler().compile(document: committed, imageResourceData: [:], pixelRatio: .init(2))
        XCTAssertEqual(current.pages.first { $0.id == page.id }?.objects.first { $0.id == virtual(first) }?.plainText, "Independent")
        XCTAssertEqual(current.pages.first { $0.id == page.id }?.objects.first { $0.id == virtual(second) }?.plainText, "Shared second edit")
        XCTAssertEqual(previous.pages.first { $0.id == page.id }?.objects.first { $0.id == virtual(second) }?.plainText, "Original")
        let output = try MultiPageStaticBuildPlanner.plan(document: committed)
        XCTAssertTrue(output.files.contains { $0.contents.contains("Independent") })
        XCTAssertTrue(output.files.contains { $0.contents.contains("Shared second edit") })
        XCTAssertTrue(output.files.contains { $0.contents.contains(":hover") })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(committed)), committed)
        try session.undo(); try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
        try session.redo(); try session.redo(); XCTAssertEqual(session.document.pages, committed.pages)
    }

    func testComponentRetainedDraftRejectsReplacementSelectionAndRepeatedAdoptionIsNeutral() {
        let document = DocumentID(), page = PageID(), scene = CanvasViewportSceneID(), first = NodeID(), other = NodeID()
        func identity(_ revision: UInt64) -> DesignInspectorOperationIdentity {
            .init(documentID: document, pageID: page, revision: revision, sceneID: scene, rendererGeneration: revision)
        }
        var draft = ComponentInstanceTextDraft(committed: "Inherited", identity: identity(1), selectionIDs: [first])
        draft.value = "Unfinished"
        for revision in UInt64(2)...4 { draft.adopt(committed: "Inherited", identity: identity(revision), selectionIDs: [first]) }
        XCTAssertEqual(draft.value, "Unfinished"); XCTAssertNil(draft.conflict)
        XCTAssertEqual(draft.identity, identity(4))
        draft.adopt(committed: "Inherited", identity: identity(5), selectionIDs: [other])
        XCTAssertEqual(draft.conflict, .contextChanged); XCTAssertNil(draft.identity)
        XCTAssertEqual(draft.value, "Unfinished")
        draft.cancel(committed: "Inherited", identity: identity(5), selectionIDs: [other])
        XCTAssertFalse(draft.isDirty); XCTAssertNil(draft.conflict)
        draft.adopt(committed: "New clean selection", identity: identity(6), selectionIDs: [first])
        XCTAssertNil(draft.conflict, "An untouched field must not block the new selection")
        XCTAssertEqual(draft.value, "New clean selection")
    }
    func testSelectedMediaAssetUseAndGlobalReferenceInventoryPreserveScope() throws {
        let document = try componentImageChoiceFixture(), session = DocumentSession(document: document)
        let definition = document.componentDefinitions[0], image = definition.nodes[1], oldAsset = document.imageAssets[0]
        try session.execute(textCommand(.exposeMedia(nodeID: image.id, label: "Hero"), document: session.document,
            pageID: definition.id, selected: image.id).command)
        let binding = try XCTUnwrap(CanonicalComponentMedia.property(on: session.document.componentDefinitions[0].nodes[1]))
        let page = session.document.websitePages[0], first = page.nodes[1].id, second = page.nodes[2].id
        let ordinary = DocumentNode(kind: .image, name: "Ordinary", parent: .node(page.rootNodeIDs[0]), properties: image.properties.map {
            .init(key: $0.key, value: $0.value, origin: $0.origin)
        })
        try session.execute(.insertNode(.init(pageID: page.id, node: ordinary, index: 2)))
        let fill = DocumentNode(kind: .frame, name: "Fill", parent: .node(page.rootNodeIDs[0]), properties: [
            .init(key: .init(rawValue: CanonicalImageFill.assetKey), value: .string(oldAsset.id.description))])
        try session.execute(.insertNode(.init(pageID: page.id, node: fill, index: 3)))
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id, metadata: .init(faviconAssetID: oldAsset.id))))
        try session.execute(textCommand(.setMediaOverride(instanceID: first, propertyID: binding.id, assetID: oldAsset.id),
            document: session.document, pageID: page.id, selected: first).command)
        let references = ImageAssetReference.references(to: oldAsset.id, in: session.document)
        XCTAssertEqual(references.count, 5)
        for kind in ImageAssetReference.Kind.allCases { XCTAssertEqual(references.filter { $0.kind == kind }.count, 1) }
        let alternate = ImageAsset(resourceID: ResourceID(), displayName: "Alternate", originalFilename: "alternate.png", format: .png,
            pixelWidth: 8, pixelHeight: 6, byteCount: 1, contentHash: String(repeating: "b", count: 64))
        try session.execute(.insertImageAsset(.init(asset: alternate, index: 1)))
        let scene = CanvasViewportSceneID(), before = session.document
        let request = ImageAssetUseRequest(identity: .init(documentID: before.id, pageID: page.id, revision: before.revision,
            sceneID: scene, rendererGeneration: before.revision, selectedNodeIDs: [first]), target: .componentMedia(instanceID: first, propertyID: binding.id))
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene, rendererGeneration: before.revision,
            selectedNodeIDs: [first], availableNodeIDs: [first], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let command = try ImageInspectorCommandRegistry().prepareAssetUse(alternate.id, request: request, in: before, context: context)
        try session.execute(command)
        XCTAssertEqual(CanonicalComponentMedia.overrides(on: session.document.websitePages[0].nodes[1])[binding.id], alternate.id)
        XCTAssertTrue(CanonicalComponentMedia.overrides(on: session.document.websitePages[0].nodes[2]).isEmpty)
        XCTAssertEqual(session.document.websitePages[0].nodes[2].id, second)
        XCTAssertEqual(session.document.componentDefinitions, before.componentDefinitions)
        XCTAssertEqual(session.document.imageAssets, before.imageAssets)
        XCTAssertEqual(ImageAssetReference.references(to: oldAsset.id, in: session.document).count, 4)
        let local = session.document
        var global = oldAsset; global.resourceID = ResourceID(); global.contentHash = String(repeating: "c", count: 64)
        try session.execute(.updateImageAsset(.init(asset: global)))
        XCTAssertEqual(session.document.pages, local.pages)
        XCTAssertEqual(ImageAssetReference.references(to: oldAsset.id, in: session.document).count, 4)
        try session.undo(); XCTAssertEqual(session.document.imageAssets, local.imageAssets)
        try session.undo(); XCTAssertEqual(session.document.pages, before.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, local.pages)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testComponentNamedCreationIsAtomicAndPreservesSourceIdentity() throws {
        var document = BlankProjectDefaults.document()
        let parent = document.pages[0].rootNodeIDs[0]
        let root = DocumentNode(kind: .frame, name: "Frame", parent: .node(parent), properties:
            [("layout.x", 100.0), ("layout.y", 80.0), ("layout.width", 240.0), ("layout.height", 160.0)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        document.pages[0].nodes[0].childIDs = [root.id]
        document.pages[0].nodes.append(root)
        let session = DocumentSession(document: document), pageID = document.pages[0].id
        for invalid in ["", "\n", String(repeating: "a", count: 257)] {
            XCTAssertThrowsError(try textCommand(.createNamed(root.id, name: invalid), document: document,
                pageID: pageID, selected: root.id))
            XCTAssertEqual(session.document, document)
        }
        try session.execute(textCommand(.createNamed(root.id, name: "Editorial Card"), document: document,
            pageID: pageID, selected: root.id).command)
        let created = session.document
        XCTAssertEqual(created.componentDefinitions.first?.name, "Editorial Card")
        let instance = try XCTUnwrap(created.pages[0].nodes.first { $0.id == root.id })
        XCTAssertEqual(instance.name, "Editorial Card")
        XCTAssertEqual(instance.kind, .component)
        XCTAssertEqual(instance.insertionGeometry, root.insertionGeometry)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(created)), created)
        try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, created.pages)
        XCTAssertThrowsError(try ComponentCommandRegistry.creationSourceIDs(instance.id,
            page: created.pages[0], document: created))
    }

    func testComponentNamedCreationCancelledStaleDuplicateAndUnsupportedAreNeutral() throws {
        var document = BlankProjectDefaults.document()
        let pageID = document.pages[0].id, parent = document.pages[0].rootNodeIDs[0]
        let root = DocumentNode(kind: .frame, name: "Card", parent: .node(parent), properties:
            [("layout.x", 10.0), ("layout.y", 20.0), ("layout.width", 240.0), ("layout.height", 160.0)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        document.pages[0].nodes[0].childIDs = [root.id]
        document.pages[0].nodes.append(root)
        let scene = CanvasViewportSceneID(), registry = ComponentCommandRegistry()
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: pageID,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        let context = TransformValidationContext(activePageID: pageID, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [root.id], availableNodeIDs: [root.id],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try registry.prepare(.createNamed(root.id, name: "Card"), identity: identity,
            in: document, context: context, cancelled: true))
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.createNamed(root.id, name: "Card"), document: document,
            pageID: pageID, selected: root.id).command)
        let duplicate = DocumentNode(kind: .frame, name: "Other", parent: .node(parent), properties: root.properties.map {
            NodeProperty(key: $0.key, value: $0.value, origin: $0.origin)
        })
        try session.execute(.insertNode(.init(pageID: pageID, node: duplicate, index: 1)))
        let before = session.document
        XCTAssertThrowsError(try textCommand(.createNamed(duplicate.id, name: "cArD"), document: before,
            pageID: pageID, selected: duplicate.id))
        XCTAssertThrowsError(try registry.prepare(.createNamed(root.id, name: "Stale"), identity: identity,
            in: before, context: context))
        XCTAssertEqual(session.document, before)
        for kind in [NodeKind.text, .image, .button, .component] {
            var unsupported = document
            unsupported.pages[0].nodes[1].kind = kind
            XCTAssertThrowsError(try ComponentCommandRegistry.creationSourceIDs(root.id,
                page: unsupported.pages[0], document: unsupported))
        }
    }

    func testComponentConnectedReusePropagationResetHistoryAndImmutableOutput() async throws {
        let session = try exposedTextSession()
        let definition = session.document.componentDefinitions[0], text = definition.nodes[1]
        let binding = try XCTUnwrap(CanonicalComponentText.property(on: text))
        try session.execute(textCommand(.exposeVisibility(nodeID: text.id, label: "Show title", defaultValue: true),
            document: session.document, pageID: definition.id, selected: text.id).command)
        let visibility = try XCTUnwrap(CanonicalComponentVisibility.property(on: session.document.componentDefinitions[0].nodes[1]))
        let page = session.document.websitePages[0], first = page.nodes[1].id, second = page.nodes[2].id
        func apply(_ edit: ComponentEdit, pageID: PageID, selected: NodeID) throws {
            try session.execute(textCommand(edit, document: session.document, pageID: pageID, selected: selected).command)
        }
        try apply(.setTextOverride(instanceID: first, propertyID: binding.id, value: "Independent title"), pageID: page.id, selected: first)
        try apply(.exposeText(nodeID: text.id, label: "Title", defaultValue: "Shared revised title"), pageID: definition.id, selected: text.id)
        func virtual(_ instance: NodeID) -> NodeID {
            NodeID(DocumentPage.deterministicUUID(namespace: instance.rawValue, label: "component-child:" + text.id.description))
        }
        let old = try await LocalPreviewRuntimeCompiler().compile(document: session.document, imageResourceData: [:], pixelRatio: .init(2))
        XCTAssertEqual(old.pages.first { $0.id == page.id }?.objects.first { $0.id == virtual(first) }?.plainText, "Independent title")
        XCTAssertEqual(old.pages.first { $0.id == page.id }?.objects.first { $0.id == virtual(second) }?.plainText, "Shared revised title")
        let output = try MultiPageStaticBuildPlanner.plan(document: session.document)
        XCTAssertTrue(output.files.contains { $0.contents.contains("Independent title") })
        XCTAssertTrue(output.files.contains { $0.contents.contains("Shared revised title") })
        try apply(.setVisibilityOverride(instanceID: first, propertyID: visibility.id, value: false), pageID: page.id, selected: first)
        let retained = session.document.pages
        let hidden = try await LocalPreviewRuntimeCompiler().compile(document: session.document, imageResourceData: [:], pixelRatio: .init(1))
        XCTAssertNil(hidden.pages.first { $0.id == page.id }?.objects.first { $0.id == virtual(first) })
        try apply(.resetAllOverrides(first), pageID: page.id, selected: first)
        XCTAssertTrue(CanonicalComponentText.overrides(on: session.document.pages[0].nodes[1]).isEmpty)
        XCTAssertTrue(CanonicalComponentVisibility.overrides(on: session.document.pages[0].nodes[1]).isEmpty)
        let reset = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, retained)
        try session.redo(); XCTAssertEqual(session.document.pages, reset)
        let current = try await LocalPreviewRuntimeCompiler().compile(document: session.document, imageResourceData: [:], pixelRatio: .init(2))
        for id in [first, second] {
            XCTAssertEqual(current.pages.first { $0.id == page.id }?.objects.first { $0.id == virtual(id) }?.plainText, "Shared revised title")
        }
        XCTAssertEqual(old.pages.first { $0.id == page.id }?.objects.first { $0.id == virtual(first) }?.plainText, "Independent title")
        XCTAssertEqual(current.revision, session.document.revision)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testComponentDefinitionReturnContextRestoresOrderedSelectionAndRejectsReplacement() throws {
        let document = try componentTextFixture(), page = document.pages[0]
        let ids = [page.nodes[2].id, page.nodes[1].id]
        var selection = SelectionState()
        selection.setSelection(ids, primary: ids[0], anchor: ids[1], provenance: .layersNavigator)
        let context = try XCTUnwrap(ComponentDefinitionReturnContext(document: document, pageID: page.id, selection: selection))
        XCTAssertEqual(context.resolve(in: document)?.selection, selection)
        XCTAssertEqual(context.resolve(in: document)?.selection?.orderedIDs, ids)
        var changed = document
        changed.pages[0].nodes.removeAll { $0.id == ids[0] }
        XCTAssertEqual(context.resolve(in: changed)?.reason, .selectionUnavailable)
        XCTAssertNil(context.resolve(in: changed)?.selection)
        changed = document
        changed.pages.removeAll { $0.id == page.id }
        XCTAssertEqual(context.resolve(in: changed)?.reason, .pageUnavailable)
        XCTAssertNil(context.resolve(in: changed)?.selection)
        let replacement = BlankProjectDefaults.document()
        XCTAssertNil(context.resolve(in: replacement))
        var single = SelectionState()
        single.setSelection([ids[0]], primary: ids[0], anchor: ids[0], provenance: .layersNavigator)
        XCTAssertTrue(try XCTUnwrap(ComponentDefinitionReturnContext(document: document, pageID: page.id, selection: single)).returnsToInstance)
    }

    func testComponentDefinitionReturnContextDoesNotSelectRetargetedLockedOrHiddenInstances() throws {
        let document = try componentTextFixture(), page = document.pages[0], node = page.nodes[1]
        var selection = SelectionState()
        selection.setSelection([node.id], primary: node.id, anchor: node.id, provenance: .pointer)
        let context = try XCTUnwrap(ComponentDefinitionReturnContext(document: document, pageID: page.id, selection: selection))
        for key in ["locked", "hidden"] {
            var changed = document
            changed.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: key), value: .boolean(true), origin: .authored))
            XCTAssertEqual(context.resolve(in: changed)?.reason, .selectionUnavailable)
            XCTAssertNil(context.resolve(in: changed)?.selection)
        }
        var changed = document
        changed.pages[0].nodes[1].kind = .frame
        XCTAssertEqual(context.resolve(in: changed)?.reason, .selectionUnavailable)
        selection.setSelection([node.id], primary: node.id, anchor: node.id, provenance: .layersNavigator)
        let layers = try XCTUnwrap(ComponentDefinitionReturnContext(document: document, pageID: page.id, selection: selection))
        changed = document
        changed.pages[0].nodes[1].properties.append(.init(key: .init(rawValue: "hidden"), value: .boolean(true), origin: .authored))
        XCTAssertEqual(layers.resolve(in: changed)?.selection, selection, "Layers inspection does not fabricate a canvas target")
    }

    func testComponentTextDraftAdoptionPreservesTypingAndRejectsConflictingContext() throws {
        let document = try componentTextFixture(), page = document.pages[0], scene = CanvasViewportSceneID()
        func identity(_ revision: UInt64, sceneID: CanvasViewportSceneID? = nil) -> DesignInspectorOperationIdentity {
            .init(documentID: document.id, pageID: page.id, revision: revision,
                sceneID: sceneID ?? scene, rendererGeneration: revision)
        }
        var draft = ComponentInstanceTextDraft(committed: "Original", identity: identity(1))
        draft.value = "Typing"
        draft.adopt(committed: "Original", identity: identity(2))
        XCTAssertEqual(draft.value, "Typing")
        XCTAssertEqual(draft.identity, identity(2))
        draft.adopt(committed: "Typing", identity: nil)
        XCTAssertFalse(draft.isDirty)
        XCTAssertNil(draft.identity, "A successful event must not be repeated while renderer adoption is pending")
        draft.adopt(committed: "Typing", identity: identity(3))
        XCTAssertEqual(draft.identity, identity(3))
        XCTAssertNil(draft.conflict)
        draft.value = "Local"
        draft.adopt(committed: "Remote", identity: identity(4))
        XCTAssertEqual(draft.value, "Local")
        XCTAssertEqual(draft.conflict, .valueChanged)
        XCTAssertNil(draft.identity)
        draft.cancel(committed: "Remote", identity: identity(4))
        XCTAssertEqual(draft.value, "Remote")
        XCTAssertFalse(draft.isDirty)
        draft.value = "Do not send to another scene"
        draft.adopt(committed: "Elsewhere", identity: identity(5, sceneID: CanvasViewportSceneID()))
        XCTAssertEqual(draft.conflict, .contextChanged)
        XCTAssertNil(draft.identity)
        XCTAssertEqual(draft.value, "Do not send to another scene")
    }

    func testContextualColorTargetUsesWholeSelectionWithoutPrimaryBorrowing() {
        XCTAssertEqual(LocalColorTarget.initialInspectorTarget(for: []), .fill)
        XCTAssertEqual(LocalColorTarget.initialInspectorTarget(for: [.text]), .textForeground)
        XCTAssertEqual(LocalColorTarget.initialInspectorTarget(for: [.text, .text]), .textForeground)
        XCTAssertEqual(LocalColorTarget.initialInspectorTarget(for: [.text, .frame]), .fill)
        XCTAssertEqual(LocalColorTarget.initialInspectorTarget(for: [.frame, .text]), .fill)
        XCTAssertEqual(LocalColorTarget.initialInspectorTarget(for: [.button]), .fill)
    }
    private func componentTextFixture() throws -> CanonicalDocument {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "schema-v7-linked-text-document", withExtension: "json", subdirectory: "Legacy"))
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

    private func exposedVisibilitySession(defaultVisible: Bool = false) throws -> DocumentSession {
        let document = try componentTextFixture(), definition = document.componentDefinitions[0]
        let child = definition.nodes[1]
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.exposeVisibility(nodeID: child.id, label: "Optional text",
            defaultValue: defaultVisible), document: document, pageID: definition.id, selected: child.id).command)
        return session
    }

    private func componentImageChoiceFixture() throws -> CanonicalDocument {
        var document = try componentTextFixture()
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Hero", originalFilename: "hero.png",
            format: .png, pixelWidth: 400, pixelHeight: 300, byteCount: 1,
            contentHash: String(repeating: "a", count: 64))
        document.imageAssets = [asset]
        let definitionIndex = try XCTUnwrap(document.pages.firstIndex { $0.role == .componentDefinition })
        var child = document.pages[definitionIndex].nodes[1]
        child.kind = .image
        child.name = "Hero Image"
        child.properties.removeAll { $0.key.rawValue == "content.text" || CanonicalComponentText.metadataKeys.contains($0.key.rawValue) }
        child.properties += [
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"), value: .string(asset.id.description), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string(ImageFitMode.fit.rawValue), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string("Hero"), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(false), origin: .defaulted),
        ]
        document.pages[definitionIndex].nodes[1] = child
        try document.validate()
        return document
    }

    func testComponentImageFitChoiceOverrideResetHistoryRendererAndPersistence() throws {
        let initial = try componentImageChoiceFixture()
        let definition = initial.componentDefinitions[0], image = definition.nodes[1]
        let session = DocumentSession(document: initial)
        try session.execute(textCommand(.exposeChoice(nodeID: image.id, label: "Image Fit"),
            document: session.document, pageID: definition.id, selected: image.id).command)
        let exposedDefinition = session.document.componentDefinitions[0]
        let binding = try XCTUnwrap(CanonicalComponentChoice.property(on: exposedDefinition.nodes[1]))
        XCTAssertEqual(binding.defaultValue, .fit)

        let page = session.document.websitePages[0], instance = page.nodes[1]
        try session.execute(textCommand(.setChoiceOverride(instanceID: instance.id, propertyID: binding.id, value: .fill),
            document: session.document, pageID: page.id, selected: instance.id).command)
        let authored = session.document
        XCTAssertEqual(CanonicalComponentChoice.overrides(on: authored.websitePages[0].nodes[1])[binding.id], .fill)
        let derivedID = NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue,
            label: "component-child:" + image.id.description))
        let resolved = try ComponentGraphResolver.resolvedPage(authored.websitePages[0], in: authored, breakpoint: .desktop)
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(resolved.nodes.first { $0.id == derivedID }))?.fitMode, .fill)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(authored)), authored)
        try session.undo()
        XCTAssertTrue(CanonicalComponentChoice.overrides(on: session.document.websitePages[0].nodes[1]).isEmpty)
        try session.redo()
        XCTAssertEqual(CanonicalComponentChoice.overrides(on: session.document.websitePages[0].nodes[1])[binding.id], .fill)
        try session.execute(textCommand(.resetChoiceOverride(instanceID: instance.id, propertyID: binding.id),
            document: session.document, pageID: page.id, selected: instance.id).command)
        let inherited = try ComponentGraphResolver.resolvedPage(session.document.websitePages[0], in: session.document,
            breakpoint: .desktop)
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(inherited.nodes.first { $0.id == derivedID }))?.fitMode, .fit)

        let stale = DesignInspectorOperationIdentity(documentID: session.document.id, pageID: page.id,
            revision: 0, sceneID: CanvasViewportSceneID(), rendererGeneration: 0)
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(.setChoiceOverride(instanceID: instance.id,
            propertyID: binding.id, value: .stretch), identity: stale, in: session.document,
            context: .init(activePageID: page.id, currentSceneID: stale.sceneID, rendererGeneration: session.document.revision,
                selectedNodeIDs: [instance.id], availableNodeIDs: [instance.id], isLifecycleAvailable: true,
                lifecycleDisabledReason: nil)))
    }

    func testComponentImageMediaOverrideResetHistoryRendererPersistenceAndValidation() throws {
        var initial = try componentImageChoiceFixture()
        let alternate = ImageAsset(resourceID: ResourceID(), displayName: "Alternate", originalFilename: "alternate.png",
            format: .png, pixelWidth: 640, pixelHeight: 480, byteCount: 1,
            contentHash: String(repeating: "b", count: 64))
        initial.imageAssets.append(alternate)
        let definition = initial.componentDefinitions[0], image = definition.nodes[1]
        let session = DocumentSession(document: initial)
        try session.execute(textCommand(.exposeMedia(nodeID: image.id, label: "Hero Image"),
            document: session.document, pageID: definition.id, selected: image.id).command)
        let exposed = session.document.componentDefinitions[0]
        let binding = try XCTUnwrap(CanonicalComponentMedia.property(on: exposed.nodes[1]))
        XCTAssertEqual(binding.defaultValue, initial.imageAssets[0].id)

        let page = session.document.websitePages[0], instance = page.nodes[1]
        try session.execute(textCommand(.setMediaOverride(instanceID: instance.id,
            propertyID: binding.id, assetID: alternate.id), document: session.document,
            pageID: page.id, selected: instance.id).command)
        let authored = session.document
        XCTAssertEqual(CanonicalComponentMedia.overrides(on: authored.websitePages[0].nodes[1])[binding.id], alternate.id)
        let derivedID = NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue,
            label: "component-child:" + image.id.description))
        let resolved = try ComponentGraphResolver.resolvedPage(authored.websitePages[0], in: authored, breakpoint: .desktop)
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(resolved.nodes.first { $0.id == derivedID }))?.assetID,
            alternate.id)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(authored)), authored)
        let forgedSchema11 = Data(String(decoding: try DocumentSerializer.encode(authored), as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":11").utf8)
        XCTAssertThrowsError(try DocumentSerializer.decode(forgedSchema11))

        try session.undo()
        XCTAssertTrue(CanonicalComponentMedia.overrides(on: session.document.websitePages[0].nodes[1]).isEmpty)
        try session.redo()
        XCTAssertEqual(CanonicalComponentMedia.overrides(on: session.document.websitePages[0].nodes[1])[binding.id], alternate.id)
        try session.execute(textCommand(.resetMediaOverride(instanceID: instance.id, propertyID: binding.id),
            document: session.document, pageID: page.id, selected: instance.id).command)
        let inherited = try ComponentGraphResolver.resolvedPage(session.document.websitePages[0], in: session.document,
            breakpoint: .desktop)
        XCTAssertEqual(CanonicalImageStyle.resolve(try XCTUnwrap(inherited.nodes.first { $0.id == derivedID }))?.assetID,
            initial.imageAssets[0].id)

        XCTAssertThrowsError(try textCommand(.setMediaOverride(instanceID: instance.id,
            propertyID: binding.id, assetID: AssetID()), document: session.document,
            pageID: page.id, selected: instance.id))
        let scene = CanvasViewportSceneID()
        let identity = DesignInspectorOperationIdentity(documentID: session.document.id, pageID: page.id,
            revision: session.document.revision, sceneID: scene, rendererGeneration: session.document.revision)
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: session.document.revision, selectedNodeIDs: [instance.id],
            availableNodeIDs: [instance.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(.setMediaOverride(instanceID: instance.id,
            propertyID: binding.id, assetID: alternate.id), identity: identity,
            in: session.document, context: context, cancelled: true))
        let mixedContext = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: session.document.revision,
            selectedNodeIDs: [instance.id, page.rootNodeIDs[0]],
            availableNodeIDs: [instance.id, page.rootNodeIDs[0]],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(.setMediaOverride(instanceID: instance.id,
            propertyID: binding.id, assetID: alternate.id), identity: identity,
            in: session.document, context: mixedContext))
    }

    func testComponentActionOverrideResetHistoryRendererPersistenceAndValidation() throws {
        var initial = try componentTextFixture()
        let definitionIndex = try XCTUnwrap(initial.pages.firstIndex { $0.role == .componentDefinition })
        var control = initial.pages[definitionIndex].nodes[1]
        control.kind = .button
        control.name = "Call to Action"
        control.properties.removeAll {
            $0.key.rawValue == "content.text" || CanonicalComponentText.metadataKeys.contains($0.key.rawValue)
        }
        control.properties.append(.init(key: .init(rawValue: CanonicalLinkTarget.labelKey),
            value: .string("Learn more"), origin: .authored))
        initial.pages[definitionIndex].nodes[1] = control
        try initial.validate()

        let definition = initial.componentDefinitions[0]
        let session = DocumentSession(document: initial)
        try session.execute(textCommand(.exposeAction(nodeID: control.id, label: "Destination"),
            document: session.document, pageID: definition.id, selected: control.id).command)
        let exposed = session.document.componentDefinitions[0]
        let binding = try XCTUnwrap(CanonicalComponentAction.property(on: exposed.nodes[1]))
        XCTAssertEqual(binding.defaultValue, .none)

        let page = session.document.websitePages[0], instance = page.nodes[1]
        let target = CanonicalLinkTarget.external("https://example.com/components")
        try session.execute(textCommand(.setActionOverride(instanceID: instance.id,
            propertyID: binding.id, target: target), document: session.document,
            pageID: page.id, selected: instance.id).command)
        XCTAssertEqual(CanonicalComponentAction.overrides(on: session.document.websitePages[0].nodes[1])[binding.id], target)
        let derivedID = NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue,
            label: "component-child:" + control.id.description))
        let resolved = try ComponentGraphResolver.resolvedPage(session.document.websitePages[0],
            in: session.document, breakpoint: .desktop)
        XCTAssertEqual(try CanonicalLinkTarget.resolve(try XCTUnwrap(resolved.nodes.first { $0.id == derivedID })), target)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let forgedSchema12 = Data(String(decoding: try DocumentSerializer.encode(session.document), as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":12").utf8)
        XCTAssertThrowsError(try DocumentSerializer.decode(forgedSchema12))

        try session.undo()
        XCTAssertTrue(CanonicalComponentAction.overrides(on: session.document.websitePages[0].nodes[1]).isEmpty)
        try session.redo()
        XCTAssertEqual(CanonicalComponentAction.overrides(on: session.document.websitePages[0].nodes[1])[binding.id], target)
        try session.execute(textCommand(.resetActionOverride(instanceID: instance.id, propertyID: binding.id),
            document: session.document, pageID: page.id, selected: instance.id).command)
        XCTAssertTrue(CanonicalComponentAction.overrides(on: session.document.websitePages[0].nodes[1]).isEmpty)
        XCTAssertNil(CanonicalComponentAction.decode("external:not-base64"))
    }

    func testComponentActionCodecRetainsNoneAndStrictDestinationIntent() {
        let page = PageID(), section = NodeID()
        let values: [CanonicalLinkTarget] = [.none, .page(page), .section(pageID: page, nodeID: section),
                                           .external("https://example.com/path?q=a%20b#anchor")]
        for value in values { XCTAssertEqual(CanonicalComponentAction.decode(CanonicalComponentAction.encode(value)), value) }
        for invalid in ["", "None", "none:extra", "page:invalid", "section:\(page):invalid", "external:%%%%",
                        CanonicalComponentAction.encode(.external("https://user:password@example.com")),
                        CanonicalComponentAction.encode(.external("file:///private/file")), String(repeating: "a", count: 11_001)] {
            XCTAssertNil(CanonicalComponentAction.decode(invalid))
        }
    }

    private func exposedActionSession() throws -> (DocumentSession, NodeID, ComponentActionPropertyID) {
        var document = try componentTextFixture()
        let index = try XCTUnwrap(document.pages.firstIndex { $0.role == .componentDefinition })
        var node = document.pages[index].nodes[1]
        node.kind = .link
        node.properties.removeAll { $0.key.rawValue == "content.text" || CanonicalComponentText.metadataKeys.contains($0.key.rawValue) }
        document.pages[index].nodes[1] = node
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.exposeAction(nodeID: node.id, label: "Destination"), document: document,
            pageID: document.pages[index].id, selected: node.id).command)
        return (session, node.id, try XCTUnwrap(CanonicalComponentAction.property(on: session.document.componentDefinitions[0].nodes[1])).id)
    }

    func testComponentActionRegistryRejectsCancelledStaleMalformedAndMissingDestinations() throws {
        let (session, _, propertyID) = try exposedActionSession()
        let document = session.document, page = document.websitePages[0], instance = page.nodes[1]
        let scene = CanvasViewportSceneID()
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: page.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [instance.id], availableNodeIDs: [instance.id],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let edit = ComponentEdit.setActionOverride(instanceID: instance.id, propertyID: propertyID, target: .none)
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: identity, in: document, context: context, cancelled: true))
        let stale: [DesignInspectorOperationIdentity] = [
            .init(documentID: DocumentID(), pageID: page.id, revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: PageID(), revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: page.id, revision: document.revision - 1, sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: page.id, revision: document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: page.id, revision: document.revision, sceneID: scene, rendererGeneration: document.revision - 1)]
        for captured in stale { XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: captured, in: document, context: context)) }
        let mixed = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [instance.id, page.rootNodeIDs[0]],
            availableNodeIDs: [instance.id, page.rootNodeIDs[0]], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: identity, in: document, context: mixed))
        let invalidTargets: [CanonicalLinkTarget] = [.page(PageID()), .section(pageID: page.id, nodeID: NodeID()),
                                                     .external("javascript:alert(1)"), .external("https://example.com/a b")]
        for target in invalidTargets {
            XCTAssertThrowsError(try textCommand(.setActionOverride(instanceID: instance.id, propertyID: propertyID, target: target),
                document: document, pageID: page.id, selected: instance.id))
        }
        XCTAssertEqual(session.document, document)
    }

    func testComponentActionMissingBindingResetAllAndRetargetGuardPreserveExactHistory() throws {
        let (session, controlID, propertyID) = try exposedActionSession()
        let page = session.document.websitePages[0], instance = page.nodes[1], definitionID = session.document.componentDefinitions[0].id
        let target = CanonicalLinkTarget.page(page.id)
        try session.execute(textCommand(.setActionOverride(instanceID: instance.id, propertyID: propertyID, target: target),
            document: session.document, pageID: page.id, selected: instance.id).command)
        let authored = session.document
        let valueID = try XCTUnwrap(authored.websitePages[0].nodes[1].insertionProperty(CanonicalComponentAction.overrideKey(propertyID))).id
        var retargeted = authored.componentDefinitions[0]
        let oldIndex = try XCTUnwrap(retargeted.nodes.firstIndex { $0.id == controlID })
        let old = retargeted.nodes[oldIndex]
        retargeted.nodes[oldIndex].properties.removeAll { CanonicalComponentAction.metadataKeys.contains($0.key.rawValue) }
        let newID = NodeID()
        let replacement = DocumentNode(id: newID, kind: old.kind, name: old.name, parent: old.parent,
            childIDs: old.childIDs, properties: old.properties.map { .init(id: PropertyID(), key: $0.key, value: $0.value, origin: $0.origin) })
        retargeted.nodes.append(replacement)
        retargeted.nodes[0].childIDs.append(newID)
        let index = try XCTUnwrap(authored.pages.firstIndex { $0.id == definitionID })
        XCTAssertThrowsError(try session.execute(.batch([.removePage(.init(pageID: definitionID)), .insertPage(.init(page: retargeted, index: index))])))
        XCTAssertEqual(session.document, authored)
        try session.execute(textCommand(.removeActionProperty(controlID), document: session.document,
            pageID: definitionID, selected: controlID).command)
        let projected = try CanonicalComponentOverrides.resolve(instance: session.document.websitePages[0].nodes[1], document: session.document)
        XCTAssertTrue(projected.contains { $0.property == .action(propertyID) && $0.resolution == .conflict(.missingProperty, propertyID: valueID) })
        try session.execute(textCommand(.resetAllOverrides(instance.id), document: session.document, pageID: page.id, selected: instance.id).command)
        XCTAssertTrue(CanonicalComponentAction.overrides(on: session.document.websitePages[0].nodes[1]).isEmpty)
        try session.undo()
        XCTAssertEqual(session.document.websitePages[0].nodes[1].insertionProperty(CanonicalComponentAction.overrideKey(propertyID))?.id, valueID)
        try session.undo()
        XCTAssertEqual(session.document.pages, authored.pages)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testComponentActionLinkDestinationReachesImmutablePreviewAndStaticOutput() async throws {
        let (session, controlID, bindingID) = try exposedActionSession()
        let page = session.document.websitePages[0], instance = page.nodes[1]
        let external = CanonicalLinkTarget.external("https://example.com/authored-action")
        try session.execute(textCommand(.setActionOverride(instanceID: instance.id, propertyID: bindingID, target: external),
            document: session.document, pageID: page.id, selected: instance.id).command)
        let expectedID = NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue,
            label: "component-child:" + controlID.description))
        let runtime = try await LocalPreviewRuntimeCompiler().compile(document: session.document,
            imageResourceData: [:], pixelRatio: .init(1))
        let rendered = try XCTUnwrap(runtime.pages.first { $0.id == page.id }?.objects.first { $0.id == expectedID })
        XCTAssertEqual(rendered.previewLink?.target, external)
        XCTAssertEqual(rendered.previewLink?.isMissing, false)
        XCTAssertEqual(runtime.revision, session.document.revision)
        let output = try MultiPageStaticBuildPlanner.plan(document: session.document)
        XCTAssertTrue(output.files.contains { $0.contents.contains("href=\"https://example.com/authored-action\"") })

        let definition = session.document.componentDefinitions[0]
        let sectionID = NodeID()
        let section = DocumentNode(id: sectionID, kind: .section, name: "Internal destination", parent: .node(definition.rootNodeIDs[0]), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(12), origin: .defaulted),
            .init(key: .init(rawValue: "layout.y"), value: .number(60), origin: .defaulted),
            .init(key: .init(rawValue: "layout.width"), value: .number(160), origin: .defaulted),
            .init(key: .init(rawValue: "layout.height"), value: .number(80), origin: .defaulted),
            .init(key: .init(rawValue: "layout.container.kind"), value: .string("section"), origin: .defaulted),
            .init(key: .init(rawValue: "layout.padding"), value: .number(0), origin: .defaulted),
            .init(key: .init(rawValue: "layout.axis"), value: .string("vertical"), origin: .defaulted)])
        try session.execute(.insertNode(.init(pageID: definition.id, node: section, index: 1)))
        try session.execute(textCommand(.setActionOverride(instanceID: instance.id, propertyID: bindingID,
            target: .section(pageID: definition.id, nodeID: sectionID)), document: session.document,
            pageID: page.id, selected: instance.id).command)
        let updated = try await LocalPreviewRuntimeCompiler().compile(document: session.document,
            imageResourceData: [:], pixelRatio: .init(1))
        let virtualSectionID = NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue,
            label: "component-child:" + sectionID.description))
        let updatedLink = try XCTUnwrap(updated.pages.first { $0.id == page.id }?.objects.first { $0.id == expectedID }?.previewLink)
        XCTAssertEqual(updatedLink.target, .section(pageID: page.id, nodeID: virtualSectionID))
        XCTAssertFalse(updatedLink.isMissing, "A section in the immutable expanded graph is a valid Preview destination")
        XCTAssertEqual(rendered.previewLink?.target, external, "The old immutable snapshot must not adopt later edits")
    }

    func testComponentActionPageRenameRemovalAndDuplicationPreserveStableIntent() throws {
        let (session, _, bindingID) = try exposedActionSession()
        let source = session.document.websitePages[0], instance = source.nodes[1]
        let destination = DocumentPage.minimum(name: "Destination", route: "/destination", role: .standard, provenance: .authored)
        try session.execute(.insertPage(.init(page: destination, index: session.document.pages.count)))
        try session.execute(textCommand(.setActionOverride(instanceID: instance.id, propertyID: bindingID, target: .page(destination.id)),
            document: session.document, pageID: source.id, selected: instance.id).command)
        XCTAssertEqual(PageCommandRegistry().inboundLinkCount(to: destination.id, in: session.document), 1)
        try session.execute(.renamePage(.init(pageID: destination.id, name: "Renamed")))
        XCTAssertEqual(CanonicalComponentAction.overrides(on: session.document.websitePages[0].nodes[1])[bindingID], .page(destination.id))
        try session.execute(.removePage(.init(pageID: destination.id)))
        XCTAssertEqual(CanonicalComponentAction.overrides(on: session.document.websitePages[0].nodes[1])[bindingID], .page(destination.id))
        XCTAssertTrue(CanonicalLinkTarget.page(destination.id).isMissing(in: session.document))
        let dependencies = try ComponentDependencySnapshot.build(document: session.document)
        let dependency = try XCTUnwrap(dependencies.entries.first)
        XCTAssertEqual(dependency.actionProperties.map(\.id), [bindingID])
        XCTAssertEqual(dependency.actionPageIDs, [destination.id])
        XCTAssertTrue(dependency.issues.contains(.missingActionDestination))
        try session.undo()
        XCTAssertFalse(CanonicalLinkTarget.page(destination.id).isMissing(in: session.document))
        try session.execute(textCommand(.setActionOverride(instanceID: instance.id, propertyID: bindingID, target: .page(source.id)),
            document: session.document, pageID: source.id, selected: instance.id).command)
        let copy = try PageCommandRegistry().prepare(.duplicate,
            identity: .init(documentID: session.document.id, revision: session.document.revision, pageID: source.id),
            in: session.document, isAvailable: true)
        try session.execute(copy.command)
        let copiedPage = try XCTUnwrap(session.document.websitePages.first { $0.id == copy.selectedPageID })
        let copiedInstance = try XCTUnwrap(copiedPage.nodes.first { $0.kind == .component })
        XCTAssertEqual(CanonicalComponentAction.overrides(on: copiedInstance)[bindingID], .page(copiedPage.id))
        XCTAssertEqual(CanonicalComponentAction.overrides(on: session.document.websitePages[0].nodes[1])[bindingID], .page(source.id))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    private func componentSlotFallbackFixture() throws -> (CanonicalDocument, NodeID, [NodeID]) {
        var document = try componentTextFixture()
        let index = try XCTUnwrap(document.pages.firstIndex { $0.role == .componentDefinition })
        var slot = document.pages[index].nodes[1]
        slot.kind = .frame; slot.name = "Content Container"
        slot.properties.removeAll { $0.key.rawValue == "content.text" || CanonicalComponentText.metadataKeys.contains($0.key.rawValue) }
        if let height = slot.properties.firstIndex(where: { $0.key.rawValue == "layout.height" }) { slot.properties[height].value = .number(96) }
        if let width = slot.properties.firstIndex(where: { $0.key.rawValue == "layout.width" }) { slot.properties[width].value = .number(160) }
        let children = [NodeID(), NodeID()]
        slot.childIDs = children
        document.pages[index].nodes[1] = slot
        let origin = try XCTUnwrap(slot.insertionGeometry).origin
        for (offset, id) in children.enumerated() {
            document.pages[index].nodes.append(DocumentNode(id: id, kind: .text, name: "Fallback \(offset + 1)", parent: .node(slot.id), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(origin.x), origin: .defaulted),
                .init(key: .init(rawValue: "layout.y"), value: .number(origin.y + Double(offset * 28)), origin: .defaulted),
                .init(key: .init(rawValue: "layout.width"), value: .number(120), origin: .defaulted),
                .init(key: .init(rawValue: "layout.height"), value: .number(24), origin: .defaulted),
                .init(key: .init(rawValue: "content.text"), value: .string("Fallback \(offset + 1)"), origin: .authored)]))
        }
        try document.validate()
        return (document, slot.id, children)
    }

    private func organizedComponentFixture() throws -> CanonicalDocument {
        let fixture = try componentSlotFallbackFixture()
        var document = fixture.0
        let slotID = fixture.1, children = fixture.2
        let definitionIndex = try XCTUnwrap(document.pages.firstIndex { $0.role == .componentDefinition })
        let rootID = document.pages[definitionIndex].rootNodeIDs[0]
        let imageDocument = try componentImageChoiceFixture()
        document.imageAssets = imageDocument.imageAssets
        let sourceImage = imageDocument.componentDefinitions[0].nodes[1]
        let image = DocumentNode(id: NodeID(), kind: .image, name: sourceImage.name, parent: .node(rootID),
            properties: sourceImage.properties.map { .init(id: PropertyID(), key: $0.key, value: $0.value, origin: $0.origin) })
        let sourceAction = try XCTUnwrap(document.pages[definitionIndex].nodes.first { $0.id == children[1] })
        var action = DocumentNode(id: NodeID(), kind: .button, name: "Action", parent: .node(rootID),
            properties: sourceAction.properties.filter { $0.key.rawValue != "content.text" }
                .map { .init(id: PropertyID(), key: $0.key, value: $0.value, origin: $0.origin) })
        action.properties.append(.init(key: .init(rawValue: CanonicalLinkTarget.labelKey), value: .string("Continue"), origin: .authored))
        document.pages[definitionIndex].nodes.append(contentsOf: [image, action])
        document.pages[definitionIndex].nodes[0].childIDs.append(contentsOf: [image.id, action.id])
        let session = DocumentSession(document: document)
        let edits: [(NodeID, ComponentEdit)] = [
            (slotID, .exposeSlot(nodeID: slotID, label: "Content")),
            (children[0], .exposeText(nodeID: children[0], label: "Title", defaultValue: "Original")),
            (slotID, .exposeVisibility(nodeID: slotID, label: "Show content", defaultValue: true)),
            (image.id, .exposeChoice(nodeID: image.id, label: "Image Fit")),
            (image.id, .exposeMedia(nodeID: image.id, label: "Image Source")),
            (action.id, .exposeAction(nodeID: action.id, label: "Destination"))]
        for (id, edit) in edits {
            try session.execute(textCommand(edit, document: session.document,
                pageID: document.pages[definitionIndex].id, selected: id).command)
        }
        return session.document
    }

    func testComponentPropertyOrganizationAllTypesOrderGroupsAndContentNeutrality() throws {
        let document = try organizedComponentFixture(), definition = document.componentDefinitions[0]
        let entries = CanonicalComponentOrganization.entries(in: definition)
        XCTAssertEqual(Set(entries.map { $0.id.organizationKind }), Set(CanonicalComponentOrganization.kinds))
        XCTAssertEqual(entries.map(\.id.stableDescription), entries.map(\.id.stableDescription).sorted())
        let session = DocumentSession(document: document)
        for entry in entries.reversed() {
            try session.execute(textCommand(.organizeProperty(nodeID: entry.sourceNodeID, property: entry.id,
                group: "Content", position: 0), document: session.document, pageID: definition.id,
                selected: entry.sourceNodeID).command)
        }
        let ordered = CanonicalComponentOrganization.entries(in: session.document.componentDefinitions[0])
        XCTAssertEqual(ordered.map(\.id), entries.map(\.id)); XCTAssertTrue(ordered.allSatisfy { $0.group == "Content" })
        XCTAssertEqual(ordered.compactMap(\.rank), Array(entries.indices))
        for breakpoint in ResponsiveBreakpoint.allCases {
            let old = try ComponentGraphResolver.resolvedPage(document.websitePages[0], in: document, breakpoint: breakpoint)
            let new = try ComponentGraphResolver.resolvedPage(session.document.websitePages[0], in: session.document, breakpoint: breakpoint)
            XCTAssertEqual(new.nodes, old.nodes, "Organization must not change renderer, geometry, defaults, or editor chrome")
        }
        XCTAssertEqual(session.document.websitePages, document.websitePages)
        let original = try CanonicalComponentOverrides.resolve(instance: document.websitePages[0].nodes[1], document: document)
        let resolved = try CanonicalComponentOverrides.resolve(instance: session.document.websitePages[0].nodes[1], document: session.document)
        XCTAssertEqual(resolved, original)
    }

    func testComponentPropertyDiscoveryAllTypesGroupedOrderAndValuePrivacy() throws {
        let document = try organizedComponentFixture()
        let entries = CanonicalComponentOrganization.entries(in: document.componentDefinitions[0])
        let empty = ComponentPropertyDiscovery.project(entries, query: "", authored: [], conflicts: [])
        XCTAssertEqual(empty.entries, entries)
        for kind in CanonicalComponentOrganization.kinds {
            let result = ComponentPropertyDiscovery.project(entries, query: kind.uppercased(), authored: [], conflicts: [])
            XCTAssertEqual(result.entries, entries.filter { $0.id.organizationKind == kind || $0.label.lowercased().contains(kind) })
        }
        let grouped = entries.enumerated().map { index, entry in
            CanonicalComponentOrganization.Entry(id: entry.id, sourceNodeID: entry.sourceNodeID,
                label: "Résumé \(index)", group: index.isMultiple(of: 2) ? "Editorial" : "Layout", rank: index)
        }
        let result = ComponentPropertyDiscovery.project(grouped, query: "RESUME editorial", authored: [], conflicts: [])
        XCTAssertEqual(result.entries.map(\.id), grouped.enumerated().filter { $0.offset.isMultiple(of: 2) }.map { $0.element.id })
        XCTAssertEqual(result.total, entries.count)
        XCTAssertTrue(ComponentPropertyDiscovery.project(entries, query: "unrelated-private-content", authored: [], conflicts: []).entries.isEmpty)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
    }

    func testComponentPropertyDiscoveryConflictsRemainDiscoverableAndResetScopeUnfiltered() throws {
        let document = try organizedComponentFixture()
        let entries = CanonicalComponentOrganization.entries(in: document.componentDefinitions[0])
        let first = try XCTUnwrap(entries.first)
        let orphan = ComponentOverridePropertyIdentity.text(ComponentTextPropertyID())
        let conflicts: Set<ComponentOverridePropertyIdentity> = [first.id, orphan]
        let result = ComponentPropertyDiscovery.project(entries, query: "no-match", authored: [first.id], conflicts: conflicts)
        XCTAssertTrue(result.entries.isEmpty); XCTAssertEqual(result.hiddenConflictCount, 2)
        let recovered = ComponentPropertyDiscovery.project(entries, query: "", authored: [first.id], conflicts: conflicts, conflictsOnly: true)
        XCTAssertEqual(recovered.entries.map(\.id), [first.id]); XCTAssertEqual(recovered.hiddenConflictCount, 1)
        XCTAssertEqual(ComponentPropertyDiscovery.project(entries, query: "inherited", authored: [first.id], conflicts: []).entries.map(\.id), entries.dropFirst().map(\.id))
        XCTAssertEqual(ComponentPropertyDiscovery.project(entries, query: "authored", authored: [first.id], conflicts: []).entries.map(\.id), [first.id])
        // Discovery never rewrites the complete registry input or reset scope.
        XCTAssertEqual(CanonicalComponentOrganization.entries(in: document.componentDefinitions[0]), entries)
    }

    func testComponentPropertyDiscoveryTraversalLiveDefinitionAndContextReplacement() throws {
        let document = try organizedComponentFixture()
        let entries = CanonicalComponentOrganization.entries(in: document.componentDefinitions[0])
        let result = ComponentPropertyDiscovery.project(entries, query: "", authored: [], conflicts: [])
        XCTAssertEqual(result.neighbor(of: nil, offset: 1), entries.first?.id)
        XCTAssertEqual(result.neighbor(of: entries.last?.id, offset: 1), entries.last?.id)
        XCTAssertEqual(result.neighbor(of: entries.first?.id, offset: -1), entries.first?.id)
        XCTAssertEqual(result.neighbor(of: entries.first?.id, offset: 1), entries.dropFirst().first?.id)
        let replacement = Array(entries.dropFirst().reversed())
        let live = ComponentPropertyDiscovery.project(replacement, query: "", authored: [], conflicts: [])
        XCTAssertEqual(live.entries, replacement)
        XCTAssertEqual(live.neighbor(of: entries.first?.id, offset: 1), replacement.first?.id)
        XCTAssertNil(ComponentPropertyDiscovery.project([], query: "", authored: [], conflicts: []).neighbor(of: entries.first?.id, offset: 1))
        let session = DocumentSession(document: document)
        let entry = try XCTUnwrap(entries.first)
        try session.execute(textCommand(.organizeProperty(nodeID: entry.sourceNodeID, property: entry.id,
            group: "Live Group", position: 0), document: session.document,
            pageID: document.componentDefinitions[0].id, selected: entry.sourceNodeID).command)
        let changed = CanonicalComponentOrganization.entries(in: session.document.componentDefinitions[0])
        XCTAssertEqual(ComponentPropertyDiscovery.project(changed, query: "live group", authored: [], conflicts: []).entries.map(\.id), [entry.id])
        XCTAssertEqual(Set(changed.map(\.id)), Set(entries.map(\.id)))
    }

    func testComponentPropertyOrganizationAtomicHistoryResetRemovalAndSchemaRoundTrip() throws {
        let document = try organizedComponentFixture(), definition = document.componentDefinitions[0]
        let entry = try XCTUnwrap(CanonicalComponentOrganization.entries(in: definition).first { $0.id.organizationKind == "text" })
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.organizeProperty(nodeID: entry.sourceNodeID, property: entry.id,
            group: "Editorial", position: 0), document: document, pageID: definition.id, selected: entry.sourceNodeID).command)
        let organizedPages = session.document.pages
        let unchanged = try textCommand(.organizeProperty(nodeID: entry.sourceNodeID, property: entry.id,
            group: "Editorial", position: 0), document: session.document, pageID: definition.id, selected: entry.sourceNodeID)
        if case .batch(let commands) = unchanged.command { XCTAssertTrue(commands.isEmpty) } else { XCTFail("Expected atomic batch") }
        try session.undo(); XCTAssertEqual(session.document.pages, document.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, organizedPages)
        let bytes = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(bytes), session.document)
        XCTAssertThrowsError(try DocumentSerializer.decode(Data(String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":14").utf8)))
        try session.execute(textCommand(.resetPropertyOrganization(nodeID: entry.sourceNodeID, property: entry.id),
            document: session.document, pageID: definition.id, selected: entry.sourceNodeID).command)
        let reset = try XCTUnwrap(CanonicalComponentOrganization.entries(in: session.document.componentDefinitions[0]).first { $0.id == entry.id })
        XCTAssertNil(reset.group); XCTAssertNil(reset.rank)
        try session.undo(); XCTAssertEqual(session.document.pages, organizedPages)
        try session.execute(textCommand(.removeTextProperty(entry.sourceNodeID), document: session.document,
            pageID: definition.id, selected: entry.sourceNodeID).command)
        let source = try XCTUnwrap(session.document.componentDefinitions[0].nodes.first { $0.id == entry.sourceNodeID })
        XCTAssertFalse(source.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentOrganization.namespace + "text.") })
        try session.undo(); XCTAssertEqual(session.document.pages, organizedPages)
        let legacy = try componentTextFixture()
        XCTAssertTrue(CanonicalComponentOrganization.entries(in: legacy.componentDefinitions[0]).isEmpty)
        var previousSchema = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(document)) as? [String: Any])
        previousSchema["schemaVersion"] = 14
        var previousDocument = try XCTUnwrap(previousSchema["document"] as? [String: Any])
        previousDocument.removeValue(forKey: "websiteMetadata") // Not part of schema 14.
        previousSchema["document"] = previousDocument
        XCTAssertEqual(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: previousSchema)), document)
    }

    func testComponentPropertyOrganizationRenameRemovalConflictAndDetachPreserveIntent() throws {
        let document = try organizedComponentFixture(), definition = document.componentDefinitions[0]
        let entry = try XCTUnwrap(CanonicalComponentOrganization.entries(in: definition).first { $0.id.organizationKind == "text" })
        guard case .text(let id) = entry.id else { return XCTFail("Expected text binding") }
        let session = DocumentSession(document: document)
        let instance = document.websitePages[0].nodes[1], pageID = document.websitePages[0].id
        try session.execute(textCommand(.setTextOverride(instanceID: instance.id, propertyID: id, value: "Instance title"),
            document: session.document, pageID: pageID, selected: instance.id).command)
        let instanceProperties = session.document.websitePages[0].nodes[1].properties
        try session.execute(textCommand(.organizeProperty(nodeID: entry.sourceNodeID, property: entry.id, group: "Content", position: 0),
            document: session.document, pageID: definition.id, selected: entry.sourceNodeID).command)
        try session.execute(textCommand(.exposeText(nodeID: entry.sourceNodeID, label: "Renamed title", defaultValue: "Updated default"),
            document: session.document, pageID: definition.id, selected: entry.sourceNodeID).command)
        let renamed = try XCTUnwrap(CanonicalComponentOrganization.entries(in: session.document.componentDefinitions[0]).first { $0.id == entry.id })
        XCTAssertEqual(renamed.group, "Content"); XCTAssertEqual(renamed.label, "Renamed title")
        XCTAssertEqual(session.document.websitePages[0].nodes[1].properties, instanceProperties)
        try session.execute(textCommand(.removeTextProperty(entry.sourceNodeID), document: session.document, pageID: definition.id,
            selected: entry.sourceNodeID).command)
        let values = try CanonicalComponentOverrides.resolve(instance: session.document.websitePages[0].nodes[1], document: session.document)
        let conflict = try XCTUnwrap(values.first { $0.property == entry.id })
        if case .conflict(.missingProperty, _) = conflict.resolution {} else { XCTFail("Removal must retain authored intent as a conflict") }
        XCTAssertEqual(conflict.effectiveValue, .text("Instance title"))
        try session.undo(); try session.execute(textCommand(.detach(instance.id), document: session.document,
            pageID: pageID, selected: instance.id).command)
        XCTAssertFalse(session.document.websitePages.flatMap(\.nodes).flatMap(\.properties).contains {
            $0.key.rawValue.hasPrefix(CanonicalComponentOrganization.namespace)
        })
        XCTAssertTrue(session.document.websitePages.flatMap(\.nodes).contains { $0.insertionStringProperty("content.text") == "Instance title" })
    }

    func testComponentPropertyOrganizationRejectsInvalidDuplicateMissingStaleAndCancelledState() throws {
        let document = try organizedComponentFixture(), definition = document.componentDefinitions[0]
        let entries = CanonicalComponentOrganization.entries(in: definition), entry = try XCTUnwrap(entries.first)
        for (group, position) in [(" ", 0), ("Bad\nGroup", 0), (String(repeating: "g", count: 65), 0), ("Valid", -1), ("Valid", 64)] {
            XCTAssertThrowsError(try textCommand(.organizeProperty(nodeID: entry.sourceNodeID, property: entry.id,
                group: group, position: position), document: document, pageID: definition.id, selected: entry.sourceNodeID))
        }
        XCTAssertThrowsError(try textCommand(.organizeProperty(nodeID: entry.sourceNodeID, property: .text(ComponentTextPropertyID()),
            group: nil, position: 0), document: document, pageID: definition.id, selected: entry.sourceNodeID))
        let scene = CanvasViewportSceneID()
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: definition.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        let context = TransformValidationContext(activePageID: definition.id, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [entry.sourceNodeID], availableNodeIDs: [entry.sourceNodeID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let edit = ComponentEdit.organizeProperty(nodeID: entry.sourceNodeID, property: entry.id, group: "Content", position: 0)
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: identity, in: document, context: context, cancelled: true))
        var newer = document; newer.revision += 1
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: identity, in: newer, context: context))
        for stale in [
            DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: definition.id, revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            DesignInspectorOperationIdentity(documentID: document.id, pageID: PageID(), revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            DesignInspectorOperationIdentity(documentID: document.id, pageID: definition.id, revision: document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: document.revision),
            DesignInspectorOperationIdentity(documentID: document.id, pageID: definition.id, revision: document.revision, sceneID: scene, rendererGeneration: document.revision + 1)
        ] {
            XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: stale, in: document, context: context))
        }
        let mixed = TransformValidationContext(activePageID: definition.id, currentSceneID: scene, rendererGeneration: document.revision,
            selectedNodeIDs: [entry.sourceNodeID, definition.rootNodeIDs[0]], availableNodeIDs: [entry.sourceNodeID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: identity, in: document, context: mixed))
        var invalid = document
        let di = try XCTUnwrap(invalid.pages.firstIndex { $0.id == definition.id })
        for item in entries.prefix(2) {
            let ni = try XCTUnwrap(invalid.pages[di].nodes.firstIndex { $0.id == item.sourceNodeID })
            invalid.pages[di].nodes[ni].properties.append(.init(key: .init(rawValue: CanonicalComponentOrganization.key(item.id.organizationKind, "order")),
                value: .number(0), origin: .authored))
            invalid.pages[di].nodes[ni].properties.append(.init(key: .init(rawValue: CanonicalComponentOrganization.key(item.id.organizationKind, "binding")),
                value: .string(item.id.stableDescription), origin: .authored))
        }
        XCTAssertThrowsError(try invalid.validate(), "Duplicate authored ranks are invalid, not dictionary-order dependent")
        for value in [PropertyValue.number(-1), .number(64), .number(0.5), .number(.infinity), .number(.nan), .string("0")] {
            var malformed = document
            let ni = try XCTUnwrap(malformed.pages[di].nodes.firstIndex { $0.id == entry.sourceNodeID })
            malformed.pages[di].nodes[ni].properties.append(.init(key: .init(rawValue: CanonicalComponentOrganization.key(entry.id.organizationKind, "order")),
                value: value, origin: .authored))
            malformed.pages[di].nodes[ni].properties.append(.init(key: .init(rawValue: CanonicalComponentOrganization.key(entry.id.organizationKind, "binding")),
                value: .string(entry.id.stableDescription), origin: .authored))
            XCTAssertThrowsError(try malformed.validate())
        }
        var missing = document
        missing.pages[di].nodes[0].properties.append(.init(key: .init(rawValue: CanonicalComponentOrganization.key("text", "group")),
            value: .string("Orphan"), origin: .authored))
        XCTAssertThrowsError(try missing.validate(), "Organization cannot invent a binding or live on an instance")
        XCTAssertEqual(document.componentDefinitions[0], definition)
    }

    private func retainedComponentConflictSession() throws -> (DocumentSession, NodeID) {
        let document = try organizedComponentFixture(), definition = document.componentDefinitions[0]
        let session = DocumentSession(document: document), instance = document.websitePages[0].nodes[1]
        let entries = CanonicalComponentOrganization.entries(in: definition)
        for entry in entries {
            let edit: ComponentEdit
            switch entry.id {
            case .text(let id): edit = .setTextOverride(instanceID: instance.id, propertyID: id, value: "Retained private title")
            case .visibility(let id): edit = .setVisibilityOverride(instanceID: instance.id, propertyID: id, value: false)
            case .choice(let id): edit = .setChoiceOverride(instanceID: instance.id, propertyID: id, value: .fill)
            case .media(let id): edit = .setMediaOverride(instanceID: instance.id, propertyID: id, assetID: document.imageAssets[0].id)
            case .action(let id): edit = .setActionOverride(instanceID: instance.id, propertyID: id, target: .external("https://example.invalid/retained"))
            case .slot: continue
            }
            try session.execute(textCommand(edit, document: session.document, pageID: document.websitePages[0].id,
                selected: instance.id).command)
        }
        for entry in entries {
            let edit: ComponentEdit
            switch entry.id {
            case .text: edit = .removeTextProperty(entry.sourceNodeID)
            case .visibility: edit = .removeVisibilityProperty(entry.sourceNodeID)
            case .choice: edit = .removeChoiceProperty(entry.sourceNodeID)
            case .media: edit = .removeMediaProperty(entry.sourceNodeID)
            case .action: edit = .removeActionProperty(entry.sourceNodeID)
            case .slot: continue
            }
            try session.execute(textCommand(edit, document: session.document, pageID: definition.id,
                selected: entry.sourceNodeID).command)
        }
        return (session, instance.id)
    }

    func testComponentConflictRecoveryAllTypesResetOneAllExactHistoryAndPersistence() throws {
        let (session, instanceID) = try retainedComponentConflictSession()
        let pageID = session.document.websitePages[0].id
        func conflicts() throws -> [ComponentOverrideConflictFinding] {
            let instance = try XCTUnwrap(session.document.websitePages[0].nodes.first { $0.id == instanceID })
            return try CanonicalComponentOverrides.conflicts(instance: instance, document: session.document)
        }
        let findings = try conflicts(), retained = session.document.pages
        XCTAssertEqual(Set(findings.map { $0.property.organizationKind }), ["text", "visibility", "choice", "media", "action"])
        XCTAssertTrue(findings.allSatisfy { $0.reason == .missingProperty && $0.path == nil })
        let first = try XCTUnwrap(findings.first)
        try session.execute(textCommand(.resetOverrideConflicts(instanceID: instanceID, expectedPropertyIDs: [first.authoredPropertyID], confirmed: true),
            document: session.document, pageID: pageID, selected: instanceID).command)
        XCTAssertEqual(try conflicts().count, 4)
        XCTAssertFalse(session.document.websitePages[0].nodes[1].properties.contains { $0.id == first.authoredPropertyID })
        try session.undo(); XCTAssertEqual(session.document.pages, retained)
        try session.redo(); XCTAssertEqual(try conflicts().count, 4)
        let beforeAll = session.document.pages, remaining = try conflicts()
        try session.execute(textCommand(.resetOverrideConflicts(instanceID: instanceID,
            expectedPropertyIDs: remaining.map(\.authoredPropertyID), confirmed: true), document: session.document,
            pageID: pageID, selected: instanceID).command)
        XCTAssertTrue(try conflicts().isEmpty)
        XCTAssertEqual(session.document.componentDefinitions.map(\.nodes), retained.filter { $0.role == .componentDefinition }.map(\.nodes))
        XCTAssertEqual(session.document.websitePages[0].nodes[1].id, instanceID)
        try session.undo(); XCTAssertEqual(session.document.pages, beforeAll)
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened, session.document)
        XCTAssertEqual(try CanonicalComponentOverrides.conflicts(instance: reopened.websitePages[0].nodes[1], document: reopened), remaining)
    }

    func testComponentConflictRecoveryMissingDefinitionAndOriginalBindingRestoration() throws {
        let session = try exposedTextSession(), definition = session.document.componentDefinitions[0]
        let binding = try XCTUnwrap(CanonicalComponentText.properties(in: definition).first)
        let instance = session.document.websitePages[0].nodes[1], pageID = session.document.websitePages[0].id
        try session.execute(textCommand(.setTextOverride(instanceID: instance.id, propertyID: binding.id, value: "Preserve original intent"),
            document: session.document, pageID: pageID, selected: instance.id).command)
        let originalInstance = session.document.websitePages[0].nodes[1]
        try session.execute(textCommand(.removeTextProperty(binding.sourceNodeID), document: session.document,
            pageID: definition.id, selected: binding.sourceNodeID).command)
        XCTAssertEqual(try CanonicalComponentOverrides.conflicts(instance: session.document.websitePages[0].nodes[1], document: session.document).count, 1)
        try session.undo()
        XCTAssertTrue(try CanonicalComponentOverrides.conflicts(instance: session.document.websitePages[0].nodes[1], document: session.document).isEmpty)
        XCTAssertEqual(session.document.websitePages[0].nodes[1], originalInstance)
        let restored = try XCTUnwrap(CanonicalComponentText.properties(in: session.document.componentDefinitions[0]).first)
        XCTAssertEqual(restored.id, binding.id); XCTAssertEqual(restored.sourceNodeID, binding.sourceNodeID)
        var missing = session.document; missing.pages.removeAll { $0.id == definition.id }
        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(missing))
        let conflict = try XCTUnwrap(CanonicalComponentOverrides.conflicts(instance: reopened.websitePages[0].nodes[1], document: reopened).first)
        XCTAssertEqual(conflict.reason, .missingDefinition); XCTAssertNil(conflict.path)
        XCTAssertEqual(conflict.retainedValue, .text("Preserve original intent"))
        let missingSession = DocumentSession(document: reopened)
        try missingSession.execute(textCommand(.resetOverrideConflicts(instanceID: instance.id,
            expectedPropertyIDs: [conflict.authoredPropertyID], confirmed: true), document: reopened, pageID: pageID, selected: instance.id).command)
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: missingSession.document.websitePages[0].nodes[1]), definition.id)
        XCTAssertTrue(try CanonicalComponentOverrides.requiresRecovery(instance: missingSession.document.websitePages[0].nodes[1], document: missingSession.document),
            "Resetting a value must not fabricate or retarget its missing definition")
        try missingSession.undo(); XCTAssertEqual(missingSession.document.pages, reopened.pages)
    }

    func testComponentConflictRecoveryRejectsUnconfirmedCancelledStaleHealthyAndDuplicateTargets() throws {
        let (session, instanceID) = try retainedComponentConflictSession()
        let document = session.document, pageID = document.websitePages[0].id
        let conflicts = try CanonicalComponentOverrides.conflicts(instance: document.websitePages[0].nodes[1], document: document)
        let first = try XCTUnwrap(conflicts.first)
        for ids in [[], [PropertyID()], [first.authoredPropertyID, first.authoredPropertyID]] {
            XCTAssertThrowsError(try textCommand(.resetOverrideConflicts(instanceID: instanceID, expectedPropertyIDs: ids, confirmed: true),
                document: document, pageID: pageID, selected: instanceID))
        }
        XCTAssertThrowsError(try textCommand(.resetOverrideConflicts(instanceID: instanceID, expectedPropertyIDs: [first.authoredPropertyID], confirmed: false),
            document: document, pageID: pageID, selected: instanceID))
        let scene = CanvasViewportSceneID()
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: pageID, revision: document.revision,
            sceneID: scene, rendererGeneration: document.revision)
        let context = TransformValidationContext(activePageID: pageID, currentSceneID: scene, rendererGeneration: document.revision,
            selectedNodeIDs: [instanceID], availableNodeIDs: [instanceID], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let edit = ComponentEdit.resetOverrideConflicts(instanceID: instanceID, expectedPropertyIDs: [first.authoredPropertyID], confirmed: true)
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: identity, in: document, context: context, cancelled: true))
        var newer = document; newer.revision += 1
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: identity, in: newer, context: context))
        for stale in [
            DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: pageID, revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            DesignInspectorOperationIdentity(documentID: document.id, pageID: PageID(), revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            DesignInspectorOperationIdentity(documentID: document.id, pageID: pageID, revision: document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: document.revision),
            DesignInspectorOperationIdentity(documentID: document.id, pageID: pageID, revision: document.revision, sceneID: scene, rendererGeneration: document.revision + 1)
        ] {
            XCTAssertThrowsError(try ComponentCommandRegistry().prepare(edit, identity: stale, in: document, context: context))
        }
        let healthy = try exposedTextSession(), definition = healthy.document.componentDefinitions[0]
        let binding = try XCTUnwrap(CanonicalComponentText.properties(in: definition).first), instance = healthy.document.websitePages[0].nodes[1]
        try healthy.execute(textCommand(.setTextOverride(instanceID: instance.id, propertyID: binding.id, value: "Healthy"),
            document: healthy.document, pageID: healthy.document.websitePages[0].id, selected: instance.id).command)
        let propertyID = try XCTUnwrap(healthy.document.websitePages[0].nodes[1].properties.first { $0.key.rawValue == CanonicalComponentText.overrideKey(binding.id) }?.id)
        XCTAssertThrowsError(try textCommand(.resetOverrideConflicts(instanceID: instance.id, expectedPropertyIDs: [propertyID], confirmed: true),
            document: healthy.document, pageID: healthy.document.websitePages[0].id, selected: instance.id))
        XCTAssertEqual(session.document, document)
    }

    func testComponentConflictRecoveryPreviewAndStaticOutputFailClosedWithoutDisclosingValues() async throws {
        let (session, _) = try retainedComponentConflictSession()
        let document = session.document
        let result = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
            resourceDescriptors: [:], resourceData: [:])
        XCTAssertNil(result.plan)
        XCTAssertTrue(result.findings.contains { $0.code == "component-override-conflict" && $0.requirementID == "SF-0905-004" })
        XCTAssertFalse(result.redactedSummary.contains("Retained private title"))
        XCTAssertFalse(result.redactedSummary.contains("https://example.invalid/retained"))
        do {
            _ = try await LocalPreviewRuntimeCompiler().compile(document: document, imageResourceData: [:], pixelRatio: CanvasPixelRatio(1))
            XCTFail("Preview must not publish a snapshot of unresolved authored intent")
        } catch { XCTAssertEqual(error as? LocalPreviewRuntimeError, .componentRecoveryRequired) }
        XCTAssertEqual(session.document, document)
    }

    func testComponentConflictMissingActionDestinationSharesDependencyFindingAndPreservesHealthyOverrides() throws {
        let initial = try organizedComponentFixture(), definition = initial.componentDefinitions[0]
        let action = try XCTUnwrap(CanonicalComponentAction.properties(in: definition).first)
        let text = try XCTUnwrap(CanonicalComponentText.properties(in: definition).first)
        let instance = initial.websitePages[0].nodes[1], pageID = initial.websitePages[0].id
        let removedPageID = try XCTUnwrap(initial.websitePages.last?.id)
        XCTAssertNotEqual(pageID, removedPageID)
        let session = DocumentSession(document: initial)
        try session.execute(textCommand(.setActionOverride(instanceID: instance.id, propertyID: action.id, target: .page(removedPageID)),
            document: session.document, pageID: pageID, selected: instance.id).command)
        try session.execute(textCommand(.setTextOverride(instanceID: instance.id, propertyID: text.id, value: "Healthy remains"),
            document: session.document, pageID: pageID, selected: instance.id).command)
        var unavailable = session.document; unavailable.pages.removeAll { $0.id == removedPageID }
        let loaded = try DocumentSerializer.decode(DocumentSerializer.encode(unavailable))
        let findings = try CanonicalComponentOverrides.conflicts(instance: loaded.websitePages[0].nodes[1], document: loaded)
        let conflict = try XCTUnwrap(findings.first)
        XCTAssertEqual(findings.count, 1); XCTAssertEqual(conflict.property, .action(action.id))
        XCTAssertEqual(conflict.reason, .missingActionDestination)
        XCTAssertEqual(conflict.path?.sourceNodeID, action.sourceNodeID)
        let details = try XCTUnwrap(ComponentDependencySnapshot.build(document: loaded).entry(for: definition.id))
        XCTAssertEqual(details.overrideConflicts, findings); XCTAssertEqual(details.overrideConflictCount, 1)
        let recovery = DocumentSession(document: loaded)
        try recovery.execute(textCommand(.resetOverrideConflicts(instanceID: instance.id,
            expectedPropertyIDs: [conflict.authoredPropertyID], confirmed: true), document: loaded,
            pageID: pageID, selected: instance.id).command)
        XCTAssertEqual(CanonicalComponentText.overrides(on: recovery.document.websitePages[0].nodes[1])[text.id], "Healthy remains")
        XCTAssertTrue(CanonicalComponentAction.overrides(on: recovery.document.websitePages[0].nodes[1]).isEmpty)
        try recovery.undo(); XCTAssertEqual(recovery.document.pages, loaded.pages)
    }

    func testComponentSlotFallbackBindingOrderingHistoryAndSchemaRoundTrip() throws {
        let (document, slotID, children) = try componentSlotFallbackFixture()
        let definitionID = document.componentDefinitions[0].id
        let session = DocumentSession(document: document)
        let prepared = try textCommand(.exposeSlot(nodeID: slotID, label: "Content"), document: document,
            pageID: definitionID, selected: slotID)
        XCTAssertEqual(prepared.selectedNodeID, slotID)
        try session.execute(prepared.command)
        let binding = try XCTUnwrap(CanonicalComponentSlot.properties(in: session.document.componentDefinitions[0]).first)
        XCTAssertEqual(binding.defaultChildIDs, children)
        let instance = session.document.websitePages[0].nodes[1]
        XCTAssertTrue(instance.childIDs.isEmpty, "Fallback slots must preserve the approved childless-instance contract")
        let values = try CanonicalComponentOverrides.resolve(instance: instance, document: session.document)
        XCTAssertTrue(values.contains { $0.property == .slot(binding.id) && $0.effectiveValue == .slotFallback(children) && $0.resolution == .inherited })
        let metadata = try XCTUnwrap(session.document.componentDefinitions[0].nodes.first { $0.id == slotID }).properties
        try session.execute(textCommand(.exposeSlot(nodeID: slotID, label: "Renamed Content"), document: session.document,
            pageID: definitionID, selected: slotID).command)
        XCTAssertEqual(CanonicalComponentSlot.properties(in: session.document.componentDefinitions[0]).first?.id, binding.id)
        try session.undo()
        XCTAssertEqual(session.document.componentDefinitions[0].nodes.first { $0.id == slotID }?.properties, metadata)
        try session.execute(textCommand(.removeSlotProperty(slotID), document: session.document,
            pageID: definitionID, selected: slotID).command)
        XCTAssertEqual(session.document.componentDefinitions[0].nodes.first { $0.id == slotID }?.childIDs, children)
        XCTAssertTrue(CanonicalComponentSlot.properties(in: session.document.componentDefinitions[0]).isEmpty)
        try session.undo()
        XCTAssertEqual(session.document.componentDefinitions[0].nodes.first { $0.id == slotID }?.properties, metadata)
        let encoded = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), session.document)
        let forged = Data(String(decoding: encoded, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":13").utf8)
        XCTAssertThrowsError(try DocumentSerializer.decode(forged))
        XCTAssertTrue(CanonicalComponentSlot.properties(in: try componentTextFixture().componentDefinitions[0]).isEmpty)
        var empty = session.document
        let definitionIndex = try XCTUnwrap(empty.pages.firstIndex { $0.id == definitionID })
        empty.pages[definitionIndex].nodes.removeAll { children.contains($0.id) }
        let slotIndex = try XCTUnwrap(empty.pages[definitionIndex].nodes.firstIndex { $0.id == slotID })
        empty.pages[definitionIndex].nodes[slotIndex].childIDs = []
        try empty.validate()
        XCTAssertEqual(CanonicalComponentSlot.properties(in: empty.componentDefinitions[0]).first?.defaultChildIDs, [])
        let emptyProjection = try ComponentGraphResolver.resolvedPage(empty.websitePages[0], in: empty, breakpoint: .desktop)
        XCTAssertEqual(emptyProjection.nodes.count, 5, "Page root plus two instance roots and two empty authored slot containers remain")
    }

    func testComponentSlotFallbackRejectsCancelledStaleNestedCyclicAndSuppliedOwnership() throws {
        let (document, slotID, children) = try componentSlotFallbackFixture()
        let definition = document.componentDefinitions[0], scene = CanvasViewportSceneID()
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: definition.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        let context = TransformValidationContext(activePageID: definition.id, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [slotID], availableNodeIDs: [slotID],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let registry = ComponentCommandRegistry(), edit = ComponentEdit.exposeSlot(nodeID: slotID, label: "Content")
        XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: document, context: context, cancelled: true))
        let stale = DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: definition.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        XCTAssertThrowsError(try registry.prepare(edit, identity: stale, in: document, context: context))
        let staleIdentities: [DesignInspectorOperationIdentity] = [
            .init(documentID: document.id, pageID: PageID(), revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: definition.id, revision: document.revision + 1, sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: definition.id, revision: document.revision, sceneID: CanvasViewportSceneID(), rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: definition.id, revision: document.revision, sceneID: scene, rendererGeneration: document.revision + 1)]
        for captured in staleIdentities { XCTAssertThrowsError(try registry.prepare(edit, identity: captured, in: document, context: context)) }
        XCTAssertThrowsError(try textCommand(.exposeSlot(nodeID: definition.rootNodeIDs[0], label: "Root"),
            document: document, pageID: definition.id, selected: definition.rootNodeIDs[0]))
        let session = DocumentSession(document: document)
        try session.execute(try registry.prepare(edit, identity: identity, in: document, context: context).command)
        let before = session.document
        let page = before.websitePages[0], instance = page.nodes[1]
        XCTAssertThrowsError(try session.execute(.setProperty(.init(pageID: page.id, nodeID: instance.id,
            property: .init(key: .init(rawValue: CanonicalComponentSlot.unsupportedOverrideNamespace + ComponentSlotPropertyID().description),
                value: .string("unsupported supplied content"), origin: .authored)))))
        XCTAssertEqual(session.document, before)
        var nested = before
        let index = try XCTUnwrap(nested.pages.firstIndex { $0.id == definition.id })
        let nestedIndex = try XCTUnwrap(nested.pages[index].nodes.firstIndex { $0.id == children[0] })
        nested.pages[index].nodes[nestedIndex].kind = .frame
        nested.pages[index].nodes[nestedIndex].properties.removeAll { $0.key.rawValue == "content.text" }
        nested.pages[index].nodes[nestedIndex].properties += [
            .init(key: .init(rawValue: CanonicalComponentSlot.namespace + "id"), value: .string(ComponentSlotPropertyID().description), origin: .authored),
            .init(key: .init(rawValue: CanonicalComponentSlot.namespace + "label"), value: .string("Outer"), origin: .authored),
            .init(key: .init(rawValue: CanonicalComponentSlot.namespace + "type"), value: .string("ordered-fallback-children"), origin: .authored)]
        XCTAssertThrowsError(try nested.validate())
        var cyclic = before
        let slotIndex = try XCTUnwrap(cyclic.pages[index].nodes.firstIndex { $0.id == slotID })
        cyclic.pages[index].nodes[slotIndex].childIDs.append(definition.rootNodeIDs[0])
        XCTAssertThrowsError(try cyclic.validate())
        var retargeted = before.pages[index]
        let oldSlot = retargeted.nodes[slotIndex]
        retargeted.nodes[slotIndex].properties.removeAll { CanonicalComponentSlot.metadataKeys.contains($0.key.rawValue) }
        let replacementID = NodeID()
        let replacement = DocumentNode(id: replacementID, kind: .frame, name: "Retargeted slot", parent: .node(definition.rootNodeIDs[0]),
            properties: oldSlot.properties.map { .init(id: PropertyID(), key: $0.key, value: $0.value, origin: $0.origin) })
        retargeted.nodes.append(replacement)
        retargeted.nodes[0].childIDs.append(replacementID)
        XCTAssertThrowsError(try session.execute(.batch([.removePage(.init(pageID: definition.id)),
            .insertPage(.init(page: retargeted, index: index))])))
        XCTAssertEqual(session.document, before, "A retained slot identity cannot silently point to another source container")
    }

    func testComponentSlotFallbackDefinitionUpdatesDetachAndOutputKeepChildIdentity() async throws {
        let (document, slotID, children) = try componentSlotFallbackFixture()
        let session = DocumentSession(document: document), definitionID = document.componentDefinitions[0].id
        try session.execute(textCommand(.exposeSlot(nodeID: slotID, label: "Content"), document: document,
            pageID: definitionID, selected: slotID).command)
        let page = session.document.websitePages[0], instance = page.nodes[1]
        let childIDs = children.map { NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue, label: "component-child:" + $0.description)) }
        let expanded = try ComponentGraphResolver.resolvedPage(page, in: session.document, breakpoint: .desktop)
        let projectedSlotID = NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue, label: "component-child:" + slotID.description))
        XCTAssertEqual(expanded.nodes.first { $0.id == projectedSlotID }?.childIDs, childIDs)
        XCTAssertTrue(expanded.nodes.allSatisfy { !$0.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentSlot.namespace) } })
        let viewport = try CanvasViewportState(viewportSize: .init(width: 1_000, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)), pixelRatio: .init(2))
        let prepared = try await WorkspaceScenePreparationWorker().prepare(.init(document: session.document,
            activePageID: page.id, activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID()))
        XCTAssertTrue(childIDs.allSatisfy { id in prepared.renderScene.objects.contains { $0.id == id } })
        let plan = try CanvasRendererCore().prepare(scene: prepared.renderScene, overlays: prepared.overlays, viewport: viewport, previous: nil)
        XCTAssertTrue(childIDs.allSatisfy { id in plan.accessibilityElements.contains { $0.objectID == id } })
        let staticPlan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        XCTAssertTrue(staticPlan.files.contains { $0.contents.contains("Fallback 1") && $0.contents.contains("Fallback 2") })
        let property = try XCTUnwrap(session.document.componentDefinitions[0].nodes.first { $0.id == children[0] }?.insertionProperty("content.text"))
        var changed = property; changed.value = .string("Updated fallback")
        try session.execute(.setProperty(.init(pageID: definitionID, nodeID: children[0], property: changed)))
        let updated = try ComponentGraphResolver.resolvedPage(session.document.websitePages[0], in: session.document, breakpoint: .desktop)
        XCTAssertEqual(updated.nodes.first { $0.id == childIDs[0] }?.insertionStringProperty("content.text"), "Updated fallback")
        try session.undo()
        XCTAssertEqual(session.document.componentDefinitions[0].nodes.first { $0.id == children[0] }?.insertionProperty("content.text"), property)
        let detached = try XCTUnwrap(ComponentGraphResolver.detachedNodes(instance, definition: session.document.componentDefinitions[0], page: page))
        XCTAssertTrue(childIDs.allSatisfy { id in detached.contains { $0.id == id } })
        XCTAssertFalse(detached.flatMap(\.properties).contains { $0.key.rawValue.hasPrefix(CanonicalComponentSlot.namespace) })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testComponentVisibilityDefaultOverrideResetHistoryAndPersistence() throws {
        let session = try exposedVisibilitySession()
        let definition = session.document.componentDefinitions[0]
        let child = definition.nodes[1]
        let binding = try XCTUnwrap(CanonicalComponentVisibility.property(on: child))
        let page = session.document.websitePages[0]
        let first = page.nodes[1], second = page.nodes[2]
        func derived(_ instance: DocumentNode) throws -> DocumentNode {
            let resolved = try ComponentGraphResolver.resolvedPage(session.document.websitePages[0],
                in: session.document, breakpoint: .desktop)
            let id = NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue,
                label: "component-child:" + child.id.description))
            return try XCTUnwrap(resolved.nodes.first { $0.id == id })
        }
        XCTAssertTrue(try derived(first).selectionBooleanProperty("hidden"))
        XCTAssertTrue(try derived(second).selectionBooleanProperty("hidden"))
        let before = session.document.pages
        try session.execute(textCommand(.setVisibilityOverride(instanceID: first.id,
            propertyID: binding.id, value: true), document: session.document,
            pageID: page.id, selected: first.id).command)
        let override = try XCTUnwrap(session.document.websitePages[0].nodes[1]
            .insertionProperty(CanonicalComponentVisibility.overrideKey(binding.id)))
        XCTAssertEqual(override.value, .boolean(true))
        XCTAssertEqual(override.origin, .authored)
        XCTAssertFalse(try derived(first).selectionBooleanProperty("hidden"))
        XCTAssertTrue(try derived(second).selectionBooleanProperty("hidden"))
        let authored = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, before)
        try session.redo(); XCTAssertEqual(session.document.pages, authored)
        try session.execute(textCommand(.resetVisibilityOverride(instanceID: first.id,
            propertyID: binding.id), document: session.document,
            pageID: page.id, selected: first.id).command)
        XCTAssertNil(session.document.websitePages[0].nodes[1]
            .insertionProperty(CanonicalComponentVisibility.overrideKey(binding.id)))
        try session.undo()
        XCTAssertEqual(session.document.websitePages[0].nodes[1]
            .insertionProperty(CanonicalComponentVisibility.overrideKey(binding.id)), override)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.redo()
        XCTAssertTrue(try derived(first).selectionBooleanProperty("hidden"))
    }

    func testComponentVisibilityStrictValidationStaleCancellationAndConflictRecovery() throws {
        let session = try exposedVisibilitySession()
        let document = session.document, definition = document.componentDefinitions[0]
        let child = definition.nodes[1]
        let binding = try XCTUnwrap(CanonicalComponentVisibility.property(on: child))
        let page = document.websitePages[0], first = page.nodes[1]
        let scene = CanvasViewportSceneID()
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: page.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [first.id],
            availableNodeIDs: [first.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let edit = ComponentEdit.setVisibilityOverride(instanceID: first.id, propertyID: binding.id, value: true)
        let registry = ComponentCommandRegistry()
        XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: document, context: context, cancelled: true))
        for stale in [
            DesignInspectorOperationIdentity(documentID: DocumentID(), pageID: page.id, revision: document.revision,
                sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: PageID(), revision: document.revision,
                sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: page.id, revision: 0,
                sceneID: scene, rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: page.id, revision: document.revision,
                sceneID: CanvasViewportSceneID(), rendererGeneration: document.revision),
            .init(documentID: document.id, pageID: page.id, revision: document.revision,
                sceneID: scene, rendererGeneration: 0)
        ] { XCTAssertThrowsError(try registry.prepare(edit, identity: stale, in: document, context: context)) }
        XCTAssertThrowsError(try textCommand(.setVisibilityOverride(instanceID: first.id,
            propertyID: ComponentVisibilityPropertyID(), value: true), document: document,
            pageID: page.id, selected: first.id))
        XCTAssertThrowsError(try textCommand(.exposeVisibility(nodeID: child.id, label: " ", defaultValue: true),
            document: document, pageID: definition.id, selected: child.id))
        XCTAssertThrowsError(try textCommand(.exposeVisibility(nodeID: definition.rootNodeIDs[0],
            label: "Root", defaultValue: true), document: document, pageID: definition.id,
            selected: definition.rootNodeIDs[0]))
        var malformed = document
        let index = malformed.pages[2].nodes[1].properties.firstIndex {
            $0.key.rawValue == CanonicalComponentVisibility.namespace + "default"
        }!
        malformed.pages[2].nodes[1].properties[index].value = .string("true")
        XCTAssertThrowsError(try DocumentSerializer.encode(malformed))
        try session.execute(textCommand(edit, document: session.document, pageID: page.id,
            selected: first.id).command)
        try session.execute(textCommand(.removeVisibilityProperty(child.id),
            document: session.document, pageID: definition.id, selected: child.id).command)
        XCTAssertNil(CanonicalComponentVisibility.property(on: session.document.componentDefinitions[0].nodes[1]))
        let conflicted = try XCTUnwrap(CanonicalComponentOverrides.resolve(
            instance: session.document.websitePages[0].nodes[1], document: session.document).first)
        XCTAssertEqual(conflicted.effectiveValue, .visibility(true))
        guard case .conflict(.missingProperty, _) = conflicted.resolution else {
            return XCTFail("Expected a retained visibility override conflict")
        }
        try session.execute(textCommand(.resetAllVisibilityOverrides(first.id),
            document: session.document, pageID: page.id, selected: first.id).command)
        XCTAssertTrue(CanonicalComponentVisibility.overrides(on: session.document.websitePages[0].nodes[1]).isEmpty)
    }

    func testComponentVisibilityRendererAccessibilityAndStaticOutputShareEffectiveState() async throws {
        let session = try exposedVisibilitySession()
        let definition = session.document.componentDefinitions[0], child = definition.nodes[1]
        let binding = try XCTUnwrap(CanonicalComponentVisibility.property(on: child))
        let page = session.document.websitePages[0], instance = page.nodes[1]
        let childID = NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue,
            label: "component-child:" + child.id.description))
        let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 1_000, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)),
            pixelRatio: .init(2))
        let worker = WorkspaceScenePreparationWorker(), surface = CanvasRenderSurfaceID()
        let hidden = try await worker.prepare(.init(document: session.document, activePageID: page.id,
            activeContainerID: nil, viewport: viewport, surfaceID: surface))
        XCTAssertFalse(hidden.renderScene.objects.contains { $0.id == childID })
        let hiddenPlan = try CanvasRendererCore().prepare(scene: hidden.renderScene, overlays: hidden.overlays,
            viewport: viewport, previous: nil)
        XCTAssertFalse(hiddenPlan.accessibilityElements.contains { $0.objectID == childID })
        let hiddenStatic = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let selector = CanonicalCSSRule.selector(for: childID)
        let hiddenCSS = try XCTUnwrap(hiddenStatic.files.first { $0.path == "styles.css" }).contents
        XCTAssertTrue(hiddenCSS.contains("\(selector) {"))
        XCTAssertTrue(hiddenCSS.contains("\(selector) { box-sizing: border-box;"))
        XCTAssertTrue(hiddenCSS.components(separatedBy: "\(selector) {").dropFirst().first?
            .components(separatedBy: "}").first?.contains("display: none;") == true)
        try session.execute(textCommand(.setVisibilityOverride(instanceID: instance.id,
            propertyID: binding.id, value: true), document: session.document,
            pageID: page.id, selected: instance.id).command)
        let shown = try await worker.prepare(.init(document: session.document, activePageID: page.id,
            activeContainerID: nil, viewport: viewport, surfaceID: surface))
        XCTAssertTrue(shown.renderScene.objects.contains { $0.id == childID })
        XCTAssertEqual(shown.renderScene.identity.sceneGeneration, session.document.revision)
        XCTAssertFalse(hidden.renderScene.objects.contains { $0.id == childID },
            "Previously adopted immutable scenes may not acquire newer visibility")
        let shownPlan = try CanvasRendererCore().prepare(scene: shown.renderScene, overlays: shown.overlays,
            viewport: viewport, previous: hidden.renderScene)
        XCTAssertTrue(shownPlan.accessibilityElements.contains { $0.objectID == childID })
        let shownStatic = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let shownCSS = try XCTUnwrap(shownStatic.files.first { $0.path == "styles.css" }).contents
        XCTAssertTrue(shownCSS.components(separatedBy: "\(selector) {").dropFirst().first?
            .components(separatedBy: "}").first?.contains("display: block;") == true)
    }

    func testComponentVisibilityDuplicationAndDetachPreserveIntentAndStableIDs() throws {
        let session = try exposedVisibilitySession()
        let definition = session.document.componentDefinitions[0], child = definition.nodes[1]
        let binding = try XCTUnwrap(CanonicalComponentVisibility.property(on: child))
        let page = session.document.websitePages[0], instance = page.nodes[1]
        try session.execute(textCommand(.setVisibilityOverride(instanceID: instance.id,
            propertyID: binding.id, value: true), document: session.document,
            pageID: page.id, selected: instance.id).command)
        let original = session.document.pages
        let duplicate = try PageCommandRegistry().prepare(.duplicate,
            identity: .init(documentID: session.document.id, revision: session.document.revision, pageID: page.id),
            in: session.document, isAvailable: true)
        try session.execute(duplicate.command)
        let copy = try XCTUnwrap(session.document.pages.first { $0.id == duplicate.selectedPageID })
        let copiedInstance = try XCTUnwrap(copy.nodes.first {
            $0.kind == .component && CanonicalComponentReference.definitionID(for: $0) == definition.id
        })
        XCTAssertNotEqual(copiedInstance.id, instance.id)
        XCTAssertEqual(CanonicalComponentVisibility.overrides(on: copiedInstance)[binding.id], true)
        let derivedID = NodeID(DocumentPage.deterministicUUID(namespace: copiedInstance.id.rawValue,
            label: "component-child:" + child.id.description))
        let expanded = try ComponentGraphResolver.resolvedPage(copy, in: session.document, breakpoint: .desktop)
        XCTAssertFalse(try XCTUnwrap(expanded.nodes.first { $0.id == derivedID }).selectionBooleanProperty("hidden"))
        try session.execute(textCommand(.detach(instance.id), document: session.document,
            pageID: page.id, selected: instance.id).command)
        let materializedID = NodeID(DocumentPage.deterministicUUID(namespace: instance.id.rawValue,
            label: "component-child:" + child.id.description))
        XCTAssertFalse(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == materializedID })
            .selectionBooleanProperty("hidden"))
        XCTAssertFalse(session.document.pages[0].nodes.contains { $0.properties.contains {
            $0.key.rawValue.hasPrefix(CanonicalComponentVisibility.namespace)
                || $0.key.rawValue.hasPrefix(CanonicalComponentVisibility.overrideNamespace)
        } })
        try session.undo(); try session.undo()
        XCTAssertEqual(session.document.pages, original)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testComponentTextV7MigrationAndStrictBindingValidation() throws {
        let legacy = try componentTextFixture()
        XCTAssertTrue(CanonicalComponentText.properties(in: legacy.componentDefinitions[0]).isEmpty)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(legacy)), legacy)
        let session = try exposedTextSession(), document = session.document
        XCTAssertEqual(document.websitePages, legacy.websitePages)
        let encoded = try DocumentSerializer.encode(document)
        XCTAssertThrowsError(try DocumentSerializer.decode(Data(String(decoding: encoded, as: UTF8.self)
            .replacingOccurrences(of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":7").utf8)))
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

    func testComponentOverridePathConflictPreservesIntentAndResetRestoresExactHistory() throws {
        let session = try exposedTextSession(), definition = session.document.componentDefinitions[0]
        let text = definition.nodes[1], binding = CanonicalComponentText.properties(in: definition)[0]
        let first = session.document.pages[0].nodes[1], pageID = session.document.pages[0].id
        try session.execute(textCommand(.setTextOverride(instanceID: first.id, propertyID: binding.id, value: "Retain"),
            document: session.document, pageID: pageID, selected: first.id).command)
        let authored = session.document
        let path = try XCTUnwrap(CanonicalComponentOverrides.resolve(instance: authored.pages[0].nodes[1], document: authored).first)
        XCTAssertEqual(path.path?.definitionID, definition.id)
        XCTAssertEqual(path.path?.sourceNodeID, text.id)
        guard case .authored(let stablePropertyID) = path.resolution else { return XCTFail("Expected authored override") }

        try session.execute(textCommand(.removeTextProperty(text.id), document: session.document,
            pageID: definition.id, selected: text.id).command)
        let unresolved = session.document
        let loaded = try DocumentSerializer.decode(DocumentSerializer.encode(unresolved))
        XCTAssertEqual(CanonicalComponentText.unresolvedOverrides(on: loaded.pages[0].nodes[1], definition: loaded.pages[2]), [binding.id])
        let conflict = try XCTUnwrap(CanonicalComponentOverrides.resolve(instance: loaded.pages[0].nodes[1], document: loaded).first)
        XCTAssertEqual(conflict.effectiveValue, .text("Retain"))
        XCTAssertNil(conflict.path)
        XCTAssertEqual(conflict.resolution, .conflict(.missingProperty, propertyID: stablePropertyID))
        XCTAssertNil(ComponentGraphResolver.detachedNodes(loaded.pages[0].nodes[1], definition: loaded.pages[2], page: loaded.pages[0]))
        try session.execute(textCommand(.resetAllOverrides(first.id), document: session.document,
            pageID: pageID, selected: first.id).command)
        XCTAssertTrue(CanonicalComponentText.overrides(on: session.document.pages[0].nodes[1]).isEmpty)
        let reset = session.document
        try session.undo()
        var expectedUnresolved = unresolved; expectedUnresolved.revision = session.document.revision
        XCTAssertEqual(session.document, expectedUnresolved)
        try session.redo()
        var expectedReset = reset; expectedReset.revision = session.document.revision
        XCTAssertEqual(session.document, expectedReset)
        try session.undo(); try session.undo()
        var expectedAuthored = authored; expectedAuthored.revision = session.document.revision
        XCTAssertEqual(session.document, expectedAuthored)
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
        let old = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":6")
        XCTAssertThrowsError(try DocumentSerializer.decode(Data(old.utf8)))
        let future = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion + 1)")
        XCTAssertThrowsError(try DocumentSerializer.decode(Data(future.utf8))) {
            XCTAssertEqual($0 as? DocumentSerializationError, .unsupportedSchema(DocumentSerializer.currentSchemaVersion + 1))
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

    // SF-AUTHORING-100: definition rename is one atomic graph transaction;
    // stable definition/instance identity and every linked display name agree.
    func testComponentRenamePropagatesStableIdentityPersistsAndUndoesExactly() throws {
        let document = try componentTextFixture()
        let definition = try XCTUnwrap(document.componentDefinitions.first)
        let page = try XCTUnwrap(document.websitePages.first)
        let instance = try XCTUnwrap(page.nodes.first {
            CanonicalComponentReference.definitionID(for: $0) == definition.id
        })
        let scene = CanvasViewportSceneID()
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [instance.id],
            availableNodeIDs: [instance.id], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let prepared = try ComponentCommandRegistry().prepare(
            .rename(definitionID: definition.id, name: "Feature Card"),
            identity: .init(documentID: document.id, pageID: page.id,
                revision: document.revision, sceneID: scene, rendererGeneration: document.revision),
            in: document, context: context)
        let session = DocumentSession(document: document)
        try session.execute(prepared.command)
        XCTAssertEqual(session.document.componentDefinitions.first { $0.id == definition.id }?.name, "Feature Card")
        let renamedUses = session.document.websitePages.flatMap(\.nodes).filter {
            CanonicalComponentReference.definitionID(for: $0) == definition.id
        }
        XCTAssertFalse(renamedUses.isEmpty)
        XCTAssertTrue(renamedUses.allSatisfy { $0.name == "Feature Card" })
        XCTAssertTrue(renamedUses.contains { $0.id == instance.id })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        var restored = session.document; restored.revision = document.revision
        XCTAssertEqual(restored, document)
        try session.redo()
        XCTAssertEqual(session.document.componentDefinitions.first { $0.id == definition.id }?.name, "Feature Card")
        let unchanged = session.document
        let liveIdentity = DesignInspectorOperationIdentity(documentID: session.document.id,
            pageID: page.id, revision: session.document.revision, sceneID: scene,
            rendererGeneration: session.document.revision)
        let liveContext = TransformValidationContext(activePageID: page.id,
            currentSceneID: scene, rendererGeneration: session.document.revision,
            selectedNodeIDs: [instance.id], availableNodeIDs: [instance.id],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(
            .rename(definitionID: definition.id, name: "Feature Card"),
            identity: liveIdentity, in: session.document, context: liveContext))
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(
            .rename(definitionID: definition.id, name: " \n "), identity: liveIdentity,
            in: session.document, context: liveContext))
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(
            .rename(definitionID: definition.id, name: "Cancelled"), identity: liveIdentity,
            in: session.document, context: liveContext, cancelled: true))
        XCTAssertThrowsError(try ComponentCommandRegistry().prepare(
            .rename(definitionID: definition.id, name: "Stale"),
            identity: .init(documentID: session.document.id, pageID: page.id,
                revision: session.document.revision - 1, sceneID: scene,
                rendererGeneration: session.document.revision),
            in: session.document, context: liveContext))
        XCTAssertEqual(session.document, unchanged)
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
            CanonicalLinkTarget.page(pageID).properties.map { .init(key: .init(rawValue: $0.0), value: $0.1) }
            + [.init(key: .init(rawValue: CanonicalSemanticElement.key), value: .string(SemanticHTMLElement.a.rawValue), origin: .authored)])
        try session.execute(.insertNode(.init(pageID: pageID, node: link, index: 0)))
        let copyID = try apply(.duplicate, pageID)
        let original = try XCTUnwrap(session.document.pages.first { $0.id == pageID })
        let copy = try XCTUnwrap(session.document.pages.first { $0.id == copyID })
        XCTAssertTrue(Set(original.nodes.map(\.id)).isDisjoint(with: copy.nodes.map(\.id)))
        XCTAssertEqual(try CanonicalLinkTarget.resolve(copy.nodes[1]), .page(copyID))
        XCTAssertNotEqual(original.nodes[1].properties[0].id, copy.nodes[1].properties[0].id)
        XCTAssertEqual(SemanticElementCommandRegistry.resolvedElement(for: copy.nodes[1])?.0, .a)
        XCTAssertNotEqual(original.nodes[1].insertionProperty(CanonicalSemanticElement.key)?.id,
                          copy.nodes[1].insertionProperty(CanonicalSemanticElement.key)?.id)
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

    // SF-1006-001, SF-1006-004, SF-1006-005 — the generic transaction
    // kernel owns form metadata exactly like other canonical properties. A
    // page copy must not alias nested select-option identity.
    func testFormFieldsPreserveAtomicHistoryAndRemapSelectOptionsOnPageDuplicate() throws {
        let formID = NodeID(), selectID = NodeID(), checkboxID = NodeID(), submitID = NodeID()
        let options = [
            CanonicalFormSelectOption(label: "Starter", value: "starter"),
            CanonicalFormSelectOption(label: "Professional", value: "pro"),
        ]
        let properties: (String, String, String, Bool, [NodeProperty]) -> [NodeProperty] = { kind, label, name, required, extra in
            [
                .init(key: .init(rawValue: CanonicalFormField.kindKey), value: .string(kind)),
                .init(key: .init(rawValue: CanonicalFormField.labelKey), value: .string(label)),
                .init(key: .init(rawValue: CanonicalFormField.nameKey), value: .string(name)),
                .init(key: .init(rawValue: CanonicalFormField.requiredKey), value: .boolean(required)),
            ] + extra
        }
        let pageID = PageID()
        let form = DocumentNode(id: formID, kind: .form, name: "Contact form", parent: .page(pageID), childIDs: [selectID, checkboxID, submitID])
        let select = DocumentNode(id: selectID, kind: .text, name: "Plan", parent: .node(formID), properties: properties("select", "Plan", "plan", true, [
            .init(key: .init(rawValue: CanonicalFormField.optionsKey), value: .string(try CanonicalFormSelectOptions.encode(options))),
        ]))
        let checkbox = DocumentNode(id: checkboxID, kind: .text, name: "Terms", parent: .node(formID), properties: properties("checkbox", "Terms", "terms", true, []))
        let submit = DocumentNode(id: submitID, kind: .text, name: "Submit", parent: .node(formID), properties: properties("submit", "Submit", "submit", false, []))
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [formID], nodes: [form, select, checkbox, submit])
        let session = DocumentSession(document: .init(pages: [page]))
        try session.document.validate()

        let original = session.document
        var label = try XCTUnwrap(session.document.pages[0].nodes[1].insertionProperty(CanonicalFormField.labelKey))
        label.value = .string("Choose a plan")
        try session.execute(.setProperty(.init(pageID: pageID, nodeID: selectID, property: label)))
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionStringProperty(CanonicalFormField.labelKey), "Choose a plan")
        try session.undo()
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionStringProperty(CanonicalFormField.labelKey), "Plan")
        try session.redo()
        XCTAssertEqual(session.document.pages[0].nodes[1].insertionStringProperty(CanonicalFormField.labelKey), "Choose a plan")
        XCTAssertTrue(session.canUndo)

        let firstBuild = try MultiPageStaticBuildPlanner.plan(document: session.document)
        XCTAssertEqual(firstBuild, try MultiPageStaticBuildPlanner.plan(document: session.document))
        XCTAssertEqual(firstBuild.integrityDigest.count, 64)
        XCTAssertEqual(firstBuild.integrityDigest, try MultiPageStaticBuildPlanner.plan(document: session.document).integrityDigest)
        let html = try XCTUnwrap(firstBuild.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("<form data-siteforge-node="))
        XCTAssertTrue(html.contains("<select"))
        XCTAssertTrue(html.contains("<input"))
        XCTAssertTrue(html.contains("type=\"checkbox\""))
        XCTAssertTrue(html.contains("data-siteforge-submission=\"unconfigured\""))

        let registry = PageCommandRegistry()
        let prepared = try registry.prepare(.duplicate, identity: .init(documentID: session.document.id,
            revision: session.document.revision, pageID: pageID), in: session.document, isAvailable: true)
        let copiedID = prepared.selectedPageID
        try session.execute(prepared.command)
        let source = try XCTUnwrap(session.document.pages.first { $0.id == pageID })
        let copy = try XCTUnwrap(session.document.pages.first { $0.id == copiedID })
        let sourceOptions = try CanonicalFormSelectOptions.decode(try XCTUnwrap(source.nodes.first { $0.name == "Plan" }?.insertionStringProperty(CanonicalFormField.optionsKey)))
        let copiedOptions = try CanonicalFormSelectOptions.decode(try XCTUnwrap(copy.nodes.first { $0.name == "Plan" }?.insertionStringProperty(CanonicalFormField.optionsKey)))
        XCTAssertEqual(sourceOptions.map(\.label), copiedOptions.map(\.label))
        XCTAssertEqual(sourceOptions.map(\.value), copiedOptions.map(\.value))
        XCTAssertTrue(Set(sourceOptions.map(\.id)).isDisjoint(with: Set(copiedOptions.map(\.id))))
        XCTAssertNotEqual(original.pages[0].nodes[1].properties[0].id, copy.nodes[1].properties[0].id)
    }

    // SF-1204-003, SF-1206-003 — multi-page planning adopts the typed
    // layout projection instead of deriving a second geometry cascade.
    func testMultiPageStaticBuildPlanIncludesTypedLayoutStylesheet() throws {
        let pageID = PageID()
        let nodeID = NodeID()
        let node = DocumentNode(id: nodeID, kind: .frame, name: "Card", parent: .page(pageID), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(32), origin: .defaulted),
            .init(key: .init(rawValue: "layout.y"), value: .number(48), origin: .defaulted),
            .init(key: .init(rawValue: "layout.width"), value: .number(240), origin: .defaulted),
            .init(key: .init(rawValue: "layout.height"), value: .number(160), origin: .defaulted),
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(200), origin: .authored),
        ])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [nodeID], nodes: [node])
        let document = CanonicalDocument(pages: [page])

        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let stylesheet = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(stylesheet.contains(CanonicalCSSRule.selector(for: nodeID)))
        XCTAssertTrue(stylesheet.contains("left: 32.0px;"))
        XCTAssertTrue(stylesheet.contains("@media (max-width: 599px)"))
        XCTAssertTrue(stylesheet.contains("width: 200.0px;"))
        XCTAssertEqual(plan.files.last?.path, "manifest.txt")
    }

    // SF-0801-003, SF-0802-003, SF-0601-003, SF-0603-003, SF-1203-003 —
    // verified Image identity, intrinsic metadata, and typed responsive
    // layout share the same immutable static plan without a source-set path.
    func testMultiPageStaticBuildPlanIncludesVerifiedResponsiveImageReference() throws {
        let pageID = PageID(), nodeID = NodeID(), resourceID = ResourceID()
        let hash = String(repeating: "a", count: 64)
        let asset = ImageAsset(resourceID: resourceID, displayName: "Card", originalFilename: "card.png",
                               format: .png, pixelWidth: 640, pixelHeight: 480, byteCount: 1, contentHash: hash)
        let node = DocumentNode(id: nodeID, kind: .image, name: "Card", parent: .page(pageID), properties: [
            .init(key: .init(rawValue: "layout.x"), value: .number(32), origin: .defaulted),
            .init(key: .init(rawValue: "layout.y"), value: .number(48), origin: .defaulted),
            .init(key: .init(rawValue: "layout.width"), value: .number(320), origin: .defaulted),
            .init(key: .init(rawValue: "layout.height"), value: .number(240), origin: .defaulted),
            .init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(200), origin: .authored),
            .init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(false), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"), value: .string(asset.id.description), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string(ImageFitMode.fit.rawValue), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string("A <card>"), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(false), origin: .defaulted),
        ])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [nodeID], nodes: [node])
        let entry = StaticAssetExportEntry(resourceID: resourceID, outputPath: "assets/\(hash).png", sha256: hash)
        let plan = try MultiPageStaticBuildPlanner.plan(
            document: .init(pages: [page], imageAssets: [asset]), imageOutputEntries: [entry]
        )
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("src=\"assets/\(hash).png\""))
        XCTAssertTrue(html.contains("alt=\"A &lt;card&gt;\""))
        XCTAssertTrue(html.contains("data-siteforge-asset=\"\(asset.id.description)\""))
        XCTAssertTrue(html.contains("width=\"640\" height=\"480\""))
        let stylesheet = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(stylesheet.contains(CanonicalCSSRule.selector(for: nodeID)))
        XCTAssertTrue(stylesheet.contains("width: 320.0px;"))
        XCTAssertTrue(stylesheet.contains("@media (max-width: 599px)"))
        XCTAssertTrue(stylesheet.contains("width: 200.0px;"))
        XCTAssertTrue(stylesheet.contains("display: none;"))
        XCTAssertTrue(stylesheet.contains("object-fit: contain;"))
        XCTAssertTrue(stylesheet.contains("object-position: 50.0% 50.0%;"))
        let assetManifest = try XCTUnwrap(plan.files.first { $0.path == "assets.manifest.txt" }?.contents)
        XCTAssertTrue(assetManifest.contains(asset.id.description))
        XCTAssertTrue(assetManifest.contains("assets/\(hash).png\t640x480"))
        XCTAssertFalse(assetManifest.contains(asset.originalFilename))
    }

    // SF-1203-003, SF-1203-004 — immutable static output uses the same typed
    // authored semantic resolution as the Inspector, never a raw markup key.
    func testMultiPageStaticBuildPlanUsesAuthoredSemanticElementResolution() throws {
        let pageID = PageID(), nodeID = NodeID()
        let node = DocumentNode(id: nodeID, kind: .frame, name: "Article", parent: .page(pageID), properties: [
            .init(key: .init(rawValue: CanonicalSemanticElement.key), value: .string(SemanticHTMLElement.article.rawValue), origin: .authored),
        ])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [nodeID], nodes: [node])
        let plan = try MultiPageStaticBuildPlanner.plan(document: .init(pages: [page]))
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("<article data-siteforge-node=\"\(nodeID.rawValue.uuidString.lowercased())\""))
        XCTAssertFalse(html.contains("<div data-siteforge-node=\"\(nodeID.rawValue.uuidString.lowercased())\""))
        let outline = try XCTUnwrap(plan.files.first { $0.path == "semantic-outline.txt" }?.contents)
        XCTAssertTrue(outline.contains("\(pageID.description)\t\(nodeID.description)\t-\tarticle"))
    }

    // SF-0508-003, SF-0701-003, SF-1204-003 — only typed canonical Frame and
    // Section layers become fixed static CSS; layer order stays immutable.
    func testMultiPageStaticBuildPlanProjectsClosedFrameAndSectionFillLayers() throws {
        let pageID = PageID(), frameID = NodeID(), sectionID = NodeID()
        let red = CanonicalSolidColor(red: 1, green: 0, blue: 0, alpha: 1)
        let blue = CanonicalSolidColor(red: 0, green: 0, blue: 1, alpha: 0.5)
        let frameLayers = [CanonicalFillLayer.solid(color: red)]
        let sectionLayers = [CanonicalFillLayer.linearGradient(angleDegrees: 0, stops: [
            .init(id: GradientStopID(), position: 0, color: red),
            .init(id: GradientStopID(), position: 1, color: blue),
        ])]
        func properties(_ layers: [CanonicalFillLayer]) -> [NodeProperty] {
            CanonicalFillLayerCodec.propertyValues(for: layers).map {
                .init(key: .init(rawValue: $0.key), value: $0.value, origin: .authored)
            }
        }
        var frameProperties = properties(frameLayers)
        frameProperties.append(.init(key: .init(rawValue: "style.opacity"), value: .number(0.5), origin: .authored))
        let frame = DocumentNode(id: frameID, kind: .frame, name: "Frame", parent: .page(pageID), properties: frameProperties)
        let section = DocumentNode(id: sectionID, kind: .section, name: "Section", parent: .page(pageID), properties: properties(sectionLayers) + [
            .init(key: .init(rawValue: "layout.container.kind"), value: .string("section"), origin: .defaulted),
            .init(key: .init(rawValue: "layout.padding"), value: .number(48), origin: .defaulted),
            .init(key: .init(rawValue: "layout.axis"), value: .string("vertical"), origin: .defaulted)])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [frameID, sectionID], nodes: [frame, section])
        let plan = try MultiPageStaticBuildPlanner.plan(document: .init(pages: [page]))
        let stylesheet = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(stylesheet.contains("\(CanonicalCSSRule.selector(for: frameID)) { background-image: linear-gradient(90deg, rgba(255.0, 0.0, 0.0, 1.0) 0%, rgba(255.0, 0.0, 0.0, 1.0) 100%); opacity: 0.5; }"), stylesheet)
        XCTAssertTrue(stylesheet.contains("\(CanonicalCSSRule.selector(for: sectionID)) { background-image: linear-gradient(90.0deg, rgba(255.0, 0.0, 0.0, 1.0) 0.0%, rgba(0.0, 0.0, 255.0, 0.5) 100.0%); }"))
    }

    func testStaticSolidFillResolvesLocalColorTokenWithoutChangingLiteralFallback() throws {
        let pageID = PageID(), nodeID = NodeID()
        let fallback = CanonicalSolidColor(red: 1, green: 0, blue: 0, alpha: 1)
        let resolved = CanonicalSolidColor(red: 0, green: 0.5, blue: 1, alpha: 1)
        let token = LocalColorToken(name: "Brand", color: resolved)
        let layer = CanonicalFillLayer.solid(color: fallback)
        let properties = CanonicalFillLayerCodec.propertyValues(for: [layer]).map {
            NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored)
        } + [NodeProperty(key: .init(rawValue: LocalColorTokenBinding.key(for: .fill)), value: .string(token.id.description), origin: .authored)]
        let frame = DocumentNode(id: nodeID, kind: .frame, name: "Frame", parent: .page(pageID), properties: properties)
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [nodeID], nodes: [frame])
        let document = CanonicalDocument(pages: [page], colorTokens: [token])
        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("rgba(0.0, 127.5, 255.0, 1.0)"), css)
        XCTAssertFalse(css.contains("rgba(255.0, 0.0, 0.0, 1.0)"), css)
        XCTAssertEqual(DesignInspectorCommandRegistry.resolvedLayers(for: frame).first?.solidColor, fallback)
        XCTAssertEqual(LocalColorTokenResolver.resolvedLayers(for: frame, in: document).first?.solidColor, resolved)
    }

    func testClosedStaticSizingProjectsOnlyValidatedFrameAndImageConstraints() throws {
        let pageID = PageID(), frameID = NodeID(), imageID = NodeID()
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Card", originalFilename: "card.png",
            format: .png, pixelWidth: 64, pixelHeight: 64, byteCount: 1,
            contentHash: String(repeating: "a", count: 64))
        func property(_ suffix: String, _ value: PropertyValue) -> NodeProperty {
            .init(key: .init(rawValue: CanonicalSizingConstraints.prefix + suffix),
                value: value, origin: .authored)
        }
        let frame = DocumentNode(id: frameID, kind: .frame, name: "Frame", parent: .page(pageID),
            properties: [.init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .authored),
                         .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .authored),
                         .init(key: .init(rawValue: "layout.width"), value: .number(150), origin: .authored),
                         .init(key: .init(rawValue: "layout.height"), value: .number(100), origin: .authored),
                         property("minWidth", .number(100)), property("maxWidth", .number(500)),
                         property("aspectRatio", .number(1.5)), property("aspectEnabled", .boolean(true))])
        let image = DocumentNode(id: imageID, kind: .image, name: "Image", parent: .page(pageID),
            properties: [.init(key: .init(rawValue: "layout.x"), value: .number(180), origin: .authored),
                .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .authored),
                .init(key: .init(rawValue: "layout.width"), value: .number(64), origin: .authored),
                .init(key: .init(rawValue: "layout.height"), value: .number(64), origin: .authored),
                property("minHeight", .number(40)),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"),
                    value: .string(asset.id.description), origin: .authored),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string("fit"), origin: .defaulted),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.5), origin: .defaulted),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.5), origin: .defaulted),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string(""), origin: .defaulted),
                .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(true), origin: .defaulted)])
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
            rootNodeIDs: [frameID, imageID], nodes: [frame, image])
        let document = CanonicalDocument(pages: [page], imageAssets: [asset])
        let output = try MultiPageStaticBuildPlanner.plan(document: document,
            imageOutputEntries: [.init(resourceID: asset.resourceID,
                outputPath: "assets/\(asset.contentHash).png", sha256: asset.contentHash)])
        let css = try XCTUnwrap(output.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(css.contains("min-width: 100.0px;"), css)
        XCTAssertTrue(css.contains("max-width: 500.0px;"), css)
        XCTAssertTrue(css.contains("aspect-ratio: 1.5;"), css)
        XCTAssertTrue(css.contains("min-height: 40.0px;"), css)
        XCTAssertFalse(css.contains("var("), css)
    }

    // SF-0506-001...005, SF-1204-003 — only typed Frame/Section box values
    // enter the closed static declaration vocabulary.
    func testMultiPageStaticBuildPlanProjectsClosedFrameBoxStyle() throws {
        let pageID = PageID(), frameID = NodeID()
        let properties: [NodeProperty] = [
            .init(key: .init(rawValue: "style.box.v1.border.width"), value: .number(2), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.border.style"), value: .string("dashed"), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.border.color.red"), value: .number(0.1), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.border.color.green"), value: .number(0.2), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.border.color.blue"), value: .number(0.3), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.border.color.alpha"), value: .number(1), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.radius.uniform"), value: .number(12), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.padding.uniform"), value: .number(24), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.clip.content"), value: .boolean(true), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.shadow.offsetX"), value: .number(2), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.shadow.offsetY"), value: .number(8), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.shadow.blur"), value: .number(12), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.shadow.spread"), value: .number(1), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.shadow.color.red"), value: .number(0), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.shadow.color.green"), value: .number(0), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.shadow.color.blue"), value: .number(0), origin: .authored),
            .init(key: .init(rawValue: "style.box.v1.shadow.color.alpha"), value: .number(0.25), origin: .authored),
        ]
        let frame = DocumentNode(id: frameID, kind: .frame, name: "Frame", parent: .page(pageID), properties: properties)
        let page = DocumentPage(id: pageID, name: "Home", route: .init(rawValue: "/"), role: .home,
                                rootNodeIDs: [frameID], nodes: [frame])
        let plan = try MultiPageStaticBuildPlanner.plan(document: .init(pages: [page]))
        let stylesheet = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(stylesheet.contains("\(CanonicalCSSRule.selector(for: frameID)) { border: 2.0px dashed rgba(25.5, 51.0, 76.5, 1.0); border-radius: 12.0px; padding: 24.0px; overflow: hidden; box-shadow:"), stylesheet)
        XCTAssertTrue(stylesheet.contains("box-shadow: 2.0px 8.0px 12.0px 1.0px rgba(0.0, 0.0, 0.0, 0.25);"), stylesheet)

        // SF-0506-003/005 — an explicit disabled state retains the typed
        // authored values for later re-enable, but it must not enter output.
        var disabledFrame = frame
        disabledFrame.properties.append(.init(
            key: .init(rawValue: "style.box.v1.shadow.enabled"),
            value: .boolean(false),
            origin: .authored
        ))
        var disabledPage = page
        disabledPage.nodes = [disabledFrame]
        let disabledPlan = try MultiPageStaticBuildPlanner.plan(document: .init(pages: [disabledPage]))
        let disabledStylesheet = try XCTUnwrap(disabledPlan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertFalse(disabledStylesheet.contains("box-shadow:"), disabledStylesheet)
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
        XCTAssertTrue(json.contains("\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)"))
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
        let unknown = Data(valid.replacingOccurrences(of: "\"schemaVersion\":\(DocumentSerializer.currentSchemaVersion)", with: "\"schemaVersion\":99").utf8)
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

    // SF-0604-001/005 — page duplication keeps fluid intent and values but
    // regenerates the value identity so source and copy cannot alias later.
    func testPageDuplicateRemapsFluidValueIdentityAndPreservesFixedFallback() throws {
        var document = ProjectCreation.blank()
        let pageID = document.pages[0].id, rootID = document.pages[0].rootNodeIDs[0]
        let frameID = NodeID()
        let fluid = CanonicalFluidValue(minimum: 160, preferred: 240, maximum: 360)
        document.pages[0].nodes[0].childIDs = [frameID]
        document.pages[0].nodes.append(.init(id: frameID, kind: .frame, name: "Fluid Frame",
            parent: .node(rootID), properties: [
                .init(key: .init(rawValue: "layout.x"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.y"), value: .number(0), origin: .defaulted),
                .init(key: .init(rawValue: "layout.width"), value: .number(240), origin: .defaulted),
                .init(key: .init(rawValue: "layout.height"), value: .number(160), origin: .defaulted),
                .init(key: .init(rawValue: CanonicalFluidValueCodec.key(.width)),
                      value: .string(try CanonicalFluidValueCodec.encode(fluid, target: .width)),
                      origin: .authored),
            ]))
        let session = DocumentSession(document: document)
        let duplicate = try PageCommandRegistry().prepare(.duplicate,
            identity: .init(documentID: document.id, revision: document.revision, pageID: pageID),
            in: document, isAvailable: true)
        try session.execute(duplicate.command)
        let source = try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == frameID })
        let copyPage = try XCTUnwrap(session.document.pages.first { $0.id == duplicate.selectedPageID })
        let copy = try XCTUnwrap(copyPage.nodes.first { $0.name == "Fluid Frame" })
        let sourceFluid = try CanonicalFluidValueCodec.decode(try XCTUnwrap(
            source.insertionStringProperty(CanonicalFluidValueCodec.key(.width))), target: .width)
        let copyFluid = try CanonicalFluidValueCodec.decode(try XCTUnwrap(
            copy.insertionStringProperty(CanonicalFluidValueCodec.key(.width))), target: .width)
        XCTAssertNotEqual(copyFluid.id, sourceFluid.id)
        XCTAssertEqual([copyFluid.minimum, copyFluid.preferred, copyFluid.maximum], [160, 240, 360])
        XCTAssertEqual(copy.insertionNumberProperty("layout.width"), 240)
        XCTAssertEqual(try DocumentSerializer.decode(try DocumentSerializer.encode(session.document)), session.document)
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
