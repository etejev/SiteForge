import AppKit
import XCTest
@testable import SiteForge

@MainActor
final class InlineTextEditingModelTests: XCTestCase {
    // SF-0406-001, SF-0406-002, SF-0406-003, SF-0406-005
    func testActivationDraftCommitUsesStablePropertyAndOneExactTransaction() throws {
        let fixture = makeFixture()
        let activation = try fixture.registry.activate(
            nodeID: fixture.textID,
            provenance: .keyboard,
            in: fixture.document,
            context: fixture.context
        )
        XCTAssertEqual(activation.originalText, "Text")
        XCTAssertEqual(activation.identity.nodeID, fixture.textID)

        var session = InlineTextEditingSession()
        session.begin(activation)
        session.update(
            text: "Hello\nworld",
            selection: .init(location: 11, length: 0),
            markedRange: nil
        )
        let draft = try XCTUnwrap(session.draft)
        let prepared = try fixture.registry.prepare(
            draft,
            in: fixture.document,
            context: fixture.context
        )
        let documentSession = DocumentSession(document: fixture.document)
        let result = try documentSession.execute(try XCTUnwrap(prepared.command))
        XCTAssertEqual(result.revision, 1)
        XCTAssertTrue(documentSession.canUndo)
        XCTAssertEqual(text(in: documentSession.document, nodeID: fixture.textID), "Hello\nworld")
        XCTAssertEqual(property(in: documentSession.document, nodeID: fixture.textID)?.id, activation.propertyID)
        XCTAssertEqual(property(in: documentSession.document, nodeID: fixture.textID)?.origin, .authored)

        try documentSession.undo()
        XCTAssertEqual(text(in: documentSession.document, nodeID: fixture.textID), "Text")
        try documentSession.redo()
        XCTAssertEqual(text(in: documentSession.document, nodeID: fixture.textID), "Hello\nworld")
    }

    // SF-0406-002, SF-0406-004
    func testCompositionSelectionAndCancellationRemainEditorOnly() throws {
        let fixture = makeFixture()
        let activation = try fixture.activation()
        var session = InlineTextEditingSession()
        session.begin(activation)
        session.update(
            text: "Téxt",
            selection: .init(location: 1, length: 1),
            markedRange: .init(location: 1, length: 1)
        )
        guard case .composing = session.phase else {
            return XCTFail("Marked text must remain one composing draft.")
        }
        XCTAssertThrowsError(
            try fixture.registry.prepare(
                XCTUnwrap(session.draft),
                in: fixture.document,
                context: fixture.context
            )
        ) { XCTAssertEqual($0 as? TextEditError, .activeComposition) }
        session.cancel()
        XCTAssertEqual(fixture.document.revision, 0)
        XCTAssertEqual(text(in: fixture.document, nodeID: fixture.textID), "Text")
    }

    // SF-0406-003, SF-0406-004
    func testInvalidTextRangeLimitsAndStaleIdentitiesAreRejectedWithoutMutation() throws {
        let fixture = makeFixture()
        let activation = try fixture.activation()
        let committed = fixture.document
        let invalidCases = [
            TextEditDraft(
                activation: activation,
                text: "a\u{0001}b",
                selection: .init(location: 1, length: 0),
                markedRange: nil
            ),
            TextEditDraft(
                activation: activation,
                text: String(repeating: "x", count: InlineTextEditingPolicy.maximumTextBytes + 1),
                selection: .zero,
                markedRange: nil
            ),
            TextEditDraft(
                activation: activation,
                text: "😀",
                selection: .init(location: 1, length: 0),
                markedRange: nil
            ),
        ]
        let expected: [TextEditError] = [.invalidText, .textLimitExceeded, .invalidSelection]
        for (draft, error) in zip(invalidCases, expected) {
            XCTAssertThrowsError(
                try fixture.registry.prepare(draft, in: fixture.document, context: fixture.context)
            ) { XCTAssertEqual($0 as? TextEditError, error) }
        }
        var stale = fixture.document
        stale.revision = 1
        let validDraft = TextEditDraft(
            activation: activation,
            text: "Changed",
            selection: .init(location: 7, length: 0),
            markedRange: nil
        )
        XCTAssertThrowsError(
            try fixture.registry.prepare(validDraft, in: stale, context: fixture.context)
        ) { XCTAssertEqual($0 as? TextEditError, .staleRevision) }
        XCTAssertEqual(fixture.document, committed)
    }

