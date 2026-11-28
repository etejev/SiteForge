import Combine
import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class DocumentLifecycleTests: XCTestCase {
    nonisolated(unsafe) private var fixtureLease: ApplicationOwnedTestFixture!

    nonisolated override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureLease = try ApplicationOwnedTestFixture.create("lifecycle")
    }

    nonisolated override func tearDownWithError() throws {
        try fixtureLease.cleanup()
        try super.tearDownWithError()
    }

    func testNewDocumentHasCleanUntitledStateAndCommands() async {
        let controller = makeController()
        let result = await controller.requestNewDocument()
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(controller.phase, .clean)
        XCTAssertEqual(controller.displayName, "Untitled")
        XCTAssertTrue(controller.canSave)
        XCTAssertFalse(controller.canRevert)
        XCTAssertEqual(DocumentLifecycleController.requirementIDs, expectedRequirementIDs)
    }

    // SF-0306-003/004/005: normal exits and live sibling processes are not crashes.
    func testRecoverySessionEvidenceSeparatesLiveCrashCleanAndLegacyWithoutChangingContent() async throws {
        let directory = fixture("session-evidence", isDirectory: true)
        try await ProjectPackageStore().prepareRecoveryDirectory(directory)
        let source = ProjectPackage(document: ProjectCreation.blank())
        var running: RecoverySessionEvidence? = RecoverySessionEvidence()
        let tagged = try XCTUnwrap(running).tagging(source, in: directory)
        let reader = RecoverySessionEvidence()
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(source, in: directory))
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(tagged, in: directory), "A live window/process owns this work")
        XCTAssertEqual(tagged.document, source.document)
        XCTAssertEqual(tagged.projectID, source.projectID)
        XCTAssertEqual(RecoverySessionEvidence.removingEvidence(from: tagged), source)
        running = nil // OS releases the process lock; no clean-exit marker was written.
        XCTAssertTrue(reader.qualifiesForAutomaticRecovery(tagged, in: directory))
        let foreign = ProjectPackage(document: tagged.document, optionalMembers: tagged.optionalMembers)
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(foreign, in: directory), "Copied evidence cannot qualify a different project")
        var clean: RecoverySessionEvidence? = RecoverySessionEvidence()
        let cleanPackage = try XCTUnwrap(clean).tagging(source, in: directory)
        clean?.markCleanShutdown()
        clean = nil
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(cleanPackage, in: directory))
        XCTAssertTrue(reader.qualifiesForAutomaticRecovery(tagged, in: directory), "Another session's clean exit cannot consume a crashed session")
        let unrelated = fixture("other-session", isDirectory: true)
        try await ProjectPackageStore().prepareRecoveryDirectory(unrelated)
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(tagged, in: unrelated))
    }

    func testRecoverySessionEvidenceRejectsUnsafeMalformedAndMissingMarkers() async throws {
        let directory = fixture("unsafe-session", isDirectory: true)
        try await ProjectPackageStore().prepareRecoveryDirectory(directory)
        let source = ProjectPackage(document: ProjectCreation.blank())
        var writer: RecoverySessionEvidence? = RecoverySessionEvidence()
        let tagged = try XCTUnwrap(writer).tagging(source, in: directory)
        writer = nil
        let reader = RecoverySessionEvidence()
        let marker = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix(".session-") })
        let original = try Data(contentsOf: marker)
        XCTAssertTrue(reader.qualifiesForAutomaticRecovery(tagged, in: directory))
        try Data("not a session".utf8).write(to: marker)
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(tagged, in: directory))
        try original.write(to: marker)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: marker.path)
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(tagged, in: directory))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        let hardlink = directory.appendingPathComponent("marker-hardlink")
        try FileManager.default.linkItem(at: marker, to: hardlink)
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(tagged, in: directory))
        try FileManager.default.removeItem(at: hardlink)
        let moved = directory.appendingPathComponent("retained-marker")
        try FileManager.default.moveItem(at: marker, to: moved)
        try FileManager.default.createSymbolicLink(at: marker, withDestinationURL: moved)
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(tagged, in: directory))
        try FileManager.default.removeItem(at: marker)
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(tagged, in: directory))
        let malformed = ProjectPackage(document: source.document, optionalMembers: [
            .init(path: RecoverySessionEvidence.memberPath, data: Data("SFR1:../../outside".utf8)),
        ])
        XCTAssertFalse(reader.qualifiesForAutomaticRecovery(malformed, in: directory))
    }

    func testCrashQualifiedDiscoveryPreservesLegacyAndDurableSaveExcludesSessionEvidence() async throws {
        let directory = fixture("qualified-discovery", isDirectory: true)
        let store = ProjectPackageStore()
        try await store.prepareRecoveryDirectory(directory)
        let session = DocumentSession()
        try session.execute(.insertPage(.init(page: DocumentPage(name: "Crash work"), index: 2)))
        let source = ProjectPackage(document: session.document)
        var writer: RecoverySessionEvidence? = RecoverySessionEvidence()
        let tagged = try XCTUnwrap(writer).tagging(source, in: directory)
        let url = DocumentLifecycleBackend.recoveryURL(for: tagged.projectID, in: directory)
        try await store.write(tagged, to: url, policy: .recovery(tagged.projectID))
        let bytes = try Data(contentsOf: url)
        let reader = makeController(recoveryDirectory: directory)
        await reader.discoverUntitledRecoveryCandidate(automaticCrashOnly: true)
        XCTAssertNil(reader.recoveryCandidate)
        writer = nil
        await reader.discoverUntitledRecoveryCandidate(automaticCrashOnly: true)
        XCTAssertEqual(reader.recoveryCandidate?.package.projectID, source.projectID)
        XCTAssertEqual(try Data(contentsOf: url), bytes, "Discovery is read-only")
        let restored = await reader.requestRestoreRecovery()
        XCTAssertEqual(restored, .completed)
        let destination = fixture("Crash-restored.siteforge")
        let saved = await reader.save(to: destination)
        XCTAssertTrue(saved)
        let reopened = try await store.read(from: destination)
        XCTAssertEqual(reopened.document, session.document)
        XCTAssertFalse(reopened.optionalMembers.contains { $0.path == RecoverySessionEvidence.memberPath })

        let legacy = ProjectPackage(document: session.document)
        let legacyURL = DocumentLifecycleBackend.recoveryURL(for: legacy.projectID, in: directory)
        try await store.write(legacy, to: legacyURL, policy: .recovery(legacy.projectID))
        let legacyBytes = try Data(contentsOf: legacyURL)
        let manual = makeController(recoveryDirectory: directory)
        await manual.discoverUntitledRecoveryCandidate(automaticCrashOnly: true)
        XCTAssertNil(manual.recoveryCandidate)
        await manual.discoverUntitledRecoveryCandidate()
        XCTAssertEqual(manual.recoveryCandidate?.package.projectID, legacy.projectID)
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBytes)
    }

    func testSaveOpenAndSaveAsValidateBeforeReplacingState() async throws {
        let first = fixture("Lifecycle.siteforge")
        let second = fixture("Copy.siteforge")
        let controller = makeController()
        try addPage("Landing", to: controller)
        let firstSaved = await controller.save(to: first)
        XCTAssertTrue(firstSaved)
        XCTAssertEqual(controller.phase, .clean)
        let secondSaved = await controller.save(to: second)
        XCTAssertTrue(secondSaved)

        let newResult = await controller.requestNewDocument()
        XCTAssertEqual(newResult, .completed)
        let openResult = await controller.requestOpen(first)
        XCTAssertEqual(openResult, .completed)
        XCTAssertEqual(controller.session.document.pages.map(\.name), ["Home", "Not Found", "Landing"])
        XCTAssertEqual(controller.displayName, "Lifecycle")
        XCTAssertEqual(controller.phase, .clean)
    }

    func testCancelledOpenIsStateNeutralAndMalformedOpenPreservesDocument() async throws {
        let controller = makeController()
        try addPage("Committed", to: controller)
        let before = controller.session.document
        controller.noteCancellation()
        XCTAssertEqual(controller.session.document, before)

        let malformed = fixture("Malformed.siteforge")
        try Data("bad".utf8).write(to: malformed)
        let result = await transition(controller, decision: .discard) {
            await controller.requestOpen(malformed)
        }
        XCTAssertEqual(result, .failed(.malformedPackage))
        XCTAssertEqual(controller.session.document, before)
        XCTAssertEqual(controller.phase, .failed)
        XCTAssertEqual(controller.failure, .malformedPackage)
    }

    func testExternalModificationConflictsAndPreservesMemoryAndDisk() async throws {
        let url = fixture("Conflict.siteforge")
        let controller = makeController()
        let initialSaved = await controller.save(to: url)
        XCTAssertTrue(initialSaved)
        try addPage("Unsaved", to: controller)
        let memory = controller.session.document
        try Data("external".utf8).write(to: url)
        let disk = try Data(contentsOf: url)
        let saved = await controller.save()
        XCTAssertFalse(saved)
        XCTAssertEqual(controller.session.document, memory)
        XCTAssertEqual(try Data(contentsOf: url), disk)
        XCTAssertEqual(controller.phase, .conflicted)
    }

    func testPermissionAndIOFailuresPreserveCommittedState() async throws {
        for fault in [LifecycleBackendFault.permission, .staleScope, .io] {
            let backend = DocumentLifecycleBackend()
            await backend.configureForTesting(fault: fault)
            let controller = makeController(backend: backend)
            try addPage("Safe", to: controller)
            let before = controller.session.document
            let saved = await controller.save(to: fixture("Failure-\(UUID()).siteforge"))
            XCTAssertFalse(saved)
            XCTAssertEqual(controller.session.document, before)
            XCTAssertEqual(controller.phase, .failed)
        }
    }

    func testAutosaveCoalescesAndCreatesNewerValidRecoveryCandidate() async throws {
        let url = fixture("Recovery.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let controller = makeController(autosaveDebouncer: debouncer)
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)
        try addPage("One", to: controller)
        try addPage("Two", to: controller)
        await flushAutosave(controller, with: debouncer)
        let recoveryURL = recoveryURL(for: controller)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))

        let reopened = makeController()
        let openResult = await reopened.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        XCTAssertNotNil(reopened.recoveryCandidate)
        XCTAssertEqual(reopened.recoveryCandidate?.package.document.pages.count, 4)
        let restoreResult = await reopened.requestRestoreRecovery()
        XCTAssertEqual(restoreResult, .completed)
        XCTAssertEqual(reopened.phase, .recovered)
        XCTAssertEqual(reopened.session.document.pages.count, 4)
        XCTAssertTrue(reopened.isModified)
    }

    func testDefaultPageAndRootIdentifiersSurviveAutosaveRecovery() async throws {
        let url = fixture("DefaultIdentityRecovery.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        let pageIDs = writer.session.document.pages.map(\.id)
        let rootIDs = writer.session.document.pages.flatMap(\.rootNodeIDs)
        let saved = await writer.save(to: url)
        XCTAssertTrue(saved)
        try writer.session.execute(.renamePage(RenamePageCommand(
            pageID: writer.session.document.pages[0].id,
            name: "Recovered Home"
        )))
        await flushAutosave(writer, with: debouncer)

        let reader = makeController()
        let openResult = await reader.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        let restoreResult = await reader.requestRestoreRecovery()
        XCTAssertEqual(restoreResult, .completed)
        XCTAssertEqual(reader.session.document.pages.map(\.id), pageIDs)
        XCTAssertEqual(reader.session.document.pages.flatMap(\.rootNodeIDs), rootIDs)
        XCTAssertEqual(reader.session.document.pages[0].name, "Recovered Home")
    }

    func testDiscardAndMalformedRecoveryAreIntentional() async throws {
        let url = fixture("Discard.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        let saved = await writer.save(to: url)
        XCTAssertTrue(saved)
        try addPage("Recovered", to: writer)
        await flushAutosave(writer, with: debouncer)

        let reader = makeController()
        let firstOpen = await reader.requestOpen(url)
        XCTAssertEqual(firstOpen, .completed)
        XCTAssertNotNil(reader.recoveryCandidate)
        await reader.discardRecovery()
        XCTAssertNil(reader.recoveryCandidate)

        try Data("bad recovery".utf8).write(to: recoveryURL(for: reader))
        XCTAssertEqual(Darwin.chmod(recoveryURL(for: reader).path, mode_t(0o600)), 0)
        let secondOpen = await reader.requestOpen(url)
        XCTAssertEqual(secondOpen, .completed)
        XCTAssertNil(reader.recoveryCandidate)
        XCTAssertEqual(reader.failure, .malformedRecovery)
    }

    func testRevertAndUnsavedCloseHandling() async throws {
        let url = fixture("Revert.siteforge")
        let controller = makeController()
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)
        try addPage("Draft", to: controller)
        let closeTask = Task { await controller.requestCloseTransition() }
        await waitForPrompt(controller, transition: .closeWindow)
        let closePrompt = try XCTUnwrap(controller.pendingUnsavedChangesPrompt)
        controller.resolveUnsavedChanges(.cancel, promptID: closePrompt.id)
        let closeResult = await closeTask.value
        XCTAssertEqual(closeResult, .cancelled)
        let result = await transition(controller, decision: .discard) {
            await controller.requestRevert()
        }
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(controller.session.document.pages.count, 2)
        XCTAssertEqual(controller.phase, .clean)
        let finalClose = await controller.requestCloseTransition()
        XCTAssertEqual(finalClose, .completed)
    }

    func testStaleSaveSuppressionAndMainActorResponsiveness() async throws {
        let probe = LifecycleBackendProbe()
        let backend = DocumentLifecycleBackend(observer: probe)
        let controller = makeController(
            backend: backend, autosaveDebouncer: ManualLifecycleAutosaveDebouncer()
        )
        let url = fixture("Stale.siteforge")
        try addPage("First", to: controller)
        let firstRevision = controller.session.document.revision
        // Task creation/yield is not a save-entry ordering guarantee. Hold
        // the real first snapshot at the existing filesystem checkpoint.
        await probe.block(.beforeFilesystemWrite, intent: .saveAs)
        let first = Task { await controller.save(to: url) }
        await probe.waitUntilBlocked()
        XCTAssertEqual(controller.phase, .saving)
        let mainActorRan = await Task { @MainActor in true }.value
        try addPage("Second", to: controller)
        let secondRevision = controller.session.document.revision
        let second = Task { await controller.save(to: url) }
        await probe.release()
        let firstSaved = await first.value
        let secondSaved = await second.value
        XCTAssertTrue(firstSaved)
        XCTAssertTrue(secondSaved)
        XCTAssertTrue(mainActorRan)
        let loaded = try await ProjectPackageStore().read(from: url)
        XCTAssertEqual(loaded.document.pages.map(\.name), ["Home", "Not Found", "First", "Second"])
        let writes = await probe.completedWriteOrder()
        XCTAssertEqual(writes.map(\.revision), [firstRevision, secondRevision])
        XCTAssertEqual(loaded.document.revision, secondRevision)
        XCTAssertEqual(controller.phase, .clean)
    }

    func testDiagnosticsRedactPathsAndContent() async throws {
        let backend = DocumentLifecycleBackend()
        let controller = makeController(backend: backend)
        let secret = "private-client-name"
        let url = fixture("\(secret).siteforge")
        try addPage(secret, to: controller)
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)
        let description = String(describing: await backend.diagnosticRecords())
        XCTAssertFalse(description.contains(secret))
        XCTAssertFalse(description.contains(url.deletingLastPathComponent().path))
    }

    func testDiagnosticsCoverRevertRestoreAndDiscardRecoveryWithRedactedIdentity() async throws {
        let backend = DocumentLifecycleBackend()
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let durable = fixture("DiagnosticRecovery.siteforge")
        let writer = makeController(backend: backend, autosaveDebouncer: debouncer)
        let initialSave = await writer.save(to: durable)
        XCTAssertTrue(initialSave)
        try addPage("Diagnostic Draft", to: writer)
        await flushAutosave(writer, with: debouncer)

        let restorer = makeController(backend: backend)
        let restoreOpen = await restorer.requestOpen(durable)
        XCTAssertEqual(restoreOpen, .completed)
        XCTAssertNotNil(restorer.recoveryCandidate)
        let restored = await restorer.requestRestoreRecovery()
        XCTAssertEqual(restored, .completed)

        let discarder = makeController(backend: backend)
        let discardOpen = await discarder.requestOpen(durable)
        XCTAssertEqual(discardOpen, .completed)
        XCTAssertNotNil(discarder.recoveryCandidate)
        await discarder.discardRecovery()

        let revertResult = await transition(writer, decision: .discard) {
            await writer.requestRevert()
        }
        XCTAssertEqual(revertResult, .completed)

        let records = await backend.diagnosticRecords()
        let successful = Set(records.filter { $0.result == .success }.map(\.operation))
        XCTAssertTrue(successful.isSuperset(of: [.revert, .restore, .discardRecovery]))
        let description = String(describing: records)
        XCTAssertFalse(description.contains(durable.path))
        XCTAssertFalse(description.contains("Diagnostic Draft"))
    }

    func testCancelPreservesExactStateForNewOpenRevertAndClose() async throws {
        let durable = fixture("TransitionGuard.siteforge")
        let incoming = fixture("IncomingGuard.siteforge")
        try await ProjectPackageStore().write(
            ProjectPackage(document: ProjectCreation.blank()),
            to: incoming
        )
        let controller = makeController()
        let initialSave = await controller.save(to: durable)
        XCTAssertTrue(initialSave)
        try addPage("Protected Draft", to: controller)
        let expected = controller.stateSnapshot

        let operations: [(DestructiveDocumentTransition, @MainActor () async -> DocumentTransitionResult)] = [
            (.newDocument, { await controller.requestNewDocument() }),
            (.openProject, { await controller.requestOpen(incoming) }),
            (.revertToSaved, { await controller.requestRevert() }),
            (.closeWindow, { await controller.requestCloseTransition() }),
        ]
        for (expectedTransition, operation) in operations {
            let task = Task { await operation() }
            await waitForPrompt(controller, transition: expectedTransition)
            let prompt = try XCTUnwrap(controller.pendingUnsavedChangesPrompt)
            XCTAssertFalse(prompt.message.contains(durable.deletingLastPathComponent().path))
            controller.resolveUnsavedChanges(.cancel, promptID: prompt.id)
            let result = await task.value
            XCTAssertEqual(result, .cancelled)
            XCTAssertEqual(controller.stateSnapshot, expected)
        }
    }

    func testSaveDiscardAndSavePanelCancellationBranchesAreDeterministic() async throws {
        let durable = fixture("SaveBranch.siteforge")
        let incoming = fixture("DiscardBranch.siteforge")
        var incomingDocument = ProjectCreation.blank()
        incomingDocument.pages[0].name = "Incoming Home"
        try await ProjectPackageStore().write(ProjectPackage(document: incomingDocument), to: incoming)

        let savedController = makeController()
        let initialSave = await savedController.save(to: durable)
        XCTAssertTrue(initialSave)
        try addPage("Saved Before New", to: savedController)
        let newResult = await transition(savedController, decision: .save) {
            await savedController.requestNewDocument()
        }
        XCTAssertEqual(newResult, .completed)
        XCTAssertEqual(savedController.phase, .clean)
        let durablePackage = try await ProjectPackageStore().read(from: durable)
        XCTAssertTrue(durablePackage.document.pages.contains { $0.name == "Saved Before New" })

        try addPage("Discarded Draft", to: savedController)
        let openResult = await transition(savedController, decision: .discard) {
            await savedController.requestOpen(incoming)
        }
        XCTAssertEqual(openResult, .completed)
        XCTAssertEqual(savedController.session.document, incomingDocument)

        let cancelledController = makeController(saveDestinationProvider: { _ in nil })
        try addPage("Untitled Draft", to: cancelledController)
        let beforeCancellation = cancelledController.stateSnapshot
        let cancelled = await transition(cancelledController, decision: .save) {
            await cancelledController.requestNewDocument()
        }
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertEqual(cancelledController.stateSnapshot, beforeCancellation)
    }

    func testFailedTransitionSaveRestoresExactStateAndReportsFailureSeparately() async throws {
        let backend = DocumentLifecycleBackend()
        await backend.configureForTesting(fault: .io)
        let destination = fixture("FailedTransitionSave.siteforge")
        let controller = makeController(
            backend: backend,
            saveDestinationProvider: { _ in destination }
        )
        try addPage("Protected Untitled", to: controller)
        let expected = controller.stateSnapshot

        let result = await transition(controller, decision: .save) {
            await controller.requestNewDocument()
        }

        XCTAssertEqual(result, .failed(.ioFailure))
        XCTAssertEqual(controller.stateSnapshot, expected)
        XCTAssertEqual(controller.transitionFailure, .ioFailure)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testUntitledRecoverySurvivesRelaunchAndCleansUpAfterRestoreSaveAndDiscard() async throws {
        let recoveryDirectory = fixture("untitled-recovery", isDirectory: true)
        let writerDebouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: writerDebouncer
        )
        try addPage("Unsaved Untitled", to: writer)
        await flushAutosave(writer, with: writerDebouncer)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(
            for: writer.currentProjectID,
            in: recoveryDirectory
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))

        let relaunched = makeController(recoveryDirectory: recoveryDirectory)
        await relaunched.discoverUntitledRecoveryCandidate()
        XCTAssertEqual(relaunched.recoveryCandidate?.package.projectID, writer.currentProjectID)
        let restored = await relaunched.requestRestoreRecovery()
        XCTAssertEqual(restored, .completed)
        XCTAssertNil(relaunched.fileURL)
        XCTAssertTrue(relaunched.session.document.pages.contains { $0.name == "Unsaved Untitled" })

        let durable = fixture("RecoveredUntitled.siteforge")
        let durableSave = await relaunched.save(to: durable)
        XCTAssertTrue(durableSave)
        let retiredAfterSave = try await ProjectPackageStore().isRetiredRecoveryTombstone(
            at: recoveryURL,
            projectID: writer.currentProjectID
        )
        XCTAssertTrue(retiredAfterSave)

        let discardDebouncer = ManualLifecycleAutosaveDebouncer()
        let discardWriter = makeController(
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: discardDebouncer
        )
        try addPage("Discard Me", to: discardWriter)
        await flushAutosave(discardWriter, with: discardDebouncer)
        let discardURL = DocumentLifecycleBackend.recoveryURL(
            for: discardWriter.currentProjectID,
            in: recoveryDirectory
        )
        let discardReader = makeController(recoveryDirectory: recoveryDirectory)
        await discardReader.discoverUntitledRecoveryCandidate()
        XCTAssertNotNil(discardReader.recoveryCandidate)
        await discardReader.discardRecovery()
        let retiredAfterDiscard = try await ProjectPackageStore().isRetiredRecoveryTombstone(
            at: discardURL,
            projectID: discardWriter.currentProjectID
        )
        XCTAssertTrue(retiredAfterDiscard)
    }

    // SF-0306-003, SF-0306-004, SF-1504-004 — untitled recovery discovery
    // treats the canonical public filename as the expected project-identity
    // binding. A syntactically valid package is not an authority to recover
    // under another project's name, and noncanonical names remain untouched.
    func testUntitledRecoveryDiscoveryRequiresCanonicalFilenameAndMatchingProjectIdentity() async throws {
        let expectedProjectID = ProjectID()
        let recoveredProjectID = ProjectID()
        let recoveredDocumentSession = DocumentSession(document: ProjectCreation.blank())
        try recoveredDocumentSession.execute(.insertPage(InsertPageCommand(
            page: DocumentPage(name: "Recovered Untitled"),
            index: recoveredDocumentSession.document.pages.count
        )))
        let recoveryPackage = ProjectPackage(
            projectID: recoveredProjectID,
            createdAt: ProjectTimestamp("2026-08-09T12:00:00.000Z"),
            modifiedAt: ProjectTimestamp("2026-08-09T12:01:00.000Z"),
            document: recoveredDocumentSession.document
        )
        let store = ProjectPackageStore()

        let mismatchedDirectory = fixture("untitled-recovery-mismatched", isDirectory: true)
        try await store.prepareRecoveryDirectory(mismatchedDirectory)
        let mismatchedURL = DocumentLifecycleBackend.recoveryURL(
            for: expectedProjectID,
            in: mismatchedDirectory
        )
        try await store.write(
            recoveryPackage,
            to: mismatchedURL,
            policy: .recovery(recoveredProjectID)
        )
        let mismatchedBytes = try Data(contentsOf: mismatchedURL)

        let mismatchedReader = makeController(recoveryDirectory: mismatchedDirectory)
        await mismatchedReader.discoverUntitledRecoveryCandidate()
        XCTAssertNil(mismatchedReader.recoveryCandidate)
        await mismatchedReader.discardRecovery()
        XCTAssertEqual(try Data(contentsOf: mismatchedURL), mismatchedBytes)
        let mismatchedRetired = try await store.isRetiredRecoveryTombstone(
            at: mismatchedURL,
            projectID: expectedProjectID
        )
        XCTAssertFalse(mismatchedRetired)

        let noncanonicalDirectory = fixture("untitled-recovery-noncanonical", isDirectory: true)
        try await store.prepareRecoveryDirectory(noncanonicalDirectory)
        let noncanonicalURL = noncanonicalDirectory.appendingPathComponent(
            "\(recoveredProjectID.description.uppercased()).siteforge-recovery"
        )
        try await store.write(
            recoveryPackage,
            to: noncanonicalURL,
            policy: .recovery(recoveredProjectID)
        )
        let noncanonicalBytes = try Data(contentsOf: noncanonicalURL)

        let noncanonicalReader = makeController(recoveryDirectory: noncanonicalDirectory)
        await noncanonicalReader.discoverUntitledRecoveryCandidate()
        XCTAssertNil(noncanonicalReader.recoveryCandidate)
        await noncanonicalReader.discardRecovery()
        XCTAssertEqual(try Data(contentsOf: noncanonicalURL), noncanonicalBytes)

        let matchingDirectory = fixture("untitled-recovery-matching", isDirectory: true)
        try await store.prepareRecoveryDirectory(matchingDirectory)
        let matchingURL = DocumentLifecycleBackend.recoveryURL(
            for: recoveredProjectID,
            in: matchingDirectory
        )
        try await store.write(
            recoveryPackage,
            to: matchingURL,
            policy: .recovery(recoveredProjectID)
        )

        let matchingReader = makeController(recoveryDirectory: matchingDirectory)
        await matchingReader.discoverUntitledRecoveryCandidate()
        XCTAssertEqual(matchingReader.recoveryCandidate?.package.projectID, recoveredProjectID)
        await matchingReader.discardRecovery()
        XCTAssertNil(matchingReader.recoveryCandidate)
        let matchingRetired = try await store.isRetiredRecoveryTombstone(
            at: matchingURL,
            projectID: recoveredProjectID
        )
        XCTAssertTrue(matchingRetired)
    }

    // SF-0306-003, SF-0306-004, SF-1504-004 — a presented foreign untitled
    // candidate and the scene's current document own distinct recovery
    // proofs. Restoring B may retire C only after the user discards C, while
    // B itself stays available until it is promoted into the current scene.
    func testUntitledCandidateRestoreDoesNotConflateCurrentRecoveryOwnership() async throws {
        let recoveryDirectory = fixture("untitled-candidate-restore", isDirectory: true)
        let candidateDebouncer = ManualLifecycleAutosaveDebouncer()
        let candidateWriter = makeController(
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: candidateDebouncer
        )
        try addPage("Candidate B", to: candidateWriter)
        await flushAutosave(candidateWriter, with: candidateDebouncer)
        let candidateID = candidateWriter.currentProjectID
        let candidateURL = DocumentLifecycleBackend.recoveryURL(for: candidateID, in: recoveryDirectory)
        let candidateBytes = try Data(contentsOf: candidateURL)

        let currentDebouncer = ManualLifecycleAutosaveDebouncer()
        let reader = makeController(
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: currentDebouncer
        )
        await reader.discoverUntitledRecoveryCandidate()
        XCTAssertEqual(reader.recoveryCandidate?.package.projectID, candidateID)

        try addPage("Current C", to: reader)
        await flushAutosave(reader, with: currentDebouncer)
        let currentID = reader.currentProjectID
        let currentURL = DocumentLifecycleBackend.recoveryURL(for: currentID, in: recoveryDirectory)
        let currentBytes = try Data(contentsOf: currentURL)
        XCTAssertTrue(reader.isModified)

        let restored = await transition(reader, decision: .discard) {
            await reader.requestRestoreRecovery()
        }
        XCTAssertEqual(restored, .completed)
        XCTAssertEqual(reader.currentProjectID, candidateID)
        XCTAssertTrue(reader.session.document.pages.contains { $0.name == "Candidate B" })
        XCTAssertFalse(reader.session.document.pages.contains { $0.name == "Current C" })
        XCTAssertEqual(try Data(contentsOf: candidateURL), candidateBytes)
        let currentRetired = try await ProjectPackageStore().isRetiredRecoveryTombstone(
            at: currentURL,
            projectID: currentID
        )
        XCTAssertTrue(currentRetired)
        XCTAssertNotEqual(try Data(contentsOf: currentURL), currentBytes)
    }

    // SF-0306-003, SF-0306-004, SF-1504-004 — discarding a foreign candidate
    // cannot make the current document appear clean or retire its independent
    // recovery artifact.
    func testDiscardForeignUntitledCandidatePreservesCurrentModifiedRecovery() async throws {
        let recoveryDirectory = fixture("untitled-candidate-discard", isDirectory: true)
        let candidateDebouncer = ManualLifecycleAutosaveDebouncer()
        let candidateWriter = makeController(
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: candidateDebouncer
        )
        try addPage("Candidate B", to: candidateWriter)
        await flushAutosave(candidateWriter, with: candidateDebouncer)
        let candidateID = candidateWriter.currentProjectID
        let candidateURL = DocumentLifecycleBackend.recoveryURL(for: candidateID, in: recoveryDirectory)

        let currentDebouncer = ManualLifecycleAutosaveDebouncer()
        let reader = makeController(
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: currentDebouncer
        )
        await reader.discoverUntitledRecoveryCandidate()
        XCTAssertEqual(reader.recoveryCandidate?.package.projectID, candidateID)
        try addPage("Current C", to: reader)
        await flushAutosave(reader, with: currentDebouncer)
        let currentID = reader.currentProjectID
        let currentURL = DocumentLifecycleBackend.recoveryURL(for: currentID, in: recoveryDirectory)
        let currentBytes = try Data(contentsOf: currentURL)
        let currentDocument = reader.session.document

        await reader.discardRecovery()

        XCTAssertNil(reader.recoveryCandidate)
        XCTAssertTrue(reader.isModified)
        XCTAssertEqual(reader.phase, .modified)
        XCTAssertEqual(reader.session.document, currentDocument)
        XCTAssertEqual(try Data(contentsOf: currentURL), currentBytes)
        let candidateRetired = try await ProjectPackageStore().isRetiredRecoveryTombstone(
            at: candidateURL,
            projectID: candidateID
        )
        XCTAssertTrue(candidateRetired)
    }

    // SF-0306-003, SF-0306-004 — discarding a current-project candidate
    // clears its old expectation. The next autosave can replace the exact
    // project-bound tombstone instead of reporting a false identity conflict.
    func testDiscardCurrentRecoveryAllowsNextAutosaveFromRetiredMarker() async throws {
        let recoveryDirectory = fixture("current-candidate-discard", isDirectory: true)
        let durableURL = fixture("current-candidate-discard.siteforge")
        let writerDebouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: writerDebouncer
        )
        let initialSave = await writer.save(to: durableURL)
        XCTAssertTrue(initialSave)
        try addPage("Initial recovery", to: writer)
        await flushAutosave(writer, with: writerDebouncer)

        let readerDebouncer = ManualLifecycleAutosaveDebouncer()
        let reader = makeController(
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: readerDebouncer
        )
        let opened = await reader.requestOpen(durableURL)
        XCTAssertEqual(opened, .completed)
        XCTAssertNotNil(reader.recoveryCandidate)
        await reader.discardRecovery()
        XCTAssertNil(reader.recoveryCandidate)
        XCTAssertNil(reader.failure)

        try addPage("Recovery after discard", to: reader)
        await flushAutosave(reader, with: readerDebouncer)
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(
            for: reader.currentProjectID,
            in: recoveryDirectory
        )
        let written = try await ProjectPackageStore().readOwnedRecoverySnapshot(
            from: recoveryURL,
            expectedProjectID: reader.currentProjectID
        )
        XCTAssertTrue(written.package.document.pages.contains { $0.name == "Recovery after discard" })
        XCTAssertNil(reader.failure)
    }

    func testRestoreRecoveryCancellationPreservesCurrentEditAndHistory() async throws {
        let durable = fixture("RestoreGuard.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        let initialSave = await writer.save(to: durable)
        XCTAssertTrue(initialSave)
        try addPage("Recovery Version", to: writer)
        await flushAutosave(writer, with: debouncer)

        let reader = makeController()
        let openResult = await reader.requestOpen(durable)
        XCTAssertEqual(openResult, .completed)
        XCTAssertNotNil(reader.recoveryCandidate)
        try addPage("Current Unsaved Version", to: reader)
        let expected = reader.stateSnapshot
        let result = await transition(reader, decision: .cancel) {
            await reader.requestRestoreRecovery()
        }
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(reader.stateSnapshot, expected)
    }

    /// OD-032 fixture: the blank project plus `extraPages` standard pages,
    /// each with `framesPerPage` 24 × 24 frames under its root (about 680
    /// bytes of canonical JSON per frame).
    private func framedDocument(pages extraPages: Int, framesPerPage: Int) throws -> CanonicalDocument {
        var document = ProjectCreation.blank()
        for pageIndex in 0..<max(1, extraPages) {
            var page = extraPages == 0 ? document.pages[0]
                : DocumentPage(name: "Framed Page \(pageIndex + 1)", route: PageRoute(rawValue: "/framed-\(pageIndex + 1)"))
            let rootID = try XCTUnwrap(page.rootNodeIDs.first)
            let rootIndex = try XCTUnwrap(page.nodes.firstIndex { $0.id == rootID })
            for index in 0..<framesPerPage {
                let frame = DocumentNode(kind: .frame, name: "Frame \(index + 1)", parent: .node(rootID), properties:
                    [("layout.x", Double(index % 40 * 30)), ("layout.y", Double(index / 40 * 30)), ("layout.width", 24), ("layout.height", 24)]
                        .map { NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1)) })
                page.nodes[rootIndex].childIDs.append(frame.id)
                page.nodes.append(frame)
            }
            if extraPages == 0 { document.pages[0] = page } else { document.pages.append(page) }
        }
        try document.validate()
        return document
    }

    // SF-0301-004/007, SF-0306-004, OD-032: a page is never split across
    // package members, so one page above the 4 MiB member limit (ADR-0001/
    // ADR-0012, a security boundary) makes the save refused before anything
    // is written, with a specific failure instead of the generic validation
    // message; the last saved file stays byte-for-byte intact. Autosave
    // reports the same failure, so the user knows crash recovery is not
    // protecting the latest edits either.
    func testProjectTooLargeSaveAndAutosaveAreRefusedTruthfullyWithoutWriting() async throws {
        let url = fixture("TooLarge.siteforge")
        let small = makeController()
        let firstSave = await small.save(to: url)
        XCTAssertTrue(firstSave)
        let lastSaved = try Data(contentsOf: url)

        let oversizedDocument = try framedDocument(pages: 0, framesPerPage: 9_000)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        XCTAssertGreaterThan(try encoder.encode(oversizedDocument.pages[0]).count, ProjectFileCapacity.pageLimitBytes,
                             "Precondition: one page exceeds the per-page limit")
        XCTAssertLessThan(try DocumentSerializer.encode(oversizedDocument).count, ProjectFileCapacity.fileLimitBytes,
                          "Precondition: the whole document would fit the file limit")
        let oversized = makeController(document: oversizedDocument)
        let saved = await oversized.save(to: url)
        XCTAssertFalse(saved)
        XCTAssertEqual(oversized.failure, .projectTooLarge)
        XCTAssertEqual(oversized.phase, .failed)
        XCTAssertEqual(oversized.statusText, DocumentLifecycleFailure.projectTooLarge.localizedDescription)
        XCTAssertEqual(oversized.capacity, .exceededLimit)
        XCTAssertNil(oversized.fileURL, "A refused save never adopts the destination")
        XCTAssertEqual(try Data(contentsOf: url), lastSaved, "The last saved project is unchanged")
        XCTAssertEqual(oversized.session.document, oversizedDocument, "The in-memory project is kept for the user to reduce")
        let message = DocumentLifecycleFailure.projectTooLarge.localizedDescription
        XCTAssertTrue(message.contains("8 MB"))
        XCTAssertTrue(message.contains("each page up to 4 MB"))
        XCTAssertTrue(message.contains("Nothing was written"))
        XCTAssertFalse(message.contains("could not be validated"))
        XCTAssertEqual(DocumentLifecycleFailure.projectTooLarge.diagnosticCategory, "project-too-large")
        XCTAssertNotEqual(DocumentLifecycleFailure.projectTooLarge, .malformedPackage)

        let debouncer = ManualLifecycleAutosaveDebouncer()
        let autosaving = makeController(document: oversizedDocument, autosaveDebouncer: debouncer)
        let pageID = try XCTUnwrap(oversizedDocument.pages.first?.id)
        try autosaving.session.execute(.renamePage(.init(pageID: pageID, name: "Renamed Large Page")))
        await flushAutosave(autosaving, with: debouncer)
        XCTAssertEqual(autosaving.failure, .projectTooLarge)
        XCTAssertEqual(autosaving.phase, .failed)
        XCTAssertEqual(autosaving.capacity, .exceededLimit)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL(for: autosaving).path),
                       "No partial recovery artifact is written")
    }

    // SF-0301-007, SF-0206-007, OD-032: every successful save and autosave
    // measures the file it wrote against the 8 MiB file limit and, near the
    // member limit, the largest page against the 4 MiB page limit; the
    // workspace warns from 85% of the closer limit.
    func testProjectFileCapacityIsMeasuredOnSaveAndAutosaveAndWarnsNearTheLimit() async throws {
        let limit = ProjectFileCapacity.fileLimitBytes
        XCTAssertEqual(limit, ProjectPackageStore.maximumPackageBytes)
        XCTAssertEqual(ProjectFileCapacity.pageLimitBytes, ProjectPackageStore.maximumMemberBytes - 2)
        XCTAssertEqual(ProjectFileCapacity.warningFraction, 0.85)
        let warning = Int((Double(limit) * ProjectFileCapacity.warningFraction).rounded(.up))
        XCTAssertEqual(ProjectFileCapacity(fileBytes: 1_000).level, .normal)
        XCTAssertNil(ProjectFileCapacity(fileBytes: 1_000).statusText, "No status-bar noise while there is room")
        XCTAssertEqual(ProjectFileCapacity(fileBytes: warning - 1).level, .normal)
        XCTAssertEqual(ProjectFileCapacity(fileBytes: warning).level, .nearLimit)
        XCTAssertEqual(ProjectFileCapacity(fileBytes: limit).level, .nearLimit, "Exactly at the limit still saves")
        XCTAssertEqual(ProjectFileCapacity(fileBytes: limit + 1).level, .exceeded)
        XCTAssertEqual(ProjectFileCapacity(fileBytes: limit / 2).percentUsed, 50)
        let ninety = ProjectFileCapacity(fileBytes: limit * 9 / 10 + 1_000)
        XCTAssertEqual(ninety.statusText, "Project file 90% full")
        XCTAssertTrue(ninety.detail.contains("8 MB project-file limit"))
        XCTAssertTrue(ninety.detail.contains("Remove pages or content"))
        let page = ProjectFileCapacity.pageLimitBytes
        let pageLimited = ProjectFileCapacity(fileBytes: page, largestPageBytes: page * 9 / 10 + 1_000)
        XCTAssertTrue(pageLimited.isPageLimited)
        XCTAssertEqual(pageLimited.level, .nearLimit, "A large page warns even when the file has room")
        XCTAssertEqual(pageLimited.statusText, "Largest page 90% full")
        XCTAssertTrue(pageLimited.detail.contains("4 MB page limit"))
        XCTAssertEqual(ProjectFileCapacity(fileBytes: 1_000, largestPageBytes: page + 1).level, .exceeded)
        XCTAssertNil(ProjectFileCapacity.exceededLimit.fileBytes)
        XCTAssertEqual(ProjectFileCapacity.exceededLimit.statusText, "Project too large to save")
        XCTAssertEqual(ProjectFileCapacity.exceededLimit.detail, DocumentLifecycleFailure.projectTooLarge.localizedDescription)

        let url = fixture("Capacity.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let controller = makeController(autosaveDebouncer: debouncer)
        XCTAssertNil(controller.capacity, "Unknown until the project is first written")
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)
        XCTAssertEqual(controller.capacity?.fileBytes, try Data(contentsOf: url).count, "The file that was written is measured")
        XCTAssertNil(controller.capacity?.largestPageBytes, "A small project measures no page")
        XCTAssertEqual(controller.capacity?.level, .normal)
        try addPage("Measured", to: controller)
        await flushAutosave(controller, with: debouncer)
        XCTAssertEqual(controller.capacity?.fileBytes, try Data(contentsOf: recoveryURL(for: controller)).count,
                       "Autosave measures the recovery snapshot it wrote")
        let newResult = await transition(controller, decision: .discard) { await controller.requestNewDocument() }
        XCTAssertEqual(newResult, .completed)
        XCTAssertNil(controller.capacity, "A different project starts unmeasured")

        // The spec's large fixture (10,000 single-root pages) is measured,
        // and its level follows the same rule as any other project.
        let largeURL = fixture("Large.siteforge")
        let large = makeController(document: WorkspaceFixtureScale.large.document())
        let largeSaved = await large.save(to: largeURL)
        XCTAssertTrue(largeSaved)
        let largeBytes = try XCTUnwrap(large.capacity?.fileBytes)
        XCTAssertEqual(largeBytes, try Data(contentsOf: largeURL).count)
        XCTAssertEqual(large.capacity, ProjectFileCapacity(fileBytes: largeBytes, largestPageBytes: large.capacity?.largestPageBytes))
        XCTAssertLessThanOrEqual(largeBytes, limit)
    }

    // SF-0301-001/004/007, SF-1702-004/008, OD-032: a project above the 4 MiB
    // member limit saves as package v2 (its pages in bounded members) and
    // reopens identical; the stress fixture (the full 20,000-object budget),
    // which package v1 could not hold, is saved and reopened too when it fits
    // the 8 MiB file limit.
    func testProjectAboveOneMemberSavesAsPackageVersionTwoAndReopensIdentically() async throws {
        let url = fixture("Split.siteforge")
        let document = try framedDocument(pages: 2, framesPerPage: 4_000)
        XCTAssertGreaterThan(try DocumentSerializer.encode(document).count, ProjectPackageStore.maximumMemberBytes,
                             "Precondition: more than one member of pages")
        let controller = makeController(document: document)
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)
        XCTAssertEqual(controller.capacity?.fileBytes, try Data(contentsOf: url).count)
        XCTAssertNotNil(controller.capacity?.largestPageBytes, "Package v2 always measures its largest page")
        let reopened = makeController()
        let openResult = await reopened.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        XCTAssertEqual(reopened.session.document.pages, document.pages)
        let package = try await ProjectPackageStore().read(from: url)
        XCTAssertEqual(package.compatibility.minimumPackageReaderVersion, 2, "Older builds refuse it instead of misreading it")

        let stress = WorkspaceFixtureScale.stress.document()
        let stressURL = fixture("Stress.siteforge")
        let stressController = makeController(document: stress)
        let stressSaved = await stressController.save(to: stressURL)
        let fits = (try? await ProjectPackageStore().encode(ProjectPackage(document: stress))) != nil
        if fits {
            XCTAssertTrue(stressSaved, "The stress fixture fits the file limit")
            let stressReopened = try await ProjectPackageStore().read(from: stressURL)
            XCTAssertEqual(stressReopened.document.pages.count, WorkspaceFixtureScale.stress.pageCount)
        } else {
            XCTAssertFalse(stressSaved)
            XCTAssertEqual(stressController.failure, .projectTooLarge)
        }
    }

    // SF-0301-007, SF-0206-007, OD-032 (ADR-0140): opening a project measures
    // the file it read, so the status bar can warn before the first save. A
    // small file measures no page; a file above one package member also
    // measures its largest page, as the save that wrote it did; a new
    // project starts unmeasured again.
    func testProjectFileCapacityIsMeasuredWhenAProjectIsOpened() async throws {
        let url = fixture("OpenedCapacity.siteforge")
        let writer = makeController()
        let written = await writer.save(to: url)
        XCTAssertTrue(written)
        let reader = makeController()
        XCTAssertNil(reader.capacity)
        let opened = await reader.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.capacity, ProjectFileCapacity(fileBytes: try Data(contentsOf: url).count),
                       "The opened file is measured before any save")
        XCTAssertNil(reader.capacity?.largestPageBytes, "A small file measures no page")
        XCTAssertEqual(reader.capacity?.level, .normal)
        XCTAssertNil(reader.capacity?.statusText)

        let splitURL = fixture("OpenedSplit.siteforge")
        let splitWriter = makeController(document: try framedDocument(pages: 2, framesPerPage: 4_000))
        let splitWritten = await splitWriter.save(to: splitURL)
        XCTAssertTrue(splitWritten)
        let splitReader = makeController()
        let splitOpened = await splitReader.requestOpen(splitURL)
        XCTAssertEqual(splitOpened, .completed)
        let largestPage = try XCTUnwrap(ProjectPackageStore.largestEncodedPageSize(in: splitReader.session.document))
        XCTAssertEqual(splitReader.capacity, ProjectFileCapacity(fileBytes: try Data(contentsOf: splitURL).count,
                                                                 largestPageBytes: largestPage))
        XCTAssertEqual(splitReader.capacity?.largestPageBytes, splitWriter.capacity?.largestPageBytes,
                       "Opening measures the largest page as the save that wrote the file did")
        XCTAssertNil(ProjectFileCapacity.opened(fileBytes: 1_000, document: splitReader.session.document).largestPageBytes,
                     "Pages are measured only for a file near one package member or larger")

        let newResult = await splitReader.requestNewDocument()
        XCTAssertEqual(newResult, .completed)
        XCTAssertNil(splitReader.capacity, "A different project starts unmeasured")
    }

    // SF-1301-002, SF-1301-003, SF-1301-004 (OD-043, ADR-0038)
    func testSnapshotRestoreCommandIsOneNewUndoableTransaction() throws {
        let session = DocumentSession()
        let original = session.document
        try session.execute(.insertPage(InsertPageCommand(page: DocumentPage(name: "Pricing"), index: original.pages.count)))
        let pricing = try XCTUnwrap(session.document.pages.last)
        try session.execute(.renamePage(RenamePageCommand(pageID: pricing.id, name: "Plans")))
        let edited = session.document

        let command = try ProjectSnapshots.restoreCommand(to: original, from: edited, resources: nil)
        try session.execute(command)
        XCTAssertEqual(session.document.pages, original.pages)
        XCTAssertEqual(session.document.websiteMetadata, original.websiteMetadata)
        XCTAssertEqual(session.document.revision, edited.revision + 1, "Restore is a new revision, not a rewind")
        try session.undo()
        XCTAssertEqual(session.document.pages, edited.pages, "Undo brings back the head that was current before restore")
        try session.redo()
        XCTAssertEqual(session.document.pages, original.pages)

        XCTAssertThrowsError(try ProjectSnapshots.restoreCommand(to: session.document, from: session.document, resources: nil)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .unchanged)
        }
        XCTAssertThrowsError(try ProjectSnapshots.restoreCommand(to: CanonicalDocument(), from: session.document, resources: nil)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .documentMismatch)
        }
    }

    // SF-1301-001, SF-1301-004, SF-1301-005, SF-1301-008 (OD-043, ADR-0038)
    func testNamedSnapshotsSaveReopenRestoreToANewHeadUndoAndRecover() async throws {
        let url = fixture("Snapshots.siteforge")
        let controller = makeController()
        XCTAssertEqual(try controller.projectSnapshots(), [])
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)
        let baseline = controller.session.document
        let entry = try controller.createProjectSnapshot(named: "Before pricing")
        XCTAssertTrue(controller.isModified, "A snapshot is a project change that the next save makes durable")
        XCTAssertEqual(controller.session.document, baseline, "Creating a snapshot does not edit the document")
        try addPage("Pricing", to: controller)
        let savedAgain = await controller.save()
        XCTAssertTrue(savedAgain)
        XCTAssertEqual(controller.phase, .clean)

        let durable = try await ProjectPackageStore().readSnapshot(from: url)
        XCTAssertNil(durable.legacyDocumentData)
        XCTAssertEqual(try ProjectSnapshots.list(in: durable.package, documentID: baseline.id), [entry])
        let reopened = makeController()
        let opened = await reopened.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reopened.fileURL?.path, url.path, "Coordinated reopen retains the canonical system path")
        XCTAssertNil(reopened.historyNotice, "The adopted package and restored history share the same document identity")
        XCTAssertEqual(try reopened.projectSnapshots(), [entry])
        let head = reopened.session.document
        XCTAssertEqual(head.pages.map(\.name), ["Home", "Not Found", "Pricing"])

        try reopened.restoreProjectSnapshot(entry.id, keepingCurrentAs: "Before restore")
        XCTAssertEqual(reopened.session.document.pages, baseline.pages)
        XCTAssertEqual(reopened.session.document.revision, head.revision + 1)
        XCTAssertEqual(try reopened.projectSnapshots().map(\.name), ["Before pricing", "Before restore"],
                       "Restore never deletes the current head")
        XCTAssertTrue(reopened.isModified)
        try reopened.session.undo()
        XCTAssertEqual(reopened.session.document.pages, head.pages)
        try reopened.session.redo()
        XCTAssertEqual(reopened.session.document.pages, baseline.pages)
        let restoredSaved = await reopened.save()
        XCTAssertTrue(restoredSaved)

        let third = makeController()
        let thirdOpened = await third.requestOpen(url)
        XCTAssertEqual(thirdOpened, .completed)
        XCTAssertNil(third.historyNotice, "The restore transaction is valid persisted history")
        XCTAssertTrue(third.session.canUndo)
        XCTAssertEqual(third.session.document.pages, baseline.pages)
        let kept = try XCTUnwrap(try third.projectSnapshots().last)
        XCTAssertEqual(kept.name, "Before restore")
        try third.restoreProjectSnapshot(kept.id)
        XCTAssertEqual(third.session.document.pages.map(\.name), head.pages.map(\.name))

        let before = third.session.document
        let list = try third.projectSnapshots()
        XCTAssertThrowsError(try third.restoreProjectSnapshot(kept.id)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .unchanged)
        }
        XCTAssertThrowsError(try third.restoreProjectSnapshot(ProjectSnapshotID())) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .notFound)
        }
        XCTAssertThrowsError(try third.createProjectSnapshot(named: "before PRICING")) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .duplicateName)
        }
        XCTAssertThrowsError(try third.restoreProjectSnapshot(entry.id, keepingCurrentAs: "Before restore")) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .duplicateName)
        }
        XCTAssertEqual(third.session.document, before, "Failures leave the committed document unchanged")
        XCTAssertEqual(try third.projectSnapshots(), list)

        try third.renameProjectSnapshot(entry.id, to: "Launch")
        try third.deleteProjectSnapshot(kept.id)
        XCTAssertEqual(try third.projectSnapshots().map(\.name), ["Launch"])
        try third.deleteAllProjectSnapshots()
        XCTAssertEqual(try third.projectSnapshots(), [])
        XCTAssertThrowsError(try third.deleteAllProjectSnapshots()) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .notFound)
        }

        let records = third.snapshotDiagnosticRecords
        XCTAssertTrue(records.contains { $0.operation == .restore && $0.result == .success })
        XCTAssertTrue(records.contains { $0.operation == .restore && $0.failureCategory == "unchanged" })
        XCTAssertTrue(records.contains { $0.operation == .deleteAll && $0.result == .success })
        XCTAssertTrue(records.allSatisfy { $0.requirementID == "SF-1301-008" })
        XCTAssertFalse(records.contains { ($0.sanitizedSnapshotID ?? "").contains(entry.id.description) },
                       "Raw snapshot identifiers never enter diagnostics")
    }

    // SF-1306-002, SF-1306-004, SF-1306-005, SF-1306-008 (OD-043, ADR-0040)
    func testCompareVersionsRunsOffTheMainActorIgnoresStaleRunsAndNeverEditsTheDocument() async throws {
        let controller = makeController()
        let quiet = AccessibilityAnnouncementPoster { _ in }
        let first = ProjectComparisonModel(lifecycle: controller, announcer: quiet)
        XCTAssertTrue(first.snapshots.isEmpty)
        XCTAssertNil(first.baselineID)
        first.compare()
        XCTAssertEqual(first.phase, .failed(ProjectComparisonError.sameSource.localizedDescription))
        XCTAssertFalse(first.createSnapshot(named: "   "))
        XCTAssertTrue(first.createSnapshot(named: "Before pricing"))
        let entry = try XCTUnwrap(first.snapshots.first)
        XCTAssertEqual(first.baselineID, entry.id)
        XCTAssertNil(first.targetID, "The empty state compares the new snapshot with the current document")
        try addPage("Pricing", to: controller)
        let edited = controller.session.document

        let model = ProjectComparisonModel(lifecycle: controller, announcer: quiet)
        XCTAssertEqual(model.baselineID, entry.id, "The newest snapshot is the default baseline")
        model.compare()
        XCTAssertEqual(model.phase, .comparing)
        model.cancel()
        XCTAssertEqual(model.phase, .idle)
        model.compare()
        model.compare() // The first of these two runs is superseded; its result is ignored.
        await awaitProjectComparison(model)
        let comparison = try XCTUnwrap(model.readyComparison, "Expected a comparison, got \(model.phase)")
        XCTAssertEqual(comparison.baselineName, "Before pricing")
        XCTAssertEqual(comparison.targetName, ProjectComparisonSource.currentDocumentName)
        XCTAssertEqual(comparison.changes.count, 1)
        XCTAssertEqual(comparison.filtered(area: .pages, kind: .added).first?.after?.hasPrefix("Pricing"), true)
        XCTAssertEqual(controller.session.document, edited, "Comparing never edits the document")
        XCTAssertFalse(model.isStale(headRevision: controller.session.document.revision))
        try addPage("Team", to: controller)
        XCTAssertTrue(model.isStale(headRevision: controller.session.document.revision),
                      "A result read from the current document is labeled once the document changes")

        try controller.deleteProjectSnapshot(entry.id)
        model.compare()
        await awaitProjectComparison(model)
        XCTAssertEqual(model.phase, .failed(ProjectSnapshotError.notFound.localizedDescription))
        model.reloadSnapshots()
        XCTAssertNil(model.baselineID, "A deleted snapshot is no longer offered")

        let records = model.diagnosticRecords + first.diagnosticRecords
        XCTAssertTrue(records.allSatisfy { $0.requirementID == "SF-1306-008" })
        XCTAssertTrue(records.contains { $0.result == .success && $0.changeCount == 1 })
        XCTAssertEqual(records.filter { $0.failureCategory == "cancelled" }.count, 2)
        XCTAssertTrue(records.contains { $0.failureCategory == "not-found" })
        XCTAssertTrue(records.contains { $0.failureCategory == "same-source" })
    }

    // SF-0906-002, SF-0906-004, SF-0906-005, SF-0906-008 (OD-046, ADR-0041)
    func testComponentLibraryImportIsOneUndoableStepAndCopiesStayReadOnlyUntilDetached() async throws {
        let publisher = makeController()
        let definitionID = PageID(), rootID = NodeID()
        let root = DocumentNode(id: rootID, kind: .frame, name: "Card", parent: .page(definitionID), properties:
            [("layout.x", 0.0), ("layout.y", 0.0), ("layout.width", 320.0), ("layout.height", 200.0)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1))
            })
        try publisher.session.execute(.insertPage(InsertPageCommand(
            page: DocumentPage(id: definitionID, name: "Card", route: .init(rawValue: ""), role: .componentDefinition,
                               provenance: .authored, rootNodeIDs: [rootID], nodes: [root]),
            index: publisher.session.document.pages.count)))
        struct WriteFailure: Error {}
        XCTAssertThrowsError(try publisher.exportComponentLibrary(named: "Kit", version: .initial) { _ in throw WriteFailure() }) {
            XCTAssertEqual($0 as? ComponentLibraryError, .writeFailed)
        }
        XCTAssertNil(try publisher.componentLibraryIndex(), "A failed write records nothing")
        var written = Data()
        let file = try publisher.exportComponentLibrary(named: "Kit", version: .initial) { written = $0 }
        XCTAssertEqual(file.libraryVersion, .initial)
        XCTAssertEqual(try publisher.componentLibraryIndex()?.published?.libraryID, file.libraryID)
        XCTAssertThrowsError(try publisher.importComponentLibrary(written)) {
            XCTAssertEqual($0 as? ComponentLibraryError, .ownLibrary)
        }

        let url = fixture("Library.siteforge")
        let controller = makeController()
        let original = controller.session.document
        let record = try controller.importComponentLibrary(written)
        XCTAssertTrue(controller.isModified)
        XCTAssertEqual(controller.session.document.componentDefinitions.map(\.id), [definitionID])
        let rename = DocumentCommand.renamePage(RenamePageCommand(pageID: definitionID, name: "Mine"))
        let imported = controller.session.document
        XCTAssertThrowsError(try controller.session.execute(rename)) {
            XCTAssertEqual($0 as? CommandExecutionError, .disabled(ComponentLibraryError.readOnly("Kit").localizedDescription))
        }
        XCTAssertEqual(controller.session.document, imported, "A refused edit leaves the document unchanged")
        try addPage("Pricing", to: controller)
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)

        let reopened = makeController()
        let opened = await reopened.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        XCTAssertEqual(try reopened.componentLibraryRows().map(\.status), [.current(.initial)])
        XCTAssertThrowsError(try reopened.session.execute(rename), "The read-only rule survives save and reopen")
        try reopened.detachComponentLibrary(record.libraryID)
        try reopened.session.execute(rename)
        XCTAssertEqual(reopened.session.document.componentDefinitions.first?.name, "Mine", "Detached copies are editable")
        XCTAssertEqual(try reopened.componentLibraryRows(), [])

        try controller.session.undo()
        try controller.session.undo()
        XCTAssertEqual(controller.session.document.pages, original.pages, "Undo removes the import in one step")
        XCTAssertEqual(try controller.componentLibraryRows().map(\.status), [.missing])
        try controller.session.redo()
        XCTAssertEqual(try controller.componentLibraryRows().map(\.status), [.current(.initial)])
        XCTAssertThrowsError(try controller.updateComponentLibrary(written)) {
            XCTAssertEqual($0 as? ComponentLibraryError, .unchanged)
        }

        let records = publisher.libraryDiagnosticRecords + controller.libraryDiagnosticRecords + reopened.libraryDiagnosticRecords
        XCTAssertTrue(records.allSatisfy { $0.requirementID == "SF-0906-008" })
        XCTAssertTrue(records.contains { $0.operation == .export && $0.failureCategory == "write-failed" })
        XCTAssertTrue(records.contains { $0.operation == .import && $0.result == .success })
        XCTAssertTrue(records.contains { $0.operation == .detach && $0.result == .success })
        XCTAssertFalse(records.contains { ($0.sanitizedLibraryID ?? "").contains(record.libraryID.description) },
                       "Raw library identifiers never enter diagnostics")
    }

    private func awaitProjectComparison(_ model: ProjectComparisonModel) async {
        for _ in 0..<5_000 where model.phase == .comparing {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    // SF-1301-001, SF-1301-002, SF-1301-004, SF-1301-005, SF-1301-006 (OD-043, ADR-0039): Snapshots sheet state
    func testSnapshotsSheetCreatesRenamesRestoresKeepingCurrentHandsOffCompareAndRecoversDamagedStorage() async throws {
        let controller = makeController()
        var announcements: [String] = []
        let poster = AccessibilityAnnouncementPoster { announcements.append($0) }
        let state = WorkspaceShellState(documentSession: controller.session, lifecycle: controller, announcementPoster: poster)
        state.presentSnapshots()
        XCTAssertTrue(state.isSnapshotsPresented)
        XCTAssertEqual(state.snapshotEntries, [])
        XCTAssertNil(state.snapshotStorageFailure)
        XCTAssertTrue(state.canCreateSnapshot)
        XCTAssertEqual(state.suggestedSnapshotName(), "Snapshot 1")
        XCTAssertEqual(state.snapshotNameIssue("   "), ProjectSnapshotError.invalidName.localizedDescription)

        let baseline = controller.session.document
        XCTAssertTrue(state.createSnapshot(named: "  Launch  "))
        let launch = try XCTUnwrap(state.snapshotEntries.first)
        XCTAssertEqual(launch.name, "Launch")
        XCTAssertEqual(controller.session.document, baseline, "Creating a snapshot never edits the document")
        XCTAssertTrue(controller.isModified, "The next save makes the snapshot durable")
        XCTAssertEqual(state.suggestedSnapshotName(), "Snapshot 2")
        XCTAssertEqual(state.snapshotNameIssue("LAUNCH"), ProjectSnapshotError.duplicateName.localizedDescription)
        XCTAssertNil(state.snapshotNameIssue("launch", renaming: launch.id), "A snapshot may change the case of its own name")
        XCTAssertFalse(state.createSnapshot(named: "launch"))
        XCTAssertEqual(state.snapshotsStatus, ProjectSnapshotError.duplicateName.localizedDescription)
        XCTAssertEqual(state.snapshotEntries, [launch], "A refused create changes nothing")
        XCTAssertTrue(state.renameSnapshot(launch.id, to: "Approved"))
        XCTAssertEqual(state.snapshotEntries.map(\.name), ["Approved"])
        XCTAssertEqual(state.snapshotEntries.first?.id, launch.id, "Rename keeps identity")

        try addPage("Pricing", to: controller)
        let head = controller.session.document
        let keepName = state.suggestedSnapshotName(base: "Before restoring Approved")
        XCTAssertEqual(keepName, "Before restoring Approved")
        XCTAssertTrue(state.restoreSnapshot(launch.id, keepingCurrentAs: keepName))
        XCTAssertEqual(controller.session.document.pages, baseline.pages)
        XCTAssertEqual(controller.session.document.revision, head.revision + 1, "Restore is a new head, never a rewind")
        XCTAssertEqual(state.snapshotRows.map(\.name), ["Before restoring Approved", "Approved"],
                       "Newest first; the previous head was kept")
        XCTAssertEqual(state.suggestedSnapshotName(base: "Before restoring Approved"), "Before restoring Approved 2")
        try controller.session.undo()
        XCTAssertEqual(controller.session.document.pages, head.pages)
        try controller.session.redo()
        XCTAssertEqual(controller.session.document.pages, baseline.pages)

        let restored = controller.session.document
        XCTAssertFalse(state.restoreSnapshot(launch.id, keepingCurrentAs: "Kept by mistake"))
        XCTAssertEqual(state.snapshotsStatus, ProjectSnapshotError.unchanged.localizedDescription)
        XCTAssertEqual(state.snapshotEntries.count, 2, "A refused restore does not keep the current version either")
        XCTAssertEqual(controller.session.document, restored)

        state.compareSnapshotWithCurrent(launch.id)
        XCTAssertFalse(state.isSnapshotsPresented)
        XCTAssertNil(state.projectComparisonRequest, "Compare Versions opens only after the Snapshots sheet has gone")
        state.completeSnapshotsDismissal()
        XCTAssertEqual(state.projectComparisonRequest?.baseline, launch.id)
        XCTAssertNil(state.projectComparisonRequest?.target, "The snapshot is compared with the current document")
        state.projectComparisonRequest = nil
        state.presentSnapshots()
        state.isSnapshotsPresented = false
        state.completeSnapshotsDismissal()
        XCTAssertNil(state.projectComparisonRequest, "Done does not open a comparison")
        // SF-1301-003: Review Changes compares the current document with the snapshot before a restore.
        state.presentSnapshots()
        state.previewSnapshotRestore(launch.id)
        XCTAssertFalse(state.isSnapshotsPresented)
        XCTAssertEqual(controller.session.document, restored, "Reviewing a restore changes nothing")
        state.completeSnapshotsDismissal()
        XCTAssertNil(state.projectComparisonRequest?.baseline, "The current document is the baseline")
        XCTAssertEqual(state.projectComparisonRequest?.target, launch.id)
        state.projectComparisonRequest = nil

        let url = fixture("SnapshotsSheet.siteforge")
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)
        let store = ProjectPackageStore()
        let initialRead = try await store.readSnapshot(from: url)
        let stored = initialRead.package
        XCTAssertEqual(try ProjectSnapshots.list(in: stored, documentID: stored.document.id).map(\.name),
                       ["Approved", "Before restoring Approved"])
        let damagedMembers = stored.optionalMembers.map { member in
            member.path == launch.memberPath
                ? ProjectPackageMember(path: member.path, role: member.role, data: member.data + Data(" ".utf8))
                : member
        }
        _ = try await store.write(ProjectPackage(projectID: stored.projectID, createdAt: stored.createdAt,
                                                 modifiedAt: stored.modifiedAt, document: stored.document,
                                                 optionalMembers: damagedMembers, compatibility: stored.compatibility),
                                  to: url, expected: initialRead.file.fingerprint)

        let reopened = makeController()
        let opened = await reopened.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        let damaged = WorkspaceShellState(documentSession: reopened.session, lifecycle: reopened, announcementPoster: poster)
        damaged.presentSnapshots()
        XCTAssertEqual(damaged.snapshotStorageFailure, .corrupt)
        XCTAssertEqual(damaged.snapshotEntries, [])
        XCTAssertFalse(damaged.canCreateSnapshot)
        let document = reopened.session.document
        XCTAssertFalse(damaged.createSnapshot(named: "Fresh"))
        XCTAssertEqual(damaged.snapshotsStatus, ProjectSnapshotError.corrupt.localizedDescription)
        XCTAssertTrue(damaged.deleteAllSnapshots())
        XCTAssertNil(damaged.snapshotStorageFailure)
        XCTAssertEqual(damaged.snapshotEntries, [])
        XCTAssertEqual(reopened.session.document, document, "Delete All never changes the document")
        XCTAssertTrue(damaged.createSnapshot(named: "Fresh"))
        XCTAssertEqual(damaged.snapshotEntries.map(\.name), ["Fresh"])
        XCTAssertFalse(announcements.isEmpty, "Every snapshot action is announced")
        let records = reopened.snapshotDiagnosticRecords
        XCTAssertTrue(records.contains { $0.operation == .deleteAll && $0.result == .success })
        XCTAssertTrue(records.contains { $0.operation == .create && $0.failureCategory == "corrupt" })
    }

    // SF-0307-002, SF-0307-003, SF-0307-005, SF-0307-006 (ADR-0132)
    func testHistoryListJumpsAndUndoRedoFollowTheChangedPage() throws {
        let controller = makeController()
        var announcements: [String] = []
        let poster = AccessibilityAnnouncementPoster { announcements.append($0) }
        let state = WorkspaceShellState(documentSession: controller.session, lifecycle: controller, announcementPoster: poster)
        try addPage("Pricing", to: controller)
        let pricing = try XCTUnwrap(controller.session.document.pages.last?.id)
        let home = try XCTUnwrap(controller.session.document.pages.first?.id)
        try controller.session.execute(.renamePage(RenamePageCommand(pageID: pricing, name: "Plans")))
        state.selectPage(home)
        XCTAssertEqual(state.effectiveSelectedPageID, home)

        state.undo()
        XCTAssertEqual(controller.session.document.pages.last?.name, "Pricing")
        XCTAssertEqual(state.effectiveSelectedPageID, pricing, "Undo shows the page it changed")
        state.selectPage(home)
        state.redo()
        XCTAssertEqual(state.effectiveSelectedPageID, pricing, "Redo shows the page it changed")
        state.selectPage(home)
        try controller.session.execute(.renamePage(RenamePageCommand(pageID: home, name: "Start")))
        state.undo()
        XCTAssertEqual(state.effectiveSelectedPageID, home, "An edit on the shown page keeps that page")

        let items = state.historyItems
        XCTAssertEqual(items.map(\.isApplied), [true, true, false])
        XCTAssertEqual(items.map(\.isCurrent), [false, true, false])
        XCTAssertEqual(items[1].pageIDs, [pricing])
        XCTAssertTrue(items.allSatisfy(\.persistsOnSave))
        XCTAssertTrue(state.jumpToHistory(items[0].id))
        XCTAssertEqual(controller.session.document.pages.last?.name, "Pricing")
        XCTAssertEqual(state.historyItems.map(\.isApplied), [true, false, false])
        XCTAssertEqual(state.effectiveSelectedPageID, pricing, "A jump shows the page of the step it undid")
        XCTAssertTrue(state.jumpToHistory(items[2].id))
        XCTAssertEqual(controller.session.document.pages.first?.name, "Start")
        XCTAssertEqual(controller.session.document.pages.last?.name, "Plans")
        XCTAssertEqual(state.effectiveSelectedPageID, pricing, "A jump that also changed the shown page keeps it")
        XCTAssertTrue(state.jumpToHistory(nil))
        XCTAssertEqual(controller.session.document.pages.count, 2, "The oldest state is before the added page")
        XCTAssertEqual(state.effectiveSelectedPageID, home)
        XCTAssertNil(state.historyJumpFailure)
        XCTAssertFalse(state.jumpToHistory(TransactionID()))
        XCTAssertNotNil(state.historyJumpFailure)
        XCTAssertEqual(controller.session.document.pages.count, 2)
        XCTAssertFalse(announcements.isEmpty, "Jumps are announced")

        // SF-0306-005 (ADR-0131): a page switch ends a coalescing run.
        let notFound = try XCTUnwrap(controller.session.document.pages.last?.id)
        let key = TransactionCoalescingKey(kind: "history-page-switch", identifiers: [home.description])
        let start = Date(timeIntervalSince1970: 2_000)
        for (offset, name) in ["First", "Second"].enumerated() {
            try controller.session.executeCoalescing(.renamePage(RenamePageCommand(pageID: home, name: name)),
                                                     key: key, at: start.addingTimeInterval(Double(offset) * 0.2))
        }
        XCTAssertEqual(state.historyItems.count, 1, "One key inside the window is one step")
        state.selectPage(notFound)
        try controller.session.executeCoalescing(.renamePage(RenamePageCommand(pageID: home, name: "Third")),
                                                 key: key, at: start.addingTimeInterval(0.4))
        XCTAssertEqual(state.historyItems.count, 2, "A page switch starts a new step")
    }

    // SF-0309-002, SF-0309-004, SF-0309-005, SF-0309-008 (ADR-0130)
    func testLegacyOpenKeepsOriginalAsSnapshotBeforeUpgradedSaveAndBackupRestoresUndoably() async throws {
        let golden = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "schema-v1-rootless", withExtension: "siteforge.b64", subdirectory: "Legacy"))
        let packageBytes = try XCTUnwrap(Data(base64Encoded: try Data(contentsOf: golden), options: .ignoreUnknownCharacters))
        let stored = try ProjectPackageStore.storedDocument(in: packageBytes)
        let url = fixture("Upgraded.siteforge")
        try packageBytes.write(to: url, options: .atomic)
        let legacyRead = try await ProjectPackageStore().readSnapshot(from: url)
        XCTAssertEqual(legacyRead.legacyDocumentData, stored.data)

        let controller = makeController()
        let opened = await controller.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        let report = try XCTUnwrap(controller.migrationReport)
        XCTAssertEqual(report, try DocumentMigrations.dryRun(stored.data))
        XCTAssertEqual(report.sourceSchemaVersion, 1)
        XCTAssertEqual(controller.phase, .clean, "Opening and upgrading do not modify the file")
        XCTAssertEqual(try Data(contentsOf: url), packageBytes)
        XCTAssertEqual(controller.migrationNotice?.contains("original kept"), true)
        let backups = try controller.projectSnapshots()
        XCTAssertEqual(backups.count, 1)
        let backup = try XCTUnwrap(backups.first)
        XCTAssertEqual(backup.name, ProjectSnapshots.migrationBackupName(for: 1))
        XCTAssertEqual(backup.documentSchemaVersion, 1)
        XCTAssertEqual(backup.byteCount, stored.data.count)
        XCTAssertEqual(controller.migrationDiagnosticRecords.map(\.operation), [.dryRun, .backup])
        XCTAssertTrue(controller.migrationDiagnosticRecords.allSatisfy {
            $0.requirementID == "SF-0309-008" && $0.failureCategory == nil
        })
        XCTAssertThrowsError(try controller.restoreProjectSnapshot(backup.id)) {
            XCTAssertEqual($0 as? ProjectSnapshotError, .unchanged, "The backup reads back as the upgraded document")
        }

        let pageID = try XCTUnwrap(controller.session.document.pages.first?.id)
        try controller.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "After Upgrade")))
        let saved = await controller.save()
        XCTAssertTrue(saved)
        XCTAssertEqual(try ProjectPackageStore.storedDocument(in: try Data(contentsOf: url)).schemaVersion,
                       DocumentSerializer.currentSchemaVersion)
        let upgradedRead = try await ProjectPackageStore().readSnapshot(from: url)
        XCTAssertNil(upgradedRead.legacyDocumentData)
        XCTAssertEqual(try ProjectSnapshots.list(in: upgradedRead.package, documentID: upgradedRead.package.document.id), [backup])

        let reopened = makeController()
        let reopenedResult = await reopened.requestOpen(url)
        XCTAssertEqual(reopenedResult, .completed)
        XCTAssertEqual(reopened.fileURL?.path, url.path, "Coordinated reopen retains the canonical system path")
        XCTAssertNil(reopened.migrationReport, "A current-schema project needs no upgrade")
        XCTAssertNil(reopened.migrationNotice)
        XCTAssertEqual(reopened.migrationDiagnosticRecords, [])
        let kept = try XCTUnwrap(try reopened.projectSnapshots().first)
        XCTAssertEqual(kept, backup, "The original survives save and reopen unchanged")
        try reopened.restoreProjectSnapshot(kept.id)
        XCTAssertEqual(reopened.session.document.pages.map(\.name), ["Legacy Landing"])
        try reopened.session.undo()
        XCTAssertEqual(reopened.session.document.pages.map(\.name), ["After Upgrade"])
        try reopened.session.redo()
        XCTAssertEqual(reopened.session.document.pages.map(\.name), ["Legacy Landing"])
    }

    // SF-0307-002, SF-0307-006 (ADR-0133): Edit > Show History… and the
    // status-bar History button present the same list.
    func testShowHistoryCommandPresentsTheSharedHistoryList() throws {
        let controller = makeController()
        let state = WorkspaceShellState(documentSession: controller.session, lifecycle: controller)
        XCTAssertFalse(state.isHistoryListPresented)
        state.presentHistoryList()
        XCTAssertTrue(state.isHistoryListPresented, "An empty history still opens and explains itself")
        state.isHistoryListPresented = false
        try addPage("Pricing", to: controller)
        XCTAssertEqual(state.nextUndoDescription, controller.session.registry.descriptor(for: .insertPage).title)
        XCTAssertNil(state.nextRedoDescription)
        state.presentHistoryList()
        XCTAssertTrue(state.isHistoryListPresented)
        XCTAssertEqual(state.historyItems.map(\.isCurrent), [true])
    }

    // SF-0307-006: the history list hangs on the status bar, which Focus Mode
    // hides, so Show History… leaves Focus Mode before presenting the list.
    func testShowHistoryCommandLeavesFocusModeSoTheListIsVisible() {
        let controller = makeController()
        let state = WorkspaceShellState(documentSession: controller.session, lifecycle: controller)
        state.toggleFocusMode()
        XCTAssertTrue(state.isFocusModeEnabled)
        state.presentHistoryList()
        XCTAssertFalse(state.isFocusModeEnabled, "The status-bar History button must be on screen")
        XCTAssertTrue(state.isHistoryListPresented)
        state.isHistoryListPresented = false
        state.presentHistoryList()
        XCTAssertFalse(state.isFocusModeEnabled, "Outside Focus Mode the command leaves the mode alone")
        XCTAssertTrue(state.isHistoryListPresented)
    }

    // Collections…, Languages… and Show History… share the workspace edit
    // boundary: a draft that cannot commit keeps each of them closed.
    func testProjectSheetsWaitForTheWorkspaceEditBoundary() {
        let controller = makeController()
        let state = WorkspaceShellState(documentSession: controller.session, lifecycle: controller)
        XCTAssertTrue(state.canEditCollections)
        XCTAssertTrue(state.canEditLanguages)
        let blocker = state.editCommitRequests.sink { $0.reject() }
        state.presentCollectionsEditor()
        state.presentLanguagesEditor()
        state.presentHistoryList()
        XCTAssertFalse(state.isCollectionsEditorPresented)
        XCTAssertFalse(state.isLanguagesEditorPresented)
        XCTAssertFalse(state.isHistoryListPresented)
        blocker.cancel()
        state.presentCollectionsEditor()
        state.presentLanguagesEditor()
        XCTAssertTrue(state.isCollectionsEditorPresented)
        XCTAssertTrue(state.isLanguagesEditorPresented)
    }

    // SF-0309-002, SF-0309-004, SF-0309-006 (ADR-0133): the upgrade details
    // restore the kept original as one undoable change, and a refused
    // upgrade names its reason and recovery step.
    func testMigrationDetailsRestoreOriginalUndoablyAndRefusedUpgradeShowsItsReason() async throws {
        let golden = try XCTUnwrap(Bundle(for: Self.self).url(
            forResource: "schema-v1-rootless", withExtension: "siteforge.b64", subdirectory: "Legacy"))
        let packageBytes = try XCTUnwrap(Data(base64Encoded: try Data(contentsOf: golden), options: .ignoreUnknownCharacters))
        let url = fixture("UpgradeDetails.siteforge")
        try packageBytes.write(to: url, options: .atomic)

        let controller = makeController()
        let state = WorkspaceShellState(documentSession: controller.session, lifecycle: controller)
        let opened = await controller.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        let backupID = try XCTUnwrap(controller.migrationBackupID)
        XCTAssertEqual(try controller.projectSnapshots().map(\.id), [backupID])
        XCTAssertFalse(controller.isMigrationDetailsPresented)
        controller.isMigrationDetailsPresented = true
        XCTAssertFalse(state.restoreMigrationOriginal(), "Right after opening, the original reads back as the open document")
        XCTAssertEqual(state.snapshotsStatus, ProjectSnapshotError.unchanged.localizedDescription)

        let pageID = try XCTUnwrap(controller.session.document.pages.first?.id)
        try controller.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Edited")))
        let edited = controller.session.document
        XCTAssertTrue(state.restoreMigrationOriginal())
        XCTAssertEqual(controller.session.document.pages.map(\.name), ["Legacy Landing"])
        XCTAssertEqual(controller.session.document.revision, edited.revision + 1, "Restore is one new change")
        try controller.session.undo()
        XCTAssertEqual(controller.session.document.pages, edited.pages)
        try controller.session.redo()
        XCTAssertEqual(controller.session.document.pages.map(\.name), ["Legacy Landing"])

        let refusingBackend = DocumentLifecycleBackend()
        let refusal = DocumentMigrationRefusal.lostContent(pages: 1, nodes: 2)
        await refusingBackend.configureForTesting(fault: .migrationRefusal(refusal))
        let refusing = makeController(backend: refusingBackend)
        let before = refusing.session.document
        let refused = await refusing.requestOpen(url)
        XCTAssertEqual(refused, .failed(.malformedPackage))
        XCTAssertEqual(refusing.session.document, before, "A refused upgrade leaves the open document unchanged")
        XCTAssertEqual(refusing.migrationRefusal, refusal)
        let expected = [refusal.errorDescription, refusal.recoverySuggestion].compactMap { $0 }.joined(separator: " ")
        XCTAssertEqual(refusing.statusText, expected)
        XCTAssertTrue(expected.contains("Nothing was changed or saved"))
        XCTAssertNil(refusing.migrationBackupID)
        await refusingBackend.configureForTesting(fault: .io)
        let failedAgain = await refusing.requestOpen(url)
        XCTAssertEqual(failedAgain, .failed(.ioFailure))
        XCTAssertNil(refusing.migrationRefusal, "A later failure replaces the refusal text")
    }

    private func makeController(
        document: CanonicalDocument? = nil,
        backend: DocumentLifecycleBackend = DocumentLifecycleBackend(),
        recoveryDirectory: URL? = nil,
        saveDestinationProvider: @escaping SaveDestinationProvider = DocumentLifecycleController.nativeSaveDestination,
        autosaveDebouncer: any LifecycleAutosaveDebouncing = ContinuousLifecycleAutosaveDebouncer()
    ) -> DocumentLifecycleController {
        DocumentLifecycleController(
            session: document.map { DocumentSession(document: $0) } ?? DocumentSession(),
            backend: backend,
            recoveryDirectory: recoveryDirectory ?? fixture("recovery", isDirectory: true),
            saveDestinationProvider: saveDestinationProvider,
            autosaveDebouncer: autosaveDebouncer
        )
    }

    private func flushAutosave(
        _ controller: DocumentLifecycleController,
        with debouncer: ManualLifecycleAutosaveDebouncer
    ) async {
        await debouncer.waitUntilPending()
        debouncer.fireAll()
        while controller.hasPendingAutosaveWork { await Task.yield() }
    }

    private func addPage(_ name: String, to controller: DocumentLifecycleController) throws {
        try controller.session.execute(.insertPage(InsertPageCommand(
            page: DocumentPage(name: name), index: controller.session.document.pages.count
        )))
    }

    private func fixture(_ name: String, isDirectory: Bool = false) -> URL {
        let url = fixtureLease.url.appendingPathComponent(name, isDirectory: isDirectory)
        if isDirectory { try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return url
    }

    private func recoveryURL(for controller: DocumentLifecycleController) -> URL {
        DocumentLifecycleBackend.recoveryURL(
            for: controller.currentProjectID,
            in: fixture("recovery", isDirectory: true)
        )
    }

    private func transition(
        _ controller: DocumentLifecycleController,
        decision: UnsavedChangesDecision,
        operation: @escaping @MainActor () async -> DocumentTransitionResult
    ) async -> DocumentTransitionResult {
        let task = Task { await operation() }
        await waitForPrompt(controller)
        guard let prompt = controller.pendingUnsavedChangesPrompt else { return await task.value }
        controller.resolveUnsavedChanges(decision, promptID: prompt.id)
        return await task.value
    }

    private func waitForPrompt(
        _ controller: DocumentLifecycleController,
        transition: DestructiveDocumentTransition? = nil
    ) async {
        for _ in 0..<100 where controller.pendingUnsavedChangesPrompt == nil {
            await Task.yield()
        }
        if let transition { XCTAssertEqual(controller.pendingUnsavedChangesPrompt?.transition, transition) }
        XCTAssertNotNil(controller.pendingUnsavedChangesPrompt)
    }

    private var expectedRequirementIDs: Set<String> {
        ["SF-0203-004", "SF-0203-005", "SF-0203-006",
         "SF-0301-002", "SF-0301-004", "SF-0301-005", "SF-0301-006", "SF-0301-008",
         "SF-0306-001", "SF-0306-002", "SF-0306-003", "SF-0306-004", "SF-0306-005", "SF-0306-006", "SF-0306-008",
         "SF-1504-001", "SF-1504-003", "SF-1504-004", "SF-1504-006", "SF-1504-008",
         "SF-1603-004", "SF-1604-004", "SF-1702-004",
         "SF-1902-004", "SF-1902-005", "SF-1902-006"]
    }
}
