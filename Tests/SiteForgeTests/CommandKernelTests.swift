import Combine
import XCTest
@testable import SiteForge

@MainActor
final class CommandKernelTests: XCTestCase {
    // SF-0307-001, SF-0307-002, SF-0307-003, SF-0307-004 (ADR-0132)
    func testHistoryListMarksStepsSavingDropsAndJumpMovesBothWays() throws {
        let session = DocumentSession()
        let pageID = PageID()
        try session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: "Start"), index: 0)))
        for index in 0..<(PersistedHistoryStore.maximumEntryCount + 2) {
            try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Name \(index)")))
        }
        let items = session.historyList()
        XCTAssertEqual(items.count, PersistedHistoryStore.maximumEntryCount + 3)
        XCTAssertEqual(items.filter { !$0.persistsOnSave }.count, 3, "Saving keeps only the newest entries")
        XCTAssertFalse(items[0].persistsOnSave)
        XCTAssertTrue(items[3].persistsOnSave)
        XCTAssertEqual(items.filter(\.isCurrent).map(\.id), [items[items.count - 1].id])
        XCTAssertTrue(items.allSatisfy { $0.pageIDs == [pageID] })
        XCTAssertEqual(items[1].name, session.registry.descriptor(for: .renamePage).title)

        let revision = session.document.revision
        XCTAssertEqual(try session.jump(toStateAfter: items[items.count - 1].id), 0, "The current state needs no step")
        XCTAssertEqual(session.document.revision, revision)
        XCTAssertEqual(try session.jump(toStateAfter: items[0].id), items.count - 1)
        XCTAssertEqual(session.document.pages.first { $0.id == pageID }?.name, "Start")
        XCTAssertEqual(session.nextRedoPageIDs, [pageID])
        XCTAssertEqual(session.historyList().map(\.id), items.map(\.id), "Jumping deletes nothing")
        // With one applied step left, saving drops it first and then the
        // farthest Redo steps, exactly as PersistedHistoryStore.removingOldest does.
        XCTAssertEqual(session.historyList().filter { !$0.persistsOnSave }.map(\.id),
                       [items[0].id, items[items.count - 2].id, items[items.count - 1].id])
        XCTAssertEqual(try session.jump(toStateAfter: items[5].id), 5)
        XCTAssertEqual(session.document.pages.first { $0.id == pageID }?.name, "Name 4")
        XCTAssertThrowsError(try session.jump(toStateAfter: TransactionID()))
        XCTAssertEqual(session.historyList().filter(\.isApplied).count, 6, "A refused jump changes nothing")

        // SF-0307-004: a step that fails part-way through a jump reverses the
        // steps already taken, so content and both stacks stay as they were.
        let failing = DocumentSession()
        let failingPage = PageID()
        try failing.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: failingPage, name: "Kept"), index: 0)))
        try failing.execute(.renamePage(RenamePageCommand(pageID: failingPage, name: "Renamed")))
        let failingHistory = failing.historySnapshot()
        let insertEntry = failingHistory.undoEntries[0], renameEntry = failingHistory.undoEntries[1]
        let brokenInsert = HistoryEntry(
            id: insertEntry.id, parentRevision: insertEntry.parentRevision, resultRevision: insertEntry.resultRevision,
            commandName: insertEntry.commandName, label: insertEntry.label, timestamp: insertEntry.timestamp,
            affectedIdentifiers: insertEntry.affectedIdentifiers, forward: insertEntry.forward,
            inverse: .renamePage(RenamePageCommand(pageID: PageID(), name: "Missing"))
        )
        try failing.installValidatedHistory(PersistedHistorySnapshot(
            documentID: failingHistory.documentID, documentRevision: failingHistory.documentRevision,
            boundaryRevision: failingHistory.boundaryRevision, undoEntries: [brokenInsert, renameEntry], redoEntries: []
        ))
        let pagesBeforeFailedJump = failing.document.pages
        XCTAssertThrowsError(try failing.jump(toStateAfter: nil))
        XCTAssertEqual(failing.document.pages, pagesBeforeFailedJump, "The step already undone is redone")
        XCTAssertEqual(failing.historyList().map(\.id), [insertEntry.id, renameEntry.id])
        XCTAssertEqual(failing.historyList().map(\.isApplied), [true, true])
    }

    // SF-0306-002, SF-0306-003, SF-0306-004, SF-0306-005 (ADR-0131)
    func testCoalescedTransactionsAreOneUndoStepNamedBoundedAndPersistable() async throws {
        let session = DocumentSession()
        let pageID = PageID()
        try session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: "Start"), index: 0)))
        let baseline = session.document
        let key = TransactionCoalescingKey(kind: "test-rename", identifiers: [pageID.description])
        let start = Date(timeIntervalSince1970: 1_000)
        func name() -> String? { session.document.pages.first { $0.id == pageID }?.name }
        func rename(_ value: String, key: TransactionCoalescingKey, after seconds: TimeInterval) throws {
            try session.executeCoalescing(.renamePage(RenamePageCommand(pageID: pageID, name: value)),
                                          key: key, at: start.addingTimeInterval(seconds))
        }

        try rename("One", key: key, after: 0)
        try rename("Two", key: key, after: 0.5)
        try rename("Three", key: key, after: 1.0)
        XCTAssertEqual(name(), "Three")
        XCTAssertEqual(session.coalescedTransactionCount, 2)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 2, "Insert plus one merged rename")
        let merged = try XCTUnwrap(session.historySnapshot().undoEntries.last)
        XCTAssertEqual(merged.resultRevision, merged.parentRevision + 1, "A merged step is still one revision")
        XCTAssertEqual(merged.commandName, .batch)
        XCTAssertEqual(session.transactionName(for: merged),
                       "\(session.registry.descriptor(for: .renamePage).title) (3 changes)")
        let insert = try XCTUnwrap(session.historySnapshot().undoEntries.first)
        XCTAssertEqual(session.transactionName(for: insert), insert.label)

        try session.undo()
        XCTAssertEqual(session.document.pages, baseline.pages, "One Undo reverts the whole run")
        try session.redo()
        XCTAssertEqual(name(), "Three")

        // Redo, a gap longer than the window, an explicit end and another key
        // each start a new step.
        try rename("Four", key: key, after: 10)
        try rename("Five", key: key, after: 10 + DocumentSession.coalescingWindow + 1)
        session.endCoalescing()
        try rename("Six", key: key, after: 13.2)
        try rename("Seven", key: TransactionCoalescingKey(kind: "other", identifiers: []), after: 13.3)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 6)
        XCTAssertEqual(session.coalescedTransactionCount, 2)

        // A failed edit commits nothing and ends the run.
        let before = session.document
        XCTAssertThrowsError(try session.executeCoalescing(
            .renamePage(RenamePageCommand(pageID: PageID(), name: "Missing")), key: key, at: start.addingTimeInterval(13.4)))
        XCTAssertEqual(session.document, before)
        try rename("Eight", key: key, after: 13.5)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 7)

        // Merged entries pass persisted-history validation unchanged.
        let store = PersistedHistoryStore()
        let data = try await store.encodeRetained(session.historySnapshot())
        let package = ProjectPackage(document: session.document,
                                     optionalMembers: [ProjectPackageMember(path: PersistedHistoryStore.memberPath, data: data)])
        let loaded = try await store.load(from: package)
        guard case .restored(let restored) = loaded else { return XCTFail("Merged history must validate: \(loaded)") }
        XCTAssertEqual(restored.undoEntries, session.historySnapshot().undoEntries)

        // The in-memory journal is bounded; the boundary advances past dropped entries.
        let bounded = DocumentSession()
        let boundedPage = PageID()
        let firstRevision = bounded.document.revision
        try bounded.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: boundedPage, name: "Start"), index: 0)))
        for index in 0..<(DocumentSession.maximumUndoEntries + 4) {
            try bounded.execute(.renamePage(RenamePageCommand(pageID: boundedPage, name: "Name \(index)")))
        }
        XCTAssertEqual(bounded.historySnapshot().undoEntries.count, DocumentSession.maximumUndoEntries)
        XCTAssertEqual(bounded.droppedTransactionCount, 5)
        XCTAssertEqual(bounded.transactionDiagnosticRecords.filter { $0.operation == .trim }.map(\.stepCount), [1, 1, 1, 1, 1])
        let oldest = try XCTUnwrap(bounded.historySnapshot().undoEntries.first)
        XCTAssertGreaterThan(bounded.historyBoundaryRevision, firstRevision)
        XCTAssertLessThanOrEqual(bounded.historyBoundaryRevision, oldest.parentRevision)
        while bounded.canUndo { try bounded.undo() }
        XCTAssertEqual(bounded.document.pages.first { $0.id == boundedPage }?.name, "Name 3")
    }

    // SF-0306-006, SF-0306-008, SF-0307-008 (ADR-0133)
    func testGroupedStepDescriptionsAndTransactionDiagnosticsStayRedacted() throws {
        let session = DocumentSession()
        let pageID = PageID()
        try session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: "Start"), index: 0)))
        let insertTitle = session.registry.descriptor(for: .insertPage).title
        XCTAssertEqual(session.nextUndoDescription, insertTitle, "An ordinary step reads as its registry title")
        let key = TransactionCoalescingKey(kind: "test-description", identifiers: [pageID.description])
        let start = Date(timeIntervalSince1970: 3_000)
        try session.executeCoalescing(.renamePage(RenamePageCommand(pageID: pageID, name: "One")), key: key, at: start)
        try session.executeCoalescing(.renamePage(RenamePageCommand(pageID: pageID, name: "Two")), key: key,
                                      at: start.addingTimeInterval(0.5))
        let grouped = "\(session.registry.descriptor(for: .batch).title): "
            + "\(session.registry.descriptor(for: .renamePage).title) (2 changes)"
        XCTAssertEqual(session.nextUndoDescription, grouped)
        XCTAssertNil(session.nextRedoDescription)
        try session.undo()
        XCTAssertEqual(session.nextRedoDescription, grouped)
        XCTAssertEqual(session.nextUndoDescription, insertTitle)
        try session.redo()

        XCTAssertEqual(session.transactionDiagnosticRecords.map(\.operation), [.coalesce])
        let merge = try XCTUnwrap(session.transactionDiagnosticRecords.first)
        XCTAssertEqual(merge.requirementID, "SF-0306-008")
        XCTAssertEqual(merge.stepCount, 2)
        XCTAssertNil(merge.failureCategory)

        let items = session.historyList()
        XCTAssertEqual(try session.jump(toStateAfter: items[0].id), 1)
        XCTAssertThrowsError(try session.jump(toStateAfter: TransactionID()))
        let jumps = session.transactionDiagnosticRecords.filter { $0.operation == .jump }
        XCTAssertEqual(jumps.map(\.stepCount), [1, 0])
        XCTAssertEqual(jumps.map(\.failureCategory), [nil, "not-found"])
        XCTAssertTrue(jumps.allSatisfy { $0.requirementID == "SF-0307-008" })
        XCTAssertFalse(String(describing: session.transactionDiagnosticRecords).contains("Two"),
                       "Records hold counts and categories, never authored names")
    }

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
        XCTAssertEqual(state.componentReturnActionTitle, "Back to this copy")
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
        // One use of each kind this fixture creates; it has no social image or translated image.
        XCTAssertEqual(Set(references.map(\.kind)), [.image, .fill, .definition, .mediaOverride, .favicon])
        for kind in Set(references.map(\.kind)) { XCTAssertEqual(references.filter { $0.kind == kind }.count, 1) }
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
    /// OD-034 fixture: one Frame-rooted definition per name. `links[i]` lists,
    /// in order, the definitions (by index) that instances inside definition
    /// `i` link to; -1 links to a definition that does not exist. `extra[i]`
    /// adds that many plain Frames to definition `i`.
    private func nestedComponentDocument(_ names: [String], links: [[Int]],
                                         extra: [Int] = []) -> (CanonicalDocument, [PageID]) {
        var document = BlankProjectDefaults.document()
        let ids = names.map { _ in PageID() }
        func geometry(_ index: Int, size: Double = 10) -> [NodeProperty] {
            [("layout.x", Double(index % 40) * 12), ("layout.y", Double(index / 40) * 12),
             ("layout.width", size), ("layout.height", size)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            }
        }
        for (index, name) in names.enumerated() {
            let rootID = NodeID()
            var children: [DocumentNode] = []
            let targets = index < links.count ? links[index] : []
            let parts = index < extra.count ? extra[index] : 0
            for target in targets {
                let targetID = target >= 0 ? ids[target] : PageID()
                children.append(DocumentNode(kind: .component, name: target >= 0 ? names[target] : "Missing",
                    parent: .node(rootID), properties: geometry(children.count) + [NodeProperty(
                        key: .init(rawValue: CanonicalComponentReference.key), value: .string(targetID.description))]))
            }
            for part in 0..<parts {
                children.append(DocumentNode(kind: .frame, name: "Part \(part + 1)", parent: .node(rootID),
                                             properties: geometry(children.count)))
            }
            let root = DocumentNode(id: rootID, kind: .frame, name: name, parent: .page(ids[index]),
                                    childIDs: children.map(\.id), properties: geometry(0, size: 480))
            document.pages.append(DocumentPage(id: ids[index], name: name, route: .init(rawValue: ""),
                role: .componentDefinition, provenance: .authored, rootNodeIDs: [rootID], nodes: [root] + children))
        }
        return (document, ids)
    }

    /// OD-018 fixture: the slot fallback fixture with its container exposed as
    /// slot "Content" (two Text defaults); the home page has instances
    /// First (nodes[1]) and Second (nodes[2]).
    private func suppliedSlotFixture() throws -> (CanonicalDocument, ExposedComponentSlotProperty) {
        let (document, slotID, _) = try componentSlotFallbackFixture()
        let definitionID = document.componentDefinitions[0].id
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.exposeSlot(nodeID: slotID, label: "Content"), document: document,
            pageID: definitionID, selected: slotID).command)
        let slot = try XCTUnwrap(CanonicalComponentSlot.properties(in: session.document.componentDefinitions[0]).first)
        return (session.document, slot)
    }

    /// Appends top-level supplied items of `kinds` (slot-local geometry) to an
    /// instance on the first page and marks the slot as supplied.
    @discardableResult
    private func supply(_ kinds: [NodeKind], slot: ComponentSlotPropertyID, to instanceID: NodeID,
                        in document: inout CanonicalDocument, validate: Bool = true) throws -> [NodeID] {
        let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == instanceID })
        let existing = document.pages[0].nodes[index].childIDs.count
        let nodes = kinds.enumerated().map { offset, kind in
            DocumentNode(kind: kind, name: "Supplied \(existing + offset + 1)", parent: .node(instanceID), properties: [
                ("layout.x", 0.0), ("layout.y", Double(existing + offset) * 28), ("layout.width", 120.0), ("layout.height", 24.0)].map {
                    NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
                } + [NodeProperty(key: .init(rawValue: CanonicalComponentSlot.supplyKey), value: .string(slot.description), origin: .authored)]
                + (kind == .text ? [NodeProperty(key: .init(rawValue: "content.text"), value: .string("Supplied"))] : []))
        }
        let key = CanonicalComponentSlot.overrideKey(slot)
        if !document.pages[0].nodes[index].properties.contains(where: { $0.key.rawValue == key }) {
            document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: key),
                value: .string(CanonicalComponentSlot.suppliedValue), origin: .authored))
        }
        document.pages[0].nodes[index].childIDs += nodes.map(\.id)
        document.pages[0].nodes += nodes
        if validate { try document.validate() }
        return nodes.map(\.id)
    }

    private func markEmpty(_ slot: ComponentSlotPropertyID, on instanceID: NodeID, in document: inout CanonicalDocument) throws {
        let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == instanceID })
        document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: CanonicalComponentSlot.overrideKey(slot)),
            value: .string(CanonicalComponentSlot.emptyValue), origin: .authored))
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

    // SF-LOCAL-BUILDER-012 continuation; execution is recorded in its focused receipt.
    func testPlainComponentDiscoveryFindsCopyOriginalAndDefaultContentsWithoutMutation() throws {
        let document = try organizedComponentFixture()
        let entries = CanonicalComponentOrganization.entries(in: document.componentDefinitions[0])
        let first = try XCTUnwrap(entries.first)
        let custom: Set<ComponentOverridePropertyIdentity> = [first.id]
        for query in ["change this copy", "custom value", "authored override"] {
            XCTAssertEqual(ComponentPropertyDiscovery.project(entries, query: query, authored: custom, conflicts: []).entries.map(\.id), [first.id])
        }
        XCTAssertEqual(ComponentPropertyDiscovery.project(entries, query: "uses component default", authored: custom, conflicts: []).entries.map(\.id), entries.dropFirst().map(\.id))
        XCTAssertEqual(ComponentPropertyDiscovery.project(entries, query: "default contents", authored: [], conflicts: []).entries.map(\.id), entries.filter { $0.id.organizationKind == "slot" }.map(\.id))
        XCTAssertEqual(ComponentPropertyDiscovery.project(entries, query: "fallback", authored: [], conflicts: []).entries.map(\.id), entries.filter { $0.id.organizationKind == "slot" }.map(\.id))
        XCTAssertEqual(ComponentPropertyDiscovery.project(entries, query: "needs attention", authored: custom, conflicts: custom, conflictsOnly: true).entries.map(\.id), [first.id])
        XCTAssertTrue(ComponentPropertyDiscovery.project(entries, query: "private-custom-content", authored: custom, conflicts: custom).entries.isEmpty)
        XCTAssertEqual(CanonicalComponentOrganization.entries(in: document.componentDefinitions[0]), entries)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
    }

    func testPlainRecoveryRemovalPreservesConfirmationScopeIdentityAndExactUndo() throws {
        let (session, instanceID) = try retainedComponentConflictSession()
        let before = session.document
        let pageID = before.websitePages[0].id
        let instance = try XCTUnwrap(before.websitePages[0].nodes.first { $0.id == instanceID })
        let findings = try CanonicalComponentOverrides.conflicts(instance: instance, document: before)
        let finding = try XCTUnwrap(findings.first)
        let historyCount = session.historySnapshot().undoEntries.count
        XCTAssertEqual(findings.count, 5)
        XCTAssertEqual(AuthoringLanguage.componentResetTitle(count: findings.count), "Reset copy changes (5)")
        XCTAssertThrowsError(try textCommand(.resetOverrideConflicts(instanceID: instanceID,
            expectedPropertyIDs: [finding.authoredPropertyID], confirmed: false), document: before, pageID: pageID, selected: instanceID))
        XCTAssertEqual(session.document, before)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, historyCount)
        try session.execute(textCommand(.resetOverrideConflicts(instanceID: instanceID,
            expectedPropertyIDs: [finding.authoredPropertyID], confirmed: true), document: before, pageID: pageID, selected: instanceID).command)
        let after = session.document
        let changed = try XCTUnwrap(after.websitePages[0].nodes.first { $0.id == instanceID })
        XCTAssertEqual(changed.id, instance.id)
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: changed), CanonicalComponentReference.definitionID(for: instance))
        XCTAssertEqual(changed.properties, instance.properties.filter { $0.id != finding.authoredPropertyID })
        XCTAssertEqual(after.componentDefinitions, before.componentDefinitions)
        XCTAssertEqual(try CanonicalComponentOverrides.conflicts(instance: changed, document: after).count, 4)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, historyCount + 1)
        try session.undo()
        XCTAssertEqual(session.document.pages, before.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, after.pages)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
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

    func testComponentUsageNotesNormalizePersistAndKeepExactHistory() async throws {
        let document = try componentTextFixture()
        let page = document.websitePages[0], definition = document.componentDefinitions[0]
        let instance = page.nodes[1]
        let session = DocumentSession(document: document)
        func prepare(_ draft: String?) throws -> DocumentCommand {
            try textCommand(.setUsageNotes(definitionID: definition.id, openingSelection: [instance.id], draft: draft),
                document: session.document, pageID: page.id, selected: instance.id).command
        }
        func rootNote() -> NodeProperty? {
            session.document.componentDefinitions[0].nodes[0].insertionProperty(CanonicalComponentUsageNotes.key)
        }
        func schema19(_ document: CanonicalDocument) throws -> Data {
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(document)) as? [String: Any])
            json["schemaVersion"] = 19
            return try JSONSerialization.data(withJSONObject: json)
        }
        XCTAssertEqual(try DocumentSerializer.decode(schema19(document)), document)
        XCTAssertNil(CanonicalComponentUsageNotes.text(in: definition))
        XCTAssertFalse(String(decoding: try DocumentSerializer.encode(document), as: UTF8.self)
            .contains(CanonicalComponentUsageNotes.key))
        XCTAssertEqual(try prepare(" \t\r\n "), .batch([]))
        XCTAssertFalse(session.canUndo)
        try session.execute(prepare("  Cafe\u{301}\r\n\tDraft <b>literally</b>  "))
        let created = try XCTUnwrap(rootNote())
        let firstPages = session.document.pages
        XCTAssertEqual(created.origin, .authored)
        XCTAssertEqual(created.value, .string("Café\n\tDraft <b>literally</b>"))
        XCTAssertEqual(try prepare("Café\n\tDraft <b>literally</b>"), .batch([]))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(session.document.websitePages, document.websitePages)
        XCTAssertEqual(session.document.componentDefinitions[0].rootNodeIDs, definition.rootNodeIDs)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertThrowsError(try DocumentSerializer.decode(schema19(session.document))) {
            XCTAssertEqual($0 as? DocumentSerializationError, .malformedInput)
        }

        try session.execute(prepare("New note"))
        XCTAssertEqual(rootNote()?.id, created.id)
        let updated = session.document
        let store = ProjectPackageStore()
        let timestamp = ProjectTimestamp("2026-11-15T12:00:00.000Z")
        try session.execute(prepare(nil))
        XCTAssertNil(rootNote())
        XCTAssertEqual(try prepare(nil), .batch([]))
        XCTAssertEqual(session.historySnapshot().undoEntries.map(\.commandName), [.setProperty, .setProperty, .removeProperty])
        try session.undo(); XCTAssertEqual(session.document.pages, updated.pages)

        let history = PersistedHistoryStore()
        let snapshot = session.historySnapshot()
        let retained = try await history.encodeRetained(snapshot)
        let package = ProjectPackage(createdAt: timestamp, document: session.document,
            optionalMembers: [.init(path: PersistedHistoryStore.memberPath, data: retained)])
        let reopened = try await store.decode(store.encode(package))
        XCTAssertEqual(reopened.document, session.document)
        let loaded = try await history.load(from: reopened)
        XCTAssertEqual(loaded, .restored(snapshot))
        let reopenedSession = DocumentSession(document: reopened.document)
        try reopenedSession.installValidatedHistory(snapshot)
        try reopenedSession.redo()
        XCTAssertNil(CanonicalComponentUsageNotes.text(in: reopenedSession.document.componentDefinitions[0]))
        try reopenedSession.undo()
        XCTAssertEqual(reopenedSession.document.pages, updated.pages)
        try session.undo(); XCTAssertEqual(session.document.pages, firstPages)
        try session.undo(); XCTAssertEqual(session.document.pages, document.pages)
        try session.redo(); XCTAssertEqual(rootNote(), created)
        try session.redo(); XCTAssertEqual(session.document.pages, updated.pages)
        try session.redo(); XCTAssertNil(rootNote())
        XCTAssertEqual(session.document.pages, document.pages)
    }

    func testComponentUsageNotesRejectInvalidOwnershipAndStaleOrCancelledEdits() throws {
        let document = try componentTextFixture()
        let page = document.websitePages[0], definition = document.componentDefinitions[0]
        let instance = page.nodes[1], scene = CanvasViewportSceneID()
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: page.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [instance.id], availableNodeIDs: [instance.id],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let session = DocumentSession(document: document), registry = ComponentCommandRegistry()
        let edit = ComponentEdit.setUsageNotes(definitionID: definition.id, openingSelection: [instance.id], draft: "Notes")
        XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: document, context: context, cancelled: true)) {
            XCTAssertEqual($0 as? TransformError, .cancelled)
        }
        XCTAssertThrowsError(try registry.prepare(.setUsageNotes(definitionID: definition.id,
            openingSelection: [], draft: "Notes"), identity: identity, in: document, context: context)) {
            XCTAssertEqual($0 as? TransformError, .selectionMismatch)
        }
        var stale = document
        stale.revision += 1
        XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: stale, context: context)) {
            XCTAssertEqual($0 as? TransformError, .staleRevision)
        }
        stale = CanonicalDocument(pages: document.pages)
        XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: stale, context: context)) {
            XCTAssertEqual($0 as? TransformError, .staleDocument)
        }
        XCTAssertThrowsError(try registry.prepare(.setUsageNotes(definitionID: PageID(),
            openingSelection: [instance.id], draft: "Notes"), identity: identity, in: document, context: context))
        let maximum = String(repeating: "é", count: CanonicalComponentUsageNotes.maximumBytes / 2)
        XCTAssertEqual(try CanonicalComponentUsageNotes.normalized(maximum), maximum)
        for invalid in ["bad\u{0}draft", "bad\u{7}draft", String(repeating: "é", count: 2_049)] {
            XCTAssertThrowsError(try registry.prepare(.setUsageNotes(definitionID: definition.id,
                openingSelection: [instance.id], draft: invalid), identity: identity, in: document, context: context)) {
                XCTAssertEqual($0 as? ModelValidationError, .invalidComponentUsageNotes)
            }
        }
        let definitionIndex = try XCTUnwrap(document.pages.firstIndex { $0.id == definition.id })
        var invalid = document
        invalid.pages[definitionIndex].nodes[0].properties.append(.init(key: .init(rawValue: "locked"), value: .boolean(true)))
        XCTAssertThrowsError(try registry.prepare(edit, identity: identity, in: invalid, context: context))
        for (pageIndex, nodeIndex, key, value, origin) in [
            (definitionIndex, 1, CanonicalComponentUsageNotes.key, PropertyValue.string("Child note"), PropertyOrigin.authored),
            (0, 0, CanonicalComponentUsageNotes.key, .string("Page content"), .authored),
            (definitionIndex, 0, CanonicalComponentUsageNotes.key, .string(""), .authored),
            (definitionIndex, 0, CanonicalComponentUsageNotes.key, .string("Notes"), .defaulted),
            (definitionIndex, 0, CanonicalComponentUsageNotes.namespace + "v2.usageNotes", .string("Notes"), .authored),
            (definitionIndex, 0, CanonicalComponentUsageNotes.key, .string("Cafe\u{301}"), .authored)
        ] {
            invalid = document
            invalid.pages[pageIndex].nodes[nodeIndex].properties.append(
                .init(key: .init(rawValue: key), value: value, origin: origin))
            XCTAssertThrowsError(try DocumentSerializer.encode(invalid))
        }
        XCTAssertEqual(session.document, document)
        XCTAssertFalse(session.canUndo)
    }

    func testComponentUsageNotesDuplicateAndProjectNoVisitorContent() async throws {
        let document = try componentTextFixture()
        let page = document.websitePages[0], definition = document.componentDefinitions[0], instance = page.nodes[1]
        let session = DocumentSession(document: document)
        let note = "Author-only usage note <section> \(AssetID())"
        try session.execute(textCommand(.setUsageNotes(definitionID: definition.id,
            openingSelection: [instance.id], draft: note), document: document, pageID: page.id, selected: instance.id).command)
        let documented = session.document
        for breakpoint in ResponsiveBreakpoint.allCases {
            let before = try ComponentGraphResolver.resolvedPage(page, in: document, breakpoint: breakpoint)
            let after = try ComponentGraphResolver.resolvedPage(page, in: documented, breakpoint: breakpoint)
            XCTAssertEqual(after, before)
        }
        let viewport = try CanvasViewportState(worldOrigin: .init(x: 0, y: 0),
            viewportSize: .init(width: 1_000, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)), pixelRatio: .init(2))
        let worker = WorkspaceScenePreparationWorker(), surface = CanvasRenderSurfaceID()
        for activePageID in [page.id, definition.id] {
            let before = try await worker.prepare(.init(document: document, activePageID: activePageID,
                activeContainerID: nil, viewport: viewport, surfaceID: surface))
            let after = try await worker.prepare(.init(document: documented, activePageID: activePageID,
                activeContainerID: nil, viewport: viewport, surfaceID: surface))
            XCTAssertEqual(before.renderScene.objects, after.renderScene.objects)
        }
        let before = try MultiPageStaticBuildPlanner.plan(document: document)
        let after = try MultiPageStaticBuildPlanner.plan(document: documented)
        XCTAssertEqual(before.files, after.files)
        XCTAssertEqual(before.binaryFiles, after.binaryFiles)
        XCTAssertFalse(after.files.contains { $0.contents.contains(note) })

        let duplicate = try textCommand(.duplicateDefinition(definition.id), document: documented,
            pageID: page.id, selected: instance.id)
        try session.execute(duplicate.command)
        let copy = try XCTUnwrap(session.document.componentDefinitions.first { $0.id == duplicate.definitionID })
        XCTAssertNotEqual(copy.id, definition.id)
        XCTAssertEqual(copy.name, definition.name + " Copy 2")
        XCTAssertEqual(CanonicalComponentUsageNotes.text(in: copy), note)
        XCTAssertTrue(Set(copy.nodes.map(\.id)).isDisjoint(with: definition.nodes.map(\.id)))
        XCTAssertNotEqual(copy.nodes[0].insertionProperty(CanonicalComponentUsageNotes.key)?.id,
            documented.componentDefinitions[0].nodes[0].insertionProperty(CanonicalComponentUsageNotes.key)?.id)
        XCTAssertEqual(session.document.websitePages, document.websitePages)
        let duplicated = session.document.pages
        try session.undo(); XCTAssertEqual(session.document.pages, documented.pages)
        try session.redo(); XCTAssertEqual(session.document.pages, duplicated)
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

    // SF-0901-001/003/007, OD-034: instances may sit inside definitions. The
    // dependency graph reports direct dependencies, chain depth, users and
    // the fully expanded size; a link to a missing definition stays one
    // placeholder object and adds no dependency.
    func testComponentGraphAllowsNestedInstancesWithDepthUsersAndExpandedSize() throws {
        // Button: root + 2 parts. Card: root + 2 Buttons + 1 missing link + 1 part.
        // Section: root + Card + Button.
        let (document, ids) = nestedComponentDocument(["Button", "Card", "Section"],
            links: [[], [0, 0, -1], [1, 0]], extra: [2, 1, 0])
        let button = ids[0], card = ids[1], section = ids[2]
        try document.validate()
        let graph = CanonicalComponentGraph(document: document)
        XCTAssertNil(graph.cycle)
        XCTAssertNil(graph.violation)
        XCTAssertEqual(graph.order, ids)
        XCTAssertEqual(graph.dependencies[card], [button], "Unique, existing definitions only")
        XCTAssertEqual(graph.dependencies[section], [card, button], "Order of first appearance")
        XCTAssertEqual(graph.dependencies[button], [])
        XCTAssertEqual(graph.nestingDepth(of: button), 1)
        XCTAssertEqual(graph.nestingDepth(of: card), 2)
        XCTAssertEqual(graph.nestingDepth(of: section), 3)
        XCTAssertEqual(graph.deepestChain(from: section), [section, card, button])
        XCTAssertEqual(graph.expandedObjectCount(of: button), 3)
        // Card: root + part + missing placeholder (3) plus two Buttons (2 × 3).
        XCTAssertEqual(graph.expandedObjectCount(of: card), 9)
        // Section: root (1) + Card (9) + Button (3).
        XCTAssertEqual(graph.expandedObjectCount(of: section), 13)
        XCTAssertEqual(graph.dependents(of: button), [card, section])
        XCTAssertEqual(graph.dependents(of: section), [])
        XCTAssertTrue(graph.wouldCreateCycle(placing: section, inside: button))
        XCTAssertTrue(graph.wouldCreateCycle(placing: card, inside: card))
        XCTAssertFalse(graph.wouldCreateCycle(placing: button, inside: section))
        XCTAssertNil(graph.nestingDepth(of: PageID()))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)
    }

    // SF-0901-004, OD-034: a cycle of any length is invalid, found
    // deterministically and reported with its path; such a document neither
    // saves nor opens, and the graph stays safe to query while it is cyclic.
    func testComponentGraphRejectsCyclesWithTheirPathOnSaveAndOpen() throws {
        let (selfLoop, selfIDs) = nestedComponentDocument(["Badge"], links: [[0]])
        let selfGraph = CanonicalComponentGraph(document: selfLoop)
        XCTAssertEqual(selfGraph.cycle, [selfIDs[0], selfIDs[0]])
        let violation = try XCTUnwrap(selfGraph.violation)
        XCTAssertEqual(violation.kind, .cycle)
        XCTAssertEqual(violation.names, ["Badge", "Badge"])
        XCTAssertEqual(violation.category, "component-cycle")
        XCTAssertTrue(violation.localizedDescription.contains("Badge → Badge"))
        XCTAssertNil(selfGraph.nestingDepth(of: selfIDs[0]), "Nothing is measured while a cycle exists")
        XCTAssertThrowsError(try selfLoop.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .componentDependencyCycle)
        }
        XCTAssertThrowsError(try DocumentSerializer.encode(selfLoop)) {
            XCTAssertEqual($0 as? DocumentSerializationError, .invalidModel(.componentDependencyCycle))
        }

        let (loop, ids) = nestedComponentDocument(["Card", "Button", "Icon", "Unrelated"],
            links: [[1], [2], [0], [0]])
        let graph = CanonicalComponentGraph(document: loop)
        XCTAssertEqual(graph.cycle, [ids[0], ids[1], ids[2], ids[0]])
        XCTAssertEqual(graph.violation?.names, ["Card", "Button", "Icon", "Card"])
        XCTAssertTrue(graph.violation?.localizedDescription.contains("Card → Button → Icon → Card") == true)
        XCTAssertEqual(graph.dependents(of: ids[0]), Set(ids))
        XCTAssertFalse(graph.wouldCreateCycle(placing: ids[1], inside: ids[3]))
        XCTAssertEqual(CanonicalComponentGraph(document: loop), graph, "Deterministic")

        // A forged file whose definitions form a cycle is refused on open.
        let (acyclic, pair) = nestedComponentDocument(["Outer", "Inner"], links: [[1], [-1]])
        let bytes = try DocumentSerializer.encode(acyclic)
        let missing = try XCTUnwrap(acyclic.pages.first { $0.id == pair[1] }?.nodes
            .compactMap(CanonicalComponentReference.definitionID).first)
        let forged = Data(String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: missing.description, with: pair[0].description).utf8)
        XCTAssertThrowsError(try DocumentSerializer.decode(forged)) {
            XCTAssertEqual($0 as? DocumentSerializationError, .invalidModel(.componentDependencyCycle))
        }
        XCTAssertEqual(try DocumentSerializer.decode(bytes), acyclic)
    }

    // SF-0901-007, OD-034: chains are bounded at eight definitions and each
    // definition's expanded size at the shared 20,000-object budget. Counts
    // saturate rather than overflow on wide nesting.
    func testComponentGraphBoundsNestingDepthAndExpandedSizeWithSaturation() throws {
        let names = (1...9).map { "Level \($0)" }
        let (eight, eightIDs) = nestedComponentDocument(Array(names.prefix(8)),
            links: (0..<8).map { $0 < 7 ? [$0 + 1] : [] })
        try eight.validate()
        XCTAssertEqual(CanonicalComponentGraph(document: eight).nestingDepth(of: eightIDs[0]),
                       CanonicalComponentGraph.maximumNestingDepth)
        XCTAssertEqual(CanonicalComponentGraph.maximumNestingDepth, 8)
        let (nine, nineIDs) = nestedComponentDocument(names, links: (0..<9).map { $0 < 8 ? [$0 + 1] : [] })
        let deep = try XCTUnwrap(CanonicalComponentGraph(document: nine).violation)
        XCTAssertEqual(deep.kind, .tooDeep)
        XCTAssertEqual(deep.path, nineIDs, "The deepest chain, outermost first")
        XCTAssertEqual(deep.names, names)
        XCTAssertEqual(deep.category, "component-nesting-too-deep")
        XCTAssertTrue(deep.localizedDescription.contains("up to 8 levels"))
        XCTAssertThrowsError(try nine.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .componentNestingTooDeep)
        }

        // Part: root + 200 parts = 201 objects; 99 instances plus Grid's root = 19,900.
        let (fits, fitIDs) = nestedComponentDocument(["Part", "Grid"],
            links: [[], Array(repeating: 0, count: 99)], extra: [200, 0])
        try fits.validate()
        XCTAssertEqual(CanonicalComponentGraph(document: fits).expandedObjectCount(of: fitIDs[1]), 19_900)
        let (over, overIDs) = nestedComponentDocument(["Part", "Grid"],
            links: [[], Array(repeating: 0, count: 100)], extra: [200, 0])
        let large = try XCTUnwrap(CanonicalComponentGraph(document: over).violation)
        XCTAssertEqual(large.kind, .tooLarge)
        XCTAssertEqual(large.path, [overIDs[1]])
        XCTAssertEqual(large.objectCount, ResolvedGraphPolicy.maximumNodes + 1, "20,101 saturates")
        XCTAssertTrue(large.localizedDescription.contains("“Grid”"))
        XCTAssertTrue(large.localizedDescription.contains("more than 20,000 objects"), large.localizedDescription)
        XCTAssertEqual(large.category, "component-expansion-too-large")
        XCTAssertThrowsError(try over.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .componentExpansionTooLarge)
            XCTAssertTrue(($0 as? ModelValidationError)?.localizedDescription.contains("20,000") == true)
        }

        // Four levels of 40 instances would be 40⁴ objects; the count saturates.
        let wide = (0..<5).map { "Wide \($0)" }
        let (saturated, wideIDs) = nestedComponentDocument(wide,
            links: (0..<5).map { $0 < 4 ? Array(repeating: $0 + 1, count: 40) : [] })
        let graph = CanonicalComponentGraph(document: saturated)
        XCTAssertEqual(graph.expandedObjectCount(of: wideIDs[3]), 41)
        XCTAssertEqual(graph.expandedObjectCount(of: wideIDs[2]), 1_641)
        XCTAssertEqual(graph.expandedObjectCount(of: wideIDs[0]), ResolvedGraphPolicy.maximumNodes + 1)
        XCTAssertEqual(graph.violation?.kind, .tooLarge)
        XCTAssertEqual(graph.violation?.path, [wideIDs[0]], "First definition in document order")
    }

    // SF-0901-005, SF-0905-001/004, OD-034: an instance inside a definition
    // keeps values for its own definition's properties under the same
    // retention and protection rules as a page instance. Nesting needs
    // schema 24; a schema-23 project without nesting reopens unchanged.
    func testNestedInstancesKeepOwnValuesAndRequireSchemaTwentyFour() throws {
        let session = try exposedTextSession()
        var document = session.document
        let inner = try XCTUnwrap(document.componentDefinitions.first)
        let property = try XCTUnwrap(CanonicalComponentText.properties(in: inner).first)
        let outerID = PageID(), rootID = NodeID()
        let nested = DocumentNode(kind: .component, name: inner.name, parent: .node(rootID), properties: [
            NodeProperty(key: .init(rawValue: CanonicalComponentReference.key), value: .string(inner.id.description)),
            NodeProperty(key: .init(rawValue: CanonicalComponentText.overrideKey(property.id)),
                         value: .string("Buy"), origin: .authored),
        ])
        let root = DocumentNode(id: rootID, kind: .frame, name: "Card", parent: .page(outerID), childIDs: [nested.id])
        document.pages.append(DocumentPage(id: outerID, name: "Card", route: .init(rawValue: ""),
            role: .componentDefinition, provenance: .authored, rootNodeIDs: [rootID], nodes: [root, nested]))
        try document.validate()
        let outerIndex = try XCTUnwrap(document.pages.firstIndex { $0.id == outerID })
        let resolved = try CanonicalComponentOverrides.resolve(instance: nested, document: document)
        XCTAssertEqual(resolved.first { $0.property == .text(property.id) }?.effectiveValue, .text("Buy"))
        XCTAssertTrue(try CanonicalComponentOverrides.conflicts(instance: nested, document: document).isEmpty)
        XCTAssertEqual(CanonicalComponentGraph(document: document).dependencies[outerID], [inner.id])

        // A value for a property the inner definition does not expose stays a
        // resettable conflict, exactly as on a page instance.
        var unknown = document
        unknown.pages[outerIndex].nodes[1].properties.append(.init(
            key: .init(rawValue: CanonicalComponentText.overrideKey(ComponentTextPropertyID())),
            value: .string("Orphan"), origin: .authored))
        try unknown.validate()
        XCTAssertEqual(try CanonicalComponentOverrides.conflicts(instance: unknown.pages[outerIndex].nodes[1],
                                                                 document: unknown).count, 1)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(unknown)), unknown)
        var malformed = document
        malformed.pages[outerIndex].nodes[1].properties[1].value = .number(1)
        XCTAssertThrowsError(try malformed.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidComponentReference)
        }
        var misplaced = document
        misplaced.pages[outerIndex].nodes[0].properties.append(.init(
            key: .init(rawValue: CanonicalComponentText.overrideKey(property.id)), value: .string("Buy"), origin: .authored))
        XCTAssertThrowsError(try misplaced.validate(), "Only an instance owns instance values")

        // Retargeting the nested instance while it keeps its value is refused.
        var retargeted = document
        retargeted.pages[outerIndex].nodes[1].properties[0].value = .string(PageID().description)
        XCTAssertThrowsError(try CanonicalComponentText.validateTransition(from: document, to: retargeted)) {
            XCTAssertEqual($0 as? ModelValidationError, .componentTextIntentWouldBeLost)
        }
        XCTAssertNoThrow(try CanonicalComponentText.validateTransition(from: document, to: document))

        XCTAssertEqual(CanonicalComponentGraph.documentSchema, 24)
        XCTAssertGreaterThanOrEqual(DocumentSerializer.currentSchemaVersion, CanonicalComponentGraph.documentSchema)
        let encoded = try DocumentSerializer.encode(document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(envelope["schemaVersion"] as? Int, DocumentSerializer.currentSchemaVersion)
        for older in [23, 22, 14] {
            envelope["schemaVersion"] = older
            XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "\(older)")
        }
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(session.document)) as? [String: Any])
        legacy["schemaVersion"] = 23
        XCTAssertEqual(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)), session.document)
    }

    // SF-0901-002/004/005, SF-0308-003/004, OD-034: Insert Component places a
    // linked instance inside the definition being edited as one undoable
    // step; placing a component inside itself (directly or through others)
    // or past the nesting limit is refused with the chain, unchanged.
    func testInsertComponentInsideADefinitionIsUndoableAndRefusesCyclesAndDepth() throws {
        let (document, ids) = nestedComponentDocument(["Button", "Card"], links: [[], []])
        let button = ids[0], card = ids[1]
        let cardRoot = try XCTUnwrap(document.pages.first { $0.id == card }?.rootNodeIDs.first)
        let geometry = InsertionGeometry(origin: .init(x: 16, y: 140), size: .init(width: 120, height: 40))
        let session = DocumentSession(document: document)
        let prepared = try textCommand(.insert(definitionID: button, parentID: cardRoot, geometry: geometry),
            document: document, pageID: card, selected: cardRoot)
        try session.execute(prepared.command)
        let inserted = session.document
        let nested = try XCTUnwrap(inserted.pages.first { $0.id == card }?.nodes.first { $0.kind == .component })
        XCTAssertEqual(prepared.selectedNodeID, nested.id)
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: nested), button)
        XCTAssertEqual(nested.parent, .node(cardRoot))
        XCTAssertEqual(nested.insertionGeometry, geometry)
        XCTAssertEqual(CanonicalComponentGraph(document: inserted).dependencies[card], [button])
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(inserted)), inserted)
        try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, inserted.pages)

        let buttonPage = try XCTUnwrap(inserted.pages.first { $0.id == button })
        let loop = try XCTUnwrap(ComponentCommandRegistry.nestingViolation(inserting: card, into: buttonPage,
                                                                           document: inserted))
        XCTAssertEqual(loop.kind, .cycle)
        XCTAssertEqual(loop.names, ["Button", "Card", "Button"])
        XCTAssertThrowsError(try textCommand(.insert(definitionID: card, parentID: buttonPage.rootNodeIDs[0], geometry: geometry),
            document: inserted, pageID: button, selected: buttonPage.rootNodeIDs[0])) {
            XCTAssertTrue($0.localizedDescription.contains("inside itself (Button → Card → Button)"), $0.localizedDescription)
        }
        XCTAssertThrowsError(try textCommand(.insert(definitionID: card, parentID: cardRoot, geometry: geometry),
            document: inserted, pageID: card, selected: cardRoot)) {
            XCTAssertTrue($0.localizedDescription.contains("(Card → Card)"), $0.localizedDescription)
        }
        XCTAssertEqual(session.document.pages, inserted.pages, "Refusals change nothing")
        let homeID = inserted.pages[0].id, homeRoot = inserted.pages[0].rootNodeIDs[0]
        XCTAssertNil(ComponentCommandRegistry.nestingViolation(inserting: card, into: inserted.pages[0], document: inserted),
                     "Pages are not definitions and never nest")
        XCTAssertNoThrow(try textCommand(.insert(definitionID: card, parentID: homeRoot, geometry: geometry),
            document: inserted, pageID: homeID, selected: homeRoot))

        // Level 1 → … → Level 8 is the deepest allowed chain; Top above it would be 9.
        let names = (1...8).map { "Level \($0)" } + ["Top"]
        let (deep, deepIDs) = nestedComponentDocument(names, links: (0..<9).map { $0 < 7 ? [$0 + 1] : [] })
        try deep.validate()
        let top = try XCTUnwrap(deep.pages.first { $0.id == deepIDs[8] })
        XCTAssertThrowsError(try textCommand(.insert(definitionID: deepIDs[0], parentID: top.rootNodeIDs[0], geometry: geometry),
            document: deep, pageID: top.id, selected: top.rootNodeIDs[0])) {
            XCTAssertTrue($0.localizedDescription.contains("up to 8 levels"), $0.localizedDescription)
            XCTAssertTrue($0.localizedDescription.contains("Top → Level 1"), $0.localizedDescription)
        }
        XCTAssertNil(ComponentCommandRegistry.nestingViolation(inserting: deepIDs[1], into: top, document: deep),
                     "Level 2 → … → Level 8 under Top is exactly eight")
    }

    // SF-0901-002/005, SF-0905-005, OD-034: Create Component from a selection
    // that contains a linked instance keeps it linked inside the new
    // definition, with the value authored on it, as one undoable step.
    func testCreateComponentFromSelectionContainingAnInstanceKeepsItLinkedWithItsValue() throws {
        var document = try exposedTextSession().document
        let inner = try XCTUnwrap(document.componentDefinitions.first)
        let property = try XCTUnwrap(CanonicalComponentText.properties(in: inner).first)
        let rootID = document.pages[0].rootNodeIDs[0], frameID = NodeID()
        func geometry(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            }
        }
        let nested = DocumentNode(kind: .component, name: inner.name, parent: .node(frameID), properties: geometry(16, 140, 120, 40) + [
            NodeProperty(key: .init(rawValue: CanonicalComponentReference.key), value: .string(inner.id.description)),
            NodeProperty(key: .init(rawValue: CanonicalComponentText.overrideKey(property.id)), value: .string("Buy"), origin: .authored),
        ])
        let frame = DocumentNode(id: frameID, kind: .frame, name: "Card", parent: .node(rootID),
                                 childIDs: [nested.id], properties: geometry(400, 300, 320, 200))
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == rootID })
        document.pages[0].nodes[rootIndex].childIDs.append(frameID)
        document.pages[0].nodes += [frame, nested]
        try document.validate()
        XCTAssertEqual(try ComponentCommandRegistry.creationSourceIDs(frameID, page: document.pages[0], document: document),
                       [frameID, nested.id])

        let session = DocumentSession(document: document)
        // The fixture's own definition is named "Card", so the new one is "Promo".
        try session.execute(textCommand(.createNamed(frameID, name: "Promo"), document: document,
            pageID: document.pages[0].id, selected: frameID).command)
        let created = session.document
        let card = try XCTUnwrap(created.componentDefinitions.first { $0.name == "Promo" })
        let copied = try XCTUnwrap(card.nodes.first { $0.kind == .component })
        XCTAssertNotEqual(copied.id, nested.id, "The new definition owns new identities")
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: copied), inner.id)
        XCTAssertEqual(CanonicalComponentText.overrides(on: copied)[property.id], "Buy")
        let instance = try XCTUnwrap(created.pages[0].nodes.first { $0.id == frameID })
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: instance), card.id)
        XCTAssertFalse(created.pages[0].nodes.contains { $0.id == nested.id })
        XCTAssertEqual(CanonicalComponentGraph(document: created).dependencies[card.id], [inner.id])
        let resolved = try ComponentGraphResolver.resolvedPage(created.pages[0], in: created, breakpoint: .desktop)
        XCTAssertTrue(resolved.nodes.contains { $0.insertionStringProperty("content.text") == "Buy" })
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(created)), created)
        try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, created.pages)
    }

    // SF-0901-002/005, SF-0905-002/003/005, OD-034: inside a definition, an
    // inner instance takes, resets and keeps its own values; Duplicate keeps
    // them; Detach is one level (the inner content becomes ordinary objects of
    // the definition); each step is one exact undo entry.
    func testInnerInstanceValuesDuplicateAndDetachInsideADefinitionAreOneLevelAndUndoable() throws {
        var document = try exposedTextSession().document
        let inner = try XCTUnwrap(document.componentDefinitions.first)
        let property = try XCTUnwrap(CanonicalComponentText.properties(in: inner).first)
        let cardID = PageID(), cardRoot = NodeID()
        func geometry(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", x), ("layout.y", y), ("layout.width", width), ("layout.height", height)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            }
        }
        let nested = DocumentNode(kind: .component, name: inner.name, parent: .node(cardRoot), properties: geometry(16, 140, 120, 40) + [
            NodeProperty(key: .init(rawValue: CanonicalComponentReference.key), value: .string(inner.id.description)),
        ])
        let root = DocumentNode(id: cardRoot, kind: .frame, name: "Promo", parent: .page(cardID),
                                childIDs: [nested.id], properties: geometry(0, 0, 320, 200))
        document.pages.append(DocumentPage(id: cardID, name: "Promo", route: .init(rawValue: ""),
            role: .componentDefinition, provenance: .authored, rootNodeIDs: [cardRoot], nodes: [root, nested]))
        try document.validate()
        let session = DocumentSession(document: document)
        func apply(_ edit: ComponentEdit, on pageID: PageID, selected: NodeID) throws {
            try session.execute(textCommand(edit, document: session.document, pageID: pageID, selected: selected).command)
        }
        func innerNode() throws -> DocumentNode {
            try XCTUnwrap(session.document.pages.first { $0.id == cardID }?.nodes.first { $0.id == nested.id })
        }
        try apply(.setTextOverride(instanceID: nested.id, propertyID: property.id, value: "Buy"), on: cardID, selected: nested.id)
        XCTAssertEqual(CanonicalComponentText.overrides(on: try innerNode())[property.id], "Buy")
        let valued = session.document
        try apply(.resetTextOverride(instanceID: nested.id, propertyID: property.id), on: cardID, selected: nested.id)
        XCTAssertNil(CanonicalComponentText.overrides(on: try innerNode())[property.id])
        try session.undo()
        XCTAssertEqual(session.document.pages, valued.pages)

        let homeID = session.document.pages[0].id, homeRoot = session.document.pages[0].rootNodeIDs[0]
        try apply(.duplicateDefinition(cardID), on: homeID, selected: homeRoot)
        let copy = try XCTUnwrap(session.document.componentDefinitions.first { $0.name == "Promo Copy 2" })
        let copiedInner = try XCTUnwrap(copy.nodes.first { $0.kind == .component })
        XCTAssertEqual(CanonicalComponentReference.definitionID(for: copiedInner), inner.id)
        XCTAssertEqual(CanonicalComponentText.overrides(on: copiedInner)[property.id], "Buy",
                       "Duplicate keeps the inner instance's value and its property identity")
        try session.undo()
        XCTAssertEqual(session.document.pages, valued.pages)

        try apply(.detach(nested.id), on: cardID, selected: nested.id)
        let detached = try XCTUnwrap(session.document.pages.first { $0.id == cardID })
        XCTAssertFalse(detached.nodes.contains { $0.kind == .component })
        let detachedRoot = try XCTUnwrap(detached.nodes.first { $0.id == nested.id }, "Detach keeps the root identity")
        XCTAssertEqual(detachedRoot.parent, .node(cardRoot))
        XCTAssertTrue(detached.nodes.contains { $0.insertionStringProperty("content.text") == "Buy" })
        XCTAssertEqual(CanonicalComponentGraph(document: session.document).dependencies[cardID], [])
        try session.document.validate()
        try session.undo()
        XCTAssertEqual(session.document.pages, valued.pages)
    }

    // SF-0901-002/004, SF-0902-004, OD-034: renaming a definition renames its
    // instances inside other definitions; deleting a definition used only
    // inside another one is refused unless uses are detached, and Detach Uses
    // and Delete inlines that use in the same transaction.
    func testRenameAndDetachUsesAndDeleteIncludeUsesInsideOtherDefinitions() throws {
        let (document, ids) = nestedComponentDocument(["Button", "Card"], links: [[], [0]])
        let button = ids[0], card = ids[1]
        let homeID = document.pages[0].id, homeRoot = document.pages[0].rootNodeIDs[0]
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.rename(definitionID: button, name: "Pill"), document: document,
            pageID: homeID, selected: homeRoot).command)
        let renamed = session.document
        let innerInstance = try XCTUnwrap(renamed.pages.first { $0.id == card }?.nodes.first { $0.kind == .component })
        XCTAssertEqual(innerInstance.name, "Pill")
        XCTAssertEqual(renamed.componentDefinitions.first { $0.id == button }?.name, "Pill")

        XCTAssertThrowsError(try textCommand(.delete(definitionID: button, detachUses: false), document: renamed,
            pageID: homeID, selected: homeRoot)) {
            XCTAssertTrue($0.localizedDescription.contains("in use"), $0.localizedDescription)
        }
        try session.execute(textCommand(.delete(definitionID: button, detachUses: true), document: renamed,
            pageID: homeID, selected: homeRoot).command)
        let deleted = session.document
        XCTAssertFalse(deleted.pages.contains { $0.id == button })
        let cardPage = try XCTUnwrap(deleted.pages.first { $0.id == card })
        XCTAssertFalse(cardPage.nodes.contains { $0.kind == .component })
        XCTAssertEqual(cardPage.nodes.first { $0.id == innerInstance.id }?.kind, .frame,
                       "The use inside Card is now Card's own Frame, same identity")
        XCTAssertEqual(CanonicalComponentGraph(document: deleted).dependencies[card], [])
        try deleted.validate()
        try session.undo()
        XCTAssertEqual(session.document.pages, renamed.pages)
    }

    // SF-0901-004/007, OD-034: the one-pass answer used by the Component menu
    // and Components panel equals a full graph rebuild for every target and
    // candidate, on many seeded random graphs that reach the cycle, depth and
    // size limits, so a disabled Insert always matches the command's refusal.
    func testOnePassInsertionAnswersMatchTheFullRebuildForEveryPairOnRandomGraphs() throws {
        var seed: UInt64 = 0x0D03_4EED
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        var graphs = 0, refused: [ComponentGraphViolation.Kind: Int] = [:], allowed = 0
        while graphs < 40 {
            let count = 4 + next(7)
            let links = (0..<count).map { index -> [Int] in
                var result: [Int] = []
                if index + 1 < count, next(10) < 8 { result.append(index + 1) }
                for target in (index + 1)..<max(index + 1, count) where next(10) < 2 {
                    result += Array(repeating: target, count: 1 + next(7))
                }
                if next(12) == 0 { result.append(-1) }
                return result
            }
            // Seed and shape chosen so the 40 graphs refuse by cycle (757
            // pairs), depth (9) and size (20) and allow 859, checked offline.
            let extra = (0..<count).map { _ in next(4) == 0 ? 200 + next(300) : next(8) }
            let (document, ids) = nestedComponentDocument((0..<count).map { "D\($0)" }, links: links, extra: extra)
            let graph = CanonicalComponentGraph(document: document)
            guard graph.violation == nil else { continue }
            graphs += 1
            let definitions = document.componentDefinitions
            for target in ids {
                let fast = graph.insertionViolations(into: target, definitions: definitions)
                for candidate in ids {
                    let full = CanonicalComponentGraph.violation(adding: [candidate], into: target, definitions: definitions)
                    XCTAssertEqual(fast[candidate], full, "graph \(graphs): D\(ids.firstIndex(of: candidate)!) into D\(ids.firstIndex(of: target)!)")
                    if let full { refused[full.kind, default: 0] += 1 } else { allowed += 1 }
                }
            }
            XCTAssertTrue(graph.insertionViolations(into: PageID(), definitions: definitions).isEmpty,
                          "An unknown target (or a page) never nests")
        }
        XCTAssertGreaterThan(allowed, 0)
        for kind in [ComponentGraphViolation.Kind.cycle, .tooDeep, .tooLarge] {
            XCTAssertGreaterThan(refused[kind, default: 0], 0, "The seeded graphs exercise \(kind)")
        }
    }

    /// OD-033 fixture. Button definition: root Frame (0, 0, 200 × 48) with a
    /// Text "Label" (12, 12, 120 × 24, "Buy") and a radius of 8. Axes Size
    /// (Small default, Large) and Tone (Primary default, Secondary). One copy
    /// on Home at (40, 60), choosing nothing.
    private struct VariantFixture {
        var document: CanonicalDocument
        let definitionID: PageID, rootID: NodeID, labelID: NodeID, instanceID: NodeID
        let size: ComponentVariantAxisID, small: ComponentVariantValueID, large: ComponentVariantValueID
        let tone: ComponentVariantAxisID, primary: ComponentVariantValueID, secondary: ComponentVariantValueID
    }

    private func variantFixture() throws -> VariantFixture {
        func number(_ key: String, _ value: Double) -> NodeProperty { .init(key: .init(rawValue: key), value: .number(value)) }
        func string(_ key: String, _ value: String) -> NodeProperty { .init(key: .init(rawValue: key), value: .string(value)) }
        func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [number("layout.x", x), number("layout.y", y), number("layout.width", width), number("layout.height", height)]
        }
        typealias V = CanonicalComponentVariants
        var document = BlankProjectDefaults.document()
        let definitionID = PageID(), rootID = NodeID(), labelID = NodeID(), instanceID = NodeID()
        let size = ComponentVariantAxisID(), small = ComponentVariantValueID(), large = ComponentVariantValueID()
        let tone = ComponentVariantAxisID(), primary = ComponentVariantValueID(), secondary = ComponentVariantValueID()
        let metadata = [
            string(V.axesKey, "\(size),\(tone)"),
            string(V.axisKey(size, "name"), "Size"), string(V.axisKey(size, "values"), "\(small),\(large)"),
            string(V.axisKey(size, "default"), small.description),
            string(V.valueNameKey(small), "Small"), string(V.valueNameKey(large), "Large"),
            string(V.axisKey(tone, "name"), "Tone"), string(V.axisKey(tone, "values"), "\(primary),\(secondary)"),
            string(V.axisKey(tone, "default"), primary.description),
            string(V.valueNameKey(primary), "Primary"), string(V.valueNameKey(secondary), "Secondary"),
        ]
        document.pages.append(DocumentPage(id: definitionID, name: "Button", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [rootID], nodes: [
                DocumentNode(id: rootID, kind: .frame, name: "Button", parent: .page(definitionID), childIDs: [labelID],
                             properties: frame(0, 0, 200, 48) + [number(DesignBoxStyleCommandRegistry.namespace + "radius.uniform", 8)] + metadata),
                DocumentNode(id: labelID, kind: .text, name: "Label", parent: .node(rootID),
                             properties: frame(12, 12, 120, 24) + [string("content.text", "Buy")]),
            ]))
        let pageRoot = document.pages[0].rootNodeIDs[0]
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
        document.pages[0].nodes[rootIndex].childIDs.append(instanceID)
        document.pages[0].nodes.append(DocumentNode(id: instanceID, kind: .component, name: "Button", parent: .node(pageRoot),
            properties: frame(40, 60, 200, 48) + [string(CanonicalComponentReference.key, definitionID.description)]))
        try document.validate()
        return .init(document: document, definitionID: definitionID, rootID: rootID, labelID: labelID, instanceID: instanceID,
                     size: size, small: small, large: large, tone: tone, primary: primary, secondary: secondary)
    }

    /// Adds (or replaces) one variant property on a definition node.
    private func setVariantProperty(_ key: String, _ value: PropertyValue, on nodeID: NodeID, definition: PageID,
                                    in document: inout CanonicalDocument) throws {
        let page = try XCTUnwrap(document.pages.firstIndex { $0.id == definition })
        let node = try XCTUnwrap(document.pages[page].nodes.firstIndex { $0.id == nodeID })
        document.pages[page].nodes[node].properties.removeAll { $0.key.rawValue == key }
        document.pages[page].nodes[node].properties.append(.init(key: .init(rawValue: key), value: value))
    }

    private func chooseVariant(_ value: String, for axisKey: String, on instanceID: NodeID,
                               in document: inout CanonicalDocument) throws {
        let node = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == instanceID })
        document.pages[0].nodes[node].properties.removeAll { $0.key.rawValue == axisKey }
        document.pages[0].nodes[node].properties.append(.init(key: .init(rawValue: axisKey), value: .string(value)))
    }

    // SF-0904-001/004, OD-033: variant axes, values and allowed combinations
    // live on the definition root in one strict canonical spelling, within
    // fixed limits; overrides only for supported settings and existing
    // targets; copies' choices are well formed but may name a value that no
    // longer exists. Every malformed encoding is rejected.
    func testComponentVariantsUseOneStrictCanonicalEncodingWithinLimits() throws {
        let fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        let definition = try XCTUnwrap(fixture.document.componentDefinitions.first)
        let set = try XCTUnwrap(V.variantSet(in: definition))
        XCTAssertEqual(set.axes.map(\.name), ["Size", "Tone"])
        XCTAssertEqual(set.axes.map { $0.values.map(\.name) }, [["Small", "Large"], ["Primary", "Secondary"]])
        XCTAssertEqual(set.defaultCombination, CanonicalVariantCombination([fixture.small, fixture.primary]))
        XCTAssertEqual(set.combinations.map(\.valueIDs), [[fixture.small, fixture.primary], [fixture.small, fixture.secondary],
                                                          [fixture.large, fixture.primary], [fixture.large, fixture.secondary]])
        XCTAssertEqual(set.name(of: CanonicalVariantCombination([fixture.large, fixture.secondary])), "Large · Secondary")
        XCTAssertEqual(set.targets(for: set.defaultCombination),
                       [.value(fixture.small), .value(fixture.primary), .combination(set.defaultCombination)])
        XCTAssertNil(try V.variantSet(in: try plainComponentDefinition()), "A definition without variants has none")
        XCTAssertTrue(V.isVariantCapable("style.box.v1.radius.uniform"))
        XCTAssertTrue(V.isVariantCapable("content.text"))
        for excluded in ["component.exposedText.v1.id", "interaction.link.v1.kind", "layout.sizing.v1.widthMode",
                         "responsive.geometry.v1.desktop.x", LocalColorTokenBinding.prefix + "fill", "style.reusable.v1.applied",
                         CanonicalImageFill.assetKey] {
            XCTAssertFalse(V.isVariantCapable(excluded), excluded)
        }

        func refuses(_ label: String, _ change: (inout CanonicalDocument) throws -> Void) throws {
            var broken = fixture.document
            try change(&broken)
            XCTAssertThrowsError(try broken.validate(), label) {
                XCTAssertEqual($0 as? ModelValidationError, .invalidComponentVariants, label)
            }
        }
        func setRoot(_ key: String, _ value: PropertyValue) -> (inout CanonicalDocument) throws -> Void {
            { document in try self.setVariantProperty(key, value, on: fixture.rootID, definition: fixture.definitionID, in: &document) }
        }
        try refuses("one value", setRoot(V.axisKey(fixture.size, "values"), .string(fixture.small.description)))
        try refuses("default outside the axis", setRoot(V.axisKey(fixture.size, "default"), .string(fixture.primary.description)))
        try refuses("duplicate value name", setRoot(V.valueNameKey(fixture.large), .string("small")))
        try refuses("duplicate axis name", setRoot(V.axisKey(fixture.tone, "name"), .string("Size")))
        try refuses("non-canonical identifier", setRoot(V.axesKey, .string("\(fixture.size.description.uppercased()),\(fixture.tone)")))
        try refuses("unknown metadata field", setRoot(V.axisKey(fixture.size, "color"), .string("red")))
        try refuses("wrong value type", setRoot(V.axisKey(fixture.size, "name"), .number(1)))
        try refuses("five axes") { document in
            let extra = (0..<4).map { _ in ComponentVariantAxisID() }
            try setRoot(V.axesKey, .string(([fixture.size] + extra).map(\.description).joined(separator: ",")))(&document)
            for (offset, axis) in extra.enumerated() {
                let a = ComponentVariantValueID(), b = ComponentVariantValueID()
                for (key, value) in [(V.axisKey(axis, "name"), "Axis \(offset)"), (V.axisKey(axis, "values"), "\(a),\(b)"),
                                     (V.axisKey(axis, "default"), a.description), (V.valueNameKey(a), "A"), (V.valueNameKey(b), "B")] {
                    try setRoot(key, .string(value))(&document)
                }
            }
        }
        let allowedKey = CanonicalVariantCombination([fixture.large, fixture.secondary]).key
        let otherKey = CanonicalVariantCombination([fixture.large, fixture.primary]).key
        var restricted = fixture.document
        try setRoot(V.disallowedKey, .string(allowedKey))(&restricted)
        XCTAssertNoThrow(try restricted.validate())
        XCTAssertEqual(try V.variantSet(in: try XCTUnwrap(restricted.componentDefinitions.first))?.disallowed, [allowedKey])
        try refuses("default combination disallowed", setRoot(V.disallowedKey, .string(set.defaultCombination.key)))
        try refuses("unsorted list", setRoot(V.disallowedKey, .string([allowedKey, otherKey].sorted().reversed().joined(separator: ","))))
        try refuses("not a combination", setRoot(V.disallowedKey, .string(fixture.large.description)))
        try refuses("empty list", setRoot(V.disallowedKey, .string("")))
        try refuses("metadata on a child") { document in
            try self.setVariantProperty(V.axesKey, .string(fixture.size.description), on: fixture.labelID,
                                        definition: fixture.definitionID, in: &document)
        }
        try refuses("unsupported override") { document in
            try self.setVariantProperty(V.overrideKey(.value(fixture.large), "interaction.link.v1.kind"), .string("none"),
                                        on: fixture.labelID, definition: fixture.definitionID, in: &document)
        }
        try refuses("override for an unknown value") { document in
            try self.setVariantProperty(V.overrideKey(.value(ComponentVariantValueID()), "content.text"), .string("x"),
                                        on: fixture.labelID, definition: fixture.definitionID, in: &document)
        }
        try refuses("override for a disallowed combination") { document in
            try setRoot(V.disallowedKey, .string(allowedKey))(&document)
            try self.setVariantProperty(V.overrideKey(.combination(.init([fixture.large, fixture.secondary])), "content.text"),
                                        .string("x"), on: fixture.labelID, definition: fixture.definitionID, in: &document)
        }
        try refuses("unset marker that is not true") { document in
            try self.setVariantProperty(V.unsetKey(.value(fixture.large), "content.text"), .boolean(false),
                                        on: fixture.labelID, definition: fixture.definitionID, in: &document)
        }
        try refuses("override and unset for one key") { document in
            for key in [V.overrideKey(.value(fixture.large), "content.text"), V.unsetKey(.value(fixture.large), "content.text")] {
                try self.setVariantProperty(key, key.contains(".unset.") ? .boolean(true) : .string("x"),
                                            on: fixture.labelID, definition: fixture.definitionID, in: &document)
            }
        }
        try refuses("override without variants") { document in
            let page = try XCTUnwrap(document.pages.firstIndex { $0.id == fixture.definitionID })
            document.pages[page].nodes[0].properties.removeAll { V.isMetadataKey($0.key.rawValue) }
            try self.setVariantProperty(V.overrideKey(.value(fixture.large), "content.text"), .string("x"),
                                        on: fixture.labelID, definition: fixture.definitionID, in: &document)
        }
        try refuses("variant data on a page") { document in
            let page = document.pages[0], index = try XCTUnwrap(page.nodes.firstIndex { $0.id == fixture.instanceID })
            document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: V.overrideKey(.value(fixture.large), "layout.x")),
                                                                   value: .number(1)))
        }
        try refuses("non-canonical choice") { document in
            try self.chooseVariant(fixture.large.description.uppercased(), for: V.choiceKey(fixture.size),
                                   on: fixture.instanceID, in: &document)
        }
        var retained = fixture.document
        try chooseVariant(ComponentVariantValueID().description, for: V.choiceKey(ComponentVariantAxisID()),
                          on: fixture.instanceID, in: &retained)
        XCTAssertNoThrow(try retained.validate(), "A choice for a removed axis is retained intent, not corruption")
    }

    // SF-0904-003/004, OD-033: one precedence rule: base < each chosen axis
    // value in axis order < the exact combination. An unset marker removes a
    // base value in that variant. Overridden properties keep their identity.
    // Unavailable choices keep the stored intent, show the default and are
    // reported; a combination that is not allowed shows the default variant.
    // Canvas expansion uses the same rule.
    func testComponentVariantResolutionFollowsOnePrecedenceRuleAndKeepsUnavailableChoices() throws {
        var fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        var document = fixture.document
        let both = CanonicalVariantCombination([fixture.large, fixture.secondary])
        let radiusKey = DesignBoxStyleCommandRegistry.namespace + "radius.uniform"
        try setVariantProperty(V.overrideKey(.value(fixture.large), "layout.width"), .number(280), on: fixture.rootID,
                               definition: fixture.definitionID, in: &document)
        try setVariantProperty(V.overrideKey(.value(fixture.large), "content.text"), .string("Buy now"), on: fixture.labelID,
                               definition: fixture.definitionID, in: &document)
        try setVariantProperty(V.overrideKey(.value(fixture.secondary), "style.opacity"), .number(0.5), on: fixture.rootID,
                               definition: fixture.definitionID, in: &document)
        try setVariantProperty(V.unsetKey(.value(fixture.secondary), radiusKey), .boolean(true), on: fixture.rootID,
                               definition: fixture.definitionID, in: &document)
        try setVariantProperty(V.overrideKey(.combination(both), "content.text"), .string("Buy now, save"), on: fixture.labelID,
                               definition: fixture.definitionID, in: &document)
        try document.validate()
        fixture.document = document
        let definition = try XCTUnwrap(document.componentDefinitions.first)
        let set = try XCTUnwrap(V.variantSet(in: definition))
        func instance(_ choices: [(ComponentVariantAxisID, String)]) throws -> DocumentNode {
            var copy = try XCTUnwrap(document.pages[0].nodes.first { $0.id == fixture.instanceID })
            for (axis, value) in choices {
                copy.properties.append(.init(key: .init(rawValue: V.choiceKey(axis)), value: .string(value)))
            }
            return copy
        }
        func shown(_ node: DocumentNode) -> (width: Double?, text: String?, opacity: Double?, radius: Double?) {
            let page = V.resolvedDefinition(definition, for: node)
            let root = page.nodes.first { $0.id == fixture.rootID }, label = page.nodes.first { $0.id == fixture.labelID }
            return (root?.insertionNumberProperty("layout.width"), label?.insertionStringProperty("content.text"),
                    root?.insertionNumberProperty("style.opacity"), root?.insertionNumberProperty(radiusKey))
        }
        let base = try instance([])
        XCTAssertEqual(shown(base).width, 200); XCTAssertEqual(shown(base).text, "Buy")
        XCTAssertNil(shown(base).opacity); XCTAssertEqual(shown(base).radius, 8)
        let large = try instance([(fixture.size, fixture.large.description)])
        XCTAssertEqual(shown(large).width, 280); XCTAssertEqual(shown(large).text, "Buy now"); XCTAssertEqual(shown(large).radius, 8)
        let largeSecondary = try instance([(fixture.size, fixture.large.description), (fixture.tone, fixture.secondary.description)])
        XCTAssertEqual(shown(largeSecondary).text, "Buy now, save", "The exact combination wins over a single value")
        XCTAssertEqual(shown(largeSecondary).opacity, 0.5)
        XCTAssertNil(shown(largeSecondary).radius, "Secondary removes the base radius")
        let resolved = V.resolvedDefinition(definition, for: largeSecondary)
        XCTAssertFalse(resolved.nodes.flatMap(\.properties).contains { $0.key.rawValue.hasPrefix(V.namespace) },
                       "Variant data never reaches what a copy draws")
        let baseWidth = try XCTUnwrap(definition.nodes[0].insertionProperty("layout.width"))
        XCTAssertEqual(resolved.nodes[0].insertionProperty("layout.width")?.id, baseWidth.id, "Overridden properties keep their identity")
        let opacityOverride = try XCTUnwrap(definition.nodes[0].insertionProperty(V.overrideKey(.value(fixture.secondary), "style.opacity")))
        XCTAssertEqual(resolved.nodes[0].insertionProperty("style.opacity")?.id, opacityOverride.id)

        let chosen = V.resolution(for: largeSecondary, set: set)
        XCTAssertEqual(chosen.combination, both)
        XCTAssertEqual(chosen.sources, [fixture.size: .authored, fixture.tone: .authored])
        XCTAssertTrue(chosen.findings.isEmpty)
        XCTAssertEqual(V.resolution(for: base, set: set).sources, [fixture.size: .defaultValue, fixture.tone: .defaultValue])

        let removedValue = ComponentVariantValueID().description, removedAxis = ComponentVariantAxisID()
        let unavailable = try instance([(fixture.size, removedValue), (fixture.tone, fixture.secondary.description)])
        let repaired = V.resolution(for: unavailable, set: set)
        XCTAssertEqual(repaired.combination, CanonicalVariantCombination([fixture.small, fixture.secondary]))
        XCTAssertEqual(repaired.sources[fixture.size], .fallback)
        XCTAssertEqual(repaired.findings, [.unknownValue(axis: fixture.size, value: removedValue)])
        XCTAssertEqual(repaired.findings.first?.code, "variant-value-unavailable")
        let orphan = V.resolution(for: try instance([(removedAxis, fixture.large.description)]), set: set)
        XCTAssertEqual(orphan.findings, [.unknownAxis(axis: removedAxis.description)])
        XCTAssertEqual(orphan.combination, set.defaultCombination)

        // Not allowed: the copy keeps its choices and shows the default variant.
        var restricted = document
        let page = try XCTUnwrap(restricted.pages.firstIndex { $0.id == fixture.definitionID })
        let label = try XCTUnwrap(restricted.pages[page].nodes.firstIndex { $0.id == fixture.labelID })
        restricted.pages[page].nodes[label].properties.removeAll { $0.key.rawValue == V.overrideKey(.combination(both), "content.text") }
        try setVariantProperty(V.disallowedKey, .string(both.key), on: fixture.rootID, definition: fixture.definitionID, in: &restricted)
        try restricted.validate()
        let restrictedSet = try XCTUnwrap(V.variantSet(in: try XCTUnwrap(restricted.componentDefinitions.first)))
        let blocked = V.resolution(for: largeSecondary, set: restrictedSet)
        XCTAssertEqual(blocked.combination, restrictedSet.defaultCombination)
        XCTAssertEqual(blocked.findings, [.disallowedCombination(both)])
        XCTAssertEqual(Set(blocked.sources.values), [.fallback])

        // The canvas and export expansion draw the copy's variant.
        var chosenDocument = document
        try chooseVariant(fixture.large.description, for: V.choiceKey(fixture.size), on: fixture.instanceID, in: &chosenDocument)
        try chooseVariant(fixture.secondary.description, for: V.choiceKey(fixture.tone), on: fixture.instanceID, in: &chosenDocument)
        try chosenDocument.validate()
        let drawn = try ComponentGraphResolver.resolvedPage(chosenDocument.pages[0], in: chosenDocument, breakpoint: .desktop)
        let copy = try XCTUnwrap(chosenDocument.pages[0].nodes.first { $0.id == fixture.instanceID })
        let drawnLabel = try XCTUnwrap(drawn.nodes.first { $0.id == ComponentGraphResolver.derivedID(fixture.labelID, in: copy) })
        XCTAssertEqual(drawnLabel.insertionStringProperty("content.text"), "Buy now, save")
        XCTAssertEqual(drawn.nodes.first { $0.id == fixture.instanceID }?.insertionNumberProperty("style.opacity"), 0.5)
    }

    // SF-0904-001/004/005, OD-033: variants and copies' choices need document
    // schema 26; projects without them reopen unchanged from schema 25.
    func testComponentVariantsRoundTripAndRequireSchemaTwentySix() throws {
        let fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        var document = fixture.document
        try setVariantProperty(V.overrideKey(.value(fixture.large), "content.text"), .string("Buy now"), on: fixture.labelID,
                               definition: fixture.definitionID, in: &document)
        try chooseVariant(fixture.large.description, for: V.choiceKey(fixture.size), on: fixture.instanceID, in: &document)
        try document.validate()
        XCTAssertEqual(V.documentSchema, 26)
        // Later schemas keep reading variants (schema 27 adds container queries, SF-0605).
        XCTAssertGreaterThanOrEqual(DocumentSerializer.currentSchemaVersion, V.documentSchema)
        let encoded = try DocumentSerializer.encode(document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(envelope["schemaVersion"] as? Int, DocumentSerializer.currentSchemaVersion)
        for older in [25, 24, 18] {
            envelope["schemaVersion"] = older
            XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "\(older)")
        }
        // A choice alone (the definition may have lost its variants) is still schema-26 data.
        var choiceOnly = try variantFixture().document
        let definitionIndex = try XCTUnwrap(choiceOnly.pages.firstIndex { $0.role == .componentDefinition })
        choiceOnly.pages[definitionIndex].nodes[0].properties.removeAll { V.isMetadataKey($0.key.rawValue) }
        let choiceInstance = try XCTUnwrap(choiceOnly.pages[0].nodes.last?.id)
        try chooseVariant(ComponentVariantValueID().description, for: V.choiceKey(ComponentVariantAxisID()),
                          on: choiceInstance, in: &choiceOnly)
        try choiceOnly.validate()
        var choiceEnvelope = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(choiceOnly)) as? [String: Any])
        choiceEnvelope["schemaVersion"] = 25
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: choiceEnvelope)))
        var plain = try variantFixture().document
        let plainIndex = try XCTUnwrap(plain.pages.firstIndex { $0.role == .componentDefinition })
        plain.pages[plainIndex].nodes[0].properties.removeAll { V.isMetadataKey($0.key.rawValue) }
        try plain.validate()
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(plain)) as? [String: Any])
        legacy["schemaVersion"] = 25
        XCTAssertEqual(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)), plain)
    }

    // SF-0904-004, OD-033: every variant a copy can show is itself a valid
    // component. An override that would make a variant invalid (here a corner
    // radius on a Text, which no Text supports) is refused for the whole
    // document with a specific reason, while the base stays valid.
    func testComponentVariantThatWouldBeInvalidIsRejectedWithItsReason() throws {
        let fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        var document = fixture.document
        try setVariantProperty(V.overrideKey(.value(fixture.large), DesignBoxStyleCommandRegistry.namespace + "radius.uniform"),
                               .number(4), on: fixture.labelID, definition: fixture.definitionID, in: &document)
        XCTAssertThrowsError(try document.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .componentVariantResolvesInvalid)
        }
        XCTAssertTrue(ModelValidationError.componentVariantResolvesInvalid.localizedDescription.contains("variants"))
        var valid = fixture.document
        try setVariantProperty(V.overrideKey(.value(fixture.large), DesignBoxStyleCommandRegistry.namespace + "radius.uniform"),
                               .number(4), on: fixture.rootID, definition: fixture.definitionID, in: &valid)
        XCTAssertNoThrow(try valid.validate(), "The same setting is valid on the Frame")
    }

    /// Prepares one variant edit against the session's current document.
    private func variantEdit(_ edit: ComponentVariantEdit, definition: PageID,
                             in session: DocumentSession) throws -> PreparedComponentVariantEdit {
        try ComponentVariantCommandRegistry().prepare(edit, definitionID: definition,
            expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
            document: session.document, isLifecycleAvailable: true)
    }

    // SF-0904-002/005, OD-033: axes, values, defaults and allowed
    // combinations are created, renamed, reordered and removed, each as one
    // undoable transaction of ordinary property commands. Removing a value or
    // property also removes its settings; changing the axis order re-keys
    // combination settings; limits, names and the default rules refuse with a
    // reason and change nothing; a stale revision is refused.
    func testVariantAxesValuesAndCombinationsAreEditedInOneUndoableTransactionEach() throws {
        let fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        var plain = fixture.document
        let definitionIndex = try XCTUnwrap(plain.pages.firstIndex { $0.id == fixture.definitionID })
        plain.pages[definitionIndex].nodes[0].properties.removeAll { V.isMetadataKey($0.key.rawValue) }
        try plain.validate()
        let session = DocumentSession(document: plain)
        func set() throws -> CanonicalVariantSet? {
            try V.variantSet(in: try XCTUnwrap(session.document.componentDefinitions.first))
        }
        func run(_ edit: ComponentVariantEdit) throws -> PreparedComponentVariantEdit {
            let prepared = try variantEdit(edit, definition: fixture.definitionID, in: session)
            try session.execute(prepared.command)
            return prepared
        }
        func refuses(_ edit: ComponentVariantEdit, _ reason: String, file: StaticString = #filePath, line: UInt = #line) {
            let before = session.document
            XCTAssertThrowsError(try variantEdit(edit, definition: fixture.definitionID, in: session), file: file, line: line) {
                XCTAssertTrue($0.localizedDescription.contains(reason), $0.localizedDescription, file: file, line: line)
            }
            XCTAssertEqual(session.document, before, file: file, line: line)
        }

        let added = try run(.addAxis(name: "Size", valueNames: ["Small", "Large"]))
        XCTAssertTrue(added.announcement.contains("Small is the default"))
        let size = try XCTUnwrap(set()?.axes.first)
        XCTAssertEqual(size.values.map(\.name), ["Small", "Large"])
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertNil(try set()); try session.redo()
        let small = size.values[0].id, large = size.values[1].id
        _ = try run(.addValue(axis: size.id, name: "Medium"))
        let medium = try XCTUnwrap(set()?.axes[0].values.last?.id)
        _ = try run(.moveValue(medium, offset: -1))
        XCTAssertEqual(try set()?.axes[0].values.map(\.name), ["Small", "Medium", "Large"])
        _ = try run(.renameValue(medium, name: "Regular"))
        refuses(.renameValue(large, name: "small"), "uses")
        refuses(.removeValue(small), "default value")
        _ = try run(.setDefault(medium))
        XCTAssertEqual(try set()?.axes[0].defaultValueID, medium)

        // Settings belong to values: removing a value removes them in the same step.
        _ = try run(.addAxis(name: "Tone", valueNames: ["Primary", "Secondary"]))
        let tone = try XCTUnwrap(set()?.axes.last)
        let secondary = tone.values[1].id
        let both = CanonicalVariantCombination([large, secondary])
        var authored = session.document
        try setVariantProperty(V.overrideKey(.value(small), "content.text"), .string("Small text"), on: fixture.labelID,
                               definition: fixture.definitionID, in: &authored)
        try setVariantProperty(V.overrideKey(.combination(both), "content.text"), .string("Large secondary"), on: fixture.labelID,
                               definition: fixture.definitionID, in: &authored)
        try authored.validate()
        try session.establishBaseline(authored)
        func labelKeys() throws -> Set<String> {
            let definition = try XCTUnwrap(session.document.componentDefinitions.first)
            return Set(try XCTUnwrap(definition.nodes.first { $0.id == fixture.labelID }).properties.map(\.key.rawValue)
                .filter(V.isOverrideKey))
        }
        let reordered = try run(.moveAxis(tone.id, offset: -1))
        XCTAssertTrue(reordered.announcement.contains("up"))
        XCTAssertEqual(try set()?.axes.map(\.name), ["Tone", "Size"])
        XCTAssertEqual(try labelKeys(), [V.overrideKey(.value(small), "content.text"),
                                         V.overrideKey(.combination(.init([secondary, large])), "content.text")],
                       "Combination settings follow the new axis order")
        try session.undo()
        XCTAssertEqual(try labelKeys(), [V.overrideKey(.value(small), "content.text"), V.overrideKey(.combination(both), "content.text")])
        _ = try run(.setCombinationAllowed(both, allowed: false))
        XCTAssertEqual(try set()?.disallowed, [both.key])
        XCTAssertEqual(try labelKeys(), [V.overrideKey(.value(small), "content.text")], "A disallowed variant keeps no settings")
        refuses(.setCombinationAllowed(try XCTUnwrap(set()).defaultCombination, allowed: false), "default variant")
        _ = try run(.setCombinationAllowed(both, allowed: true))
        _ = try run(.removeValue(small))
        XCTAssertTrue(try labelKeys().isEmpty)
        XCTAssertEqual(try set()?.axes[0].values.map(\.name), ["Regular", "Large"])
        refuses(.removeValue(large), "at least two values")

        // A copy that chose a value keeps the choice when that value goes.
        let instanceIndex = try XCTUnwrap(session.document.pages[0].nodes.firstIndex { $0.id == fixture.instanceID })
        var chosen = session.document
        chosen.pages[0].nodes[instanceIndex].properties.append(.init(key: .init(rawValue: V.choiceKey(tone.id)),
                                                                     value: .string(secondary.description)))
        try session.establishBaseline(chosen)
        let removedTone = try run(.removeAxis(tone.id))
        XCTAssertEqual(removedTone.copiesNeedingRepair, 1)
        XCTAssertEqual(try set()?.axes.map(\.name), ["Size"])
        XCTAssertNotNil(session.document.pages[0].nodes[instanceIndex].insertionProperty(V.choiceKey(tone.id)),
                        "The copy's choice is kept for repair")
        let removedSize = try run(.removeAxis(size.id))
        XCTAssertTrue(removedSize.announcement.contains("no variants"))
        XCTAssertNil(try set())
        XCTAssertFalse(try XCTUnwrap(session.document.componentDefinitions.first).nodes.flatMap(\.properties)
            .contains { $0.key.rawValue.hasPrefix(V.namespace) })

        // Limits and names.
        refuses(.addAxis(name: "Solo", valueNames: ["Only"]), "2 to")
        refuses(.addAxis(name: "", valueNames: ["A", "B"]), "Use a name")
        for name in ["A", "B", "C", "D"] { _ = try run(.addAxis(name: name, valueNames: ["One", "Two"])) }
        refuses(.addAxis(name: "E", valueNames: ["One", "Two"]), "up to 4")
        refuses(.addAxis(name: "a", valueNames: ["One", "Two"]), "up to 4")
        XCTAssertThrowsError(try ComponentVariantCommandRegistry().prepare(.addValue(axis: size.id, name: "X"),
            definitionID: fixture.definitionID, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision - 1, document: session.document, isLifecycleAvailable: true)) {
            XCTAssertEqual($0 as? ComponentVariantError, .stale)
        }
        XCTAssertThrowsError(try ComponentVariantCommandRegistry().prepare(.addValue(axis: size.id, name: "X"),
            definitionID: fixture.definitionID, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision, document: session.document, isLifecycleAvailable: false,
            lifecycleDisabledReason: "Close Preview first.")) {
            XCTAssertEqual($0.localizedDescription, "Close Preview first.")
        }
    }

    // SF-0904-002 (owner choice: edit inside the variant), OD-033: while a
    // variant is edited, property edits made against the presented variant
    // become that variant's settings through the session's one conversion
    // point; setting the inherited value removes the variant's own value;
    // removing a property hides it in that variant only; structure edits and
    // settings that are the same in every variant are refused; undo restores.
    func testEditingInsideAVariantStoresItsSettingsAndKeepsStructureShared() throws {
        let fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        let session = DocumentSession(document: fixture.document)
        let target = CanonicalVariantTarget.value(fixture.large)
        let presented = V.presentedDocument(session.document, definitionID: fixture.definitionID, target: target)
        let presentedLabel = try XCTUnwrap(presented.componentDefinitions.first?.nodes.first { $0.id == fixture.labelID })
        let presentedRoot = try XCTUnwrap(presented.componentDefinitions.first?.nodes.first { $0.id == fixture.rootID })
        XCTAssertNotNil(presentedRoot.insertionProperty(V.axesKey), "Metadata stays visible while editing")
        session.authoringTransform = { command, document in
            try V.rewrite(command, definitionID: fixture.definitionID, target: target, document: document)
        }
        func label() throws -> DocumentNode {
            try XCTUnwrap(session.document.componentDefinitions.first?.nodes.first { $0.id == fixture.labelID })
        }
        let text = try XCTUnwrap(presentedLabel.insertionProperty("content.text"))
        try session.execute(.setProperty(.init(pageID: fixture.definitionID, nodeID: fixture.labelID,
            property: .init(id: text.id, key: text.key, value: .string("Buy now")))))
        XCTAssertEqual(try label().insertionStringProperty("content.text"), "Buy", "The base is unchanged")
        XCTAssertEqual(try label().insertionStringProperty(V.overrideKey(target, "content.text")), "Buy now")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(session.historySnapshot().undoEntries.last?.forward.name, .setProperty,
                       "History stores the converted command")
        try session.undo()
        XCTAssertNil(try label().insertionProperty(V.overrideKey(target, "content.text")))
        try session.redo()

        // Setting the value the variant would otherwise show removes its own value.
        try session.execute(.setProperty(.init(pageID: fixture.definitionID, nodeID: fixture.labelID,
            property: .init(id: text.id, key: text.key, value: .string("Buy")))))
        XCTAssertNil(try label().insertionProperty(V.overrideKey(target, "content.text")))

        // Removing the radius hides it in this variant only.
        let radius = try XCTUnwrap(presentedRoot.insertionProperty(DesignBoxStyleCommandRegistry.namespace + "radius.uniform"))
        try session.execute(.removeProperty(.init(pageID: fixture.definitionID, nodeID: fixture.rootID, propertyID: radius.id)))
        let root = try XCTUnwrap(session.document.componentDefinitions.first?.nodes.first { $0.id == fixture.rootID })
        XCTAssertNotNil(root.insertionProperty(radius.key.rawValue), "Base keeps its radius")
        XCTAssertEqual(root.insertionProperty(V.unsetKey(target, radius.key.rawValue))?.value, .boolean(true))
        let shown = V.presentedDocument(session.document, definitionID: fixture.definitionID, target: target)
        XCTAssertNil(shown.componentDefinitions.first?.nodes.first { $0.id == fixture.rootID }?.insertionProperty(radius.key.rawValue))

        // A combination inherits its values' settings; matching them stores nothing.
        let both = CanonicalVariantCombination([fixture.large, fixture.secondary])
        var largeText = session.document
        try setVariantProperty(V.overrideKey(target, "content.text"), .string("Buy now"), on: fixture.labelID,
                               definition: fixture.definitionID, in: &largeText)
        try session.establishBaseline(largeText)
        XCTAssertThrowsError(try V.rewrite(.setProperty(.init(pageID: fixture.definitionID, nodeID: fixture.labelID,
            property: .init(id: text.id, key: text.key, value: .string("Buy now")))),
            definitionID: fixture.definitionID, target: .combination(both), document: session.document),
            "Equal to what the combination inherits from Large: nothing to store") {
            XCTAssertEqual($0 as? ComponentVariantError, .noChanges)
        }
        let combined = try V.rewrite(.setProperty(.init(pageID: fixture.definitionID, nodeID: fixture.labelID,
            property: .init(id: text.id, key: text.key, value: .string("Save")))),
            definitionID: fixture.definitionID, target: .combination(both), document: session.document)
        guard case .setProperty(let stored) = combined else { return XCTFail("One property command") }
        XCTAssertEqual(stored.property.key.rawValue, V.overrideKey(.combination(both), "content.text"))

        // Structure and shared settings are refused; other pages pass through.
        let before = session.document
        let child = DocumentNode(kind: .frame, name: "Extra", parent: .node(fixture.rootID), properties: [])
        XCTAssertThrowsError(try session.execute(.insertNode(.init(pageID: fixture.definitionID, node: child, index: 0)))) {
            XCTAssertEqual($0 as? ComponentVariantError, .structureNeedsBase)
            XCTAssertTrue($0.localizedDescription.contains("Switch to Base"))
        }
        XCTAssertThrowsError(try session.execute(.setProperty(.init(pageID: fixture.definitionID, nodeID: fixture.labelID,
            property: .init(key: .init(rawValue: CanonicalLinkTarget.namespace + "kind"), value: .string("none")))))) {
            XCTAssertEqual($0 as? ComponentVariantError, .notVariantCapable(CanonicalLinkTarget.namespace + "kind"))
        }
        XCTAssertEqual(session.document, before)
        let pageCommand = DocumentCommand.renamePage(.init(pageID: session.document.pages[0].id, name: "Renamed"))
        XCTAssertEqual(try V.rewrite(pageCommand, definitionID: fixture.definitionID, target: target, document: session.document),
                       pageCommand)
    }

    // SF-0904-002/004/005, OD-033: a copy's choice is one undoable step; a
    // copy still at its variant's size takes the new variant's size, a resized
    // copy keeps its own; a combination that is not allowed is refused; Use
    // Default removes every stored choice, including unavailable ones.
    func testCopyVariantChoiceIsOneUndoableStepAndFollowsTheVariantSize() throws {
        let fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        var document = fixture.document
        try setVariantProperty(V.overrideKey(.value(fixture.large), "layout.width"), .number(280), on: fixture.rootID,
                               definition: fixture.definitionID, in: &document)
        let both = CanonicalVariantCombination([fixture.large, fixture.secondary])
        try setVariantProperty(V.disallowedKey, .string(both.key), on: fixture.rootID, definition: fixture.definitionID, in: &document)
        try document.validate()
        let session = DocumentSession(document: document)
        let pageID = session.document.pages[0].id
        func copy() throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.instanceID }) }
        func choose(_ axis: ComponentVariantAxisID, _ value: ComponentVariantValueID?) throws {
            try session.execute(try variantEdit(.setChoice(instanceID: fixture.instanceID, pageID: pageID, axis: axis, value: value),
                                                definition: fixture.definitionID, in: session).command)
        }
        try choose(fixture.size, fixture.large)
        XCTAssertEqual(try copy().insertionStringProperty(V.choiceKey(fixture.size)), fixture.large.description)
        XCTAssertEqual(try copy().insertionNumberProperty("layout.width"), 280, "The copy takes Large's size")
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo()
        XCTAssertEqual(try copy().insertionNumberProperty("layout.width"), 200)
        XCTAssertNil(try copy().insertionProperty(V.choiceKey(fixture.size)))
        try session.redo()
        XCTAssertThrowsError(try variantEdit(.setChoice(instanceID: fixture.instanceID, pageID: pageID, axis: fixture.tone,
                                                        value: fixture.secondary), definition: fixture.definitionID, in: session)) {
            XCTAssertTrue($0.localizedDescription.contains("isn't allowed"))
        }
        try choose(fixture.size, nil)
        XCTAssertEqual(try copy().insertionNumberProperty("layout.width"), 200, "Back to the default size")

        // A copy the user resized keeps its size when its variant changes.
        var resized = session.document
        let index = try XCTUnwrap(resized.pages[0].nodes.firstIndex { $0.id == fixture.instanceID })
        let widthIndex = try XCTUnwrap(resized.pages[0].nodes[index].properties.firstIndex { $0.key.rawValue == "layout.width" })
        resized.pages[0].nodes[index].properties[widthIndex].value = .number(300)
        resized.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: V.choiceKey(ComponentVariantAxisID())),
                                                              value: .string(ComponentVariantValueID().description)))
        try session.establishBaseline(resized)
        try choose(fixture.size, fixture.large)
        XCTAssertEqual(try copy().insertionNumberProperty("layout.width"), 300)
        XCTAssertThrowsError(try variantEdit(.setChoice(instanceID: fixture.instanceID, pageID: pageID, axis: fixture.size,
                                                        value: fixture.large), definition: fixture.definitionID, in: session)) {
            XCTAssertEqual($0 as? ComponentVariantError, .noChanges)
        }
        try session.execute(try variantEdit(.resetChoices(instanceID: fixture.instanceID, pageID: pageID),
                                            definition: fixture.definitionID, in: session).command)
        XCTAssertFalse(try copy().properties.contains { V.isChoiceKey($0.key.rawValue) }, "Unavailable choices are removed too")
    }

    // SF-0904-002/006, OD-033: in the workspace, choosing a variant of the
    // open definition shows it on the canvas document, stores edits as that
    // variant's settings, blocks insertion (structure is shared), and ends
    // when the definition is closed.
    func testWorkspaceEditsInsideAVariantAndReturnsToBaseOnExit() throws {
        let fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        var document = fixture.document
        try setVariantProperty(V.overrideKey(.value(fixture.large), "content.text"), .string("Buy now"), on: fixture.labelID,
                               definition: fixture.definitionID, in: &document)
        try document.validate()
        let session = DocumentSession(document: document)
        let shell = WorkspaceShellState(documentSession: session)
        XCTAssertFalse(shell.editVariant(.value(fixture.large)), "Only while a definition is open")
        shell.editComponentDefinition(fixture.definitionID)
        XCTAssertEqual(shell.editingComponentID, fixture.definitionID)
        XCTAssertTrue(shell.editVariant(.value(fixture.large)))
        XCTAssertTrue(shell.variantAnnouncement.contains("Size: Large"))
        func shownText(_ document: CanonicalDocument) -> String? {
            document.componentDefinitions.first?.nodes.first { $0.id == fixture.labelID }?.insertionStringProperty("content.text")
        }
        XCTAssertEqual(shownText(shell.authoringDocument), "Buy now")
        XCTAssertEqual(shownText(session.document), "Buy")
        XCTAssertFalse(shell.componentInsertionIsAvailable)
        // ADR-0038/0041: restoring a snapshot or changing libraries waits for the variant to close.
        XCTAssertFalse(shell.canReplaceProjectContent)
        XCTAssertFalse(shell.restoreSnapshot(ProjectSnapshotID(), keepingCurrentAs: nil))
        XCTAssertEqual(shell.snapshotsStatus, WorkspaceShellState.variantOpenReplacementMessage)
        let nodeCount = session.document.componentDefinitions.first?.nodes.count
        shell.performDefaultInsertion(.text, provenance: .menu)
        XCTAssertEqual(session.document.componentDefinitions.first?.nodes.count, nodeCount, "No insertion inside a variant")

        let text = try XCTUnwrap(shell.authoringDocument.componentDefinitions.first?.nodes.first { $0.id == fixture.labelID }?
            .insertionProperty("content.text"))
        try session.execute(.setProperty(.init(pageID: fixture.definitionID, nodeID: fixture.labelID,
            property: .init(id: text.id, key: text.key, value: .string("Buy more")))))
        XCTAssertEqual(shownText(shell.authoringDocument), "Buy more")
        XCTAssertEqual(shownText(session.document), "Buy")
        XCTAssertEqual(shell.variantSource(of: "content.text", nodeID: fixture.labelID), .value(fixture.large))

        XCTAssertTrue(shell.editVariant(nil))
        XCTAssertEqual(shownText(shell.authoringDocument), "Buy")
        XCTAssertTrue(shell.editVariant(.value(fixture.secondary)))
        shell.exitComponentDefinition()
        XCTAssertNil(shell.editingComponentID)
        XCTAssertNil(shell.variantEditingTarget)
        XCTAssertNil(session.authoringTransform, "Closing the definition ends variant editing")
        XCTAssertTrue(shell.canReplaceProjectContent)
    }

    // SF-0904-004/008, OD-033: an Undo that removes the variant being edited
    // never lets a later edit land in the base. The conversion point refuses
    // edits of that definition as stale (other pages still edit normally), and
    // on the next main-queue turn the workspace returns to Base and says why.
    // Diagnostics carry the requirement, operation and sanitized identities.
    func testUndoThatRemovesTheEditedVariantReturnsToBaseAndRefusesStaleEdits() async throws {
        let fixture = try variantFixture()
        let session = DocumentSession(document: fixture.document)
        let shell = WorkspaceShellState(documentSession: session)
        shell.editComponentDefinition(fixture.definitionID)
        XCTAssertTrue(shell.performVariantEdit(.addValue(axis: fixture.size, name: "Huge"), definitionID: fixture.definitionID))
        let added = try XCTUnwrap(shell.lastVariantDiagnostic)
        XCTAssertEqual(added.requirementID, "SF-0904-002")
        XCTAssertEqual(added.operation, "variant.value.add")
        XCTAssertEqual(added.failureCategory, "none")
        XCTAssertFalse(added.definitionIdentifier.contains(fixture.definitionID.description), "Identities are sanitized")
        XCTAssertFalse(added.documentIdentifier.contains(session.document.id.description))
        let huge = try XCTUnwrap(shell.editingComponentVariantSet?.axes.first?.values.last)
        XCTAssertEqual(huge.name, "Huge")
        XCTAssertTrue(shell.editVariant(.value(huge.id)))
        XCTAssertEqual(shell.lastVariantDiagnostic?.operation, "variant.edit.begin")

        shell.undo()
        XCTAssertNil(shell.editingComponentVariantSet?.value(huge.id), "Undo removed the value being edited")
        let before = session.document
        let text = try XCTUnwrap(before.componentDefinitions.first?.nodes.first { $0.id == fixture.labelID }?
            .insertionProperty("content.text"))
        XCTAssertThrowsError(try session.execute(.setProperty(.init(pageID: fixture.definitionID, nodeID: fixture.labelID,
            property: .init(id: text.id, key: text.key, value: .string("Huge text")))))) {
            XCTAssertEqual($0 as? ComponentVariantError, .stale)
        }
        XCTAssertEqual(session.document, before, "Nothing is stored in the base")
        let pageCommand = DocumentCommand.renamePage(.init(pageID: session.document.pages[0].id, name: "Still Editable"))
        XCTAssertNoThrow(try session.execute(pageCommand), "Other pages are unaffected")

        let reconciled = expectation(description: "variant editing reconciled")
        DispatchQueue.main.async { reconciled.fulfill() }
        await fulfillment(of: [reconciled], timeout: 2)
        XCTAssertNil(shell.variantEditingTarget)
        XCTAssertNil(session.authoringTransform)
        XCTAssertTrue(shell.variantAnnouncement.contains("no longer exists"))
        XCTAssertEqual(shell.lastVariantDiagnostic?.requirementID, "SF-0904-004")
        XCTAssertEqual(shell.lastVariantDiagnostic?.failureCategory, "stale")
        XCTAssertEqual(shell.editingComponentID, fixture.definitionID, "The definition stays open, in Base")
    }

    // SF-0904-007, OD-033: enabling a variant control applies the registry's
    // rules without the commit-only work (whole-document validation and the
    // count of copies needing repair); both paths build the same command and
    // refuse with the same reason.
    func testVariantControlAvailabilityUsesTheRegistryRulesWithoutCommitOnlyWork() throws {
        let fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        var document = fixture.document
        try chooseVariant(fixture.secondary.description, for: V.choiceKey(fixture.tone), on: fixture.instanceID, in: &document)
        try document.validate()
        func prepare(_ edit: ComponentVariantEdit, forCommit: Bool) throws -> PreparedComponentVariantEdit {
            try ComponentVariantCommandRegistry().prepare(edit, definitionID: fixture.definitionID,
                expectedDocumentID: document.id, expectedRevision: document.revision, document: document,
                isLifecycleAvailable: true, forCommit: forCommit)
        }
        let commit = try prepare(.removeAxis(fixture.tone), forCommit: true)
        let control = try prepare(.removeAxis(fixture.tone), forCommit: false)
        XCTAssertEqual(control.command, commit.command, "The same edit either way")
        XCTAssertEqual(commit.copiesNeedingRepair, 1)
        XCTAssertEqual(control.copiesNeedingRepair, 0, "Only the commit counts copies")
        for forCommit in [true, false] {
            XCTAssertThrowsError(try prepare(.removeValue(fixture.small), forCommit: forCommit)) {
                XCTAssertTrue($0.localizedDescription.contains("default value"), "\(forCommit)")
            }
        }
    }

    // SF-0901-005, SF-0303, SF-0904-005, OD-033: detaching a copy keeps what
    // it showed (its variant's values, no variant storage); duplicating the
    // page keeps each copy's choice; duplicating the definition keeps its
    // variants for the new component.
    func testDetachPageAndDefinitionDuplicateKeepTheVariantACopyShows() throws {
        let fixture = try variantFixture()
        typealias V = CanonicalComponentVariants
        var document = fixture.document
        try setVariantProperty(V.overrideKey(.value(fixture.large), "content.text"), .string("Buy now"), on: fixture.labelID,
                               definition: fixture.definitionID, in: &document)
        try setVariantProperty(V.overrideKey(.value(fixture.secondary), "style.opacity"), .number(0.5), on: fixture.rootID,
                               definition: fixture.definitionID, in: &document)
        try chooseVariant(fixture.large.description, for: V.choiceKey(fixture.size), on: fixture.instanceID, in: &document)
        try chooseVariant(fixture.secondary.description, for: V.choiceKey(fixture.tone), on: fixture.instanceID, in: &document)
        try document.validate()
        let pageID = document.pages[0].id

        let duplicate = try PageCommandRegistry().prepare(.duplicate,
            identity: .init(documentID: document.id, revision: document.revision, pageID: pageID), in: document, isAvailable: true)
        let duplicated = DocumentSession(document: document)
        try duplicated.execute(duplicate.command)
        let newPage = try XCTUnwrap(duplicated.document.pages.first { $0.id == duplicate.selectedPageID })
        let newCopy = try XCTUnwrap(newPage.nodes.first { $0.kind == .component })
        XCTAssertEqual(newCopy.insertionStringProperty(V.choiceKey(fixture.size)), fixture.large.description)
        XCTAssertEqual(newCopy.insertionStringProperty(V.choiceKey(fixture.tone)), fixture.secondary.description)

        let duplicateDefinition = try textCommand(.duplicateDefinition(fixture.definitionID), document: document,
                                                  pageID: pageID, selected: fixture.instanceID)
        let withCopy = DocumentSession(document: document)
        try withCopy.execute(duplicateDefinition.command)
        XCTAssertEqual(withCopy.document.componentDefinitions.count, 2)
        for definition in withCopy.document.componentDefinitions {
            XCTAssertEqual(try V.variantSet(in: definition)?.axes.map(\.name), ["Size", "Tone"])
        }

        let session = DocumentSession(document: document)
        try session.execute(textCommand(.detach(fixture.instanceID), document: document, pageID: pageID,
                                        selected: fixture.instanceID).command)
        let detached = session.document.pages[0]
        let root = try XCTUnwrap(detached.nodes.first { $0.id == fixture.instanceID })
        XCTAssertEqual(root.kind, .frame)
        XCTAssertEqual(root.insertionNumberProperty("style.opacity"), 0.5)
        let label = try XCTUnwrap(detached.nodes.first { $0.parent == .node(fixture.instanceID) && $0.kind == .text })
        XCTAssertEqual(label.insertionStringProperty("content.text"), "Buy now")
        XCTAssertFalse(detached.nodes.flatMap(\.properties).contains {
            $0.key.rawValue.hasPrefix(V.namespace) || V.isChoiceKey($0.key.rawValue)
        }, "Detached objects carry no variant storage")
        try session.document.validate()
        try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)
    }

    /// SF-0605 fixture: Home with a Frame "Panel" (0, 0, 500 × 300) that is
    /// the query container "panel", holding a Text "Caption" (10, 10, 200 × 24)
    /// and a Stack "Row" (10, 60, 300 × 100) holding a Frame "Chip".
    private struct ContainerQueryFixture {
        var document: CanonicalDocument
        let pageID: PageID, panel: NodeID, caption: NodeID, row: NodeID, chip: NodeID
    }

    private func containerQueryFixture() throws -> ContainerQueryFixture {
        func number(_ key: String, _ value: Double) -> NodeProperty { .init(key: .init(rawValue: key), value: .number(value)) }
        func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [number("layout.x", x), number("layout.y", y), number("layout.width", width), number("layout.height", height)]
        }
        var document = BlankProjectDefaults.document()
        let pageRoot = document.pages[0].rootNodeIDs[0]
        let panel = NodeID(), caption = NodeID(), row = NodeID(), chip = NodeID()
        var stack = DocumentNode(id: row, kind: .stack, name: "Row", parent: .node(panel), childIDs: [chip], properties: frame(10, 60, 300, 100))
        stack.properties += [("layout.container.kind", PropertyValue.string("stack")), ("layout.axis", .string("horizontal")),
                             ("layout.padding", .number(0)), ("layout.gap", .number(8)), ("layout.align", .string("start"))]
            .map { NodeProperty(key: .init(rawValue: $0.0), value: $0.1, origin: .defaulted) }
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
        document.pages[0].nodes[rootIndex].childIDs.append(panel)
        document.pages[0].nodes += [
            DocumentNode(id: panel, kind: .frame, name: "Panel", parent: .node(pageRoot), childIDs: [caption, row],
                         properties: frame(0, 0, 500, 300) + [.init(key: .init(rawValue: CanonicalContainerQueries.containerKey), value: .string("panel"))]),
            DocumentNode(id: caption, kind: .text, name: "Caption", parent: .node(panel),
                         properties: frame(10, 10, 200, 24) + [.init(key: .init(rawValue: "content.text"), value: .string("Caption"))]),
            stack,
            DocumentNode(id: chip, kind: .frame, name: "Chip", parent: .node(row), properties: frame(0, 0, 40, 40)),
        ]
        try document.validate()
        return .init(document: document, pageID: document.pages[0].id, panel: panel, caption: caption, row: row, chip: chip)
    }

    private func containerQueryEdit(_ edit: ContainerQueryEdit, page: PageID,
                                    in session: DocumentSession) throws -> PreparedContainerQueryEdit {
        try ContainerQueryCommandRegistry().prepare(edit, pageID: page, expectedDocumentID: session.document.id,
            expectedRevision: session.document.revision, document: session.document, isLifecycleAvailable: true)
    }

    // SF-0605-001/004/005: a query container and ordered rules use one strict
    // spelling; container names, width ranges, settings and their targets are
    // validated; every malformed encoding is rejected; the data needs
    // document schema 27 and older files carrying it are refused.
    func testContainerQueriesUseOneStrictEncodingAndRequireSchemaTwentySeven() throws {
        typealias Q = CanonicalContainerQueries
        let fixture = try containerQueryFixture()
        let rule = ContainerQueryRuleID()
        func adding(_ node: NodeID, _ values: [(String, PropertyValue)], to base: CanonicalDocument? = nil) throws -> CanonicalDocument {
            var document = base ?? fixture.document
            let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == node })
            for (key, value) in values {
                document.pages[0].nodes[index].properties.removeAll { $0.key.rawValue == key }
                document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: key), value: value))
            }
            return document
        }
        let valid: [(String, PropertyValue)] = [(Q.rulesKey, .string(rule.description)), (Q.ruleKey(rule, "minWidth"), .number(400)),
                                                (Q.setKey(rule, CanonicalTypography.namespace + "size"), .number(24))]
        let document = try adding(fixture.caption, valid)
        XCTAssertNoThrow(try document.validate())
        let caption = try XCTUnwrap(document.pages[0].nodes.first { $0.id == fixture.caption })
        let parsed = try XCTUnwrap(Q.rules(on: caption).first)
        XCTAssertEqual(parsed.minWidth, 400); XCTAssertNil(parsed.maxWidth); XCTAssertNil(parsed.container)
        XCTAssertEqual(parsed.values.map(\.key), [CanonicalTypography.namespace + "size"])
        XCTAssertEqual(parsed.rangeDescription, "at least 400 pt")
        XCTAssertTrue(parsed.matches(width: 400)); XCTAssertFalse(parsed.matches(width: 399))

        func refuses(_ label: String, _ node: NodeID, _ values: [(String, PropertyValue)]) {
            XCTAssertThrowsError(try adding(node, values).validate(), label) {
                XCTAssertEqual($0 as? ModelValidationError, .invalidContainerQueryState, label)
            }
        }
        refuses("name with capitals", fixture.panel, [(Q.containerKey, .string("Panel"))])
        refuses("name starting with a digit", fixture.panel, [(Q.containerKey, .string("1panel"))])
        refuses("container on text", fixture.caption, [(Q.containerKey, .string("text"))])
        refuses("no range", fixture.caption, [(Q.rulesKey, .string(rule.description)),
                                              (Q.setKey(rule, "hidden"), .boolean(true))])
        refuses("minimum above maximum", fixture.caption, valid + [(Q.ruleKey(rule, "maxWidth"), .number(300))])
        refuses("fractional width", fixture.caption, [(Q.rulesKey, .string(rule.description)), (Q.ruleKey(rule, "minWidth"), .number(400.5)),
                                                      (Q.setKey(rule, "hidden"), .boolean(true))])
        refuses("no settings", fixture.caption, [(Q.rulesKey, .string(rule.description)), (Q.ruleKey(rule, "minWidth"), .number(400))])
        refuses("unsupported setting", fixture.caption, valid + [(Q.setKey(rule, "content.text"), .string("x"))])
        refuses("unknown field", fixture.caption, valid + [(Q.ruleKey(rule, "priority"), .number(1))])
        refuses("rule data without the list", fixture.caption, Array(valid.dropFirst()))
        refuses("text size on a frame", fixture.chip, [(Q.rulesKey, .string(rule.description)), (Q.ruleKey(rule, "minWidth"), .number(1)),
                                                       (Q.setKey(rule, CanonicalTypography.namespace + "size"), .number(20))])
        refuses("width inside a Stack", fixture.chip, [(Q.rulesKey, .string(rule.description)), (Q.ruleKey(rule, "minWidth"), .number(1)),
                                                       (Q.setKey(rule, "layout.width"), .number(80))])
        refuses("opacity above one", fixture.caption, [(Q.rulesKey, .string(rule.description)), (Q.ruleKey(rule, "minWidth"), .number(1)),
                                                       (Q.setKey(rule, "style.opacity"), .number(2))])
        let nine = (0..<9).map { _ in ContainerQueryRuleID() }
        refuses("nine rules", fixture.caption, [(Q.rulesKey, .string(nine.map(\.description).joined(separator: ",")))]
            + nine.flatMap { [(Q.ruleKey($0, "minWidth"), PropertyValue.number(1)), (Q.setKey($0, "hidden"), .boolean(true))] })
        XCTAssertNoThrow(try adding(fixture.caption, valid + [(Q.ruleKey(rule, "container"), .string("missing"))]).validate(),
                         "An unknown container name is kept intent, reported by evaluation")

        XCTAssertEqual(Q.documentSchema, 27)
        XCTAssertEqual(DocumentSerializer.currentSchemaVersion, Q.documentSchema)
        let encoded = try DocumentSerializer.encode(document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(envelope["schemaVersion"] as? Int, 27)
        for older in [26, 25, 20] {
            envelope["schemaVersion"] = older
            XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "\(older)")
        }
        var plain = try containerQueryFixture().document
        let panelIndex = try XCTUnwrap(plain.pages[0].nodes.firstIndex { $0.kind == .frame && $0.name == "Panel" })
        plain.pages[0].nodes[panelIndex].properties.removeAll { $0.key.rawValue.hasPrefix(Q.namespace) }
        try plain.validate()
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(plain)) as? [String: Any])
        legacy["schemaVersion"] = 26
        XCTAssertEqual(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)), plain)
    }

    // SF-0605-003/004: rules apply in order (a later match wins per setting),
    // query the nearest container or a named one, never the object itself,
    // and beat a breakpoint's own value as `@container` beats `@media`. A rule
    // with no container never applies and is reported by identity.
    func testContainerQueryEvaluationIsOrderedNearestFirstAndBeatsBreakpointValues() throws {
        typealias Q = CanonicalContainerQueries
        var fixture = try containerQueryFixture()
        let session = DocumentSession(document: fixture.document)
        let page = fixture.pageID
        func add(_ node: NodeID, min: Double?, max: Double?, container: String? = nil, _ key: String, _ value: PropertyValue) throws -> ContainerQueryRuleID {
            let prepared = try containerQueryEdit(.addRule(nodeID: node, container: container, minWidth: min, maxWidth: max, key: key, value: value),
                                                  page: page, in: session)
            try session.execute(prepared.command)
            return try XCTUnwrap(prepared.ruleID)
        }
        let first = try add(fixture.caption, min: 400, max: nil, "style.opacity", .number(0.5))
        let second = try add(fixture.caption, min: 450, max: nil, "style.opacity", .number(0.25))
        _ = try add(fixture.caption, min: nil, max: 100, "hidden", .boolean(true))
        let named = try add(fixture.caption, min: 1, max: nil, container: "elsewhere", "style.opacity", .number(0.1))
        fixture.document = session.document

        let (applied, evaluation) = Q.evaluated(session.document.pages[0], breakpoint: .desktop)
        let caption = try XCTUnwrap(applied.nodes.first { $0.id == fixture.caption })
        XCTAssertEqual(caption.insertionNumberProperty("style.opacity"), 0.25, "Panel is 500 pt: both match, the later wins")
        XCTAssertFalse(caption.insertionBooleanProperty("hidden"))
        XCTAssertEqual(evaluation.winners[fixture.caption]?["style.opacity"], second)
        let statuses = try XCTUnwrap(evaluation.statuses[fixture.caption])
        XCTAssertEqual(statuses.map(\.matches), [true, true, false, false])
        XCTAssertEqual(statuses.first?.containerID, fixture.panel)
        XCTAssertEqual(statuses.first?.containerWidth, 500)
        XCTAssertEqual(statuses.first?.containerName, "panel")
        XCTAssertNil(statuses.last?.containerID)
        XCTAssertTrue(evaluation.findings.contains(.noContainer(nodeID: fixture.caption, ruleID: named)))
        XCTAssertEqual(ContainerQueryFinding.noContainer(nodeID: fixture.caption, ruleID: named).code, "container-query-no-container")
        XCTAssertNotNil(statuses.first { $0.ruleID == first })

        // Reordering changes the winner; a container never queries itself.
        try session.execute(try containerQueryEdit(.moveRule(nodeID: fixture.caption, ruleID: second, offset: -1), page: page, in: session).command)
        XCTAssertEqual(Q.evaluated(session.document.pages[0], breakpoint: .desktop).page.nodes
            .first { $0.id == fixture.caption }?.insertionNumberProperty("style.opacity"), 0.5)
        _ = try add(fixture.panel, min: 1, max: nil, "style.opacity", .number(0.3))
        let selfQuery = Q.evaluated(session.document.pages[0], breakpoint: .desktop)
        XCTAssertNotEqual(selfQuery.evaluation.statuses[fixture.panel]?.first?.containerID, fixture.panel,
                          "A container's own rules look above it")

        // At tablet, a matching rule beats the tablet's own visibility value.
        var tablet = session.document
        let captionIndex = try XCTUnwrap(tablet.pages[0].nodes.firstIndex { $0.id == fixture.caption })
        tablet.pages[0].nodes[captionIndex].properties.append(.init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.tablet)),
                                                                    value: .boolean(true)))
        _ = try XCTUnwrap(tablet.pages[0].nodes[captionIndex].insertionProperty(Q.rulesKey))
        let hideID = ContainerQueryRuleID()
        var ids = try XCTUnwrap(tablet.pages[0].nodes[captionIndex].insertionStringProperty(Q.rulesKey))
        ids += "," + hideID.description
        tablet.pages[0].nodes[captionIndex].properties.removeAll { $0.key.rawValue == Q.rulesKey }
        tablet.pages[0].nodes[captionIndex].properties += [
            .init(key: .init(rawValue: Q.rulesKey), value: .string(ids)),
            .init(key: .init(rawValue: Q.ruleKey(hideID, "minWidth")), value: .number(1)),
            .init(key: .init(rawValue: Q.setKey(hideID, "hidden")), value: .boolean(true)),
        ]
        try tablet.validate()
        let tabletPage = Q.evaluated(tablet.pages[0], breakpoint: .tablet).page
        let tabletCaption = try XCTUnwrap(tabletPage.nodes.first { $0.id == fixture.caption })
        XCTAssertFalse(ResponsiveVisibilityResolver.isVisible(tabletCaption, breakpoint: .tablet))
        XCTAssertNil(Q.evaluated(fixture.document.pages[1], breakpoint: .desktop).evaluation.statuses.first,
                     "A page without rules is returned unchanged")
    }

    // SF-0605-002/004/005/006: every container-query edit is one undoable
    // transaction; names, ranges, settings and order are validated with a
    // specific reason that changes nothing; a stale or busy edit is refused.
    func testContainerQueryEditsAreOneUndoableTransactionEachWithSpecificRefusals() throws {
        typealias Q = CanonicalContainerQueries
        let fixture = try containerQueryFixture()
        let session = DocumentSession(document: fixture.document)
        let page = fixture.pageID
        func run(_ edit: ContainerQueryEdit) throws -> PreparedContainerQueryEdit {
            let prepared = try containerQueryEdit(edit, page: page, in: session)
            try session.execute(prepared.command)
            return prepared
        }
        func refuses(_ edit: ContainerQueryEdit, _ reason: String, file: StaticString = #filePath, line: UInt = #line) {
            let before = session.document
            XCTAssertThrowsError(try containerQueryEdit(edit, page: page, in: session), file: file, line: line) {
                XCTAssertTrue($0.localizedDescription.contains(reason), $0.localizedDescription, file: file, line: line)
            }
            XCTAssertEqual(session.document, before, file: file, line: line)
        }
        func caption() throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.caption }) }

        let added = try run(.addRule(nodeID: fixture.caption, container: nil, minWidth: 600, maxWidth: nil,
                                     key: "hidden", value: .boolean(true)))
        let rule = try XCTUnwrap(added.ruleID)
        XCTAssertTrue(added.announcement.contains("at least 600 pt"))
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        try session.undo(); XCTAssertTrue(try Q.rules(on: caption()).isEmpty); try session.redo()
        _ = try run(.setRange(nodeID: fixture.caption, ruleID: rule, minWidth: 200, maxWidth: 480))
        XCTAssertEqual(try Q.rules(on: caption()).first?.rangeDescription, "200–480 pt")
        _ = try run(.setRuleContainer(nodeID: fixture.caption, ruleID: rule, container: "panel"))
        XCTAssertEqual(try Q.rules(on: caption()).first?.container, "panel")
        _ = try run(.setValue(nodeID: fixture.caption, ruleID: rule, key: "style.opacity", value: .number(0.4)))
        XCTAssertEqual(try Q.rules(on: caption()).first?.values.map(\.key), ["hidden", "style.opacity"])
        _ = try run(.setValue(nodeID: fixture.caption, ruleID: rule, key: "hidden", value: nil))
        refuses(.setValue(nodeID: fixture.caption, ruleID: rule, key: "style.opacity", value: nil), "Remove the rule instead")
        refuses(.setRange(nodeID: fixture.caption, ruleID: rule, minWidth: 500, maxWidth: 100), "must not be larger")
        refuses(.setRange(nodeID: fixture.caption, ruleID: rule, minWidth: nil, maxWidth: nil), "minimum width, a maximum width")
        refuses(.setRange(nodeID: fixture.caption, ruleID: rule, minWidth: 10.5, maxWidth: nil), "whole points")
        refuses(.setRuleContainer(nodeID: fixture.caption, ruleID: rule, container: "Bad Name"), "lowercase letters")
        refuses(.addRule(nodeID: fixture.chip, container: nil, minWidth: 1, maxWidth: nil, key: "layout.width", value: .number(80)),
                "placed in a Frame")
        refuses(.addRule(nodeID: fixture.chip, container: nil, minWidth: 1, maxWidth: nil, key: CanonicalTypography.namespace + "size",
                         value: .number(20)), "text, buttons and links")
        refuses(.addRule(nodeID: fixture.caption, container: nil, minWidth: 1, maxWidth: nil, key: "content.text", value: .string("x")),
                "visibility, opacity")
        refuses(.setContainerName(nodeID: fixture.caption, name: "label"), "Frame, Section, Stack or Grid")
        refuses(.moveRule(nodeID: fixture.caption, ruleID: rule, offset: 1), "can't move further")
        refuses(.removeRule(nodeID: fixture.caption, ruleID: ContainerQueryRuleID()), "no longer exists")

        let renamed = try run(.setContainerName(nodeID: fixture.panel, name: "board"))
        XCTAssertTrue(renamed.announcement.contains("query container board"))
        _ = try run(.setContainerName(nodeID: fixture.panel, name: nil))
        XCTAssertNil(Q.containerName(of: try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.panel })))
        _ = try run(.removeRule(nodeID: fixture.caption, ruleID: rule))
        XCTAssertFalse(try caption().properties.contains { $0.key.rawValue.hasPrefix(Q.namespace) }, "Removing the last rule leaves nothing behind")
        for _ in 0..<Q.maximumRulesPerNode {
            _ = try run(.addRule(nodeID: fixture.caption, container: nil, minWidth: 1, maxWidth: nil, key: "hidden", value: .boolean(true)))
        }
        refuses(.addRule(nodeID: fixture.caption, container: nil, minWidth: 1, maxWidth: nil, key: "hidden", value: .boolean(true)), "up to 8")

        XCTAssertThrowsError(try ContainerQueryCommandRegistry().prepare(.setContainerName(nodeID: fixture.panel, name: "panel"),
            pageID: page, expectedDocumentID: session.document.id, expectedRevision: session.document.revision - 1,
            document: session.document, isLifecycleAvailable: true)) { XCTAssertTrue($0.localizedDescription.contains("changed")) }
        XCTAssertThrowsError(try ContainerQueryCommandRegistry().prepare(.setContainerName(nodeID: fixture.panel, name: "panel"),
            pageID: page, expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
            document: session.document, isLifecycleAvailable: false, lifecycleDisabledReason: "Close Preview first.")) {
            XCTAssertEqual($0.localizedDescription, "Close Preview first.")
        }
    }

    // SF-0606-001/005: suppressed audit findings are stored on the object as
    // one sorted list of known kinds; every other spelling is rejected; the
    // data needs schema 27; suppressing is one undoable change, refused for
    // objects that exist only inside component copies.
    func testResponsiveAuditSuppressionIsStrictAndOneUndoableChange() throws {
        typealias S = CanonicalResponsiveAuditSuppression
        let fixture = try containerQueryFixture()
        func with(_ value: PropertyValue, key: String = S.suppressedKey) throws -> CanonicalDocument {
            var document = fixture.document
            let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == fixture.caption })
            document.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: key), value: value))
            return document
        }
        XCTAssertNoThrow(try with(.string("collision,truncation")).validate())
        for (label, value, key) in [("unsorted", PropertyValue.string("truncation,collision"), S.suppressedKey),
                                    ("unknown kind", .string("ugly"), S.suppressedKey), ("empty", .string(""), S.suppressedKey),
                                    ("duplicate", .string("collision,collision"), S.suppressedKey),
                                    ("not text", .boolean(true), S.suppressedKey), ("unknown key", .string("collision"), S.namespace + "other")] {
            XCTAssertThrowsError(try with(value, key: key).validate(), label)
        }
        let stored = try with(.string("collision"))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(stored)) as? [String: Any])
        envelope["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)))

        let session = DocumentSession(document: fixture.document)
        func prepare(_ kind: ResponsiveAuditFindingKind, _ suppressed: Bool, node: NodeID? = nil) throws -> DocumentCommand {
            try ResponsiveAuditSuppressionRegistry().prepare(nodeID: node ?? fixture.caption, pageID: fixture.pageID, kind: kind,
                suppressed: suppressed, expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
                document: session.document, isLifecycleAvailable: true)
        }
        func kinds() throws -> Set<String> {
            S.suppressedKinds(of: try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.caption }))
        }
        try session.execute(try prepare(.truncation, true))
        try session.execute(try prepare(.collision, true))
        XCTAssertEqual(try kinds(), ["collision", "truncation"])
        XCTAssertEqual(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.caption })
            .insertionStringProperty(S.suppressedKey), "collision,truncation")
        XCTAssertThrowsError(try prepare(.collision, true)) { XCTAssertTrue($0.localizedDescription.contains("already")) }
        try session.execute(try prepare(.collision, false))
        try session.execute(try prepare(.truncation, false))
        XCTAssertNil(try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.caption }).insertionProperty(S.suppressedKey),
                     "Reporting the last kind again removes the property")
        XCTAssertThrowsError(try prepare(.truncation, false)) { XCTAssertTrue($0.localizedDescription.contains("isn't suppressed")) }
        XCTAssertThrowsError(try prepare(.overflow, true, node: NodeID())) {
            XCTAssertTrue($0.localizedDescription.contains("original component"))
        }
        try session.undo()
        XCTAssertEqual(try kinds(), ["truncation"])
        XCTAssertEqual(S.kinds, ResponsiveAuditFindingKind.allCases.map(\.rawValue).sorted(), "One list of kinds")
    }

    // SF-0605-003 / SF-1204-003 (lane V04 regression; lane V19): text and
    // controls take `display` from compound selectors, so a rule that hides
    // them uses the node attribute's extra specificity in its own block. Its
    // other settings stay in the plain block. A rule that shows writes no
    // `display` (the object keeps its own); a later Show rule that matches
    // stops the earlier hide instead, as the later rule wins on the canvas.
    // On this page without page flow the hide queries the Panel's wrapper by
    // its unique name (`StaticContainerQueryWrapping`).
    func testContainerQueryExportHidesTextAboveItsDisplayRule() throws {
        let fixture = try containerQueryFixture()
        let session = DocumentSession(document: fixture.document)
        let added = try containerQueryEdit(.addRule(nodeID: fixture.caption, container: "panel", minWidth: 1, maxWidth: 499,
                                                    key: "hidden", value: .boolean(true)), page: fixture.pageID, in: session)
        try session.execute(added.command)
        let rule = try XCTUnwrap(added.ruleID)
        try session.execute(try containerQueryEdit(.setValue(nodeID: fixture.caption, ruleID: rule, key: "style.opacity",
                                                             value: .number(0.5)), page: fixture.pageID, in: session).command)
        try session.execute(try containerQueryEdit(.addRule(nodeID: fixture.caption, container: nil, minWidth: 500, maxWidth: nil,
                                                            key: "hidden", value: .boolean(false)), page: fixture.pageID, in: session).command)
        let css = StaticContainerQueryOutputEmitter.emit(pages: [session.document.pages[0]])
        let caption = CanonicalCSSRule.selector(for: fixture.caption)
        let panel = CanonicalCSSRule.selector(for: fixture.panel)
        let panelID = StaticContainerQueryWrapping.identifier(fixture.panel)
        XCTAssertTrue(css.contains("\(panel) { container-type: inline-size; container-name: sf-cq-panel; }"), css)
        XCTAssertTrue(css.contains("[data-siteforge-cq=\"\(panelID)\"] { position:absolute; left:0; top:0; width:500.0px; height:0; "
            + "margin:0; padding:0; border:0; container-type:inline-size; container-name:sf-cq-panel sf-cqid-\(panelID); }"), css)
        let query = "@container sf-cq-panel (min-width: 1px) and (max-width: 499px)"
        XCTAssertTrue(css.contains("\(query) { \(caption) { opacity: 0.5; } }"), css)
        XCTAssertTrue(css.contains("@container sf-cqid-\(panelID) (min-width: 1px) and (max-width: 499px) { "
            + "@container sf-cqid-\(panelID) not ((min-width: 500px)) { \(caption)[data-siteforge-node] { display: none; } } }"), css)
        XCTAssertFalse(css.contains("\(caption) { display: none;"), "A plain hide would lose to the text's own display rule")
        XCTAssertFalse(css.contains("display: block"), "Show keeps the text's own display (flex) instead of forcing block: \(css)")
        // The canvas agrees: on the 500 pt Panel the later Show rule wins; on a
        // 400 pt Panel the hide applies, and the wrapper is 400 px wide.
        let page = session.document.pages[0]
        XCTAssertTrue(CanonicalContainerQueries.evaluated(page, breakpoint: .desktop).page
            .effectiveVisibleNodeIDs(breakpoint: .desktop).contains(fixture.caption))
        var narrow = page
        let panelIndex = try XCTUnwrap(narrow.nodes.firstIndex { $0.id == fixture.panel })
        let widthIndex = try XCTUnwrap(narrow.nodes[panelIndex].properties.firstIndex { $0.key.rawValue == "layout.width" })
        narrow.nodes[panelIndex].properties[widthIndex].value = .number(400)
        XCTAssertFalse(CanonicalContainerQueries.evaluated(narrow, breakpoint: .desktop).page
            .effectiveVisibleNodeIDs(breakpoint: .desktop).contains(fixture.caption))
        XCTAssertTrue(StaticContainerQueryOutputEmitter.emit(pages: [narrow]).contains("width:400.0px;"))
    }

    // OD-143 (ADR-0143, lane V16): rules query the container's content box,
    // inside its padding and border, as `container-type: inline-size` does in
    // browsers. A 500 pt static-layout Panel with a 2 pt border and 24 pt box
    // padding is exported `border-box` 500 px wide with that border and
    // padding, so its content is 448 pt: from 448 applies and from 449 does
    // not, up to 448 applies and up to 447 does not, on the canvas exactly
    // as in the exported CSS. On a connected page a horizontal Stack's 16 pt
    // padding is CSS padding and a box border is an outline, so only the
    // padding counts. A container without padding or border measures its frame.
    func testContainerQueriesMeasureTheContentBoxInsidePaddingAndBorderLikeBrowsers() throws {
        typealias Q = CanonicalContainerQueries
        let plain = try containerQueryFixture()
        let plainPanel = try XCTUnwrap(plain.document.pages[0].nodes.first { $0.id == plain.panel })
        XCTAssertEqual(Q.contentInset(of: plainPanel, on: plain.document.pages[0], breakpoint: .desktop), 0,
                       "No padding or border: the frame is the content box")

        var fixture = try containerQueryFixture()
        let panelIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.panel })
        let box = DesignBoxStyleCommandRegistry.namespace
        fixture.document.pages[0].nodes[panelIndex].properties += [
            ("border.width", PropertyValue.number(2)), ("border.style", .string("solid")),
            ("border.color.red", .number(0)), ("border.color.green", .number(0)), ("border.color.blue", .number(0)),
            ("border.color.alpha", .number(1)), ("padding.uniform", .number(24)),
        ].map { NodeProperty(key: .init(rawValue: box + $0.0), value: $0.1, origin: .authored) }
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        func add(_ node: NodeID, container: String, min: Double?, max: Double?) throws -> ContainerQueryRuleID {
            let prepared = try containerQueryEdit(.addRule(nodeID: node, container: container, minWidth: min, maxWidth: max,
                                                           key: "style.opacity", value: .number(0.5)),
                                                  page: fixture.pageID, in: session)
            try session.execute(prepared.command)
            return try XCTUnwrap(prepared.ruleID)
        }
        let rules = try [add(fixture.caption, container: "panel", min: 448, max: nil),
                         add(fixture.caption, container: "panel", min: 449, max: nil),
                         add(fixture.caption, container: "panel", min: nil, max: 448),
                         add(fixture.caption, container: "panel", min: nil, max: 447)]
        let page = session.document.pages[0]
        XCTAssertFalse(page.usesConnectedOutput)
        let panel = try XCTUnwrap(page.nodes.first { $0.id == fixture.panel })
        XCTAssertEqual(Q.contentInset(of: panel, on: page, breakpoint: .desktop), 52, "2 × (2 pt border + 24 pt padding)")
        let evaluated = Q.evaluated(page, breakpoint: .desktop, styleSource: session.document)
        let statuses = try XCTUnwrap(evaluated.evaluation.statuses[fixture.caption])
        XCTAssertEqual(statuses.map(\.ruleID), rules)
        XCTAssertEqual(statuses.map(\.containerWidth), [448, 448, 448, 448])
        XCTAssertEqual(statuses.map(\.matches), [true, false, true, false])
        XCTAssertEqual(Q.evaluated(page, breakpoint: .desktop, styleSource: session.document).evaluation, evaluated.evaluation,
                       "Deterministic")

        // The exported site gives the browser the same 448 pt content box.
        let plan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let selector = CanonicalCSSRule.selector(for: fixture.panel)
        let caption = CanonicalCSSRule.selector(for: fixture.caption)
        let layout = try XCTUnwrap(css.components(separatedBy: "\n").first { $0.hasPrefix(selector + " { box-sizing: border-box;") }, css)
        XCTAssertTrue(layout.contains(" width: 500.0px;"), layout)
        XCTAssertTrue(css.contains("\(selector) { border: 2.0px solid rgba(0.0, 0.0, 0.0, 1.0); padding: 24.0px; }"), css)
        XCTAssertTrue(css.contains("\(selector) { container-type: inline-size; container-name: sf-cq-panel; }"), css)
        for condition in ["(min-width: 448px)", "(min-width: 449px)", "(max-width: 448px)", "(max-width: 447px)"] {
            XCTAssertTrue(css.contains("@container sf-cq-panel \(condition) { \(caption) { opacity: 0.5; } }"), condition)
        }

        // Connected page: the Row's 16 pt layout padding is its CSS padding.
        var connected = session.document
        let rowIndex = try XCTUnwrap(connected.pages[0].nodes.firstIndex { $0.id == fixture.row })
        connected.pages[0].nodes[rowIndex].properties.removeAll { $0.key.rawValue == "layout.padding" }
        connected.pages[0].nodes[rowIndex].properties += [
            NodeProperty(key: .init(rawValue: "layout.padding"), value: .number(16), origin: .authored),
            NodeProperty(key: .init(rawValue: Q.containerKey), value: .string("row"), origin: .authored),
            NodeProperty(key: .init(rawValue: CanonicalSizingConstraints.prefix + "heightMode"), value: .string("hug"), origin: .authored),
        ]
        try connected.validate()
        try session.establishBaseline(connected)
        let chipRules = try [add(fixture.chip, container: "row", min: 268, max: nil),
                             add(fixture.chip, container: "row", min: 269, max: nil)]
        let connectedPage = session.document.pages[0]
        XCTAssertTrue(connectedPage.usesConnectedOutput)
        let row = try XCTUnwrap(connectedPage.nodes.first { $0.id == fixture.row })
        XCTAssertEqual(Q.contentInset(of: row, on: connectedPage, breakpoint: .desktop), 32, "2 × 16 pt padding")
        let connectedPanel = try XCTUnwrap(connectedPage.nodes.first { $0.id == fixture.panel })
        XCTAssertEqual(Q.contentInset(of: connectedPanel, on: connectedPage, breakpoint: .desktop), 0,
                       "Connected output draws the border as an outline and gives a fixed-height Frame no CSS padding")
        let rowWidth = try XCTUnwrap(connectedPage.resolvedStructuralGeometry(breakpoint: .desktop, viewportWidth: nil)[fixture.row]?.size.width)
        XCTAssertEqual(rowWidth, 300, "A fixed width stays fixed")
        let chipStatuses = try XCTUnwrap(Q.evaluated(connectedPage, breakpoint: .desktop).evaluation.statuses[fixture.chip])
        XCTAssertEqual(chipStatuses.map(\.ruleID), chipRules)
        XCTAssertEqual(chipStatuses.map(\.containerWidth), [268, 268])
        XCTAssertEqual(chipStatuses.map(\.matches), [true, false])
        let connectedCSS = ConnectedPageOutput.css(pages: [connectedPage])
        let rowSelector = CanonicalCSSRule.selector(for: fixture.row)
        XCTAssertTrue(connectedCSS.components(separatedBy: "\n").contains {
            $0.hasPrefix(rowSelector + " { ") && $0.contains(";box-sizing:border-box;") && $0.contains(";padding:16.0px;")
        }, connectedCSS)
    }

    // Lane V19 (owner decision 2026-11-26 9:55 PM EST, ADR-0031): on a page
    // without page flow every object is its own absolutely placed element, so
    // a queried container's contents are written inside a wrapper directly
    // after the container's element. The wrapper is the container's content
    // box for queries (500 pt Panel with a 2 pt border and 24 pt padding:
    // 448 pt; 400 pt on tablets: 348 pt), at the page corner with no height,
    // so nothing moves: without the wrapper tags the page is the page without
    // rules, and every rule written for the page without rules, positions
    // included, is still written unchanged. The canvas measures the same
    // widths, and a page without rules gets no wrapper.
    func testStaticLayoutContainerQueriesWrapQueriedContentsWithoutMovingAnything() throws {
        typealias Q = CanonicalContainerQueries
        var fixture = try containerQueryFixture()
        let panelIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.panel })
        let box = DesignBoxStyleCommandRegistry.namespace
        fixture.document.pages[0].nodes[panelIndex].properties += [
            ("border.width", PropertyValue.number(2)), ("border.style", .string("solid")),
            ("border.color.red", .number(0)), ("border.color.green", .number(0)), ("border.color.blue", .number(0)),
            ("border.color.alpha", .number(1)), ("padding.uniform", .number(24)),
        ].map { NodeProperty(key: .init(rawValue: box + $0.0), value: $0.1, origin: .authored) }
        fixture.document.pages[0].nodes[panelIndex].properties.append(NodeProperty(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .tablet)), value: .number(400), origin: .authored))
        try fixture.document.validate()
        let unqueried = fixture.document
        let session = DocumentSession(document: fixture.document)
        try session.execute(try containerQueryEdit(.addRule(nodeID: fixture.caption, container: "panel", minWidth: 448, maxWidth: nil,
                                                            key: "style.opacity", value: .number(0.5)),
                                                   page: fixture.pageID, in: session).command)
        let page = session.document.pages[0]
        XCTAssertFalse(page.usesConnectedOutput)
        let desktop = try XCTUnwrap(Q.evaluated(page, breakpoint: .desktop, styleSource: session.document)
            .evaluation.statuses[fixture.caption]?.first)
        XCTAssertEqual(desktop.containerWidth, 448)
        XCTAssertTrue(desktop.matches)
        let tablet = try XCTUnwrap(Q.evaluated(page, breakpoint: .tablet, styleSource: session.document)
            .evaluation.statuses[fixture.caption]?.first)
        XCTAssertEqual(tablet.containerWidth, 348)
        XCTAssertFalse(tablet.matches)

        func builtQueryPage(_ document: CanonicalDocument) throws -> (html: String, css: String) {
            let plan = try MultiPageStaticBuildPlanner.plan(document: document)
            return (try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents),
                    try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents))
        }
        let before = try builtQueryPage(unqueried)
        let after = try builtQueryPage(session.document)
        XCTAssertFalse(before.html.contains("data-siteforge-cq"), "A page without rules gets no wrapper")
        XCTAssertFalse(before.css.contains("data-siteforge-cq"), before.css)
        let id = StaticContainerQueryWrapping.identifier(fixture.panel)
        let tag = "<div data-siteforge-cq=\"\(id)\">"
        func position(_ text: String) throws -> String.Index { try XCTUnwrap(after.html.range(of: text)?.lowerBound, text) }
        func element(_ node: NodeID) -> String { "data-siteforge-node=\"\(StaticContainerQueryWrapping.identifier(node))\"" }
        let wrapper = try position("\n" + tag + "\n")
        XCTAssertLessThan(try position(element(fixture.panel)), wrapper, "The wrapper follows the Panel")
        XCTAssertLessThan(wrapper, try position(element(fixture.caption)))
        XCTAssertLessThan(try position(element(fixture.caption)), try position(element(fixture.row)))
        XCTAssertLessThan(try position(element(fixture.row)), try position(element(fixture.chip)))
        XCTAssertLessThan(try position(element(fixture.chip)), try position("\n</div>"), "The Chip is inside the wrapper")
        XCTAssertEqual(after.html.replacingOccurrences(of: "\n" + tag, with: "").replacingOccurrences(of: "\n</div>", with: ""),
                       before.html, "Without the wrapper tags the page is unchanged: same elements, order and attributes")
        let beforeLines = Set(before.css.components(separatedBy: "\n"))
        let afterLines = Set(after.css.components(separatedBy: "\n"))
        XCTAssertTrue(beforeLines.isSubset(of: afterLines), "Every rule of the page without rules, positions included, is unchanged")
        let selector = "[data-siteforge-cq=\"\(id)\"]"
        let caption = CanonicalCSSRule.selector(for: fixture.caption)
        XCTAssertEqual(afterLines.subtracting(beforeLines), [
            "\(selector) { position:absolute; left:0; top:0; width:448.0px; height:0; margin:0; padding:0; border:0; "
                + "container-type:inline-size; container-name:sf-cq-panel sf-cqid-\(id); }",
            "@media (min-width: 600px) and (width < 1024px) { \(selector) { width:348.0px; } }",
            "@container sf-cq-panel (min-width: 448px) { \(caption) { opacity: 0.5; } }",
        ], after.css)
    }

    // Lane V19 (ADR-0031): nested containers each get a wrapper inside the
    // outer one; an unnamed rule queries the nearest wrapper and a named rule
    // the named one, as on the canvas. A container an interaction hides
    // (ADR-0065) hides the wrappers that hold its contents, whose contents
    // still name it for the runtimes. Every language tree (right to left too)
    // and Static Release (minified CSS, integrity manifest) keep the wrappers.
    func testStaticLayoutContainerQueryWrappersNestFollowInteractionsLanguagesAndRelease() throws {
        typealias Q = CanonicalContainerQueries
        var fixture = try containerQueryFixture()
        let rowIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.row })
        fixture.document.pages[0].nodes[rowIndex].properties.append(
            NodeProperty(key: .init(rawValue: Q.containerKey), value: .string("row"), origin: .authored))
        let captionIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.caption })
        fixture.document.pages[0].nodes[captionIndex].properties += CanonicalEventGraph(interactions: [
            CanonicalInteraction(id: UUID(), trigger: .focusIn, actions: [CanonicalInteraction.Action(kind: .hide, target: fixture.panel)]),
        ]).properties.sorted { $0.key < $1.key }.map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value) }
        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        _ = try SiteLocalizationEditing.addLocale(code: "ar", name: "العربية", to: &localization)
        fixture.document.localization = localization
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        func addQueryRule(_ node: NodeID, _ container: String?, min: Double) throws -> ContainerQueryRuleID {
            let prepared = try containerQueryEdit(.addRule(nodeID: node, container: container, minWidth: min, maxWidth: nil,
                                                           key: "style.opacity", value: .number(0.5)), page: fixture.pageID, in: session)
            try session.execute(prepared.command)
            return try XCTUnwrap(prepared.ruleID)
        }
        _ = try addQueryRule(fixture.caption, nil, min: 400)
        let nearest = try addQueryRule(fixture.chip, nil, min: 200)
        let named = try addQueryRule(fixture.chip, "panel", min: 450)
        let page = session.document.pages[0]
        let chipStatuses = try XCTUnwrap(Q.evaluated(page, breakpoint: .desktop).evaluation.statuses[fixture.chip])
        XCTAssertEqual(chipStatuses.map(\.ruleID), [nearest, named])
        XCTAssertEqual(chipStatuses.map(\.containerID), [fixture.row, fixture.panel])
        XCTAssertEqual(chipStatuses.map(\.containerWidth), [300, 500])
        XCTAssertEqual(chipStatuses.map(\.matches), [true, true])

        let plan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        func file(_ path: String) throws -> String { try XCTUnwrap(plan.files.first { $0.path == path }?.contents, path) }
        let html = try file("index.html"), css = try file("styles.css")
        let panelID = StaticContainerQueryWrapping.identifier(fixture.panel)
        let rowID = StaticContainerQueryWrapping.identifier(fixture.row)
        let panelTag = "<div data-siteforge-cq=\"\(panelID)\" data-siteforge-cq-within=\"\(panelID)\">"
        let rowTag = "<div data-siteforge-cq=\"\(rowID)\" data-siteforge-cq-within=\"\(panelID)\">"
        func position(_ text: String) throws -> String.Index { try XCTUnwrap(html.range(of: text)?.lowerBound, text) }
        func element(_ node: NodeID) -> String { "data-siteforge-node=\"\(StaticContainerQueryWrapping.identifier(node))\"" }
        XCTAssertLessThan(try position(element(fixture.panel)), try position("\n" + panelTag + "\n"))
        XCTAssertLessThan(try position("\n" + panelTag + "\n"), try position(element(fixture.caption)))
        XCTAssertLessThan(try position(element(fixture.row)), try position("\n" + rowTag + "\n"))
        XCTAssertLessThan(try position("\n" + rowTag + "\n"), try position(element(fixture.chip)))
        let chipStart = try position(element(fixture.chip))
        XCTAssertNotNil(html.range(of: "\n</div>\n</div>", range: chipStart..<html.endIndex), "Both wrappers close after the Chip")
        let chipTagEnd = try XCTUnwrap(html.range(of: ">", range: chipStart..<html.endIndex)).lowerBound
        XCTAssertTrue(html[chipStart..<chipTagEnd].contains("data-siteforge-within=\"\(panelID)\""),
                      "Contents still name the container for the runtimes: \(html)")

        let caption = CanonicalCSSRule.selector(for: fixture.caption), chip = CanonicalCSSRule.selector(for: fixture.chip)
        XCTAssertTrue(css.contains("[data-siteforge-cq=\"\(rowID)\"] { position:absolute; left:0; top:0; width:300.0px; height:0; margin:0; "
            + "padding:0; border:0; container-type:inline-size; container-name:sf-cq-row sf-cqid-\(rowID); }"), css)
        XCTAssertTrue(css.contains("[data-siteforge-cq=\"\(panelID)\"] { position:absolute; left:0; top:0; width:500.0px; height:0; margin:0; "
            + "padding:0; border:0; container-type:inline-size; container-name:sf-cq-panel sf-cqid-\(panelID); }"), css)
        XCTAssertTrue(css.contains("@container (min-width: 400px) { \(caption) { opacity: 0.5; } }"), css)
        XCTAssertTrue(css.contains("@container (min-width: 200px) { \(chip) { opacity: 0.5; } }"), css)
        XCTAssertTrue(css.contains("@container sf-cq-panel (min-width: 450px) { \(chip) { opacity: 0.5; } }"), css)
        XCTAssertTrue(css.contains("[data-siteforge-node=\"\(panelID)\"][hidden] ~ [data-siteforge-cq-within~=\"\(panelID)\"] "
            + "{ display:none !important; }"), css)
        XCTAssertTrue(css.contains("[data-siteforge-node=\"\(panelID)\"][hidden] ~ [data-siteforge-within~=\"\(panelID)\"] "
            + "{ display:none !important; }"), "ADR-0065's own rule is unchanged")

        let arabic = try file("ar/index.html")
        XCTAssertTrue(arabic.contains(" dir=\"rtl\""), arabic)
        XCTAssertTrue(arabic.contains("\n" + panelTag + "\n") && arabic.contains("\n" + rowTag + "\n"),
                      "The right-to-left tree uses the same wrappers (left:0 is physical, so nothing mirrors twice): \(arabic)")

        let release = LocalBuildProfileCompiler.compile(plan, profile: .staticRelease)
        let releaseCSS = try XCTUnwrap(release.0.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertEqual(release.1.cssReports.first { $0.path == "styles.css" }?.isOptimized, true)
        for line in css.components(separatedBy: "\n") where line.contains("data-siteforge-cq") || line.hasPrefix("@container") {
            XCTAssertTrue(releaseCSS.contains(StaticCSSOptimizer.minify(line)), line)
        }
        let releaseHTML = try XCTUnwrap(release.0.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(releaseHTML.contains(panelTag) && releaseHTML.contains(rowTag), releaseHTML)
        let manifest = try XCTUnwrap(release.0.files.first { $0.path == StaticOutputManifest.fileName }?.contents)
        XCTAssertTrue(manifest.contains(ProjectResourceStore.digest(Data(releaseHTML.utf8))), manifest)
    }

    // Lane V19 (ADR-0031): an object that keeps its own stacking layer (or
    // position, or an overlay) needs the page as its containing block, so it
    // is never moved into a wrapper, and on a page without page flow a
    // container holding one can't be queried: the canvas reports it and
    // applies nothing, and export writes no wrapper and no rule, so canvas
    // and browser agree.
    func testStaticLayoutContainerHoldingAPositionedObjectIsNotQueried() throws {
        typealias Q = CanonicalContainerQueries
        var fixture = try containerQueryFixture()
        let chipIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.chip })
        fixture.document.pages[0].nodes[chipIndex].properties.append(
            NodeProperty(key: .init(rawValue: CanonicalPositioning.namespace + "zIndex"), value: .number(2), origin: .authored))
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        let prepared = try containerQueryEdit(.addRule(nodeID: fixture.caption, container: "panel", minWidth: 1, maxWidth: nil,
                                                       key: "style.opacity", value: .number(0.5)), page: fixture.pageID, in: session)
        try session.execute(prepared.command)
        let rule = try XCTUnwrap(prepared.ruleID)
        let page = session.document.pages[0]
        XCTAssertEqual(StaticContainerQueryWrapping.pinnedNodeIDs(page), [fixture.chip])
        XCTAssertEqual(StaticContainerQueryWrapping.unqueryableContainers(page), [fixture.panel])
        let evaluation = Q.evaluated(page, breakpoint: .desktop).evaluation
        XCTAssertTrue(evaluation.findings.contains(.containerHoldsPositioned(containerID: fixture.panel)))
        XCTAssertTrue(evaluation.findings.contains(.noContainer(nodeID: fixture.caption, ruleID: rule)))
        XCTAssertNil(evaluation.statuses[fixture.caption]?.first?.containerID)
        XCTAssertNil(evaluation.winners[fixture.caption])
        XCTAssertEqual(ContainerQueryFinding.containerHoldsPositioned(containerID: fixture.panel).code, "container-query-container-positioned")
        let plan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertFalse(html.contains("data-siteforge-cq"), html)
        XCTAssertFalse(css.contains("data-siteforge-cq"), css)
        XCTAssertFalse(css.contains("@container"), "No rule is written that the browser could apply: \(css)")
        XCTAssertTrue(css.contains("\(CanonicalCSSRule.selector(for: fixture.chip)) { z-index: 2; }"), css)
    }

    // Lane V19 (owner decision 2026-11-26 9:55 PM EST, ADR-0143): Show writes
    // no `display`, so Text keeps its flex box, a Button its flex control and
    // a horizontal Stack its flex row. On a page without page flow it reveals
    // an object hidden at phone width: the phone hide holds only while the
    // Show rule doesn't match, and the layout rule no longer hides it first;
    // the canvas shows it exactly when the rule matches (a 500 pt Panel; on a
    // 250 pt phone Panel it stays hidden). On a page with page flow an object
    // hidden at a breakpoint has no layout there, so canvas and export keep it
    // hidden and say why.
    func testContainerQueryShowRevealsHiddenObjectsAndKeepsTheirOwnDisplay() throws {
        typealias Q = CanonicalContainerQueries
        var fixture = try containerQueryFixture()
        let action = NodeID()
        let panelIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.panel })
        fixture.document.pages[0].nodes[panelIndex].childIDs.append(action)
        fixture.document.pages[0].nodes.append(DocumentNode(id: action, kind: .button, name: "Go", parent: .node(fixture.panel),
            properties: [("layout.x", 260.0), ("layout.y", 10.0), ("layout.width", 120.0), ("layout.height", 40.0)]
                .map { NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1)) }
                + [NodeProperty(key: .init(rawValue: "content.text"), value: .string("Go"))]))
        let captionIndex = try XCTUnwrap(fixture.document.pages[0].nodes.firstIndex { $0.id == fixture.caption })
        fixture.document.pages[0].nodes[captionIndex].properties.append(
            NodeProperty(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(false), origin: .authored))
        try fixture.document.validate()
        let session = DocumentSession(document: fixture.document)
        func showRule(_ node: NodeID, _ container: String?, min: Double) throws -> ContainerQueryRuleID {
            let prepared = try containerQueryEdit(.addRule(nodeID: node, container: container, minWidth: min, maxWidth: nil,
                                                           key: "hidden", value: .boolean(false)), page: fixture.pageID, in: session)
            try session.execute(prepared.command)
            return try XCTUnwrap(prepared.ruleID)
        }
        _ = try showRule(fixture.caption, "panel", min: 300)
        _ = try showRule(action, nil, min: 1)
        let page = session.document.pages[0]
        XCTAssertFalse(page.usesConnectedOutput)
        XCTAssertFalse(page.effectiveVisibleNodeIDs(breakpoint: .mobile).contains(fixture.caption), "Hidden at phone width")
        XCTAssertTrue(Q.evaluated(page, breakpoint: .mobile).page.effectiveVisibleNodeIDs(breakpoint: .mobile).contains(fixture.caption),
                      "The 500 pt Panel matches, so Show reveals the Caption on phones")
        var narrow = page
        let narrowPanel = try XCTUnwrap(narrow.nodes.firstIndex { $0.id == fixture.panel })
        narrow.nodes[narrowPanel].properties.append(NodeProperty(
            key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .mobile)), value: .number(250), origin: .authored))
        XCTAssertFalse(Q.evaluated(narrow, breakpoint: .mobile).page.effectiveVisibleNodeIDs(breakpoint: .mobile).contains(fixture.caption),
                       "A 250 pt Panel doesn't match, so the Caption stays hidden")

        let plan = try MultiPageStaticBuildPlanner.plan(document: session.document)
        let css = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        let caption = CanonicalCSSRule.selector(for: fixture.caption), button = CanonicalCSSRule.selector(for: action)
        let panelID = StaticContainerQueryWrapping.identifier(fixture.panel)
        XCTAssertTrue(css.contains("@media (width < 600px) { @container sf-cqid-\(panelID) not ((min-width: 300px)) { "
            + "\(caption)[data-siteforge-node] { display:none; } } }"), css)
        XCTAssertFalse(css.contains("@media (width < 600px) { \(caption)[data-siteforge-node] { display:none; }"),
                       "No phone hide that Show couldn't lift")
        XCTAssertTrue(css.contains("\(caption) { display: block; }"), "The phone layout rule leaves hiding to the rule above: \(css)")
        XCTAssertFalse(css.contains("\(caption) { display: none; }"), css)
        XCTAssertTrue(css.contains("\(caption)[data-siteforge-node] { display:flex;"), "Text keeps its own display")
        XCTAssertTrue(css.contains("\(button):is(a,button) { display:flex;"), "The Button keeps its own display")
        XCTAssertFalse(css.components(separatedBy: "\n").contains { $0.hasPrefix("@container") && $0.contains("display") },
                       "Show writes no display: \(css)")

        // A page with page flow: the Row is a flex row; Show keeps it, and an
        // object hidden on phones there has no layout to be shown in.
        var connected = session.document
        let rowIndex = try XCTUnwrap(connected.pages[0].nodes.firstIndex { $0.id == fixture.row })
        connected.pages[0].nodes[rowIndex].properties += [
            NodeProperty(key: .init(rawValue: Q.containerKey), value: .string("row"), origin: .authored),
            NodeProperty(key: .init(rawValue: CanonicalSizingConstraints.prefix + "heightMode"), value: .string("hug"), origin: .authored),
        ]
        let chipIndex = try XCTUnwrap(connected.pages[0].nodes.firstIndex { $0.id == fixture.chip })
        connected.pages[0].nodes[chipIndex].properties.append(
            NodeProperty(key: .init(rawValue: ResponsiveVisibilityResolver.key(.mobile)), value: .boolean(false), origin: .authored))
        try connected.validate()
        try session.establishBaseline(connected)
        _ = try showRule(fixture.row, "panel", min: 1)
        let chipRule = try showRule(fixture.chip, "row", min: 1)
        let connectedPage = session.document.pages[0]
        XCTAssertTrue(connectedPage.usesConnectedOutput)
        let queries = StaticContainerQueryOutputEmitter.emit(pages: [connectedPage])
        XCTAssertFalse(queries.contains("display"), "Show writes no display on a page with page flow either: \(queries)")
        let rowSelector = CanonicalCSSRule.selector(for: fixture.row)
        XCTAssertTrue(ConnectedPageOutput.css(pages: [connectedPage]).components(separatedBy: "\n").contains {
            $0.hasPrefix(rowSelector + " { ") && $0.contains("display:flex")
        }, "The Row keeps its flex row")
        let phone = Q.evaluated(connectedPage, breakpoint: .mobile)
        XCTAssertEqual(phone.evaluation.statuses[fixture.chip]?.first?.matches, true)
        XCTAssertTrue(phone.evaluation.findings.contains(.showWithoutLayout(nodeID: fixture.chip, ruleID: chipRule)))
        XCTAssertFalse(phone.page.effectiveVisibleNodeIDs(breakpoint: .mobile).contains(fixture.chip),
                       "The canvas keeps it hidden, as the exported page does")
        XCTAssertEqual(ContainerQueryFinding.showWithoutLayout(nodeID: fixture.chip, ruleID: chipRule).code,
                       "container-query-show-without-layout")
    }

    // SF-0605-008 / SF-0606-008 (lane V04): container-query edits, audit runs
    // and cancellation leave one sanitized diagnostic each: requirement,
    // operation, stable identities, a count, timing and a failure category,
    // never names or values.
    func testContainerQueryAndAuditDiagnosticsAreSanitizedAndCategorized() async throws {
        let fixture = try containerQueryFixture()
        let session = DocumentSession(document: fixture.document)
        let state = WorkspaceShellState(documentSession: session)
        XCTAssertTrue(state.performContainerQueryEdit(.setContainerName(nodeID: fixture.panel, name: "board")))
        let renamed = try XCTUnwrap(state.lastResponsiveAuthoringDiagnostic)
        XCTAssertEqual(renamed.requirementID, "SF-0605-002")
        XCTAssertEqual(renamed.operation, "container-query.container.set")
        func hashed(_ raw: String) -> String {
            DiagnosticStableIdentifier.sanitize(raw, domain: .document, kind: "responsive-target")
        }
        XCTAssertEqual(renamed.identifiers, [hashed(fixture.panel.description)])
        XCTAssertFalse(String(describing: renamed).contains(fixture.panel.description), "Identities are hashed")
        XCTAssertEqual(renamed.failureCategory, "none")
        XCTAssertGreaterThanOrEqual(renamed.durationMilliseconds, 0)
        XCTAssertFalse(String(describing: renamed).contains("board"), "Names are content, not diagnostics")
        XCTAssertFalse(state.performContainerQueryEdit(.setContainerName(nodeID: fixture.caption, name: "label")))
        XCTAssertEqual(state.lastResponsiveAuthoringDiagnostic?.operation, "container-query.container.set")
        XCTAssertEqual(state.lastResponsiveAuthoringDiagnostic?.failureCategory, "refused")

        state.runResponsiveAudit()
        let deadline = ContinuousClock.now + .seconds(30)
        while state.isRunningResponsiveAudit {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderReadCorrupt) }
            try await Task.sleep(for: .milliseconds(10))
        }
        let audit = try XCTUnwrap(state.lastResponsiveAuthoringDiagnostic)
        XCTAssertEqual(audit.requirementID, "SF-0606-003")
        XCTAssertEqual(audit.operation, "responsive-audit.run")
        XCTAssertEqual(audit.identifiers, [hashed(fixture.pageID.description)])
        XCTAssertEqual(audit.findingCount, state.currentResponsiveAuditReport?.findings.count)
        XCTAssertEqual(audit.failureCategory, "none")

        state.runResponsiveAudit()
        state.cancelResponsiveAudit()
        XCTAssertFalse(state.isRunningResponsiveAudit)
        XCTAssertEqual(state.lastResponsiveAuthoringDiagnostic?.operation, "responsive-audit.cancel")
        XCTAssertEqual(state.lastResponsiveAuthoringDiagnostic?.failureCategory, "cancelled")
        XCTAssertEqual(ResponsiveAuthoringDiagnostic.category(for: WorkspaceScenePreparationError.cancelled), "cancelled")
        XCTAssertEqual(ResponsiveAuthoringDiagnostic.category(for: CommandExecutionError.revisionExhausted), "revision-exhausted")
        XCTAssertEqual(ResponsiveAuthoringDiagnostic.category(for: nil), "none")
    }

    // SF-0704-001/003: the trace lists each source of a setting in the
    // engine's own order and the last one is what the canvas shows: Desktop,
    // then smooth scaling, then the breakpoint's own value, then a matching
    // container-query rule; opacity goes default, linked styles, own value.
    // SF-0704-002/005: clearing the winner is one undoable command that
    // reveals the next source; required Desktop geometry, defaults and linked
    // values are refused with a reason.
    func testValueTraceMatchesEnginePrecedenceAndClearsTheWinnerInOneStep() throws {
        typealias Q = CanonicalContainerQueries
        var fixture = try containerQueryFixture()
        let session = DocumentSession(document: fixture.document)
        let page = fixture.pageID
        func caption() throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.caption }) }
        func trace(_ setting: ValueTraceSetting, _ breakpoint: ResponsiveBreakpoint = .tablet) throws -> ValueTrace {
            let evaluation = Q.evaluated(session.document.pages[0], breakpoint: breakpoint).evaluation
            return CanonicalValueTrace.trace(setting, node: try caption(), breakpoint: breakpoint, viewportWidth: 768,
                                             containerQueries: evaluation, styles: try CanonicalReusableStyleIndex(document: session.document))
        }
        XCTAssertEqual(ValueTraceSetting.applicable(to: try caption()),
                       [.x, .y, .width, .height, .visibility, .opacity, .textSize, .lineHeight])
        let base = try trace(.width)
        XCTAssertEqual(base.steps.map(\.source), [.desktop])
        XCTAssertFalse(base.canClearWinner)
        XCTAssertThrowsError(try CanonicalValueTrace.clearWinner(base, pageID: page, document: session.document,
            expectedRevision: session.document.revision, isLifecycleAvailable: true)) {
            XCTAssertTrue($0.localizedDescription.contains("Desktop geometry is required"))
        }

        // Tablet's own width, then a matching container-query rule on top.
        var tablet = session.document
        let index = try XCTUnwrap(tablet.pages[0].nodes.firstIndex { $0.id == fixture.caption })
        tablet.pages[0].nodes[index].properties.append(.init(key: .init(rawValue: ResponsiveGeometryResolver.key(.width, breakpoint: .tablet)),
                                                             value: .number(150)))
        try session.establishBaseline(tablet)
        try session.execute(try containerQueryEdit(.addRule(nodeID: fixture.caption, container: nil, minWidth: 1, maxWidth: nil,
                                                            key: "layout.width", value: .number(180)), page: page, in: session).command)
        fixture.document = session.document
        let layered = try trace(.width)
        XCTAssertEqual(layered.steps.map { CanonicalValueTrace.describe($0.value, setting: .width) }, ["200", "150", "180"])
        XCTAssertEqual(layered.steps.map(\.sourceTitle), ["Set here · Desktop", "Set here · Tablet", "Container query rule"])
        let drawn = Q.evaluated(session.document.pages[0], breakpoint: .tablet).page.nodes.first { $0.id == fixture.caption }
        XCTAssertEqual(drawn.flatMap { ResponsiveGeometryResolver.value(for: .width, node: $0, breakpoint: .tablet)?.0 }, 180,
                       "The trace's winner is what the engine resolves")
        XCTAssertTrue(layered.canClearWinner)
        try session.execute(try CanonicalValueTrace.clearWinner(layered, pageID: page, document: session.document,
            expectedRevision: session.document.revision, isLifecycleAvailable: true))
        XCTAssertTrue(try Q.rules(on: caption()).isEmpty, "The rule's only value: the rule is removed")
        XCTAssertEqual(try trace(.width).winner?.source, .breakpoint(.tablet))
        try session.execute(try CanonicalValueTrace.clearWinner(try trace(.width), pageID: page, document: session.document,
            expectedRevision: session.document.revision, isLifecycleAvailable: true))
        XCTAssertEqual(try trace(.width).winner?.source, .desktop)
        try session.undo()
        XCTAssertEqual(try trace(.width).winner?.source, .breakpoint(.tablet), "One Undo restores one cleared value")

        // Visibility: Desktop, then Tablet's own value.
        var hidden = session.document
        let hiddenIndex = try XCTUnwrap(hidden.pages[0].nodes.firstIndex { $0.id == fixture.caption })
        hidden.pages[0].nodes[hiddenIndex].properties.append(.init(key: .init(rawValue: ResponsiveVisibilityResolver.key(.tablet)),
                                                                   value: .boolean(false)))
        try session.establishBaseline(hidden)
        XCTAssertEqual(try trace(.visibility).steps.map { CanonicalValueTrace.describe($0.value, setting: .visibility) },
                       ["Shown", "Hidden"])
        XCTAssertEqual(try trace(.visibility, .desktop).steps.count, 1, "Desktop ignores Tablet's value")

        // Opacity and text size start at the default, which can't be cleared.
        let opacity = try trace(.opacity)
        XCTAssertEqual(opacity.steps.map(\.source), [.defaultValue])
        XCTAssertEqual(CanonicalValueTrace.describe(opacity.steps[0].value, setting: .opacity), "100%")
        XCTAssertThrowsError(try CanonicalValueTrace.clearWinner(opacity, pageID: page, document: session.document,
            expectedRevision: session.document.revision, isLifecycleAvailable: true)) {
            XCTAssertTrue($0.localizedDescription.contains("default"))
        }
        XCTAssertEqual(try trace(.textSize).winner?.value, .number(CanonicalTypography.defaultValue.size))
        XCTAssertThrowsError(try CanonicalValueTrace.clearWinner(try trace(.height), pageID: page, document: session.document,
            expectedRevision: session.document.revision - 1, isLifecycleAvailable: true)) {
            XCTAssertTrue($0.localizedDescription.contains("changed"))
        }
    }

    // SF-0704-003/008, SF-0605-003, SF-0807-008 (ADR-0144): a width that
    // layout places wins over the stored values and can't be cleared here;
    // smooth scaling can't be added under a container-query rule for the
    // same setting (canvas and CSS would disagree); Clear Winning Value and
    // asset-dependency edits leave identity-only diagnostics.
    func testValueTraceLayoutWinnerFluidRuleConflictAndDiagnosticsStayTruthful() throws {
        let fixture = try containerQueryFixture()
        let session = DocumentSession(document: fixture.document)
        let page = fixture.pageID
        func caption() throws -> DocumentNode { try XCTUnwrap(session.document.pages[0].nodes.first { $0.id == fixture.caption }) }
        let placed = CanonicalValueTrace.trace(.width, node: try caption(), breakpoint: .desktop, viewportWidth: 1280,
            containerQueries: .empty, styles: nil, layout: (value: 460, source: "Computed by Fill"))
        XCTAssertEqual(placed.steps.map(\.source), [.desktop, .layout("Computed by Fill")])
        XCTAssertEqual(placed.winner?.value, .number(460))
        XCTAssertEqual(placed.winner?.sourceTitle, "Computed by Fill")
        XCTAssertFalse(placed.canClearWinner)
        XCTAssertThrowsError(try CanonicalValueTrace.clearWinner(placed, pageID: page, document: session.document,
            expectedRevision: session.document.revision, isLifecycleAvailable: true)) {
            XCTAssertTrue($0.localizedDescription.contains("Layout places this value"))
        }
        XCTAssertEqual(CanonicalValueTrace.trace(.width, node: try caption(), breakpoint: .desktop, viewportWidth: 1280,
            containerQueries: .empty, styles: nil).steps.map(\.source), [.desktop], "Without layout the stored value wins")

        // A rule sets the caption's text size: smooth scaling for that setting is refused, others are not.
        try session.execute(try containerQueryEdit(.addRule(nodeID: fixture.caption, container: nil, minWidth: 1, maxWidth: nil,
            key: CanonicalTypography.namespace + "size", value: .number(20)), page: page, in: session).command)
        let scene = CanvasViewportSceneID(), document = session.document
        let context = TransformValidationContext(activePageID: page, currentSceneID: scene, rendererGeneration: document.revision,
            selectedNodeIDs: [fixture.caption], availableNodeIDs: [fixture.caption], isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        func fluid(_ target: FluidValueTarget, _ value: CanonicalFluidValue) -> FluidValueCommand {
            .init(identity: .init(editID: GeometryInspectorEditID(), documentID: document.id, pageID: page, revision: document.revision,
                                  sceneID: scene, rendererGeneration: document.revision),
                  orderedNodeIDs: [fixture.caption], target: target, value: value, provenance: .keyboard, cancelled: false)
        }
        XCTAssertThrowsError(try FluidValueCommandRegistry().prepare(fluid(.fontSize, .init(minimum: 12, preferred: 14, maximum: 16)),
                                                                     in: document, context: context)) {
            XCTAssertEqual($0 as? FluidValueCommandError, .containerQueryConflict)
        }
        XCTAssertNoThrow(try FluidValueCommandRegistry().prepare(fluid(.lineHeight, .init(minimum: 17, preferred: 20, maximum: 24)),
                                                                 in: document, context: context), "Only the setting the rule changes is refused")
        XCTAssertEqual(session.document, document, "Nothing changed")

        let diagnostics = CommandDiagnostics()
        let asset = AssetID()
        diagnostics.recordValueSourceOperation(pageID: page, nodeID: fixture.caption, succeeded: false, durationMilliseconds: 1)
        diagnostics.recordAssetDependencyOperation(assetIDs: [asset], succeeded: true, durationMilliseconds: 1)
        XCTAssertTrue(diagnostics.records[0].requirementIDs.contains("SF-0704-008"))
        XCTAssertEqual(diagnostics.records[0].failureCategory, .validation)
        XCTAssertTrue(diagnostics.records[1].requirementIDs.contains("SF-0807-008"))
        XCTAssertNil(diagnostics.records[1].failureCategory)
        XCTAssertFalse(String(describing: diagnostics.records).contains(fixture.caption.description))
        XCTAssertFalse(String(describing: diagnostics.records).contains(asset.description))
    }

    /// A definition without variants (for negative checks).
    private func plainComponentDefinition() throws -> DocumentPage {
        var definition = try XCTUnwrap(try variantFixture().document.componentDefinitions.first)
        definition.nodes[0].properties.removeAll { CanonicalComponentVariants.isMetadataKey($0.key.rawValue) }
        return definition
    }

    // SF-0903-001/003, SF-0905-001, OD-018: an instance owns its supplied slot
    // contents as its own canonical children (each marked with its slot) or an
    // authored empty state, both distinct from inheriting the default contents.
    // The definition never gains instance content; the state round-trips and
    // needs schema 25; every inconsistent encoding is rejected.
    func testSuppliedSlotContentAndEmptyStateValidateResolveAndRequireSchemaTwentyFive() throws {
        let fixture = try suppliedSlotFixture()
        var document = fixture.0
        let slot = fixture.1
        let page = document.websitePages[0], first = page.nodes[1].id, second = page.nodes[2].id
        let definitionBefore = try XCTUnwrap(document.componentDefinitions.first)
        let roots = try supply([.frame, .text], slot: slot.id, to: first, in: &document)
        try markEmpty(slot.id, on: second, in: &document)
        try document.validate()
        let home = document.pages[0]
        let byID = Dictionary(uniqueKeysWithValues: home.nodes.map { ($0.id, $0) })
        let firstNode = try XCTUnwrap(byID[first]), secondNode = try XCTUnwrap(byID[second])
        XCTAssertEqual(firstNode.childIDs, roots)
        XCTAssertEqual(CanonicalComponentSlot.state(of: slot.id, on: firstNode, nodesByID: byID), .supplied(roots))
        XCTAssertEqual(CanonicalComponentSlot.state(of: slot.id, on: secondNode, nodesByID: byID), .empty)
        XCTAssertEqual(CanonicalComponentSlot.suppliedNodeIDs(in: home), Set(roots))
        XCTAssertEqual(document.componentDefinitions.first, definitionBefore, "The definition never gains instance content")

        let firstValue = try XCTUnwrap(CanonicalComponentOverrides.resolve(instance: firstNode, document: document)
            .first { $0.property == .slot(slot.id) })
        XCTAssertEqual(firstValue.effectiveValue, .slotSupplied)
        XCTAssertEqual(firstValue.inheritedValue, .slotFallback(slot.defaultChildIDs))
        let marker = try XCTUnwrap(CanonicalComponentSlot.markers(on: firstNode)[slot.id])
        XCTAssertEqual(firstValue.resolution, .authored(propertyID: marker.id))
        XCTAssertEqual(try CanonicalComponentOverrides.resolve(instance: secondNode, document: document)
            .first { $0.property == .slot(slot.id) }?.effectiveValue, .slotEmpty)
        XCTAssertTrue(try CanonicalComponentOverrides.conflicts(instance: firstNode, document: document).isEmpty)

        XCTAssertEqual(CanonicalComponentSlot.contentSchema, 25)
        // Later schemas keep reading slot content (schema 26 adds variants, OD-033).
        XCTAssertGreaterThanOrEqual(DocumentSerializer.currentSchemaVersion, CanonicalComponentSlot.contentSchema)
        let encoded = try DocumentSerializer.encode(document)
        XCTAssertEqual(try DocumentSerializer.decode(encoded), document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(envelope["schemaVersion"] as? Int, DocumentSerializer.currentSchemaVersion)
        for older in [24, 23, 14] {
            envelope["schemaVersion"] = older
            XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "\(older)")
        }
        let plain = try suppliedSlotFixture().0
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(plain)) as? [String: Any])
        legacy["schemaVersion"] = 24
        XCTAssertEqual(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: legacy)), plain)

        func refuses(_ label: String, _ change: (inout CanonicalDocument) throws -> Void) rethrows {
            var broken = document
            try change(&broken)
            XCTAssertThrowsError(try broken.validate(), label)
        }
        let firstIndex = try XCTUnwrap(home.nodes.firstIndex { $0.id == first })
        let secondIndex = try XCTUnwrap(home.nodes.firstIndex { $0.id == second })
        let markerKey = CanonicalComponentSlot.overrideKey(slot.id)
        try refuses("root without membership") { broken in
            let index = try XCTUnwrap(broken.pages[0].nodes.firstIndex { $0.id == roots[1] })
            broken.pages[0].nodes[index].properties.removeAll { $0.key.rawValue == CanonicalComponentSlot.supplyKey }
        }
        try refuses("membership below the top level") { broken in
            let frameIndex = try XCTUnwrap(broken.pages[0].nodes.firstIndex { $0.id == roots[0] })
            let child = DocumentNode(kind: .text, name: "Nested", parent: .node(roots[0]), properties: [
                .init(key: .init(rawValue: CanonicalComponentSlot.supplyKey), value: .string(slot.id.description), origin: .authored)])
            broken.pages[0].nodes[frameIndex].childIDs.append(child.id)
            broken.pages[0].nodes.append(child)
        }
        refuses("supplied marker without roots") { broken in
            broken.pages[0].nodes[secondIndex].properties.removeAll { $0.key.rawValue == markerKey }
            broken.pages[0].nodes[secondIndex].properties.append(.init(key: .init(rawValue: markerKey),
                value: .string(CanonicalComponentSlot.suppliedValue), origin: .authored))
        }
        refuses("empty marker with roots") { broken in
            let at = broken.pages[0].nodes[firstIndex].properties.firstIndex { $0.key.rawValue == markerKey }!
            broken.pages[0].nodes[firstIndex].properties[at].value = .string(CanonicalComponentSlot.emptyValue)
        }
        refuses("unknown marker value") { broken in
            let at = broken.pages[0].nodes[secondIndex].properties.firstIndex { $0.key.rawValue == markerKey }!
            broken.pages[0].nodes[secondIndex].properties[at].value = .string("custom")
        }
        refuses("defaulted marker") { broken in
            let at = broken.pages[0].nodes[secondIndex].properties.firstIndex { $0.key.rawValue == markerKey }!
            broken.pages[0].nodes[secondIndex].properties[at].origin = .defaulted
        }
        refuses("roots without a supplied marker") { broken in
            broken.pages[0].nodes[firstIndex].properties.removeAll { $0.key.rawValue == markerKey }
        }
        refuses("marker on an ordinary object") { broken in
            broken.pages[0].nodes[0].properties.append(.init(key: .init(rawValue: markerKey),
                value: .string(CanonicalComponentSlot.emptyValue), origin: .authored))
        }
        var many = try suppliedSlotFixture().0
        _ = try supply(Array(repeating: .frame, count: CanonicalComponentSlot.maximumRoots), slot: slot.id,
                       to: many.websitePages[0].nodes[1].id, in: &many)
        try many.validate()
        _ = try supply([.frame], slot: slot.id, to: many.websitePages[0].nodes[1].id, in: &many, validate: false)
        XCTAssertThrowsError(try many.validate(), "More than 256 top-level items")

        var retargeted = document
        let reference = try XCTUnwrap(retargeted.pages[0].nodes[firstIndex].properties.firstIndex {
            $0.key.rawValue == CanonicalComponentReference.key
        })
        retargeted.pages[0].nodes[firstIndex].properties[reference].value = .string(PageID().description)
        XCTAssertThrowsError(try CanonicalComponentSlot.validateTransition(from: document, to: retargeted)) {
            XCTAssertEqual($0 as? ModelValidationError, .componentSlotContentWouldBeLost)
        }
    }

    // SF-0903-003/004, OD-018: slot rules limit the allowed top-level types and
    // number of items for both the default contents and every copy's own
    // contents. Setting a rule the current contents break is refused with the
    // reason; a document that breaks a rule is invalid; only one canonical
    // spelling is accepted; removing the slot removes its rules.
    func testSlotRulesConstrainDefaultAndSuppliedContentAndRefuseWithTheReason() throws {
        let (document, slot) = try suppliedSlotFixture()
        let definitionID = document.componentDefinitions[0].id, slotNode = slot.sourceNodeID
        func rules(_ kinds: Set<NodeKind>?, _ maximum: Int?) -> ComponentEdit {
            .setSlotRules(nodeID: slotNode, rules: .init(allowedKinds: kinds, maximumRoots: maximum))
        }
        XCTAssertThrowsError(try textCommand(rules([.frame], nil), document: document, pageID: definitionID, selected: slotNode)) {
            XCTAssertTrue($0.localizedDescription.contains("default contents break this rule: Text is not allowed; this slot accepts Frame"),
                          $0.localizedDescription)
        }
        XCTAssertThrowsError(try textCommand(rules(nil, 1), document: document, pageID: definitionID, selected: slotNode)) {
            XCTAssertTrue($0.localizedDescription.contains("2 items is more than this slot's limit of 1"), $0.localizedDescription)
        }
        XCTAssertThrowsError(try textCommand(rules([], nil), document: document, pageID: definitionID, selected: slotNode))
        XCTAssertThrowsError(try textCommand(rules(nil, 257), document: document, pageID: definitionID, selected: slotNode))

        let session = DocumentSession(document: document)
        try session.execute(textCommand(rules([.text, .frame], 3), document: document, pageID: definitionID, selected: slotNode).command)
        let ruled = session.document
        let stored = try XCTUnwrap(CanonicalComponentSlot.properties(in: ruled.componentDefinitions[0]).first)
        XCTAssertEqual(stored.rules, .init(allowedKinds: [.frame, .text], maximumRoots: 3))
        XCTAssertEqual(stored.rules.encodedKinds, "frame,text", "Canonical order, not authoring order")
        XCTAssertEqual(stored.id, slot.id)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(ruled)), ruled)

        var three = ruled
        let first = three.websitePages[0].nodes[1].id
        _ = try supply([.text, .text, .frame], slot: slot.id, to: first, in: &three)
        try three.validate()
        var four = three
        _ = try supply([.text], slot: slot.id, to: first, in: &four, validate: false)
        XCTAssertThrowsError(try four.validate()) { XCTAssertEqual($0 as? ModelValidationError, .componentSlotRuleBroken) }
        let threeSession = DocumentSession(document: three)
        XCTAssertThrowsError(try textCommand(rules(nil, 2), document: three, pageID: definitionID, selected: slotNode)) {
            XCTAssertTrue($0.localizedDescription.contains("One copy of this component breaks this rule with its own contents (3 items is more than this slot's limit of 2)"),
                          $0.localizedDescription)
        }
        XCTAssertThrowsError(try textCommand(rules([.text], nil), document: three, pageID: definitionID, selected: slotNode)) {
            XCTAssertTrue($0.localizedDescription.contains("Frame is not allowed; this slot accepts Text"), $0.localizedDescription)
        }
        try threeSession.execute(textCommand(rules(nil, nil), document: three, pageID: definitionID, selected: slotNode).command)
        let cleared = try XCTUnwrap(CanonicalComponentSlot.properties(in: threeSession.document.componentDefinitions[0]).first)
        XCTAssertEqual(cleared.rules, .unrestricted)
        XCTAssertFalse(threeSession.document.componentDefinitions[0].nodes.first { $0.id == slotNode }!.properties
            .contains { CanonicalComponentSlot.ruleKeys.contains($0.key.rawValue) }, "No rules stores no rule keys")
        try threeSession.undo()
        XCTAssertEqual(threeSession.document.pages, three.pages)

        let definitionIndex = try XCTUnwrap(ruled.pages.firstIndex { $0.id == definitionID })
        let nodeIndex = try XCTUnwrap(ruled.pages[definitionIndex].nodes.firstIndex { $0.id == slotNode })
        for (kinds, maximum) in [("text,frame", nil), ("frame,frame", nil), ("", nil), ("widget", nil),
                                 (nil, 0.0), (nil, 257.0), (nil, 2.5)] as [(String?, Double?)] {
            var forged = ruled
            forged.pages[definitionIndex].nodes[nodeIndex].properties.removeAll { CanonicalComponentSlot.ruleKeys.contains($0.key.rawValue) }
            if let kinds { forged.pages[definitionIndex].nodes[nodeIndex].properties.append(.init(
                key: .init(rawValue: CanonicalComponentSlot.allowedKindsKey), value: .string(kinds), origin: .authored)) }
            if let maximum { forged.pages[definitionIndex].nodes[nodeIndex].properties.append(.init(
                key: .init(rawValue: CanonicalComponentSlot.maximumRootsKey), value: .number(maximum), origin: .authored)) }
            XCTAssertThrowsError(try forged.validate(), "\(String(describing: kinds)) \(String(describing: maximum))")
        }
        try session.execute(textCommand(.removeSlotProperty(slotNode), document: session.document, pageID: definitionID,
            selected: slotNode).command)
        XCTAssertFalse(session.document.componentDefinitions[0].nodes.first { $0.id == slotNode }!.properties
            .contains { $0.key.rawValue.hasPrefix(CanonicalComponentSlot.namespace) })
    }

    // SF-0903-004/005, SF-0905-004, OD-018: when the definition stops exposing
    // a slot, a copy's own contents are kept as a conflict that blocks output;
    // resetting that conflict removes the contents and the marker in one
    // undoable step. Detach is refused while a copy has its own slot state.
    func testRemovedSlotKeepsSuppliedContentAsAConflictAndResetRemovesItInOneUndoableStep() throws {
        let fixture = try suppliedSlotFixture()
        var document = fixture.0
        let slot = fixture.1
        let first = document.websitePages[0].nodes[1].id, pageID = document.websitePages[0].id
        let roots = try supply([.frame, .text], slot: slot.id, to: first, in: &document)
        let nested = DocumentNode(kind: .text, name: "Inside", parent: .node(roots[0]), properties: [
            ("layout.x", 4.0), ("layout.y", 4.0), ("layout.width", 40.0), ("layout.height", 20.0)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            } + [NodeProperty(key: .init(rawValue: "content.text"), value: .string("Kept"))])
        let frameIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == roots[0] })
        document.pages[0].nodes[frameIndex].childIDs.append(nested.id)
        document.pages[0].nodes.append(nested)
        try document.validate()
        let supplied = Set(roots + [nested.id])
        XCTAssertEqual(CanonicalComponentSlot.suppliedNodeIDs(in: document.pages[0]), supplied)

        let session = DocumentSession(document: document)
        let definitionID = document.componentDefinitions[0].id
        try session.execute(textCommand(.removeSlotProperty(slot.sourceNodeID), document: document,
            pageID: definitionID, selected: slot.sourceNodeID).command)
        let orphaned = session.document
        XCTAssertTrue(Set(orphaned.pages[0].nodes.map(\.id)).isSuperset(of: supplied), "Content is kept")
        let instance = try XCTUnwrap(orphaned.pages[0].nodes.first { $0.id == first })
        let conflict = try XCTUnwrap(CanonicalComponentOverrides.conflicts(instance: instance, document: orphaned)
            .first { $0.property == .slot(slot.id) })
        XCTAssertEqual(conflict.property, .slot(slot.id))
        XCTAssertEqual(conflict.reason, .missingProperty)
        XCTAssertEqual(conflict.retainedValue, .slotSupplied)
        XCTAssertTrue(try CanonicalComponentOverrides.requiresRecovery(instance: instance, document: orphaned))
        let compiled = StaticBuildCompiler.compile(document: orphaned, profileSelection: .init(profile: .development),
            resourceDescriptors: [:], resourceData: [:])
        XCTAssertNil(compiled.plan)
        XCTAssertTrue(compiled.findings.contains { $0.code == "component-override-conflict" && $0.affectedNodeID == first })
        XCTAssertFalse(compiled.redactedSummary.contains("Kept"))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(orphaned)), orphaned)
        XCTAssertThrowsError(try textCommand(.detach(first), document: orphaned, pageID: pageID, selected: first),
                             "Detaching would drop contents kept for a missing slot") {
            XCTAssertTrue($0.localizedDescription.contains("a slot with this copy's own contents is missing"), $0.localizedDescription)
        }

        try session.execute(textCommand(.resetOverrideConflicts(instanceID: first, expectedPropertyIDs: [conflict.authoredPropertyID],
            confirmed: true), document: orphaned, pageID: pageID, selected: first).command)
        let reset = session.document
        let cleaned = try XCTUnwrap(reset.pages[0].nodes.first { $0.id == first })
        XCTAssertTrue(cleaned.childIDs.isEmpty)
        XCTAssertTrue(CanonicalComponentSlot.markers(on: cleaned).isEmpty)
        XCTAssertTrue(Set(reset.pages[0].nodes.map(\.id)).isDisjoint(with: supplied))
        XCTAssertTrue(try CanonicalComponentOverrides.conflicts(instance: cleaned, document: reset).isEmpty)
        try reset.validate()
        try session.undo()
        XCTAssertEqual(session.document.pages, orphaned.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, reset.pages)
    }

    // SF-0903-002/003/005, OD-018: Customize gives the copy its own copy of
    // the defaults exactly as it shows them (its own text value applied, new
    // identities, slot-local geometry, no definition metadata), drawn in the
    // same place; Make Empty and Use Default each replace the slot's state in
    // one undoable step, and the three steps return the original document.
    func testCustomizeMakeEmptyAndUseDefaultReplaceOneSlotStateInOneUndoableStepEach() throws {
        let fixture = try suppliedSlotFixture()
        var document = fixture.0
        let slot = fixture.1
        let definitionID = document.componentDefinitions[0].id
        let firstDefault = slot.defaultChildIDs[0]
        let expose = DocumentSession(document: document)
        try expose.execute(textCommand(.exposeText(nodeID: firstDefault, label: "Heading", defaultValue: "Fallback 1"),
            document: document, pageID: definitionID, selected: firstDefault).command)
        let property = try XCTUnwrap(CanonicalComponentText.properties(in: expose.document.componentDefinitions[0]).first)
        let pageID = expose.document.pages[0].id, first = expose.document.pages[0].nodes[1].id
        try expose.execute(textCommand(.setTextOverride(instanceID: first, propertyID: property.id, value: "Shown value"),
            document: expose.document, pageID: pageID, selected: first).command)
        document = expose.document
        let original = document
        let before = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
        let instance = try XCTUnwrap(document.pages[0].nodes.first { $0.id == first })
        let derived = slot.defaultChildIDs.map { ComponentGraphResolver.derivedID($0, in: instance) }
        let shownFrames = derived.map { id in before.nodes.first { $0.id == id }?.insertionGeometry }
        XCTAssertEqual(before.nodes.first { $0.id == derived[0] }?.insertionStringProperty("content.text"), "Shown value")

        let session = DocumentSession(document: document)
        func apply(_ edit: ComponentEdit, selected: NodeID? = nil) throws -> PreparedComponentEdit {
            let prepared = try textCommand(edit, document: session.document, pageID: pageID, selected: selected ?? first)
            try session.execute(prepared.command)
            return prepared
        }
        let customized = try apply(.customizeSlot(instanceID: first, slotID: slot.id))
        XCTAssertEqual(customized.selectedNodeID, first)
        let page = session.document.pages[0]
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let owner = try XCTUnwrap(byID[first])
        guard case .supplied(let roots) = CanonicalComponentSlot.state(of: slot.id, on: owner, nodesByID: byID) else {
            return XCTFail("Customize supplies the slot")
        }
        XCTAssertEqual(roots.count, 2)
        XCTAssertTrue(Set(roots).isDisjoint(with: Set(slot.defaultChildIDs + derived)), "New identities")
        let copies = roots.compactMap { byID[$0] }
        XCTAssertEqual(copies.map { $0.insertionStringProperty("content.text") }, ["Shown value", "Fallback 2"],
                       "The copy starts from what it showed, its own value included")
        XCTAssertEqual(copies.map { $0.insertionGeometry?.origin }, [WorldPoint(x: 0, y: 0), WorldPoint(x: 0, y: 28)],
                       "Slot-local: default position − slot container position")
        XCTAssertFalse(copies.contains { $0.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentText.namespace) } })
        XCTAssertTrue(copies.allSatisfy { CanonicalComponentSlot.suppliedSlotID($0) == slot.id })
        let after = try ComponentGraphResolver.resolvedPage(session.document.pages[0], in: session.document, breakpoint: .desktop)
        XCTAssertEqual(roots.map { id in after.nodes.first { $0.id == id }?.insertionGeometry }, shownFrames,
                       "Drawn exactly where the defaults were")
        XCTAssertFalse(after.nodes.contains { derived.contains($0.id) })
        try session.document.validate()
        let customizedDocument = session.document
        try session.undo()
        XCTAssertEqual(session.document.pages, original.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, customizedDocument.pages)

        _ = try apply(.makeSlotEmpty(instanceID: first, slotID: slot.id))
        let emptied = session.document.pages[0]
        XCTAssertTrue(Set(emptied.nodes.map(\.id)).isDisjoint(with: Set(roots)))
        XCTAssertEqual(CanonicalComponentSlot.state(of: slot.id, on: emptied.nodes.first { $0.id == first }!,
            nodesByID: Dictionary(uniqueKeysWithValues: emptied.nodes.map { ($0.id, $0) })), .empty)
        _ = try apply(.useSlotDefault(instanceID: first, slotID: slot.id))
        XCTAssertEqual(session.document.pages, original.pages, "Customize → Empty → Default returns the original copy")
        XCTAssertEqual(try ComponentGraphResolver.resolvedPage(session.document.pages[0], in: session.document, breakpoint: .desktop), before)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 3, "One entry per step")

        XCTAssertThrowsError(try textCommand(.customizeSlot(instanceID: first, slotID: ComponentSlotPropertyID()),
            document: original, pageID: pageID, selected: first)) {
            XCTAssertTrue($0.localizedDescription.contains("no longer has this slot"), $0.localizedDescription)
        }
        XCTAssertThrowsError(try textCommand(.addToSlot(instanceID: first, slotID: slot.id, kind: .frame),
            document: original, pageID: pageID, selected: first)) {
            XCTAssertTrue($0.localizedDescription.contains("Choose Customize or Make Empty first"), $0.localizedDescription)
        }
        // A slot whose default contents are empty customizes to the empty state.
        var bare = original
        let definitionIndex = try XCTUnwrap(bare.pages.firstIndex { $0.id == definitionID })
        bare.pages[definitionIndex].nodes.removeAll { slot.defaultChildIDs.contains($0.id) }
        let slotIndex = try XCTUnwrap(bare.pages[definitionIndex].nodes.firstIndex { $0.id == slot.sourceNodeID })
        bare.pages[definitionIndex].nodes[slotIndex].childIDs = []
        bare.pages[definitionIndex].nodes.removeAll { $0.properties.contains { $0.key.rawValue.hasPrefix(CanonicalComponentText.namespace) } }
        bare.pages[0].nodes = bare.pages[0].nodes.map { node in
            var copy = node; copy.properties.removeAll { CanonicalComponentText.overrideID($0.key.rawValue) != nil }; return copy
        }
        try bare.validate()
        let bareSession = DocumentSession(document: bare)
        try bareSession.execute(textCommand(.customizeSlot(instanceID: first, slotID: slot.id), document: bare,
            pageID: pageID, selected: first).command)
        XCTAssertEqual(CanonicalComponentSlot.markers(on: bareSession.document.pages[0].nodes.first { $0.id == first }!)[slot.id]?.value,
                       .string(CanonicalComponentSlot.emptyValue))
    }

    // SF-0903-002/003/004, OD-018: Add appends a Frame or Text after the
    // slot's last item within the slot rules (refused with the rule), and
    // Move Up/Down reorders top-level items within their slot only.
    func testAddToSlotFollowsTheRulesAndMoveSlotItemReordersWithinTheSlot() throws {
        let (document, slot) = try suppliedSlotFixture()
        let definitionID = document.componentDefinitions[0].id
        let pageID = document.pages[0].id, first = document.pages[0].nodes[1].id
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.customizeSlot(instanceID: first, slotID: slot.id), document: document,
            pageID: pageID, selected: first).command)
        let added = try textCommand(.addToSlot(instanceID: first, slotID: slot.id, kind: .frame), document: session.document,
            pageID: pageID, selected: first)
        try session.execute(added.command)
        let page = session.document.pages[0]
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let roots = try XCTUnwrap(CanonicalComponentSlot.suppliedRoots(of: try XCTUnwrap(byID[first]), nodesByID: byID)[slot.id]).map(\.id)
        XCTAssertEqual(roots.count, 3)
        XCTAssertEqual(roots.last, added.selectedNodeID, "The new item is last and selected")
        let frame = try XCTUnwrap(byID[roots[2]])
        XCTAssertEqual(frame.kind, .frame)
        XCTAssertEqual(frame.insertionGeometry, InsertionGeometry(origin: .init(x: 0, y: 60), size: .init(width: 240, height: 160)),
                       "Below the last item (28 + 24 + 8)")
        XCTAssertEqual(CanonicalComponentSlot.suppliedSlotID(frame), slot.id)
        try session.document.validate()

        try session.execute(textCommand(.setSlotRules(nodeID: slot.sourceNodeID, rules: .init(allowedKinds: [.text, .frame], maximumRoots: 3)),
            document: session.document, pageID: definitionID, selected: slot.sourceNodeID).command)
        XCTAssertThrowsError(try textCommand(.addToSlot(instanceID: first, slotID: slot.id, kind: .text), document: session.document,
            pageID: pageID, selected: first)) {
            XCTAssertTrue($0.localizedDescription.contains("4 items is more than this slot's limit of 3"), $0.localizedDescription)
        }
        try session.undo()
        try session.execute(textCommand(.setSlotRules(nodeID: slot.sourceNodeID, rules: .init(allowedKinds: [.text, .frame], maximumRoots: nil)),
            document: session.document, pageID: definitionID, selected: slot.sourceNodeID).command)
        XCTAssertNoThrow(try textCommand(.addToSlot(instanceID: first, slotID: slot.id, kind: .text), document: session.document,
            pageID: pageID, selected: first))
        try session.undo()

        let beforeMove = session.document
        try session.execute(textCommand(.moveSlotItem(nodeID: roots[2], offset: -1), document: session.document,
            pageID: pageID, selected: roots[2]).command)
        let moved = session.document.pages[0]
        let movedByID = Dictionary(uniqueKeysWithValues: moved.nodes.map { ($0.id, $0) })
        XCTAssertEqual(try XCTUnwrap(CanonicalComponentSlot.suppliedRoots(of: try XCTUnwrap(movedByID[first]), nodesByID: movedByID)[slot.id]).map(\.id),
                       [roots[0], roots[2], roots[1]])
        XCTAssertThrowsError(try textCommand(.moveSlotItem(nodeID: roots[0], offset: -1), document: session.document,
            pageID: pageID, selected: roots[0])) {
            XCTAssertTrue($0.localizedDescription.contains("already the first item"), $0.localizedDescription)
        }
        XCTAssertThrowsError(try textCommand(.moveSlotItem(nodeID: first, offset: 1), document: session.document,
            pageID: pageID, selected: first))
        try session.undo()
        XCTAssertEqual(session.document.pages, beforeMove.pages)
    }

    // SF-0901-002, SF-0903-005, OD-018: Make Independent keeps the copy's own
    // slot contents (canonical identities, world geometry, no membership) in
    // place of the defaults, and an empty slot stays empty; Detach Uses and
    // Delete does the same for every use in one transaction.
    func testDetachKeepsTheCopysOwnSlotContentsAndDetachUsesAndDeleteIncludesThem() throws {
        let (document, slot) = try suppliedSlotFixture()
        let pageID = document.pages[0].id, first = document.pages[0].nodes[1].id, second = document.pages[0].nodes[2].id
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.customizeSlot(instanceID: first, slotID: slot.id), document: document,
            pageID: pageID, selected: first).command)
        try session.execute(textCommand(.makeSlotEmpty(instanceID: second, slotID: slot.id), document: session.document,
            pageID: pageID, selected: second).command)
        let prepared = session.document
        let byID = Dictionary(uniqueKeysWithValues: prepared.pages[0].nodes.map { ($0.id, $0) })
        let roots = try XCTUnwrap(CanonicalComponentSlot.suppliedRoots(of: try XCTUnwrap(byID[first]), nodesByID: byID)[slot.id]).map(\.id)
        let shown = try ComponentGraphResolver.resolvedPage(prepared.pages[0], in: prepared, breakpoint: .desktop)
        let shownFrames = roots.map { id in shown.nodes.first { $0.id == id }?.insertionGeometry }

        try session.execute(textCommand(.detach(first), document: prepared, pageID: pageID, selected: first).command)
        let detached = session.document.pages[0]
        let container = ComponentGraphResolver.derivedID(slot.sourceNodeID, in: try XCTUnwrap(byID[first]))
        let detachedByID = Dictionary(uniqueKeysWithValues: detached.nodes.map { ($0.id, $0) })
        XCTAssertEqual(detachedByID[first]?.kind, .frame)
        XCTAssertEqual(detachedByID[container]?.childIDs, roots, "The copy's own contents replace the defaults")
        XCTAssertEqual(roots.map { detachedByID[$0]?.insertionGeometry }, shownFrames, "World geometry, same place")
        XCTAssertTrue(roots.allSatisfy { detachedByID[$0]?.insertionProperty(CanonicalComponentSlot.supplyKey) == nil })
        XCTAssertEqual(detached.nodes.filter { roots.contains($0.id) }.count, roots.count, "No duplicates")
        try session.document.validate()
        try session.undo()
        XCTAssertEqual(session.document.pages, prepared.pages)

        let definitionID = prepared.componentDefinitions[0].id
        try session.execute(textCommand(.delete(definitionID: definitionID, detachUses: true), document: prepared,
            pageID: pageID, selected: first).command)
        let deleted = session.document
        XCTAssertTrue(deleted.componentDefinitions.isEmpty)
        let deletedByID = Dictionary(uniqueKeysWithValues: deleted.pages[0].nodes.map { ($0.id, $0) })
        XCTAssertEqual(deletedByID[container]?.childIDs, roots)
        let secondContainer = ComponentGraphResolver.derivedID(slot.sourceNodeID, in: try XCTUnwrap(byID[second]))
        XCTAssertEqual(deletedByID[secondContainer]?.childIDs, [], "The empty slot stays empty")
        try deleted.validate()
        try session.undo()
        XCTAssertEqual(session.document.pages, prepared.pages)
    }

    // SF-0403/0405/0406, SF-0308-003, OD-018: every editing path that works
    // in canvas coordinates keeps slot contents where the canvas shows them:
    // move/resize outlines and snapping use world frames while stored values
    // change by the delta; Insert inside slot contents, dragging in and out,
    // copy (world, no membership), paste into slot contents (slot-local) and
    // cutting a slot's last item (slot becomes empty).
    // SF-0903-003/005/008: changing coordinate domains must preserve inherited
    // positions at every breakpoint, including when no override existed before.
    func testSlotCoordinateConversionMaterializesOnlyRequiredResponsiveOverrides() throws {
        let page = DocumentPage.minimum(name: "Coordinates", route: "/", role: .home, provenance: .authored)
        let root = try XCTUnwrap(page.rootNodeIDs.first)
        let node = DocumentNode(kind: .frame, name: "Inherited position", parent: .node(root), properties: [
            ("layout.x", 130.0), ("layout.y", 90.0), ("layout.width", 40.0), ("layout.height", 30.0)
        ].map { NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored) })
        func offset(_ breakpoint: ResponsiveBreakpoint) -> WorldVector {
            breakpoint == .mobile ? .init(dx: 20, dy: 10) : .init(dx: 100, dy: 40)
        }
        let local = CanonicalSlotGeometry.shifted(node, sign: -1, by: offset)
        for breakpoint in ResponsiveBreakpoint.allCases {
            let frame = try XCTUnwrap(ResponsiveGeometryResolver.geometry(for: local, breakpoint: breakpoint))
            XCTAssertEqual(frame.origin.x + offset(breakpoint).dx, 130)
            XCTAssertEqual(frame.origin.y + offset(breakpoint).dy, 90)
        }
        XCTAssertNil(local.insertionProperty(ResponsiveGeometryResolver.key(.x, breakpoint: .tablet)))
        XCTAssertNotNil(local.insertionProperty(ResponsiveGeometryResolver.key(.x, breakpoint: .mobile)))
        XCTAssertEqual(local.properties.prefix(node.properties.count).map(\.id), node.properties.map(\.id))

        var document = CanonicalDocument(pages: [page])
        document.pages[0].nodes[0].childIDs.append(node.id)
        document.pages[0].nodes.append(node)
        let session = DocumentSession(document: document)
        let commands = CanonicalSlotGeometry.shiftCommands(subtreeOf: node.id, in: document.pages[0]) { bp in
            .init(dx: -offset(bp).dx, dy: -offset(bp).dy)
        }
        try session.execute(.batch(commands))
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let committed = session.document
        try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)
        try session.redo()
        XCTAssertEqual(session.document.pages, committed.pages)
        let restored = CanonicalSlotGeometry.shifted(local, sign: 1, by: offset)
        for breakpoint in ResponsiveBreakpoint.allCases {
            XCTAssertEqual(ResponsiveGeometryResolver.geometry(for: restored, breakpoint: breakpoint)?.origin,
                           WorldPoint(x: 130, y: 90))
        }
    }

    // SF-0903-003/008: editing must use the slot position after each copy's
    // actual Stack sizing, not the original definition's fixed-width position.
    func testSlotOriginsMatchRenderedLayoutForDifferentlySizedCopies() throws {
        var (document, slot) = try suppliedSlotFixture()
        let definitionIndex = try XCTUnwrap(document.pages.firstIndex { $0.role == .componentDefinition })
        let rootID = try XCTUnwrap(document.pages[definitionIndex].rootNodeIDs.first)
        let rootIndex = try XCTUnwrap(document.pages[definitionIndex].nodes.firstIndex { $0.id == rootID })
        document.pages[definitionIndex].nodes[rootIndex].kind = .stack
        for (key, value) in ["layout.container.kind": PropertyValue.string("stack"),
                             "layout.axis": .string("vertical"), "layout.align": .string("end"),
                             "layout.padding": .number(24), "layout.gap": .number(0)] {
            if let index = document.pages[definitionIndex].nodes[rootIndex].properties.firstIndex(where: { $0.key.rawValue == key }) {
                document.pages[definitionIndex].nodes[rootIndex].properties[index].value = value
            } else {
                document.pages[definitionIndex].nodes[rootIndex].properties.append(.init(key: .init(rawValue: key), value: value))
            }
        }
        let copies = document.pages[0].nodes.filter { $0.kind == .component }
        XCTAssertGreaterThanOrEqual(copies.count, 2)
        for (offset, copy) in copies.enumerated() {
            let index = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == copy.id })
            let width = try XCTUnwrap(document.pages[0].nodes[index].properties.firstIndex { $0.key.rawValue == "layout.width" })
            document.pages[0].nodes[index].properties[width].value = .number(600 + Double(offset) * 200)
            try supply([.text], slot: slot.id, to: copy.id, in: &document)
        }
        for breakpoint in ResponsiveBreakpoint.allCases {
            let page = document.pages[0]
            let projected = try ComponentGraphResolver.resolvedPage(page, in: document, breakpoint: breakpoint)
            let frames = projected.resolvedStructuralGeometry(breakpoint: breakpoint)
            let offsets = CanonicalSlotGeometry.offsets(in: page, document: document, breakpoint: breakpoint)
            let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
            for copy in page.nodes where copy.kind == .component {
                let slotID = ComponentGraphResolver.derivedID(slot.sourceNodeID, in: copy)
                let origin = try XCTUnwrap(frames[slotID]).origin
                let actual = CanonicalSlotGeometry.slotOffset(instance: copy, slot: slot.id, page: page,
                                                              document: document, breakpoint: breakpoint)
                XCTAssertEqual(actual, WorldVector(dx: origin.x, dy: origin.y))
                for item in CanonicalComponentSlot.suppliedRoots(of: copy, nodesByID: byID)[slot.id] ?? [] {
                    XCTAssertEqual(offsets[item.id], actual)
                }
            }
        }
    }

    func testCanvasPathsConvertBetweenWorldAndSlotLocalGeometryAtTheBoundary() throws {
        let (fixture, slot) = try suppliedSlotFixture()
        let pageID = fixture.pages[0].id, first = fixture.pages[0].nodes[1].id
        let session = DocumentSession(document: fixture)
        try session.execute(textCommand(.customizeSlot(instanceID: first, slotID: slot.id), document: fixture,
            pageID: pageID, selected: first).command)
        try session.execute(textCommand(.addToSlot(instanceID: first, slotID: slot.id, kind: .frame), document: session.document,
            pageID: pageID, selected: first).command)
        var document = session.document
        let byID = Dictionary(uniqueKeysWithValues: document.pages[0].nodes.map { ($0.id, $0) })
        let roots = try XCTUnwrap(CanonicalComponentSlot.suppliedRoots(of: try XCTUnwrap(byID[first]), nodesByID: byID)[slot.id]).map(\.id)
        let text = roots[0], box = roots[2]
        // First is at (80, 80); its slot container at (24, 24) in Card → slot origin (104, 104).
        XCTAssertEqual(CanonicalSlotGeometry.offsets(in: document.pages[0], document: document)[text], WorldVector(dx: 104, dy: 104))
        let scene = CanvasViewportSceneID()
        let ids = Set(document.pages[0].nodes.map(\.id))
        func transformContext(_ selected: [NodeID]) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: scene, rendererGeneration: 1, selectedNodeIDs: selected,
                  availableNodeIDs: ids, isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        let move = GeometryTransformCommand(identity: .init(sessionID: TransformSessionID(), documentID: document.id, pageID: pageID,
            revision: document.revision, sceneID: scene, rendererGeneration: 1), orderedNodeIDs: [text],
            operation: .move(delta: .init(dx: 10, dy: 5), constraint: .none), provenance: .automation)
        let moved = try TransformCommandRegistry().prepare(move, in: document, context: transformContext([text]))
        XCTAssertEqual(moved.geometries[0].original.origin, WorldPoint(x: 104, y: 104), "Outline and snapping use the canvas frame")
        XCTAssertEqual(moved.geometries[0].preview.origin, WorldPoint(x: 114, y: 109))
        try session.execute(moved.documentCommand)
        XCTAssertEqual(session.document.pages[0].nodes.first { $0.id == text }?.insertionGeometry?.origin, WorldPoint(x: 10, y: 5),
                       "Stored value changes by the delta")
        try session.undo()

        // Insert a Frame inside the supplied Frame at canvas (150, 200).
        let insertion = AuthoringInsertionCommand.frame(FrameInsertionCommand(identity: .init(documentID: document.id,
            pageID: pageID, revision: document.revision, generation: 1), nodeID: NodeID(), parentID: box, index: 0,
            geometry: .init(origin: .init(x: 150, y: 200), size: .init(width: 40, height: 40)), provenance: .automation))
        let inserted = try InsertionCommandRegistry().prepare(insertion, in: document,
            context: .init(activePageID: pageID, activeRoute: document.pages[0].route, operationGeneration: 1))
        XCTAssertEqual(inserted.node.insertionGeometry?.origin, WorldPoint(x: 46, y: 96), "150 − 104, 200 − 104")
        try session.execute(inserted.documentCommand)
        let resolved = try ComponentGraphResolver.resolvedPage(session.document.pages[0], in: session.document, breakpoint: .desktop)
        XCTAssertEqual(resolved.nodes.first { $0.id == inserted.node.id }?.insertionGeometry?.origin, WorldPoint(x: 150, y: 200))
        try session.undo()

        // Drag an ordinary page Frame at (600, 400) into the supplied Frame, then back out.
        let pageRoot = document.pages[0].rootNodeIDs[0]
        let loose = DocumentNode(kind: .frame, name: "Loose", parent: .node(pageRoot), properties: [
            ("layout.x", 600.0), ("layout.y", 400.0), ("layout.width", 50.0), ("layout.height", 50.0)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
        document.pages[0].nodes[rootIndex].childIDs.append(loose.id)
        document.pages[0].nodes.append(loose)
        try document.validate()
        let drags = DocumentSession(document: document)
        let dragContext = DragDropValidationContext(activePageID: pageID, sceneID: scene, rendererGeneration: 1,
            availableNodeIDs: Set(document.pages[0].nodes.map(\.id)), isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        func drag(_ source: NodeID, to destination: DragDestination) throws {
            let command = DragDropCommand(identity: .init(sessionID: DragSessionID(), documentID: drags.document.id, pageID: pageID,
                revision: drags.document.revision, sceneID: scene, rendererGeneration: 1), sourceNodeID: source,
                destination: destination, provenance: .automation)
            try drags.execute(DragDropCommandRegistry().prepare(command, in: drags.document, context: dragContext).command)
        }
        try drag(loose.id, to: .container(box, index: 0))
        XCTAssertEqual(drags.document.pages[0].nodes.first { $0.id == loose.id }?.insertionGeometry?.origin, WorldPoint(x: 496, y: 296))
        let inside = try ComponentGraphResolver.resolvedPage(drags.document.pages[0], in: drags.document, breakpoint: .desktop)
        XCTAssertEqual(inside.nodes.first { $0.id == loose.id }?.insertionGeometry?.origin, WorldPoint(x: 600, y: 400),
                       "The canvas position is kept")
        try drag(loose.id, to: .container(pageRoot, index: 0))
        XCTAssertEqual(drags.document.pages[0].nodes.first { $0.id == loose.id }?.insertionGeometry?.origin, WorldPoint(x: 600, y: 400))
        XCTAssertThrowsError(try DragDropCommandRegistry().prepare(DragDropCommand(identity: .init(sessionID: DragSessionID(),
            documentID: drags.document.id, pageID: pageID, revision: drags.document.revision, sceneID: scene, rendererGeneration: 1),
            sourceNodeID: text, destination: .container(pageRoot, index: 0), provenance: .automation), in: drags.document,
            context: dragContext)) { XCTAssertEqual($0 as? DragDropError, .slotItem) }

        // Copy the supplied Text: world geometry, no membership; paste it into the supplied Frame.
        let registry = ClipboardTransferRegistry()
        let copyIdentity = ClipboardOperationIdentity(documentID: document.id, pageID: pageID, revision: document.revision,
            sceneID: scene, rendererGeneration: 1, selectedNodeIDs: [text])
        let envelope = try registry.prepareCopy(identity: copyIdentity, document: document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        XCTAssertEqual(envelope.nodes[0].insertionGeometry?.origin, WorldPoint(x: 104, y: 104))
        XCTAssertNil(envelope.nodes[0].insertionProperty(CanonicalComponentSlot.supplyKey))
        let pasteIdentity = ClipboardOperationIdentity(documentID: document.id, pageID: pageID, revision: document.revision,
            sceneID: scene, rendererGeneration: 1, selectedNodeIDs: [])
        let paste = try registry.preparePaste(envelope: envelope, identity: pasteIdentity, document: document,
            context: .init(liveIdentity: pasteIdentity, activeContainerID: box, lifecycleAvailable: true, disabledReason: nil),
            placement: .inPlace)
        let pastes = DocumentSession(document: document)
        try pastes.execute(paste.command)
        let pastedID = try XCTUnwrap(paste.insertedRootIDs.first)
        XCTAssertEqual(pastes.document.pages[0].nodes.first { $0.id == pastedID }?.insertionGeometry?.origin, WorldPoint(x: 0, y: 0),
                       "Slot-local again: 104 − 104")
        try pastes.document.validate()

        // Cut every top-level item of the slot: it becomes empty, not "supplied" with nothing.
        let cutIdentity = ClipboardOperationIdentity(documentID: document.id, pageID: pageID, revision: document.revision,
            sceneID: scene, rendererGeneration: 1, selectedNodeIDs: roots)
        let cutEnvelope = try registry.prepareCopy(identity: cutIdentity, document: document,
            resourceData: { _ in throw ClipboardTransferError.invalidDependency })
        let removal = try registry.prepareCutRemoval(envelope: cutEnvelope, identity: cutIdentity, document: document,
            context: .init(liveIdentity: cutIdentity, activeContainerID: nil, lifecycleAvailable: true, disabledReason: nil))
        let cuts = DocumentSession(document: document)
        try cuts.execute(removal)
        let cutOwner = try XCTUnwrap(cuts.document.pages[0].nodes.first { $0.id == first })
        XCTAssertTrue(cutOwner.childIDs.isEmpty)
        XCTAssertEqual(CanonicalComponentSlot.markers(on: cutOwner)[slot.id]?.value, .string(CanonicalComponentSlot.emptyValue))
        try cuts.document.validate()
    }

    // SF-0901-002, OD-018 with OD-034: creating a component from a selection
    // that contains a copy with its own slot contents keeps those contents
    // (slot-local, membership kept) inside the new definition, drawn in place.
    func testCreateComponentFromSelectionKeepsAnInnerCopysOwnSlotContents() throws {
        let fixture = try suppliedSlotFixture()
        var document = fixture.0
        let slot = fixture.1
        let pageID = document.pages[0].id, first = document.pages[0].nodes[1].id, pageRoot = document.pages[0].rootNodeIDs[0]
        let session = DocumentSession(document: document)
        try session.execute(textCommand(.customizeSlot(instanceID: first, slotID: slot.id), document: document,
            pageID: pageID, selected: first).command)
        document = session.document
        let wrapper = DocumentNode(kind: .frame, name: "Wrapper", parent: .node(pageRoot), childIDs: [first], properties: [
            ("layout.x", 60.0), ("layout.y", 60.0), ("layout.width", 400.0), ("layout.height", 300.0)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
        document.pages[0].nodes[rootIndex].childIDs.removeAll { $0 == first }
        document.pages[0].nodes[rootIndex].childIDs.append(wrapper.id)
        let firstIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == first })
        document.pages[0].nodes[firstIndex].parent = .node(wrapper.id)
        document.pages[0].nodes.append(wrapper)
        try document.validate()
        let before = try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: .desktop)
        let roots = document.pages[0].nodes.first { $0.id == first }!.childIDs
        let shown = roots.map { id in before.nodes.first { $0.id == id }?.insertionGeometry?.origin }

        let creating = DocumentSession(document: document)
        try creating.execute(textCommand(.createNamed(wrapper.id, name: "Promo"), document: document, pageID: pageID,
            selected: wrapper.id).command)
        let created = creating.document
        let promo = try XCTUnwrap(created.componentDefinitions.first { $0.name == "Promo" })
        let inner = try XCTUnwrap(promo.nodes.first { $0.kind == .component })
        XCTAssertEqual(inner.childIDs.count, roots.count)
        XCTAssertTrue(inner.childIDs.compactMap { id in promo.nodes.first { $0.id == id } }
            .allSatisfy { CanonicalComponentSlot.suppliedSlotID($0) == slot.id })
        XCTAssertEqual(CanonicalComponentSlot.markers(on: inner)[slot.id]?.value, .string(CanonicalComponentSlot.suppliedValue))
        try created.validate()
        let after = try ComponentGraphResolver.resolvedPage(created.pages[0], in: created, breakpoint: .desktop)
        let promoInstance = try XCTUnwrap(created.pages[0].nodes.first { $0.id == wrapper.id })
        let drawn = inner.childIDs.map { id in
            after.nodes.first { $0.id == ComponentGraphResolver.derivedID(id, in: promoInstance) }?.insertionGeometry?.origin
        }
        XCTAssertEqual(drawn, shown, "Same place after becoming part of the new component")
        try creating.undo()
        XCTAssertEqual(creating.document.pages, document.pages)
    }

    /// SF-0903-002, OD-018 regression: Customize copies an inner
    /// copy's own slot contents with their positions at every breakpoint, so
    /// the customized slot looks the same on mobile as before.
    func testCustomizeKeepsAnInnerCopysOwnSlotContentsAtEveryBreakpoint() throws {
        let fixture = try suppliedSlotFixture()
        var document = fixture.0
        let cardSlot = fixture.1, cardID = document.componentDefinitions[0].id
        func number(_ key: String, _ value: Double) -> NodeProperty { .init(key: .init(rawValue: key), value: .number(value)) }
        func string(_ key: String, _ value: String) -> NodeProperty { .init(key: .init(rawValue: key), value: .string(value)) }
        func frame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> [NodeProperty] {
            [number("layout.x", x), number("layout.y", y), number("layout.width", width), number("layout.height", height)]
        }
        // Panel's Body slot holds, by default, a Card whose own slot holds "Inner"
        // (x 4 on desktop, 10 on mobile).
        let panelID = PageID(), panelRoot = NodeID(), body = NodeID(), innerCard = NodeID(), innerText = NodeID()
        let bodySlot = ComponentSlotPropertyID()
        document.pages.append(DocumentPage(id: panelID, name: "Panel", route: .init(rawValue: ""), role: .componentDefinition,
            provenance: .authored, rootNodeIDs: [panelRoot], nodes: [
                DocumentNode(id: panelRoot, kind: .frame, name: "Panel", parent: .page(panelID), childIDs: [body],
                             properties: frame(0, 0, 400, 300)),
                DocumentNode(id: body, kind: .frame, name: "Body", parent: .node(panelRoot), childIDs: [innerCard],
                             properties: frame(20, 20, 360, 260) + [
                                string(CanonicalComponentSlot.namespace + "id", bodySlot.description),
                                string(CanonicalComponentSlot.namespace + "label", "Body"),
                                string(CanonicalComponentSlot.namespace + "type", "ordered-fallback-children")]),
                DocumentNode(id: innerCard, kind: .component, name: "Card", parent: .node(body), childIDs: [innerText],
                             properties: frame(40, 40, 240, 160) + [
                                string(CanonicalComponentReference.key, cardID.description),
                                string(CanonicalComponentSlot.overrideKey(cardSlot.id), CanonicalComponentSlot.suppliedValue)]),
                DocumentNode(id: innerText, kind: .text, name: "Inner", parent: .node(innerCard),
                             properties: frame(4, 4, 100, 24) + [
                                string(CanonicalComponentSlot.supplyKey, cardSlot.id.description), string("content.text", "Inner"),
                                number(ResponsiveGeometryResolver.key(.x, breakpoint: .mobile), 10)]),
            ]))
        let pageID = document.pages[0].id, pageRoot = document.pages[0].rootNodeIDs[0]
        let panel = DocumentNode(kind: .component, name: "Panel", parent: .node(pageRoot),
                                 properties: frame(500, 500, 400, 300) + [string(CanonicalComponentReference.key, panelID.description)])
        let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == pageRoot })
        document.pages[0].nodes[rootIndex].childIDs.append(panel.id)
        document.pages[0].nodes.append(panel)
        try document.validate()
        func drawnX(_ id: NodeID, in document: CanonicalDocument, at breakpoint: ResponsiveBreakpoint) throws -> Double? {
            try ComponentGraphResolver.resolvedPage(document.pages[0], in: document, breakpoint: breakpoint)
                .nodes.first { $0.id == id }?.insertionGeometry?.origin.x
        }
        let derivedInner = ComponentGraphResolver.derivedID(innerText, in: panel)
        let shown = try ResponsiveBreakpoint.allCases.map { try drawnX(derivedInner, in: document, at: $0) }
        XCTAssertTrue(shown.allSatisfy { $0 != nil })

        let session = DocumentSession(document: document)
        try session.execute(textCommand(.customizeSlot(instanceID: panel.id, slotID: bodySlot), document: document,
            pageID: pageID, selected: panel.id).command)
        let page = session.document.pages[0]
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let owner = try XCTUnwrap(byID[panel.id])
        let cardCopy = try XCTUnwrap(CanonicalComponentSlot.suppliedRoots(of: owner, nodesByID: byID)[bodySlot]?.first)
        XCTAssertEqual(cardCopy.kind, .component, "The inner copy stays linked")
        let textCopy = try XCTUnwrap(cardCopy.childIDs.first.flatMap { byID[$0] })
        XCTAssertEqual(CanonicalComponentSlot.suppliedSlotID(textCopy), cardSlot.id)
        XCTAssertEqual(textCopy.insertionGeometry?.origin.x, 4, "Still slot-local to the inner copy")
        XCTAssertEqual(textCopy.insertionProperty(ResponsiveGeometryResolver.key(.x, breakpoint: .mobile))?.value, .number(10),
                       "Its mobile position travels with it")
        XCTAssertEqual(try ResponsiveBreakpoint.allCases.map { try drawnX(textCopy.id, in: session.document, at: $0) }, shown)
        try session.document.validate()
    }

    // SF-0903-008, OD-018: a slot edit's diagnostic record also names the
    // slot requirement; other component edits keep the component IDs only.
    // Records never carry raw identifiers.
    func testSlotEditDiagnosticsNameTheSlotRequirementAndOtherComponentEditsDoNot() {
        let instanceID = NodeID(), slotID = ComponentSlotPropertyID(), definitionID = PageID()
        let slotEdits: [ComponentEdit] = [
            .exposeSlot(nodeID: instanceID, label: "Content"), .removeSlotProperty(instanceID),
            .setSlotRules(nodeID: instanceID, rules: .unrestricted),
            .customizeSlot(instanceID: instanceID, slotID: slotID), .makeSlotEmpty(instanceID: instanceID, slotID: slotID),
            .useSlotDefault(instanceID: instanceID, slotID: slotID),
            .addToSlot(instanceID: instanceID, slotID: slotID, kind: .frame), .moveSlotItem(nodeID: instanceID, offset: 1),
        ]
        XCTAssertTrue(slotEdits.allSatisfy(\.isSlotEdit))
        let otherEdits: [ComponentEdit] = [.create(instanceID), .detach(instanceID), .duplicateDefinition(definitionID),
                                           .delete(definitionID: definitionID, detachUses: false), .resetAllOverrides(instanceID)]
        XCTAssertFalse(otherEdits.contains(where: \.isSlotEdit))

        let diagnostics = CommandDiagnostics()
        let pageID = PageID()
        diagnostics.recordComponentOperation(pageID: pageID, nodeIDs: [instanceID], succeeded: true,
                                             durationMilliseconds: 1, slotOperation: true)
        diagnostics.recordComponentOperation(pageID: pageID, nodeIDs: [instanceID], succeeded: false, durationMilliseconds: 1)
        XCTAssertEqual(diagnostics.records.count, 2)
        XCTAssertEqual(diagnostics.records[0].requirementIDs.first, "SF-0901-008")
        XCTAssertTrue(diagnostics.records[0].requirementIDs.contains("SF-0903-008"))
        XCTAssertEqual(diagnostics.records[0].result, .success)
        XCTAssertNil(diagnostics.records[0].failureCategory)
        XCTAssertFalse(diagnostics.records[1].requirementIDs.contains("SF-0903-008"))
        XCTAssertEqual(diagnostics.records[1].failureCategory, .validation)
        XCTAssertFalse(String(describing: diagnostics.records).contains(instanceID.description))
    }

    // SF-0303, SF-0903-005, OD-018: duplicating a page copies each copy's own
    // slot contents and empty state with new identities and the same slot,
    // drawn in the same places on the new page.
    func testPageDuplicateCopiesEachCopysOwnSlotContentsAndEmptyState() throws {
        let fixture = try suppliedSlotFixture()
        var document = fixture.0
        let slot = fixture.1
        let first = document.pages[0].nodes[1].id, second = document.pages[0].nodes[2].id
        let roots = try supply([.text, .frame], slot: slot.id, to: first, in: &document)
        try markEmpty(slot.id, on: second, in: &document)
        try document.validate()
        let session = DocumentSession(document: document)
        let copy = try PageCommandRegistry().prepare(.duplicate,
            identity: .init(documentID: document.id, revision: document.revision, pageID: document.pages[0].id),
            in: document, isAvailable: true)
        try session.execute(copy.command)
        let page = try XCTUnwrap(session.document.pages.first { $0.id == copy.selectedPageID })
        let byID = Dictionary(uniqueKeysWithValues: page.nodes.map { ($0.id, $0) })
        let instances = page.nodes.filter { $0.kind == .component }
        XCTAssertEqual(instances.count, 2)
        let supplied = try XCTUnwrap(instances.first { !$0.childIDs.isEmpty })
        let empty = try XCTUnwrap(instances.first { $0.childIDs.isEmpty })
        guard case .supplied(let copiedRoots) = CanonicalComponentSlot.state(of: slot.id, on: supplied, nodesByID: byID) else {
            return XCTFail("The duplicated copy keeps its own contents")
        }
        XCTAssertEqual(copiedRoots.count, 2)
        XCTAssertTrue(Set(copiedRoots).isDisjoint(with: Set(roots)))
        XCTAssertEqual(CanonicalComponentSlot.state(of: slot.id, on: empty, nodesByID: byID), .empty)
        try session.document.validate()
        let original = try ComponentGraphResolver.resolvedPage(session.document.pages[0], in: session.document, breakpoint: .desktop)
        let duplicated = try ComponentGraphResolver.resolvedPage(page, in: session.document, breakpoint: .desktop)
        XCTAssertEqual(zip(roots, copiedRoots).map { pair in
            original.nodes.first { $0.id == pair.0 }?.insertionGeometry == duplicated.nodes.first { $0.id == pair.1 }?.insertionGeometry
        }, [true, true], "Same places on the new page")
        try session.undo()
        XCTAssertEqual(session.document.pages, document.pages)
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
        XCTAssertTrue(stylesheet.contains("@media (width < 600px)"))
        XCTAssertTrue(stylesheet.contains("width: 200.0px;"))
        XCTAssertEqual(plan.files.last?.path, "manifest.txt")
        // Lane V14e: the static-layout page links the stylesheet that positions it.
        let html = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(html.contains("<link rel=\"stylesheet\" href=\"styles.css\">"), html)
        XCTAssertEqual(StaticOutputReferenceAudit.unresolved(in: plan), [:])
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
        XCTAssertTrue(stylesheet.contains("@media (width < 600px)"))
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