    // SF-0406-004, SF-0406-006
    func testLockedHiddenUnavailableWrongKindAndCrossPageTargetsExposeTypedReasons() throws {
        var fixture = makeFixture()
        let frameID = fixture.document.pages[0].rootNodeIDs[0]
        XCTAssertEqual(
            fixture.registry.availability(
                nodeID: frameID, provenance: .menu,
                in: fixture.document, context: fixture.context
            ).disabledReason,
            TextEditError.incompatibleNode.localizedDescription
        )
        for (key, expected) in [
            ("locked", TextEditError.lockedNode),
            ("hidden", TextEditError.hiddenNode),
        ] {
            fixture.document.pages[0].nodes[1].properties.append(
                NodeProperty(key: .init(rawValue: key), value: .boolean(true))
            )
            XCTAssertThrowsError(try fixture.activation()) {
                XCTAssertEqual($0 as? TextEditError, expected)
            }
            fixture.document.pages[0].nodes[1].properties.removeLast()
        }
        var unavailable = fixture.context
        unavailable = .init(
            activePageID: unavailable.activePageID,
            sceneID: unavailable.sceneID,
            rendererGeneration: unavailable.rendererGeneration,
            availableNodeIDs: [],
            isLifecycleAvailable: true,
            lifecycleDisabledReason: nil
        )
        XCTAssertThrowsError(try fixture.registry.activate(
            nodeID: fixture.textID, provenance: .accessibility,
            in: fixture.document, context: unavailable
        )) { XCTAssertEqual($0 as? TextEditError, .unavailableNode) }
        let otherContext = TextEditValidationContext(
            activePageID: fixture.document.pages[1].id,
            sceneID: fixture.context.sceneID,
            rendererGeneration: fixture.context.rendererGeneration,
            availableNodeIDs: nil,
            isLifecycleAvailable: true,
            lifecycleDisabledReason: nil
        )
        XCTAssertThrowsError(try fixture.registry.activate(
            nodeID: fixture.textID, provenance: .automation,
            in: fixture.document, context: otherContext
        )) { XCTAssertEqual($0 as? TextEditError, .stalePage) }
    }

    // SF-0406-001, SF-0406-004, SF-0406-006
    func testAllProvenancesPrepareEquivalentCommandsAndCancellationIsNeutral() throws {
        let fixture = makeFixture()
        var commands: [DocumentCommand] = []
        for provenance in TextEditProvenance.allCases {
            let activation = try fixture.registry.activate(
                nodeID: fixture.textID,
                provenance: provenance,
                in: fixture.document,
                context: fixture.context
            )
            let draft = TextEditDraft(
                activation: activation,
                text: "Equivalent",
                selection: .init(location: 10, length: 0),
                markedRange: nil
            )
            commands.append(try XCTUnwrap(try fixture.registry.prepare(
                draft,
                in: fixture.document,
                context: fixture.context
            ).command))
        }
        XCTAssertTrue(commands.dropFirst().allSatisfy { $0 == commands.first })

        XCTAssertThrowsError(try fixture.registry.activate(
            nodeID: fixture.textID,
            provenance: .automation,
            in: fixture.document,
            context: fixture.context,
            cancellation: .init(isCancelled: { true })
        )) { XCTAssertEqual($0 as? TextEditError, .cancelled) }
        XCTAssertEqual(text(in: fixture.document, nodeID: fixture.textID), "Text")
    }

