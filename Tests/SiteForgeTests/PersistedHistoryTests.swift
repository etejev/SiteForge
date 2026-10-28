import XCTest
@testable import SiteForge

@MainActor
final class PersistedHistoryTests: XCTestCase {
    // SF-SOURCE-BATCH-20261027-01, SF-1207-003/005: unrun source coverage.
    func testSiteSetupPageIndexingResetPreservesOtherOverridesAndExactHistory() throws {
        var document = CanonicalDocument()
        let page = document.pages[0], other = document.pages[1]
        let metadata = WebsiteMetadata(siteName: "Local Studio", titlePattern: "{page} | {site}",
            defaultDescription: "Site description", allowsIndexing: true, pages: [
                .init(pageID: page.id, title: "Page title", description: "Page description", allowsIndexing: false),
                .init(pageID: other.id, title: "Other title", allowsIndexing: false)
            ])
        document.websiteMetadata = metadata
        let reset = metadata.replacingPageOverride(.init(pageID: page.id))
        XCTAssertFalse(reset.pages.contains { $0.pageID == page.id })
        XCTAssertEqual(reset.pages.first { $0.pageID == other.id }, metadata.pages.first { $0.pageID == other.id })
        let scene = CanvasViewportSceneID()
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [], availableNodeIDs: [],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: page.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        let session = DocumentSession(document: document)
        try session.execute(WebsiteMetadataCommandRegistry().prepare(reset, identity: identity, document: document, context: context))
        let resolved = WebsiteMetadataResolver.resolve(page: page, document: session.document)
        XCTAssertEqual(resolved.title, "\(page.name) | Local Studio")
        XCTAssertEqual(resolved.titleSource, .inherited)
        XCTAssertEqual(resolved.description, "Site description")
        XCTAssertTrue(resolved.allowsIndexing)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        try session.undo()
        XCTAssertEqual(session.document.websiteMetadata, metadata)
        try session.redo()
        XCTAssertEqual(session.document.websiteMetadata, reset)
        XCTAssertTrue(WebsiteMetadata().replacingPageOverride(.init(pageID: page.id)).isEmpty,
                      "Default settings must not create an empty page override")
    }

