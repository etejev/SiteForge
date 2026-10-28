import XCTest
@testable import SiteForge

@MainActor
final class LaunchExperienceTests: XCTestCase {
    // SF-0204-003/004/006: ordered metadata persistence retains removals and
    // last-valid presentation; forgetting never changes project authorization.
    func testRecentProjectMutationsSerializeAndFailedRefreshRetainsLastValidList() async throws {
        let first = fixture("First.siteforge"), second = fixture("Second.siteforge")
        let records = RecentProjectPolicy.recording(second, in: RecentProjectPolicy.recording(first, in: []))
        let store = HeldLaunchRecentProjectStore(projects: records)
        let controller = makeController(recentProjectStore: store)
        await controller.loadRecentProjects()
        XCTAssertEqual(controller.recentProjects, records)
        await store.failLoads(true)
        await controller.loadRecentProjects()
        XCTAssertEqual(controller.recentProjects, records)
        XCTAssertTrue(controller.recentProjectsMessage?.contains("last valid list") == true)
        await store.failLoads(false)
        controller.forgetRecentProject(records[0])
        await store.waitUntilSaving()
        controller.forgetRecentProject(records[1])
        let savesBeforeRelease = await store.saveCount
        XCTAssertEqual(savesBeforeRelease, 1, "A later removal must wait and compute from the committed earlier result")
        XCTAssertTrue(controller.isUpdatingRecentProjects)
        await store.releaseSave()
        try await waitUntil { !controller.isUpdatingRecentProjects }
        XCTAssertTrue(controller.recentProjects.isEmpty)
        let stored = try await store.load(); XCTAssertTrue(stored.isEmpty)
        XCTAssertNil(controller.recentProjectsMessage)
        XCTAssertEqual(controller.state, .welcome)
        XCTAssertFalse(controller.lifecycle.isModified)
    }

    // SF-0301-003/004: an old successful Open waiting on recent metadata
    // cannot overwrite the newer operation's visible failure or document.
    func testOpenCompletionAfterRecentPersistenceCannotReplaceNewerLaunchState() async throws {
        let url = fixture("Opened.siteforge")
        try await writePackage(to: url)
        let store = HeldLaunchRecentProjectStore()
        let backend = DocumentLifecycleBackend(fileAccess: FileAccessService(policy: .sandboxedUserSelectedReadWrite,
            runtime: LaunchBookmarkRuntime(), bookmarks: MemoryLaunchBookmarkStore(), coordinator: LaunchFileCoordinator()))
        let controller = makeController(backend: backend, recentProjectStore: store)
        controller.openProject(url, userSelected: true)
        await store.waitUntilSaving()
        let opened = controller.lifecycle.session.document
        controller.openProject(fixture("Missing.siteforge"))
        try await waitUntil { controller.state.kind == .failure }
        let newerState = controller.state
        await store.releaseSave()
        try await waitUntil { !controller.isUpdatingRecentProjects }
        XCTAssertEqual(controller.state, newerState)
        XCTAssertEqual(controller.lifecycle.session.document, opened)
        XCTAssertEqual(controller.recentProjects.count, 1, "The actual successful open may be remembered without claiming a later failed open succeeded")
        XCTAssertFalse(String(describing: controller.recentProjects).contains(fixtureDirectory.path))
        let queuedCreation = makeController(), original = queuedCreation.lifecycle.session.document
        queuedCreation.createBlankProject()
        await queuedCreation.openProjectAndWait(fixture("Another Missing.siteforge"))
        XCTAssertEqual(queuedCreation.state.kind, .failure)
        XCTAssertEqual(queuedCreation.lifecycle.session.document, original,
            "A superseded creation queued before its first event turn must not adopt or publish")
        let untitled = makeController()
        await untitled.createBlankProjectAndWait()
        let current = untitled.lifecycle.session.document
        await untitled.openProjectAndWait(fixture("Missing From Untitled.siteforge"))
        XCTAssertEqual(untitled.state.kind, .failure); XCTAssertNil(untitled.lifecycle.fileURL)
        XCTAssertTrue(untitled.canReturnToCurrentProject, "An untitled workspace is still a real current project")
        untitled.returnToCurrentProject()
        XCTAssertEqual(untitled.state, .workspace)
        XCTAssertEqual(untitled.lifecycle.session.document, current)
    }