    // SF-0406-004, SF-0406-005
    func testWrongDocumentRendererAndRevisionExhaustionRemainNonmutating() throws {
        let fixture = makeFixture()
        let activation = try fixture.activation()
        let draft = TextEditDraft(
            activation: activation,
            text: "Changed",
            selection: .init(location: 7, length: 0),
            markedRange: nil
        )
        let otherDocument = CanonicalDocument(
            id: DocumentID(),
            revision: fixture.document.revision,
            creationKind: fixture.document.creationKind,
            templateID: fixture.document.templateID,
            pages: fixture.document.pages,
            guides: fixture.document.guides
        )
        XCTAssertThrowsError(try fixture.registry.prepare(
            draft, in: otherDocument, context: fixture.context
        )) { XCTAssertEqual($0 as? TextEditError, .staleDocument) }
        let staleRenderer = TextEditValidationContext(
            activePageID: fixture.context.activePageID,
            sceneID: CanvasViewportSceneID(),
            rendererGeneration: fixture.context.rendererGeneration + 1,
            availableNodeIDs: fixture.context.availableNodeIDs,
            isLifecycleAvailable: true,
            lifecycleDisabledReason: nil
        )
        XCTAssertThrowsError(try fixture.registry.prepare(
            draft, in: fixture.document, context: staleRenderer
        )) { XCTAssertEqual($0 as? TextEditError, .staleRenderer) }

        var exhausted = fixture.document
        exhausted.revision = UInt64.max - 1
        let exhaustedActivation = try fixture.registry.activate(
            nodeID: fixture.textID,
            provenance: .automation,
            in: exhausted,
            context: TextEditValidationContext(
                activePageID: fixture.context.activePageID,
                sceneID: fixture.context.sceneID,
                rendererGeneration: exhausted.revision,
                availableNodeIDs: fixture.context.availableNodeIDs,
                isLifecycleAvailable: true,
                lifecycleDisabledReason: nil
            )
        )
        let exhaustedDraft = TextEditDraft(
            activation: exhaustedActivation,
            text: "Exhausted",
            selection: .init(location: 9, length: 0),
            markedRange: nil
        )
        let context = TextEditValidationContext(
            activePageID: fixture.context.activePageID,
            sceneID: fixture.context.sceneID,
            rendererGeneration: exhausted.revision,
            availableNodeIDs: fixture.context.availableNodeIDs,
            isLifecycleAvailable: true,
            lifecycleDisabledReason: nil
        )
        let prepared = try fixture.registry.prepare(
            exhaustedDraft, in: exhausted, context: context
        )
        let session = DocumentSession(document: exhausted)
        XCTAssertThrowsError(try session.execute(try XCTUnwrap(prepared.command))) {
            XCTAssertEqual($0 as? CommandExecutionError, .revisionExhausted)
        }
        XCTAssertEqual(session.document, exhausted)
        XCTAssertFalse(session.canUndo)
    }

    // SF-0406-005
    func testNoChangeProducesNoTransactionAndSerializationContainsOnlyCommittedText() throws {
        let fixture = makeFixture()
        let activation = try fixture.activation()
        let unchanged = TextEditDraft(
            activation: activation,
            text: activation.originalText,
            selection: .init(location: 4, length: 0),
            markedRange: nil
        )
        XCTAssertNil(try fixture.registry.prepare(
            unchanged, in: fixture.document, context: fixture.context
        ).command)

        var changed = unchanged
        changed.text = "Persisted"
        changed.selection = .init(location: 9, length: 0)
        let prepared = try fixture.registry.prepare(
            changed, in: fixture.document, context: fixture.context
        )
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(try XCTUnwrap(prepared.command))
        let first = try DocumentSerializer.encode(session.document)
        let second = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(first, second)
        XCTAssertTrue(String(decoding: first, as: UTF8.self).contains("Persisted"))
        XCTAssertFalse(String(decoding: first, as: UTF8.self).contains("text-edit-session"))
        XCTAssertEqual(try DocumentSerializer.decode(first), session.document)
    }

    // SF-0406-001, SF-0406-004, SF-0406-005
    func testCommittedTextPackageAndHistoryRoundTripWhileDraftStateStaysExcluded() async throws {
        let fixture = makeFixture()
        let activation = try fixture.activation()
        let draft = TextEditDraft(
            activation: activation,
            text: "Durable\nplain text",
            selection: .init(location: 18, length: 0),
            markedRange: nil
        )
        let prepared = try fixture.registry.prepare(
            draft,
            in: fixture.document,
            context: fixture.context
        )
        let session = DocumentSession(document: fixture.document)
        _ = try session.execute(try XCTUnwrap(prepared.command))

        let package = ProjectPackage(
            projectID: ProjectID(UUID(uuidString: "a4000000-0000-4000-8000-000000000001")!),
            createdAt: ProjectTimestamp("2026-07-28T12:00:00.000Z"),
            document: session.document
        )
        let historyStore = PersistedHistoryStore()
        let persisted = try await historyStore.package(package, with: session.historySnapshot())
        let packageStore = ProjectPackageStore()
        let first = try await packageStore.encode(persisted)
        let second = try await packageStore.encode(persisted)
        XCTAssertEqual(first, second)

        let reopened = try await packageStore.decode(first)
        XCTAssertEqual(text(in: reopened.document, nodeID: fixture.textID), draft.text)
        let serializedPackage = String(decoding: first, as: UTF8.self)
        XCTAssertFalse(serializedPackage.contains("text-edit-session"))
        XCTAssertFalse(serializedPackage.contains("markedRange"))
        XCTAssertFalse(serializedPackage.contains("selection"))

        guard case .restored(let history) = try await historyStore.load(from: reopened) else {
            return XCTFail("Expected compatible text-edit history.")
        }
        let reopenedSession = DocumentSession(document: reopened.document)
        try reopenedSession.installValidatedHistory(history)
        try reopenedSession.undo()
        XCTAssertEqual(text(in: reopenedSession.document, nodeID: fixture.textID), "Text")
        try reopenedSession.redo()
        XCTAssertEqual(text(in: reopenedSession.document, nodeID: fixture.textID), draft.text)
    }

