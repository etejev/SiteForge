import XCTest
@testable import SiteForge

@MainActor
final class DocumentLifecycleRaceTests: XCTestCase {
    nonisolated(unsafe) private var fixtureLease: ApplicationOwnedTestFixture!

    nonisolated override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureLease = try ApplicationOwnedTestFixture.create("lifecycle-races")
    }

    nonisolated override func tearDownWithError() throws {
        try fixtureLease.cleanup()
        try super.tearDownWithError()
    }

    // SF-0301-002, SF-0301-004, SF-0306-004, SF-1902-004
    func testTypedOperationIdentityIsCompleteAndDiagnosticsRemainRedacted() async throws {
        let probe = LifecycleBackendProbe()
        let context = try await makeContext("Identity", probe: probe)
        try addPage("Private client material", to: context.controller)
        let saved = await context.controller.save()
        XCTAssertTrue(saved)

        let operations = await probe.operations(at: .afterFilesystemWrite)
        let operation = try XCTUnwrap(operations.last { $0.intent == .save })
        XCTAssertEqual(operation.documentID, context.controller.session.document.id)
        XCTAssertEqual(operation.projectID, context.controller.currentProjectID)
        XCTAssertEqual(operation.revision, context.controller.session.document.revision)
        XCTAssertEqual(operation.destination.kind, .durable)
        XCTAssertNotNil(operation.destination.sanitizedToken)

        let diagnostics = await context.controller.backend.diagnosticRecords()
        let record = try XCTUnwrap(diagnostics.last { $0.operation == .save })
        XCTAssertEqual(record.revision, operation.revision)
        XCTAssertEqual(record.destinationKind, .durable)
        XCTAssertFalse(record.sanitizedOperationID.contains(operation.id.rawValue.uuidString))
        XCTAssertFalse(String(describing: diagnostics).contains(context.durable.deletingLastPathComponent().path))
        XCTAssertFalse(String(describing: diagnostics).contains("Private client material"))
    }

    // SF-0301-002, SF-0301-004, SF-0306-003, SF-0306-004
    func testSaveCrossedWithEveryDocumentTransitionCannotReattachStaleStateOrWriteBytes() async throws {
        for transition in TransitionCase.allCases {
            let probe = LifecycleBackendProbe()
            let context = try await makeContext("Save-\(transition.rawValue)", probe: probe)
            if transition == .restore { try await seedRecoveryCandidate(in: context) }
            try addPage("Protected save draft", to: context.controller)
            let beforeSave = context.controller.stateSnapshot
            let diskBefore = try Data(contentsOf: context.durable)

            await probe.block(.beforeFilesystemWrite, intent: .save)
            let save = Task { await context.controller.save() }
            await probe.waitUntilBlocked()
            let oldEpoch = context.controller.currentLifecycleEpoch
            let documentTransition = start(transition, context: context)
            await resolveDiscardIfPresented(context.controller)
            await waitForEpochChange(context.controller, from: oldEpoch)
            await probe.release()

            let saveResult = await save.value
            let transitionResult = await documentTransition.value
            let saveWrites = await probe.writeCount(.save)
            XCTAssertFalse(saveResult, "Save should be stale for \(transition.rawValue)")
            XCTAssertEqual(transitionResult, .completed)
            XCTAssertEqual(try Data(contentsOf: context.durable), diskBefore)
            XCTAssertEqual(saveWrites, 0)
            try assertAdoptedState(for: transition, context: context, prior: beforeSave)
        }
    }

    // SF-0301-005, SF-0306-003, SF-0306-005
    func testExecutingAutosaveCrossedWithEveryDocumentTransitionIsCancelledBeforeCommit() async throws {
        for transition in TransitionCase.allCases {
            let probe = LifecycleBackendProbe()
            let debouncer = ManualLifecycleAutosaveDebouncer()
            let context = try await makeContext(
                "Autosave-\(transition.rawValue)",
                probe: probe,
                debouncer: debouncer
            )
            if transition == .restore { try await seedRecoveryCandidate(in: context) }
            try addPage("Protected autosave draft", to: context.controller)
            await debouncer.waitUntilPending()
            await probe.block(.beforeFilesystemWrite, intent: .autosave)
            debouncer.fireAll()
            await probe.waitUntilBlocked()
            let prior = context.controller.stateSnapshot
            let oldEpoch = context.controller.currentLifecycleEpoch

            let documentTransition = start(transition, context: context)
            await resolveDiscardIfPresented(context.controller)
            await waitForEpochChange(context.controller, from: oldEpoch)
            await probe.release()

            let transitionResult = await documentTransition.value
            let autosaveWrites = await probe.writeCount(.autosave)
            XCTAssertEqual(transitionResult, .completed)
            XCTAssertEqual(autosaveWrites, 0)
            try assertAdoptedState(for: transition, context: context, prior: prior)
        }
    }

    // SF-0306-003, SF-0306-004, SF-0306-005 — a validated recovery remains
    // restorable while a newer edit is pending or executing, then is retired
    // only once replacement bytes have committed under the owned fingerprint.
    func testValidatedRecoveryCandidateRemainsUntilReplacementAutosaveCommits() async throws {
        let probe = LifecycleBackendProbe()
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let context = try await makeContext(
            "RecoveryCandidateReplacement",
            probe: probe,
            debouncer: debouncer
        )
        try await seedRecoveryCandidate(in: context)
        let originalCandidate = try XCTUnwrap(context.controller.recoveryCandidate)

        try addPage("Current edit replaces candidate", to: context.controller)
        await debouncer.waitUntilPending()
        XCTAssertEqual(context.controller.recoveryCandidate, originalCandidate)

        await probe.block(.beforeFilesystemWrite, intent: .autosave)
        debouncer.fireAll()
        await probe.waitUntilBlocked()
        XCTAssertEqual(context.controller.recoveryCandidate, originalCandidate)

        await probe.release()
        await waitUntil { !context.controller.hasPendingAutosaveWork }
        XCTAssertNil(context.controller.recoveryCandidate)
        XCTAssertNil(context.controller.failure)

        let replacement = try await ProjectPackageStore().read(
            from: DocumentLifecycleBackend.recoveryURL(
                for: context.controller.currentProjectID,
                in: context.recoveryDirectory
            )
        )
        XCTAssertEqual(replacement.document, context.controller.session.document)
        XCTAssertNotEqual(replacement.document, originalCandidate.package.document)
    }

    // SF-0301-005, SF-0306-003, SF-0306-004, SF-0306-005
    func testPendingAutosaveIsCancelledAndDrainedBeforeManualSave() async throws {
        let probe = LifecycleBackendProbe()
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let context = try await makeContext("PendingThenSave", probe: probe, debouncer: debouncer)
        try addPage("Latest durable revision", to: context.controller)
        await debouncer.waitUntilPending()

        let saved = await context.controller.save()
        let autosaveWrites = await probe.writeCount(.autosave)
        let saveWrites = await probe.writeCount(.save)
        let durableDocument = try await ProjectPackageStore().read(from: context.durable).document
        XCTAssertTrue(saved)
        XCTAssertEqual(autosaveWrites, 0)
        XCTAssertEqual(saveWrites, 1)
        XCTAssertEqual(durableDocument, context.controller.session.document)
        XCTAssertEqual(context.controller.phase, .clean)
    }

    // SF-0301-005, SF-0303-005, SF-0306-003, SF-0306-005, SF-0307-005
    func testAutosaveBurstCoalescesOnceAndSeparatedEditWritesNextRevisionExactly() async throws {
        let probe = LifecycleBackendProbe()
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let context = try await makeContext("ExactCoalescing", probe: probe, debouncer: debouncer)

        try addPage("Burst one", to: context.controller)
        try addPage("Burst two", to: context.controller)
        try addPage("Burst three", to: context.controller)
        let burstRevision = context.controller.session.document.revision
        await debouncer.waitUntilPending()
        let writesBeforeFire = await probe.writeCount(.autosave)
        XCTAssertEqual(writesBeforeFire, 0)
        debouncer.fireAll()
        await probe.waitForEvent(.afterFilesystemWrite, intent: .autosave, count: 1)

        try addPage("Separated edit", to: context.controller)
        let separatedRevision = context.controller.session.document.revision
        await debouncer.waitUntilPending()
        debouncer.fireAll()
        await probe.waitForEvent(.afterFilesystemWrite, intent: .autosave, count: 2)

        let writes = await probe.completedWriteOrder().filter { $0.intent == .autosave }
        XCTAssertEqual(writes, [
            CompletedLifecycleWrite(intent: .autosave, revision: burstRevision),
            CompletedLifecycleWrite(intent: .autosave, revision: separatedRevision),
        ])
    }

    // SF-0301-005, SF-0306-003, SF-0306-004, SF-0306-005
    func testExecutingAutosaveIsCancelledAndDrainedBeforeManualSave() async throws {
        let probe = LifecycleBackendProbe()
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let context = try await makeContext("ExecutingThenSave", probe: probe, debouncer: debouncer)
        try addPage("Explicit save wins", to: context.controller)
        await debouncer.waitUntilPending()
        await probe.block(.beforeFilesystemWrite, intent: .autosave)
        debouncer.fireAll()
        await probe.waitUntilBlocked()

        let save = Task { await context.controller.save() }
        await waitUntil { !context.controller.hasPendingAutosaveWork }
        await probe.release()
        let saved = await save.value
        let autosaveWrites = await probe.writeCount(.autosave)
        let saveWrites = await probe.writeCount(.save)
        let durableDocument = try await ProjectPackageStore().read(from: context.durable).document
        XCTAssertTrue(saved)

        XCTAssertEqual(autosaveWrites, 0)
        XCTAssertEqual(saveWrites, 1)
        XCTAssertEqual(durableDocument, context.controller.session.document)
        XCTAssertEqual(context.controller.phase, .clean)
    }

    // SF-0301-005, SF-0306-003, SF-0306-004, SF-0306-005 — a cancelled
    // autosave that already committed bytes contributes its exact fingerprint
    // before a later revision attempts the next conditional replacement.
    func testPostCommitAutosaveCancellationSerializesNextRecoveryRevision() async throws {
        let probe = LifecycleBackendProbe()
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let context = try await makeContext("PostCommitAutosave", probe: probe, debouncer: debouncer)
        try addPage("First recovery revision", to: context.controller)
        let first = context.controller.session.document
        await debouncer.waitUntilPending()
        await probe.block(.afterFilesystemWrite, intent: .autosave)
        debouncer.fireAll()
        await probe.waitUntilBlocked()

        try addPage("Second recovery revision", to: context.controller)
        let second = context.controller.session.document
        await probe.release()
        await debouncer.waitUntilPending()
        debouncer.fireAll()
        await probe.waitForEvent(.afterFilesystemWrite, intent: .autosave, count: 2)

        let recovery = try await ProjectPackageStore().read(
            from: DocumentLifecycleBackend.recoveryURL(for: context.controller.currentProjectID, in: context.recoveryDirectory)
        )
        XCTAssertEqual(recovery.document, second)
        XCTAssertNil(context.controller.failure)
        let autosaveOrder = await probe.completedWriteOrder().filter { $0.intent == .autosave }
        XCTAssertEqual(
            autosaveOrder,
            [
                CompletedLifecycleWrite(intent: .autosave, revision: first.revision),
                CompletedLifecycleWrite(intent: .autosave, revision: second.revision),
            ]
        )
    }

    // SF-0301-005, SF-0306-003, SF-0306-004 — explicit Save drains a
    // post-commit autosave, learns its recovery identity, and removes only
    // that owned recovery after the durable revision succeeds.
    func testManualSaveDrainsPostCommitAutosaveAndCleansOwnedRecovery() async throws {
        let probe = LifecycleBackendProbe()
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let context = try await makeContext("PostCommitAutosaveSave", probe: probe, debouncer: debouncer)
        try addPage("Durable after recovery", to: context.controller)
        await debouncer.waitUntilPending()
        await probe.block(.afterFilesystemWrite, intent: .autosave)
        debouncer.fireAll()
        await probe.waitUntilBlocked()

        let save = Task { await context.controller.save() }
        await Task.yield()
        await probe.release()
        let saved = await save.value
        XCTAssertTrue(saved)

        let autosaveWrites = await probe.writeCount(.autosave)
        let saveWrites = await probe.writeCount(.save)
        XCTAssertEqual(autosaveWrites, 1)
        XCTAssertEqual(saveWrites, 1)
        XCTAssertEqual(context.controller.phase, .clean)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(
            for: context.controller.currentProjectID,
            in: context.recoveryDirectory
        )
        let retired = try await ProjectPackageStore().isRetiredRecoveryTombstone(
            at: recoveryURL,
            projectID: context.controller.currentProjectID
        )
        XCTAssertTrue(retired)
    }

    // SF-0301-005, SF-0306-003, SF-0306-004, SF-0306-005
    func testEditDuringSaveKeepsSavedRevisionDurableAndNewerRevisionRecoverable() async throws {
        let probe = LifecycleBackendProbe()
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let context = try await makeContext("EditDuringSave", probe: probe, debouncer: debouncer)
        try addPage("Saved revision", to: context.controller)
        let savedRevision = context.controller.session.document
        await probe.block(.beforeFilesystemWrite, intent: .save)
        let save = Task { await context.controller.save() }
        await probe.waitUntilBlocked()

        try addPage("Newer recoverable revision", to: context.controller)
        let activeRevision = context.controller.session.document
        await debouncer.waitUntilPending()
        await probe.release()
        let saved = await save.value
        let durableDocument = try await ProjectPackageStore().read(from: context.durable).document
        XCTAssertTrue(saved)

        XCTAssertEqual(durableDocument, savedRevision)
        XCTAssertEqual(context.controller.session.document, activeRevision)
        XCTAssertEqual(context.controller.phase, .modified)
        XCTAssertTrue(context.controller.isModified)

        debouncer.fireAll()
        await probe.waitForEvent(.afterFilesystemWrite, intent: .autosave, count: 1)
        let recovery = try await ProjectPackageStore().read(
            from: DocumentLifecycleBackend.recoveryURL(
                for: context.controller.currentProjectID,
                in: context.recoveryDirectory
            )
        )
        XCTAssertEqual(recovery.document, activeRevision)
        let completedWrites = await probe.completedWriteOrder()
        XCTAssertEqual(completedWrites, [
            CompletedLifecycleWrite(intent: .save, revision: savedRevision.revision),
            CompletedLifecycleWrite(intent: .autosave, revision: activeRevision.revision),
        ])
    }

    // SF-0301-005, SF-0306-003, SF-0306-004
    func testSaveAsCancelsPendingAutosaveAndUsesDistinctIntent() async throws {
        let probe = LifecycleBackendProbe()
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let recoveryDirectory = fixture("SaveAs-Recovery", isDirectory: true)
        let controller = makeController(probe: probe, debouncer: debouncer, recoveryDirectory: recoveryDirectory)
        try addPage("Untitled save as", to: controller)
        await debouncer.waitUntilPending()
        let target = fixture("SaveAs.siteforge")

        let saved = await controller.save(to: target)
        let autosaveWrites = await probe.writeCount(.autosave)
        let saveAsWrites = await probe.writeCount(.saveAs)
        let durableDocument = try await ProjectPackageStore().read(from: target).document
        XCTAssertTrue(saved)
        XCTAssertEqual(autosaveWrites, 0)
        XCTAssertEqual(saveAsWrites, 1)
        XCTAssertEqual(controller.fileURL, target)
        XCTAssertEqual(controller.phase, .clean)
        XCTAssertEqual(durableDocument, controller.session.document)
    }

    // SF-0301-002, SF-0301-004, SF-0306-004
    func testSuccessfulCompletionAfterEpochInvalidationCannotMutateNewDocumentState() async throws {
        let probe = LifecycleBackendProbe()
        let context = try await makeContext("StaleSuccess", probe: probe)
        try addPage("Committed before stale completion", to: context.controller)
        let savedDocument = context.controller.session.document
        await probe.block(.afterFilesystemWrite, intent: .save)
        let save = Task { await context.controller.save() }
        await probe.waitUntilBlocked()

        let oldEpoch = context.controller.currentLifecycleEpoch
        let newDocument = Task { await context.controller.requestNewDocument() }
        await resolveDiscardIfPresented(context.controller)
        await waitForEpochChange(context.controller, from: oldEpoch)
        await probe.release()

        let saveResult = await save.value
        let transitionResult = await newDocument.value
        let durableDocument = try await ProjectPackageStore().read(from: context.durable).document
        XCTAssertFalse(saveResult)
        XCTAssertEqual(transitionResult, .completed)
        XCTAssertEqual(context.controller.phase, .clean)
        XCTAssertNil(context.controller.fileURL)
        XCTAssertNotEqual(context.controller.currentProjectID, context.projectID)
        XCTAssertEqual(durableDocument, savedDocument)
    }

    // SF-0301-004, SF-0306-003, SF-0306-004
    func testFailedCompletionForOlderRevisionIsStateNeutral() async throws {
        let probe = LifecycleBackendProbe()
        let backend = DocumentLifecycleBackend(observer: probe)
        let context = try await makeContext("StaleFailure", backend: backend, probe: probe)
        try addPage("Revision being saved", to: context.controller)
        await probe.block(.beforeWritePreparation, intent: .save)
        let save = Task { await context.controller.save() }
        await probe.waitUntilBlocked()

        try addPage("Newer active revision", to: context.controller)
        let expected = context.controller.stateSnapshot
        await backend.configureForTesting(fault: .io)
        await probe.release()

        let saveResult = await save.value
        XCTAssertFalse(saveResult)
        assertState(context.controller.stateSnapshot, equals: expected, includingEpoch: true)
        XCTAssertEqual(try Data(contentsOf: context.durable), context.durableBytes)
    }

    // SF-0301-004, SF-0306-003, SF-0306-004, SF-1902-004
    func testCancellationBeforeAndAfterBackendPreparationIsStateNeutral() async throws {
        for checkpoint in [LifecycleBackendCheckpoint.beforeWritePreparation, .beforeFilesystemWrite] {
            let probe = LifecycleBackendProbe()
            let context = try await makeContext("Cancel-\(String(describing: checkpoint))", probe: probe)
            try addPage("Cancelled save", to: context.controller)
            let expected = context.controller.stateSnapshot
            await probe.block(checkpoint, intent: .save)
            let save = Task { await context.controller.save() }
            await probe.waitUntilBlocked()

            save.cancel()
            await probe.release()
            let saveResult = await save.value
            let saveWrites = await probe.writeCount(.save)
            XCTAssertFalse(saveResult)
            assertState(context.controller.stateSnapshot, equals: expected, includingEpoch: true)
            XCTAssertEqual(try Data(contentsOf: context.durable), context.durableBytes)
            XCTAssertEqual(saveWrites, 0)
        }
    }

    // SF-0301-004, SF-0306-003, SF-0306-004, SF-0306-005 — a newer
    // transition claims ownership before it displays its authorization. That
    // claim must cancel an older Open at the pre-adoption recovery-retirement
    // seam, preserving both the active canonical state and recovery bytes.
    func testSupersedingTransitionPreventsOlderOpenFromRetiringRecoveryOrAdopting() async throws {
        let probe = LifecycleBackendProbe()
        let context = try await makeContext("SupersedingTransition", probe: probe)
        try await seedRecoveryCandidate(in: context)
        try addPage("Original document remains active", to: context.controller)

        var staleIncoming = ProjectCreation.blank()
        staleIncoming.pages[0].name = "Stale incoming project"
        try await ProjectPackageStore().write(ProjectPackage(document: staleIncoming), to: context.incoming)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(
            for: context.controller.currentProjectID,
            in: context.recoveryDirectory
        )
        let recoveryBytes = try Data(contentsOf: recoveryURL)

        await probe.block(.beforeRecoveryDeletion, intent: .discardRecovery)
        let olderOpen = Task { @MainActor in
            await context.controller.requestOpen(context.incoming)
        }
        await resolveDiscardIfPresented(context.controller)
        await probe.waitUntilBlocked()
        let expected = context.controller.stateSnapshot

        // This newer request remains at its real unsaved-changes prompt while
        // the first operation is released. Observing that prompt proves it has
        // claimed the attempt before the older backend is allowed to commit.
        let newerTransition = Task { @MainActor in
            await context.controller.requestNewDocument()
        }
        await waitUntil {
            context.controller.pendingUnsavedChangesPrompt?.transition == .newDocument
        }
        let newerPrompt = try XCTUnwrap(context.controller.pendingUnsavedChangesPrompt)

        await probe.release()
        let olderResult = await olderOpen.value
        XCTAssertEqual(olderResult, .cancelled)
        assertState(context.controller.stateSnapshot, equals: expected, includingEpoch: true)
        XCTAssertNil(context.controller.failure)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), recoveryBytes)
        let readOperations = await probe.operations(at: .beforeRead)
        XCTAssertEqual(readOperations.filter { $0.intent == .open }.count, 2)

        context.controller.resolveUnsavedChanges(.cancel, promptID: newerPrompt.id)
        let newerResult = await newerTransition.value
        XCTAssertEqual(newerResult, .cancelled)
    }

    // SF-0301-004, SF-0306-003, SF-0306-004, SF-0306-005 — the lifecycle
    // attempt must remain authoritative through the descriptor layer's final
    // logical-retirement exchange, not merely until it starts recovery I/O.
    func testSupersedingTransitionAtFinalRecoveryRetirementCommitPreservesCandidateAndBytes() async throws {
        let probe = LifecycleBackendProbe()
        let retirementBarrier = RecoveryRetirementCommitBarrier()
        let backend = DocumentLifecycleBackend(
            store: ProjectPackageStore(ioObserver: retirementBarrier),
            observer: probe
        )
        let context = try await makeContext(
            "SupersedingRetirementCommit",
            backend: backend,
            probe: probe
        )
        try await seedRecoveryCandidate(in: context)
        try addPage("Original document remains active", to: context.controller)
        let originalCandidate = try XCTUnwrap(context.controller.recoveryCandidate)

        var staleIncoming = ProjectCreation.blank()
        staleIncoming.pages[0].name = "Stale incoming project"
        try await ProjectPackageStore().write(ProjectPackage(document: staleIncoming), to: context.incoming)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(
            for: context.controller.currentProjectID,
            in: context.recoveryDirectory
        )
        let recoveryBytes = try Data(contentsOf: recoveryURL)

        let olderOpen = Task { @MainActor in
            await context.controller.requestOpen(context.incoming)
        }
        await resolveDiscardIfPresented(context.controller)
        await retirementBarrier.waitUntilReached()
        let expected = context.controller.stateSnapshot
        XCTAssertEqual(expected.recoveryCandidate, originalCandidate)

        let newerTransition = Task { @MainActor in
            await context.controller.requestNewDocument()
        }
        await waitUntil {
            context.controller.pendingUnsavedChangesPrompt?.transition == .newDocument
        }
        let newerPrompt = try XCTUnwrap(context.controller.pendingUnsavedChangesPrompt)

        await retirementBarrier.release()
        let olderResult = await olderOpen.value
        XCTAssertEqual(olderResult, .cancelled)
        assertState(context.controller.stateSnapshot, equals: expected, includingEpoch: true)
        XCTAssertEqual(try Data(contentsOf: recoveryURL), recoveryBytes)
        XCTAssertEqual(context.controller.recoveryCandidate, originalCandidate)
        XCTAssertNil(context.controller.failure)

        context.controller.resolveUnsavedChanges(.cancel, promptID: newerPrompt.id)
        let newerResult = await newerTransition.value
        XCTAssertEqual(newerResult, .cancelled)
    }

    // SF-0301-004, SF-0306-003, SF-0306-004, SF-0306-005 — standalone
    // Discard holds the same final-commit lease as transition-owned cleanup.
    // A New boundary that wins while the descriptor layer is ready to retire
    // bytes cancels the exchange and leaves the old artifact recoverable.
    func testNewDocumentSupersedesStandaloneRecoveryDiscardAtFinalCommit() async throws {
        let probe = LifecycleBackendProbe()
        let retirementBarrier = RecoveryRetirementCommitBarrier()
        let backend = DocumentLifecycleBackend(
            store: ProjectPackageStore(ioObserver: retirementBarrier),
            observer: probe
        )
        let context = try await makeContext(
            "StandaloneDiscardRetirementCommit",
            backend: backend,
            probe: probe
        )
        try await seedRecoveryCandidate(in: context)
        let originalCandidate = try XCTUnwrap(context.controller.recoveryCandidate)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(
            for: context.controller.currentProjectID,
            in: context.recoveryDirectory
        )
        let recoveryBytes = try Data(contentsOf: recoveryURL)

        let discard = Task { @MainActor in
            await context.controller.discardRecovery()
        }
        await retirementBarrier.waitUntilReached()

        let oldEpoch = context.controller.currentLifecycleEpoch
        let newDocument = Task { @MainActor in
            await context.controller.requestNewDocument()
        }
        await waitForEpochChange(context.controller, from: oldEpoch)
        await retirementBarrier.release()

        await discard.value
        let newDocumentResult = await newDocument.value
        XCTAssertEqual(newDocumentResult, .completed)
        XCTAssertEqual(context.controller.phase, .clean)
        XCTAssertNil(context.controller.fileURL)
        XCTAssertNil(context.controller.failure)
        XCTAssertEqual(context.controller.session.document.pages.map(\.name), ["Home", "Not Found"])
        XCTAssertEqual(try Data(contentsOf: recoveryURL), recoveryBytes)
        let retired = try await ProjectPackageStore().isRetiredRecoveryTombstone(
            at: recoveryURL,
            projectID: originalCandidate.package.projectID
        )
        XCTAssertFalse(retired)

        let relaunched = makeController(
            backend: DocumentLifecycleBackend(),
            probe: LifecycleBackendProbe(),
            debouncer: ManualLifecycleAutosaveDebouncer(),
            recoveryDirectory: context.recoveryDirectory
        )
        await relaunched.discoverUntitledRecoveryCandidate()
        XCTAssertEqual(relaunched.recoveryCandidate?.fingerprint, originalCandidate.fingerprint)
        XCTAssertEqual(relaunched.recoveryCandidate?.package, originalCandidate.package)
    }

    private func makeContext(
        _ name: String,
        backend: DocumentLifecycleBackend? = nil,
        probe: LifecycleBackendProbe,
        debouncer: any LifecycleAutosaveDebouncing = ManualLifecycleAutosaveDebouncer()
    ) async throws -> LifecycleRaceContext {
        let recoveryDirectory = fixture("\(name)-Recovery", isDirectory: true)
        let resolvedBackend = backend ?? DocumentLifecycleBackend(observer: probe)
        let controller = makeController(
            backend: resolvedBackend,
            probe: probe,
            debouncer: debouncer,
            recoveryDirectory: recoveryDirectory
        )
        let durable = fixture("\(name)-Durable.siteforge")
        let saved = await controller.save(to: durable)
        let saveDiagnostics = await resolvedBackend.diagnosticRecords()
        XCTAssertTrue(
            saved,
            "Initial durable save failed: phase=\(controller.phase), failure=\(String(describing: controller.failure)), adopted=\(controller.fileURL != nil), diagnostics: \(String(describing: saveDiagnostics.last))"
        )
        let projectID = controller.currentProjectID
        let durableBytes = try Data(contentsOf: durable)
        await probe.reset()
        return LifecycleRaceContext(
            controller: controller,
            durable: durable,
            incoming: fixture("\(name)-Incoming.siteforge"),
            recoveryDirectory: recoveryDirectory,
            projectID: projectID,
            durableBytes: durableBytes
        )
    }

    private func makeController(
        backend: DocumentLifecycleBackend? = nil,
        probe: LifecycleBackendProbe,
        debouncer: any LifecycleAutosaveDebouncing,
        recoveryDirectory: URL
    ) -> DocumentLifecycleController {
        DocumentLifecycleController(
            session: DocumentSession(document: ProjectCreation.blank()),
            backend: backend ?? DocumentLifecycleBackend(observer: probe),
            recoveryDirectory: recoveryDirectory,
            saveDestinationProvider: { _ in nil },
            autosaveDebouncer: debouncer,
            clock: LifecycleClock(now: { Date(timeIntervalSince1970: 1_700_000_000) })
        )
    }

    private func seedRecoveryCandidate(in context: LifecycleRaceContext) async throws {
        let durablePackage = try await ProjectPackageStore().read(from: context.durable)
        let recoveredSession = DocumentSession(document: durablePackage.document)
        try recoveredSession.execute(.insertPage(InsertPageCommand(
            page: DocumentPage(name: "Recovery winner"),
            index: recoveredSession.document.pages.count
        )))
        let recovered = ProjectPackage(
            projectID: durablePackage.projectID,
            createdAt: durablePackage.createdAt,
            modifiedAt: ProjectTimestamp("2026-07-19T18:00:00.000Z"),
            document: recoveredSession.document,
            optionalMembers: durablePackage.optionalMembers,
            compatibility: durablePackage.compatibility
        )
        let store = ProjectPackageStore()
        try await store.prepareRecoveryDirectory(context.recoveryDirectory)
        try await store.write(
            recovered,
            to: DocumentLifecycleBackend.recoveryURL(
                for: durablePackage.projectID,
                in: context.recoveryDirectory
            ),
            policy: .recovery(durablePackage.projectID)
        )
        let openResult = await context.controller.requestOpen(context.durable)
        XCTAssertEqual(openResult, .completed)
        XCTAssertNotNil(context.controller.recoveryCandidate)
        await context.controller.backend.configureForTesting()
    }

    private func start(
        _ transition: TransitionCase,
        context: LifecycleRaceContext
    ) -> Task<DocumentTransitionResult, Never> {
        Task { @MainActor in
            switch transition {
            case .new: return await context.controller.requestNewDocument()
            case .open:
                var incoming = ProjectCreation.blank()
                incoming.pages[0].name = "Incoming winner"
                _ = try? await ProjectPackageStore().write(ProjectPackage(document: incoming), to: context.incoming)
                return await context.controller.requestOpen(context.incoming)
            case .revert: return await context.controller.requestRevert()
            case .restore: return await context.controller.requestRestoreRecovery()
            case .close: return await context.controller.requestCloseTransition()
            }
        }
    }

    private func resolveDiscardIfPresented(_ controller: DocumentLifecycleController) async {
        await waitUntil { controller.pendingUnsavedChangesPrompt != nil }
        if let prompt = controller.pendingUnsavedChangesPrompt {
            controller.resolveUnsavedChanges(.discard, promptID: prompt.id)
        }
    }

    private func waitForEpochChange(
        _ controller: DocumentLifecycleController,
        from epoch: LifecycleEpoch
    ) async {
        await waitUntil { controller.currentLifecycleEpoch != epoch }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        while !condition() { await Task.yield() }
    }

    private func assertAdoptedState(
        for transition: TransitionCase,
        context: LifecycleRaceContext,
        prior: DocumentLifecycleStateSnapshot,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let state = context.controller.stateSnapshot
        switch transition {
        case .new:
            XCTAssertEqual(state.phase, .clean, file: file, line: line)
            XCTAssertNil(state.fileURL, file: file, line: line)
            XCTAssertNotEqual(state.projectID, prior.projectID, file: file, line: line)
            XCTAssertEqual(state.document.pages.map(\.name), ["Home", "Not Found"], file: file, line: line)
        case .open:
            XCTAssertEqual(state.phase, .clean, file: file, line: line)
            XCTAssertEqual(state.fileURL, context.incoming, file: file, line: line)
            XCTAssertEqual(state.document.pages[0].name, "Incoming winner", file: file, line: line)
        case .revert:
            XCTAssertEqual(state.phase, .clean, file: file, line: line)
            XCTAssertEqual(state.fileURL, context.durable, file: file, line: line)
            XCTAssertEqual(state.document.pages.map(\.name), ["Home", "Not Found"], file: file, line: line)
        case .restore:
            XCTAssertEqual(state.phase, .recovered, file: file, line: line)
            XCTAssertEqual(state.fileURL, context.durable, file: file, line: line)
            XCTAssertTrue(state.document.pages.contains { $0.name == "Recovery winner" }, file: file, line: line)
            XCTAssertNil(state.recoveryCandidate, file: file, line: line)
        case .close:
            XCTAssertEqual(state.document, prior.document, file: file, line: line)
            XCTAssertEqual(state.history, prior.history, file: file, line: line)
            XCTAssertEqual(state.projectID, prior.projectID, file: file, line: line)
            XCTAssertEqual(state.fileURL, prior.fileURL, file: file, line: line)
            XCTAssertEqual(state.durableFingerprint, prior.durableFingerprint, file: file, line: line)
            XCTAssertEqual(state.recoveryCandidate, prior.recoveryCandidate, file: file, line: line)
            XCTAssertEqual(state.phase, .modified, file: file, line: line)
        }
    }

    private func assertState(
        _ actual: DocumentLifecycleStateSnapshot,
        equals expected: DocumentLifecycleStateSnapshot,
        includingEpoch: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.document, expected.document, file: file, line: line)
        XCTAssertEqual(actual.history, expected.history, file: file, line: line)
        XCTAssertEqual(actual.projectID, expected.projectID, file: file, line: line)
        XCTAssertEqual(actual.fileURL, expected.fileURL, file: file, line: line)
        XCTAssertEqual(actual.durableFingerprint, expected.durableFingerprint, file: file, line: line)
        XCTAssertEqual(actual.phase, expected.phase, file: file, line: line)
        XCTAssertEqual(actual.displayName, expected.displayName, file: file, line: line)
        XCTAssertEqual(actual.failure, expected.failure, file: file, line: line)
        XCTAssertEqual(actual.recoveryCandidate, expected.recoveryCandidate, file: file, line: line)
        if includingEpoch { XCTAssertEqual(actual.lifecycleEpoch, expected.lifecycleEpoch, file: file, line: line) }
    }

    private func addPage(_ name: String, to controller: DocumentLifecycleController) throws {
        try controller.session.execute(.insertPage(InsertPageCommand(
            page: DocumentPage(name: name),
            index: controller.session.document.pages.count
        )))
    }

    private func fixture(_ name: String, isDirectory: Bool = false) -> URL {
        let uniqueName = "\(UUID().uuidString)-\(name)"
        let url = fixtureLease.url.appendingPathComponent(uniqueName, isDirectory: isDirectory)
        if isDirectory { try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return url
    }
}

