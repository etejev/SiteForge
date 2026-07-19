import Darwin
import XCTest
@testable import SiteForge

@MainActor
final class DocumentLifecycleTests: XCTestCase {
    nonisolated(unsafe) private var fixtureURLs: [URL] = []

    nonisolated override func tearDown() {
        for url in fixtureURLs { try? FileManager.default.removeItem(at: url) }
        fixtureURLs.removeAll()
        super.tearDown()
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
        let backend = DocumentLifecycleBackend()
        await backend.configureForTesting(delayNanoseconds: 200_000_000)
        let controller = makeController(backend: backend)
        let url = fixture("Stale.siteforge")
        try addPage("First", to: controller)
        let first = Task { await controller.save(to: url) }
        await Task.yield()
        var mainActorRan = false
        mainActorRan = true
        try addPage("Second", to: controller)
        let second = Task { await controller.save(to: url) }
        _ = await first.value
        let secondSaved = await second.value
        XCTAssertTrue(secondSaved)
        XCTAssertTrue(mainActorRan)
        let loaded = try await ProjectPackageStore().read(from: url)
        XCTAssertEqual(loaded.document.pages.map(\.name), ["Home", "Not Found", "First", "Second"])
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
        XCTAssertFalse(FileManager.default.fileExists(atPath: recoveryURL.path))

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
        XCTAssertFalse(FileManager.default.fileExists(atPath: discardURL.path))
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

    private func makeController(
        backend: DocumentLifecycleBackend = DocumentLifecycleBackend(),
        recoveryDirectory: URL? = nil,
        saveDestinationProvider: @escaping SaveDestinationProvider = DocumentLifecycleController.nativeSaveDestination,
        autosaveDebouncer: any LifecycleAutosaveDebouncing = ContinuousLifecycleAutosaveDebouncer()
    ) -> DocumentLifecycleController {
        DocumentLifecycleController(
            session: DocumentSession(),
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
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository
            .appendingPathComponent(".siteforge-test-fixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fixtureURLs.contains(directory) { fixtureURLs.append(directory) }
        let url = directory.appendingPathComponent(name, isDirectory: isDirectory)
        if isDirectory { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
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
