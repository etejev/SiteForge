import XCTest
@testable import SiteForge

@MainActor
final class PersistedHistoryTests: XCTestCase {
    nonisolated(unsafe) private var fixtureDirectory: URL!

    nonisolated override func setUp() {
        super.setUp()
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        fixtureDirectory = repository.appendingPathComponent(".siteforge-history-fixtures", isDirectory: true)
        try? FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
    }

    nonisolated override func tearDown() {
        try? FileManager.default.removeItem(at: fixtureDirectory)
        fixtureDirectory = nil
        super.tearDown()
    }

    func testRequirementMappingAndTransactionMetadataAreStableAndSanitized() throws {
        XCTAssertEqual(PersistedHistoryStore.requirementIDs, expectedRequirementIDs)
        let session = DocumentSession()
        let page = DocumentPage(name: "Private page content")
        try session.execute(.insertPage(InsertPageCommand(page: page, index: 0)))
        let entry = session.historySnapshot().undoEntries[0]
        XCTAssertEqual(entry.parentRevision, 0)
        XCTAssertEqual(entry.resultRevision, 1)
        XCTAssertEqual(entry.commandName, .insertPage)
        XCTAssertEqual(entry.label, "Insert Page")
        XCTAssertNotNil(entry.timestamp.date)
        XCTAssertEqual(entry.affectedIdentifiers, entry.forward.targets)
        XCTAssertFalse(entry.label.contains(page.name))
    }