private enum TransitionCase: String, CaseIterable {
    case new
    case open
    case revert
    case restore
    case close
}

private struct LifecycleRaceContext {
    let controller: DocumentLifecycleController
    let durable: URL
    let incoming: URL
    let recoveryDirectory: URL
    let projectID: ProjectID
    let durableBytes: Data
}

private struct CompletedLifecycleWrite: Equatable, Sendable {
    let intent: LifecycleOperationIntent
    let revision: UInt64
}

private actor RecoveryRetirementCommitBarrier: ProjectPackageIOObserving {
    private var hasReached = false
    private var released = false
    private var reachWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func reached(_ checkpoint: ProjectPackageIOCheckpoint) async {
        guard checkpoint == .recoveryDeletionReadyToCommit, !hasReached else { return }
        hasReached = true
        let waiters = reachWaiters
        reachWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            if released {
                continuation.resume()
            } else {
                releaseContinuation = continuation
            }
        }
    }

    func waitUntilReached() async {
        if hasReached { return }
        await withCheckedContinuation { reachWaiters.append($0) }
    }

    func release() {
        released = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

final class ManualLifecycleAutosaveDebouncer: LifecycleAutosaveDebouncing, @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var cancelled: Set<UUID> = []

    func wait() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(continuation, id: id)
            }
        } onCancel: {
            self.cancel(id)
        }
    }

    func waitUntilPending() async {
        while pendingCount == 0 { await Task.yield() }
    }

    func fireAll() {
        lock.lock()
        let current = waiters.values
        waiters.removeAll()
        lock.unlock()
        current.forEach { $0.resume() }
    }

    private var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiters.count
    }

    private func register(_ continuation: CheckedContinuation<Void, Error>, id: UUID) {
        lock.lock()
        if cancelled.remove(id) != nil || Task.isCancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
        } else {
            waiters[id] = continuation
            lock.unlock()
        }
    }

    private func cancel(_ id: UUID) {
        lock.lock()
        if let continuation = waiters.removeValue(forKey: id) {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
        } else {
            cancelled.insert(id)
            lock.unlock()
        }
    }
}

