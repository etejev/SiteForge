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

    // SF-1207-001/004/005: website metadata version 2 adds the site address
    // and social image. Version 1 records still decode (both absent) and
    // every other key set is refused; addresses are https only, without a
    // trailing slash, query, fragment, credentials or other port; the new
    // fields need document schema 27; the social image counts as a use, can't
    // be deleted while used, and Delete with Uses clears it in one undoable step.
    func testWebsiteMetadataVersionTwoSiteAddressAndSocialImageAreStrictAndTracked() throws {
        let metadata = WebsiteMetadata(siteName: "Aurora", siteURL: "https://aurora.example/shop")
        XCTAssertEqual(WebsiteMetadata.currentVersion, 3)
        let encoded = try JSONEncoder().encode(metadata)
        XCTAssertEqual(try JSONDecoder().decode(WebsiteMetadata.self, from: encoded), metadata)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["version"] = 1
        object.removeValue(forKey: "siteURL")
        object.removeValue(forKey: "socialImageAssetID")
        object.removeValue(forKey: "customCode")
        let versionOne = try JSONDecoder().decode(WebsiteMetadata.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(versionOne, WebsiteMetadata(siteName: "Aurora"), "Read as the current version with the new fields absent")
        XCTAssertEqual(versionOne.version, WebsiteMetadata.currentVersion)
        let forgeries: [(String, (inout [String: Any]) -> Void)] = [
            ("version 1 with new keys", { $0["version"] = 1 }),
            ("version 3 missing keys", { _ = $0.removeValue(forKey: "siteURL") }),
            ("unknown version", { $0["version"] = 4 }),
            ("unknown key", { $0["ogType"] = "article" }),
        ]
        for (label, change) in forgeries {
            var forged = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            change(&forged)
            XCTAssertThrowsError(try JSONDecoder().decode(WebsiteMetadata.self, from: JSONSerialization.data(withJSONObject: forged)), label)
        }
        for valid in ["https://aurora.example", "https://aurora.example/shop", "https://aurora.example:443"] {
            XCTAssertTrue(WebsiteMetadata.validSiteURL(valid), valid)
        }
        for invalid in ["http://aurora.example", "https://aurora.example/", "https://aurora.example?a=1", "https://aurora.example#top",
                        "https://user:pass@aurora.example", "https://aurora.example:8443", "aurora.example", "https://", " https://a.example",
                        "https://a.example/\"x", "https://a.example/<x"] {
            XCTAssertFalse(WebsiteMetadata.validSiteURL(invalid), invalid)
        }

        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Share", originalFilename: "share.png",
            format: .png, pixelWidth: 1200, pixelHeight: 630, byteCount: 1, contentHash: String(repeating: "b", count: 64))
        let session = DocumentSession()
        try session.execute(.insertImageAsset(.init(asset: asset, index: 0)))
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id,
            metadata: .init(siteName: "Aurora", siteURL: "https://aurora.example", socialImageAssetID: asset.id))))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(session.document)) as? [String: Any])
        envelope["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "Needs schema 27")
        XCTAssertEqual(ImageAssetReference.references(to: asset.id, in: session.document).map(\.kind), [.socialImage])
        let before = session.document
        XCTAssertThrowsError(try session.execute(.removeImageAsset(.init(assetID: asset.id))))
        XCTAssertEqual(session.document, before)
        let shell = WorkspaceShellState(documentSession: session)
        XCTAssertEqual(shell.imageAssetUsageCount(asset.id), 1)
        shell.deleteImageAssetAndUses(asset.id)
        XCTAssertTrue(session.document.imageAssets.isEmpty)
        XCTAssertNil(session.document.websiteMetadata?.socialImageAssetID)
        XCTAssertEqual(session.document.websiteMetadata?.siteURL, "https://aurora.example", "Only the image is cleared")
        try session.undo()
        XCTAssertEqual(session.document.websiteMetadata, before.websiteMetadata)
    }

    // SF-1001-001/002/004/005, SF-1002-005 (OD-035): collections are strict,
    // schema-27 gated, one undoable transaction, persisted in history, and
    // their fields feed template expressions.
    func testCollectionsAreStrictSchemaGatedUndoableAndPersistedInHistory() async throws {
        var authors = CollectionEditing.newCollection(in: [], name: "Authors")
        var posts = CollectionEditing.newCollection(in: [authors], name: "Posts")
        XCTAssertEqual(authors.slug, "authors")
        XCTAssertEqual(posts.fields.map(\.key), ["title"])
        XCTAssertEqual(posts.fields.first?.isRequired, true)
        let published = try CollectionEditing.addField(label: "Published On", type: .date, referencing: nil, to: &posts)
        let price = try CollectionEditing.addField(label: "Price", type: .number, referencing: nil, to: &posts)
        let author = try CollectionEditing.addField(label: "Author", type: .reference, referencing: authors.id, to: &posts)
        XCTAssertEqual([published.key, price.key, author.key], ["publishedOn", "price", "author"])
        XCTAssertThrowsError(try CollectionEditing.addField(label: "Writer", type: .reference, referencing: nil, to: &posts))

        let authorTitle = try XCTUnwrap(authors.fields.first)
        let ada = CollectionItem(slug: "ada", status: .published,
                                 values: [CollectionItemValue(fieldID: authorTitle.id, value: .text("Ada"))])
        authors.items = [ada]
        let postTitle = try XCTUnwrap(posts.fields.first)
        let day = try XCTUnwrap(SiteExpressionDate(iso: "2026-11-26"))
        var post = CollectionEditing.newItem(in: posts)
        XCTAssertEqual(post.slug, "item")
        XCTAssertEqual(post.status, .draft)
        post.setValue(.text("Hello"), for: postTitle.id)
        post.setValue(.date(day), for: published.id)
        post.setValue(.reference(ada.id), for: author.id)
        post.status = .published
        posts.items = [post]
        let collections = [authors, posts]
        XCTAssertEqual(CanonicalCollections.issues(collections), [])

        let schema = posts.expressionSchema(in: collections)
        XCTAssertEqual(schema.fields["author.title"], .text)
        XCTAssertEqual(schema.fields["author.slug"], .text)
        XCTAssertEqual(schema.fields["publishedOn"], .date)
        XCTAssertNil(schema.fields["author"], "References are not expression values")
        let program = try SiteExpressionEngine.check("upper(author.title) + \" · \" + formatDate(publishedOn, \"long\") + \" · \" + text(price ?? 0)", schema: schema)
        XCTAssertEqual(SiteExpressionEngine.evaluate(program, context: posts.expressionContext(for: post, in: collections)).value,
                       .text("ADA · November 26, 2026 · 0"))

        let blank = ProjectCreation.blank()
        XCTAssertFalse(String(decoding: try DocumentSerializer.encode(blank), as: UTF8.self).contains("\"collections\""),
                       "A project without collections stores no collections key")
        let session = DocumentSession(document: blank)
        XCTAssertThrowsError(try CollectionEditing.prepare(collections, openingRevision: blank.revision, document: blank,
                                                           isLifecycleAvailable: false)) {
            XCTAssertEqual($0 as? CollectionEditError, .busy)
        }
        XCTAssertThrowsError(try CollectionEditing.prepare(collections, openingRevision: blank.revision + 1, document: blank,
                                                           isLifecycleAvailable: true)) {
            XCTAssertEqual($0 as? CollectionEditError, .stale)
        }
        XCTAssertThrowsError(try CollectionEditing.prepare([], openingRevision: blank.revision, document: blank,
                                                           isLifecycleAvailable: true)) {
            XCTAssertEqual($0 as? CollectionEditError, .unchanged)
        }
        try session.execute(CollectionEditing.prepare(collections, openingRevision: blank.revision, document: session.document,
                                                      isLifecycleAvailable: true))
        XCTAssertEqual(session.document.collections, collections)
        XCTAssertEqual(session.historySnapshot().undoEntries.map(\.commandName), [.setCollections])
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = blank.revision
        XCTAssertEqual(undone, blank)
        try session.redo()
        XCTAssertEqual(session.document.collections, collections)

        let data = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(data), session.document)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        envelope["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "Needs schema 27")
        let forgeries: [(String, ([String: Any]) -> [String: Any])] = [
            ("empty list", { document in var copy = document; copy["collections"] = [Any](); return copy }),
            ("null", { document in var copy = document; copy["collections"] = NSNull(); return copy }),
            ("unknown collection key", { document in
                var copy = document
                var stored = copy["collections"] as? [[String: Any]] ?? []
                stored[0]["query"] = "SELECT"
                copy["collections"] = stored
                return copy
            }),
            ("invalid item address", { document in
                var copy = document
                var stored = copy["collections"] as? [[String: Any]] ?? []
                var items = stored[1]["items"] as? [[String: Any]] ?? []
                items[0]["slug"] = "Not A Slug"
                stored[1]["items"] = items
                copy["collections"] = stored
                return copy
            }),
        ]
        for (label, change) in forgeries {
            var forged = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            forged["document"] = change(try XCTUnwrap(forged["document"] as? [String: Any]))
            XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: forged)), label)
        }

        let store = PersistedHistoryStore()
        let history = try await store.encodeRetained(session.historySnapshot())
        XCTAssertTrue(String(decoding: history, as: UTF8.self).contains("\"setCollections\""))
        let loaded = try await store.load(from: ProjectPackage(document: session.document,
            optionalMembers: [.init(path: PersistedHistoryStore.memberPath, data: history)]))
        guard case .restored(let snapshot) = loaded else { return XCTFail("Collection history must restore: \(loaded)") }
        XCTAssertEqual(snapshot.undoEntries.map(\.commandName), [.setCollections])
        XCTAssertEqual(snapshot.undoEntries.first?.inverse, .setCollections(.init(documentID: blank.id, collections: [])))
    }

    // SF-1007-001/002/004/005, SF-1506-001 (OD-038, ADR-0080): site languages
    // are strict, schema-27 gated, keep defaulted and authored values apart,
    // commit as one undoable transaction, persist in history and are restored
    // and compared with snapshots.
    func testSiteLanguagesAreStrictSchemaGatedUndoableAndPersistedInHistory() async throws {
        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let french = try SiteLocalizationEditing.addLocale(code: "fr_ca", name: "Français (Canada)", to: &localization)
        let arabic = try SiteLocalizationEditing.addLocale(code: "AR", name: "العربية", to: &localization)
        XCTAssertEqual(localization.locales.map(\.code), ["en", "fr-CA", "ar"])
        XCTAssertEqual(localization.defaultLocale?.name, "English")
        XCTAssertNil(french.fallbackLocaleID, "A new language falls back to the default")
        XCTAssertThrowsError(try SiteLocalizationEditing.addLocale(code: "FR-ca", to: &localization)) {
            XCTAssertEqual($0 as? SiteLocalizationEditError, .duplicateCode)
        }
        XCTAssertThrowsError(try SiteLocalizationEditing.addLocale(code: "not a code", to: &localization)) {
            XCTAssertEqual($0 as? SiteLocalizationEditError, .invalidCode)
        }
        XCTAssertEqual(localization.locales[2].id, arabic.id)
        localization.locales[2].direction = .rightToLeft

        let blank = ProjectCreation.blank()
        XCTAssertEqual(CanonicalLocalization.issues(localization, pages: blank.pages), [])
        XCTAssertFalse(String(decoding: try DocumentSerializer.encode(blank), as: UTF8.self).contains("\"localization\""),
                       "A site with one unnamed language stores no localization key")
        let session = DocumentSession(document: blank)
        XCTAssertThrowsError(try SiteLocalizationEditing.prepare(localization, openingRevision: blank.revision, document: blank,
                                                                 isLifecycleAvailable: false)) {
            XCTAssertEqual($0 as? SiteLocalizationEditError, .busy)
        }
        XCTAssertThrowsError(try SiteLocalizationEditing.prepare(localization, openingRevision: blank.revision + 1, document: blank,
                                                                 isLifecycleAvailable: true)) {
            XCTAssertEqual($0 as? SiteLocalizationEditError, .stale)
        }
        XCTAssertThrowsError(try SiteLocalizationEditing.prepare(nil, openingRevision: blank.revision, document: blank,
                                                                 isLifecycleAvailable: true)) {
            XCTAssertEqual($0 as? SiteLocalizationEditError, .unchanged)
        }
        var broken = localization
        broken.locales[1].code = "fr-ca"
        XCTAssertThrowsError(try SiteLocalizationEditing.prepare(broken, openingRevision: blank.revision, document: blank,
                                                                 isLifecycleAvailable: true)) {
            XCTAssertEqual($0 as? SiteLocalizationEditError,
                           .invalid([SiteLocalizationIssue(kind: .code, localeID: french.id)]))
        }
        XCTAssertEqual(session.document, blank, "Refused edits leave the document unchanged")

        try session.execute(SiteLocalizationEditing.prepare(localization, openingRevision: blank.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        XCTAssertEqual(session.document.localization, localization)
        XCTAssertEqual(session.historySnapshot().undoEntries.map(\.commandName), [.setLocalization])
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = blank.revision
        XCTAssertEqual(undone, blank)
        try session.redo()
        XCTAssertEqual(session.document.localization, localization)

        let data = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(data), session.document)
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let storedDocument = try XCTUnwrap(stored["document"] as? [String: Any])
        let storedLocales = try XCTUnwrap((storedDocument["localization"] as? [String: Any])?["locales"] as? [[String: Any]])
        XCTAssertEqual(Set(storedLocales[1].keys), ["id", "code", "name"], "Defaulted direction and fallback are omitted")
        XCTAssertEqual(Set(storedLocales[2].keys), ["id", "code", "name", "direction"],
                       "An authored direction is stored even when it matches the one the code implies")
        var envelope = stored
        envelope["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "Needs schema 27")

        func forgingLanguages(_ change: @escaping (inout [String: Any]) -> Void) -> ([String: Any]) -> [String: Any] {
            { document in
                var copy = document
                var languages = copy["localization"] as? [String: Any] ?? [:]
                change(&languages)
                copy["localization"] = languages
                return copy
            }
        }
        func forgingLocale(_ index: Int, _ key: String, _ value: Any) -> ([String: Any]) -> [String: Any] {
            forgingLanguages { languages in
                var locales = languages["locales"] as? [[String: Any]] ?? []
                locales[index][key] = value
                languages["locales"] = locales
            }
        }
        let forgeries: [(String, ([String: Any]) -> [String: Any])] = [
            ("null", { document in var copy = document; copy["localization"] = NSNull(); return copy }),
            ("no languages", forgingLanguages { $0["locales"] = [Any]() }),
            ("unknown key", forgingLanguages { $0["translations"] = [String: Any]() }),
            ("future version", forgingLanguages { $0["version"] = 2 }),
            ("unknown default", forgingLanguages { $0["defaultLocaleID"] = UUID().uuidString }),
            ("null direction", forgingLocale(1, "direction", NSNull())),
            ("null fallback", forgingLocale(1, "fallbackLocaleID", NSNull())),
            ("non-canonical code", forgingLocale(1, "code", "FR-ca")),
            ("unknown direction", forgingLocale(1, "direction", "upward")),
        ]
        for (label, change) in forgeries {
            var forged = stored
            forged["document"] = change(storedDocument)
            XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: forged)), label)
        }

        let store = PersistedHistoryStore()
        let history = try await store.encodeRetained(session.historySnapshot())
        XCTAssertTrue(String(decoding: history, as: UTF8.self).contains("\"setLocalization\""))
        let loaded = try await store.load(from: ProjectPackage(document: session.document,
            optionalMembers: [.init(path: PersistedHistoryStore.memberPath, data: history)]))
        guard case .restored(let snapshot) = loaded else { return XCTFail("Language history must restore: \(loaded)") }
        XCTAssertEqual(snapshot.undoEntries.map(\.commandName), [.setLocalization])
        XCTAssertEqual(snapshot.undoEntries.first?.inverse, .setLocalization(.init(documentID: blank.id, localization: nil)))

        // SF-1301 / SF-1306: snapshots restore and compare the languages.
        let localized = session.document
        let comparison = try ProjectComparer.compare(
            ProjectComparisonSource(snapshotID: nil, name: "Before Languages", document: blank),
            with: ProjectComparisonSource(snapshotID: nil, name: ProjectComparisonSource.currentDocumentName, document: localized))
        XCTAssertEqual(comparison.changes.filter { $0.area == .settings }.map(\.subject), ["Languages"])
        let restore = try ProjectSnapshots.restoreCommand(to: blank, from: localized, resources: nil)
        XCTAssertEqual(restore, .batch([.setLocalization(.init(documentID: blank.id, localization: nil))]))
        try session.execute(restore)
        XCTAssertNil(session.document.localization)
        try session.undo()
        XCTAssertEqual(session.document.localization, localization)
    }

    // SF-1007-003/004/008, SF-1506-003 (OD-038, ADR-0080): codes are canonical;
    // fallbacks, direction and language addresses resolve deterministically with
    // provenance; broken rules name the language or page; language addresses
    // never collide with pages; edit diagnostics hold no names or codes.
    func testSiteLanguageRulesResolveFallbacksDirectionAndAddresses() throws {
        XCTAssertEqual(SiteLocaleCode.canonical(" zh_hant_tw "), "zh-Hant-TW")
        XCTAssertEqual(SiteLocaleCode.canonical("ES-419"), "es-419")
        XCTAssertEqual(SiteLocaleCode.canonical("de-ch-1996"), "de-CH-1996")
        for invalid in ["", "e", "english", "fr--CA", "-fr", "fr-", "fr-C", "fr/ca", "fr-abc", "fr-CA-x-private", "日本"] {
            XCTAssertNil(SiteLocaleCode.canonical(invalid), invalid)
        }
        XCTAssertTrue(SiteLocaleCode.isValid("fr-CA"))
        XCTAssertFalse(SiteLocaleCode.isValid("fr-ca"))
        XCTAssertEqual(SiteLocaleCode.routeSegment("pt-BR"), "pt-br")
        XCTAssertEqual(SiteTextDirection.implied(byCode: "ar-EG"), .rightToLeft)
        XCTAssertEqual(SiteTextDirection.implied(byCode: "he"), .rightToLeft)
        XCTAssertEqual(SiteTextDirection.implied(byCode: "az-Arab"), .rightToLeft)
        XCTAssertEqual(SiteTextDirection.implied(byCode: "ar-Latn"), .leftToRight)
        XCTAssertEqual(SiteTextDirection.implied(byCode: "fr-CA"), .leftToRight)
        XCTAssertEqual(SiteTextDirection.rightToLeft.htmlValue, "rtl")

        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let english = localization.defaultLocaleID
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "Français", to: &localization)
        let canadian = try SiteLocalizationEditing.addLocale(code: "fr-CA", name: "Français (Canada)", to: &localization)
        let hebrew = try SiteLocalizationEditing.addLocale(code: "he", name: "עברית", to: &localization)
        localization.locales[2].fallbackLocaleID = french.id
        localization.locales[3].direction = .leftToRight
        let pages = ProjectCreation.blank().pages
        XCTAssertEqual(CanonicalLocalization.issues(localization, pages: pages), [])

        let canada = try XCTUnwrap(SiteLocaleResolver.resolve(canadian.id, in: localization))
        XCTAssertEqual(canada.fallbackChain, [french.id, english])
        XCTAssertEqual(canada.fallbackSource, .authored)
        XCTAssertEqual(canada.routePrefix, "/fr-ca")
        XCTAssertEqual(canada.direction, .leftToRight)
        XCTAssertEqual(canada.directionSource, .impliedByCode)
        XCTAssertTrue(canada.explanation.contains("2 fallback language(s)"), canada.explanation)
        let base = try XCTUnwrap(SiteLocaleResolver.resolve(english, in: localization))
        XCTAssertTrue(base.isDefault)
        XCTAssertEqual(base.fallbackChain, [])
        XCTAssertEqual(base.fallbackSource, .isDefault)
        XCTAssertEqual(base.routePrefix, "")
        let override = try XCTUnwrap(SiteLocaleResolver.resolve(hebrew.id, in: localization))
        XCTAssertEqual(override.direction, .leftToRight)
        XCTAssertEqual(override.directionSource, .authored)
        XCTAssertEqual(override.fallbackSource, .defaultLocale)
        XCTAssertTrue(override.explanation.contains("set for this language"), override.explanation)
        XCTAssertFalse(override.explanation.contains("עברית"))
        XCTAssertNil(SiteLocaleResolver.resolve(SiteLocaleID(), in: localization))
        XCTAssertEqual(SiteLocaleResolver.route(PageRoute(rawValue: "/"), for: french.id, in: localization)?.rawValue, "/fr")
        XCTAssertEqual(SiteLocaleResolver.route(PageRoute(rawValue: "/about"), for: canadian.id, in: localization)?.rawValue,
                       "/fr-ca/about")
        XCTAssertEqual(SiteLocaleResolver.route(PageRoute(rawValue: "/about"), for: english, in: localization)?.rawValue, "/about")
        XCTAssertEqual(SiteLocaleResolver.firstAvailable(canadian.id, in: localization, where: { $0 != canadian.id }), french.id)
        XCTAssertEqual(SiteLocaleResolver.firstAvailable(canadian.id, in: localization, where: { $0 == english }), english)
        XCTAssertNil(SiteLocaleResolver.firstAvailable(canadian.id, in: localization, where: { _ in false }))

        func kinds(_ change: (inout SiteLocalization) -> Void) -> [SiteLocalizationIssue.Kind] {
            var copy = localization
            change(&copy)
            return CanonicalLocalization.issues(copy, pages: pages).map(\.kind)
        }
        XCTAssertEqual(kinds { $0.locales[1].code = "FR" }, [.code])
        XCTAssertEqual(kinds { $0.locales[2].code = "fr" }, [.duplicateCode])
        XCTAssertEqual(kinds { $0.locales[1].name = " Français" }, [.name])
        XCTAssertEqual(kinds { $0.locales[2].name = "FRANÇAIS" }, [.duplicateName])
        XCTAssertEqual(kinds { $0.locales[0].fallbackLocaleID = french.id }, [.defaultHasFallback])
        XCTAssertEqual(kinds { $0.locales[3].fallbackLocaleID = hebrew.id }, [.fallbackToSelf])
        XCTAssertEqual(kinds { $0.locales[1].fallbackLocaleID = SiteLocaleID() }, [.unknownFallback])
        XCTAssertEqual(kinds { $0.locales[1].fallbackLocaleID = canadian.id }, [.fallbackCycle, .fallbackCycle])
        XCTAssertEqual(kinds { $0.defaultLocaleID = SiteLocaleID() }, [.missingDefault])
        XCTAssertEqual(kinds { $0.locales.removeAll() }, [.noLocales, .missingDefault])
        XCTAssertEqual(kinds { let twin = $0.locales[1]; $0.locales.append(twin) },
                       [.duplicateIdentity, .duplicateCode, .duplicateName])
        for kind in SiteLocalizationIssue.Kind.allCases {
            XCTAssertFalse(SiteLocalizationIssue(kind: kind).message.isEmpty, kind.rawValue)
        }

        var colliding = pages
        colliding.append(DocumentPage(name: "Notes", route: PageRoute(rawValue: "/fr/notes")))
        colliding.append(DocumentPage(name: "French", route: PageRoute(rawValue: "/french")))
        let collisions = CanonicalLocalization.issues(localization, pages: colliding)
        XCTAssertEqual(collisions.map(\.kind), [.routeCollision])
        XCTAssertEqual(collisions.first?.localeID, french.id)
        XCTAssertEqual(collisions.first?.pageID, colliding[pages.count].id)
        var document = ProjectCreation.blank()
        document.localization = localization
        XCTAssertNoThrow(try document.validate())
        let beforeCollision = document
        document.pages.append(DocumentPage(name: "Notes", route: PageRoute(rawValue: "/fr/notes")))
        XCTAssertThrowsError(try document.validate()) {
            XCTAssertEqual($0 as? ModelValidationError, .invalidLocalization)
        }
        var crowded = beforeCollision
        crowded.localization = nil
        crowded.pages.append(DocumentPage(name: "Notes", route: PageRoute(rawValue: "/fr/notes")))
        XCTAssertThrowsError(try SiteLocalizationEditing.prepare(localization, openingRevision: crowded.revision, document: crowded,
                                                                 isLifecycleAvailable: true)) {
            XCTAssertEqual(($0 as? SiteLocalizationEditError)?.category, "invalid")
        }

        var removed = localization
        try SiteLocalizationEditing.removeLocale(french.id, from: &removed)
        XCTAssertNotNil(removed.locale(canadian.id))
        XCTAssertNil(removed.locale(canadian.id)?.fallbackLocaleID, "Removing a fallback restores the default")
        XCTAssertEqual(CanonicalLocalization.issues(removed, pages: pages), [])
        XCTAssertThrowsError(try SiteLocalizationEditing.removeLocale(english, from: &removed)) {
            XCTAssertEqual($0 as? SiteLocalizationEditError, .cannotRemoveDefault)
        }
        XCTAssertThrowsError(try SiteLocalizationEditing.removeLocale(french.id, from: &removed)) {
            XCTAssertEqual($0 as? SiteLocalizationEditError, .unknownLocale)
        }
        var moved = localization
        try SiteLocalizationEditing.makeDefault(canadian.id, in: &moved)
        XCTAssertEqual(moved.defaultLocaleID, canadian.id)
        XCTAssertNil(moved.locale(canadian.id)?.fallbackLocaleID)
        XCTAssertEqual(CanonicalLocalization.issues(moved, pages: pages), [])
        XCTAssertEqual(SiteLocaleResolver.resolve(english, in: moved)?.fallbackChain, [canadian.id])

        let german = SiteLocalizationEditing.suggestedName(for: "de", in: localization)
        XCTAssertFalse(german.isEmpty)
        var withGerman = localization
        try SiteLocalizationEditing.addLocale(code: "de", name: german, to: &withGerman)
        XCTAssertTrue(SiteLocalizationEditing.suggestedName(for: "de", in: withGerman).hasSuffix("(de)"))

        let diagnostic = SiteLocalizationEditDiagnostic(operation: "set", localization: localization,
                                                        durationMilliseconds: 4, error: SiteLocalizationEditError.stale)
        XCTAssertEqual(diagnostic.requirementID, "SF-1007-002")
        XCTAssertEqual(diagnostic.failureCategory, "stale")
        XCTAssertEqual(diagnostic.localeCount, 4)
        XCTAssertEqual(diagnostic.localeIdentifiers, localization.locales.map(\.id.description))
        let recorded = String(describing: diagnostic)
        for secret in ["English", "Français", "fr-CA", "עברית"] {
            XCTAssertFalse(recorded.contains(secret), secret)
        }
        XCTAssertEqual(SiteLocalizationEditDiagnostic(operation: "set", localization: nil, durationMilliseconds: 0,
                                                      error: nil).failureCategory, "none")
    }

    // SF-1007-001/002/004/005/008 (OD-038 part 2, ADR-0081): translations are
    // authored node properties keyed by language identity; each edit is one
    // undoable grouped edit, refusals leave the document unchanged, strict
    // rules refuse malformed translations, history persists them, and an
    // image a translation uses stays protected.
    func testSiteTranslationsAreStrictUndoablePersistedAndResolvedPerLanguage() async throws {
        let fixture = try siteTranslationFixture()
        let pageID = fixture.pageID, headingID = fixture.headingID, pictureID = fixture.pictureID
        func translatedNode(_ id: NodeID, in document: CanonicalDocument) throws -> DocumentNode {
            try XCTUnwrap(document.pages.flatMap(\.nodes).first { $0.id == id })
        }
        XCTAssertThrowsError(try SiteTranslationEditing.prepare("Bonjour", field: .text, nodeID: headingID, pageID: pageID,
            localeID: SiteLocaleID(), openingRevision: fixture.document.revision, document: fixture.document,
            isLifecycleAvailable: true)) {
            XCTAssertEqual($0 as? SiteTranslationEditError, .notLocalized)
        }

        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let english = localization.defaultLocaleID
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "Français", to: &localization)
        let canadian = try SiteLocalizationEditing.addLocale(code: "fr-CA", name: "Français (Canada)", to: &localization)
        localization.locales[2].fallbackLocaleID = french.id
        let session = DocumentSession(document: fixture.document)
        let languagesOn = try SiteLocalizationEditing.prepare(localization, openingRevision: session.document.revision,
                                                              document: session.document, isLifecycleAvailable: true)
        XCTAssertEqual(languagesOn.name, .setLocalization, "Without translations a language edit stays one command")
        try session.execute(languagesOn)
        let localized = session.document

        func translating(_ value: String?, _ field: SiteTranslationField = .text, node: NodeID? = nil,
                         locale: SiteLocaleID? = nil, revision: UInt64? = nil, available: Bool = true) throws -> DocumentCommand {
            try SiteTranslationEditing.prepare(value, field: field, nodeID: node ?? headingID, pageID: pageID,
                localeID: locale ?? french.id, openingRevision: revision ?? session.document.revision,
                document: session.document, isLifecycleAvailable: available)
        }
        let refusals: [(SiteTranslationEditError, () throws -> DocumentCommand)] = [
            (.busy, { try translating("Bonjour", available: false) }),
            (.stale, { try translating("Bonjour", revision: session.document.revision + 1) }),
            (.defaultLocale, { try translating("Hi", locale: english) }),
            (.unknownLocale, { try translating("Hi", locale: SiteLocaleID()) }),
            (.unknownNode, { try translating("Hi", node: NodeID()) }),
            (.unsupportedField, { try translating("Couverture", .imageAlt) }),
            (.invalidValue, { try translating("Bad\u{0007}") }),
            (.invalidValue, { try translating(AssetID().description, .imageAssetID, node: pictureID) }),
            (.unchanged, { try translating(nil) }),
        ]
        for (expected, attempt) in refusals {
            XCTAssertThrowsError(try attempt(), expected.category) {
                XCTAssertEqual($0 as? SiteTranslationEditError, expected)
            }
            XCTAssertNotNil(expected.errorDescription)
        }
        XCTAssertEqual(session.document, localized, "Refused translations leave the document unchanged")

        let first = try translating("Bonjour")
        guard case .batch(let grouped) = first else { return XCTFail("A translation is one grouped edit") }
        XCTAssertEqual(grouped.map(\.name), [.setProperty])
        try session.execute(first)
        XCTAssertEqual(Set(session.historySnapshot().undoEntries.map(\.commandName)), [.setLocalization, .batch])
        let heading = try translatedNode(headingID, in: session.document)
        XCTAssertEqual(CanonicalTranslations.value(.text, for: french.id, on: heading), "Bonjour")
        XCTAssertEqual(heading.insertionStringProperty("content.text"), "Hello", "The default language's value stays on the node")
        XCTAssertEqual(heading.insertionProperty(SiteTranslationKey(localeID: french.id, field: .text).rawValue)?.origin, .authored)
        let frenchText = try XCTUnwrap(SiteTranslationResolver.resolve(.text, on: heading, for: french.id, in: localization))
        XCTAssertEqual(frenchText.value, "Bonjour")
        XCTAssertEqual(frenchText.source, .translation)
        let canadianText = try XCTUnwrap(SiteTranslationResolver.resolve(.text, on: heading, for: canadian.id, in: localization))
        XCTAssertEqual(canadianText.value, "Bonjour")
        XCTAssertEqual(canadianText.source, .fallback)
        XCTAssertEqual(canadianText.sourceLocaleID, french.id)
        XCTAssertFalse(canadianText.explanation.contains("Bonjour"))
        let englishText = try XCTUnwrap(SiteTranslationResolver.resolve(.text, on: heading, for: english, in: localization))
        XCTAssertEqual(englishText.value, "Hello")
        XCTAssertEqual(englishText.source, .defaultValue)
        XCTAssertTrue(englishText.explanation.contains("own value"), englishText.explanation)
        XCTAssertNil(SiteTranslationResolver.resolve(.imageAlt, on: heading, for: french.id, in: localization),
                     "A Text element has no alternative text")
        XCTAssertNil(SiteTranslationResolver.resolve(.text, on: heading, for: SiteLocaleID(), in: localization))
        XCTAssertThrowsError(try translating("Bonjour")) { XCTAssertEqual($0 as? SiteTranslationEditError, .unchanged) }
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = localized.revision
        XCTAssertEqual(undone, localized)
        try session.redo()
        XCTAssertEqual(CanonicalTranslations.value(.text, for: french.id, on: try translatedNode(headingID, in: session.document)),
                       "Bonjour")

        // Translated images: the asset stays in use and protected.
        try session.execute(translating(fixture.translated.id.description, .imageAssetID, node: pictureID))
        try session.execute(translating("Couverture", .imageAlt, node: pictureID))
        let picture = try translatedNode(pictureID, in: session.document)
        XCTAssertEqual(SiteTranslationResolver.resolve(.imageAssetID, on: picture, for: canadian.id, in: localization)?.value,
                       fixture.translated.id.description)
        XCTAssertEqual(SiteTranslationResolver.resolve(.imageAlt, on: picture, for: english, in: localization)?.value, "Cover")
        XCTAssertTrue(CanonicalTranslations.usesAsset(fixture.translated.id, in: session.document))
        XCTAssertTrue(CanonicalGraphReferences.assets(picture).contains(fixture.translated.id),
                      "Copy and paste carry the image a translation shows")
        XCTAssertFalse(ImageAssetDependencies.unusedAssetIDs(in: session.document).contains(fixture.translated.id))
        guard case .disabled(let reason) = CommandRegistry().availability(
            for: .removeImageAsset(.init(assetID: fixture.translated.id)), in: session.document) else {
            return XCTFail("Deleting an image a translation uses must be refused")
        }
        XCTAssertTrue(reason.contains("translation"), reason)

        // Strict rules.
        let translated = session.document
        XCTAssertNoThrow(try translated.validate())
        func forging(_ key: String, _ value: PropertyValue, on node: NodeID,
                     origin: PropertyOrigin = .authored) throws -> CanonicalDocument {
            var copy = translated
            let pageIndex = try XCTUnwrap(copy.pages.firstIndex { $0.id == pageID })
            let nodeIndex = try XCTUnwrap(copy.pages[pageIndex].nodes.firstIndex { $0.id == node })
            copy.pages[pageIndex].nodes[nodeIndex].properties.append(
                NodeProperty(key: .init(rawValue: key), value: value, origin: origin))
            return copy
        }
        let canadianTextKey = SiteTranslationKey(localeID: canadian.id, field: .text).rawValue
        let forgeries: [(String, CanonicalDocument)] = [
            ("default language", try forging(SiteTranslationKey(localeID: english, field: .text).rawValue, .string("Hi"), on: headingID)),
            ("malformed language", try forging(SiteTranslationKey.namespace + "not-a-language.text", .string("Hi"), on: headingID)),
            ("uppercase language", try forging(SiteTranslationKey.namespace + canadian.id.description.uppercased() + ".text",
                                               .string("Hi"), on: headingID)),
            ("unknown field", try forging(SiteTranslationKey.namespace + canadian.id.description + ".caption", .string("Hi"),
                                          on: headingID)),
            ("wrong element", try forging(SiteTranslationKey(localeID: canadian.id, field: .imageAlt).rawValue, .string("Hi"),
                                          on: headingID)),
            ("defaulted", try forging(canadianTextKey, .string("Hi"), on: headingID, origin: .defaulted)),
            ("not text", try forging(canadianTextKey, .number(1), on: headingID)),
            ("control character", try forging(canadianTextKey, .string("Hi\u{0000}"), on: headingID)),
            ("unknown image", try forging(SiteTranslationKey(localeID: canadian.id, field: .imageAssetID).rawValue,
                                          .string(AssetID().description), on: pictureID)),
        ]
        for (label, forged) in forgeries {
            XCTAssertThrowsError(try forged.validate(), label) {
                XCTAssertEqual($0 as? ModelValidationError, .invalidTranslation, label)
            }
        }
        XCTAssertNoThrow(try forging(canadianTextKey, .string("Allô"), on: headingID).validate())
        let key = SiteTranslationKey(localeID: french.id, field: .imageAssetID)
        XCTAssertEqual(SiteTranslationKey(rawValue: key.rawValue), key)
        XCTAssertNil(SiteTranslationKey(rawValue: "content.text"))
        XCTAssertEqual(SiteTranslationField.fields(for: .image), [.imageAssetID, .imageAlt])
        XCTAssertEqual(SiteTranslationField.fields(for: .button), [.text])
        XCTAssertEqual(SiteTranslationField.fields(for: .frame), [])

        // Save, reopen and persisted history.
        let data = try DocumentSerializer.encode(translated)
        XCTAssertEqual(try DocumentSerializer.decode(data), translated)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(SiteTranslationKey.namespace))
        let store = PersistedHistoryStore()
        let history = try await store.encodeRetained(session.historySnapshot())
        let loaded = try await store.load(from: ProjectPackage(document: session.document,
            optionalMembers: [.init(path: PersistedHistoryStore.memberPath, data: history)]))
        guard case .restored(let snapshot) = loaded else { return XCTFail("Translation history must restore: \(loaded)") }
        XCTAssertEqual(snapshot.undoEntries.map(\.commandName), session.historySnapshot().undoEntries.map(\.commandName))

        let diagnostic = SiteTranslationEditDiagnostic(operation: "set", nodeID: headingID, localeID: french.id, field: .text,
                                                       durationMilliseconds: 3, error: SiteTranslationEditError.stale)
        XCTAssertEqual(diagnostic.requirementID, "SF-1007-002")
        XCTAssertEqual(diagnostic.failureCategory, "stale")
        XCTAssertEqual(diagnostic.nodeIdentifier, headingID.description)
        XCTAssertEqual(diagnostic.localeIdentifier, french.id.description)
        let recorded = String(describing: diagnostic)
        for secret in ["Bonjour", "Hello", "Couverture", "Français"] {
            XCTAssertFalse(recorded.contains(secret), secret)
        }
        XCTAssertEqual(SiteTranslationEditDiagnostic(operation: "clear", nodeID: headingID, localeID: french.id, field: .text,
                                                     durationMilliseconds: 0, error: nil).failureCategory, "none")
    }

    // SF-1007-002/003/004 (OD-038 part 2, ADR-0081): missing translations are
    // reported before publish with the language shown instead; removing a
    // language drops its translations in the same undoable edit (counted
    // first); a new default swaps values without losing text; turning
    // languages off drops every translation; orphans are never shown.
    func testSiteTranslationReportAndLanguageChangesKeepTranslationsConsistent() throws {
        let fixture = try siteTranslationFixture()
        let pageID = fixture.pageID, headingID = fixture.headingID, pictureID = fixture.pictureID
        func translatedNode(_ id: NodeID, in document: CanonicalDocument) throws -> DocumentNode {
            try XCTUnwrap(document.pages.flatMap(\.nodes).first { $0.id == id })
        }
        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let english = localization.defaultLocaleID
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "Français", to: &localization)
        let german = try SiteLocalizationEditing.addLocale(code: "de", name: "Deutsch", to: &localization)
        var document = fixture.document
        document.localization = localization
        XCTAssertNoThrow(try document.validate())
        let session = DocumentSession(document: document)

        let untranslated = SiteTranslationReport.build(session.document)
        XCTAssertEqual(untranslated.translatableCount, 2, "The heading text and the picture's alternative text")
        XCTAssertEqual(untranslated.missingCount(french.id), 2)
        XCTAssertEqual(untranslated.missingCount(german.id), 2)
        XCTAssertEqual(untranslated.missingCount(english), 0, "The default language is never missing")
        XCTAssertEqual(Set(untranslated.gaps.compactMap(\.shownLocaleID)), [english])
        XCTAssertEqual(untranslated.orphanedCount, 0)
        XCTAssertFalse(untranslated.summary.contains("Hello"))
        XCTAssertEqual(SiteTranslationReport.build(fixture.document).gaps, [], "A site without languages has nothing to translate")

        func translate(_ value: String, _ field: SiteTranslationField, node: NodeID, locale: SiteLocaleID) throws {
            try session.execute(SiteTranslationEditing.prepare(value, field: field, nodeID: node, pageID: pageID,
                localeID: locale, openingRevision: session.document.revision, document: session.document,
                isLifecycleAvailable: true))
        }
        try translate("Bonjour", .text, node: headingID, locale: french.id)
        try translate("Couverture", .imageAlt, node: pictureID, locale: french.id)
        try translate("Hallo", .text, node: headingID, locale: german.id)
        let report = SiteTranslationReport.build(session.document)
        XCTAssertEqual(report.missingCount(french.id), 0)
        XCTAssertEqual(report.missingCount(german.id), 1)
        XCTAssertEqual(report.gaps.map(\.field), [.imageAlt])
        XCTAssertEqual(report.gaps.first?.nodeID, pictureID)
        XCTAssertEqual(report.gaps.first?.shownLocaleID, english)
        XCTAssertTrue(report.summary.hasPrefix("1 translation(s) missing"), report.summary)
        let translated = session.document

        // Removing German drops its one translation in the same edit.
        var withoutGerman = localization
        try SiteLocalizationEditing.removeLocale(german.id, from: &withoutGerman)
        XCTAssertEqual(SiteTranslationEditing.droppedTranslationCount(to: withoutGerman, in: session.document), 1)
        let removal = try SiteLocalizationEditing.prepare(withoutGerman, openingRevision: session.document.revision,
                                                          document: session.document, isLifecycleAvailable: true)
        guard case .batch(let removalCommands) = removal else { return XCTFail("Dropping translations is one grouped edit") }
        XCTAssertEqual(removalCommands.map(\.name), [.removeProperty, .setLocalization])
        try session.execute(removal)
        let remaining = try translatedNode(headingID, in: session.document)
        XCTAssertNil(CanonicalTranslations.value(.text, for: german.id, on: remaining))
        XCTAssertEqual(CanonicalTranslations.value(.text, for: french.id, on: remaining), "Bonjour")
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undoneRemoval = session.document; undoneRemoval.revision = translated.revision
        XCTAssertEqual(undoneRemoval, translated)

        // A new default swaps values; nothing is lost and Undo restores both.
        var frenchFirst = localization
        try SiteLocalizationEditing.makeDefault(french.id, in: &frenchFirst)
        XCTAssertEqual(SiteTranslationEditing.droppedTranslationCount(to: frenchFirst, in: session.document), 0)
        try session.execute(SiteLocalizationEditing.prepare(frenchFirst, openingRevision: session.document.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        let swapped = try translatedNode(headingID, in: session.document)
        XCTAssertEqual(swapped.insertionStringProperty("content.text"), "Bonjour")
        XCTAssertEqual(CanonicalTranslations.value(.text, for: english, on: swapped), "Hello")
        XCTAssertNil(CanonicalTranslations.value(.text, for: french.id, on: swapped))
        XCTAssertEqual(CanonicalTranslations.value(.text, for: german.id, on: swapped), "Hallo")
        let swappedPicture = try translatedNode(pictureID, in: session.document)
        XCTAssertEqual(swappedPicture.insertionStringProperty(CanonicalImageStyle.namespace + "alt"), "Couverture")
        XCTAssertEqual(CanonicalTranslations.value(.imageAlt, for: english, on: swappedPicture), "Cover")
        XCTAssertEqual(SiteTranslationResolver.resolve(.text, on: swapped, for: english, in: frenchFirst)?.source, .translation)
        XCTAssertNoThrow(try session.document.validate())
        try session.undo()
        var undoneSwap = session.document; undoneSwap.revision = translated.revision
        XCTAssertEqual(undoneSwap, translated)

        // A new default with the old default removed in the same edit: the new
        // default's translations become the content and nothing stays keyed to it.
        var frenchOnly = frenchFirst
        try SiteLocalizationEditing.removeLocale(english, from: &frenchOnly)
        let replacement = try SiteLocalizationEditing.prepare(frenchOnly, openingRevision: session.document.revision,
                                                              document: session.document, isLifecycleAvailable: true)
        guard case .batch(let replacementCommands) = replacement else { return XCTFail("A new default is one grouped edit") }
        XCTAssertEqual(replacementCommands.map(\.name),
                       [.setProperty, .removeProperty, .setProperty, .removeProperty, .setLocalization])
        try session.execute(replacement)
        let promoted = try translatedNode(headingID, in: session.document)
        XCTAssertEqual(promoted.insertionStringProperty("content.text"), "Bonjour")
        XCTAssertNil(CanonicalTranslations.value(.text, for: french.id, on: promoted))
        XCTAssertNil(CanonicalTranslations.value(.text, for: english, on: promoted))
        XCTAssertEqual(CanonicalTranslations.value(.text, for: german.id, on: promoted), "Hallo")
        XCTAssertEqual(try translatedNode(pictureID, in: session.document)
            .insertionStringProperty(CanonicalImageStyle.namespace + "alt"), "Couverture")
        XCTAssertNoThrow(try session.document.validate())
        try session.undo()
        var undonePromotion = session.document; undonePromotion.revision = translated.revision
        XCTAssertEqual(undonePromotion, translated)

        // Turning languages off drops every translation in one edit.
        XCTAssertEqual(SiteTranslationEditing.droppedTranslationCount(to: nil, in: session.document), 3)
        try session.execute(SiteLocalizationEditing.prepare(nil, openingRevision: session.document.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        XCTAssertNil(session.document.localization)
        XCTAssertTrue(session.document.pages.flatMap(\.nodes).allSatisfy { CanonicalTranslations.translations(on: $0).isEmpty })
        try session.undo()
        var undoneLanguagesOff = session.document; undoneLanguagesOff.revision = translated.revision
        XCTAssertEqual(undoneLanguagesOff, translated)

        // A translation of a language the site no longer has stays openable,
        // is reported and is never shown.
        var orphaned = translated
        let orphanLocale = SiteLocaleID()
        let pageIndex = try XCTUnwrap(orphaned.pages.firstIndex { $0.id == pageID })
        let nodeIndex = try XCTUnwrap(orphaned.pages[pageIndex].nodes.firstIndex { $0.id == headingID })
        orphaned.pages[pageIndex].nodes[nodeIndex].properties.append(NodeProperty(
            key: .init(rawValue: SiteTranslationKey(localeID: orphanLocale, field: .text).rawValue), value: .string("Ciao")))
        XCTAssertNoThrow(try orphaned.validate())
        let orphanReport = SiteTranslationReport.build(orphaned)
        XCTAssertEqual(orphanReport.orphanedCount, 1)
        XCTAssertTrue(orphanReport.summary.contains("no longer has"), orphanReport.summary)
        XCTAssertFalse(orphanReport.summary.contains("Ciao"))
        let orphanHeading = orphaned.pages[pageIndex].nodes[nodeIndex]
        XCTAssertNil(SiteTranslationResolver.resolve(.text, on: orphanHeading, for: orphanLocale, in: localization))
        XCTAssertEqual(SiteTranslationResolver.resolve(.text, on: orphanHeading, for: german.id, in: localization)?.value, "Hallo")
        XCTAssertEqual(SiteTranslationEditing.droppedTranslationCount(to: localization, in: orphaned), 1,
                       "The next language edit drops orphans")
    }

    // SF-1007-002/004/006/008, SF-1506-001 (OD-038 part 4, ADR-0083): the
    // Languages sheet commits its whole draft as one undoable edit, says how
    // many translations an edit removes before it is applied, refuses invalid
    // and stale drafts without changing anything, records sanitized
    // diagnostics, and sits behind its own feature flag.
    func testSiteLanguagesSheetCommitsDraftsUndoablyAndCountsRemovedTranslations() throws {
        let fixture = try siteTranslationFixture()
        let session = DocumentSession(document: fixture.document)
        let shell = WorkspaceShellState(documentSession: session, announcementPoster: AccessibilityAnnouncementPoster { _ in })
        XCTAssertEqual(FeatureFlagRegistry.definition(.siteLanguages)?.requirementIDs, ["SF-1007", "SF-1506"])
        XCTAssertTrue(shell.canEditLanguages)
        XCTAssertFalse(shell.commitLanguages(nil), "Apply without opening Languages is refused")
        XCTAssertEqual(shell.languagesStatus, SiteLocalizationEditError.stale.localizedDescription)
        shell.presentLanguagesEditor()
        XCTAssertTrue(shell.isLanguagesEditorPresented)
        XCTAssertEqual(shell.languagesStatus, "")

        // Turning languages on is one undoable edit.
        var draft = try SiteLocalizationEditing.start(code: "en", name: "English")
        let english = draft.defaultLocaleID
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "Français", to: &draft)
        XCTAssertEqual(shell.languagesDroppedTranslationCount(draft), 0)
        XCTAssertEqual(shell.languagesDroppedTranslationCount(nil), 0, "An unchanged draft removes nothing")
        let blank = session.document
        XCTAssertTrue(shell.commitLanguages(draft))
        XCTAssertEqual(session.document.localization, draft)
        XCTAssertEqual(session.document.pages, blank.pages)
        XCTAssertEqual(shell.languagesStatus, "Languages updated.")
        XCTAssertEqual(shell.lastLanguagesDiagnostic?.failureCategory, "none")
        XCTAssertEqual(shell.lastLanguagesDiagnostic?.localeIdentifiers, [english.description, french.id.description])
        XCTAssertEqual(shell.languagesTranslationReport.missingCount(french.id), 2)
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = blank.revision
        XCTAssertEqual(undone, blank)
        try session.redo()
        XCTAssertEqual(session.document.localization, draft)

        // Removing a language says how many translations go, and Undo restores them.
        try session.execute(SiteTranslationEditing.prepare("Bonjour", field: .text, nodeID: fixture.headingID,
            pageID: fixture.pageID, localeID: french.id, openingRevision: session.document.revision,
            document: session.document, isLifecycleAvailable: true))
        let translated = session.document
        XCTAssertEqual(shell.languagesTranslationReport.missingCount(french.id), 1)
        shell.presentLanguagesEditor()
        var withoutFrench = draft
        try SiteLocalizationEditing.removeLocale(french.id, from: &withoutFrench)
        XCTAssertEqual(shell.languagesDroppedTranslationCount(withoutFrench), 1)
        XCTAssertEqual(shell.languagesDroppedTranslationCount(nil), 1)
        XCTAssertTrue(shell.commitLanguages(withoutFrench))
        XCTAssertEqual(shell.languagesStatus, "Languages updated. 1 translation(s) removed; choose Undo to restore them.")
        XCTAssertTrue(session.document.pages.flatMap(\.nodes).allSatisfy { CanonicalTranslations.translations(on: $0).isEmpty })
        try session.undo()
        var undoneRemoval = session.document; undoneRemoval.revision = translated.revision
        XCTAssertEqual(undoneRemoval, translated, "One Undo restores the language and its translation")
        let restored = session.document

        // Invalid, unchanged and stale drafts change nothing.
        shell.presentLanguagesEditor()
        var duplicate = draft
        duplicate.locales[1].name = "english"
        XCTAssertFalse(shell.commitLanguages(duplicate))
        XCTAssertEqual(shell.languagesStatus,
                       "SF-1007-004: " + SiteLocalizationIssue(kind: .duplicateName, localeID: french.id).message)
        XCTAssertEqual(shell.lastLanguagesDiagnostic?.failureCategory, "invalid")
        XCTAssertEqual(session.document, restored)
        XCTAssertTrue(shell.commitLanguages(draft), "Unchanged languages are not an error")
        XCTAssertEqual(shell.languagesStatus, SiteLocalizationEditError.unchanged.localizedDescription)
        XCTAssertEqual(shell.lastLanguagesDiagnostic?.failureCategory, "unchanged")
        XCTAssertEqual(session.document, restored)
        try session.execute(SiteTranslationEditing.prepare("Salut", field: .text, nodeID: fixture.headingID,
            pageID: fixture.pageID, localeID: french.id, openingRevision: session.document.revision,
            document: session.document, isLifecycleAvailable: true))
        let edited = session.document
        XCTAssertFalse(shell.commitLanguages(nil), "The project changed after Languages opened")
        XCTAssertEqual(shell.languagesStatus, SiteLocalizationEditError.stale.localizedDescription)
        XCTAssertEqual(shell.lastLanguagesDiagnostic?.failureCategory, "stale")
        XCTAssertEqual(session.document, edited)

        // Turning languages off removes every translation in one edit.
        shell.presentLanguagesEditor()
        XCTAssertTrue(shell.commitLanguages(nil))
        XCTAssertNil(session.document.localization)
        XCTAssertEqual(shell.languagesStatus, "Languages turned off. 1 translation(s) removed; choose Undo to restore them.")
        XCTAssertEqual(shell.lastLanguagesDiagnostic?.localeCount, 0)
        try session.undo()
        var undoneLanguagesOff = session.document; undoneLanguagesOff.revision = edited.revision
        XCTAssertEqual(undoneLanguagesOff, edited)
        let heading = try XCTUnwrap(session.document.pages.flatMap(\.nodes).first { $0.id == fixture.headingID })
        XCTAssertEqual(CanonicalTranslations.value(.text, for: french.id, on: heading), "Salut")
    }

    // SF-1007-002/003/004/006/008 (OD-038 part 4b, ADR-0084): the Inspector's
    // Translations section targets one element on a website page while the
    // site has a second language, explains which rule chose each value, saves
    // and clears a translation as one undoable edit each, refuses stale,
    // default-language, unsupported and invalid edits without changing
    // anything, lists the element's missing translations exactly as the
    // project report does, and records diagnostics without values.
    func testSiteTranslationInspectorEditsOneElementUndoablyAndListsItsMissingTranslations() throws {
        let fixture = try siteTranslationFixture()
        let pageID = fixture.pageID, headingID = fixture.headingID, pictureID = fixture.pictureID
        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let english = localization.defaultLocaleID
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "French", to: &localization)
        let canadian = try SiteLocalizationEditing.addLocale(code: "fr-CA", name: "Canadian French", to: &localization)
        let arabic = try SiteLocalizationEditing.addLocale(code: "ar", name: "Arabic", to: &localization)
        localization.locales[2].fallbackLocaleID = french.id
        let session = DocumentSession(document: fixture.document)
        XCTAssertNil(SiteTranslationInspection.target(selectedNodeIDs: [headingID], pageID: pageID, in: session.document),
                     "A site with one language has nothing to translate")
        try session.execute(SiteLocalizationEditing.prepare(localization, openingRevision: session.document.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        let shell = WorkspaceShellState(documentSession: session, announcementPoster: AccessibilityAnnouncementPoster { _ in })
        func inspectedNode(_ id: NodeID) throws -> DocumentNode {
            try XCTUnwrap(session.document.pages.flatMap(\.nodes).first { $0.id == id })
        }
        func reportedGaps(_ id: NodeID) -> [SiteTranslationGap] {
            SiteTranslationReport.build(session.document).gaps.filter { $0.kind == .missing && $0.nodeID == id }
        }

        // One element of a translatable kind on a website page.
        let heading = try inspectedNode(headingID)
        XCTAssertEqual(SiteTranslationInspection.target(selectedNodeIDs: [headingID], pageID: pageID, in: session.document),
                       SiteTranslationInspectorTarget(pageID: pageID, node: heading))
        XCTAssertNil(SiteTranslationInspection.target(selectedNodeIDs: [headingID, pictureID], pageID: pageID, in: session.document))
        XCTAssertNil(SiteTranslationInspection.target(selectedNodeIDs: [], pageID: pageID, in: session.document))
        XCTAssertNil(SiteTranslationInspection.target(selectedNodeIDs: [headingID], pageID: nil, in: session.document))
        XCTAssertNil(SiteTranslationInspection.target(selectedNodeIDs: [headingID], pageID: PageID(), in: session.document))

        // The language shown: the chosen one while it can be translated, else the first non-default one.
        XCTAssertEqual(SiteTranslationInspection.translatableLocales(localization).map(\.id), [french.id, canadian.id, arabic.id])
        XCTAssertTrue(SiteTranslationInspection.translatableLocales(nil).isEmpty)
        XCTAssertEqual(SiteTranslationInspection.locale(preferred: english, in: localization), french.id,
                       "The default language's value is the element's own content")
        XCTAssertNil(SiteTranslationInspection.locale(preferred: french.id, in: nil))
        XCTAssertEqual(shell.translationInspectorEffectiveLocaleID, french.id)
        shell.translationInspectorLocaleID = arabic.id
        XCTAssertEqual(shell.translationInspectorEffectiveLocaleID, arabic.id)
        XCTAssertTrue(SiteTranslationInspection.isRightToLeft(arabic.id, in: localization), "Arabic is typed right to left")
        XCTAssertFalse(SiteTranslationInspection.isRightToLeft(french.id, in: localization))

        // Each value says which rule chose it; only required values count as missing.
        let pictureRows = SiteTranslationInspection.rows(for: try inspectedNode(pictureID), localeID: french.id, in: localization)
        XCTAssertEqual(pictureRows.map(\.field), [.imageAssetID, .imageAlt])
        XCTAssertEqual(pictureRows.map(\.needsTranslation), [false, true])
        XCTAssertEqual(pictureRows.map(\.isMissing), [false, true])
        XCTAssertEqual(pictureRows[1].resolution.source, .defaultValue)
        XCTAssertEqual(pictureRows[1].resolution.value, "Cover")
        XCTAssertNil(pictureRows[1].translation)
        let headingGaps = SiteTranslationInspection.missingTranslations(on: heading, pageID: pageID, in: localization)
        XCTAssertEqual(headingGaps, reportedGaps(headingID), "The element's list matches the project report")
        XCTAssertEqual(headingGaps.map(\.localeID), [french.id, canadian.id, arabic.id])
        XCTAssertEqual(SiteTranslationInspection.missingSummary(headingGaps, in: localization),
                       "3 translation(s) missing for this element (French, Canadian French, Arabic). "
                       + "Until they are added, a fallback language's value is shown.")
        XCTAssertEqual(SiteTranslationInspection.missingSummary([], in: localization), "This element is translated in every language.")

        // Saving is one undoable edit; a language that falls back to it shows the translation.
        let localized = session.document
        XCTAssertTrue(shell.commitTranslation("Bonjour", field: .text, nodeID: headingID, pageID: pageID, localeID: french.id,
                                              openingRevision: session.document.revision))
        XCTAssertEqual(shell.translationInspectorStatus, "Text translation saved.")
        XCTAssertEqual(shell.lastTranslationInspectorDiagnostic?.operation, "set")
        XCTAssertEqual(shell.lastTranslationInspectorDiagnostic?.failureCategory, "none")
        XCTAssertEqual(shell.lastTranslationInspectorDiagnostic?.nodeIdentifier, headingID.description)
        XCTAssertEqual(shell.lastTranslationInspectorDiagnostic?.localeIdentifier, french.id.description)
        XCTAssertEqual(shell.lastTranslationInspectorDiagnostic?.field, "text")
        XCTAssertFalse(String(describing: shell.lastTranslationInspectorDiagnostic).contains("Bonjour"), "Diagnostics hold no values")
        let translatedHeading = try inspectedNode(headingID)
        let frenchText = try XCTUnwrap(SiteTranslationInspection.rows(for: translatedHeading, localeID: french.id, in: localization).first)
        XCTAssertEqual(frenchText.translation, "Bonjour")
        XCTAssertEqual(frenchText.resolution.source, .translation)
        XCTAssertFalse(frenchText.isMissing)
        let canadianText = try XCTUnwrap(SiteTranslationInspection.rows(for: translatedHeading, localeID: canadian.id,
                                                                        in: localization).first)
        XCTAssertEqual(canadianText.resolution.source, .fallback)
        XCTAssertEqual(canadianText.resolution.value, "Bonjour")
        XCTAssertTrue(canadianText.isMissing)
        let remaining = SiteTranslationInspection.missingTranslations(on: translatedHeading, pageID: pageID, in: localization)
        XCTAssertEqual(remaining, reportedGaps(headingID))
        XCTAssertEqual(remaining.map(\.localeID), [canadian.id, arabic.id])
        XCTAssertEqual(remaining.first?.shownLocaleID, french.id)
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = localized.revision
        XCTAssertEqual(undone, localized)
        try session.redo()
        let translated = session.document
        XCTAssertEqual(CanonicalTranslations.value(.text, for: french.id, on: try inspectedNode(headingID)), "Bonjour")

        // Refused edits change nothing and say why.
        func refusesTranslation(_ value: String?, _ field: SiteTranslationField, node: NodeID, locale: SiteLocaleID,
                                revision: UInt64? = nil, expected: SiteTranslationEditError) {
            let label = expected.category
            XCTAssertFalse(shell.commitTranslation(value, field: field, nodeID: node, pageID: pageID, localeID: locale,
                                                   openingRevision: revision ?? session.document.revision), label)
            XCTAssertEqual(shell.translationInspectorStatus, expected.localizedDescription, label)
            XCTAssertEqual(shell.lastTranslationInspectorDiagnostic?.failureCategory, expected.category, label)
            XCTAssertEqual(session.document, translated, label)
        }
        refusesTranslation("Salut", .text, node: headingID, locale: french.id, revision: translated.revision + 1, expected: .stale)
        refusesTranslation("Hi", .text, node: headingID, locale: english, expected: .defaultLocale)
        refusesTranslation("Salut", .text, node: pictureID, locale: french.id, expected: .unsupportedField)
        refusesTranslation("Bad\u{7}", .text, node: headingID, locale: french.id, expected: .invalidValue)
        refusesTranslation(UUID().uuidString.lowercased(), .imageAssetID, node: pictureID, locale: french.id,
                           expected: .invalidValue)
        refusesTranslation("Salut", .text, node: NodeID(), locale: french.id, expected: .unknownNode)
        refusesTranslation("Salut", .text, node: headingID, locale: SiteLocaleID(), expected: .unknownLocale)
        XCTAssertTrue(shell.commitTranslation("Bonjour", field: .text, nodeID: headingID, pageID: pageID, localeID: french.id,
                                              openingRevision: session.document.revision), "An unchanged translation is not an error")
        XCTAssertEqual(shell.translationInspectorStatus, SiteTranslationEditError.unchanged.localizedDescription)
        XCTAssertEqual(shell.lastTranslationInspectorDiagnostic?.failureCategory, "unchanged")
        XCTAssertEqual(session.document, translated)

        // A translated image is chosen from the project's images; Use Fallback clears it.
        XCTAssertTrue(shell.commitTranslation(fixture.translated.id.description, field: .imageAssetID, nodeID: pictureID,
                                              pageID: pageID, localeID: arabic.id, openingRevision: session.document.revision))
        XCTAssertEqual(shell.translationInspectorStatus, "Image translation saved.")
        let arabicPicture = SiteTranslationInspection.rows(for: try inspectedNode(pictureID), localeID: arabic.id, in: localization)
        XCTAssertEqual(arabicPicture.first?.translation, fixture.translated.id.description)
        XCTAssertEqual(arabicPicture.first?.resolution.source, .translation)
        XCTAssertEqual(arabicPicture.first?.isMissing, false, "Images never count as missing")
        XCTAssertTrue(shell.commitTranslation(nil, field: .imageAssetID, nodeID: pictureID, pageID: pageID, localeID: arabic.id,
                                              openingRevision: session.document.revision))
        XCTAssertEqual(shell.translationInspectorStatus, "Image translation removed; the fallback value is shown again.")
        XCTAssertEqual(shell.lastTranslationInspectorDiagnostic?.operation, "clear")
        XCTAssertEqual(session.document.pages, translated.pages, "Clearing restores the element exactly")
        XCTAssertTrue(shell.commitTranslation(nil, field: .imageAssetID, nodeID: pictureID, pageID: pageID, localeID: arabic.id,
                                              openingRevision: session.document.revision))
        XCTAssertEqual(shell.translationInspectorStatus, SiteTranslationEditError.unchanged.localizedDescription)
        try session.undo()
        XCTAssertEqual(CanonicalTranslations.value(.imageAssetID, for: arabic.id, on: try inspectedNode(pictureID)),
                       fixture.translated.id.description, "Undo restores the cleared translation")
        XCTAssertEqual(FeatureFlagRegistry.definition(.siteLanguages)?.summary.contains("Translations section"), true)
    }

    // SF-1007-002/003/004, SF-1506-003 (OD-038 part 4c, ADR-0086): a right-to-left
    // language mirrors the canvas layout the way `dir="rtl"` does in export:
    // children a Stack lays out run from its right edge; children an unstyled
    // Frame places absolutely keep their offset and move with their parent;
    // page roots, vertical positions and sizes never change; mirroring twice
    // gives the original. Only a shown right-to-left language other than the
    // default mirrors; moving and resizing are refused while it is shown; the
    // document and Undo are untouched; a direction change and Undo follow live.
    func testSiteRightToLeftCanvasLayoutMirrorsLaidOutChildrenLikeExportDirection() throws {
        let layoutPageID = PageID()
        let outerID = NodeID(), rowID = NodeID(), firstID = NodeID(), secondID = NodeID()
        let badgeID = NodeID(), looseID = NodeID(), unplacedID = NodeID()
        let outer = DocumentNode(id: outerID, kind: .frame, name: "Outer", parent: .page(layoutPageID), childIDs: [rowID, looseID])
        let row = DocumentNode(id: rowID, kind: .stack, name: "Row", parent: .node(outerID), childIDs: [firstID, secondID, unplacedID])
        let first = DocumentNode(id: firstID, kind: .text, name: "First", parent: .node(rowID))
        let second = DocumentNode(id: secondID, kind: .frame, name: "Second", parent: .node(rowID), childIDs: [badgeID])
        let badge = DocumentNode(id: badgeID, kind: .text, name: "Badge", parent: .node(secondID))
        let loose = DocumentNode(id: looseID, kind: .text, name: "Loose", parent: .node(outerID))
        let unplaced = DocumentNode(id: unplacedID, kind: .text, name: "Unplaced", parent: .node(rowID))
        let layoutPage = DocumentPage(id: layoutPageID, name: "Layout", route: .init(rawValue: "/layout"), rootNodeIDs: [outerID],
                                      nodes: [outer, row, first, second, badge, loose, unplaced])
        func rtlFrame(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> InsertionGeometry {
            InsertionGeometry(origin: WorldPoint(x: x, y: y), size: WorldSize(width: width, height: height))
        }
        let laidOut: [NodeID: InsertionGeometry] = [
            outerID: rtlFrame(0, 0, 800, 600), rowID: rtlFrame(100, 50, 600, 200),
            firstID: rtlFrame(124, 74, 100, 40), secondID: rtlFrame(248, 74, 100, 40),
            badgeID: rtlFrame(258, 84, 20, 10), looseID: rtlFrame(40, 400, 80, 20),
        ]
        let mirrored = SiteRightToLeftCanvasLayout.mirrored(laidOut, page: layoutPage, breakpoint: .desktop, viewportWidth: 800)
        XCTAssertEqual(mirrored[outerID], laidOut[outerID], "A page root keeps its place on the artboard")
        XCTAssertEqual(mirrored[rowID], laidOut[rowID], "An unstyled Frame places children absolutely, as export's left: does")
        XCTAssertEqual(mirrored[looseID], laidOut[looseID])
        XCTAssertEqual(mirrored[firstID], rtlFrame(576, 74, 100, 40), "The Stack's first child starts at its right edge")
        XCTAssertEqual(mirrored[secondID], rtlFrame(452, 74, 100, 40))
        XCTAssertEqual(mirrored[badgeID], rtlFrame(462, 84, 20, 10), "An absolutely placed child keeps its offset and moves with its parent")
        XCTAssertNil(mirrored[unplacedID], "A node without a frame gets none")
        XCTAssertEqual(mirrored.count, laidOut.count)
        XCTAssertEqual(SiteRightToLeftCanvasLayout.mirrored(mirrored, page: layoutPage, breakpoint: .desktop, viewportWidth: 800),
                       laidOut, "Mirroring twice gives the original layout")
        XCTAssertTrue(SiteRightToLeftCanvasLayout.mirrored([:], page: layoutPage, breakpoint: .desktop, viewportWidth: 800).isEmpty)

        // Only a shown right-to-left language other than the default mirrors.
        let fixture = try siteTranslationFixture()
        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "French", to: &localization)
        let arabic = try SiteLocalizationEditing.addLocale(code: "ar", name: "Arabic", to: &localization)
        XCTAssertFalse(SiteRightToLeftCanvasLayout.isMirrored(showing: nil, in: localization))
        XCTAssertFalse(SiteRightToLeftCanvasLayout.isMirrored(showing: localization.defaultLocaleID, in: localization))
        XCTAssertFalse(SiteRightToLeftCanvasLayout.isMirrored(showing: french.id, in: localization))
        XCTAssertFalse(SiteRightToLeftCanvasLayout.isMirrored(showing: SiteLocaleID(), in: localization))
        XCTAssertFalse(SiteRightToLeftCanvasLayout.isMirrored(showing: arabic.id, in: nil))
        XCTAssertTrue(SiteRightToLeftCanvasLayout.isMirrored(showing: arabic.id, in: localization))
        let session = DocumentSession(document: fixture.document)
        try session.execute(SiteLocalizationEditing.prepare(localization, openingRevision: session.document.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        let committed = session.document
        let undoLabel = session.nextUndoLabel
        let shell = WorkspaceShellState(documentSession: session, announcementPoster: AccessibilityAnnouncementPoster { _ in })
        XCTAssertFalse(shell.canvasMirrorsRightToLeft)
        XCTAssertTrue(shell.showCanvasLanguage(french.id))
        XCTAssertFalse(shell.canvasMirrorsRightToLeft)
        XCTAssertFalse(shell.canvasLanguageStatus.contains("mirrors"))

        // Shown: mirrored, explained, and moving/resizing are refused with the recovery.
        XCTAssertTrue(shell.showCanvasLanguage(arabic.id))
        XCTAssertTrue(shell.canvasMirrorsRightToLeft)
        XCTAssertTrue(shell.canvasLanguageStatus.contains(SiteRightToLeftCanvasLayout.statusNote))
        XCTAssertTrue(shell.canvasLanguageStatus.contains("right to left"))
        XCTAssertFalse(shell.beginPointerTransform(at: WorldPoint(x: 10, y: 10)))
        XCTAssertNotEqual(shell.lastTransformAnnouncement, SiteRightToLeftCanvasLayout.transformRefusal,
                          "A press that would not move or resize the selection is not refused aloud")
        shell.performTransform(.move(delta: WorldVector(dx: 8, dy: 0), constraint: .none), provenance: .keyboard)
        XCTAssertEqual(shell.lastTransformAnnouncement, SiteRightToLeftCanvasLayout.transformRefusal)
        XCTAssertEqual(session.document, committed, "A mirrored canvas never changes the document")
        XCTAssertEqual(session.nextUndoLabel, undoLabel)

        // An authored left-to-right direction stops mirroring; Undo mirrors again.
        var leftToRight = try XCTUnwrap(session.document.localization)
        let arabicIndex = try XCTUnwrap(leftToRight.locales.firstIndex { $0.id == arabic.id })
        leftToRight.locales[arabicIndex].direction = .leftToRight
        try session.execute(SiteLocalizationEditing.prepare(leftToRight, openingRevision: session.document.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        XCTAssertEqual(shell.canvasShownLocaleID, arabic.id)
        XCTAssertFalse(shell.canvasMirrorsRightToLeft)
        XCTAssertFalse(shell.canvasLanguageStatus.contains("mirrors"))
        try session.undo()
        XCTAssertTrue(shell.canvasMirrorsRightToLeft)
        XCTAssertEqual(session.document.localization, committed.localization, "Undo restores the language's direction")
        XCTAssertEqual(session.document.pages, committed.pages)

        // The default language shows the document unmirrored again.
        XCTAssertTrue(shell.showCanvasLanguage(nil))
        XCTAssertFalse(shell.canvasMirrorsRightToLeft)
        XCTAssertEqual(shell.canvasLanguageStatus, "")
    }

    // SF-1007-002/003/008, SF-1506-003 (OD-038 part 4c, ADR-0085): the canvas
    // and Local Preview show any site language exactly as export writes it, as
    // view state only (the document and Undo are untouched); canvas text
    // editing is refused with a recovery; Inspector translations and Undo show
    // live; a removed language falls back to the default and Undo brings it back.
    func testSiteCanvasLanguageShowsALanguageAsExportedWithoutChangingTheDocument() throws {
        let fixture = try siteTranslationFixture()
        let pageID = fixture.pageID, headingID = fixture.headingID, pictureID = fixture.pictureID
        let assetKey = CanonicalImageStyle.namespace + "assetID"
        XCTAssertTrue(SiteCanvasLanguage.options(nil).isEmpty)
        XCTAssertNil(SiteCanvasLanguage.shownLocale(SiteLocaleID(), in: nil))
        XCTAssertEqual(SiteCanvasLanguage.displayedDocument(fixture.document, showing: SiteLocaleID(), in: nil), fixture.document,
                       "A site without languages shows its own document")

        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let english = localization.defaultLocaleID
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "French", to: &localization)
        let canadian = try SiteLocalizationEditing.addLocale(code: "fr-CA", name: "Canadian French", to: &localization)
        let arabic = try SiteLocalizationEditing.addLocale(code: "ar", name: "Arabic", to: &localization)
        localization.locales[2].fallbackLocaleID = french.id
        let session = DocumentSession(document: fixture.document)
        try session.execute(SiteLocalizationEditing.prepare(localization, openingRevision: session.document.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        func canvasTranslate(_ value: String, _ field: SiteTranslationField, node: NodeID, locale: SiteLocaleID) throws {
            try session.execute(SiteTranslationEditing.prepare(value, field: field, nodeID: node, pageID: pageID,
                localeID: locale, openingRevision: session.document.revision, document: session.document,
                isLifecycleAvailable: true))
        }
        try canvasTranslate("Bonjour", .text, node: headingID, locale: french.id)
        try canvasTranslate(fixture.translated.id.description, .imageAssetID, node: pictureID, locale: arabic.id)
        let committed = session.document
        let undoLabel = session.nextUndoLabel
        let shell = WorkspaceShellState(documentSession: session, announcementPoster: AccessibilityAnnouncementPoster { _ in })
        func canvasValue(_ id: NodeID, _ key: String) throws -> String? {
            try XCTUnwrap(shell.canvasDisplayedDocument.pages.flatMap(\.nodes).first { $0.id == id }).insertionStringProperty(key)
        }
        func assertCanvasLanguageLeftDocumentAlone(_ label: String) {
            XCTAssertEqual(session.document, committed, label)
            XCTAssertEqual(session.nextUndoLabel, undoLabel, label)
        }
        let originalPicture = try XCTUnwrap(fixture.document.pages.flatMap(\.nodes).first { $0.id == pictureID })
        let originalAsset = try XCTUnwrap(originalPicture.insertionStringProperty(assetKey))

        // Every language, the default first; the default shows the document itself.
        let options = shell.canvasLanguageOptions
        XCTAssertEqual(options.map(\.id), [english, french.id, canadian.id, arabic.id])
        XCTAssertEqual(options.map(\.isDefault), [true, false, false, false])
        XCTAssertEqual(options.map(\.isRightToLeft), [false, false, false, true])
        XCTAssertNil(shell.canvasShownLocaleID)
        XCTAssertEqual(shell.canvasDisplayedDocument, committed)
        XCTAssertEqual(shell.canvasLanguageStatus, "")
        XCTAssertTrue(shell.showCanvasLanguage(english))
        XCTAssertNil(shell.canvasShownLocaleID, "Choosing the default language shows the document itself")
        XCTAssertEqual(shell.canvasLanguageAnnouncement, "The canvas shows the default language.")

        // Another language shows its translation, else a fallback's, else the default value, as export does.
        XCTAssertTrue(shell.showCanvasLanguage(canadian.id))
        XCTAssertEqual(shell.canvasShownLocaleID, canadian.id)
        XCTAssertEqual(shell.translationInspectorEffectiveLocaleID, canadian.id, "The Translations section follows the canvas")
        XCTAssertEqual(try canvasValue(headingID, "content.text"), "Bonjour", "Canadian French falls back to French")
        XCTAssertEqual(try canvasValue(pictureID, assetKey), originalAsset)
        XCTAssertEqual(shell.canvasDisplayedDocument,
                       SiteLanguageOutput.translatedDocument(committed, to: canadian.id, in: try XCTUnwrap(committed.localization)))
        XCTAssertFalse(shell.canvasDisplayedDocument.pages.flatMap(\.nodes).contains { node in
            node.properties.contains { $0.key.rawValue.hasPrefix(SiteTranslationKey.namespace) }
        }, "The canvas never renders translation properties")
        XCTAssertEqual(SiteTranslationReport.build(committed).missingCount(canadian.id), 2)
        XCTAssertTrue(shell.canvasLanguageStatus.hasPrefix(
            "Showing Canadian French. 2 value(s) are not translated yet and show a fallback language's value."))
        XCTAssertTrue(shell.canvasLanguageStatus.hasSuffix(SiteCanvasLanguage.textEditingRefusal))
        XCTAssertFalse(shell.canvasLanguageStatus.contains("right to left"))
        XCTAssertEqual(shell.canvasLanguageAnnouncement, "The canvas shows Canadian French.")
        XCTAssertEqual(shell.lastCanvasLanguageDiagnostic?.requirementID, "SF-1007-003")
        XCTAssertEqual(shell.lastCanvasLanguageDiagnostic?.operation, "show")
        XCTAssertEqual(shell.lastCanvasLanguageDiagnostic?.localeIdentifier, canadian.id.description)
        XCTAssertEqual(shell.lastCanvasLanguageDiagnostic?.failureCategory, "none")
        XCTAssertFalse(String(describing: shell.lastCanvasLanguageDiagnostic).contains("Canadian"), "Diagnostics hold no names")
        XCTAssertNil(shell.previewLanguageName, "Local Preview captures the language only when it opens or refreshes")
        assertCanvasLanguageLeftDocumentAlone("Showing a language is view state only")

        // Canvas text editing is refused with a recovery; nothing changes.
        XCTAssertFalse(shell.beginTextEditing(nodeID: headingID, provenance: .keyboard))
        XCTAssertFalse(shell.textEditingSession.isActive)
        XCTAssertEqual(shell.lastTextEditingAnnouncement, SiteCanvasLanguage.textEditingRefusal)
        assertCanvasLanguageLeftDocumentAlone("Refused canvas text editing")

        // A right-to-left language with a translated image; Inspector edits and Undo show live.
        XCTAssertTrue(shell.showCanvasLanguage(arabic.id))
        XCTAssertEqual(try canvasValue(pictureID, assetKey), fixture.translated.id.description)
        XCTAssertEqual(try canvasValue(headingID, "content.text"), "Hello", "Untranslated text shows the default value")
        XCTAssertTrue(shell.canvasLanguageStatus.contains("right to left"))
        XCTAssertTrue(shell.commitTranslation("مرحبا", field: .text, nodeID: headingID, pageID: pageID, localeID: arabic.id,
                                              openingRevision: session.document.revision))
        XCTAssertEqual(try canvasValue(headingID, "content.text"), "مرحبا")
        try session.undo()
        XCTAssertEqual(try canvasValue(headingID, "content.text"), "Hello")
        XCTAssertEqual(session.document.pages, committed.pages, "Undo restores the committed content")

        // An unknown language is refused and the shown one stays.
        XCTAssertFalse(shell.showCanvasLanguage(SiteLocaleID()))
        XCTAssertEqual(shell.canvasShownLocaleID, arabic.id)
        XCTAssertEqual(shell.canvasLanguageAnnouncement, SiteLocalizationEditError.unknownLocale.localizedDescription)
        XCTAssertEqual(shell.lastCanvasLanguageDiagnostic?.failureCategory, "unknown-locale")
        XCTAssertNil(shell.lastCanvasLanguageDiagnostic?.localeIdentifier)

        // Removing the shown language shows the default again; Undo brings it back.
        var withoutArabic = try XCTUnwrap(session.document.localization)
        try SiteLocalizationEditing.removeLocale(arabic.id, from: &withoutArabic)
        try session.execute(SiteLocalizationEditing.prepare(withoutArabic, openingRevision: session.document.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        XCTAssertNil(shell.canvasShownLocaleID)
        XCTAssertEqual(shell.canvasDisplayedDocument, session.document)
        XCTAssertEqual(shell.canvasLanguageStatus, "")
        try session.undo()
        XCTAssertEqual(shell.canvasShownLocaleID, arabic.id, "Undo brings the language and the view back")
        XCTAssertEqual(try canvasValue(pictureID, assetKey), fixture.translated.id.description)
        XCTAssertTrue(shell.showCanvasLanguage(nil))
        XCTAssertNil(shell.canvasShownLocaleID)
        XCTAssertEqual(shell.canvasDisplayedDocument, session.document)
        XCTAssertEqual(FeatureFlagRegistry.definition(.siteLanguages)?.summary.contains("canvas and Local Preview"), true)
    }

    // SF-1007-002/003/007/008, SF-1506-003 (OD-038, ADR-0087): a right-to-left
    // default language mirrors the canvas only while Mirror Layout is on (view
    // state; moving, resizing and canvas text editing refused with the
    // recovery); text keeps the alignment export writes; the scene worker
    // translates for the shown language; the canvas status follows every
    // revision; Website Preview opens the shown language's address; the
    // Geometry Inspector says a computed X is mirrored.
    func testSiteRightToLeftDefaultMirrorsOnRequestKeepsExportedAlignmentAndOpensPreviewInTheShownLanguage() async throws {
        let fixture = try siteTranslationFixture()
        let pageID = fixture.pageID, headingID = fixture.headingID
        var localization = try SiteLocalizationEditing.start(code: "ar", name: "Arabic")
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "French", to: &localization)
        XCTAssertTrue(SiteRightToLeftCanvasLayout.defaultReadsRightToLeft(localization))
        XCTAssertFalse(SiteRightToLeftCanvasLayout.defaultReadsRightToLeft(nil))
        let session = DocumentSession(document: fixture.document)
        try session.execute(SiteLocalizationEditing.prepare(localization, openingRevision: session.document.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        let committed = session.document
        let undoLabel = session.nextUndoLabel
        let shell = WorkspaceShellState(documentSession: session, announcementPoster: AccessibilityAnnouncementPoster { _ in })
        XCTAssertTrue(shell.canvasDefaultReadsRightToLeft)
        XCTAssertFalse(shell.canvasMirrorsRightToLeft, "A right-to-left default is mirrored only on request")
        XCTAssertEqual(shell.canvasLanguageStatus, "")

        // Mirror Layout is view state; moving, resizing and canvas text editing are refused with the recovery.
        XCTAssertTrue(shell.setDefaultLanguageMirroring(true))
        XCTAssertTrue(shell.canvasMirrorsDefaultLanguage)
        XCTAssertTrue(shell.canvasMirrorsRightToLeft)
        XCTAssertEqual(shell.canvasLanguageStatus, SiteRightToLeftCanvasLayout.defaultMirrorStatusNote)
        XCTAssertEqual(shell.lastCanvasLanguageDiagnostic?.operation, "mirror-default")
        XCTAssertEqual(shell.lastCanvasLanguageDiagnostic?.localeIdentifier, localization.defaultLocaleID.description)
        XCTAssertEqual(shell.lastCanvasLanguageDiagnostic?.failureCategory, "none")
        shell.performTransform(.move(delta: WorldVector(dx: 8, dy: 0), constraint: .none), provenance: .keyboard)
        XCTAssertEqual(shell.lastTransformAnnouncement, SiteRightToLeftCanvasLayout.defaultMirrorRefusal)
        XCTAssertFalse(shell.beginTextEditing(nodeID: headingID, provenance: .keyboard))
        XCTAssertFalse(shell.textEditingSession.isActive)
        XCTAssertEqual(shell.lastTextEditingAnnouncement, SiteRightToLeftCanvasLayout.defaultMirrorRefusal)
        XCTAssertEqual(session.document, committed, "Mirror Layout never changes the document")
        XCTAssertEqual(session.nextUndoLabel, undoLabel)

        // A left-to-right language is not mirrored; its status follows every revision.
        XCTAssertTrue(shell.showCanvasLanguage(french.id))
        XCTAssertFalse(shell.canvasMirrorsRightToLeft)
        XCTAssertTrue(shell.canvasLanguageStatus.hasPrefix("Showing French. 2 value(s) are not translated yet"))
        XCTAssertTrue(shell.commitTranslation("Bonjour", field: .text, nodeID: headingID, pageID: pageID, localeID: french.id,
                                              openingRevision: session.document.revision))
        XCTAssertTrue(shell.canvasLanguageStatus.hasPrefix("Showing French. 1 value(s) are not translated yet"))
        try session.undo()
        XCTAssertTrue(shell.canvasLanguageStatus.hasPrefix("Showing French. 2 value(s) are not translated yet"))
        try session.redo()
        XCTAssertTrue(shell.canvasLanguageStatus.hasPrefix("Showing French. 1 value(s) are not translated yet"))

        // Back on the default, Mirror Layout is still on until the author turns it off.
        XCTAssertTrue(shell.showCanvasLanguage(nil))
        XCTAssertTrue(shell.canvasMirrorsRightToLeft)
        XCTAssertTrue(shell.setDefaultLanguageMirroring(false))
        XCTAssertFalse(shell.canvasMirrorsRightToLeft)
        XCTAssertEqual(shell.canvasLanguageStatus, "")
        XCTAssertEqual(shell.lastCanvasLanguageDiagnostic?.operation, "unmirror-default")

        // The worker translates for the shown language (off the main actor). Text
        // keeps the alignment export writes: every text object gets `text-align`
        // (left by default), which `dir="rtl"` does not change, mirrored or not.
        let document = session.document
        let documentLocalization = try XCTUnwrap(document.localization)
        let viewport = try CanvasViewportState(viewportSize: .init(width: 1_000, height: 700),
            contentBounds: .init(origin: .init(x: 0, y: 0), size: .init(width: 1_440, height: 900)), pixelRatio: .init(2))
        let shownRequest = WorkspaceScenePreparationRequest(document: document, activePageID: pageID, activeContainerID: nil,
            viewport: viewport, surfaceID: CanvasRenderSurfaceID(), displayedLocaleID: french.id)
        XCTAssertEqual(shownRequest.displayingShownLanguage().document,
                       SiteLanguageOutput.translatedDocument(document, to: french.id, in: documentLocalization))
        XCTAssertNil(shownRequest.displayingShownLanguage().displayedLocaleID, "A request is translated once")
        let plainRequest = WorkspaceScenePreparationRequest(document: document, activePageID: pageID, activeContainerID: nil,
            viewport: viewport, surfaceID: CanvasRenderSurfaceID())
        XCTAssertEqual(plainRequest.displayingShownLanguage().document, document)
        let shown = try await WorkspaceScenePreparationWorker().prepare(shownRequest)
        let shownHeading = try XCTUnwrap(shown.renderScene.objects.first { $0.id == headingID })
        XCTAssertEqual(shownHeading.plainText, "Bonjour", "The canvas shows the translation export writes")
        XCTAssertEqual(shownHeading.typography?.alignment, .leading)
        let mirrored = try await WorkspaceScenePreparationWorker().prepare(.init(document: document, activePageID: pageID,
            activeContainerID: nil, viewport: viewport, surfaceID: CanvasRenderSurfaceID(), mirrorsLayoutRightToLeft: true))
        let mirroredHeading = try XCTUnwrap(mirrored.renderScene.objects.first { $0.id == headingID })
        let canonicalHeading = try XCTUnwrap(document.pages.flatMap(\.nodes).first { $0.id == headingID })
        XCTAssertEqual(CanonicalTypography.resolved(for: canonicalHeading)?.alignment, .leading,
                       "Export writes this alignment as text-align: left for every text object")
        XCTAssertEqual(mirroredHeading.typography?.alignment, .leading, "A mirrored canvas keeps the exported text alignment")
        XCTAssertEqual(mirroredHeading.plainText, "Hello")

        // Website Preview opens the page in the shown language, at the path export writes it to.
        let page = try XCTUnwrap(document.pages.first { $0.id == pageID })
        let pagePath = try MultiPageStaticBuildPlanner.outputPath(for: page)
        XCTAssertEqual(SiteLanguageOutput.previewPath(pagePath, showing: french.id, in: document), "fr/" + pagePath)
        XCTAssertEqual(SiteLanguageOutput.previewPath(pagePath, showing: localization.defaultLocaleID, in: document), pagePath)
        XCTAssertEqual(SiteLanguageOutput.previewPath(pagePath, showing: nil, in: document), pagePath)
        XCTAssertEqual(SiteLanguageOutput.previewPath(pagePath, showing: SiteLocaleID(), in: document), pagePath)
        XCTAssertEqual(SiteLanguageOutput.previewPath(pagePath, showing: french.id, in: fixture.document), pagePath)
        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        XCTAssertTrue(plan.files.contains { $0.path == "fr/" + pagePath })

        // The Geometry Inspector says a computed X is the mirrored canvas frame.
        XCTAssertEqual(SiteRightToLeftCanvasLayout.computedSource("Computed by responsive layout", field: .x, isMirrored: true),
                       "Computed by responsive layout, mirrored right to left")
        XCTAssertEqual(SiteRightToLeftCanvasLayout.computedSource("Computed by responsive layout", field: .y, isMirrored: true),
                       "Computed by responsive layout")
        XCTAssertEqual(SiteRightToLeftCanvasLayout.computedSource("Computed by responsive layout", field: .x, isMirrored: false),
                       "Computed by responsive layout")

        // A left-to-right default offers no Mirror Layout; asking is refused and changes nothing.
        var english = try SiteLocalizationEditing.start(code: "en", name: "English")
        try SiteLocalizationEditing.addLocale(code: "ar", name: "Arabic", to: &english)
        let leftToRightSession = DocumentSession(document: fixture.document)
        try leftToRightSession.execute(SiteLocalizationEditing.prepare(english, openingRevision: leftToRightSession.document.revision,
                                                                       document: leftToRightSession.document, isLifecycleAvailable: true))
        let leftToRightShell = WorkspaceShellState(documentSession: leftToRightSession,
                                                   announcementPoster: AccessibilityAnnouncementPoster { _ in })
        XCTAssertFalse(leftToRightShell.canvasDefaultReadsRightToLeft)
        XCTAssertFalse(leftToRightShell.setDefaultLanguageMirroring(true))
        XCTAssertFalse(leftToRightShell.canvasMirrorsDefaultLanguage)
        XCTAssertFalse(leftToRightShell.canvasMirrorsRightToLeft)
        XCTAssertEqual(leftToRightShell.lastCanvasLanguageDiagnostic?.operation, "mirror-default")
        XCTAssertEqual(leftToRightShell.lastCanvasLanguageDiagnostic?.failureCategory, "not-right-to-left")
    }

    // SF-1007-002/004, SF-0807-001 (OD-038, ADR-0087): an image a translation
    // shows is a listed use, so Reveal Usage, Replace Everywhere (one undoable
    // step) and delete agree; a paste keeps no translation keyed to the
    // destination's default language; an element of a component definition is
    // translatable in the Inspector.
    func testSiteTranslatedImagesAreListedUsesAndDefinitionsAreTranslatable() throws {
        let fixture = try siteTranslationFixture()
        let pageID = fixture.pageID, pictureID = fixture.pictureID
        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "French", to: &localization)
        let session = DocumentSession(document: fixture.document)
        try session.execute(SiteLocalizationEditing.prepare(localization, openingRevision: session.document.revision,
                                                            document: session.document, isLifecycleAvailable: true))
        XCTAssertTrue(ImageAssetReference.references(to: fixture.translated.id, in: session.document).isEmpty)
        try session.execute(SiteTranslationEditing.prepare(fixture.translated.id.description, field: .imageAssetID,
            nodeID: pictureID, pageID: pageID, localeID: french.id, openingRevision: session.document.revision,
            document: session.document, isLifecycleAvailable: true))
        let references = ImageAssetReference.references(to: fixture.translated.id, in: session.document)
        XCTAssertEqual(references, [ImageAssetReference(kind: .translation, pageID: pageID, nodeID: pictureID)])
        XCTAssertEqual(ImageAssetReference.summary(references), "Translated images: 1")
        XCTAssertFalse(ImageAssetDependencies.unusedAssetIDs(in: session.document).contains(fixture.translated.id))
        let original = try XCTUnwrap(fixture.document.imageAssets.first { $0.id != fixture.translated.id })
        let before = session.document
        let retarget = try ImageAssetDependencies.retarget(from: fixture.translated.id, to: original.id, in: before,
                                                           expectedRevision: before.revision, isLifecycleAvailable: true)
        XCTAssertEqual(retarget.count, references.count, "Replace Everywhere changes exactly the listed uses")
        try session.execute(retarget.command)
        XCTAssertTrue(ImageAssetReference.references(to: fixture.translated.id, in: session.document).isEmpty)
        let picture = try XCTUnwrap(session.document.pages.flatMap(\.nodes).first { $0.id == pictureID })
        XCTAssertEqual(CanonicalTranslations.value(.imageAssetID, for: french.id, on: picture), original.id.description)
        try session.undo()
        XCTAssertEqual(session.document.pages, before.pages)

        // A paste keeps no translation keyed to the destination's default language.
        let defaultKey = SiteTranslationKey(localeID: localization.defaultLocaleID, field: .text).rawValue
        let frenchKey = SiteTranslationKey(localeID: french.id, field: .text).rawValue
        let pastedProperties = [
            NodeProperty(key: .init(rawValue: "content.text"), value: .string("Hello")),
            NodeProperty(key: .init(rawValue: defaultKey), value: .string("Hi"), origin: .authored),
            NodeProperty(key: .init(rawValue: frenchKey), value: .string("Bonjour"), origin: .authored),
        ]
        XCTAssertEqual(SiteTranslationEditing.pastableProperties(pastedProperties, into: localization).map(\.key.rawValue),
                       ["content.text", frenchKey])
        XCTAssertEqual(SiteTranslationEditing.pastableProperties(pastedProperties, into: nil), pastedProperties,
                       "Without languages a paste keeps every translation (reported as orphans)")
        let definitionID = PageID(), titleID = NodeID()
        let definition = DocumentPage(id: definitionID, name: "Card", role: .componentDefinition, rootNodeIDs: [titleID], nodes: [
            DocumentNode(id: titleID, kind: .text, name: "Title", parent: .page(definitionID), properties: pastedProperties)])
        XCTAssertEqual(SiteTranslationEditing.pastablePage(definition, into: localization).nodes[0].properties.map(\.key.rawValue),
                       ["content.text", frenchKey])

        // An element of a component definition is translatable: every instance exports its translations.
        var withDefinition = session.document
        withDefinition.pages.append(SiteTranslationEditing.pastablePage(definition, into: localization))
        XCTAssertEqual(SiteTranslationInspection.target(selectedNodeIDs: [titleID], pageID: definitionID, in: withDefinition)?.node.id,
                       titleID)
    }

    // SF-1007-007 / SF-1506-007 (OD-038, ADR-0087): the translation report, a
    // language's document and the canvas status stay within safety bounds on
    // the standard (about 100 objects) and large (about 10,000 objects) fixtures.
    func testSiteLanguagesStayWithinSafetyBoundsOnStandardAndLargeFixtures() throws {
        let clock = ContinuousClock()
        for (count, bound) in [(100, Duration.seconds(10)), (10_000, .seconds(120))] {
            var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
            let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "French", to: &localization)
            let arabic = try SiteLocalizationEditing.addLocale(code: "ar", name: "Arabic", to: &localization)
            var document = ProjectCreation.blank()
            document.localization = localization
            let baseline = SiteTranslationReport.build(document)
            let root = document.pages[0].rootNodeIDs[0]
            let rootIndex = try XCTUnwrap(document.pages[0].nodes.firstIndex { $0.id == root })
            let frenchKey = PropertyKey(rawValue: SiteTranslationKey(localeID: french.id, field: .text).rawValue)
            for index in 0..<count {
                var properties = [("layout.x", Double(index % 40) * 30), ("layout.y", Double(index / 40) * 30),
                                  ("layout.width", 28.0), ("layout.height", 28.0)]
                    .map { NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1)) }
                properties.append(NodeProperty(key: .init(rawValue: "content.text"), value: .string("Item \(index)")))
                if index.isMultiple(of: 2) {
                    properties.append(NodeProperty(key: frenchKey, value: .string("Element \(index)"), origin: .authored))
                }
                let node = DocumentNode(kind: .text, name: "Item \(index)", parent: .node(root), properties: properties)
                document.pages[0].nodes[rootIndex].childIDs.append(node.id)
                document.pages[0].nodes.append(node)
            }
            let started = clock.now
            let report = SiteTranslationReport.build(document)
            let translated = SiteLanguageOutput.translatedDocument(document, to: french.id, in: localization)
            let status = SiteCanvasLanguage.status(showing: arabic.id, in: document)
            XCTAssertLessThan(started.duration(to: clock.now), bound, "\(count) objects: safety bound only")
            XCTAssertEqual(report.missingCount(french.id), baseline.missingCount(french.id) + count / 2)
            XCTAssertEqual(report.missingCount(arabic.id), baseline.missingCount(arabic.id) + count)
            XCTAssertTrue(status.hasPrefix("Showing Arabic. \(report.missingCount(arabic.id)) value(s) are not translated yet"))
            let translatedNodes = translated.pages.flatMap(\.nodes)
            XCTAssertFalse(translatedNodes.contains { node in
                node.properties.contains { $0.key.rawValue.hasPrefix(SiteTranslationKey.namespace) }
            }, "\(count): no translation property reaches the canvas or export")
            XCTAssertEqual(translatedNodes.first { $0.name == "Item 0" }?.insertionStringProperty("content.text"), "Element 0")
            XCTAssertEqual(translatedNodes.first { $0.name == "Item 1" }?.insertionStringProperty("content.text"), "Item 1")
        }
    }

    // SF-1007-002/003/005, SF-1506-003 (OD-038 part 3, ADR-0082): export writes
    // one tree per language with its translations (or a fallback's), `lang`
    // and `dir`, links and images that work inside the tree, hreflang
    // alternates with x-default, every language in the sitemap and images only
    // a translation shows; missing translations are warned about before
    // export, Undo changes the output back, reopening exports the same files,
    // and a site without languages exports exactly as before.
    func testSiteLanguagesExportOneTreePerLanguageWithAlternatesAndTranslations() throws {
        let fixture = try siteTranslationFixture()
        let pageID = fixture.pageID, headingID = fixture.headingID, pictureID = fixture.pictureID
        func file(_ path: String, in plan: LocalStaticBuildPlan) throws -> String {
            try XCTUnwrap(plan.files.first { $0.path == path }?.contents, path)
        }
        let plain = try MultiPageStaticBuildPlanner.plan(document: fixture.document)
        XCTAssertEqual(SiteLanguageOutput.passes(fixture.document).map(\.pathPrefix), [""])
        XCTAssertTrue(try file("post.html", in: plain).hasPrefix("<!doctype html><html lang=\"en\"><head>"))
        XCTAssertFalse(plain.files.contains { $0.contents.contains("hreflang") || $0.contents.contains(" dir=\"") },
                       "A site without languages exports exactly as before")

        var localization = try SiteLocalizationEditing.start(code: "en", name: "English")
        let french = try SiteLocalizationEditing.addLocale(code: "fr", name: "Français", to: &localization)
        _ = try SiteLocalizationEditing.addLocale(code: "ar", name: "Arabic", to: &localization)
        var document = fixture.document
        document.localization = localization
        try document.validate()
        let session = DocumentSession(document: document)
        func translate(_ value: String, _ field: SiteTranslationField, node: NodeID) throws {
            try session.execute(SiteTranslationEditing.prepare(value, field: field, nodeID: node, pageID: pageID,
                localeID: french.id, openingRevision: session.document.revision, document: session.document,
                isLifecycleAvailable: true))
        }
        try translate("Bonjour", .text, node: headingID)
        try translate(fixture.translated.id.description, .imageAssetID, node: pictureID)
        try translate("Couverture", .imageAlt, node: pictureID)
        let translated = session.document
        XCTAssertEqual(SiteLanguageOutput.passes(translated).map(\.pathPrefix), ["", "fr/", "ar/"])
        XCTAssertEqual(SiteLanguageOutput.passes(translated).map(\.htmlAttributes),
                       [" lang=\"en\" dir=\"ltr\"", " lang=\"fr\" dir=\"ltr\"", " lang=\"ar\" dir=\"rtl\""])

        let entries: [StaticAssetExportEntry] = translated.imageAssets.map {
            .init(resourceID: $0.resourceID, outputPath: "assets/\($0.contentHash).png", sha256: $0.contentHash)
        }
        let plan = try MultiPageStaticBuildPlanner.plan(document: translated, imageOutputEntries: entries)
        XCTAssertTrue(Set(plan.files.map(\.path)).isSuperset(of: ["index.html", "post.html", "404.html", "fr/index.html",
            "fr/post.html", "fr/404.html", "ar/index.html", "ar/post.html", "ar/404.html"]))
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: translated, imageOutputEntries: entries), plan,
                       "Language trees are deterministic")
        let originalPath = "assets/\(fixture.document.imageAssets[0].contentHash).png"
        let translatedPath = "assets/\(fixture.translated.contentHash).png"

        let englishPost = try file("post.html", in: plan)
        XCTAssertTrue(englishPost.hasPrefix("<!doctype html><html lang=\"en\" dir=\"ltr\"><head>"))
        XCTAssertTrue(englishPost.contains(">Hello<"))
        XCTAssertFalse(englishPost.contains("Bonjour"))
        XCTAssertTrue(englishPost.contains(" src=\"\(originalPath)\""))
        let frenchPost = try file("fr/post.html", in: plan)
        XCTAssertTrue(frenchPost.hasPrefix("<!doctype html><html lang=\"fr\" dir=\"ltr\"><head>"))
        XCTAssertTrue(frenchPost.contains(">Bonjour<"))
        XCTAssertFalse(frenchPost.contains(">Hello<"))
        XCTAssertTrue(frenchPost.contains(" src=\"../\(translatedPath)\""), "Images start at the language folder")
        XCTAssertTrue(frenchPost.contains("alt=\"Couverture\""))
        XCTAssertTrue(frenchPost.contains("<link rel=\"canonical\" href=\"/fr/post\">"))
        XCTAssertTrue(frenchPost.contains("<link rel=\"alternate\" hreflang=\"en\" href=\"/post\">"
            + "<link rel=\"alternate\" hreflang=\"fr\" href=\"/fr/post\">"
            + "<link rel=\"alternate\" hreflang=\"ar\" href=\"/ar/post\">"
            + "<link rel=\"alternate\" hreflang=\"x-default\" href=\"/post\">"))
        XCTAssertFalse(frenchPost.contains("href=\"fr/"), "Links inside a language tree are relative to the page")
        XCTAssertFalse(frenchPost.contains(SiteTranslationKey.namespace))
        let arabicPost = try file("ar/post.html", in: plan)
        XCTAssertTrue(arabicPost.hasPrefix("<!doctype html><html lang=\"ar\" dir=\"rtl\"><head>"))
        XCTAssertTrue(arabicPost.contains(">Hello<"), "Untranslated text shows the default language's value")
        XCTAssertTrue(arabicPost.contains("alt=\"Cover\""))
        XCTAssertTrue(arabicPost.contains(" src=\"../\(originalPath)\""))
        XCTAssertTrue(try file("fr/index.html", in: plan).contains("hreflang=\"fr\" href=\"/fr/\""))
        XCTAssertFalse(try file("fr/404.html", in: plan).contains("hreflang"), "Not Found pages have no alternates")

        XCTAssertEqual(SiteLanguageOutput.relativePath(from: ["fr"], to: "fr/index.html"), "index.html")
        XCTAssertEqual(SiteLanguageOutput.relativePath(from: ["fr", "blog"], to: "fr/about.html"), "../about.html")
        XCTAssertEqual(SiteLanguageOutput.relativePath(from: [], to: "about.html"), "about.html")
        XCTAssertEqual(SiteLanguageOutput.relativeRoutes([pageID: "fr/post.html"], from: "fr/blog/post.html"),
                       [pageID: "../post.html"])

        // With the site address: absolute alternates and every language in the sitemap.
        var addressed = translated
        addressed.websiteMetadata = WebsiteMetadata(siteURL: "https://aurora.example")
        try addressed.validate()
        let addressedPlan = try MultiPageStaticBuildPlanner.plan(document: addressed, imageOutputEntries: entries)
        let sitemap = try file("sitemap.xml", in: addressedPlan)
        for address in ["https://aurora.example/", "https://aurora.example/post", "https://aurora.example/fr/",
                        "https://aurora.example/fr/post", "https://aurora.example/ar/", "https://aurora.example/ar/post"] {
            XCTAssertTrue(sitemap.contains("<loc>\(address)</loc>"), address)
        }
        XCTAssertFalse(sitemap.contains("404"), "Not Found pages stay out of the sitemap in every language")
        XCTAssertTrue(try file("ar/post.html", in: addressedPlan)
            .contains("<link rel=\"alternate\" hreflang=\"x-default\" href=\"https://aurora.example/post\">"))

        // Check Website: the image only French shows is written; gaps are warned about.
        var exported = translated
        var descriptors: [ResourceID: ProjectResourceDescriptor] = [:], blobs: [ResourceID: Data] = [:]
        for index in exported.imageAssets.indices {
            let bytes = Data("language-picture-\(index)".utf8)
            exported.imageAssets[index].contentHash = ProjectResourceStore.digest(bytes)
            exported.imageAssets[index].byteCount = bytes.count
            let picture = exported.imageAssets[index]
            descriptors[picture.resourceID] = ProjectResourceDescriptor(id: picture.resourceID, filename: "picture.png",
                mediaType: "image/png", byteCount: bytes.count, sha256: picture.contentHash)
            blobs[picture.resourceID] = bytes
        }
        try exported.validate()
        let compiled = StaticBuildCompiler.compile(document: exported, profileSelection: .init(profile: .development),
                                                   resourceDescriptors: descriptors, resourceData: blobs)
        let compiledPlan = try XCTUnwrap(compiled.plan, "\(compiled.findings.map(\.code))")
        let exportedTranslatedPath = "assets/\(exported.imageAssets[1].contentHash).png"
        XCTAssertTrue(compiledPlan.binaryFiles.contains { $0.path == exportedTranslatedPath },
                      "An image only a translation shows is written with the site")
        XCTAssertTrue(try file("fr/post.html", in: compiledPlan).contains(" src=\"../\(exportedTranslatedPath)\""))
        let missing = compiled.findings.filter { $0.code == "translation-missing" }
        XCTAssertEqual(missing.map(\.outputPath), ["/ar"], "Only Arabic misses translations")
        XCTAssertTrue(missing.allSatisfy { $0.severity == .warning && $0.explanation.hasPrefix("2 value(s)") })
        XCTAssertTrue(compiled.findings.contains { $0.code == "language-alternates-need-site-url" })
        XCTAssertFalse(compiled.findings.contains { $0.explanation.contains("Hello") || $0.explanation.contains("Bonjour") })
        XCTAssertEqual(SiteLanguageOutput.findings(document: fixture.document), [])

        // Reopening exports the same files; Undo and Redo change the output.
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: DocumentSerializer.decode(DocumentSerializer.encode(translated)),
                                                            imageOutputEntries: entries), plan)
        try session.undo()
        try session.undo()
        try session.undo()
        let undoneFrench = try file("fr/post.html", in: MultiPageStaticBuildPlanner.plan(document: session.document,
                                                                                         imageOutputEntries: entries))
        XCTAssertTrue(undoneFrench.contains(">Hello<"), "After Undo French shows the default language's text again")
        XCTAssertTrue(undoneFrench.contains(" src=\"../\(originalPath)\""))
        try session.redo()
        XCTAssertTrue(try file("fr/post.html", in: MultiPageStaticBuildPlanner.plan(document: session.document,
                                                                                    imageOutputEntries: entries)).contains(">Bonjour<"))

        // A page address inside a language's folder is refused before any file is planned.
        var colliding = translated
        colliding.pages.append(DocumentPage(name: "Notes", route: .init(rawValue: "/fr/notes")))
        XCTAssertThrowsError(try MultiPageStaticBuildPlanner.plan(document: colliding)) {
            XCTAssertEqual($0 as? MultiPageStaticBuildError, .invalidDocument)
        }
    }

    // SF-1001-003/004, SF-1002-002/004/008 (OD-035): rules name the broken
    // object, schema changes never discard data silently, bulk actions and
    // search are deterministic, and images used by items stay protected.
    func testCollectionRulesProtectDataAndEditorOperationsAreDeterministic() throws {
        XCTAssertEqual(CollectionField.suggestedKey(for: "Published On", existing: []), "publishedOn")
        XCTAssertEqual(CollectionField.suggestedKey(for: "Title", existing: ["title"]), "title2")
        XCTAssertEqual(CollectionField.suggestedKey(for: "2024", existing: []), "field")
        XCTAssertEqual(CollectionField.suggestedKey(for: "Status", existing: []), "field")
        for invalid in ["", "Title", "1st", "and", "slug", "with space", String(repeating: "a", count: 41)] {
            XCTAssertFalse(CollectionField.isValidKey(invalid), invalid)
        }
        XCTAssertEqual(CollectionSlug.make(from: "Spring Sale — 2026!"), "spring-sale-2026")
        XCTAssertEqual(CollectionSlug.make(from: "Café"), "cafe")
        XCTAssertEqual(CollectionSlug.make(from: "!!!"), "item")
        XCTAssertEqual(CollectionSlug.unique("item", existing: ["item", "item-2"]), "item-3")
        XCTAssertFalse(CollectionSlug.isValid("-a"))
        XCTAssertFalse(CollectionSlug.isValid("a--b"))
        XCTAssertFalse(CollectionSlug.isValid("A"))

        var posts = CollectionEditing.newCollection(in: [], name: "Posts")
        let title = try XCTUnwrap(posts.fields.first)
        let price = try CollectionEditing.addField(label: "Price", type: .number, referencing: nil, to: &posts)
        let body = try CollectionEditing.addField(label: "Body", type: .text, referencing: nil, to: &posts)
        let ready = CollectionItem(slug: "ready", values: [.init(fieldID: title.id, value: .text("Hello world")),
                                                           .init(fieldID: price.id, value: .number(5))])
        let unfinished = CollectionItem(slug: "unfinished", values: [.init(fieldID: body.id, value: .text("Notes"))])
        posts.items = [ready, unfinished]
        XCTAssertEqual(CanonicalCollections.issues([posts]), [])

        func kinds(_ change: (inout ContentCollection) -> Void) -> [CollectionIssue.Kind] {
            var copy = posts
            change(&copy)
            return CanonicalCollections.issues([copy]).map(\.kind)
        }
        XCTAssertEqual(kinds { $0.items[1].status = .published }, [.requiredMissing])
        XCTAssertEqual(kinds { $0.items[1].slug = "ready" }, [.duplicateItemSlug])
        XCTAssertEqual(kinds { $0.items[1].slug = "Not Valid" }, [.itemSlug])
        XCTAssertEqual(kinds { $0.fields[1].key = "title" }, [.duplicateFieldKey])
        XCTAssertEqual(kinds { $0.fields[1].key = "not" }, [.fieldKey])
        XCTAssertEqual(kinds { $0.fields[1].label = " Price" }, [.fieldLabel])
        XCTAssertEqual(kinds { $0.fields[1].referencedCollectionID = $0.id }, [.reference])
        XCTAssertEqual(kinds { $0.items[0].setValue(.text("5"), for: price.id) }, [.valueType])
        XCTAssertEqual(kinds { $0.items[0].setValue(.text("a\u{0}b"), for: body.id) }, [.textTooLong])
        XCTAssertEqual(kinds { $0.items[0].values.append(.init(fieldID: CollectionFieldID(), value: .text("x"))) }.first, .unknownField)
        XCTAssertEqual(kinds { $0.name = "" }, [.name])
        XCTAssertEqual(kinds { $0.slug = "Posts" }, [.slug])
        let issue = try XCTUnwrap(CanonicalCollections.issues([{ var copy = posts; copy.items[1].status = .published; return copy }()]).first)
        XCTAssertEqual(issue.itemID, unfinished.id)
        XCTAssertEqual(issue.fieldID, title.id)
        var twins = posts
        twins.items = []
        XCTAssertEqual(CanonicalCollections.issues([twins, twins]).map(\.kind), [.duplicateIdentity, .duplicateName, .duplicateSlug])

        // Type changes keep data: text ⇄ rich text is free; other changes need an empty field.
        XCTAssertThrowsError(try CollectionEditing.changeType(of: price.id, to: .text, referencing: nil, in: &posts))
        XCTAssertEqual(posts.field(price.id)?.type, .number)
        try CollectionEditing.changeType(of: body.id, to: .richText, referencing: nil, in: &posts)
        XCTAssertEqual(posts.items[1].value(for: body.id), .text("Notes"))
        XCTAssertEqual(CanonicalCollections.itemsWithValue(for: price.id, in: posts), 1)
        var withoutPrice = posts
        CollectionEditing.removeField(price.id, from: &withoutPrice)
        XCTAssertNil(withoutPrice.items[0].value(for: price.id))
        XCTAssertEqual(CanonicalCollections.issues([withoutPrice]), [])

        // Bulk publish, duplicate, search and filter.
        var bulk = posts
        XCTAssertEqual(CollectionEditing.publishReadyDrafts(in: &bulk), 1)
        XCTAssertEqual(bulk.items.map(\.status), [.published, .draft])
        let copy = try XCTUnwrap(CollectionEditing.duplicate(ready.id, in: &bulk))
        XCTAssertEqual(copy.slug, "ready-copy")
        XCTAssertEqual(copy.status, .draft)
        XCTAssertEqual(bulk.items.map(\.slug), ["ready", "ready-copy", "unfinished"])
        XCTAssertEqual(CollectionEditing.items(in: bulk, matching: "WORLD", status: nil).map(\.slug), ["ready", "ready-copy"])
        XCTAssertEqual(CollectionEditing.items(in: bulk, matching: "", status: .published).map(\.slug), ["ready"])
        XCTAssertEqual(CollectionEditing.displayTitle(bulk.items[2], in: bulk), "unfinished")

        // A referenced collection cannot be deleted; the reference field is listed.
        var authors = CollectionEditing.newCollection(in: [posts], name: "Authors")
        authors.items = [CollectionItem(slug: "ada")]
        var library = [authors, posts]
        _ = try CollectionEditing.addField(label: "Author", type: .reference, referencing: authors.id, to: &library[1])
        library[1].items[0].setValue(.reference(authors.items[0].id), for: library[1].fields[3].id)
        XCTAssertEqual(CanonicalCollections.referencesTo(item: authors.items[0].id, in: library), 1)
        XCTAssertThrowsError(try CollectionEditing.removeCollection(authors.id, from: &library))
        CollectionEditing.removeField(library[1].fields[3].id, from: &library[1])
        try CollectionEditing.removeCollection(authors.id, from: &library)
        XCTAssertEqual(library.map(\.name), ["Posts"])

        // Images used only by collection items count as used.
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Cover", originalFilename: "cover.png",
                               format: .png, pixelWidth: 64, pixelHeight: 64, byteCount: 1,
                               contentHash: String(repeating: "c", count: 64))
        var gallery = posts
        let cover = try CollectionEditing.addField(label: "Cover", type: .image, referencing: nil, to: &gallery)
        gallery.items[0].setValue(.image(asset.id), for: cover.id)
        var document = ProjectCreation.blank()
        document.imageAssets = [asset]
        document.collections = [gallery]
        try document.validate()
        XCTAssertTrue(CanonicalCollections.usesAsset(asset.id, in: document.collections))
        XCTAssertEqual(ImageAssetDependencies.unusedAssetIDs(in: document), [])
        guard case .disabled(let reason) = CommandRegistry().availability(for: .removeImageAsset(.init(assetID: asset.id)),
                                                                           in: document) else {
            return XCTFail("Deleting an image a collection item uses must be refused")
        }
        XCTAssertTrue(reason.contains("Collection"))

        let diagnostic = CollectionEditing.diagnostic("apply", collections: [posts], startedAt: Date(),
                                                      error: CollectionEditError.stale)
        XCTAssertEqual(diagnostic.requirementID, "SF-1001-004")
        XCTAssertEqual(diagnostic.failureCategory, "stale")
        XCTAssertEqual(diagnostic.collectionIdentifiers, [posts.id.description])
        XCTAssertEqual(diagnostic.itemCount, 2)
        XCTAssertFalse(String(describing: diagnostic).contains("Hello"))
        XCTAssertFalse(String(describing: diagnostic).contains("Posts"))
    }

    // SF-1003-001/002/004/006 (OD-035): a template page becomes one static
    // page per published item, with bound text escaped and bound pictures;
    // drafts, the template itself and unusable bindings are never written.
    func testCollectionTemplatePageBuildsOneEscapedPagePerPublishedItem() throws {
        func layout(_ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", 0.0), ("layout.y", 0.0), ("layout.width", width), ("layout.height", height)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1), origin: .defaulted)
            }
        }
        func asset(_ character: Character) -> ImageAsset {
            ImageAsset(resourceID: ResourceID(), displayName: "Picture", originalFilename: "picture.png",
                       format: .png, pixelWidth: 20, pixelHeight: 10, byteCount: 1,
                       contentHash: String(repeating: character, count: 64))
        }
        let placeholder = asset("a"), cover = asset("b")
        let templateID = PageID(), headingID = NodeID(), pictureID = NodeID(), staleID = NodeID()
        let heading = DocumentNode(id: headingID, kind: .text, name: "Heading", parent: .page(templateID),
            properties: layout(200, 40) + [.init(key: .init(rawValue: "content.text"), value: .string("Placeholder heading"))])
        let picture = DocumentNode(id: pictureID, kind: .image, name: "Picture", parent: .page(templateID), properties: layout(20, 10) + [
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"), value: .string(placeholder.id.description), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string(ImageFitMode.fit.rawValue), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string("Cover"), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(false), origin: .defaulted),
        ])
        var document = ProjectCreation.blank()
        document.pages.append(DocumentPage(id: templateID, name: "Post", route: .init(rawValue: "/post"),
                                           rootNodeIDs: [headingID, pictureID], nodes: [heading, picture]))
        document.imageAssets = [placeholder, cover]

        var posts = CollectionEditing.newCollection(in: [], name: "Posts")
        let title = try XCTUnwrap(posts.fields.first)
        let coverField = try CollectionEditing.addField(label: "Cover", type: .image, referencing: nil, to: &posts)
        let price = try CollectionEditing.addField(label: "Price", type: .number, referencing: nil, to: &posts)
        var hello = CollectionItem(slug: "hello", status: .published)
        hello.setValue(.text("Hello <World> & co"), for: title.id)
        hello.setValue(.image(cover.id), for: coverField.id)
        hello.setValue(.number(5), for: price.id)
        var second = CollectionItem(slug: "second", status: .published)
        second.setValue(.text("Second"), for: title.id)
        var draft = CollectionItem(slug: "draft")
        draft.setValue(.text("Unfinished"), for: title.id)
        posts.items = [hello, second, draft]

        XCTAssertFalse(CollectionEditing.setTextBinding("title", node: headingID, in: &posts), "No template yet")
        CollectionEditing.setTemplatePage(templateID, in: &posts)
        XCTAssertTrue(CollectionEditing.setTitle("title + \" | Posts\"", in: &posts))
        XCTAssertTrue(CollectionEditing.setTextBinding("upper(title) + \" / \" + text(price ?? 0)", node: headingID, in: &posts))
        XCTAssertFalse(CollectionEditing.setTextBinding("upper(", node: headingID, in: &posts), "Invalid text changes nothing")
        CollectionEditing.setImageBinding(coverField.id, node: pictureID, in: &posts)
        XCTAssertTrue(CollectionEditing.setTextBinding("title", node: staleID, in: &posts))
        let template = try XCTUnwrap(posts.template)
        XCTAssertTrue(template.isStructurallyValid)
        XCTAssertEqual(template.binding(for: headingID, target: .text)?.expression?.source, "upper(title) + \" / \" + text(price ?? 0)")
        XCTAssertEqual(CollectionEditing.bindableNodes(document.pages.last!).map(\.id), [headingID, pictureID])
        document.collections = [posts]
        try document.validate()
        XCTAssertEqual(CollectionTemplates.findings(document).map(\.kind), [.missingNode],
                       "A binding to a removed layer is kept and reported, not dropped")
        XCTAssertEqual(CollectionTemplates.linkTargets(document), [templateID: PageRoute(rawValue: "/posts/hello")])

        let entries: [StaticAssetExportEntry] = [placeholder, cover].map {
            .init(resourceID: $0.resourceID, outputPath: "assets/\($0.contentHash).png", sha256: $0.contentHash)
        }
        let plan = try MultiPageStaticBuildPlanner.plan(document: document, imageOutputEntries: entries)
        let paths = plan.files.map(\.path)
        XCTAssertTrue(paths.contains("posts/hello.html"))
        XCTAssertTrue(paths.contains("posts/second.html"))
        XCTAssertFalse(paths.contains("posts/draft.html"), "Drafts are never written")
        XCTAssertFalse(paths.contains("post.html"), "The template itself is not a page of the site")
        let helloPage = try XCTUnwrap(plan.files.first { $0.path == "posts/hello.html" }?.contents)
        let secondPage = try XCTUnwrap(plan.files.first { $0.path == "posts/second.html" }?.contents)
        XCTAssertTrue(helloPage.contains("HELLO &lt;WORLD&gt; &amp; CO / 5"))
        XCTAssertTrue(helloPage.contains("<title>Hello &lt;World&gt; &amp; co | Posts</title>"))
        XCTAssertTrue(helloPage.contains("assets/\(cover.contentHash).png"))
        XCTAssertFalse(helloPage.contains("assets/\(placeholder.contentHash).png"))
        XCTAssertTrue(secondPage.contains("SECOND / 0"))
        XCTAssertTrue(secondPage.contains("assets/\(placeholder.contentHash).png"), "No item picture keeps the template picture")
        XCTAssertFalse((helloPage + secondPage).contains("Placeholder heading"))
        XCTAssertFalse(plan.files.map(\.contents).joined().contains("Unfinished"))
        let home = try XCTUnwrap(plan.files.first { $0.path == "index.html" }?.contents)
        XCTAssertFalse(home.contains("post.html"), "The template is not listed in generated navigation")
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: document, imageOutputEntries: entries).files.map(\.contents),
                       plan.files.map(\.contents), "Item pages are deterministic")

        // A title set on the template page itself never replaces each item's title.
        var titled = document
        titled.websiteMetadata = WebsiteMetadata(pages: [PageWebsiteMetadata(pageID: templateID, title: "Post template")])
        try titled.validate()
        let titledHello = try XCTUnwrap(try MultiPageStaticBuildPlanner.plan(document: titled, imageOutputEntries: entries)
            .files.first { $0.path == "posts/hello.html" }?.contents)
        XCTAssertTrue(titledHello.contains("<title>Hello &lt;World&gt; &amp; co | Posts</title>"))
        XCTAssertFalse(titledHello.contains("Post template"))

        // Check Website and Preview export a picture that only an item uses.
        let coverBytes = Data("cover-picture".utf8), placeholderBytes = Data("placeholder-picture".utf8)
        var exported = document
        exported.imageAssets[0].contentHash = ProjectResourceStore.digest(placeholderBytes)
        exported.imageAssets[0].byteCount = placeholderBytes.count
        exported.imageAssets[1].contentHash = ProjectResourceStore.digest(coverBytes)
        exported.imageAssets[1].byteCount = coverBytes.count
        try exported.validate()
        var descriptors: [ResourceID: ProjectResourceDescriptor] = [:], blobs: [ResourceID: Data] = [:]
        for (picture, bytes) in zip(exported.imageAssets, [placeholderBytes, coverBytes]) {
            descriptors[picture.resourceID] = ProjectResourceDescriptor(id: picture.resourceID, filename: "picture.png",
                mediaType: "image/png", byteCount: bytes.count, sha256: picture.contentHash)
            blobs[picture.resourceID] = bytes
        }
        let compiled = StaticBuildCompiler.compile(document: exported, profileSelection: .init(profile: .development),
                                                   resourceDescriptors: descriptors, resourceData: blobs)
        let compiledPlan = try XCTUnwrap(compiled.plan, "\(compiled.findings.map(\.code))")
        let coverPath = "assets/\(exported.imageAssets[1].contentHash).png"
        XCTAssertTrue(compiledPlan.binaryFiles.contains { $0.path == coverPath && $0.contents == coverBytes },
                      "The item's own picture is written with the site")
        XCTAssertTrue(try XCTUnwrap(compiledPlan.files.first { $0.path == "posts/hello.html" }?.contents).contains(coverPath))
        // SF-1206-004 (ADR-0121): item pages live in a folder, so their image, link and
        // navigation references start at that folder and every one resolves.
        XCTAssertTrue(try XCTUnwrap(compiledPlan.files.first { $0.path == "posts/hello.html" }?.contents)
            .contains(" src=\"../\(coverPath)\""))
        XCTAssertEqual(StaticOutputReferenceAudit.unresolved(in: compiledPlan), [:])
        XCTAssertFalse(compiled.findings.contains { $0.code == "output-reference-unresolved" }, "\(compiled.findings.map(\.code))")

        // A type error keeps the expression, reports it, and leaves the layer as designed.
        var typo = document
        XCTAssertTrue(CollectionEditing.setTextBinding("upper(headline)", node: headingID, in: &typo.collections[0]))
        let typoFindings = CollectionTemplates.findings(typo)
        XCTAssertTrue(typoFindings.contains { $0.kind == .expression && $0.nodeID == headingID && $0.detail != nil })
        XCTAssertFalse(typoFindings.contains { $0.detail?.contains("Hello") == true }, "Findings never carry item values")
        let typoPlan = try MultiPageStaticBuildPlanner.plan(document: typo, imageOutputEntries: entries)
        XCTAssertTrue(try XCTUnwrap(typoPlan.files.first { $0.path == "posts/hello.html" }?.contents).contains("Placeholder heading"))

        // No published item: no item pages; links to the template are reported.
        var unpublished = document
        for index in unpublished.collections[0].items.indices { unpublished.collections[0].items[index].status = .draft }
        XCTAssertTrue(CollectionTemplates.findings(unpublished).contains { $0.kind == .noPublishedItems })
        XCTAssertFalse(try MultiPageStaticBuildPlanner.plan(document: unpublished).files.contains { $0.path.hasPrefix("posts/") })

        // An item address that another page already uses is reported and refused at build.
        var collided = document
        collided.pages.append(DocumentPage(name: "Taken", route: .init(rawValue: "/posts/hello")))
        XCTAssertTrue(CollectionTemplates.findings(collided).contains { $0.kind == .routeCollision && $0.itemID == hello.id })
        XCTAssertThrowsError(try MultiPageStaticBuildPlanner.plan(document: collided, imageOutputEntries: entries))

        // Home cannot be a template: the page builds as itself.
        var onHome = document
        CollectionEditing.setTemplatePage(onHome.pages[0].id, in: &onHome.collections[0])
        XCTAssertTrue(CollectionTemplates.findings(onHome).contains { $0.kind == .unsupportedPage })
        XCTAssertTrue(try MultiPageStaticBuildPlanner.plan(document: onHome, imageOutputEntries: entries).files.contains { $0.path == "post.html" })

        // Removing the template page keeps the template (and its bindings) and reports it.
        var removed = document
        removed.pages.removeAll { $0.id == templateID }
        try removed.validate()
        XCTAssertEqual(CollectionTemplates.findings(removed).map(\.kind), [.missingPage])
        XCTAssertEqual(removed.collections[0].template, template)
    }

    // SF-1003-001/003/005/008 (OD-035): templates are strict stored records
    // inside their collection, edited as one undoable change, previewed live,
    // and diagnosed without names or values.
    func testCollectionTemplateRecordIsStrictUndoableAndPreviewedLive() throws {
        var document = ProjectCreation.blank()
        let page = DocumentPage(name: "Member", route: .init(rawValue: "/member"))
        document.pages.append(page)
        var team = CollectionEditing.newCollection(in: [], name: "Team")
        let name = try XCTUnwrap(team.fields.first)
        let photo = try CollectionEditing.addField(label: "Photo", type: .image, referencing: nil, to: &team)
        var ada = CollectionItem(slug: "ada", status: .published)
        ada.setValue(.text("Ada"), for: name.id)
        team.items = [ada]
        let nodeA = NodeID(), nodeB = NodeID()
        CollectionEditing.setTemplatePage(page.id, in: &team)
        XCTAssertTrue(CollectionEditing.setTitle("title", in: &team))
        XCTAssertTrue(CollectionEditing.setTextBinding("lower(title)", node: nodeB, in: &team))
        XCTAssertTrue(CollectionEditing.setTextBinding("title", node: nodeA, in: &team))
        CollectionEditing.setImageBinding(photo.id, node: nodeA, in: &team)
        let keys = try XCTUnwrap(team.template).bindings.map { $0.nodeID.description + "/" + $0.target.rawValue }
        XCTAssertEqual(keys, keys.sorted(), "Bindings are kept in a stable order")
        XCTAssertEqual(keys.count, 3)
        XCTAssertTrue(CollectionEditing.setTextBinding("  ", node: nodeB, in: &team), "Empty text removes the binding")
        XCTAssertEqual(team.template?.bindings.count, 2)
        CollectionEditing.setImageBinding(nil, node: nodeA, in: &team)
        XCTAssertEqual(team.template?.bindings.map(\.target), [.text])

        // Live preview uses the first published item; errors name the problem, not values.
        XCTAssertEqual(CollectionEditing.templatePreview("upper(title)", collection: team, collections: [team]).text, "ADA")
        XCTAssertNil(CollectionEditing.templatePreview("", collection: team, collections: [team]).text)
        let broken = CollectionEditing.templatePreview("upper(nickname)", collection: team, collections: [team])
        XCTAssertNil(broken.text)
        XCTAssertNotNil(broken.error)
        XCTAssertFalse(broken.error?.contains("Ada") ?? true)

        // Structural rules.
        var duplicate = team
        duplicate.template?.bindings.append(.text(nodeA, try XCTUnwrap(SiteExpression(source: "title"))))
        XCTAssertEqual(CanonicalCollections.issues([duplicate]).map(\.kind), [.template])
        var other = CollectionEditing.newCollection(in: [team], name: "Alumni")
        CollectionEditing.setTemplatePage(page.id, in: &other)
        XCTAssertEqual(CanonicalCollections.issues([team, other]).map(\.kind), [.duplicateTemplatePage])
        XCTAssertTrue(CanonicalCollections.issues([team]).isEmpty)

        // Choosing another page clears bindings but keeps the title; None removes the template.
        var moved = team
        CollectionEditing.setTemplatePage(document.pages[1].id, in: &moved)
        XCTAssertEqual(moved.template?.bindings, [])
        XCTAssertEqual(moved.template?.title?.source, "title")
        CollectionEditing.setTemplatePage(nil, in: &moved)
        XCTAssertNil(moved.template)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(moved), as: UTF8.self).contains("\"template\""))

        // One undoable change through the Collections command; exact keys on reopen.
        let session = DocumentSession(document: document)
        try session.execute(CollectionEditing.prepare([team], openingRevision: document.revision, document: session.document,
                                                      isLifecycleAvailable: true))
        XCTAssertEqual(session.document.collections.first?.template, team.template)
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = document.revision
        XCTAssertEqual(undone, document)
        try session.redo()
        let data = try DocumentSerializer.encode(session.document)
        XCTAssertEqual(try DocumentSerializer.decode(data), session.document)
        let encoded = try JSONEncoder().encode(team)
        let forgeries: [(String, (inout [String: Any]) -> Void)] = [
            ("unknown template key", { object in
                var template = object["template"] as? [String: Any] ?? [:]; template["layout"] = "grid"; object["template"] = template }),
            ("null title", { object in
                var template = object["template"] as? [String: Any] ?? [:]; template["title"] = NSNull(); object["template"] = template }),
            ("binding with expression and field", { object in
                var template = object["template"] as? [String: Any] ?? [:]
                var bindings = template["bindings"] as? [[String: Any]] ?? []
                bindings[0]["fieldID"] = photo.id.description
                template["bindings"] = bindings; object["template"] = template }),
            ("image binding without a field", { object in
                var template = object["template"] as? [String: Any] ?? [:]
                var bindings = template["bindings"] as? [[String: Any]] ?? []
                bindings[0]["target"] = "image"
                template["bindings"] = bindings; object["template"] = template }),
            ("unknown target", { object in
                var template = object["template"] as? [String: Any] ?? [:]
                var bindings = template["bindings"] as? [[String: Any]] ?? []
                bindings[0]["target"] = "html"
                template["bindings"] = bindings; object["template"] = template }),
        ]
        for (label, change) in forgeries {
            var forged = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            change(&forged)
            XCTAssertThrowsError(try JSONDecoder().decode(ContentCollection.self, from: JSONSerialization.data(withJSONObject: forged)), label)
        }

        // A single item page can be produced on its own (for preview), with the template's identities.
        let itemPage = CollectionTemplates.itemPage(page, collection: team, item: ada, document: session.document)
        XCTAssertEqual(itemPage.id, page.id)
        XCTAssertEqual(itemPage.route, PageRoute(rawValue: "/team/ada"))
        XCTAssertEqual(itemPage.name, "Ada")

        let diagnostic = CollectionTemplates.diagnostic("build", document: session.document, startedAt: Date())
        XCTAssertEqual(diagnostic.requirementID, "SF-1003-001")
        XCTAssertEqual(diagnostic.collectionIdentifiers, [team.id.description])
        XCTAssertEqual(diagnostic.itemCount, 1)
        XCTAssertEqual(diagnostic.failureCategory, "missingNode", "The bound layer is not on the page")
        XCTAssertFalse(String(describing: diagnostic).contains("Ada"))
        XCTAssertFalse(String(describing: diagnostic).contains("Team"))
    }

    // SF-1003-002/003/004/006 (OD-035): a list repeats one layer of a page for
    // every published item (filtered, ordered, limited and split into
    // /page/2… pages), with links to each item's page and Previous/Next layers.
    func testCollectionListRepeatsALayerPerItemFilteredOrderedAndPaginated() throws {
        func property(_ key: String, _ value: PropertyValue) -> NodeProperty {
            .init(key: .init(rawValue: key), value: value, origin: .authored)
        }
        func geometry(_ width: Double, _ height: Double) -> [NodeProperty] {
            [property("layout.x", .number(0)), property("layout.y", .number(0)),
             property("layout.width", .number(width)), property("layout.height", .number(height))]
        }
        func stackLayout(gap: Double) -> [NodeProperty] {
            [property("layout.container.kind", .string("stack")), property("layout.padding", .number(8)),
             property("layout.gap", .number(gap)), property("layout.axis", .string("vertical")),
             property("layout.align", .string("start"))]
        }
        func link(_ id: NodeID, _ label: String, parent: NodeID) -> DocumentNode {
            DocumentNode(id: id, kind: .link, name: label, parent: .node(parent),
                         properties: geometry(160, 24) + [property(CanonicalLinkTarget.labelKey, .string(label))])
        }
        var document = ProjectCreation.blank()
        let blogID = PageID(), rootID = NodeID(), feedID = NodeID(), cardID = NodeID(), headlineID = NodeID()
        let readID = NodeID(), newerID = NodeID(), olderID = NodeID()
        let root = DocumentNode(id: rootID, kind: .frame, name: "Root", parent: .page(blogID), childIDs: [feedID, newerID, olderID])
        let feed = DocumentNode(id: feedID, kind: .stack, name: "Feed", parent: .node(rootID), childIDs: [cardID],
                                properties: geometry(600, 400) + stackLayout(gap: 16))
        let card = DocumentNode(id: cardID, kind: .stack, name: "Card", parent: .node(feedID), childIDs: [headlineID, readID],
                                properties: geometry(560, 120) + stackLayout(gap: 8))
        let headline = DocumentNode(id: headlineID, kind: .text, name: "Headline", parent: .node(cardID),
                                    properties: geometry(500, 40) + [property("content.text", .string("Placeholder headline"))])
        document.pages.append(DocumentPage(id: blogID, name: "Blog", route: .init(rawValue: "/blog"), rootNodeIDs: [rootID],
            nodes: [root, feed, card, headline, link(readID, "Read on", parent: cardID),
                    link(newerID, "Newer posts", parent: rootID), link(olderID, "Older posts", parent: rootID)]))
        let postPage = DocumentPage(name: "Post", route: .init(rawValue: "/post"))
        document.pages.append(postPage)

        var posts = CollectionEditing.newCollection(in: [], name: "Posts")
        let title = try XCTUnwrap(posts.fields.first)
        let rank = try CollectionEditing.addField(label: "Rank", type: .number, referencing: nil, to: &posts)
        func post(_ slug: String, _ name: String, rank value: Double?, status: CollectionItemStatus = .published) -> CollectionItem {
            var item = CollectionItem(slug: slug, status: status)
            item.setValue(.text(name), for: title.id)
            if let value { item.setValue(.number(value), for: rank.id) }
            return item
        }
        posts.items = [post("alpha", "Alpha", rank: 3), post("bravo", "Bravo", rank: 1), post("charlie", "Charlie", rank: nil),
                       post("delta", "Delta", rank: 2, status: .draft), post("echo", "Echo", rank: 2)]
        CollectionEditing.setTemplatePage(postPage.id, in: &posts)

        let blog = try XCTUnwrap(document.pages.first { $0.id == blogID })
        XCTAssertEqual(CollectionEditing.repeatableNodes(blog).map(\.id), [cardID, headlineID, readID])
        XCTAssertEqual(CollectionEditing.listBindableNodes(blog, repeating: cardID).map(\.id), [headlineID, readID])
        XCTAssertEqual(CollectionEditing.paginationNodes(blog, repeating: cardID).map(\.id), [newerID, olderID])
        XCTAssertTrue(CollectionEditing.addList(page: blogID, repeating: cardID, to: &posts))
        XCTAssertFalse(CollectionEditing.addList(page: blogID, repeating: cardID, to: &posts), "One list per repeated layer")
        XCTAssertTrue(CollectionEditing.setListFilter("slug != \"echo\"", list: cardID, in: &posts))
        XCTAssertFalse(CollectionEditing.setListFilter("slug !=", list: cardID, in: &posts), "Invalid text changes nothing")
        XCTAssertTrue(CollectionEditing.setListTextBinding("upper(title)", node: headlineID, list: cardID, in: &posts))
        CollectionEditing.setListLinkBinding(true, node: readID, list: cardID, in: &posts)
        CollectionEditing.updateList(cardID, in: &posts) {
            $0.sortFieldID = rank.id
            $0.pageSize = 2
            $0.previousNodeID = newerID
            $0.nextNodeID = olderID
        }
        let list = try XCTUnwrap(posts.lists.first)
        XCTAssertTrue(list.isStructurallyValid)
        XCTAssertEqual(list.filter?.source, "slug != \"echo\"")
        XCTAssertEqual(list.binding(for: readID, target: .link), CollectionBinding.link(readID))
        document.collections = [posts]
        try document.validate()
        XCTAssertEqual(CollectionLists.findings(document), [])

        // Resolution: published only, then the filter, the order (no value last), the limit and pages.
        let resolution = CollectionEditing.listPreview(list, collection: posts, collections: [posts])
        XCTAssertEqual(resolution.items.map(\.slug), ["bravo", "alpha", "charlie"])
        XCTAssertEqual(resolution.publishedCount, 4)
        XCTAssertEqual(resolution.matchingCount, 3)
        XCTAssertEqual(resolution.pageCount, 2)
        XCTAssertEqual(resolution.items(onPage: 2).map(\.slug), ["charlie"])
        XCTAssertEqual(resolution.items(onPage: 3), [])
        XCTAssertFalse(resolution.explanation.joined().contains("Alpha"), "The explanation names rules and counts, never values")
        var descending = list
        descending.sortDirection = .descending
        XCTAssertEqual(CollectionEditing.listPreview(descending, collection: posts, collections: [posts]).items.map(\.slug),
                       ["alpha", "bravo", "charlie"], "Items without a value stay last in either direction")
        var limited = list
        limited.limit = 1
        XCTAssertEqual(CollectionEditing.listPreview(limited, collection: posts, collections: [posts]).items.map(\.slug), ["bravo"])

        let plan = try MultiPageStaticBuildPlanner.plan(document: document)
        let paths = plan.files.map(\.path)
        XCTAssertTrue(paths.contains("blog.html"))
        XCTAssertTrue(paths.contains("blog/page/2.html"))
        XCTAssertFalse(paths.contains("blog/page/3.html"))
        XCTAssertTrue(paths.contains("posts/bravo.html"))
        let first = try XCTUnwrap(plan.files.first { $0.path == "blog.html" }?.contents)
        let second = try XCTUnwrap(plan.files.first { $0.path == "blog/page/2.html" }?.contents)
        let bravo = try XCTUnwrap(first.range(of: "BRAVO")), alpha = try XCTUnwrap(first.range(of: "ALPHA"))
        XCTAssertLessThan(bravo.lowerBound, alpha.lowerBound, "Lowest rank first")
        XCTAssertFalse(first.contains("CHARLIE"))
        XCTAssertTrue(second.contains("CHARLIE"), second)
        XCTAssertFalse((first + second).contains("Placeholder headline"))
        XCTAssertFalse((first + second).contains("ECHO"), "The filter leaves Echo out")
        XCTAssertFalse((first + second).contains("DELTA"), "Drafts are never listed")
        XCTAssertTrue(first.contains("href=\"posts/bravo.html\""), "Read on opens the item's page: \(first)")
        XCTAssertTrue(first.contains("href=\"blog/page/2.html\""), "Older posts opens page 2")
        XCTAssertFalse(first.contains("Newer posts"), "Page 1 has no newer page, so that layer is left out")
        XCTAssertTrue(second.contains("href=\"../../blog.html\""), "Links from blog/page/ are relative to the page: \(second)")
        XCTAssertTrue(second.contains("href=\"../../posts/charlie.html\""))
        XCTAssertFalse(second.contains("Older posts"), "The last page has no older page")
        let styles = try XCTUnwrap(plan.files.first { $0.path == "styles.css" }?.contents)
        XCTAssertTrue(styles.contains(CanonicalCSSRule.selector(for: CollectionLists.copyID(headlineID, slot: 1))),
                      "A copy is styled like its original")
        XCTAssertEqual(try MultiPageStaticBuildPlanner.plan(document: document).files.map(\.contents), plan.files.map(\.contents),
                       "List pages are deterministic")
        XCTAssertEqual(CollectionLists.linkRoutes(document, pages: document.pages)[CollectionLists.pageLinkID(blogID, number: 2)],
                       PageRoute(rawValue: "/blog/page/2"))
        XCTAssertEqual(CollectionLists.pageRoute(PageRoute(rawValue: "/"), number: 3), PageRoute(rawValue: "/page/3"))

        let diagnostic = CollectionLists.diagnostic("build", document: document, startedAt: Date())
        XCTAssertEqual(diagnostic.requirementID, "SF-1003-002")
        XCTAssertEqual(diagnostic.collectionIdentifiers, [posts.id.description])
        XCTAssertEqual(diagnostic.itemCount, 3)
        XCTAssertEqual(diagnostic.failureCategory, "none")
        XCTAssertFalse(String(describing: diagnostic).contains("Posts"))
        XCTAssertFalse(String(describing: diagnostic).contains("Bravo"))

        // Unusable parts are reported and the page is written as designed.
        func kinds(_ change: (inout CollectionList) -> Void) -> [CollectionTemplateFinding.Kind] {
            var changed = document
            CollectionEditing.updateList(cardID, in: &changed.collections[0], change)
            return CollectionLists.findings(changed).map(\.kind)
        }
        XCTAssertEqual(kinds { $0.filter = SiteExpression(source: "title") }, [.listFilter], "A filter must give True or False")
        XCTAssertEqual(kinds { $0.sortFieldID = CollectionFieldID() }, [.listSortField])
        XCTAssertEqual(kinds { $0.previousNodeID = headlineID }, [.paginationControl], "Previous cannot be inside the repeated layer")
        func listKinds(repeating node: NodeID, on page: PageID) -> [CollectionTemplateFinding.Kind] {
            var changed = document
            changed.collections[0].lists = [CollectionList(pageID: page, repeatedNodeID: node)]
            return CollectionLists.findings(changed).map(\.kind)
        }
        XCTAssertEqual(listKinds(repeating: NodeID(), on: blogID), [.listLayerMissing])
        XCTAssertEqual(listKinds(repeating: feedID, on: blogID), [.listNeedsFlow], "Copies need a Stack or Grid to flow in")
        XCTAssertEqual(listKinds(repeating: cardID, on: postPage.id), [.listPage], "A template page cannot hold a list")
        XCTAssertEqual(listKinds(repeating: cardID, on: PageID()), [.missingPage])
        var overlapping = document
        XCTAssertTrue(CollectionEditing.addList(page: blogID, repeating: headlineID, to: &overlapping.collections[0]))
        XCTAssertEqual(CollectionLists.findings(overlapping).map(\.kind), [.listOverlap])
        var needsFlow = document
        CollectionEditing.removeList(cardID, from: &needsFlow.collections[0])
        XCTAssertTrue(CollectionEditing.addList(page: blogID, repeating: feedID, to: &needsFlow.collections[0]))
        let designed = try XCTUnwrap(try MultiPageStaticBuildPlanner.plan(document: needsFlow).files.first { $0.path == "blog.html" }?.contents)
        XCTAssertTrue(designed.contains("Placeholder headline"), "An unusable list leaves the page as designed")

        // Without a template the layer keeps its own link.
        var untemplated = document
        CollectionEditing.setTemplatePage(nil, in: &untemplated.collections[0])
        XCTAssertEqual(CollectionLists.findings(untemplated).map(\.kind), [.noItemPages])
        let plain = try XCTUnwrap(try MultiPageStaticBuildPlanner.plan(document: untemplated).files.first { $0.path == "blog.html" }?.contents)
        XCTAssertTrue(plain.contains("BRAVO"))
        XCTAssertFalse(plain.contains("posts/"))

        // A later page whose address is taken is reported and refused at build.
        var collided = document
        collided.pages.append(DocumentPage(name: "Taken", route: .init(rawValue: "/blog/page/2")))
        XCTAssertTrue(CollectionLists.findings(collided).contains { $0.kind == .routeCollision && $0.listID == cardID })
        XCTAssertThrowsError(try MultiPageStaticBuildPlanner.plan(document: collided))

        // No published item: one page, no copies, no Previous or Next.
        var empty = document
        for index in empty.collections[0].items.indices { empty.collections[0].items[index].status = .draft }
        let emptyPlan = try MultiPageStaticBuildPlanner.plan(document: empty)
        XCTAssertFalse(emptyPlan.files.contains { $0.path.hasPrefix("blog/") })
        let emptyBlog = try XCTUnwrap(emptyPlan.files.first { $0.path == "blog.html" }?.contents)
        XCTAssertFalse(emptyBlog.contains("Placeholder headline"))
        XCTAssertFalse(emptyBlog.contains("Older posts") || emptyBlog.contains("Newer posts"))
    }

    // SF-1003-001/005 (OD-035): lists are strict stored records inside their
    // collection (omitted when there are none, refused when malformed) and
    // change through the one undoable Collections command.
    func testCollectionListRecordIsStrictBoundedAndUndoable() throws {
        var document = ProjectCreation.blank()
        let page = DocumentPage(name: "Shop", route: .init(rawValue: "/shop"))
        document.pages.append(page)
        var products = CollectionEditing.newCollection(in: [], name: "Products")
        let titleField = try XCTUnwrap(products.fields.first)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(products), as: UTF8.self).contains("\"lists\""),
                       "No lists: the key is omitted")
        let cardA = NodeID(), cardB = NodeID(), text = NodeID(), more = NodeID()
        XCTAssertTrue(CollectionEditing.addList(page: page.id, repeating: cardA, to: &products))
        XCTAssertEqual(products.lists.first?.pageSize, CollectionList.defaultPageSize)
        XCTAssertEqual(products.lists.first?.sortDirection, .ascending)
        XCTAssertTrue(CollectionEditing.setListTextBinding("title", node: text, list: cardA, in: &products))
        CollectionEditing.setListLinkBinding(true, node: more, list: cardA, in: &products)
        CollectionEditing.setListLinkBinding(true, node: text, list: cardA, in: &products)
        let keys = try XCTUnwrap(products.lists.first).bindings.map { $0.nodeID.description + "/" + $0.target.rawValue }
        XCTAssertEqual(keys, keys.sorted(), "Bindings are kept in a stable order")
        XCTAssertEqual(keys.count, 3)
        CollectionEditing.setListLinkBinding(false, node: text, list: cardA, in: &products)
        XCTAssertTrue(CollectionEditing.setListTextBinding(" ", node: text, list: cardA, in: &products), "Empty text removes the binding")
        XCTAssertEqual(products.lists.first?.bindings, [CollectionBinding.link(more)])
        XCTAssertFalse(CollectionEditing.setListFilter("title", list: cardB, in: &products), "Unknown list")
        XCTAssertFalse(CollectionEditing.setListTextBinding("title", node: text, list: cardB, in: &products))
        XCTAssertTrue(CanonicalCollections.issues([products]).isEmpty)

        let broken: [(String, (inout CollectionList) -> Void)] = [
            ("no items per page", { $0.pageSize = 0 }),
            ("too many per page", { $0.pageSize = CollectionList.maximumPageSize + 1 }),
            ("zero limit", { $0.limit = 0 }),
            ("previous is next", { list in list.previousNodeID = more; list.nextNodeID = more }),
            ("previous is the repeated layer", { $0.previousNodeID = cardA }),
            ("binding without its expression", { $0.bindings.append(CollectionBinding(nodeID: cardB, target: .text)) }),
        ]
        for (label, change) in broken {
            var candidate = products
            CollectionEditing.updateList(cardA, in: &candidate, change)
            XCTAssertEqual(CanonicalCollections.issues([candidate]).map(\.kind), [.list], label)
        }
        var crowded = products
        for _ in 1..<CollectionList.maximumListsPerCollection {
            XCTAssertTrue(CollectionEditing.addList(page: page.id, repeating: NodeID(), to: &crowded))
        }
        XCTAssertFalse(CollectionEditing.addList(page: page.id, repeating: NodeID(), to: &crowded), "At most 16 lists")
        crowded.lists.append(CollectionList(pageID: page.id, repeatedNodeID: NodeID()))
        XCTAssertEqual(CanonicalCollections.issues([crowded]).map(\.kind), [.list])
        var offers = CollectionEditing.newCollection(in: [products], name: "Offers")
        XCTAssertTrue(CollectionEditing.addList(page: page.id, repeating: cardA, to: &offers))
        XCTAssertEqual(CanonicalCollections.issues([products, offers]).map(\.kind), [.duplicateListLayer])

        // Every optional value set, then exact keys on reopen.
        CollectionEditing.updateList(cardA, in: &products) {
            $0.filter = SiteExpression(source: "slug != \"sold-out\"")
            $0.sortFieldID = titleField.id
            $0.sortDirection = .descending
            $0.limit = 50
            $0.pageSize = 10
            $0.previousNodeID = NodeID()
            $0.nextNodeID = NodeID()
        }
        XCTAssertTrue(CanonicalCollections.issues([products]).isEmpty)
        let encoded = try JSONEncoder().encode(products)
        XCTAssertEqual(try JSONDecoder().decode(ContentCollection.self, from: encoded), products)
        func changingList(_ change: @escaping (inout [String: Any]) -> Void) -> (inout [String: Any]) -> Void {
            { object in
                var lists = object["lists"] as? [[String: Any]] ?? []
                change(&lists[0])
                object["lists"] = lists
            }
        }
        let forgeries: [(String, (inout [String: Any]) -> Void)] = [
            ("empty lists stored", { $0["lists"] = [Any]() }),
            ("null lists", { $0["lists"] = NSNull() }),
            ("unknown list key", changingList { $0["layout"] = "grid" }),
            ("null filter", changingList { $0["filter"] = NSNull() }),
            ("null limit", changingList { $0["limit"] = NSNull() }),
            ("missing items per page", changingList { $0["pageSize"] = nil }),
            ("unknown direction", changingList { $0["sortDirection"] = "random" }),
            ("link binding with an expression", changingList { list in
                var bindings = list["bindings"] as? [[String: Any]] ?? []
                bindings[0]["expression"] = list["filter"] ?? NSNull()
                list["bindings"] = bindings }),
        ]
        for (label, change) in forgeries {
            var forged = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            change(&forged)
            XCTAssertThrowsError(try JSONDecoder().decode(ContentCollection.self, from: JSONSerialization.data(withJSONObject: forged)), label)
        }

        // One undoable change through the Collections command.
        let session = DocumentSession(document: document)
        try session.execute(CollectionEditing.prepare([products], openingRevision: document.revision, document: session.document,
                                                      isLifecycleAvailable: true))
        XCTAssertEqual(session.document.collections.first?.lists, products.lists)
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = document.revision
        XCTAssertEqual(undone, document)
        try session.redo()
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)
        XCTAssertEqual(CollectionLists.findings(session.document).map(\.kind), [.listLayerMissing],
                       "A list whose layer is gone is kept and reported")
        XCTAssertEqual(session.document.collections.first?.lists, products.lists)
        XCTAssertTrue(try MultiPageStaticBuildPlanner.plan(document: session.document).files.contains { $0.path == "shop.html" })

        var removed = products
        CollectionEditing.removeList(cardA, from: &removed)
        XCTAssertEqual(removed.lists, [])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(removed), as: UTF8.self).contains("\"lists\""))
    }

    // SF-1005-001/002/003/005/007/008 (OD-037, ADR-0073): a local CSV or JSON
    // file becomes collection items: RFC 4180 quoting, columns matched to
    // fields, every row type-checked, updates by address, new items as drafts,
    // and the result applied as one undoable Collections change.
    func testCollectionImportReadsCSVAndJSONMapsFieldsAndChecksEveryRow() throws {
        var authors = CollectionEditing.newCollection(in: [], name: "Authors")
        let ada = CollectionItem(slug: "ada")
        authors.items = [ada]
        var posts = CollectionEditing.newCollection(in: [authors], name: "Posts")
        let title = try XCTUnwrap(posts.fields.first)
        let price = try CollectionEditing.addField(label: "Price", type: .number, referencing: nil, to: &posts)
        let published = try CollectionEditing.addField(label: "Published On", type: .date, referencing: nil, to: &posts)
        let body = try CollectionEditing.addField(label: "Body", type: .richText, referencing: nil, to: &posts)
        let cover = try CollectionEditing.addField(label: "Cover", type: .image, referencing: nil, to: &posts)
        let author = try CollectionEditing.addField(label: "Author", type: .reference, referencing: authors.id, to: &posts)
        var hello = CollectionItem(slug: "hello", status: .published)
        hello.setValue(.text("Old title"), for: title.id)
        hello.setValue(.number(1), for: price.id)
        posts.items = [hello]
        let asset = ImageAsset(resourceID: ResourceID(), displayName: "Cover Art", originalFilename: "cover.png",
                               format: .png, pixelWidth: 64, pixelHeight: 64, byteCount: 1,
                               contentHash: String(repeating: "c", count: 64))

        let csv = "\u{FEFF}Title,Price,Published On,Body,Cover,Author,Slug\r\n"
            + "\"Hello, again\",\"12.5\",2026-11-26,\"Line one\r\nLine \"\"two\"\"\",COVER.PNG,ada,hello\r\n"
            + "Spring Sale,1e2,,,,,\r\n"
            + "\r\n"
            + "Broken,twelve,2026-02-30,,missing.png,nobody,Not An Address\r\n"
            + "Second copy,3,,,,,hello\n"
        let table = try CollectionImport.parse(Data(csv.utf8), format: .csv)
        XCTAssertEqual(table.columns, ["Title", "Price", "Published On", "Body", "Cover", "Author", "Slug"],
                       "The byte order mark is not part of the first column name")
        XCTAssertEqual(table.rows.count, 4, "Blank lines are ignored")
        XCTAssertEqual(table.rows[0][0], "Hello, again")
        XCTAssertEqual(table.rows[0][3], "Line one\nLine \"two\"", "Quoted line breaks are kept as LF and doubled quotes are one quote")
        XCTAssertEqual(table.rows[1], ["Spring Sale", "1e2", "", "", "", "", ""])

        let mapping = CollectionImport.suggestedMapping(table, for: posts)
        XCTAssertEqual(mapping.fields, [0: title.id, 1: price.id, 2: published.id, 3: body.id, 4: cover.id, 5: author.id])
        XCTAssertEqual(mapping.slugColumn, 6)
        XCTAssertEqual(mapping.newItemStatus, .draft, "Imported items are reviewed before they are published")
        XCTAssertTrue(mapping.updatesMatchingItems)

        let preview = try CollectionImport.preview(table, mapping: mapping, into: posts, collections: [authors, posts], assets: [asset])
        XCTAssertEqual([preview.added, preview.updated, preview.skipped, preview.keptAsDraft], [1, 1, 2, 0])
        XCTAssertEqual(preview.summary, "Adds 1 item, updates 1, skips 2 rows.")
        XCTAssertEqual(preview.problems.map(\.kind), [.number, .date, .image, .reference, .slug, .duplicateSlug])
        XCTAssertEqual(preview.problems.map(\.row), [3, 3, 3, 3, 3, 4])
        XCTAssertEqual(preview.problems.map(\.column), [1, 2, 4, 5, 6, 6])
        XCTAssertEqual(preview.problems[0].message,
                       "Row 3, column 2: not a number (use digits, an optional minus sign and a decimal point). The row is skipped.")
        XCTAssertFalse(preview.problems.map(\.message).joined().contains("twelve"), "Problems never carry cell values")
        let updated = try XCTUnwrap(preview.collection.items.first { $0.slug == "hello" })
        XCTAssertEqual(updated.id, hello.id, "An update keeps the item's identity")
        XCTAssertEqual(updated.status, .published, "An update keeps the item's status")
        XCTAssertEqual(updated.value(for: title.id), .text("Hello, again"))
        XCTAssertEqual(updated.value(for: price.id), .number(12.5))
        XCTAssertEqual(updated.value(for: published.id), .date(try XCTUnwrap(SiteExpressionDate(iso: "2026-11-26"))))
        XCTAssertEqual(updated.value(for: body.id), .text("Line one\nLine \"two\""))
        XCTAssertEqual(updated.value(for: cover.id), .image(asset.id), "Images match their file name ignoring case")
        XCTAssertEqual(updated.value(for: author.id), .reference(ada.id), "References match the item's address")
        let added = try XCTUnwrap(preview.collection.items.last)
        XCTAssertEqual(added.slug, "spring-sale", "An empty address cell makes one from the title")
        XCTAssertEqual(added.status, .draft)
        XCTAssertEqual(added.value(for: price.id), .number(100))
        XCTAssertNil(added.value(for: published.id))
        XCTAssertEqual(CanonicalCollections.issues([authors, preview.collection]), [])
        XCTAssertEqual(posts.items, [hello], "A preview never changes the collection it reads")

        // An empty cell clears a value; a missing JSON key or null keeps it.
        let clearing = try CollectionImport.parseCSV("slug,price\nhello,\n")
        let cleared = try CollectionImport.preview(clearing, mapping: CollectionImport.suggestedMapping(clearing, for: preview.collection),
                                                   into: preview.collection, collections: [authors], assets: [asset])
        XCTAssertNil(cleared.collection.items.first { $0.slug == "hello" }?.value(for: price.id))
        let json = Data(#"[{"title":"From JSON","price":7,"featured":true,"slug":"from-json"},{"title":"Nulls keep values","price":null,"slug":"hello"}]"#.utf8)
        let jsonTable = try CollectionImport.parse(json, format: .json)
        XCTAssertEqual(jsonTable.columns, ["featured", "price", "slug", "title"], "Columns are sorted, whatever the key order")
        XCTAssertEqual(jsonTable.rows[0], ["true", "7", "from-json", "From JSON"])
        XCTAssertEqual(jsonTable.rows[1], [nil, nil, "hello", "Nulls keep values"])
        var publishing = CollectionImport.suggestedMapping(jsonTable, for: preview.collection)
        XCTAssertEqual(publishing.fields, [1: price.id, 3: title.id], "A column without a matching field is skipped")
        XCTAssertEqual(publishing.slugColumn, 2)
        publishing.newItemStatus = .published
        let jsonPreview = try CollectionImport.preview(jsonTable, mapping: publishing, into: preview.collection,
                                                       collections: [authors], assets: [asset])
        XCTAssertEqual([jsonPreview.added, jsonPreview.updated, jsonPreview.skipped], [1, 1, 0])
        XCTAssertEqual(jsonPreview.collection.items.first { $0.slug == "hello" }?.value(for: price.id), .number(12.5))
        XCTAssertEqual(jsonPreview.collection.items.first { $0.slug == "hello" }?.value(for: title.id), .text("Nulls keep values"))
        XCTAssertEqual(jsonPreview.collection.items.first { $0.slug == "from-json" }?.status, .published)

        // Published new items without a required value stay drafts; a published item is never emptied.
        let untitled = try CollectionImport.parseCSV("Price\n4\n")
        var publishUntitled = CollectionImport.suggestedMapping(untitled, for: posts)
        publishUntitled.newItemStatus = .published
        let draftPreview = try CollectionImport.preview(untitled, mapping: publishUntitled, into: posts, collections: [authors], assets: [])
        XCTAssertEqual(draftPreview.keptAsDraft, 1)
        XCTAssertEqual(draftPreview.collection.items.last?.status, .draft)
        XCTAssertEqual(draftPreview.collection.items.last?.slug, "item")
        XCTAssertEqual(draftPreview.summary, "Adds 1 item, updates 0, skips 0 rows, keeps 1 new item as drafts because a required field is empty.")
        let emptying = try CollectionImport.parseCSV("slug,title\nhello,\n")
        let refused = try CollectionImport.preview(emptying, mapping: CollectionImport.suggestedMapping(emptying, for: posts),
                                                   into: posts, collections: [authors], assets: [])
        XCTAssertEqual(refused.problems, [CollectionImportProblem(kind: .requiredMissing, row: 1)])
        XCTAssertEqual(refused.collection, posts)
        let copying = try CollectionImport.parseCSV("slug,title\nhello,Copy\n")
        var addOnly = CollectionImport.suggestedMapping(copying, for: posts)
        addOnly.updatesMatchingItems = false
        XCTAssertEqual(try CollectionImport.preview(copying, mapping: addOnly, into: posts, collections: [authors], assets: [])
            .collection.items.map(\.slug), ["hello", "hello-2"], "Without updates a matching address is made unique")

        // Mappings that no longer fit are refused and change nothing.
        var twice = mapping
        twice.fields[1] = title.id
        XCTAssertThrowsError(try CollectionImport.preview(table, mapping: twice, into: posts, collections: [], assets: [])) {
            XCTAssertEqual($0 as? CollectionImportError, .duplicateMapping)
        }
        var outside = mapping
        outside.fields = [9: price.id]
        XCTAssertThrowsError(try CollectionImport.validate(outside, table: table, collection: posts)) {
            XCTAssertEqual($0 as? CollectionImportError, .unknownMapping)
        }
        var withoutPrice = posts
        CollectionEditing.removeField(price.id, from: &withoutPrice)
        XCTAssertThrowsError(try CollectionImport.validate(mapping, table: table, collection: withoutPrice)) {
            XCTAssertEqual($0 as? CollectionImportError, .unknownMapping)
        }

        // Apply puts the editor draft into the document as one undoable change.
        var document = ProjectCreation.blank()
        document.imageAssets = [asset]
        document.collections = [authors, posts]
        try document.validate()
        let session = DocumentSession(document: document)
        var draft = document.collections
        draft[1] = preview.collection
        try session.execute(CollectionEditing.prepare(draft, openingRevision: document.revision, document: session.document,
                                                      isLifecycleAvailable: true))
        XCTAssertEqual(session.document.collections[1], preview.collection)
        XCTAssertEqual(session.historySnapshot().undoEntries.map(\.commandName), [.setCollections])
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = document.revision
        XCTAssertEqual(undone, document)
        try session.redo()
        XCTAssertEqual(session.document.collections[1], preview.collection)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        let diagnostic = CollectionImport.diagnostic("import", collection: posts.id, preview: preview, error: nil, startedAt: Date())
        XCTAssertEqual(diagnostic.requirementID, "SF-1005-002")
        XCTAssertEqual(diagnostic.collectionIdentifiers, [posts.id.description])
        XCTAssertEqual(diagnostic.itemCount, 2)
        XCTAssertEqual(diagnostic.failureCategory, "number")
        XCTAssertFalse(String(describing: diagnostic).contains("Hello"))
        XCTAssertFalse(String(describing: diagnostic).contains("Posts"))
        let failed = CollectionImport.diagnostic("import", collection: posts.id, preview: nil, error: .ragged(row: 2), startedAt: Date())
        XCTAssertEqual(failed.requirementID, "SF-1005-004")
        XCTAssertEqual(failed.failureCategory, "ragged")
        XCTAssertEqual(failed.itemCount, 0)
    }

    // SF-1005-001/004/007 (OD-037, ADR-0073): broken, oversized or ambiguous
    // files are refused with the line or row and nothing else; large files
    // stay bounded and fast.
    func testCollectionImportRefusesBrokenFilesAndStaysBounded() throws {
        func csvError(_ text: String) -> CollectionImportError? {
            do {
                _ = try CollectionImport.parseCSV(text)
                return nil
            } catch {
                return error as? CollectionImportError
            }
        }
        func dataError(_ data: Data, _ format: CollectionImportFormat) -> CollectionImportError? {
            do {
                _ = try CollectionImport.parse(data, format: format)
                return nil
            } catch {
                return error as? CollectionImportError
            }
        }
        XCTAssertEqual(csvError(""), .empty)
        XCTAssertEqual(csvError("title\n"), .empty, "A header without rows imports nothing")
        XCTAssertEqual(csvError("title,title\nA,B\n"), .header)
        XCTAssertEqual(csvError("Title,title\nA,B\n"), .header, "Column names are unique ignoring case")
        XCTAssertEqual(csvError("title,\nA,B\n"), .header)
        XCTAssertEqual(csvError("title,price\nA,1\nB\n"), .ragged(row: 2))
        XCTAssertEqual(csvError("title\n\"never closed\nstill open\n"), .unclosedQuote(line: 2))
        XCTAssertEqual(csvError("title\nab\"c\n"), .strayQuote(line: 2))
        XCTAssertEqual(csvError("title\n\"ab\"c\n"), .strayQuote(line: 2))
        XCTAssertEqual(CollectionImportError.ragged(row: 2).errorDescription,
                       "Row 2 has a different number of cells than the header row. Nothing changed.")
        XCTAssertEqual(try CollectionImport.parseCSV("title\rA\rB").rows, [["A"], ["B"]], "CR line ends and a missing last line end")
        XCTAssertEqual(try CollectionImport.parseCSV("a,b\n\"\",\"x,y\"\n1,\n").rows, [["", "x,y"], ["1", ""]])
        XCTAssertEqual(try CollectionImport.parse(Data([0xEF, 0xBB, 0xBF]) + Data("Title\nA\n".utf8), format: .csv).columns, ["Title"])

        XCTAssertEqual(dataError(Data(count: CollectionImportTable.maximumBytes + 1), .csv), .tooLarge)
        XCTAssertEqual(dataError(Data(count: CollectionImportTable.maximumBytes + 1), .json), .tooLarge)
        XCTAssertEqual(dataError(Data([0xFF, 0xFE, 0x41]), .csv), .notText)
        let wide = (0...CollectionImportTable.maximumColumns).map { "c\($0)" }.joined(separator: ",") + "\n"
            + Array(repeating: "x", count: CollectionImportTable.maximumColumns + 1).joined(separator: ",") + "\n"
        XCTAssertEqual(csvError(wide), .tooManyColumns)
        XCTAssertEqual(csvError("title\n" + String(repeating: "x\n", count: ContentCollection.maximumItems + 1)), .tooManyRows)

        XCTAssertEqual(dataError(Data(#"{"title":"x"}"#.utf8), .json), .json, "The top level must be an array")
        XCTAssertEqual(dataError(Data(#"[{"title":{"nested":1}}]"#.utf8), .json), .json)
        XCTAssertEqual(dataError(Data(#"[{"tags":["a"]}]"#.utf8), .json), .json)
        XCTAssertEqual(dataError(Data("[1, 2]".utf8), .json), .json)
        XCTAssertEqual(dataError(Data("not json".utf8), .json), .json)
        XCTAssertEqual(dataError(Data("[]".utf8), .json), .empty)
        XCTAssertEqual(dataError(Data(#"[{"Title":"a","title":"b"}]"#.utf8), .json), .header)
        XCTAssertEqual(try CollectionImport.parse(Data([0xEF, 0xBB, 0xBF]) + Data(#"[{"title":"A"}]"#.utf8), format: .json).columns,
                       ["title"])
        XCTAssertEqual(try CollectionImport.parse(Data(#"[{"n":1.5,"m":3,"b":false}]"#.utf8), format: .json).rows,
                       [["false", "3", "1.5"]])

        var posts = CollectionEditing.newCollection(in: [], name: "Posts")
        let price = try CollectionEditing.addField(label: "Price", type: .number, referencing: nil, to: &posts)
        let date = try CollectionEditing.addField(label: "Date", type: .date, referencing: nil, to: &posts)
        for spelling in ["inf", "nan", "0x10", "1,000", "12 kg", "1e400"] {
            let table = try CollectionImport.parseCSV("price\n\"\(spelling)\"\n")
            let checked = try CollectionImport.preview(table, mapping: CollectionImport.suggestedMapping(table, for: posts),
                                                       into: posts, collections: [], assets: [])
            XCTAssertEqual(checked.problems.map(\.kind), [.number], spelling)
        }

        // Every bad cell is checked, the problem list is bounded and a skipped row never claims its address.
        let badRows = "price,date,slug\n" + (0..<600).map { "x,y,row-\($0 % 2)" }.joined(separator: "\n") + "\n5,2026-01-01,row-0\n"
        let badTable = try CollectionImport.parseCSV(badRows)
        let bad = try CollectionImport.preview(badTable, mapping: CollectionImport.suggestedMapping(badTable, for: posts),
                                               into: posts, collections: [], assets: [])
        XCTAssertEqual(bad.skipped, 600)
        XCTAssertEqual(bad.problems.count, CollectionImportPreview.maximumProblems)
        XCTAssertEqual(bad.added, 1)
        XCTAssertEqual(bad.collection.items.last?.slug, "row-0")
        XCTAssertEqual(bad.collection.items.last?.value(for: price.id), .number(5))
        XCTAssertEqual(bad.collection.items.last?.value(for: date.id), .date(try XCTUnwrap(SiteExpressionDate(iso: "2026-01-01"))))

        // A full collection takes no new items.
        var full = posts
        full.items = (0..<ContentCollection.maximumItems).map { CollectionItem(slug: "item-\($0)") }
        let one = try CollectionImport.parseCSV("price\n1\n")
        let overflow = try CollectionImport.preview(one, mapping: CollectionImport.suggestedMapping(one, for: full),
                                                    into: full, collections: [], assets: [])
        XCTAssertEqual(overflow.problems.map(\.kind), [.tooManyItems])
        XCTAssertEqual(overflow.collection.items.count, ContentCollection.maximumItems)

        // Large fixture: 10,000 rows with one title stay linear and get unique addresses.
        let large = "Title,Price\n" + (0..<ContentCollection.maximumItems).map { "Same title,\($0)" }.joined(separator: "\n")
        let started = Date()
        let largeTable = try CollectionImport.parse(Data(large.utf8), format: .csv)
        let largePreview = try CollectionImport.preview(largeTable, mapping: CollectionImport.suggestedMapping(largeTable, for: posts),
                                                        into: posts, collections: [], assets: [])
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertEqual(largePreview.added, ContentCollection.maximumItems)
        XCTAssertEqual(Set(largePreview.collection.items.map(\.slug)).count, ContentCollection.maximumItems)
        XCTAssertEqual(largePreview.collection.items[1].slug, "same-title-2")
        XCTAssertEqual(CanonicalCollections.issues([largePreview.collection]), [])
    }

    // SF-1005-002/003/004/005/008 (OD-037, ADR-0074): the Import tab's steps —
    // read the chosen file, choose what each column fills, preview, add to
    // the draft only while the preview is current, then Apply as one
    // undoable change.
    func testCollectionImportTabReadsAFileMapsColumnsAndAddsToTheDraftAsOneUndoableChange() throws {
        var posts = CollectionEditing.newCollection(in: [], name: "Posts")
        let title = try XCTUnwrap(posts.fields.first)
        let price = try CollectionEditing.addField(label: "Price", type: .number, referencing: nil, to: &posts)
        var hello = CollectionItem(slug: "hello", status: .published)
        hello.setValue(.text("Hello"), for: title.id)
        posts.items = [hello]

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("collection-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let csvURL = folder.appendingPathComponent("Posts.CSV")
        try Data("Headline,Cost,Slug\nSpring Sale,1.5e3,\nSpring Sale,2,spring-sale\nHello again,3,hello\n".utf8).write(to: csvURL)

        XCTAssertEqual(CollectionImportFormat(fileExtension: "CSV"), .csv, "Extensions match ignoring case")
        XCTAssertEqual(CollectionImportFormat(fileExtension: "json"), .json)
        XCTAssertNil(CollectionImportFormat(fileExtension: "txt"))
        let table = try CollectionImport.read(csvURL)
        XCTAssertEqual(table.columns, ["Headline", "Cost", "Slug"])
        XCTAssertEqual(table.example(column: 0), "Spring Sale")
        XCTAssertEqual(table.example(column: 2), "spring-sale", "Empty cells are passed over")
        XCTAssertNil(table.example(column: 9))

        var mapping = CollectionImport.suggestedMapping(table, for: posts)
        XCTAssertEqual(mapping.fields, [:], "Headline and Cost match no field name or label")
        XCTAssertEqual(mapping.slugColumn, 2)
        XCTAssertEqual(mapping.target(ofColumn: 2), .address)
        XCTAssertEqual(mapping.target(ofColumn: 0), .skip)
        mapping.assign(.field(title.id), toColumn: 0)
        mapping.assign(.field(price.id), toColumn: 1)
        XCTAssertEqual(mapping.target(ofColumn: 1), .field(price.id))
        var moved = mapping
        moved.assign(.field(title.id), toColumn: 1)
        XCTAssertEqual(moved.fields, [1: title.id], "Choosing a field for one column takes it from the other")
        moved.assign(.address, toColumn: 0)
        XCTAssertEqual(moved.slugColumn, 0, "There is one address column")
        moved.assign(.skip, toColumn: 0)
        XCTAssertNil(moved.slugColumn)
        XCTAssertNoThrow(try CollectionImport.validate(moved, table: table, collection: posts))

        let preview = try CollectionImport.preview(table, mapping: mapping, into: posts, collections: [posts], assets: [])
        XCTAssertEqual([preview.added, preview.updated, preview.skipped], [1, 1, 1])
        XCTAssertEqual(preview.problems, [CollectionImportProblem(kind: .duplicateSlug, row: 2, column: 2)],
                       "An address made from a title is claimed, so a later row naming it never updates the new item")
        XCTAssertEqual(preview.collection.items.map(\.slug), ["hello", "spring-sale"])
        XCTAssertEqual(preview.collection.items.last?.value(for: price.id), .number(1_500))
        XCTAssertEqual(preview.collection.items.first?.value(for: title.id), .text("Hello again"))
        XCTAssertEqual(preview.collection.items.first?.id, hello.id)

        // Add to Draft replaces the collection only while the preview is current.
        let draft = try CollectionImport.merge(preview, base: posts, into: [posts])
        XCTAssertEqual(draft, [preview.collection])
        var edited = posts
        edited.name = "Edited Posts"
        XCTAssertThrowsError(try CollectionImport.merge(preview, base: posts, into: [edited])) {
            XCTAssertEqual($0 as? CollectionImportError, .stale, "A preview made before later edits is never added")
        }
        XCTAssertThrowsError(try CollectionImport.merge(preview, base: posts, into: [])) {
            XCTAssertEqual($0 as? CollectionImportError, .stale)
        }

        // Apply commits the draft as one undoable change that survives reopening.
        var document = ProjectCreation.blank()
        document.collections = [posts]
        try document.validate()
        let session = DocumentSession(document: document)
        try session.execute(CollectionEditing.prepare(draft, openingRevision: document.revision, document: session.document,
                                                      isLifecycleAvailable: true))
        XCTAssertEqual(session.document.collections, draft)
        XCTAssertEqual(session.historySnapshot().undoEntries.map(\.commandName), [.setCollections])
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = document.revision
        XCTAssertEqual(undone, document)
        try session.redo()
        XCTAssertEqual(session.document.collections, draft)
        XCTAssertEqual(try DocumentSerializer.decode(DocumentSerializer.encode(session.document)), session.document)

        // Reading refuses other files without changing anything or naming the path.
        let jsonURL = folder.appendingPathComponent("posts.json")
        try Data(#"[{"title":"From JSON"}]"#.utf8).write(to: jsonURL)
        XCTAssertEqual(try CollectionImport.read(jsonURL).rows, [["From JSON"]])
        func readError(_ url: URL) -> CollectionImportError? {
            do {
                _ = try CollectionImport.read(url)
                return nil
            } catch {
                return error as? CollectionImportError
            }
        }
        let notes = folder.appendingPathComponent("notes.txt")
        try Data("title\nA\n".utf8).write(to: notes)
        XCTAssertEqual(readError(notes), .unsupportedFormat)
        XCTAssertEqual(readError(folder.appendingPathComponent("missing.csv")), .unreadable)
        let large = folder.appendingPathComponent("large.csv")
        try Data(count: CollectionImportTable.maximumBytes + 1).write(to: large)
        XCTAssertEqual(readError(large), .tooLarge, "The size is checked before the file is read")
        for error in [CollectionImportError.unreadable, .unsupportedFormat, .stale] {
            XCTAssertFalse(error.errorDescription?.contains(folder.path) ?? true, "Messages never name paths")
        }
        XCTAssertEqual([CollectionImportError.unreadable, .unsupportedFormat, .stale].map(\.category),
                       ["unreadable", "unsupported-format", "stale"])

        // Number cells and the editor's number fields share one rule, which
        // accepts every form the editor shows.
        XCTAssertEqual(CollectionImport.parseNumber(" 1.5e3 "), 1_500)
        XCTAssertEqual(CollectionImport.parseNumber(SiteExpressionEngine.numberText(1e20)), 1e20)
        XCTAssertNil(CollectionImport.parseNumber("1,5"))
        XCTAssertNil(CollectionImport.parseNumber(""))

        let diagnostic = CollectionImport.diagnostic("import", collection: posts.id, preview: preview, error: nil, startedAt: Date())
        XCTAssertEqual(diagnostic.requirementID, "SF-1005-002")
        XCTAssertEqual(diagnostic.itemCount, 2)
        XCTAssertEqual(diagnostic.failureCategory, "duplicateSlug")
        XCTAssertFalse(String(describing: diagnostic).contains("Spring"))
        let readFailure = CollectionImport.diagnostic("import-read", collection: posts.id, preview: nil, error: .unreadable,
                                                      startedAt: Date())
        XCTAssertEqual(readFailure.requirementID, "SF-1005-004")
        XCTAssertEqual(readFailure.failureCategory, "unreadable")
    }

    // SF-1004-003 (OD-036): the expression preview explains which rule won
    // for the previewed item, each reason once.
    func testCollectionExpressionPreviewExplainsWhichRuleWonForTheFirstItem() throws {
        var posts = CollectionEditing.newCollection(in: [], name: "Posts")
        let title = try XCTUnwrap(posts.fields.first)
        _ = try CollectionEditing.addField(label: "Price", type: .number, referencing: nil, to: &posts)
        XCTAssertEqual(CollectionEditing.templatePreviewExplanation("title", collection: posts, collections: [posts]), [],
                       "Nothing to explain without an item")
        var hello = CollectionItem(slug: "hello", status: .published)
        hello.setValue(.text("Hello"), for: title.id)
        posts.items = [hello]

        let condition = "if(price > 10, \"big\", \"small\")"
        XCTAssertEqual(CollectionEditing.templatePreview(condition, collection: posts, collections: [posts]).text, "small")
        XCTAssertEqual(CollectionEditing.templatePreviewExplanation(condition, collection: posts, collections: [posts]),
                       ["The field \u{201C}price\u{201D} has no value.",
                        "if(\u{2026}): the condition is false or missing, so the second result is used."])
        XCTAssertEqual(CollectionEditing.templatePreviewExplanation("title ?? \"Untitled\"", collection: posts, collections: [posts]),
                       ["The first value is present, so the fallback is not used."])
        XCTAssertEqual(CollectionEditing.templatePreviewExplanation("price ?? 0 + (price ?? 1)", collection: posts,
                                                                    collections: [posts]).filter { $0.contains("price") }.count, 1,
                       "A missing field is explained once")
        XCTAssertEqual(CollectionEditing.templatePreviewExplanation("", collection: posts, collections: [posts]), [])
        XCTAssertEqual(CollectionEditing.templatePreviewExplanation("upper(", collection: posts, collections: [posts]), [],
                       "An unusable expression is explained by the preview's error instead")

        // SF-1004-006: the editor marks where an unusable expression goes wrong.
        let misspelled = try XCTUnwrap(CollectionEditing.templatePreviewProblem("upper(titel)", collection: posts, collections: [posts]))
        XCTAssertEqual(misspelled.range, 6..<11)
        XCTAssertEqual(misspelled.place, "at characters 7 to 11")
        XCTAssertEqual(misspelled.suggestion, "Choose a field from the list of available fields.")
        let unfinished = try XCTUnwrap(CollectionEditing.templatePreviewProblem("upper(", collection: posts, collections: [posts]))
        XCTAssertEqual(unfinished.range, 6..<6)
        XCTAssertEqual(unfinished.place, "at the end")
        XCTAssertNil(CollectionEditing.templatePreviewProblem("upper(title)", collection: posts, collections: [posts]))
        XCTAssertNil(CollectionEditing.templatePreviewProblem(" ", collection: posts, collections: [posts]))
    }

    // SF-1003-003/007 (OD-035): list resolution — filter, order, pages — stays
    // linear and deterministic for the 10,000-item large fixture.
    func testCollectionListResolutionStaysFastAndOrderedForTenThousandItems() throws {
        var posts = CollectionEditing.newCollection(in: [], name: "Posts")
        let title = try XCTUnwrap(posts.fields.first)
        let price = try CollectionEditing.addField(label: "Price", type: .number, referencing: nil, to: &posts)
        posts.items = (0..<ContentCollection.maximumItems).map { index in
            var item = CollectionItem(slug: "item-\(index)", status: .published)
            item.setValue(.text("Item \(index)"), for: title.id)
            item.setValue(.number(Double(index % 1_000)), for: price.id)
            return item
        }
        XCTAssertEqual(CanonicalCollections.issues([posts]), [])
        let list = CollectionList(pageID: PageID(), repeatedNodeID: NodeID(), filter: SiteExpression(source: "price >= 500"),
                                  sortFieldID: price.id, sortDirection: .descending, pageSize: 100)
        let started = Date()
        let resolution = CollectionEditing.listPreview(list, collection: posts, collections: [posts])
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
        XCTAssertEqual(resolution.matchingCount, 5_000)
        XCTAssertEqual(resolution.pageCount, 50)
        XCTAssertEqual(resolution.items.first?.value(for: price.id), .number(999))
        XCTAssertEqual(resolution.items.first?.slug, "item-999", "Ties keep the Items order")
        XCTAssertEqual(resolution.items.last?.value(for: price.id), .number(500))
        XCTAssertEqual(resolution.items(onPage: 50).count, 100)
        XCTAssertEqual(resolution.items(onPage: 51), [])
        XCTAssertEqual(resolution.summary, "Shows 5000 of 10000 published items on 50 pages.")
    }

    // SF-1107-001/002/004/005 (OD-041): custom code is website metadata
    // version 3 — strict, schema-27 gated, one undoable transaction, removed
    // with its page, and version 2 records still open.
    func testCustomCodeIsStrictVersionedSchemaGatedUndoableAndRemovedWithItsPage() throws {
        XCTAssertNil(CustomCodeBlock.make(headHTML: " \n", bodyHTML: "", css: "\t"))
        let site = try XCTUnwrap(CustomCodeBlock.make(headHTML: "<meta name=\"x\" content=\"1\">", bodyHTML: "", css: "  .a { color: red; }  "))
        XCTAssertEqual(site.css, "  .a { color: red; }  ", "Code is kept exactly as typed")
        XCTAssertNil(site.bodyHTML)
        XCTAssertTrue(site.isValid); XCTAssertFalse(site.containsScript)
        XCTAssertTrue(CustomCodeBlock(bodyHTML: "<script src=\"a.js\"></script>").containsScript)
        XCTAssertTrue(CustomCodeBlock(headHTML: "<a href=\"#\" onclick=\"x()\">a</a>").containsScript)
        XCTAssertTrue(CustomCodeBlock(bodyHTML: "<a href=\"javascript:void(0)\">a</a>").containsScript)
        for invalid in [CustomCodeBlock(), CustomCodeBlock(headHTML: "</head><body>"), CustomCodeBlock(headHTML: "<BODY>"),
                        CustomCodeBlock(bodyHTML: "</body>"), CustomCodeBlock(css: "a{} </STYLE><script>"),
                        CustomCodeBlock(css: "   "), CustomCodeBlock(css: "a\u{0}b"),
                        CustomCodeBlock(headHTML: String(repeating: "a", count: CustomCodeBlock.maximumBytes + 1))] {
            XCTAssertFalse(invalid.isValid, "\(invalid)")
        }
        XCTAssertTrue(CustomCodeBlock(css: String(repeating: "a", count: CustomCodeBlock.maximumBytes)).isValid)

        var document = ProjectCreation.blank()
        let about = DocumentPage(name: "About", route: .init(rawValue: "/about"))
        document.pages.append(about)
        let session = DocumentSession(document: document)
        let pageCode = CustomCodeBlock(bodyHTML: "<div id=\"chat\"></div>")
        let metadata = WebsiteMetadata(siteName: "Studio",
            pages: [PageWebsiteMetadata(pageID: about.id, customCode: pageCode)], customCode: site)
        XCTAssertTrue(metadata.usesCustomCode); XCTAssertFalse(metadata.usesSocialFields)
        let before = session.document
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id, metadata: metadata)))
        XCTAssertEqual(session.document.websiteMetadata, metadata)
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = before.revision
        XCTAssertEqual(undone, before)
        try session.redo(); XCTAssertEqual(session.document.websiteMetadata, metadata)

        let reopened = try DocumentSerializer.decode(DocumentSerializer.encode(session.document))
        XCTAssertEqual(reopened.websiteMetadata, metadata)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: DocumentSerializer.encode(session.document)) as? [String: Any])
        envelope["schemaVersion"] = 26
        XCTAssertThrowsError(try DocumentSerializer.decode(JSONSerialization.data(withJSONObject: envelope)), "Needs schema 27")

        let encoded = try JSONEncoder().encode(metadata)
        let forgeries: [(String, (inout [String: Any]) -> Void)] = [
            ("version 2 with custom code key", { $0["version"] = 2 }),
            ("page code inside a version 2 record", { object in
                object["version"] = 2; object.removeValue(forKey: "customCode") }),
            ("null page code", { object in
                var pages = object["pages"] as? [[String: Any]] ?? []; pages[0]["customCode"] = NSNull(); object["pages"] = pages }),
            ("unknown custom code key", { object in
                var code = object["customCode"] as? [String: Any] ?? [:]; code["javascript"] = "x"; object["customCode"] = code }),
            ("closing tag", { object in
                var code = object["customCode"] as? [String: Any] ?? [:]; code["css"] = "</style>"; object["customCode"] = code }),
        ]
        for (label, change) in forgeries {
            var forged = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
            change(&forged)
            XCTAssertThrowsError(try JSONDecoder().decode(WebsiteMetadata.self, from: JSONSerialization.data(withJSONObject: forged)), label)
        }
        // A version 2 record (no custom code anywhere) still opens as version 3.
        var versionTwo = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(
            WebsiteMetadata(siteName: "Studio", pages: [PageWebsiteMetadata(pageID: about.id, title: "About us")]))) as? [String: Any])
        versionTwo["version"] = 2
        versionTwo.removeValue(forKey: "customCode")
        XCTAssertEqual(try JSONDecoder().decode(WebsiteMetadata.self, from: JSONSerialization.data(withJSONObject: versionTwo)),
                       WebsiteMetadata(siteName: "Studio", pages: [PageWebsiteMetadata(pageID: about.id, title: "About us")]))

        // Removing the page removes its code in the same undoable step.
        try session.execute(.removePage(.init(pageID: about.id)))
        XCTAssertEqual(session.document.websiteMetadata?.pages, [])
        XCTAssertEqual(session.document.websiteMetadata?.customCode, site)
        try session.undo()
        XCTAssertEqual(session.document.websiteMetadata, metadata)
    }

    // SF-1107-005 (OD-041, ADR-0145): duplicating a page copies its custom code
    // in the same undoable step, so the copy builds like the original.
    func testCustomCodeIsCopiedWithADuplicatedPageInOneUndoableStep() throws {
        var document = ProjectCreation.blank()
        let about = DocumentPage(name: "About", route: .init(rawValue: "/about"))
        document.pages.append(about)
        let session = DocumentSession(document: document)
        let pageCode = CustomCodeBlock(headHTML: "<meta name=\"robots\" content=\"noarchive\">", css: ".about { margin: 0; }")
        try session.execute(.setWebsiteMetadata(.init(documentID: session.document.id,
            metadata: WebsiteMetadata(siteName: "Studio", pages: [PageWebsiteMetadata(pageID: about.id, customCode: pageCode)]))))
        let before = session.document
        let prepared = try PageCommandRegistry().prepare(.duplicateNamed(name: "About Copy", route: "/about-copy"),
            identity: .init(documentID: before.id, revision: before.revision, pageID: about.id),
            in: before, isAvailable: true)
        try session.execute(prepared.command)
        let copyID = prepared.selectedPageID
        XCTAssertNotEqual(copyID, about.id)
        let pages = try XCTUnwrap(session.document.websiteMetadata?.pages)
        XCTAssertEqual(pages.first { $0.pageID == copyID }?.customCode, pageCode)
        XCTAssertEqual(pages.first { $0.pageID == about.id }?.customCode, pageCode)
        // Undo commits a new revision, so compare everything else.
        try session.undo()
        var undone = session.document; undone.revision = before.revision
        XCTAssertEqual(undone, before)
        try session.redo()
        XCTAssertEqual(session.document.websiteMetadata?.pages.first { $0.pageID == copyID }?.customCode, pageCode)
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

    // SF-0206-005: project preferences survive save, reopen and recovery with
    // their history; history v4 owns the command and an older envelope cannot
    // carry it.
    func testProjectPreferencesSaveReopenRecoveryAndPersistedHistorySchema() async throws {
        let url = fixtureDirectory.appendingPathComponent("Preferences.siteforge")
        let debouncer = ManualLifecycleAutosaveDebouncer()
        let writer = makeController(autosaveDebouncer: debouncer)
        func edit(_ session: DocumentSession, _ change: ProjectPreferencesEdit) throws {
            try session.execute(ProjectPreferencesCommandRegistry().prepare(change,
                expectedDocumentID: session.document.id, expectedRevision: session.document.revision,
                document: session.document, isLifecycleAvailable: true))
        }
        try edit(writer.session, .replace(.init(gridVisibleOnOpen: false)))
        try edit(writer.session, .gridSpacing(24))
        let first = writer.session.document.projectPreferences
        let saved = await writer.save(to: url)
        XCTAssertTrue(saved)
        let reader = makeController()
        let opened = await reader.requestOpen(url)
        XCTAssertEqual(opened, .completed)
        XCTAssertEqual(reader.session.document.projectPreferences, first)
        XCTAssertNil(reader.historyNotice)
        try reader.session.undo()
        XCTAssertEqual(reader.session.document.projectPreferences, .init(gridVisibleOnOpen: false))
        try reader.session.redo()
        XCTAssertEqual(reader.session.document.projectPreferences, first)

        try edit(writer.session, .resetAll)
        await flushAutosave(writer, with: debouncer)
        let recoveryReader = makeController()
        let recoveryOpen = await recoveryReader.requestOpen(url)
        XCTAssertEqual(recoveryOpen, .completed)
        XCTAssertNotNil(recoveryReader.recoveryCandidate)
        let restored = await recoveryReader.requestRestoreRecovery()
        XCTAssertEqual(restored, .completed)
        XCTAssertNil(recoveryReader.session.document.projectPreferences)
        try recoveryReader.session.undo()
        XCTAssertEqual(recoveryReader.session.document.projectPreferences, first)

        let store = PersistedHistoryStore()
        let data = try await store.encodeRetained(writer.session.historySnapshot())
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["schemaVersion"] as? Int, PersistedHistorySnapshot.currentSchemaVersion)
        XCTAssertEqual(PersistedHistorySnapshot.currentSchemaVersion, 4)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"setProjectPreferences\""))
        let current = try await store.load(from: ProjectPackage(document: writer.session.document,
            optionalMembers: [.init(path: PersistedHistoryStore.memberPath, data: data)]))
        guard case .restored(let snapshot) = current else { return XCTFail("Current history must restore: \(current)") }
        XCTAssertEqual(snapshot.undoEntries.map(\.commandName),
                       [.setProjectPreferences, .setProjectPreferences, .setProjectPreferences])
        let relabeled = try mutate(data) { $0["schemaVersion"] = 3 }
        let rejected = try await store.load(from: ProjectPackage(document: writer.session.document,
            optionalMembers: [.init(path: PersistedHistoryStore.memberPath, data: relabeled)]))
        XCTAssertEqual(rejected, .cleanBaseline(.corrupt))

        // Migration: an existing v3 history without preference commands still
        // restores, upgraded to the current schema.
        let legacy = DocumentSession()
        try legacy.execute(.setWebsiteMetadata(.init(documentID: legacy.document.id, metadata: .init(siteName: "Aurora"))))
        let legacyCurrent = try await store.encodeRetained(legacy.historySnapshot())
        let legacyData = try mutate(legacyCurrent) { $0["schemaVersion"] = 3 }
        let migrated = try await store.load(from: ProjectPackage(document: legacy.document,
            optionalMembers: [.init(path: PersistedHistoryStore.memberPath, data: legacyData)]))
        guard case .restored(let upgraded) = migrated else { return XCTFail("A v3 history must migrate: \(migrated)") }
        XCTAssertEqual(upgraded.schemaVersion, PersistedHistorySnapshot.currentSchemaVersion)
        XCTAssertEqual(upgraded.undoEntries.map(\.commandName), [.setWebsiteMetadata])
    }

    // SF-0206-005/007, SF-0206-004: preferences add a bounded number of bytes
    // and round-trip at the large fixture. At the stress fixture the outcome
    // follows the package file limit (OD-032, ADR-0030: package v2 splits pages
    // into bounded members; the 8 MiB file cap of ADR-0001/ADR-0012 remains):
    // within it the project round-trips; above it the save is refused before
    // any write and the last saved project, preferences included, is unchanged.
    func testProjectPreferencesPersistAtLargeFixtureAndRespectPackageLimitAtStress() async throws {
        let url = fixtureDirectory.appendingPathComponent("Scale.siteforge")
        let store = ProjectPackageStore()
        var large = WorkspaceFixtureScale.large.document()
        let bare = try DocumentSerializer.encode(large).count
        large.projectPreferences = .init(gridVisibleOnOpen: false, gridSpacing: 24)
        let preferred = try DocumentSerializer.encode(large).count
        XCTAssertGreaterThan(preferred, bare)
        XCTAssertLessThan(preferred - bare, 128, "Project preferences add a small constant, independent of project size")
        XCTAssertLessThanOrEqual(preferred, ProjectPackageStore.maximumMemberBytes)
        try await store.write(ProjectPackage(document: large), to: url)
        let reopened = try await store.readSnapshot(from: url)
        XCTAssertEqual(reopened.package.document.projectPreferences, large.projectPreferences)
        XCTAssertEqual(reopened.package.document.pages.count, WorkspaceFixtureScale.large.pageCount)
        let lastSaved = try Data(contentsOf: url)

        var stress = WorkspaceFixtureScale.stress.document()
        stress.projectPreferences = .init(gridSpacing: 32)
        let stressBytes = try DocumentSerializer.encode(stress).count
        XCTAssertGreaterThan(stressBytes, ProjectPackageStore.maximumMemberBytes, "Stress needs package v2")
        let fits = (try? await store.encode(ProjectPackage(document: stress))) != nil
        if !fits {
            do {
                try await store.write(ProjectPackage(document: stress), to: url, expected: reopened.file.fingerprint)
                XCTFail("A document above the package file cap must not be written")
            } catch let error as ProjectPackageError {
                XCTAssertEqual(error, .oversizedInput)
            }
            XCTAssertEqual(try Data(contentsOf: url), lastSaved, "The last saved project is byte-for-byte unchanged")
            let retained = try await store.read(from: url)
            XCTAssertEqual(retained.document.projectPreferences, large.projectPreferences)
        } else {
            try await store.write(ProjectPackage(document: stress), to: url, expected: reopened.file.fingerprint)
            let stressReopened = try await store.read(from: url)
            XCTAssertEqual(stressReopened.document.projectPreferences, stress.projectPreferences)
            XCTAssertEqual(stressReopened.document.pages.count, WorkspaceFixtureScale.stress.pageCount)
        }
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

    /// OD-038 part 2: a page with one heading ("Hello") and one picture
    /// (alternative text "Cover") plus a second asset to translate the picture to.
    private func siteTranslationFixture() throws -> (document: CanonicalDocument, pageID: PageID, headingID: NodeID,
                                                     pictureID: NodeID, translated: ImageAsset) {
        func translationLayout(_ width: Double, _ height: Double) -> [NodeProperty] {
            [("layout.x", 0.0), ("layout.y", 0.0), ("layout.width", width), ("layout.height", height)].map {
                NodeProperty(key: .init(rawValue: $0.0), value: .number($0.1), origin: .defaulted)
            }
        }
        func translationAsset(_ character: Character) -> ImageAsset {
            ImageAsset(resourceID: ResourceID(), displayName: "Picture", originalFilename: "picture.png",
                       format: .png, pixelWidth: 20, pixelHeight: 10, byteCount: 1,
                       contentHash: String(repeating: character, count: 64))
        }
        let original = translationAsset("a"), translated = translationAsset("b")
        let pageID = PageID(), headingID = NodeID(), pictureID = NodeID()
        let heading = DocumentNode(id: headingID, kind: .text, name: "Heading", parent: .page(pageID),
            properties: translationLayout(200, 40) + [.init(key: .init(rawValue: "content.text"), value: .string("Hello"))])
        let picture = DocumentNode(id: pictureID, kind: .image, name: "Picture", parent: .page(pageID),
                                   properties: translationLayout(20, 10) + [
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "assetID"), value: .string(original.id.description), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "fit"), value: .string(ImageFitMode.fit.rawValue), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.x"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "focal.y"), value: .number(0.5), origin: .defaulted),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "alt"), value: .string("Cover"), origin: .authored),
            .init(key: .init(rawValue: CanonicalImageStyle.namespace + "decorative"), value: .boolean(false), origin: .defaulted),
        ])
        var document = ProjectCreation.blank()
        document.pages.append(DocumentPage(id: pageID, name: "Post", route: .init(rawValue: "/post"),
                                           rootNodeIDs: [headingID, pictureID], nodes: [heading, picture]))
        document.imageAssets = [original, translated]
        try document.validate()
        return (document, pageID, headingID, pictureID, translated)
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
