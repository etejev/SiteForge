import XCTest
@testable import SiteForge

@MainActor
final class DocumentLifecycleTests: XCTestCase {
    private var fixtureURLs: [URL] = []

    override func tearDown() {
        for url in fixtureURLs { try? FileManager.default.removeItem(at: url) }
        fixtureURLs.removeAll()
        super.tearDown()
    }

    func testNewDocumentHasCleanUntitledStateAndCommands() {
        let controller = makeController()
        controller.newDocument()
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

        controller.newDocument()
        await controller.open(first)
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
        await controller.open(malformed)
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
        let controller = makeController()
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)
        try addPage("One", to: controller)
        try addPage("Two", to: controller)
        try await Task.sleep(for: .milliseconds(600))
        let recoveryURL = DocumentLifecycleBackend.recoveryURL(for: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: recoveryURL.path))

        let reopened = makeController()
        await reopened.open(url)
        XCTAssertNotNil(reopened.recoveryCandidate)
        XCTAssertEqual(reopened.recoveryCandidate?.package.document.pages.count, 4)
        reopened.restoreRecovery()
        XCTAssertEqual(reopened.phase, .recovered)
        XCTAssertEqual(reopened.session.document.pages.count, 4)
        XCTAssertTrue(reopened.isModified)
    }

    func testDefaultPageAndRootIdentifiersSurviveAutosaveRecovery() async throws {
        let url = fixture("DefaultIdentityRecovery.siteforge")
        let writer = makeController()
        let pageIDs = writer.session.document.pages.map(\.id)
        let rootIDs = writer.session.document.pages.flatMap(\.rootNodeIDs)
        let saved = await writer.save(to: url)
        XCTAssertTrue(saved)
        try writer.session.execute(.renamePage(RenamePageCommand(
            pageID: writer.session.document.pages[0].id,
            name: "Recovered Home"
        )))
        try await Task.sleep(for: .milliseconds(600))

        let reader = makeController()
        await reader.open(url)
        reader.restoreRecovery()
        XCTAssertEqual(reader.session.document.pages.map(\.id), pageIDs)
        XCTAssertEqual(reader.session.document.pages.flatMap(\.rootNodeIDs), rootIDs)
        XCTAssertEqual(reader.session.document.pages[0].name, "Recovered Home")
    }

    func testDiscardAndMalformedRecoveryAreIntentional() async throws {
        let url = fixture("Discard.siteforge")
        let writer = makeController()
        let saved = await writer.save(to: url)
        XCTAssertTrue(saved)
        try addPage("Recovered", to: writer)
        try await Task.sleep(for: .milliseconds(600))

        let reader = makeController()
        await reader.open(url)
        XCTAssertNotNil(reader.recoveryCandidate)
        await reader.discardRecovery()
        XCTAssertNil(reader.recoveryCandidate)

        try Data("bad recovery".utf8).write(to: DocumentLifecycleBackend.recoveryURL(for: url))
        await reader.open(url)
        XCTAssertNil(reader.recoveryCandidate)
        XCTAssertEqual(reader.failure, .malformedRecovery)
    }

    func testRevertAndUnsavedCloseHandling() async throws {
        let url = fixture("Revert.siteforge")
        let controller = makeController()
        let saved = await controller.save(to: url)
        XCTAssertTrue(saved)
        try addPage("Draft", to: controller)
        XCTAssertFalse(controller.requestClose())
        XCTAssertTrue(controller.isCloseConfirmationPresented)
        await controller.revert()
        XCTAssertEqual(controller.session.document.pages.count, 2)
        XCTAssertEqual(controller.phase, .clean)
        XCTAssertTrue(controller.requestClose())
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

    private func makeController(backend: DocumentLifecycleBackend = DocumentLifecycleBackend()) -> DocumentLifecycleController {
        DocumentLifecycleController(session: DocumentSession(), backend: backend)
    }

    private func addPage(_ name: String, to controller: DocumentLifecycleController) throws {
        try controller.session.execute(.insertPage(InsertPageCommand(
            page: DocumentPage(name: name), index: controller.session.document.pages.count
        )))
    }

    private func fixture(_ name: String) -> URL {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = repository
            .appendingPathComponent(".siteforge-test-fixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fixtureURLs.contains(directory) { fixtureURLs.append(directory) }
        return directory.appendingPathComponent(name)
    }

    private var expectedRequirementIDs: Set<String> {
        ["SF-0301-002", "SF-0301-004", "SF-0301-005", "SF-0301-006", "SF-0301-008",
         "SF-0306-001", "SF-0306-002", "SF-0306-003", "SF-0306-004", "SF-0306-005", "SF-0306-006", "SF-0306-008",
         "SF-1504-001", "SF-1504-004", "SF-1504-006", "SF-1504-008"]
    }
}