private actor LifecycleBackendProbe: LifecycleBackendObserving {
    private struct BarrierRule {
        let checkpoint: LifecycleBackendCheckpoint
        let intent: LifecycleOperationIntent
    }

    private struct Event: Sendable {
        let checkpoint: LifecycleBackendCheckpoint
        let operation: LifecycleOperationIdentity
    }

    private var events: [Event] = []
    private var barrier: BarrierRule?
    private var blocked = false
    private var blockWaiters: [CheckedContinuation<Void, Never>] = []
    private var eventWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var barrierCancellationRequested = false

    func reached(_ checkpoint: LifecycleBackendCheckpoint, operation: LifecycleOperationIdentity) async {
        events.append(Event(checkpoint: checkpoint, operation: operation))
        let pendingEventWaiters = eventWaiters
        eventWaiters.removeAll()
        pendingEventWaiters.forEach { $0.resume() }
        guard let barrier,
              barrier.checkpoint == checkpoint,
              barrier.intent == operation.intent,
              !blocked else { return }
        blocked = true
        let pendingBlockWaiters = blockWaiters
        blockWaiters.removeAll()
        pendingBlockWaiters.forEach { $0.resume() }
        // A backend operation can be cancelled while a deterministic test
        // barrier holds it. Treat that as an observation boundary, not as an
        // uninterruptible filesystem operation: the production backend checks
        // cancellation immediately after this callback. Resuming here lets
        // the test prove that explicit Save drains a running autosave instead
        // of deadlocking behind its own instrumentation.
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                if barrierCancellationRequested || Task.isCancelled {
                    barrierCancellationRequested = false
                    continuation.resume()
                } else {
                    releaseContinuation = continuation
                }
            }
        }, onCancel: {
            Task { await self.releaseForCancellation() }
        })
    }

    func block(_ checkpoint: LifecycleBackendCheckpoint, intent: LifecycleOperationIntent) {
        barrier = BarrierRule(checkpoint: checkpoint, intent: intent)
        blocked = false
        barrierCancellationRequested = false
        releaseContinuation = nil
    }

    func waitUntilBlocked() async {
        if blocked { return }
        await withCheckedContinuation { blockWaiters.append($0) }
    }

    func release() {
        barrier = nil
        barrierCancellationRequested = false
        resumeBarrier()
    }

    private func releaseForCancellation() {
        barrierCancellationRequested = true
        resumeBarrier()
    }

    func reset() {
        events.removeAll()
        barrier = nil
        blocked = false
        barrierCancellationRequested = false
        resumeBarrier()
    }

    func operations(at checkpoint: LifecycleBackendCheckpoint) -> [LifecycleOperationIdentity] {
        events.filter { $0.checkpoint == checkpoint }.map(\.operation)
    }

    func writeCount(_ intent: LifecycleOperationIntent) -> Int {
        events.filter { $0.checkpoint == .afterFilesystemWrite && $0.operation.intent == intent }.count
    }

    func completedWriteOrder() -> [CompletedLifecycleWrite] {
        events.filter { $0.checkpoint == .afterFilesystemWrite }
            .map { CompletedLifecycleWrite(intent: $0.operation.intent, revision: $0.operation.revision) }
    }

    func waitForEvent(
        _ checkpoint: LifecycleBackendCheckpoint,
        intent: LifecycleOperationIntent,
        count: Int
    ) async {
        while events.filter({ $0.checkpoint == checkpoint && $0.operation.intent == intent }).count < count {
            await withCheckedContinuation { eventWaiters.append($0) }
        }
    }

    private func resumeBarrier() {
        let continuation = releaseContinuation
        releaseContinuation = nil
        continuation?.resume()
    }
}