    // SF-0406-004, SF-0406-005
    func testExternalNodeRemovalInvalidatesDraftWithoutResurrectingContent() async throws {
        let fixture = makeFixture()
        let documentSession = DocumentSession(document: fixture.document)
        let state = WorkspaceShellState(documentSession: documentSession)
        state.resizeViewport(to: .init(width: 900, height: 600), pixelRatio: 2)
        for _ in 0..<200 where state.canvasRenderPlan == nil { await Task.yield() }
        XCTAssertTrue(state.beginTextEditing(nodeID: fixture.textID, provenance: .automation))
        state.updateTextEditingDraft(
            text: "Uncommitted private draft",
            selection: .init(location: 25, length: 0),
            markedRange: nil
        )

        _ = try documentSession.execute(.removeNode(.init(
            pageID: fixture.document.pages[0].id,
            nodeID: fixture.textID
        )))
        for _ in 0..<50 where state.textEditingSession.isActive { await Task.yield() }

        XCTAssertFalse(state.textEditingSession.isActive)
        XCTAssertNil(documentSession.document.pages[0].nodes.first {
            $0.id == fixture.textID
        })
        XCTAssertEqual(documentSession.historySnapshot().undoEntries.count, 1)
    }

    // SF-0406-008
    func testDiagnosticsContainOnlySanitizedIdentityCountsAndCategories() async throws {
        let fixture = makeFixture(text: "private authored phrase")
        let activation = try fixture.activation()
        let draft = TextEditDraft(
            activation: activation,
            text: "replacement private phrase",
            selection: .init(location: 26, length: 0),
            markedRange: nil
        )
        let record = TextEditDiagnosticFactory.make(
            operation: "commit",
            draft: draft,
            durationMilliseconds: 0.2,
            result: .failure,
            failure: .staleRevision
        )
        let description = String(describing: record)
        XCTAssertFalse(description.contains("private authored phrase"))
        XCTAssertFalse(description.contains("replacement private phrase"))
        XCTAssertFalse(description.contains("/Users/"))
        XCTAssertEqual(record.requirementIDs, InlineTextCommandRegistry.requirementIDs.sorted())
        XCTAssertEqual(record.originalUTF8Bytes, 23)
        XCTAssertNil(record.resultUTF8Bytes)
        let activationFailure = TextEditDiagnosticFactory.makeActivationFailure(
            nodeID: fixture.textID,
            pageID: fixture.document.pages[0].id,
            durationMilliseconds: 0.1,
            failure: .lockedNode
        )
        XCTAssertEqual(activationFailure.operation, "activate")
        XCTAssertEqual(activationFailure.originalUTF8Bytes, 0)
        XCTAssertFalse(String(describing: activationFailure).contains("private authored phrase"))
    }

    // SF-0406-007, SF-0406-008
    func testPreparationCapacityAt100And10000ObjectsIsDeterministicAndBounded() throws {
        for count in [100, 10_000] {
            var fixture = makeFixture(objectCount: count)
            let textIndex = fixture.document.pages[0].nodes.firstIndex {
                $0.id == fixture.textID
            }!
            let textNode = fixture.document.pages[0].nodes.remove(at: textIndex)
            fixture.document.pages[0].nodes.append(textNode)
            let activation = try fixture.activation()
            let draft = TextEditDraft(
                activation: activation,
                text: "Capacity edit",
                selection: .init(location: 13, length: 0),
                markedRange: nil
            )
            var samples: [Double] = []
            for _ in 0..<4 {
                let start = DispatchTime.now().uptimeNanoseconds
                let prepared = try fixture.registry.prepare(
                    draft, in: fixture.document, context: fixture.context
                )
                XCTAssertNotNil(prepared.command)
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            samples.sort()
            let p95 = samples[min(samples.count - 1, Int(Double(samples.count) * 0.95))]
            print("TEXT_EDIT_EVIDENCE objects=\(count) p95Milliseconds=\(p95) samples=\(samples)")
        }
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        print("TEXT_EDIT_EVIDENCE maximumResidentBytes=\(max(0, usage.ru_maxrss))")
    }

    // SF-0406-004, SF-0406-006
    func testNativeEditorCopyCutPastePreservesPlainTextAndSelection() {
        let editor = InlineCanvasTextView()
        editor.string = "Edited"
        editor.setSelectedRange(NSRange(location: 0, length: 6))

        editor.copy(nil)
        editor.cut(nil)
        XCTAssertEqual(editor.string, "")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 0))