    // Route/rename are existing Page commands, not a second metadata authority.
    func testSiteSetupRouteRenamePreservesPageMetadataAndLinkIntentInOutput() throws {
        let session = DocumentSession()
        let registry = PageCommandRegistry()
        @MainActor func edit(_ value: PageEdit, pageID: PageID) throws {
            let command = try registry.prepare(value, identity: .init(documentID: session.document.id,
                revision: session.document.revision, pageID: pageID), in: session.document, isAvailable: true)
            try session.execute(command.command)
        }
        let home = session.document.pages[0].id
        try edit(.create(name: "About", route: "/about"), pageID: home)
        let target = try XCTUnwrap(session.document.pages.last)
        let rootID = session.document.pages[0].rootNodeIDs[0]
        let link = DocumentNode(kind: .link, name: "Authored navigation label", parent: .node(rootID), properties:
            CanonicalLinkTarget.page(target.id).properties.map { .init(key: .init(rawValue: $0.0), value: $0.1) }
            + [.init(key: .init(rawValue: CanonicalLinkTarget.labelKey), value: .string("Meet the team"))])
        try session.execute(.insertNode(.init(pageID: home, node: link, index: 0)))
        let metadata = WebsiteMetadata(siteName: "Studio", titlePattern: "{page} | {site}",
            defaultDescription: "A \"local\" <description>", pages: [.init(pageID: target.id, allowsIndexing: false)])
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id, metadata: metadata)))
        try edit(.rename("Team"), pageID: target.id)
        try edit(.route("/team"), pageID: target.id)
        let snapshot = session.document
        let sameLink = try XCTUnwrap(snapshot.pages[0].nodes.first { $0.id == link.id })
        XCTAssertEqual(try CanonicalLinkTarget.resolve(sameLink), .page(target.id))
        XCTAssertEqual(sameLink.controlLabel, "Meet the team")
        XCTAssertEqual(snapshot.websiteMetadata, metadata)
        let plan = try MultiPageStaticBuildPlanner.plan(document: snapshot)
        let markup = try XCTUnwrap(plan.files.first { $0.path == "team.html" }?.contents)
        XCTAssertTrue(markup.contains("<title>Team | Studio</title>"))
        XCTAssertTrue(markup.contains("noindex, follow"))
        XCTAssertTrue(markup.contains("&quot;local&quot; &lt;description>"))
        XCTAssertEqual(session.document, snapshot, "Output planning is immutable")
        XCTAssertThrowsError(try registry.prepare(.route("/"), identity: .init(documentID: snapshot.id,
            revision: snapshot.revision, pageID: target.id), in: snapshot, isAvailable: true))
        try session.undo()
        XCTAssertEqual(session.document.pages.first { $0.id == target.id }?.route.rawValue, "/about")
        XCTAssertEqual(session.document.websiteMetadata, metadata)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
    }

    func testResponsiveSizingSaveReopenRecoveryPreservesComponentOverridesAndPageIdentity() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "schema-v7-linked-text-document", withExtension: "json", subdirectory: "Legacy"))
        let session = DocumentSession(document: try DocumentSerializer.decode(Data(contentsOf: fixture)))
        let page = session.document.websitePages[0], definition = session.document.componentDefinitions[0]
        let scene = CanvasViewportSceneID()
        func identity(_ pageID: PageID) -> GeometryInspectorOperationIdentity {
            .init(editID: GeometryInspectorEditID(), documentID: session.document.id, pageID: pageID,
                revision: session.document.revision, sceneID: scene, rendererGeneration: session.document.revision)
        }
        func context(_ pageID: PageID, selected: NodeID) -> TransformValidationContext {
            .init(activePageID: pageID, currentSceneID: scene, rendererGeneration: session.document.revision,
                selectedNodeIDs: [selected], availableNodeIDs: Set(session.document.pages.flatMap(\.nodes).map(\.id)),
                isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        }
        let textID = definition.nodes[1].id, instanceID = page.nodes[1].id
        try session.execute(ComponentCommandRegistry().prepare(.exposeText(nodeID: textID, label: "Title", defaultValue: "Shared"),
            identity: .init(documentID: session.document.id, pageID: definition.id, revision: session.document.revision,
                sceneID: scene, rendererGeneration: session.document.revision), in: session.document,
            context: context(definition.id, selected: textID)).command)
        let binding = try XCTUnwrap(CanonicalComponentText.property(on: session.document.componentDefinitions[0].nodes[1]))
        try session.execute(ComponentCommandRegistry().prepare(.setTextOverride(instanceID: instanceID, propertyID: binding.id, value: "Independent"),
            identity: .init(documentID: session.document.id, pageID: page.id, revision: session.document.revision,
                sceneID: scene, rendererGeneration: session.document.revision), in: session.document,
            context: context(page.id, selected: instanceID)).command)
        func geometry() -> [NodeProperty] {
            [("layout.x", 20.0), ("layout.y", 20.0), ("layout.width", 300.0), ("layout.height", 200.0)].map {
                .init(key: .init(rawValue: $0.0), value: .number($0.1), origin: .authored)
            }
        }
        let frame = DocumentNode(kind: .frame, name: "Responsive region", parent: .node(page.rootNodeIDs[0]), properties: geometry())
        try session.execute(.insertNode(.init(pageID: page.id, node: frame, index: 2)))
        let copy = DocumentNode(kind: .text, name: "Responsive copy", parent: .node(frame.id), properties: geometry() + [
            .init(key: .init(rawValue: "content.text"), value: .string("Responsive content"))])
        try session.execute(.insertNode(.init(pageID: page.id, node: copy, index: 0)))
        for edit in [SizingConstraintEdit.setMode(.width, .fill), .setMode(.height, .hug)] {
            try session.execute(SizingConstraintCommandRegistry().prepare(.init(identity: identity(page.id), orderedNodeIDs: [frame.id],
                edit: edit, cancelled: false), in: session.document, context: context(page.id, selected: frame.id)).documentCommand)
        }
        let durable = session.document, debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = DocumentLifecycleController(session: session,
            recoveryDirectory: fixtureDirectory.appendingPathComponent("recovery", isDirectory: true), autosaveDebouncer: debouncer)
        let url = fixtureDirectory.appendingPathComponent("ResponsiveComponents.siteforge")
        let saved = await writer.save(to: url); XCTAssertTrue(saved)
        let reader = makeController()
        let opened = await reader.requestOpen(url); XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document, durable)
        try reader.session.undo()
        XCTAssertNil(reader.session.document.pages[0].nodes.first { $0.id == frame.id }?.insertionProperty(CanonicalSizingConstraints.prefix + "heightMode"))
        try reader.session.redo(); XCTAssertEqual(reader.session.document.pages, durable.pages)
        let override = try GeometryInspectorCommandRegistry().prepare(.init(identity: identity(page.id), orderedNodeIDs: [frame.id],
            field: .width, value: 180, provenance: .keyboard, breakpoint: .mobile), in: session.document,
            context: context(page.id, selected: frame.id))
        try session.execute(override.documentCommand)
        await flushAutosave(writer, with: debouncer)
        let recovered = makeController()
        let recoveryOpen = await recovered.requestOpen(url); XCTAssertEqual(recoveryOpen, .completed)
        let restored = await recovered.requestRestoreRecovery(); XCTAssertEqual(restored, .completed)
        XCTAssertEqual(recovered.session.document.pages, session.document.pages)
        XCTAssertEqual(recovered.session.document.websitePages.map(\.id), durable.websitePages.map(\.id))
        XCTAssertEqual(recovered.session.document.websitePages.map(\.route), durable.websitePages.map(\.route))
        XCTAssertEqual(CanonicalComponentText.overrides(on: recovered.session.document.pages[0].nodes[1])[binding.id], "Independent")
        try recovered.session.undo(); XCTAssertEqual(recovered.session.document.pages, durable.pages)
        try recovered.session.redo(); XCTAssertEqual(recovered.session.document.pages, session.document.pages)
    }

    func testComponentReuseSaveReopenRecoveryAndExactResetHistory() async throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "schema-v7-linked-text-document",
            withExtension: "json", subdirectory: "Legacy"))
        let document = try DocumentSerializer.decode(Data(contentsOf: fixture))
        let session = DocumentSession(document: document), definition = document.componentDefinitions[0]
        let text = definition.nodes[1], page = document.websitePages[0], first = page.nodes[1].id, second = page.nodes[2].id
        func apply(_ edit: ComponentEdit, pageID: PageID, target: NodeID) throws {
            let scene = CanvasViewportSceneID(), current = session.document
            let prepared = try ComponentCommandRegistry().prepare(edit,
                identity: .init(documentID: current.id, pageID: pageID, revision: current.revision,
                    sceneID: scene, rendererGeneration: current.revision), in: current,
                context: .init(activePageID: pageID, currentSceneID: scene, rendererGeneration: current.revision,
                    selectedNodeIDs: [target], availableNodeIDs: [target], isLifecycleAvailable: true, lifecycleDisabledReason: nil))
            try session.execute(prepared.command)
        }
        try apply(.exposeText(nodeID: text.id, label: "Title", defaultValue: "Shared"), pageID: definition.id, target: text.id)
        let binding = try XCTUnwrap(CanonicalComponentText.property(on: session.document.componentDefinitions[0].nodes[1]))
        try apply(.setTextOverride(instanceID: first, propertyID: binding.id, value: "Independent"), pageID: page.id, target: first)
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = DocumentLifecycleController(session: session,
            recoveryDirectory: fixtureDirectory.appendingPathComponent("recovery", isDirectory: true), autosaveDebouncer: debouncer)
        let url = fixtureDirectory.appendingPathComponent("Reuse.siteforge")
        let saved = await writer.save(to: url)
        XCTAssertTrue(saved)
        let reader = makeController()
        let opened = await reader.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document, session.document)
        try reader.session.undo()
        XCTAssertTrue(CanonicalComponentText.overrides(on: reader.session.document.pages[0].nodes[1]).isEmpty)
        try reader.session.redo()
        XCTAssertEqual(reader.session.document.pages, session.document.pages)
        try apply(.exposeText(nodeID: text.id, label: "Title", defaultValue: "Revised"), pageID: definition.id, target: text.id)
        await flushAutosave(writer, with: debouncer)
        let recovery = makeController()
        let recoveryOpened = await recovery.requestOpen(url)
        XCTAssertEqual(recoveryOpened, .completed)
        XCTAssertNotNil(recovery.recoveryCandidate)
        let restored = await recovery.requestRestoreRecovery()
        XCTAssertEqual(restored, .completed)
        XCTAssertEqual(recovery.session.document.pages, session.document.pages)
        XCTAssertEqual(CanonicalComponentText.overrides(on: recovery.session.document.pages[0].nodes[1])[binding.id], "Independent")
        XCTAssertTrue(CanonicalComponentText.overrides(on: recovery.session.document.pages[0].nodes[2]).isEmpty)
        XCTAssertEqual(recovery.session.document.pages[0].nodes[2].id, second)
        let scene = CanvasViewportSceneID(), current = recovery.session.document
        let reset = try ComponentCommandRegistry().prepare(.resetTextOverride(instanceID: first, propertyID: binding.id),
            identity: .init(documentID: current.id, pageID: page.id, revision: current.revision, sceneID: scene, rendererGeneration: current.revision),
            in: current, context: .init(activePageID: page.id, currentSceneID: scene, rendererGeneration: current.revision,
                selectedNodeIDs: [first], availableNodeIDs: [first], isLifecycleAvailable: true, lifecycleDisabledReason: nil))
        try recovery.session.execute(reset.command)
        XCTAssertTrue(CanonicalComponentText.overrides(on: recovery.session.document.pages[0].nodes[1]).isEmpty)
        try recovery.session.undo()
        XCTAssertEqual(recovery.session.document.pages, current.pages)
        try recovery.session.redo()
        XCTAssertTrue(CanonicalComponentText.overrides(on: recovery.session.document.pages[0].nodes[1]).isEmpty)
    }

    func testWebsiteMetadataForgedRedoInverseCannotHideOutsidePageContent() async throws {
        let session = DocumentSession()
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id,
            metadata: .init(siteName: "Aurora"))))
        try session.undo()
        let store = PersistedHistoryStore()
        let data = try await store.encodeRetained(session.historySnapshot())
        let incorrect = DocumentCommand.setWebsiteMetadata(.init(documentID: session.document.id,
            metadata: .init(siteName: "Incorrect inverse")))
        let encodedIncorrect = try JSONSerialization.jsonObject(with: JSONEncoder().encode(incorrect))
        let changed = try mutate(data) { root in
            var entries = root["redoEntries"] as! [[String: Any]]
            entries[0]["inverse"] = encodedIncorrect
            root["redoEntries"] = entries
        }
        let package = ProjectPackage(document: session.document,
            optionalMembers: [.init(path: PersistedHistoryStore.memberPath, data: changed)])
        let result = try await store.load(from: package)
        XCTAssertEqual(result, .cleanBaseline(.inverseMismatch))
        XCTAssertNil(session.document.websiteMetadata)
    }

    func testWebsiteFaviconDependencyDetachUndoAndMissingOutputAreTruthful() throws {
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Favicon", originalFilename: "icon.png",
            format: .png, pixelWidth: 32, pixelHeight: 32, byteCount: 1, contentHash: String(repeating: "a", count: 64))
        let session = DocumentSession()
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id,
            metadata: .init(siteName: "Aurora", faviconAssetID: asset.id))))
        let before = session.document
        XCTAssertThrowsError(try session.execute(.removeImageAsset(.init(assetID: asset.id))))
        XCTAssertEqual(session.document, before)
        let shell = WorkspaceShellState(documentSession: session)
        XCTAssertEqual(shell.imageAssetUsageCount(asset.id), 1)
        shell.deleteImageAssetAndUses(asset.id)
        XCTAssertTrue(session.document.imageAssets.isEmpty)
        XCTAssertNil(session.document.websiteMetadata?.faviconAssetID)
        try session.undo()
        XCTAssertEqual(session.document.imageAssets, before.imageAssets)
        XCTAssertEqual(session.document.websiteMetadata, before.websiteMetadata)
        var missing = session.document
        missing.imageAssets = []
        let output = StaticBuildCompiler.compile(document: missing, profileSelection: .init(profile: .development),
            resourceDescriptors: [:], resourceData: [:])
        XCTAssertFalse(output.canWrite)
        XCTAssertTrue(output.findings.contains { $0.code == "favicon-missing" })
        XCTAssertEqual(missing.websiteMetadata?.faviconAssetID, asset.id)
    }

    func testWebsiteMetadataSaveReopenAndRecoveryPreserveCanonicalHistory() async throws {
        let url = fixtureDirectory.appendingPathComponent("Website.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        let first = WebsiteMetadata(siteName: "Aurora", titlePattern: "{page} · {site}")
        try writer.session.execute(.setWebsiteMetadata(.init(documentID: writer.session.document.id, metadata: first)))
        let saved = await writer.save(to: url)
        XCTAssertTrue(saved)
        let reader = makeController()
        let opened = await reader.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document.websiteMetadata, first)
        try reader.session.undo()
        XCTAssertNil(reader.session.document.websiteMetadata)
        try reader.session.redo()
        XCTAssertEqual(reader.session.document.websiteMetadata, first)
        let recovered = WebsiteMetadata(siteName: "Aurora", defaultDescription: "A coastal journal")
        try writer.session.execute(.setWebsiteMetadata(.init(documentID: writer.session.document.id, metadata: recovered)))
        await flushAutosave(writer, with: debouncer)
        let recoveryReader = makeController()
        let recoveryOpen = await recoveryReader.requestOpen(url)
        XCTAssertEqual(recoveryOpen, .completed)
        XCTAssertNotNil(recoveryReader.recoveryCandidate)
        let restored = await recoveryReader.requestRestoreRecovery()
        XCTAssertEqual(restored, .completed)
        XCTAssertEqual(recoveryReader.session.document.websiteMetadata, recovered)
        try recoveryReader.session.undo()
        XCTAssertEqual(recoveryReader.session.document.websiteMetadata, first)
    }

    func testWebsiteMetadataDefaultHeaderTitleDoesNotRewriteAuthoredText() throws {
        var document = CanonicalDocument()
        let page = document.pages[0]
        var title = DocumentNode(kind: .text, name: "Site title", parent: .page(page.id),
            properties: [.init(key: .init(rawValue: "content.text"), value: .string("Home"), origin: .defaulted)])
        document.websiteMetadata = .init(siteName: "Aurora")
        XCTAssertEqual(CanonicalPageChrome.titleText(title, in: document), "Aurora")
        title.properties[0].origin = .authored
        XCTAssertEqual(CanonicalPageChrome.titleText(title, in: document), "Home")
    }

    func testWebsiteMetadataOutputUsesEscapedResolvedPageValues() throws {
        var document = CanonicalDocument()
        let page = document.pages.first { $0.role == .home }!
        document.websiteMetadata = .init(siteName: "Aurora & Coast", titlePattern: "{page} · {site}",
            defaultDescription: "A \"quiet\" <coast>", allowsIndexing: false,
            pages: [.init(pageID: page.id, title: "Aurora <Home>")])
        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let markup = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertTrue(markup.contains("<title>Aurora &lt;Home></title>"))
        XCTAssertTrue(markup.contains("content=\"A &quot;quiet&quot; &lt;coast>\""))
        XCTAssertTrue(markup.contains("noindex, follow"))
        XCTAssertEqual(markup.components(separatedBy: "<html").count, 2)
        XCTAssertFalse(markup.contains("<title>Aurora <Home>"))
        XCTAssertEqual(document.websiteMetadata?.pages.first?.pageID, page.id)
    }

    func testWebsiteMetadataLegacySchemaMigrationAndStrictCurrentShape() throws {
        let original = CanonicalDocument()
        let current = try DocumentSerializer.encode(original)
        var historical = try XCTUnwrap(JSONSerialization.jsonObject(with: current) as? [String: Any])
        historical["schemaVersion"] = 17
        var document = try XCTUnwrap(historical["document"] as? [String: Any])
        document.removeValue(forKey: "websiteMetadata")
        historical["document"] = document
        let migrated = try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical))
        XCTAssertEqual(migrated, original)
        XCTAssertNil(migrated.websiteMetadata)
        historical["schemaVersion"] = DocumentSerializer.currentSchemaVersion
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: historical)))
    }

    func testWebsiteMetadataRegistryRejectsStaleCancelledAndInvalidEdits() throws {
        let document = CanonicalDocument()
        let page = document.pages[0]
        let scene = CanvasViewportSceneID()
        let context = TransformValidationContext(activePageID: page.id, currentSceneID: scene,
            rendererGeneration: document.revision, selectedNodeIDs: [], availableNodeIDs: [],
            isLifecycleAvailable: true, lifecycleDisabledReason: nil)
        let identity = DesignInspectorOperationIdentity(documentID: document.id, pageID: page.id,
            revision: document.revision, sceneID: scene, rendererGeneration: document.revision)
        let registry = WebsiteMetadataCommandRegistry()
        let value = WebsiteMetadata(siteName: "Aurora")
        XCTAssertEqual(try registry.prepare(value, identity: identity, document: document, context: context),
                       .setWebsiteMetadata(.init(documentID: document.id, metadata: value)))
        XCTAssertThrowsError(try registry.prepare(value, identity: identity, document: document,
                                                  context: context, cancelled: true))
        let stale = DesignInspectorOperationIdentity(documentID: document.id, pageID: page.id,
            revision: document.revision + 1, sceneID: scene, rendererGeneration: document.revision)
        XCTAssertThrowsError(try registry.prepare(value, identity: stale, document: document, context: context))
        XCTAssertThrowsError(try registry.prepare(.init(siteName: "\nPrivate value"), identity: identity,
                                                  document: document, context: context))
        XCTAssertThrowsError(try registry.prepare(.init(), identity: identity, document: document, context: context))
        XCTAssertNil(document.websiteMetadata)
    }

    func testWebsiteMetadataResolutionRoundTripAndExactHistory() async throws {
        let session = DocumentSession()
        let original = session.document
        let page = original.pages.first { $0.role == .home }!
        let metadata = WebsiteMetadata(siteName: "Aurora", titlePattern: "{page} · {site}",
                                       defaultDescription: "A coastal journal",
                                       pages: [.init(pageID: page.id, allowsIndexing: false)])
        try session.execute(.setWebsiteMetadata(.init(documentID: original.id, metadata: metadata)))
        let resolved = WebsiteMetadataResolver.resolve(page: page, document: session.document)
        XCTAssertEqual(resolved.title, "\(page.name) · Aurora")
        XCTAssertEqual(resolved.descriptionSource, .inherited)
        XCTAssertFalse(resolved.allowsIndexing)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        let store = PersistedHistoryStore()
        let package = try await store.package(ProjectPackage(document: session.document), with: session.historySnapshot())
        guard case .restored(let restored) = try await store.load(from: package) else {
            return XCTFail("Metadata transactions must survive strict persisted-history validation")
        }
        XCTAssertEqual(restored, session.historySnapshot())
        try session.undo()
        XCTAssertNil(session.document.websiteMetadata)
        try session.redo()
        XCTAssertEqual(session.document.websiteMetadata, metadata)
        XCTAssertEqual(session.historySnapshot().undoEntries.count, 1)
    }

    func testWebsiteMetadataRejectsMalformedValuesAndPreservesPageRemovalInverse() throws {
        let session = DocumentSession()
        let page = DocumentPage(name: "Coast")
        try session.execute(.insertPage(.init(page: page, index: session.document.pages.count)))
        let metadata = WebsiteMetadata(siteName: "Aurora", pages: [.init(pageID: page.id, title: "The coast")])
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id, metadata: metadata)))
        let before = session.document
        XCTAssertThrowsError(try session.execute(.setWebsiteMetadata(.init(documentID: before.id,
            metadata: .init(titlePattern: "{unknown}")))))
        XCTAssertEqual(session.document, before)
        try session.execute(.removePage(.init(pageID: page.id)))
        XCTAssertEqual(session.document.websiteMetadata?.pages, [])
        try session.undo()
        XCTAssertEqual(session.document.websiteMetadata, metadata)
        XCTAssertEqual(session.document.pages, before.pages)
    }

    nonisolated(unsafe) private var fixtureDirectory: URL!
    nonisolated(unsafe) private var fixtureLease: ApplicationOwnedTestFixture!

    nonisolated override func setUpWithError() throws {
        try super.setUpWithError()
        fixtureLease = try ApplicationOwnedTestFixture.create("history")
        fixtureDirectory = fixtureLease.url
    }

    nonisolated override func tearDownWithError() throws {
        try fixtureLease.cleanup()
        fixtureDirectory = nil
        try super.tearDownWithError()
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
        let overflowingRevision = try mutate(valid.data) { object in
            var entries = object["undoEntries"] as! [[String: Any]]
            entries[0]["parentRevision"] = NSNumber(value: UInt64.max)
            object["undoEntries"] = entries
        }
        cases.append((overflowingRevision, .revisionMismatch))

        for (data, expected) in cases {
            let store = PersistedHistoryStore()
            let result = try await store.load(from: package(valid.package, historyData: data))
            XCTAssertEqual(result, .cleanBaseline(expected))
        }
    }

    // SF-0307-004 — history schema v2 is closed. A compatible decoder may
    // not silently erase future transaction, target, or command semantics.
    func testCurrentHistorySchemaRejectsUnknownEnvelopeEntryTargetAndCommandFields() async throws {
        let valid = try await makeValidHistoryFixture(entryCount: 1)
        let cases: [Data] = [
            try mutate(valid.data) { $0["futureHistoryField"] = true },
            try mutate(valid.data) { object in
                var entries = object["undoEntries"] as! [[String: Any]]
                entries[0]["futureEntryField"] = true
                object["undoEntries"] = entries
            },
            try mutate(valid.data) { object in
                var entries = object["undoEntries"] as! [[String: Any]]
                var targets = entries[0]["affectedIdentifiers"] as! [[String: Any]]
                targets[0]["futureTargetField"] = true
                entries[0]["affectedIdentifiers"] = targets
                object["undoEntries"] = entries
            },
            try mutate(valid.data) { object in
                var entries = object["undoEntries"] as! [[String: Any]]
                var forward = entries[0]["forward"] as! [String: Any]
                var wrapper = forward["insertPage"] as! [String: Any]
                var payload = wrapper["_0"] as! [String: Any]
                payload["futureCommandField"] = true
                wrapper["_0"] = payload
                forward["insertPage"] = wrapper
                entries[0]["forward"] = forward
                object["undoEntries"] = entries
            },
        ]

        for data in cases {
            let result = try await PersistedHistoryStore().load(from: package(valid.package, historyData: data))
            XCTAssertEqual(result, .cleanBaseline(.corrupt))
        }
    }

    // SF-0306-004, SF-0306-005, SF-0307-004 — v1 persisted the inverse
    // index of a backwards same-parent move after removal. Loading it must
    // repair history without changing canonical package state.
    func testVersionOneSameParentBackwardMoveMigratesToExactUndoInverse() async throws {
        let first = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000110")!)
        let second = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000111")!)
        let third = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000112")!)
        let rootID = NodeID(UUID(uuidString: "00000000-0000-0000-0000-000000000113")!)
        let pageID = PageID(UUID(uuidString: "00000000-0000-0000-0000-000000000114")!)
        let original = CanonicalDocument(pages: [DocumentPage(
            id: pageID,
            name: "History move",
            rootNodeIDs: [rootID],
            nodes: [
                DocumentNode(id: rootID, kind: .frame, name: "Root", parent: .page(pageID), childIDs: [first, second, third]),
                DocumentNode(id: first, kind: .frame, name: "First", parent: .node(rootID)),
                DocumentNode(id: second, kind: .frame, name: "Second", parent: .node(rootID)),
                DocumentNode(id: third, kind: .frame, name: "Third", parent: .node(rootID)),
            ]
        )])
        let session = DocumentSession(document: original)
        try session.execute(.moveNode(MoveNodeCommand(
            pageID: pageID, nodeID: third, destination: .node(rootID), index: 0
        )))
        let currentData = try await PersistedHistoryStore().encodeRetained(session.historySnapshot())
        let v1Data = try mutate(currentData) { object in
            object["schemaVersion"] = 1
            var entries = object["undoEntries"] as! [[String: Any]]
            var inverse = entries[0]["inverse"] as! [String: Any]
            var wrapper = inverse["moveNode"] as! [String: Any]
            var payload = wrapper["_0"] as! [String: Any]
            payload["index"] = 2 // Exact v1 pre-fix encoding; v2 stores 3.
            wrapper["_0"] = payload
            inverse["moveNode"] = wrapper
            entries[0]["inverse"] = inverse
            object["undoEntries"] = entries
        }
        let result = try await PersistedHistoryStore().load(from: package(
            ProjectPackage(document: session.document), historyData: v1Data
        ))
        guard case .restored(let migrated) = result else {
            return XCTFail("A supported v1 history must migrate rather than isolate")
        }
        XCTAssertEqual(migrated.schemaVersion, PersistedHistorySnapshot.currentSchemaVersion)
        guard case .moveNode(let inverse) = migrated.undoEntries[0].inverse else {
            return XCTFail("Expected migrated move inverse")
        }
        XCTAssertEqual(inverse.index, 3)

        let reopened = DocumentSession(document: session.document)
        try reopened.installValidatedHistory(migrated)
        try reopened.undo()
        XCTAssertEqual(reopened.document.pages, original.pages)
        try reopened.redo()
        // Revisions are monotonic transaction identities: undo and redo
        // restore exact authored content while each applies its own commit.
        XCTAssertEqual(reopened.document.id, session.document.id)
        XCTAssertEqual(reopened.document.pages, session.document.pages)
        XCTAssertEqual(reopened.document.guides, session.document.guides)
        XCTAssertEqual(reopened.document.revision, session.document.revision + 2)
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

    // SF-0306-005/008, SF-0307-003/005: both halves of a full retained
    // history still validate and replay exactly after eliminating duplicate
    // availability work. No retention or inverse check may be skipped.
    func testFullRetainedHistoryReopensBothStacksWithExactMetadataRoundTrips() async throws {
        let session = DocumentSession(document: ProjectCreation.blank())
        let baseline = session.document
        for index in 0..<PersistedHistoryStore.maximumEntryCount {
            try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id,
                metadata: .init(siteName: "History \(index)", defaultDescription: "Retained \(index)"))))
        }
        let fullyAuthored = session.document
        for _ in 0..<(PersistedHistoryStore.maximumEntryCount / 2) { try session.undo() }
        let expected = session.historySnapshot()
        XCTAssertEqual(expected.undoEntries.count + expected.redoEntries.count, PersistedHistoryStore.maximumEntryCount)
        let store = PersistedHistoryStore()
        let data = try await store.encodeRetained(expected)
        let persisted = package(ProjectPackage(document: session.document), historyData: data)
        let loaded = try await store.load(from: persisted)
        XCTAssertEqual(loaded, .restored(expected))
        let url = fixtureDirectory.appendingPathComponent("FullHistory.siteforge")
        try await ProjectPackageStore().write(persisted, to: url)
        let reader = makeController()
        let opened = await reader.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.historySnapshot(), expected)
        while reader.session.canUndo { try reader.session.undo() }
        XCTAssertEqual(reader.session.document.pages, baseline.pages)
        XCTAssertEqual(reader.session.document.websiteMetadata, baseline.websiteMetadata)
        while reader.session.canRedo { try reader.session.redo() }
        XCTAssertEqual(reader.session.document.pages, fullyAuthored.pages)
        XCTAssertEqual(reader.session.document.websiteMetadata, fullyAuthored.websiteMetadata)
        XCTAssertEqual(reader.session.document.id, baseline.id)
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
        let retained = try await store.load(from: package(ProjectPackage(document: session.document), historyData: retainedData))
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
        _ = try await store.load(from: package(valid.package, historyData: valid.data))
        let description = String(describing: await diagnostics.records)
        XCTAssertFalse(description.contains("top-secret-page"))
        XCTAssertFalse(description.contains(valid.package.document.id.description))
        XCTAssertFalse(description.contains(fixtureDirectory.path))
        XCTAssertTrue(description.contains("document-"))
    }

    // SF-0301-004, SF-0301-007, SF-0307-008
    func testCancellationInsideHistoryValidationIsDistinctFromIsolation() async throws {
        let valid = try await makeValidHistoryFixture(entryCount: 4)
        let barrier = DeterministicCancellationBarrier(blockAt: 3)
        let store = PersistedHistoryStore(cancellation: CooperativeCancellationCheckpoint(barrier.check))
        let task = Task { try await store.load(from: package(valid.package, historyData: valid.data)) }

        await barrier.waitUntilBlocked()
        task.cancel()
        barrier.release()

        do {
            _ = try await task.value
            XCTFail("Cancelled history validation must not produce an isolation baseline")
        } catch is CancellationError {
            // The lifecycle can keep the current document and report cancellation.
        }
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
