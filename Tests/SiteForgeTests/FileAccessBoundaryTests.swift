import XCTest
@testable import SiteForge

final class FileAccessBoundaryTests: XCTestCase {
    // These exercises pass real packages through descriptor-bound I/O. Keep
    // that system boundary inside the test host's owned temporary container;
    // a checkout can live beneath a File Provider or a user-selected folder.
    private var fixtureLease: ApplicationOwnedTestFixture!

    override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureLease = try ApplicationOwnedTestFixture.create("file-access")
    }

    override func tearDownWithError() throws {
        try fixtureLease.cleanup()
        try super.tearDownWithError()
    }

    // SF-1504-001, SF-1504-002, SF-1504-005, SF-1504-008
    func testRealSecurityScopedBookmarkPersistsAcrossServiceRecreation() async throws {
        let directory = fixtureDirectory()
        let projectURL = directory.appendingPathComponent("Selected.siteforge")
        try Data("selected".utf8).write(to: projectURL)
        let storeURL = directory.appendingPathComponent("access/bookmarks.json")

        let first = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            bookmarks: FileBookmarkStore(url: storeURL)
        )
        try await first.authorizeUserSelection(projectURL)
        let firstBytes = try await first.withAccess(to: projectURL, intent: .open) {
            try Data(contentsOf: $0)
        }
        XCTAssertEqual(firstBytes, Data("selected".utf8))

        let relaunched = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            bookmarks: FileBookmarkStore(url: storeURL)
        )
        let reopenedBytes = try await relaunched.withAccess(to: projectURL, intent: .revert) {
            try Data(contentsOf: $0)
        }
        XCTAssertEqual(reopenedBytes, firstBytes)
        XCTAssertEqual(try permissions(of: storeURL), 0o600)
        XCTAssertEqual(try permissions(of: storeURL.deletingLastPathComponent()), 0o700)
    }

    // SF-1504-001, SF-1504-002, SF-1504-005
    func testNewSavePersistsParentScopeBeforeCommitAndReopensCreatedProject() async throws {
        let projectURL = fixtureDirectory().appendingPathComponent("New Save.siteforge")
        let runtime = BookmarkRuntimeProbe()
        let bookmarks = MemoryBookmarkStore()
        let first = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            runtime: runtime,
            bookmarks: bookmarks,
            coordinator: FileCoordinatorProbe()
        )

        let projectKeyBeforeSave = FileAccessService.key(for: projectURL)
        try await first.authorizeUserSelection(projectURL)
        let persistedBeforeSave = await bookmarks.bookmark(for: projectKeyBeforeSave)
        XCTAssertNotNil(persistedBeforeSave)
        try await first.withAccess(to: projectURL, intent: .save) {
            try Data("created".utf8).write(to: $0)
        }
        XCTAssertEqual(FileAccessService.key(for: projectURL), projectKeyBeforeSave)
        let relaunched = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            runtime: runtime,
            bookmarks: bookmarks,
            coordinator: FileCoordinatorProbe()
        )
        let reopened = try await relaunched.withAccess(to: projectURL, intent: .open) {
            try Data(contentsOf: $0)
        }

        XCTAssertEqual(reopened, Data("created".utf8))
        let starts = await runtime.startCount
        let stops = await runtime.stopCount
        let creations = await runtime.bookmarkCreationCount
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(stops, 2)
        XCTAssertEqual(creations, 1)
    }

    // SF-1504-003, SF-1504-004, SF-1504-005
    func testStaleBookmarkRepairAndRelocationPreserveAccessWithBalancedScope() async throws {
        let oldURL = fixture("Old.siteforge")
        let movedURL = fixture("Moved.siteforge")
        try Data("moved".utf8).write(to: movedURL)
        let runtime = BookmarkRuntimeProbe(
            resolution: SecurityScopedBookmarkResolution(url: movedURL, isStale: true)
        )
        let bookmarks = MemoryBookmarkStore()
        await bookmarks.setBookmark(
            PersistedFileBookmark(bookmark: Data("legacy-bookmark".utf8)),
            for: FileAccessService.key(for: oldURL)
        )
        let coordinator = FileCoordinatorProbe()
        let service = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            runtime: runtime,
            bookmarks: bookmarks,
            coordinator: coordinator
        )

        let resolved = try await service.withAccess(to: oldURL, intent: .open) { $0 }

        XCTAssertEqual(resolved, movedURL)
        let startCount = await runtime.startCount
        let stopCount = await runtime.stopCount
        let bookmarkCreationCount = await runtime.bookmarkCreationCount
        let relocatedBookmark = await bookmarks.bookmark(for: FileAccessService.key(for: movedURL))
        let coordinationEvents = await coordinator.events
        XCTAssertEqual(startCount, 1)
        XCTAssertEqual(stopCount, 1)
        XCTAssertEqual(bookmarkCreationCount, 1)
        XCTAssertNotNil(relocatedBookmark)
        XCTAssertEqual(coordinationEvents, [.open])
    }

    // SF-1504-003, SF-1504-004
    func testMissingAndDeniedAccessAreTypedAndNeverRunFileOperation() async throws {
        let url = fixture("Denied.siteforge")
        try Data().write(to: url)
        let missing = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            runtime: BookmarkRuntimeProbe(),
            bookmarks: MemoryBookmarkStore(),
            coordinator: FileCoordinatorProbe()
        )
        await XCTAssertThrowsFileAccess(.missingBookmark) {
            try await missing.withAccess(to: url, intent: .open) { _ in
                XCTFail("Unselected file operation ran")
            }
        }

        let runtime = BookmarkRuntimeProbe(allowsAccess: false)
        let denied = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            runtime: runtime,
            bookmarks: MemoryBookmarkStore(),
            coordinator: FileCoordinatorProbe()
        )
        try await denied.authorizeUserSelection(url)
        await XCTAssertThrowsFileAccess(.permissionDenied) {
            try await denied.withAccess(to: url, intent: .open) { _ in
                XCTFail("Denied file operation ran")
            }
        }
        let deniedStartCount = await runtime.startCount
        let deniedStopCount = await runtime.stopCount
        XCTAssertEqual(deniedStartCount, 1)
        XCTAssertEqual(deniedStopCount, 0)
    }

    // SF-1504-003, SF-1504-004, SF-1603-004
    func testCoordinationFailureBalancesScopeAndPreservesExternalBytes() async throws {
        let url = fixture("Coordinated.siteforge")
        let original = Data("external bytes".utf8)
        try original.write(to: url)
        let runtime = BookmarkRuntimeProbe()
        let coordinator = FileCoordinatorProbe(failure: FileAccessFailure.coordinationFailed)
        let service = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            runtime: runtime,
            bookmarks: MemoryBookmarkStore(),
            coordinator: coordinator
        )
        try await service.authorizeUserSelection(url)

        await XCTAssertThrowsFileAccess(.coordinationFailed) {
            try await service.withAccess(to: url, intent: .save) { coordinatedURL in
                try Data("must not commit".utf8).write(to: coordinatedURL)
            }
        }

        XCTAssertEqual(try Data(contentsOf: url), original)
        let failedStartCount = await runtime.startCount
        let failedStopCount = await runtime.stopCount
        let failedCoordinationEvents = await coordinator.events
        XCTAssertEqual(failedStartCount, 1)
        XCTAssertEqual(failedStopCount, 1)
        XCTAssertEqual(failedCoordinationEvents, [.save])
    }

    // SF-1504-003, SF-1504-004, SF-1504-006
    func testFilePresenterReportsChangeMoveAndDeletionWithoutChangingContent() throws {
        let originalURL = fixture("Presented.siteforge")
        let movedURL = fixture("Relocated.siteforge")
        let events = LockedEvents()
        let presenter = ProjectFilePresenter(url: originalURL) { events.append($0) }

        presenter.presentedItemDidChange()
        presenter.presentedItemDidMove(to: movedURL)
        let deletion = expectation(description: "deletion accommodated")
        presenter.accommodatePresentedItemDeletion { error in
            XCTAssertNil(error)
            deletion.fulfill()
        }
        wait(for: [deletion], timeout: 1)

        XCTAssertEqual(presenter.presentedItemURL, movedURL)
        XCTAssertEqual(events.values, [.changed, .moved(movedURL), .deleted])
    }

    // SF-1504-001, SF-1504-003, SF-1504-004, SF-1504-008
    @MainActor
    func testLifecycleReopensThroughPersistedBookmarkAfterRelaunch() async throws {
        let directory = fixtureDirectory()
        let projectURL = directory.appendingPathComponent("Lifecycle.siteforge")
        let bookmarkURL = directory.appendingPathComponent("access/bookmarks.json")
        let package = ProjectPackage(document: CanonicalDocument())
        try await ProjectPackageStore().write(package, to: projectURL)

        let firstAccess = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            bookmarks: FileBookmarkStore(url: bookmarkURL)
        )
        let first = DocumentLifecycleController(
            session: DocumentSession(),
            backend: DocumentLifecycleBackend(fileAccess: firstAccess),
            recoveryDirectory: directory.appendingPathComponent("recovery")
        )
        let selectedOpenResult = await first.requestOpen(projectURL, userSelected: true)
        XCTAssertEqual(selectedOpenResult, .completed)

        let relaunchedAccess = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            bookmarks: FileBookmarkStore(url: bookmarkURL)
        )
        let relaunched = DocumentLifecycleController(
            session: DocumentSession(),
            backend: DocumentLifecycleBackend(fileAccess: relaunchedAccess),
            recoveryDirectory: directory.appendingPathComponent("recovery")
        )
        let relaunchedOpenResult = await relaunched.requestOpen(projectURL)
        XCTAssertEqual(relaunchedOpenResult, .completed)
        XCTAssertEqual(relaunched.session.document, package.document)
        XCTAssertEqual(relaunched.fileURL, projectURL)
    }

    // SF-1504-003, SF-1504-004, SF-1504-006
    @MainActor
    func testExternalPresentationEventsPreserveCanonicalStateAndTrackRelocation() async throws {
        let directory = fixtureDirectory()
        let originalURL = directory.appendingPathComponent("Original.siteforge")
        let movedURL = directory.appendingPathComponent("Moved.siteforge")
        let package = ProjectPackage(document: CanonicalDocument())
        try await ProjectPackageStore().write(package, to: originalURL)
        let access = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            bookmarks: FileBookmarkStore(url: directory.appendingPathComponent("access/bookmarks.json"))
        )
        let controller = DocumentLifecycleController(
            session: DocumentSession(),
            backend: DocumentLifecycleBackend(fileAccess: access),
            recoveryDirectory: directory.appendingPathComponent("recovery")
        )
        let openResult = await controller.requestOpen(originalURL, userSelected: true)
        XCTAssertEqual(openResult, .completed)
        let beforeDocument = controller.session.document
        let beforeURL = controller.fileURL

        controller.receiveFilePresentation(.changed)
        XCTAssertEqual(controller.phase, .conflicted)
        XCTAssertEqual(controller.failure, .externalModification)
        XCTAssertEqual(controller.session.document, beforeDocument)
        XCTAssertEqual(controller.fileURL, beforeURL)

        try FileManager.default.moveItem(at: originalURL, to: movedURL)
        controller.receiveFilePresentation(.moved(movedURL))
        XCTAssertEqual(controller.fileURL, movedURL)
        XCTAssertEqual(controller.displayName, "Moved")
        XCTAssertEqual(controller.session.document, beforeDocument)
    }

    // SF-1504-008
    func testDiagnosticsAreCompleteAndRedactFileNamesAndAbsolutePaths() async throws {
        let secret = fixture("Confidential Customer.siteforge")
        try Data("private content".utf8).write(to: secret)
        let diagnostics = FileAccessDiagnostics()
        let service = FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            runtime: BookmarkRuntimeProbe(),
            bookmarks: MemoryBookmarkStore(),
            coordinator: FileCoordinatorProbe(),
            diagnostics: diagnostics
        )
        try await service.authorizeUserSelection(secret)
        _ = try await service.withAccess(to: secret, intent: .inspect) { try Data(contentsOf: $0).count }

        let records = await service.diagnosticRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(Set(records[0].requirementIDs), FileAccessService.requirementIDs)
        XCTAssertTrue(records[0].sanitizedResourceID.hasPrefix("resource-"))
        let description = String(describing: records)
        XCTAssertFalse(description.contains(secret.path))
        XCTAssertFalse(description.contains(secret.lastPathComponent))
        XCTAssertFalse(description.contains("private content"))
    }

    // SF-1504-001, SF-1504-006, SF-1504-008
    func testDistributionCandidateDeclaresExactSandboxAndProjectTypePolicy() throws {
        let fixture = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "DistributionPolicy", withExtension: "entitlements")
        )
        let data = try Data(contentsOf: fixture)
        let entitlements = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(entitlements["com.apple.security.app-sandbox"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.user-selected.read-write"] as? Bool, true)
        XCTAssertEqual(entitlements["com.apple.security.files.bookmarks.app-scope"] as? Bool, true)
        XCTAssertEqual(entitlements.count, 3)

        let info = try XCTUnwrap(Bundle.main.infoDictionary)
        let exported = try XCTUnwrap(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        XCTAssertEqual(exported.first?["UTTypeIdentifier"] as? String, "app.siteforge.project-package")
    }

    private func fixtureDirectory() -> URL {
        let url = fixtureLease.url.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixture(_ name: String) -> URL { fixtureDirectory().appendingPathComponent(name) }

    private func permissions(of url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue ?? -1
    }
}

private actor MemoryBookmarkStore: FileBookmarkPersisting {
    private var records: [String: PersistedFileBookmark] = [:]
    func bookmark(for key: String) -> PersistedFileBookmark? { records[key] }
    func setBookmark(_ bookmark: PersistedFileBookmark, for key: String) { records[key] = bookmark }
}

private actor BookmarkRuntimeProbe: SecurityScopedBookmarkRuntime {
    private let configuredResolution: SecurityScopedBookmarkResolution?
    private let allowsAccess: Bool
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var bookmarkCreationCount = 0

    init(resolution: SecurityScopedBookmarkResolution? = nil, allowsAccess: Bool = true) {
        configuredResolution = resolution
        self.allowsAccess = allowsAccess
    }

    func makeBookmark(for url: URL) -> Data {
        bookmarkCreationCount += 1
        return Data(url.path.utf8)
    }

    func resolveBookmark(_ data: Data) throws -> SecurityScopedBookmarkResolution {
        if let configuredResolution { return configuredResolution }
        guard let path = String(data: data, encoding: .utf8) else {
            throw FileAccessFailure.corruptBookmarkStore
        }
        return SecurityScopedBookmarkResolution(url: URL(fileURLWithPath: path), isStale: false)
    }

    func startAccessing(_ url: URL) -> Bool {
        startCount += 1
        return allowsAccess
    }

    func stopAccessing(_ url: URL) { stopCount += 1 }
}

private actor FileCoordinatorProbe: ProjectFileCoordinating {
    private let failure: Error?
    private(set) var events: [FileAccessIntent] = []

    init(failure: Error? = nil) { self.failure = failure }

    func coordinate<T: Sendable>(
        at url: URL,
        intent: FileAccessIntent,
        operation: @escaping @Sendable (URL) async throws -> T
    ) async throws -> T {
        events.append(intent)
        if let failure { throw failure }
        return try await operation(url)
    }
}

private final class LockedEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ProjectFilePresentationEvent] = []
    func append(_ event: ProjectFilePresentationEvent) { lock.withLock { storage.append(event) } }
    var values: [ProjectFilePresentationEvent] { lock.withLock { storage } }
}

private func XCTAssertThrowsFileAccess<T>(
    _ expected: FileAccessFailure,
    operation: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await operation()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? FileAccessFailure, expected, file: file, line: line)
    }
}