        editor.paste(nil)
        XCTAssertEqual(editor.string, "Edited")
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 6, length: 0))
        XCTAssertFalse(editor.isRichText)
        XCTAssertFalse(editor.allowsUndo)
        XCTAssertTrue(editor.acceptsFirstResponder)
    }

    // SF-0406-004, SF-0406-006
    func testWindowLocalTextKeyRoutingCommitsCancelsAndProtectsComposition() {
        XCTAssertEqual(
            TextEditKeyRoutingPolicy.decision(
                key: .returnKey,
                isCommandModified: true,
                hasUnsupportedModifiers: false,
                isEditing: true,
                hasMarkedText: false
            ),
            .commit
        )
        XCTAssertEqual(
            TextEditKeyRoutingPolicy.decision(
                key: .escape,
                isCommandModified: false,
                hasUnsupportedModifiers: false,
                isEditing: true,
                hasMarkedText: true
            ),
            .cancel
        )
        for decision in [
            TextEditKeyRoutingPolicy.decision(
                key: .returnKey,
                isCommandModified: true,
                hasUnsupportedModifiers: false,
                isEditing: true,
                hasMarkedText: true
            ),
            TextEditKeyRoutingPolicy.decision(
                key: .returnKey,
                isCommandModified: true,
                hasUnsupportedModifiers: true,
                isEditing: true,
                hasMarkedText: false
            ),
            TextEditKeyRoutingPolicy.decision(
                key: .escape,
                isCommandModified: false,
                hasUnsupportedModifiers: false,
                isEditing: false,
                hasMarkedText: false
            ),
        ] {
            XCTAssertEqual(decision, .passThrough)
        }
    }

    private struct Fixture {
        var document: CanonicalDocument
        let textID: NodeID
        let sceneID: CanvasViewportSceneID
        let registry = InlineTextCommandRegistry()

        var context: TextEditValidationContext {
            TextEditValidationContext(
                activePageID: document.pages[0].id,
                sceneID: sceneID,
                rendererGeneration: document.revision,
                availableNodeIDs: Set(document.pages[0].nodes.map(\.id)),
                isLifecycleAvailable: true,
                lifecycleDisabledReason: nil
            )
        }

        func activation() throws -> TextEditActivation {
            try registry.activate(
                nodeID: textID,
                provenance: .automation,
                in: document,
                context: context
            )
        }
    }

    private func makeFixture(text: String = "Text", objectCount: Int = 2) -> Fixture {
        var document = ProjectCreation.blank()
        let rootID = document.pages[0].rootNodeIDs[0]
        let textID = NodeID(UUID(uuidString: "a1000000-0000-4000-8000-000000000001")!)
        let textProperty = NodeProperty(
            id: PropertyID(UUID(uuidString: "a2000000-0000-4000-8000-000000000001")!),
            key: .init(rawValue: "content.text"),
            value: .string(text),
            origin: .defaulted
        )
        document.pages[0].nodes[0].childIDs = [textID]
        document.pages[0].nodes.append(DocumentNode(
            id: textID,
            kind: .text,
            name: "Text",
            parent: .node(rootID),
            properties: [
                NodeProperty(key: .init(rawValue: "layout.x"), value: .number(20), origin: .defaulted),
                NodeProperty(key: .init(rawValue: "layout.y"), value: .number(20), origin: .defaulted),
                NodeProperty(key: .init(rawValue: "layout.width"), value: .number(120), origin: .defaulted),
                NodeProperty(key: .init(rawValue: "layout.height"), value: .number(24), origin: .defaulted),
                textProperty,
            ]
        ))
        if objectCount > 2 {
            for index in 2..<objectCount {
                let id = NodeID(UUID(uuidString: String(
                    format: "a3000000-0000-4000-8000-%012d", index
                ))!)
                document.pages[0].nodes[0].childIDs.append(id)
                document.pages[0].nodes.append(DocumentNode(
                    id: id,
                    kind: .frame,
                    name: "Capacity",
                    parent: .node(rootID)
                ))
            }
        }
        return Fixture(document: document, textID: textID, sceneID: CanvasViewportSceneID())
    }

    private func property(in document: CanonicalDocument, nodeID: NodeID) -> NodeProperty? {
        document.pages.flatMap(\.nodes).first(where: { $0.id == nodeID })?
            .properties.first(where: { $0.key.rawValue == "content.text" })
    }

    private func text(in document: CanonicalDocument, nodeID: NodeID) -> String? {
        guard case .string(let value) = property(in: document, nodeID: nodeID)?.value else {
            return nil
        }
        return value
    }
}