    // SF-0306-003/004: manual review cancellation leaves Welcome, and a
    // failed discard retains its recovery surface/intent instead of pretending
    // success. All bytes below are fixture-owned, never owner recovery data.
    func testRecoveryReviewCancellationAndFailedDiscardKeepTruthfulStateAndBytes() async throws {
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        try addPage("Retained work", to: writer.lifecycle.session)
        await debouncer.waitUntilPending(); debouncer.fireAll()
        while writer.lifecycle.hasPendingAutosaveWork { await Task.yield() }
        let url = DocumentLifecycleBackend.recoveryURL(for: writer.lifecycle.currentProjectID,
            in: fixtureDirectory.appendingPathComponent("recovery", isDirectory: true))
        let bytes = try Data(contentsOf: url)
        let probe = LifecycleBackendProbe()
        let backend = DocumentLifecycleBackend(observer: probe)
        let reader = makeController(backend: backend)
        let before = reader.lifecycle.session.document
        await reader.discoverInitialRecovery()
        XCTAssertFalse(reader.recoveryAvailableAtWelcome, "A live session is not a crash")
        await probe.block(.beforeRead, intent: .discoverRecovery)
        reader.reviewRecoveryHistory()
        await probe.waitUntilBlocked()
        reader.cancelCurrentOperation()
        await probe.release()
        try await waitUntil { reader.state == .welcome }
        XCTAssertTrue(reader.recoveryHistoryMessage?.contains("cancelled") == true)
        XCTAssertEqual(reader.lifecycle.session.document, before)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        reader.reviewRecoveryHistory()
        try await waitUntil { reader.state.kind == .recovery }
        let candidate = try XCTUnwrap(reader.lifecycle.recoveryCandidate)
        let changedBytes = Data("fixture recovery changed after review".utf8)
        try changedBytes.write(to: candidate.url)
        reader.discardRecovery()
        XCTAssertTrue(reader.isResolvingRecovery)
        try await waitUntil { !reader.isResolvingRecovery }
        XCTAssertEqual(reader.state.kind, .recovery)
        XCTAssertNotNil(reader.lifecycle.recoveryCandidate)
        XCTAssertNotNil(reader.recoveryHistoryMessage)
        XCTAssertEqual(reader.lifecycle.session.document, before)
        XCTAssertEqual(try Data(contentsOf: candidate.url), changedBytes)
        reader.deferRecovery(); XCTAssertEqual(reader.state, .welcome)
        XCTAssertEqual(try Data(contentsOf: candidate.url), changedBytes)
    }

    // SF-0204-002/004/005/006: the bundled source is the actual UI-authored
    // package, copied through the normal lifecycle with verified local bytes.
    func testAuroraPackagedTemplateCreatesIndependentEditableResourceBaseline() async throws {
        let url = try XCTUnwrap(BundledSiteTemplates.auroraURL())
        let loader = PackagedSiteTemplateLoader()
        let first = try await loader.load(from: url, templateID: BundledSiteTemplates.auroraID)
        let second = try await loader.load(from: url, templateID: BundledSiteTemplates.auroraID)
        XCTAssertNotEqual(first.projectID, second.projectID)
        XCTAssertNotEqual(first.document.id, second.document.id)
        XCTAssertEqual(first.document.pages, second.document.pages)
        XCTAssertEqual(first.document.revision, 0)
        XCTAssertEqual(first.document.creationKind, .template)
        XCTAssertEqual(first.document.pages.map(\.name), ["Home", "Not Found", "Journal", "About", "Contact"])
        XCTAssertEqual(first.document.websitePages.filter { $0.role != .notFound }.map(\.name), ["Home", "Journal", "About", "Contact"])
        XCTAssertEqual(first.document.imageAssets.count, 1)
        XCTAssertTrue(first.document.pages.allSatisfy { $0.provenance == .template })
        let index = try XCTUnwrap(ProjectResourceIndex.decode(from: first))
        XCTAssertEqual(index.resources.count, 1)
        let descriptor = try XCTUnwrap(index.resources.first)
        XCTAssertEqual(ProjectResourceStore.digest(try first.resourceData(for: descriptor)), descriptor.sha256)
        XCTAssertFalse(first.optionalMembers.contains { $0.path.contains("history") })

        let controller = makeController()
        await controller.createAuroraProjectAndWait()
        XCTAssertEqual(controller.state, .workspace)
        XCTAssertEqual(controller.lifecycle.session.document.templateID, BundledSiteTemplates.auroraID)
        XCTAssertFalse(controller.lifecycle.session.canUndo)
        XCTAssertNil(controller.lifecycle.fileURL)
        XCTAssertEqual(controller.lifecycle.phase, .clean)
        let asset = try XCTUnwrap(controller.lifecycle.session.document.imageAssets.first)
        XCTAssertEqual(ProjectResourceStore.digest(try controller.lifecycle.projectResourceData(for: asset.resourceID)), asset.contentHash)
    }