    func testSaveReopenRestoresUndoRedoOrderingAndShellAvailability() async throws {
        let url = fixtureDirectory.appendingPathComponent("History.siteforge")
        let writer = makeController()
        let pageID = PageID()
        try writer.session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: "History Page"), index: 0)))
        try writer.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "First")))
        try writer.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Second")))
        try writer.session.undo()
        let writerSaved = await writer.save(to: url)
        XCTAssertTrue(writerSaved)

        let reader = makeController()
        let openResult = await reader.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        XCTAssertTrue(reader.session.canUndo)
        XCTAssertTrue(reader.session.canRedo)
        XCTAssertNil(reader.historyNotice)
        let shell = WorkspaceShellState(documentSession: reader.session)
        XCTAssertTrue(shell.canUndo)
        XCTAssertTrue(shell.canRedo)

        try reader.session.redo()
        XCTAssertEqual(reader.session.document.pages[0].name, "Second")
        try reader.session.undo()
        XCTAssertEqual(reader.session.document.pages[0].name, "First")
        try reader.session.undo()
        XCTAssertEqual(reader.session.document.pages[0].name, "History Page")
        try reader.session.redo()
        XCTAssertEqual(reader.session.document.pages[0].name, "First")
    }

    func testRedoBranchInvalidatesAfterReopen() async throws {
        let url = fixtureDirectory.appendingPathComponent("Branch.siteforge")
        let controller = makeController()
        let pageID = PageID()
        try controller.session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: "Branch Page"), index: 0)))
        try controller.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Old branch")))
        try controller.session.undo()
        let branchSaved = await controller.save(to: url)
        XCTAssertTrue(branchSaved)

        let reopened = makeController()
        let openResult = await reopened.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        XCTAssertTrue(reopened.session.canRedo)
        try reopened.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "New branch")))
        XCTAssertFalse(reopened.session.canRedo)
        XCTAssertEqual(reopened.session.document.pages[0].name, "New branch")
    }

    func testRecoveryRestoresOnlyTransactionsAfterExplicitDurableBoundary() async throws {
        let url = fixtureDirectory.appendingPathComponent("RecoveryHistory.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        let pageID = PageID()
        try writer.session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: "Recovery Page"), index: 0)))
        let recoverySaved = await writer.save(to: url)
        XCTAssertTrue(recoverySaved)
        let durableRevision = writer.session.document.revision
        try writer.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Recovered one")))
        try writer.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Recovered two")))
        await flushAutosave(writer, with: debouncer)

        let reopened = makeController()
        let openResult = await reopened.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        XCTAssertNotNil(reopened.recoveryCandidate)
        let restoreResult = await reopened.requestRestoreRecovery()
        XCTAssertEqual(restoreResult, .completed)
        XCTAssertEqual(reopened.session.historyBoundaryRevision, durableRevision)
        XCTAssertTrue(reopened.session.canUndo)
        try reopened.session.undo()
        XCTAssertEqual(reopened.session.document.pages[0].name, "Recovered one")
        try reopened.session.undo()
        XCTAssertEqual(reopened.session.document.pages[0].name, "Recovery Page")
        XCTAssertFalse(reopened.session.canUndo, "Undo must not cross the recovery boundary")

        try reopened.session.redo()
        try reopened.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Recovered branch")))
        XCTAssertFalse(reopened.session.canRedo)
    }

    func testDiscardedRecoveryRetainsDurableHistoryBoundary() async throws {
        let url = fixtureDirectory.appendingPathComponent("DiscardBoundary.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        let pageID = PageID()
        try writer.session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: "Durable Page"), index: 0)))
        let discardSaved = await writer.save(to: url)
        XCTAssertTrue(discardSaved)
        try writer.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Recovery only")))
        await flushAutosave(writer, with: debouncer)

        let reopened = makeController()
        let openResult = await reopened.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        await reopened.discardRecovery()
        XCTAssertEqual(reopened.session.document.pages[0].name, "Durable Page")
        XCTAssertTrue(reopened.session.canUndo)
        try reopened.session.undo()
        XCTAssertEqual(reopened.session.document.pages.map(\.name), ["Home", "Not Found"])
        XCTAssertFalse(reopened.session.canUndo)
    }

    func testIncompatibleRecoveryHistoryRestoresDocumentOnCleanNonCrossableBaseline() async throws {
        let url = fixtureDirectory.appendingPathComponent("IncompatibleRecovery.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        let pageID = PageID()
        try writer.session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: "Recovery Boundary"), index: 0)))
        let durableSaved = await writer.save(to: url)
        XCTAssertTrue(durableSaved)
        try writer.session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Recovered")))
        await flushAutosave(writer, with: debouncer)

        let recoveryURL = DocumentLifecycleBackend.recoveryURL(
            for: writer.currentProjectID,
            in: fixtureDirectory.appendingPathComponent("recovery", isDirectory: true)
        )
        let packageStore = ProjectPackageStore()
        let recoverySnapshot = try await packageStore.readSnapshot(from: recoveryURL)
        let recoveryPackage = recoverySnapshot.package
        let history = recoveryPackage.optionalMembers.first { $0.path == PersistedHistoryStore.memberPath }!
        let unsupported = try mutate(history.data) { $0["schemaVersion"] = 99 }
        var members = recoveryPackage.optionalMembers.filter { $0.path != PersistedHistoryStore.memberPath }
        members.append(ProjectPackageMember(path: PersistedHistoryStore.memberPath, data: unsupported))
        try await packageStore.write(ProjectPackage(
            projectID: recoveryPackage.projectID, createdAt: recoveryPackage.createdAt,
            modifiedAt: recoveryPackage.modifiedAt, document: recoveryPackage.document,
            optionalMembers: members, compatibility: recoveryPackage.compatibility
        ), to: recoveryURL, expected: recoverySnapshot.file.fingerprint)

        let reopened = makeController()
        let openResult = await reopened.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        XCTAssertNotNil(reopened.recoveryCandidate)
        let restoreResult = await reopened.requestRestoreRecovery()
        XCTAssertEqual(restoreResult, .completed)
        XCTAssertEqual(reopened.session.document.pages[0].name, "Recovered")
        XCTAssertFalse(reopened.session.canUndo)
        XCTAssertFalse(reopened.session.canRedo)
        XCTAssertTrue(reopened.historyNotice?.contains("not supported") == true)
        XCTAssertEqual(reopened.session.historyBoundaryRevision, reopened.session.document.revision)
    }

    func testMissingHistoryOpensLegacyPackageOnCleanCompatibilityBaseline() async throws {
        let document = CanonicalDocument(revision: 7, pages: [DocumentPage(name: "Legacy")])
        let package = ProjectPackage(document: document)
        let url = fixtureDirectory.appendingPathComponent("Legacy.siteforge")
        try await ProjectPackageStore().write(package, to: url)

        let controller = makeController()
        let openResult = await controller.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        XCTAssertEqual(controller.session.document, document)
        XCTAssertFalse(controller.session.canUndo)
        XCTAssertFalse(controller.session.canRedo)
        XCTAssertEqual(controller.session.historyBoundaryRevision, 7)
        XCTAssertTrue(controller.historyNotice?.contains("legacy") == true)
    }

    func testCorruptUnsupportedOversizedAndMismatchedHistoryIsIsolated() async throws {
        let valid = try await makeValidHistoryFixture(entryCount: 2)
        var cases: [(Data, PersistedHistoryError)] = [
            (Data("not-json".utf8), .corrupt),
            (Data(repeating: 0, count: PersistedHistoryStore.maximumHistoryBytes + 1), .oversized),
            (try mutate(valid.data) { $0["schemaVersion"] = 99 }, .unsupportedSchema(99)),
            (try mutate(valid.data) { $0["documentRevision"] = 999 }, .documentMismatch),
        ]
        let duplicated = try mutate(valid.data) { object in
            var entries = object["undoEntries"] as! [[String: Any]]
            entries.append(entries[0]); object["undoEntries"] = entries
        }
        cases.append((duplicated, .duplicateTransaction))
        let reordered = try mutate(valid.data) { object in
            var entries = object["undoEntries"] as! [[String: Any]]
            entries.swapAt(0, 1); object["undoEntries"] = entries
        }
        cases.append((reordered, .reorderedTransactions))
        let identityMismatch = try mutate(valid.data) { object in
            var entries = object["undoEntries"] as! [[String: Any]]
            entries[0]["label"] = "Private content"; object["undoEntries"] = entries
        }
        cases.append((identityMismatch, .identityMismatch))
        let revisionMismatch = try mutate(valid.data) { object in
            var entries = object["undoEntries"] as! [[String: Any]]
            entries[0]["resultRevision"] = 44; object["undoEntries"] = entries
        }
        cases.append((revisionMismatch, .revisionMismatch))

        for (data, expected) in cases {
            let store = PersistedHistoryStore()
            let result = await store.load(from: package(valid.package, historyData: data))
            XCTAssertEqual(result, .cleanBaseline(expected))
        }
    }

    func testInverseIdentityMismatchAndCanonicalDocumentSurvival() async throws {
        let valid = try await makeValidHistoryFixture(entryCount: 1)
        let mismatched = try mutate(valid.data) { object in
            var entries = object["undoEntries"] as! [[String: Any]]
            entries[0]["inverse"] = entries[0]["forward"]
            object["undoEntries"] = entries
        }
        let package = package(valid.package, historyData: mismatched)
        let url = fixtureDirectory.appendingPathComponent("BadInverse.siteforge")
        try await ProjectPackageStore().write(package, to: url)

        let controller = makeController()
        let openResult = await controller.requestOpen(url)
        XCTAssertEqual(openResult, .completed)
        XCTAssertEqual(controller.session.document, valid.package.document)
        XCTAssertFalse(controller.session.canUndo)
        XCTAssertNotNil(controller.historyNotice)
    }

    func testRetentionAndByteLimitsKeepNewestValidTransactions() async throws {
        let session = DocumentSession()
        let pageID = PageID()
        try session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: "Retention Page"), index: 0)))
        for index in 0..<(PersistedHistoryStore.maximumEntryCount + 20) {
            try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Page \(index)")))
        }
        let store = PersistedHistoryStore()
        let retainedData = try await store.encodeRetained(session.historySnapshot())
        XCTAssertLessThanOrEqual(retainedData.count, PersistedHistoryStore.maximumHistoryBytes)
        let retained = await store.load(from: package(ProjectPackage(document: session.document), historyData: retainedData))
        guard case .restored(let snapshot) = retained else { return XCTFail("Retained history must validate") }
        XCTAssertLessThanOrEqual(snapshot.undoEntries.count + snapshot.redoEntries.count, PersistedHistoryStore.maximumEntryCount)
        XCTAssertEqual(snapshot.undoEntries.last?.resultRevision, session.document.revision)

        for index in 0..<24 {
            try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: String(repeating: "x", count: 30_000) + "\(index)")))
        }
        let sizeRetained = try await store.encodeRetained(session.historySnapshot())
        XCTAssertLessThanOrEqual(sizeRetained.count, PersistedHistoryStore.maximumHistoryBytes)
    }

    func testHistoryMemberAndWholePackageRemainDeterministic() async throws {
        let valid = try await makeValidHistoryFixture(entryCount: 2)
        let firstHistory = try await PersistedHistoryStore().encodeRetained(valid.snapshot)
        let secondHistory = try await PersistedHistoryStore().encodeRetained(valid.snapshot)
        XCTAssertEqual(firstHistory, secondHistory)
        let package = package(valid.package, historyData: firstHistory)
        let packageStore = ProjectPackageStore()
        let firstPackage = try await packageStore.encode(package)
        let secondPackage = try await packageStore.encode(package)
        XCTAssertEqual(firstPackage, secondPackage)
    }

    func testHistoryDiagnosticsRedactContentPathsAndRawIdentity() async throws {
        let diagnostics = PersistedHistoryDiagnostics()
        let store = PersistedHistoryStore(diagnostics: diagnostics)
        let valid = try await makeValidHistoryFixture(entryCount: 1, pageName: "top-secret-page")
        _ = await store.load(from: package(valid.package, historyData: valid.data))
        let description = String(describing: await diagnostics.records)
        XCTAssertFalse(description.contains("top-secret-page"))
        XCTAssertFalse(description.contains(valid.package.document.id.description))
        XCTAssertFalse(description.contains(fixtureDirectory.path))
        XCTAssertTrue(description.contains("document-"))
    }

    private func makeController(
        autosaveDebouncer: any LifecycleAutosaveDebouncing = ContinuousLifecycleAutosaveDebouncer()
    ) -> DocumentLifecycleController {
        let recoveryDirectory = fixtureDirectory.appendingPathComponent("recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        return DocumentLifecycleController(
            session: DocumentSession(),
            recoveryDirectory: recoveryDirectory,
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

    private func makeValidHistoryFixture(entryCount: Int, pageName: String = "Fixture Page") async throws
    -> (package: ProjectPackage, snapshot: PersistedHistorySnapshot, data: Data) {
        let session = DocumentSession()
        let pageID = PageID()
        try session.execute(.insertPage(InsertPageCommand(page: DocumentPage(id: pageID, name: pageName), index: 0)))
        if entryCount > 1 {
            for index in 1..<entryCount {
                try session.execute(.renamePage(RenamePageCommand(pageID: pageID, name: "Name \(index)")))
            }
        }
        let snapshot = session.historySnapshot()
        let data = try await PersistedHistoryStore().encodeRetained(snapshot)
        return (ProjectPackage(document: session.document), snapshot, data)
    }

    private func package(_ package: ProjectPackage, historyData: Data) -> ProjectPackage {
        ProjectPackage(
            projectID: package.projectID, createdAt: package.createdAt, modifiedAt: package.modifiedAt,
            document: package.document,
            optionalMembers: [ProjectPackageMember(path: PersistedHistoryStore.memberPath, data: historyData)],
            compatibility: package.compatibility
        )
    }

    private func mutate(_ data: Data, _ mutation: (inout [String: Any]) -> Void) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        mutation(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private var expectedRequirementIDs: Set<String> {
        ["SF-0306-002", "SF-0306-004", "SF-0306-005", "SF-0306-008",
         "SF-0307-001", "SF-0307-002", "SF-0307-003", "SF-0307-004", "SF-0307-005",
         "SF-0307-006", "SF-0307-008"]
    }
}
