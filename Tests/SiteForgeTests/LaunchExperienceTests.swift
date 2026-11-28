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
    // SF-0204-002/004/005/006, SF-0508-001/004/005, SF-1101-003/004,
    // SF-1204-003/004, SF-0502-003/005, SF-0602-003/004, SF-0604-003/004:
    // the Aurora Flow showcase is reproducible through the ordinary command
    // vocabulary, validates, compiles offline with its one owned local runtime,
    // survives an ordinary save and loads through the shared packaged-template
    // creation path. Its saved bytes are attached for owner/Codex visual
    // review; this test never writes the fingerprinted Samples directory.
    func testAuroraFlowShowcaseRecipeBuildsCompilesSavesAndLoadsEditableTemplate() async throws {
        let package = try await AuroraFlowShowcaseRecipe.makePackage()
        let document = package.document
        try document.validate()
        XCTAssertEqual(document.creationKind, .template)
        XCTAssertEqual(document.templateID, BundledSiteTemplates.auroraFlowID)
        XCTAssertEqual(document.revision, 0)
        XCTAssertTrue(document.pages.allSatisfy { $0.provenance == .template })
        XCTAssertEqual(document.websitePages.filter { $0.role != .notFound }.map(\.name), ["Home", "About", "Contact"])
        XCTAssertEqual(document.websiteMetadata?.siteName, "Aurora Flow")
        XCTAssertEqual(document.websiteMetadata?.allowsIndexing, false)
        XCTAssertEqual(Set(document.colorTokens.map(\.name)), Set(AuroraFlowShowcaseRecipe.tokenNames))
        XCTAssertTrue(document.colorTokens.allSatisfy { $0.darkColor?.isValid == true },
            "Every showcase token needs an explicit, valid dark website variant")

        // One opt-in flowing gradient on the Home hero, on an eligible fill.
        let allNodes = document.pages.flatMap(\.nodes)
        let flows = allNodes.filter { (try? CanonicalFlowGradient.resolve($0)) != nil }
        XCTAssertEqual(flows.count, 1)
        let home = try XCTUnwrap(document.pages.first { $0.role == .home })
        let hero = try XCTUnwrap(flows.first)
        XCTAssertTrue(home.nodes.contains { $0.id == hero.id })
        XCTAssertNotNil(CanonicalFlowGradient.gradient(on: hero), CanonicalFlowGradient.unavailableReason)
        XCTAssertEqual(try CanonicalFlowGradient.resolve(hero), AuroraFlowShowcaseRecipe.heroFlow)

        // Glass header and cards with opaque fallbacks for both themes.
        for page in document.websitePages where page.role != .notFound {
            let glass = page.nodes.compactMap { try? CanonicalGlassSurface.resolve($0) }
            XCTAssertGreaterThanOrEqual(glass.count, 4, page.name)
            XCTAssertTrue(glass.allSatisfy { $0.fallback.alpha == 1 && $0.darkFallback?.alpha == 1 }, page.name)
        }

        // Every page keeps one Footer with About/Contact/QR groups; the QR is
        // a real decodable local image shared by content hash.
        let qrNodes = allNodes.filter { (try? CanonicalQRCode.resolve($0)) != nil }
        XCTAssertEqual(qrNodes.count, document.websitePages.count)
        XCTAssertTrue(qrNodes.allSatisfy { (try? CanonicalQRCode.resolve($0))?.payload == AuroraFlowShowcaseRecipe.exampleDestination })
        XCTAssertEqual(document.imageAssets.count, 1)
        let index = try XCTUnwrap(ProjectResourceIndex.decode(from: package))
        XCTAssertEqual(index.resources.count, 1)
        var descriptors: [ResourceID: ProjectResourceDescriptor] = [:], data: [ResourceID: Data] = [:]
        for descriptor in index.resources {
            let bytes = try package.resourceData(for: descriptor)
            try ProjectQRCodeVerifier.verify(bytes, payload: AuroraFlowShowcaseRecipe.exampleDestination)
            descriptors[descriptor.id] = descriptor; data[descriptor.id] = bytes
        }
        for page in document.websitePages {
            XCTAssertEqual(page.nodes.filter { CanonicalPageFlow.role($0) == .footer }.count, 1, page.name)
            XCTAssertEqual(page.nodes.filter { CanonicalPageFlow.role($0) == .header }.count, 1, page.name)
            for name in ["About Us", "Contact Us", "Scan to explore"] {
                XCTAssertEqual(page.nodes.filter { $0.name == name && $0.kind == .stack }.count, 1, page.name + " " + name)
            }
        }
        XCTAssertFalse(allNodes.contains { node in
            node.properties.contains { property in
                guard case .string(let value) = property.value else { return false }
                return value.contains("localhost") || value.contains("127.0.0.1")
            }
        }, "Showcase destinations must be reserved examples, never a temporary preview URL")

        // Responsive layout keeps content inside every supported page width.
        for page in document.websitePages {
            for (width, breakpoint) in [(1440.0, ResponsiveBreakpoint.desktop), (768, .tablet), (390, .mobile)] {
                let snapshot = ConnectedPageLayoutSnapshot(page: page, breakpoint: breakpoint, width: width,
                    availablePageIDs: Set(document.pages.map(\.id)))
                let expectedVisible = page.effectiveVisibleNodeIDs(breakpoint: breakpoint)
                // A collapsed Menu renders its control, not its retained inline links.
                let collapsedLinks = Set(page.nodes.compactMap {
                    CanonicalPageFlow.role($0) != nil
                        ? CanonicalPageFlow.navigation(owner: $0, page: page, document: document, breakpoint: breakpoint, width: width) : nil
                }.filter(\.usesHamburger).flatMap { $0.links.map(\.id) })
                for node in page.nodes where expectedVisible.contains(node.id) && !page.rootNodeIDs.contains(node.id) && !collapsedLinks.contains(node.id) {
                    XCTAssertTrue(snapshot.visibleIDs.contains(node.id), "Missing visible content: \(page.name) \(node.name) @\(width)")
                    let frame = try XCTUnwrap(snapshot.frames[node.id], "Missing frame: \(page.name) \(node.name) @\(width)")
                    XCTAssertGreaterThan(frame.size.width, 0, "\(page.name) \(node.name) @\(width)")
                    XCTAssertGreaterThanOrEqual(frame.origin.x, -0.5, "\(page.name) \(node.name) @\(width)")
                    XCTAssertLessThanOrEqual(frame.origin.x + frame.size.width, width + 0.5, "\(page.name) \(node.name) @\(width)")
                }
            }
        }

        // Offline output uses the shared compiler, local runtime and static fallback.
        let compilation = StaticBuildCompiler.compile(document: document, profileSelection: .init(profile: .development),
            resourceDescriptors: descriptors, resourceData: data)
        XCTAssertTrue(compilation.canWrite, compilation.redactedSummary + " Codes: " + compilation.findings.map(\.code).joined(separator: ", "))
        let files = try XCTUnwrap(compilation.plan?.files)
        XCTAssertTrue(files.contains { $0.path == "siteforge-effects.js" && $0.contents == DecorativeEffectRuntime.javascript })
        let homeHTML = try XCTUnwrap(files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(homeHTML.contains("data-siteforge-flow="))
        XCTAssertTrue(homeHTML.contains("<header")); XCTAssertTrue(homeHTML.contains("<footer"))
        XCTAssertTrue(homeHTML.contains("<h1"))
        XCTAssertFalse(files.contains { $0.contents.contains("<script src=\"http") }, "No remote runtime or CDN")
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(document)), document)

        // Ordinary save, then the shared loader establishes fresh editable copies.
        let controller = makeController()
        let created = await controller.lifecycle.requestNewDocument(document, resourceMembers: package.optionalMembers)
        XCTAssertEqual(created, .completed)
        let destination = fixtureDirectory.appendingPathComponent("AuroraFlow.siteforge")
        let saved = await controller.lifecycle.save(to: destination)
        XCTAssertTrue(saved)
        let loader = PackagedSiteTemplateLoader()
        let first = try await loader.load(from: destination, templateID: BundledSiteTemplates.auroraFlowID)
        let second = try await loader.load(from: destination, templateID: BundledSiteTemplates.auroraFlowID)
        XCTAssertNotEqual(first.document.id, second.document.id)
        XCTAssertEqual(first.document.pages, second.document.pages)
        XCTAssertEqual(first.document.pages.map(\.name), document.pages.map(\.name))
        XCTAssertEqual(first.document.colorTokens, document.colorTokens)
        XCTAssertEqual(first.document.imageAssets, document.imageAssets)
        XCTAssertEqual(first.document.templateID, BundledSiteTemplates.auroraFlowID)
        XCTAssertFalse(first.optionalMembers.contains { $0.path.contains("history") })

        // Reviewable sample bytes: the exact saved container and sidecar blobs.
        let container = XCTAttachment(data: try Data(contentsOf: destination), uniformTypeIdentifier: "public.data")
        container.name = "AuroraFlow.siteforge"; container.lifetime = .keepAlways; add(container)
        let sidecar = ProjectResourceStore.sidecarURL(for: destination)
        let blobs = FileManager.default.fileExists(atPath: sidecar.path)
            ? try FileManager.default.contentsOfDirectory(at: sidecar, includingPropertiesForKeys: nil) : []
        for blob in blobs.sorted(by: { $0.path < $1.path }) {
            let attachment = XCTAttachment(data: try Data(contentsOf: blob), uniformTypeIdentifier: "public.data")
            attachment.name = "AuroraFlow.siteforge.resources-v1/" + blob.lastPathComponent
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    // SF-0204-002/003/006: the Aurora Flow Start choice uses the same atomic
    // creation lifecycle. Until reviewed sample bytes are bundled, choosing it
    // fails visibly without mutating the current document; once bundled it
    // creates an independent editable template copy with a clean baseline.
    func testAuroraFlowStartChoiceUsesSharedLifecycleWhetherOrNotSampleIsBundled() async throws {
        let controller = makeController()
        let before = controller.lifecycle.stateSnapshot
        await controller.createAuroraFlowProjectAndWait()
        if BundledSiteTemplates.auroraFlowURL() != nil {
            XCTAssertEqual(controller.state, .workspace)
            XCTAssertEqual(controller.lifecycle.session.document.templateID, BundledSiteTemplates.auroraFlowID)
            XCTAssertEqual(controller.lifecycle.session.document.creationKind, .template)
            XCTAssertFalse(controller.lifecycle.session.canUndo)
            XCTAssertNil(controller.lifecycle.fileURL)
        } else {
            XCTAssertEqual(controller.state.kind, .failure)
            XCTAssertEqual(controller.lifecycle.session.document, before.document)
            XCTAssertEqual(controller.lifecycle.fileURL, before.fileURL)
        }
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
        XCTAssertNil(controller.lifecycle.fileURL)
        XCTAssertEqual(controller.lifecycle.statusText, "Not saved yet")
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


// SF-0204-002/004/005/006, SF-0508, SF-1101/SF-1103, SF-0502/SF-0602/SF-0604:
// reproducible Aurora Flow showcase construction. Every node, token, style,
// effect and Footer group goes through the ordinary command vocabulary on a
// normal DocumentSession: the insertion, Footer content, color token and
// decorative effect registries, plus validated property commands for layout,
// typography and fill values. The result is an in-memory template package;
// it never writes owner projects or the fingerprinted Samples directory.
// Copy is deliberately fictional and destinations are reserved examples.
@MainActor
enum AuroraFlowShowcaseRecipe {
    static let exampleDestination = "https://example.com"
    static let heroFlow = CanonicalFlowGradient(enabled: true, radius: 320, strength: 0.6, response: 9, returnSeconds: 1.1)
    static let tokenNames = ["Page background", "Surface", "Primary text", "Secondary text", "Glass tint", "Glass edge"]

    private struct Palette {
        let background: ColorTokenID, surface: ColorTokenID, primary: ColorTokenID
        let secondary: ColorTokenID, glass: ColorTokenID, edge: ColorTokenID
    }

    private struct PageCopy {
        let eyebrow: String, title: String, lead: String, action: String, target: CanonicalLinkTarget
        let section: String?, heading: String, intro: String, cards: [(String, String)]
    }

    private static let white = CanonicalSolidColor(red: 1, green: 1, blue: 1, alpha: 1)

    private static func color(_ hex: UInt32, alpha: Double = 1) -> CanonicalSolidColor {
        CanonicalSolidColor(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                            blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    static func makePackage() async throws -> ProjectPackage {
        let session = DocumentSession(document: ProjectCreation.blank())
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id, metadata: WebsiteMetadata(
            siteName: "Aurora Flow",
            defaultDescription: "A fictional studio website made with SiteForge. Every part of it is editable.",
            allowsIndexing: false))))
        let about = DocumentPage.minimum(name: "About", route: "/about", role: .standard, provenance: .authored)
        let contact = DocumentPage.minimum(name: "Contact", route: "/contact", role: .standard, provenance: .authored)
        try session.execute(.insertPage(.init(page: about, index: 1)))
        try session.execute(.insertPage(.init(page: contact, index: 2)))
        let palette = try Palette(
            background: token("Page background", color(0xF3F6FB), dark: color(0x090E18), session),
            surface: token("Surface", color(0xFFFFFF), dark: color(0x0E1524), session),
            primary: token("Primary text", color(0x0F1A2E), dark: color(0xEDF2FF), session),
            secondary: token("Secondary text", color(0x4B5870), dark: color(0xADB9D2), session),
            glass: token("Glass tint", color(0xFFFFFF, alpha: 0.72), dark: color(0x142038, alpha: 0.62), session),
            edge: token("Glass edge", color(0x0F1A2E, alpha: 0.10), dark: color(0xFFFFFF, alpha: 0.14), session))
        let homeID = try XCTUnwrap(session.document.pages.first { $0.role == .home }?.id)
        var resources: [PreparedImageImport] = []
        for pageID in session.document.pages.map(\.id) {
            resources += try await build(pageID: pageID, palette: palette, homeID: homeID, contactID: contact.id, session: session)
        }
        let authored = session.document
        let document = CanonicalDocument(creationKind: .template, templateID: BundledSiteTemplates.auroraFlowID,
            pages: authored.pages.map { page in var copy = page; copy.provenance = .template; return copy },
            guides: authored.guides, imageAssets: authored.imageAssets,
            colorTokens: authored.colorTokens, websiteMetadata: authored.websiteMetadata)
        try document.validate()
        var package = ProjectPackage(document: document)
        for resource in resources { package = try package.withResource(resource.descriptor, data: resource.data) }
        return package
    }

    private static func copy(for page: DocumentPage, homeID: PageID, contactID: PageID) -> PageCopy {
        switch page.role {
        case .home:
            return PageCopy(eyebrow: "AURORA / FLOW", title: "Make room for possibility.",
                lead: "A fictional studio for calm, thoughtful digital work. Move your pointer across this space to see the gradient flow.",
                action: "Start a conversation", target: .page(contactID), section: "What we value",
                heading: "Built around better possibilities.",
                intro: "Three ideas guide every project. Each card is an ordinary, editable SiteForge container.",
                cards: [("01 / Thoughtful", "Clear ideas, carefully shaped, with space for the details that matter."),
                        ("02 / Fluid", "Flexible layouts that feel at home on every screen size."),
                        ("03 / Yours", "A real editable website, ready to become something personal.")])
        case .notFound:
            return PageCopy(eyebrow: "404", title: "This page drifted away.",
                lead: "The page you were looking for isn’t here. Head back home to keep exploring.",
                action: "Return home", target: .page(homeID), section: nil, heading: "", intro: "", cards: [])
        default:
            if page.id == contactID {
                return PageCopy(eyebrow: "CONTACT", title: "Let’s make something meaningful.",
                    lead: "These details are placeholders. Replace them with your own before publishing.",
                    action: "Visit example.com", target: .external(exampleDestination), section: "Ways to reach us",
                    heading: "Say hello.", intro: "All contact details below are fictional examples.",
                    cards: [("Write", "hello@auroraflow.example"),
                            ("Visit", "100 Example Avenue, Suite 1, Example City"),
                            ("Follow", "Updates are shared on example.com.")])
            }
            return PageCopy(eyebrow: "ABOUT", title: "Small team. Expansive thinking.",
                lead: "Aurora Flow is an example studio. Its people, places and projects are fictional, so you can replace every word.",
                action: "Say hello", target: .page(contactID), section: "How we work",
                heading: "A practice built on care.", intro: "Swap these principles for your own story.",
                cards: [("Listen first", "Every project begins with questions, not assumptions."),
                        ("Design in the open", "Early sketches and honest feedback keep work moving."),
                        ("Leave room to grow", "Systems that stay simple as your website expands.")])
        }
    }

    private static func build(pageID: PageID, palette: Palette, homeID: PageID, contactID: PageID,
                              session: DocumentSession) async throws -> [PreparedImageImport] {
        let page = try XCTUnwrap(session.document.pages.first { $0.id == pageID })
        let text = copy(for: page, homeID: homeID, contactID: contactID)
        let root = try XCTUnwrap(page.rootNodeIDs.first)

        // Page background: one solid layer bound to a theme-aware token.
        try replaceFill(root, [.solid(color: color(0xF3F6FB))], pageID: pageID, session: session)
        try bind(palette.background, .fill, [root], pageID: pageID, session: session)

        // Glass navigation keeps the ordinary Header template and its
        // editable managed title/navigation; only appearance is authored.
        let header = try insertSection(pageID: pageID, template: .header, name: "Glass navigation", session: session)
        let headerPage = try Self.page(pageID, session)
        let headerNode = try XCTUnwrap(headerPage.nodes.first { $0.id == header })
        // Preserve default title provenance so the narrow-menu allocator can
        // shrink its width; an authored fixed mode intentionally disables that.
        for (key, mode) in [(CanonicalPageChrome.navigationKey, "fill")] {
            if let id = CanonicalPageChrome.reference(key, on: headerNode) {
                try set(id, [CanonicalSizingConstraints.prefix + "widthMode": .string(mode)], pageID: pageID, session: session)
            }
        }
        try replaceFill(header, [.solid(color: color(0xFFFFFF, alpha: 0.72))], pageID: pageID, session: session)
        try set(header, ["style.border": .string("none")], pageID: pageID, session: session)
        try bind(palette.glass, .fill, [header], pageID: pageID, session: session)
        try effect(.glass(glass(blur: 20)), on: [header], pageID: pageID, session: session)
        try colorText(under: header, token: palette.primary, literal: color(0x0F1A2E), pageID: pageID, session: session)

        // Hero: a literal three-stop gradient (never token-bound, so the
        // Flow eligibility rule holds). Only Home opts into the flowing effect.
        let isHome = page.role == .home
        let hero = try insertSection(pageID: pageID, template: nil,
            name: isHome ? "Flowing gradient hero" : page.name + " introduction", session: session)
        let angle: Double = isHome ? 125 : page.role == .notFound ? 200 : 155
        try replaceFill(hero, [.linearGradient(angleDegrees: angle, stops: [
            .init(id: .init(), position: 0, color: color(0x3B1A94)),
            .init(id: .init(), position: 0.55, color: color(0x1F3A7A)),
            .init(id: .init(), position: 1, color: color(0x05615C))])], pageID: pageID, session: session)
        try set(hero, sectionLayout, pageID: pageID, session: session)
        if isHome { try effect(.flow(heroFlow), on: [hero], pageID: pageID, session: session) }
        let heroContent = stack("Hero content", parent: hero, gap: 22, padding: 88, tablet: 56, mobile: 28)
        let heroNodes = [
            textNode(text.eyebrow, parent: heroContent.id, size: 13, lineHeight: 18, weight: .semibold, tracking: 2,
                     color: color(0xFFFFFF, alpha: 0.78)),
            textNode(text.title, parent: heroContent.id, size: isHome ? 64 : 52, lineHeight: isHome ? 70 : 58,
                     weight: .semibold, element: .h1, color: white),
            textNode(text.lead, parent: heroContent.id, size: 20, lineHeight: 30, color: color(0xFFFFFF, alpha: 0.86)),
            linkNode(text.action, target: text.target, parent: heroContent.id, width: 260, color: white),
        ]
        try insert(heroContent, children: heroNodes, under: hero, pageID: pageID, session: session)

        // Responsive glass cards in an ordinary Grid (3 / 2 / 1 columns).
        if let sectionName = text.section {
            let section = try insertSection(pageID: pageID, template: nil, name: sectionName, session: session)
            try replaceFill(section, [], pageID: pageID, session: session)
            try set(section, sectionLayout, pageID: pageID, session: session)
            let body = stack(sectionName + " content", parent: section, gap: 28, padding: 88, tablet: 56, mobile: 28)
            let heading = textNode(text.heading, parent: body.id, size: 36, lineHeight: 44, weight: .semibold,
                                   element: .h2, color: color(0x0F1A2E))
            let intro = textNode(text.intro, parent: body.id, size: 18, lineHeight: 28, color: color(0x4B5870))
            let grid = gridNode("Responsive glass cards", parent: body.id)
            try insert(body, children: [heading, intro, grid], under: section, pageID: pageID, session: session)
            var cards: [NodeID] = [], titles: [NodeID] = [heading.id], details: [NodeID] = [intro.id]
            for (title, detail) in text.cards {
                let card = cardNode(title, parent: grid.id)
                let cardTitle = textNode(title, parent: card.id, size: 22, lineHeight: 28, weight: .semibold,
                                         element: .h3, color: color(0x0F1A2E))
                let cardDetail = textNode(detail, parent: card.id, size: 17, lineHeight: 26, color: color(0x4B5870))
                try insert(card, children: [cardTitle, cardDetail], under: grid.id, pageID: pageID, session: session)
                cards.append(card.id); titles.append(cardTitle.id); details.append(cardDetail.id)
            }
            try bind(palette.glass, .fill, cards, pageID: pageID, session: session)
            try bind(palette.edge, .border, cards, pageID: pageID, session: session)
            try effect(.glass(glass(blur: 18)), on: cards, pageID: pageID, session: session)
            try bind(palette.primary, .textForeground, titles, pageID: pageID, session: session)
            try bind(palette.secondary, .textForeground, details, pageID: pageID, session: session)
        }

        // Footer: ordinary About / Contact / QR groups under the one Footer anchor.
        let footer = try insertSection(pageID: pageID, template: .footer, name: "Flexible site footer", session: session)
        let worker = FooterContentWorker()
        var resources: [PreparedImageImport] = []
        let first = try await worker.prepare(preset: .about, footerID: footer, selectedGridID: nil,
            createColumnsConfirmed: true, document: session.document, pageID: pageID, payload: "")
        try session.execute(first.command)
        for preset in [FooterGroupPreset.contact, .qr] {
            let next = try await worker.prepare(preset: preset, footerID: footer, selectedGridID: first.columnsID,
                createColumnsConfirmed: false, document: session.document, pageID: pageID,
                payload: preset == .qr ? exampleDestination : "")
            try session.execute(next.command)
            if let resource = next.resource { resources.append(resource) }
            if preset == .contact {
                let current = try XCTUnwrap(session.document.pages.first { $0.id == pageID })
                if let detail = current.nodes.first(where: { $0.parent == .node(next.groupID) && $0.kind == .text
                    && $0.insertionStringProperty("content.text") == "Add your contact details" }) {
                    try set(detail.id, ["content.text": .string("hello@auroraflow.example · 100 Example Avenue, Example City")],
                            pageID: pageID, session: session)
                }
            }
        }
        try replaceFill(footer, [.solid(color: color(0xFFFFFF))], pageID: pageID, session: session)
        try set(footer, ["style.border": .string("none")], pageID: pageID, session: session)
        try bind(palette.surface, .fill, [footer], pageID: pageID, session: session)
        try colorText(under: footer, token: palette.primary, literal: color(0x0F1A2E), pageID: pageID, session: session)
        return resources
    }

    // MARK: Ordinary command helpers

    private static var sectionLayout: [String: PropertyValue] {
        ["layout.padding": .number(0), "style.border": .string("none"),
         CanonicalSizingConstraints.prefix + "heightMode": .string("hug")]
    }

    private static func glass(blur: Double) -> CanonicalGlassSurface {
        CanonicalGlassSurface(blur: blur, fallback: color(0xF7F9FD), darkFallback: color(0x101A2C))
    }

    private static func token(_ name: String, _ light: CanonicalSolidColor, dark: CanonicalSolidColor,
                              _ session: DocumentSession) throws -> ColorTokenID {
        var document = session.document
        try session.execute(LocalColorTokenCommandRegistry.prepare(.create(name: name, color: light), in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision, pageID: nil))
        let id = try XCTUnwrap(session.document.colorTokens.first { $0.name == name }?.id)
        document = session.document
        try session.execute(LocalColorTokenCommandRegistry.prepare(.darkVariant(id, dark), in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision, pageID: nil))
        return id
    }

    private static func page(_ pageID: PageID, _ session: DocumentSession) throws -> DocumentPage {
        try XCTUnwrap(session.document.pages.first { $0.id == pageID })
    }

    private static func insertSection(pageID: PageID, template: AuthoringElementTemplate?, name: String,
                                      session: DocumentSession) throws -> NodeID {
        let document = session.document, owner = try page(pageID, session)
        let root = try XCTUnwrap(owner.rootNodeIDs.first), id = NodeID()
        let identity = InsertionOperationIdentity(documentID: document.id, pageID: pageID,
                                                  revision: document.revision, generation: 1)
        let command = AuthoringInsertionCommand.container(.init(kind: .section, identity: identity, nodeID: id,
            parentID: root, index: owner.nodes.first { $0.id == root }?.childIDs.count ?? 0,
            geometry: .init(origin: .init(x: 0, y: 0), size: template?.size ?? .init(width: 960, height: 320)),
            provenance: .menu))
        let context = InsertionValidationContext(activePageID: pageID, activeRoute: owner.route,
            operationGeneration: 1, availableNodeIDs: Set(owner.nodes.map(\.id)))
        let prepared = try InsertionCommandRegistry().prepare(command, in: document, context: context, template: template)
        try session.execute(renaming(prepared.documentCommand, nodeID: id, to: name))
        return id
    }

    private static func renaming(_ command: DocumentCommand, nodeID: NodeID, to name: String) -> DocumentCommand {
        switch command {
        case .insertNode(let insertion) where insertion.node.id == nodeID:
            var node = insertion.node
            node.name = name
            return .insertNode(.init(pageID: insertion.pageID, node: node, index: insertion.index,
                                     storageIndex: insertion.storageIndex))
        case .batch(let commands):
            return .batch(commands.map { renaming($0, nodeID: nodeID, to: name) })
        default:
            return command
        }
    }

    /// Inserts one container and its direct children as a single batch.
    private static func insert(_ container: DocumentNode, children: [DocumentNode], under parent: NodeID,
                               pageID: PageID, session: DocumentSession) throws {
        let owner = try page(pageID, session)
        let index = owner.nodes.first { $0.id == parent }?.childIDs.count ?? 0
        var commands: [DocumentCommand] = [.insertNode(.init(pageID: pageID, node: container, index: index))]
        for (offset, child) in children.enumerated() {
            commands.append(.insertNode(.init(pageID: pageID, node: child, index: offset)))
        }
        try session.execute(.batch(commands))
    }

    private static func set(_ id: NodeID, _ values: [String: PropertyValue], pageID: PageID,
                            session: DocumentSession) throws {
        let node = try XCTUnwrap(try page(pageID, session).nodes.first { $0.id == id })
        let commands: [DocumentCommand] = values.keys.sorted().compactMap { key -> DocumentCommand? in
            guard let value = values[key] else { return nil }
            let old = node.insertionProperty(key)
            guard old?.value != value || old?.origin != .authored else { return nil }
            return .setProperty(.init(pageID: pageID, nodeID: id, property: .init(id: old?.id ?? PropertyID(),
                key: .init(rawValue: key), value: value, origin: .authored)))
        }
        if !commands.isEmpty { try session.execute(.batch(commands)) }
    }

    /// Replaces the closed fill-layer namespace, removing stale owned keys.
    private static func replaceFill(_ id: NodeID, _ layers: [CanonicalFillLayer], pageID: PageID,
                                    session: DocumentSession) throws {
        let node = try XCTUnwrap(try page(pageID, session).nodes.first { $0.id == id })
        let commands = DecorativeEffectPropertyCommands.replace(namespace: CanonicalFillLayerCodec.namespaceRoot,
            values: CanonicalFillLayerCodec.propertyValues(for: layers), node: node, pageID: pageID)
        if !commands.isEmpty { try session.execute(.batch(commands)) }
    }

    private static func bind(_ token: ColorTokenID, _ target: LocalColorTarget, _ ids: [NodeID], pageID: PageID,
                             session: DocumentSession) throws {
        guard !ids.isEmpty else { return }
        let document = session.document
        try session.execute(LocalColorTokenCommandRegistry.prepare(.bindTarget(token, target), in: document,
            expectedDocumentID: document.id, expectedRevision: document.revision, pageID: pageID, selectedNodeIDs: ids))
    }

    private static func effect(_ edit: DecorativeEffectEdit, on ids: [NodeID], pageID: PageID,
                               session: DocumentSession) throws {
        let document = session.document, owner = try page(pageID, session), scene = CanvasViewportSceneID()
        let prepared = try DecorativeEffectCommandRegistry.prepare(edit,
            identity: .init(documentID: document.id, pageID: pageID, revision: document.revision,
                            sceneID: scene, rendererGeneration: document.revision),
            orderedNodeIDs: ids, document: document,
            context: .init(activePageID: pageID, currentSceneID: scene, rendererGeneration: document.revision,
                           selectedNodeIDs: ids, availableNodeIDs: Set(owner.nodes.map(\.id)),
                           isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        try session.execute(prepared.documentCommand)
    }

    /// Gives every textual descendant an explicit literal, then binds the token.
    private static func colorText(under root: NodeID, token: ColorTokenID, literal: CanonicalSolidColor,
                                  pageID: PageID, session: DocumentSession) throws {
        let owner = try page(pageID, session)
        let byID = Dictionary(uniqueKeysWithValues: owner.nodes.map { ($0.id, $0) })
        var pending = [root], visited = Set<NodeID>(), textual: [NodeID] = []
        while let id = pending.popLast() {
            guard visited.insert(id).inserted, let node = byID[id] else { continue }
            if node.kind.isTextual { textual.append(id) }
            pending.append(contentsOf: node.childIDs)
        }
        for id in textual where byID[id].flatMap(CanonicalTextForeground.literal(for:)) == nil {
            try set(id, Dictionary(uniqueKeysWithValues: CanonicalTextForeground.values(literal)), pageID: pageID, session: session)
        }
        try bind(token, .textForeground, textual, pageID: pageID, session: session)
    }

    // MARK: Ordinary node values (the same canonical keys Footer content uses)

    private static func node(_ kind: NodeKind, _ name: String, parent: NodeID,
                             _ values: [String: PropertyValue]) -> DocumentNode {
        DocumentNode(kind: kind, name: name, parent: .node(parent), properties: values.sorted { $0.key < $1.key }
            .map { NodeProperty(key: .init(rawValue: $0.key), value: $0.value, origin: .authored) })
    }

    private static func geometry(width: Double, height: Double) -> [String: PropertyValue] {
        ["layout.x": .number(0), "layout.y": .number(0), "layout.width": .number(width), "layout.height": .number(height)]
    }

    private static func containerValues(kind: String, gap: Double, padding: Double, tablet: Double,
                                        mobile: Double) -> [String: PropertyValue] {
        var values = geometry(width: 960, height: 200)
        values["layout.container.kind"] = .string(kind)
        values["layout.gap"] = .number(gap)
        values["layout.padding"] = .number(padding)
        values[ResponsiveContainerLayoutResolver.key(.padding, breakpoint: .tablet)] = .number(tablet)
        values[ResponsiveContainerLayoutResolver.key(.padding, breakpoint: .mobile)] = .number(mobile)
        values[CanonicalSizingConstraints.prefix + "widthMode"] = .string("fill")
        values[CanonicalSizingConstraints.prefix + "heightMode"] = .string("hug")
        return values
    }

    private static func stack(_ name: String, parent: NodeID, gap: Double, padding: Double, tablet: Double,
                              mobile: Double) -> DocumentNode {
        var values = containerValues(kind: "stack", gap: gap, padding: padding, tablet: tablet, mobile: mobile)
        values["layout.axis"] = .string("vertical")
        values["layout.align"] = .string("start")
        values[CanonicalFillLayerCodec.orderKey] = .string("")
        values["style.border"] = .string("none")
        return node(.stack, name, parent: parent, values)
    }

    private static func gridNode(_ name: String, parent: NodeID) -> DocumentNode {
        var values = containerValues(kind: "grid", gap: 24, padding: 0, tablet: 0, mobile: 0)
        values["layout.grid.columns"] = .number(3)
        values["layout.grid.placement"] = .string("row-major")
        values[ResponsiveContainerLayoutResolver.key(.columns, breakpoint: .tablet)] = .number(2)
        values[ResponsiveContainerLayoutResolver.key(.columns, breakpoint: .mobile)] = .number(1)
        values[ResponsiveContainerLayoutResolver.key(.gap, breakpoint: .mobile)] = .number(16)
        values[CanonicalFillLayerCodec.orderKey] = .string("")
        values["style.border"] = .string("none")
        return node(.grid, name, parent: parent, values)
    }

    /// Card: an ordinary vertical Stack with a solid fill (bound to Glass
    /// tint afterwards), a typed border (bound to Glass edge) and radius.
    private static func cardNode(_ name: String, parent: NodeID) -> DocumentNode {
        var values = containerValues(kind: "stack", gap: 12, padding: 28, tablet: 24, mobile: 20)
        values["layout.axis"] = .string("vertical")
        values["layout.align"] = .string("start")
        for (key, value) in CanonicalFillLayerCodec.propertyValues(for: [.solid(color: color(0xFFFFFF, alpha: 0.72))]) {
            values[key] = value
        }
        let box = DesignBoxStyleCommandRegistry.namespace
        values[box + "radius.uniform"] = .number(24)
        values[box + "border.width"] = .number(1)
        values[box + "border.style"] = .string(CanonicalBorderStyle.solid.rawValue)
        let edge = color(0x0F1A2E, alpha: 0.10)
        for (channel, value) in [("red", edge.red), ("green", edge.green), ("blue", edge.blue), ("alpha", edge.alpha)] {
            values[box + "border.color." + channel] = .number(value)
        }
        return node(.stack, name, parent: parent, values)
    }

    private static func textNode(_ copy: String, parent: NodeID, size: Double, lineHeight: Double,
                                 weight: CanonicalFontWeight = .regular, element: SemanticHTMLElement? = nil,
                                 tracking: Double = 0, color: CanonicalSolidColor) -> DocumentNode {
        var values = geometry(width: 960, height: lineHeight)
        values["content.text"] = .string(copy)
        values[CanonicalSizingConstraints.prefix + "widthMode"] = .string("fill")
        values[CanonicalSizingConstraints.prefix + "heightMode"] = .string("hug")
        values[CanonicalTypography.namespace + "size"] = .number(size)
        values[CanonicalTypography.namespace + "lineHeight"] = .number(lineHeight)
        values[CanonicalTypography.namespace + "weight"] = .string(weight.rawValue)
        if tracking != 0 { values[CanonicalTypography.namespace + "tracking"] = .number(tracking) }
        if let element { values[CanonicalSemanticElement.key] = .string(element.rawValue) }
        for (key, value) in CanonicalTextForeground.values(color) { values[key] = value }
        return node(.text, String(copy.prefix(48)), parent: parent, values)
    }

    private static func linkNode(_ label: String, target: CanonicalLinkTarget, parent: NodeID, width: Double,
                                 color: CanonicalSolidColor) -> DocumentNode {
        var values = geometry(width: width, height: 28)
        values[CanonicalLinkTarget.labelKey] = .string(label)
        for (key, value) in target.properties { values[key] = value }
        values[CanonicalSizingConstraints.prefix + "heightMode"] = .string("hug")
        values[CanonicalTypography.namespace + "size"] = .number(17)
        values[CanonicalTypography.namespace + "lineHeight"] = .number(26)
        values[CanonicalTypography.namespace + "weight"] = .string(CanonicalFontWeight.semibold.rawValue)
        for (key, value) in CanonicalTextForeground.values(color) { values[key] = value }
        return node(.link, label, parent: parent, values)
    }
}