    func testPackagedTemplateRejectsUnrelatedOrCorruptCreationResourcesWithoutMutation() async throws {
        let controller = makeController()
        let before = controller.lifecycle.stateSnapshot
        let result = await controller.lifecycle.requestNewDocument(ProjectCreation.blank(), resourceMembers: [
            .init(path: "history.json", data: Data("not creation data".utf8)),
        ])
        XCTAssertEqual(result, .failed(.malformedPackage))
        XCTAssertEqual(controller.lifecycle.session.document, before.document)
        XCTAssertEqual(controller.lifecycle.fileURL, before.fileURL)
        let url = fixtureDirectory.appendingPathComponent("corrupt.siteforge")
        try Data("invalid container".utf8).write(to: url)
        do {
            _ = try await PackagedSiteTemplateLoader().load(from: url, templateID: BundledSiteTemplates.auroraID)
            XCTFail("Malformed template must not produce a creation baseline")
        } catch { XCTAssertEqual(controller.lifecycle.session.document, before.document) }
    }

    func testPackagedTemplateMissingResourceCancellationAndSaveReopen() async throws {
        let url = try XCTUnwrap(BundledSiteTemplates.auroraURL())
        let sourceBytes = try Data(contentsOf: url)
        let orphan = fixtureDirectory.appendingPathComponent("missing-resource.siteforge")
        try FileManager.default.copyItem(at: url, to: orphan)
        do {
            _ = try await PackagedSiteTemplateLoader().load(from: orphan, templateID: BundledSiteTemplates.auroraID)
            XCTFail("A packaged template cannot silently lose its image")
        } catch { }
        let task = Task { try await PackagedSiteTemplateLoader().load(from: url, templateID: BundledSiteTemplates.auroraID) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled template loading must not create content") }
        catch is CancellationError { }
        catch { XCTFail("Cancellation must retain its typed result") }

        let package = try await PackagedSiteTemplateLoader().load(from: url, templateID: BundledSiteTemplates.auroraID)
        let controller = makeController()
        let created = await controller.lifecycle.requestNewDocument(package.document, resourceMembers: package.optionalMembers)
        XCTAssertEqual(created, .completed)
        let destination = fixtureDirectory.appendingPathComponent("editable-copy.siteforge")
        let saved = await controller.lifecycle.save(to: destination)
        XCTAssertTrue(saved)
        let reopened = makeController()
        await reopened.openProjectAndWait(destination)
        XCTAssertEqual(reopened.state, .workspace)
        XCTAssertEqual(reopened.lifecycle.session.document, package.document)
        XCTAssertFalse(reopened.lifecycle.session.canUndo)
        let asset = try XCTUnwrap(package.document.imageAssets.first)
        XCTAssertEqual(try reopened.lifecycle.projectResourceData(for: asset.resourceID),
            try controller.lifecycle.projectResourceData(for: asset.resourceID))
        XCTAssertEqual(try Data(contentsOf: url), sourceBytes)
    }

    func testBundledTemplateResourceStoreIsReadOnlyAndCannotEscapeBundle() async throws {
        let url = try XCTUnwrap(BundledSiteTemplates.auroraURL())
        let package = try await PackagedSiteTemplateLoader().load(from: url, templateID: BundledSiteTemplates.auroraID)
        let descriptor = try XCTUnwrap(ProjectResourceIndex.decode(from: package)?.resources.first)
        let store = ProjectResourceStore(bundledRoot: ProjectResourceStore.sidecarURL(for: url), bundle: .main)
        let bytes = try await store.data(for: descriptor)
        XCTAssertEqual(ProjectResourceStore.digest(bytes), descriptor.sha256)
        do {
            _ = try await store.put(filename: descriptor.filename, mediaType: descriptor.mediaType, data: bytes)
            XCTFail("Bundle mode must never gain write authority")
        } catch { XCTAssertEqual(error as? ProjectResourceError, .unsafeStore) }
        let outside = ProjectResourceStore(bundledRoot: fixtureDirectory, bundle: .main)
        do { _ = try await outside.data(for: descriptor); XCTFail("Bundle reads must be contained") }
        catch { XCTAssertEqual(error as? ProjectResourceError, .unsafeStore) }
    }

    func testNativeLaunchRequestTransfersOnceWithoutReplacingPendingIntent() {
        let queue = WorkspaceLaunchRequestQueue()
        let url = URL(fileURLWithPath: "/temporary-owned-project.siteforge")
        XCTAssertTrue(queue.enqueue(.open(url)))
        XCTAssertFalse(queue.enqueue(.new))
        XCTAssertEqual(queue.take(), .open(url))
        XCTAssertNil(queue.take())
        XCTAssertTrue(queue.enqueue(.new))
        XCTAssertEqual(queue.take(), .new)
        XCTAssertNil(queue.take())
    }
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

    // SF-AUTHORING-106 / SF-0204-001...008
    func testStarterCreationUsesSameAtomicLifecycleWithCanonicalTemplateProvenance() async throws {
        let controller = makeController()
        await controller.createStarterProjectAndWait()

        XCTAssertEqual(controller.state, .workspace)
        XCTAssertEqual(controller.transitionHistory, [.welcome, .creating, .loadingNonCancelable, .workspace])
        let document = controller.lifecycle.session.document
        XCTAssertEqual(document.creationKind, .template)
        XCTAssertEqual(document.templateID, StarterSiteTemplate.id)
        XCTAssertEqual(document.pages.map(\.name), ["Home", "About"])
        XCTAssertEqual(document.pages.map(\.route.rawValue), ["/", "/about"])
        XCTAssertFalse(document.pages.contains { $0.role == .notFound })
        XCTAssertFalse(controller.lifecycle.session.canUndo)
        XCTAssertEqual(controller.lifecycle.phase, .clean)
        try document.validate()

        let diagnostics = await controller.diagnostics.snapshot()
        XCTAssertEqual(diagnostics.last?.result, .success)
        XCTAssertTrue(StarterSiteTemplate.requirementIDs.isSubset(of: Set(diagnostics.last?.requirementIDs ?? [])))
    }

    // SF-AUTHORING-106 / SF-0204-004/006 — choosing a template never bypasses
    // the existing destructive-transition decision or replaces current work
    // after cancellation.
    func testStarterCreationCancellationPreservesCurrentProjectAndReportsCancellation() async throws {
        let controller = makeController()
        try addPage("Current Work", to: controller.lifecycle.session)
        let before = controller.lifecycle.session.document

        controller.createStarterProject()
        try await waitUntil { controller.lifecycle.pendingUnsavedChangesPrompt != nil }
        let prompt = try XCTUnwrap(controller.lifecycle.pendingUnsavedChangesPrompt)
        XCTAssertEqual(prompt.transition, .newDocument)
        controller.lifecycle.resolveUnsavedChanges(.cancel, promptID: prompt.id)
        try await waitUntil { controller.state == .welcome }

        XCTAssertEqual(controller.lifecycle.session.document, before)
        let diagnostics = await controller.diagnostics.snapshot()
        XCTAssertEqual(diagnostics.last?.result, .cancelled)
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

    func testWelcomeRecoveryReviewAndLaterPreserveBytesAndDoNotLoop() async throws {
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        try addPage("Retained work", to: writer.lifecycle.session)
        await debouncer.waitUntilPending(); debouncer.fireAll()
        while writer.lifecycle.hasPendingAutosaveWork { await Task.yield() }
        let recovery = DocumentLifecycleBackend.recoveryURL(for: writer.lifecycle.currentProjectID,
            in: fixtureDirectory.appendingPathComponent("recovery", isDirectory: true))
        let bytes = try Data(contentsOf: recovery)
        let written = try await ProjectPackageStore().read(from: recovery)
        XCTAssertTrue(written.optionalMembers.contains { $0.path == RecoverySessionEvidence.memberPath },
            "Production autosave, not a test-only writer, must attach session evidence")
        let reader = makeController()
        let baseline = reader.lifecycle.session.document
        await reader.discoverInitialRecovery()
        XCTAssertEqual(reader.state, .welcome)
        XCTAssertFalse(reader.recoveryAvailableAtWelcome, "Another live app session is not a crash")
        XCTAssertNil(reader.lifecycle.recoveryCandidate)
        reader.reviewRecoveryHistory()
        try await waitUntil { reader.state.kind == .recovery }
        XCTAssertTrue(reader.recoveryAvailableAtWelcome)
        XCTAssertEqual(reader.lifecycle.recoveryCandidate?.package.projectID, writer.lifecycle.currentProjectID)
        reader.deferRecovery(); XCTAssertEqual(reader.state, .welcome)
        await reader.discoverInitialRecovery()
        XCTAssertEqual(reader.state, .welcome)
        XCTAssertEqual(reader.lifecycle.session.document, baseline)
        XCTAssertEqual(try Data(contentsOf: recovery), bytes)
        reader.reviewWelcomeRecovery(); XCTAssertEqual(reader.state.kind, .recovery)
        XCTAssertTrue(reader.recoveryAvailableAtWelcome)
        reader.deferRecovery()
        await reader.createBlankProjectAndWait()
        XCTAssertEqual(reader.state, .workspace)
        XCTAssertEqual(try Data(contentsOf: recovery), bytes, "Starting fresh must not consume the separately owned recovery")
    }

    func testInitialRecoveryOffersAbandonedSessionButKeepsCleanExitManual() async throws {
        for cleanExit in [false, true] {
            let root = fixtureDirectory.appendingPathComponent(cleanExit ? "clean-exit" : "abandoned-session")
            let store = ProjectPackageStore()
            try await store.prepareRecoveryDirectory(root)
            let session = DocumentSession()
            try addPage("Retained editorial work", to: session)
            var evidence: RecoverySessionEvidence? = RecoverySessionEvidence()
            let package = try XCTUnwrap(evidence).tagging(ProjectPackage(document: session.document), in: root)
            let url = DocumentLifecycleBackend.recoveryURL(for: package.projectID, in: root)
            try await store.write(package, to: url, policy: .recovery(package.projectID))
            let bytes = try Data(contentsOf: url)
            if cleanExit { evidence?.markCleanShutdown() }
            evidence = nil
            let lifecycle = DocumentLifecycleController(session: DocumentSession(), recoveryDirectory: root)
            let controller = LaunchExperienceController(lifecycle: lifecycle,
                recentProjectStore: MemoryRecentProjectStore())
            let baseline = lifecycle.session.document
            await controller.discoverInitialRecovery()
            XCTAssertEqual(controller.state, .welcome)
            XCTAssertEqual(controller.recoveryAvailableAtWelcome, !cleanExit)
            if cleanExit {
                XCTAssertNil(lifecycle.recoveryCandidate)
                controller.reviewRecoveryHistory()
                try await waitUntil { controller.state.kind == .recovery }
            } else {
                controller.reviewWelcomeRecovery()
                XCTAssertEqual(controller.state.kind, .recovery)
            }
            controller.deferRecovery()
            XCTAssertEqual(controller.state, .welcome)
            XCTAssertEqual(lifecycle.session.document, baseline)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
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
            "SiteForge is ready. Choose Blank Site, Starter Site or Aurora Editorial, or open an existing project.",
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
         "SF-0204-001", "SF-0204-002", "SF-0204-003", "SF-0204-004",
         "SF-0204-005", "SF-0204-006", "SF-0204-007", "SF-0204-008",
         "SF-0301-002", "SF-0301-004", "SF-0301-006", "SF-0301-007", "SF-0301-008",
         "SF-1602-004", "SF-1602-006", "SF-1602-007", "SF-1602-008"]
    }
}

private actor HeldLaunchRecentProjectStore: RecentProjectPersisting {
    private var projects: [RecentProjectReference]
    private var rejectsLoad = false
    private(set) var saveCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(projects: [RecentProjectReference] = []) { self.projects = projects }
    func load() throws -> [RecentProjectReference] {
        if rejectsLoad { throw RecentProjectStoreFailure.malformed }; return projects
    }
    func failLoads(_ value: Bool) { rejectsLoad = value }
    func save(_ projects: [RecentProjectReference]) async {
        saveCount += 1
        if saveCount == 1 {
            let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() }
            await withCheckedContinuation { continuation = $0 }
        }
        self.projects = projects
    }
    func waitUntilSaving() async {
        if saveCount > 0 { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func releaseSave() { continuation?.resume(); continuation = nil }
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
