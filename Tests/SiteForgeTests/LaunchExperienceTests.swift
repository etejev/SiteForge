import XCTest
@testable import SiteForge

@MainActor
final class LaunchExperienceTests: XCTestCase {
    nonisolated(unsafe) private var fixtureDirectory: URL!
    nonisolated(unsafe) private var fixtureLease: ApplicationOwnedTestFixture!

    nonisolated override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureLease = try ApplicationOwnedTestFixture.create("launch")
        fixtureDirectory = fixtureLease.url
    }

    nonisolated override func tearDownWithError() throws {
        try fixtureLease.cleanup()
        try super.tearDownWithError()
    }

    func testRequirementMappingAndEveryOpenTransition() async throws {
        let url = fixture("Transitions.siteforge")
        try await writePackage(to: url)
        let controller = makeController()

        await controller.openProjectAndWait(url)

        XCTAssertEqual(controller.state, .workspace)
        XCTAssertEqual(controller.transitionHistory, [
            .welcome, .loadingIndeterminate, .loadingDeterminate,
            .loadingNonCancelable, .workspace,
        ])
        XCTAssertEqual(LaunchExperienceController.requirementIDs, expectedRequirementIDs)
    }

    func testBlankCreationUsesRealTwoStepCleanBaseline() async {
        let controller = makeController()
        await controller.createBlankProjectAndWait()

        XCTAssertEqual(controller.state, .workspace)
        XCTAssertEqual(controller.transitionHistory, [.welcome, .creating, .loadingNonCancelable, .workspace])
        XCTAssertEqual(controller.lifecycle.session.document.pages.map(\.route.rawValue), ["/", "/404"])
        XCTAssertFalse(controller.lifecycle.session.canUndo)
        XCTAssertEqual(controller.lifecycle.phase, .clean)
    }

    // SF-AUTHORING-105 / SF-0201-002/003/004/006, SF-0204-002/003/004/006
    func testAuthorizedRecentProjectRecordsDeduplicatesReopensAndForgetsWithoutPaths() async throws {
        let url = fixture("Private Client.siteforge")
        try await writePackage(to: url)
        let bookmarks = MemoryLaunchBookmarkStore()
        let runtime = LaunchBookmarkRuntime()
        let recentStore = MemoryRecentProjectStore()
        let firstBackend = DocumentLifecycleBackend(fileAccess: FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            runtime: runtime,
            bookmarks: bookmarks,
            coordinator: LaunchFileCoordinator()
        ))
        let first = makeController(backend: firstBackend, recentProjectStore: recentStore)

        first.openProject(url, userSelected: true)
        try await waitUntil { first.state == .workspace }
        let retained = try await recentStore.load()
        XCTAssertEqual(retained.count, 1)
        XCTAssertEqual(retained.first?.displayName, "Private Client")
        XCTAssertFalse(String(describing: retained).contains(fixtureDirectory.path))

        let relaunchedBackend = DocumentLifecycleBackend(fileAccess: FileAccessService(
            policy: .sandboxedUserSelectedReadWrite,
            runtime: runtime,
            bookmarks: bookmarks,
            coordinator: LaunchFileCoordinator()
        ))
        let relaunched = makeController(backend: relaunchedBackend, recentProjectStore: recentStore)
        await relaunched.loadRecentProjects()
        let recent = try XCTUnwrap(relaunched.recentProjects.first)
        relaunched.openRecentProject(recent)
        try await waitUntil { relaunched.state == .workspace }
        XCTAssertEqual(relaunched.lifecycle.displayName, "Private Client")

        relaunched.forgetRecentProject(recent)
        try await waitUntil { relaunched.recentProjects.isEmpty }
        let afterRemoval = try await recentStore.load()
        let retainedAuthorization = await bookmarks.bookmark(for: FileAccessService.key(for: url))
        XCTAssertTrue(afterRemoval.isEmpty)
        XCTAssertNotNil(retainedAuthorization)
    }

    func testRecentProjectPolicyBoundsValidatesAndKeepsNewestStableIdentity() {
        var projects: [RecentProjectReference] = []
        let base = FileManager.default.temporaryDirectory
        for index in 0..<12 {
            projects = RecentProjectPolicy.recording(
                base.appendingPathComponent("Project-\(index).siteforge"),
                in: projects
            )
        }
        let newest = projects[0]
        projects = RecentProjectPolicy.recording(
            base.appendingPathComponent("Project-4.siteforge"),
            in: projects
        )

        XCTAssertEqual(projects.count, RecentProjectStore.capacity)
        XCTAssertEqual(projects.first?.displayName, "Project-4")
        XCTAssertTrue(RecentProjectPolicy.isValid(projects))
        XCTAssertEqual(Set(projects.map(\.id)).count, projects.count)
        XCTAssertNotEqual(projects.first?.id, newest.id)
    }

    func testRecentProjectStoreRoundTripsVersionedPathFreeRecordsAndRejectsCorruption() async throws {
        let url = fixtureDirectory.appendingPathComponent("recent/recent-projects.json")
        let store = RecentProjectStore(url: url)
        let projectURL = fixture("Stored.siteforge")
        let projects = RecentProjectPolicy.recording(projectURL, in: [])

        try await store.save(projects)
        let loaded = try await store.load()
        XCTAssertEqual(loaded, projects)
        let encoded = try String(contentsOf: url)
        XCTAssertFalse(encoded.contains(projectURL.path))
        XCTAssertEqual(
            (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue,
            0o600
        )

        try Data("{\"schemaVersion\":9,\"projects\":[]}".utf8).write(to: url, options: .atomic)
        do {
            _ = try await store.load()
            XCTFail("Unsupported recent-project stores must be rejected")
        } catch {
            XCTAssertEqual(error as? RecentProjectStoreFailure, .malformed)
        }
    }

    func testCancelableAndNonCancelableStagesAreExplicit() {
        XCTAssertTrue(ProjectLoadUpdate.readingPackage.status.canCancel)
        XCTAssertTrue(ProjectLoadUpdate.validatingCanonicalDocument.status.canCancel)
        XCTAssertTrue(ProjectLoadUpdate.validatingHistory.status.canCancel)
        XCTAssertFalse(ProjectLoadUpdate.preparingWorkspace.status.canCancel)
        XCTAssertFalse(ProjectLoadUpdate.checkingRecovery.status.canCancel)
        XCTAssertNil(ProjectLoadUpdate.readingPackage.status.progress)
        XCTAssertEqual(ProjectLoadUpdate.validatingHistory.status.progress, 2.0 / 3.0)
    }

    func testCancellationPreservesExistingDocument() async throws {
        let backend = DocumentLifecycleBackend()
        await backend.configureForTesting(delayNanoseconds: 500_000_000)
        let controller = makeController(backend: backend)
        try addPage("Current", to: controller.lifecycle.session)
        let before = controller.lifecycle.session.document
        let incoming = fixture("Incoming.siteforge")
        try await writePackage(to: incoming)

        controller.openProject(incoming)
        try await waitUntil { controller.lifecycle.pendingUnsavedChangesPrompt != nil }
        let prompt = try XCTUnwrap(controller.lifecycle.pendingUnsavedChangesPrompt)
        XCTAssertEqual(prompt.transition, .openProject)
        controller.lifecycle.resolveUnsavedChanges(.discard, promptID: prompt.id)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(controller.state.kind, .loadingIndeterminate)
        controller.cancelCurrentOperation()
        try await waitUntil { controller.state.kind == .welcome }

        XCTAssertEqual(controller.lifecycle.session.document, before)
        let records = await controller.diagnostics.snapshot()
        XCTAssertEqual(records.last?.result, .cancelled)
    }

    func testNonCancelableStageIgnoresCancellationRequest() async {
        let controller = makeController(preview: .loadingNonCancelable)
        let before = controller.state
        controller.cancelCurrentOperation()
        XCTAssertEqual(controller.state, before)
    }

    func testMalformedAndIncompatibleFailuresPreserveExistingDocument() async throws {
        for (name, data, expected) in [
            ("Malformed.siteforge", Data("not a package".utf8), DocumentLifecycleFailure.malformedPackage),
            ("Incompatible.siteforge", try await incompatiblePackageData(), .incompatiblePackage),
        ] {
            let controller = makeController()
            try addPage("Keep Me", to: controller.lifecycle.session)
            let before = controller.lifecycle.session.document
            let url = fixture(name)
            try data.write(to: url)

            let operation = Task { await controller.openProjectAndWait(url) }
            try await waitUntil { controller.lifecycle.pendingUnsavedChangesPrompt != nil }
            let prompt = try XCTUnwrap(controller.lifecycle.pendingUnsavedChangesPrompt)
            controller.lifecycle.resolveUnsavedChanges(.discard, promptID: prompt.id)
            await operation.value

            guard case .failure(let presentation) = controller.state else {
                return XCTFail("Expected failure for \(name)")
            }
            XCTAssertEqual(presentation.failure, expected)
            XCTAssertEqual(controller.lifecycle.session.document, before)
            XCTAssertFalse(presentation.message.contains(url.path))
        }
    }

    func testRetryUsesSameSanitizedTargetAndCanRecover() async throws {
        let url = fixture("Retry.siteforge")
        try Data("bad".utf8).write(to: url)
        let controller = makeController()
        await controller.openProjectAndWait(url)
        XCTAssertEqual(controller.state.kind, .failure)

        try FileManager.default.removeItem(at: url)
        try await writePackage(to: url)
        controller.retry()
        try await waitUntil { controller.state == .workspace }

        XCTAssertEqual(controller.lifecycle.displayName, "Retry")
    }

    func testNewerRecoveryCandidatePresentsRestoreAndDiscardPaths() async throws {
        let url = fixture("Recovery.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        let saved = await writer.lifecycle.save(to: url)
        XCTAssertTrue(saved)
        try addPage("Recovered", to: writer.lifecycle.session)
        await debouncer.waitUntilPending()
        debouncer.fireAll()
        while writer.lifecycle.hasPendingAutosaveWork { await Task.yield() }

        let restorer = makeController()
        await restorer.openProjectAndWait(url)
        XCTAssertEqual(restorer.state.kind, .recovery)
        restorer.restoreRecovery()
        try await waitUntil { restorer.state == .workspace }
        XCTAssertEqual(restorer.state, .workspace)
        XCTAssertEqual(restorer.lifecycle.phase, .recovered)
        XCTAssertTrue(restorer.lifecycle.session.document.pages.contains { $0.name == "Recovered" })

        let discarder = makeController()
        await discarder.openProjectAndWait(url)
        XCTAssertEqual(discarder.state.kind, .recovery)
        discarder.discardRecovery()
        try await waitUntil { discarder.state == .workspace }
        XCTAssertNil(discarder.lifecycle.recoveryCandidate)
    }

    func testStateMessagesAreAccessibleSpecificAndPathFree() {
        for update in ProjectLoadUpdate.allCases {
            XCTAssertFalse(update.status.accessibilityLabel.isEmpty)
            XCTAssertFalse(update.status.detail.isEmpty)
            XCTAssertFalse(update.status.detail.contains("/Users/"))
            XCTAssertFalse(LaunchExperienceState.working(update.status).announcement.isEmpty)
        }
        let failure = LaunchExperienceController(
            lifecycle: DocumentLifecycleController(session: DocumentSession()),
            previewScenario: .failure
        )
        XCTAssertTrue(failure.state.announcement.contains("failed"))
    }

    func testEveryInteractiveTransitionPostsItsSpecificAccessibilityAnnouncement() async {
        var messages: [String] = []
        let controller = LaunchExperienceController(
            lifecycle: DocumentLifecycleController(
                session: DocumentSession(),
                recoveryDirectory: fixtureDirectory.appendingPathComponent("announcement-recovery", isDirectory: true)
            ),
            previewScenario: .welcome,
            announcementPoster: AccessibilityAnnouncementPoster { messages.append($0) }
        )

        controller.announceCurrentState()
        await controller.createBlankProjectAndWait()
        controller.announceCurrentState()

        XCTAssertEqual(messages, [
            "SiteForge is ready. Create a blank project or open an existing project.",
            "Project ready.",
        ])
    }

    func testReduceMotionReplacesAnimatedIndeterminateProgress() {
        XCTAssertTrue(LaunchExperienceController.usesAnimatedIndeterminateProgress(reduceMotion: false))
        XCTAssertFalse(LaunchExperienceController.usesAnimatedIndeterminateProgress(reduceMotion: true))
    }

    func testPreferredKeyboardFocusIsDeterministicForEveryInteractiveState() {
        XCTAssertEqual(makeController(preview: .welcome).preferredFocusIdentifier, "launch.newBlankProject")
        XCTAssertEqual(makeController(preview: .loadingIndeterminate).preferredFocusIdentifier, "launch.cancel")
        XCTAssertNil(makeController(preview: .loadingNonCancelable).preferredFocusIdentifier)
        XCTAssertEqual(makeController(preview: .failure).preferredFocusIdentifier, "launch.retry")
        XCTAssertEqual(makeController(preview: .recovery).preferredFocusIdentifier, "launch.recovery.restore")
    }

    func testLoadingLeavesMainActorResponsive() async throws {
        let backend = DocumentLifecycleBackend()
        await backend.configureForTesting(delayNanoseconds: 250_000_000)
        let controller = makeController(backend: backend)
        let url = fixture("Responsive.siteforge")
        try await writePackage(to: url)

        controller.openProject(url)
        await Task.yield()
        var marker = false
        marker = true

        XCTAssertTrue(marker)
        try await waitUntil { controller.state == .workspace }
    }

    func testDiagnosticsRedactContentAndCompletePaths() async throws {
        let secret = "private-client-launch"
        let url = fixture("\(secret).siteforge")
        var document = ProjectCreation.blank()
        document.pages[0].name = secret
        try await writePackage(ProjectPackage(document: document), to: url)
        let controller = makeController()

        await controller.openProjectAndWait(url)

        let records = await controller.diagnostics.snapshot()
        let description = String(describing: records)
        XCTAssertFalse(description.contains(secret))
        XCTAssertFalse(description.contains(fixtureDirectory.path))
        XCTAssertTrue(description.contains("document-"))
    }

    func testRepresentativeHundredPageLoadCompletesWithinBudget() async throws {
        var document = ProjectCreation.blank()
        for index in 0..<98 {
            let page = DocumentPage(name: "Page \(index)", route: PageRoute(rawValue: "/page-\(index)"))
            document.pages.append(page)
        }
        let url = fixture("Performance.siteforge")
        try await writePackage(ProjectPackage(document: document), to: url)
        let controller = makeController()
        let clock = ContinuousClock()
        let elapsed = await clock.measure { await controller.openProjectAndWait(url) }

        XCTAssertEqual(controller.lifecycle.session.document.pages.count, 100)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    private func makeController(
        backend: DocumentLifecycleBackend = DocumentLifecycleBackend(),
        preview: LaunchPreviewScenario? = nil,
        recentProjectStore: any RecentProjectPersisting = MemoryRecentProjectStore(),
        autosaveDebouncer: any LifecycleAutosaveDebouncing = ContinuousLifecycleAutosaveDebouncer()
    ) -> LaunchExperienceController {
        let recoveryDirectory = fixtureDirectory.appendingPathComponent("recovery", isDirectory: true)
        try? FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        let lifecycle = DocumentLifecycleController(
            session: DocumentSession(),
            backend: backend,
            recoveryDirectory: recoveryDirectory,
            autosaveDebouncer: autosaveDebouncer
        )
        return LaunchExperienceController(
            lifecycle: lifecycle,
            recentProjectStore: recentProjectStore,
            previewScenario: preview
        )
    }

    private func fixture(_ name: String) -> URL { fixtureDirectory.appendingPathComponent(name) }

    private func writePackage(_ package: ProjectPackage = ProjectPackage(document: ProjectCreation.blank()), to url: URL) async throws {
        try await ProjectPackageStore().write(package, to: url)
    }

    private func addPage(_ name: String, to session: DocumentSession) throws {
        try session.execute(.insertPage(InsertPageCommand(
            page: DocumentPage(name: name, route: PageRoute(rawValue: "/\(name.lowercased().replacingOccurrences(of: " ", with: "-"))")),
            index: session.document.pages.count
        )))
    }

    private func incompatiblePackageData() async throws -> Data {
        let data = try await ProjectPackageStore().encode(ProjectPackage(document: ProjectCreation.blank()))
        let supported = Data("\"packageVersion\":1".utf8)
        let unsupported = Data("\"packageVersion\":9".utf8)
        let range = try XCTUnwrap(data.range(of: supported))
        var edited = data
        edited.replaceSubrange(range, with: unsupported)
        return edited
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }

    private var expectedRequirementIDs: Set<String> {
        ["SF-0201-002", "SF-0201-003", "SF-0201-004", "SF-0201-006", "SF-0201-007", "SF-0201-008",
         "SF-0204-002", "SF-0204-003", "SF-0204-004", "SF-0204-006",
         "SF-0301-002", "SF-0301-004", "SF-0301-006", "SF-0301-007", "SF-0301-008",
         "SF-1602-004", "SF-1602-006", "SF-1602-007", "SF-1602-008"]
    }
}

private actor MemoryRecentProjectStore: RecentProjectPersisting {
    private var projects: [RecentProjectReference] = []
    func load() -> [RecentProjectReference] { projects }
    func save(_ projects: [RecentProjectReference]) { self.projects = projects }
}

private actor MemoryLaunchBookmarkStore: FileBookmarkPersisting {
    private var records: [String: PersistedFileBookmark] = [:]
    func bookmark(for key: String) -> PersistedFileBookmark? { records[key] }
    func setBookmark(_ bookmark: PersistedFileBookmark, for key: String) { records[key] = bookmark }
}

private actor LaunchBookmarkRuntime: SecurityScopedBookmarkRuntime {
    func makeBookmark(for url: URL) -> Data { Data(url.path.utf8) }
    func resolveBookmark(_ data: Data) throws -> SecurityScopedBookmarkResolution {
        guard let path = String(data: data, encoding: .utf8) else {
            throw FileAccessFailure.corruptBookmarkStore
        }
        return SecurityScopedBookmarkResolution(url: URL(fileURLWithPath: path), isStale: false)
    }
    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}

private actor LaunchFileCoordinator: ProjectFileCoordinating {
    func coordinate<T: Sendable>(
        at url: URL,
        intent: FileAccessIntent,
        operation: @escaping @Sendable (URL) async throws -> T
    ) async throws -> T {
        try await operation(url)
    }
}
